// Copyright 2020 Intel Corporation.
//
// THIS SOFTWARE MAY CONTAIN PREPRODUCTION CODE AND IS PROVIDED BY THE
// COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED
// WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
// MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
// DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR
// BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
// WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
// OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
// EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <regex>
#include <map>

#define CL_VERSION_2_0
#include "CL/opencl.h"

#include "AOCLUtils/aocl_utils.h"
#include "aocl_mmd.h"

using namespace aocl_utils;

#define shared_alloc

static const size_t V = 16;
static size_t vectorSize = 1024 * 1024 * 256L;

bool use_prealloc_svm_buffer = true;

float bw;
// 0 - runall, 2 memcopy , 3 read, 4 write
int runkernel = 0;

// ACL runtime configuration
static cl_platform_id platform;
static cl_device_id device;
static cl_context context;
static cl_command_queue queue;
static cl_kernel kernel;
static cl_kernel kernel2;
static cl_kernel kernel_read;
static cl_kernel kernel_write;

static cl_program program;
static cl_int status;

#define BACK_BUFFER 0
#define ACL_ALIGNMENT 1024 * 1024 * 2L 
const char *board_name;

std::string mb_get_board_name(cl_device_id device_id) {

#ifndef SIM
  std::string full_name = aocl_utils::getDeviceName(device_id);
// Regex implementation in gcc 4.8 is buggy.  Code compiles but does not work see:
// https://stackoverflow.com/questions/12530406/is-gcc-4-8-or-earlier-buggy-about-regular-expressions
#if defined(__clang__) or defined(__GNUC__) && (__GNUC__ > 4 || __GNUC__ == 4 && __GNUC_MINOR__ > 8)

  // Example of name is: 'dcp_s10 : Intel OFS Platform (ofs_eb00000)'
  // use regex to find 'ofs_...'
  std::regex board_regex(R"X(\((ofs_[0-9a-f]+)\))X");
  std::smatch board_match;
  std::string board_name;
  if (std::regex_search(full_name, board_match, board_regex)) {
    if (board_match.size() == 2 && board_match.ready()) {
      return board_match[1];
    }
  }
// Use string find for gcc 4.8 with broken regex
#else

  // Example of name is: 'dcp_s10 : Intel OFS Platform (ofs_eb00000)'
  // search by looking for 'ofs_' followed by 7 characters
  auto pos = full_name.find("(ofs_");
  if (pos != std::string::npos) {
    return full_name.substr(pos+1, 11);
  }
#endif
  throw std::runtime_error("Error parsing board name '" + full_name + "'");
#else
    //hardcoding the device-name for simulation
    return "ofs_a53a53";
#endif
}


void *acl_aligned_malloc(size_t size)
{
  void *result = NULL;
  posix_memalign(&result, ACL_ALIGNMENT, size);
  return result;
}
void acl_aligned_free(void *ptr) { free(ptr); }

static bool device_has_svm(cl_device_id device)
{
  cl_device_svm_capabilities a;
  clGetDeviceInfo(device, CL_DEVICE_SVM_CAPABILITIES, sizeof(cl_uint), &a,
                  NULL);

  if (a & CL_DEVICE_SVM_COARSE_GRAIN_BUFFER) return true; //would like to understand if condition better

  return false;
}

void *alloc_fpga_host_buffer(cl_context &in_context, int some_int, int size,
                             int some_int2);
cl_int set_fpga_buffer_kernel_param(cl_kernel &kernel, int param, void *ptr);

cl_int enqueue_fpga_buffer(cl_command_queue queue, cl_bool blocking,
                           cl_map_flags flags, void *ptr, size_t len,
                           cl_uint num_events, const cl_event *events,
                           cl_event *the_event);
cl_int unenqueue_fpga_buffer(cl_command_queue queue, void *ptr,
                             cl_uint num_events, const cl_event *events,
                             cl_event *the_event);
void remove_fpga_buffer(cl_context &context, void *ptr);

// input and output vectors
static unsigned *hdatain, *hdataout, *hdatatemp;

cl_mem hdata_ddr1, hdata_ddr2;

static void initializeVector(unsigned *vector, int size)
{
  for (int i = 0; i < size; ++i) {
    vector[i] = 0x32103210;
  }
}
static void initializeVector_seq(unsigned *vector, int size)
{
  for (int i = 0; i < size; ++i) {
    vector[i] = i;
  }
}

static void dump_error(const char *str, cl_int status)
{
  printf("%s\n", str);
  printf("Error code: %d\n", status);
}

// free the resources allocated during initialization
static void freeResources()
{
  if (kernel) clReleaseKernel(kernel);
  if (kernel_read) clReleaseKernel(kernel_read);
  if (kernel_write) clReleaseKernel(kernel_write);
  if (program) clReleaseProgram(program);
  if (queue) clReleaseCommandQueue(queue);
  if (hdatain) remove_fpga_buffer(context, hdatain);
  if (hdataout) remove_fpga_buffer(context, hdataout);
  free(hdatatemp);
  if (context) clReleaseContext(context);
  if (board_name) { 
    free((char *)board_name); 
  }
}

//---------------------
//alloc_fpga_host_buffer
//---------------------
#ifdef shared_alloc
void *alloc_fpga_host_buffer(cl_context &in_context, int some_int, int size,
                             int some_int2)
{
  if (use_prealloc_svm_buffer) {
    printf("Info: Using preallocated host buffer and custom MPF calls!\n");
    size_t bump = size % ACL_ALIGNMENT
                      ? (1 + (size / ACL_ALIGNMENT)) * ACL_ALIGNMENT
                      : size;
    bump = bump + BACK_BUFFER;
    printf("bump = %ld \n", bump);
    printf("vectorsize = %ld\n", vectorSize);
    printf("ACL_ALIGNMENT = %ld\n", ACL_ALIGNMENT);
    printf("working board_name = %s\n",board_name);
    
    int handle = aocl_mmd_open(board_name);
    aocl_mmd_mem_properties_t properties = AOCL_MMD_MEM_PROPERTIES_GLOBAL_MEMORY; 
    int error;
    void *ptr  = aocl_mmd_shared_alloc(handle, bump, ACL_ALIGNMENT, &properties, &error);
    if(error != 0) {
      printf("ERROR CODE %d\n", error);
    }

    aocl_mmd_migrate_t mig = AOCL_MMD_MIGRATE_TO_HOST;
    int ret_val = aocl_mmd_shared_migrate(handle,(ptr),4096,mig);   
    printf("aocl_mmd_shared_migrate ret val = %d\n", ret_val);

    return ptr;
  }
  else {
    printf("Info: Using clSVMAllocIntelFPGA");
    return clSVMAlloc(in_context, some_int, size, some_int2);
  }
}

//---------------------
//alloc_fpga_host_buffer
//---------------------
#else
void *alloc_fpga_host_buffer(cl_context &in_context, int some_int, int size,
                             int some_int2)
{
  if (use_prealloc_svm_buffer) {
    printf("Info: Using aocl_mmd_host_alloc()!\n");
    size_t bump = size % ACL_ALIGNMENT
                      ? (1 + (size / ACL_ALIGNMENT)) * ACL_ALIGNMENT
                      : size;
    bump = bump + BACK_BUFFER;
    printf("bump = %ld \n", bump);
    printf("vectorsize = %ld\n", vectorSize);
    printf("ACL_ALIGNMENT = %ld\n", ACL_ALIGNMENT);
    printf("working board name %s\n",board_name);
    int handle = aocl_mmd_open(board_name);   
    int num_devices = 1;
    aocl_mmd_mem_properties_t properties = AOCL_MMD_MEM_PROPERTIES_MEMORY_BANK; 
    printf("properties = %d &properties = %p\n",properties, &properties);
    int error;
    void *ptr  = aocl_mmd_host_alloc(&handle, num_devices, bump, ACL_ALIGNMENT, &properties, &error);
    printf("ERROR CODE %d\n", error);

    aocl_mmd_migrate_t mig = AOCL_MMD_MIGRATE_TO_HOST;
    int ret_val = aocl_mmd_shared_migrate(handle,(ptr),4096,mig);   
    printf("aocl_mmd_shared_migrate ret val = %d\n", ret_val);
    return ptr;
  }
  else {
    printf("Info: Using clSVMAllocIntelFPGA");
    return clSVMAlloc(in_context, some_int, size, some_int2);
  }

}

//---------------------
//---------------------
#endif

//---------------------
//set_fpga_buffer_kernel_param
//---------------------
cl_int set_fpga_buffer_kernel_param(cl_kernel &kernel, int param, void *ptr)
{
  return clSetKernelArgSVMPointer(kernel, param, (void *)ptr);
}
//---------------------
//---------------------

//---------------------
//---------------------
cl_int enqueue_fpga_buffer(cl_command_queue queue, cl_bool blocking,
                           cl_map_flags flags, void *ptr, size_t len,
                           cl_uint num_events, const cl_event *events,
                           cl_event *the_event)
{
  //Enqueues a command that will allow the host to update a region of a SVM buffer
  return clEnqueueSVMMap(queue, blocking, flags, ptr, len, num_events, events,
                         the_event);
}
//---------------------
//---------------------

//---------------------
//---------------------
cl_int unenqueue_fpga_buffer(cl_command_queue queue, void *ptr,
                             cl_uint num_events, const cl_event *events,
                             cl_event *the_event)
{
  return clEnqueueSVMUnmap(queue, ptr, num_events, events, the_event);
}
//---------------------
//---------------------

//---------------------
//---------------------

#ifdef shared_alloc
void remove_fpga_buffer(cl_context &context, void *ptr)
{
  if (use_prealloc_svm_buffer) {
    printf(
        "Info: Using preallocated shared buffer and custom MPF calls release "
        "buffer!\n");
    printf("Info: Using aocl_mmd_shared_alloc() and aocl_mmd_free()!\n");
    aocl_mmd_free(ptr);
  }
  else {
    clSVMFree(context, ptr);
  }
}

#else
void remove_fpga_buffer(cl_context &context, void *ptr)
{
  if (use_prealloc_svm_buffer) {
    printf(
        "Info: Using preallocated host buffer and custom MPF calls release "
        "buffer!\n");
    printf("Info: Using aocl_mmd_host_alloc() and aocl_mmd_free()!\n");
    aocl_mmd_free(ptr);
  }
  else {
    clSVMFree(context, ptr);
  }
}
#endif

//---------------------
//---------------------

//---------------------
//---------------------
void cleanup() {}
//---------------------
//---------------------

//---------------------
//---------------------
int main(int argc, char *argv[])
{
  cl_uint num_devices;
  int lines;
  if (argc >= 2) {
    vectorSize = atoi(argv[1]) * V;
    lines = atoi(argv[1]);
  }
  lines = vectorSize / V;

  if (lines == 0 || lines > 800000000) {
    printf("Invalid Number of cachelines.\n");
    return 1;
  }

  // get the platform ID
  //---------------------
  //---------------------
  platform = findPlatform("Intel(R) FPGA SDK for OpenCL(TM)");

  if(platform == NULL){
    printf("Error");
    freeResources();
    return 1;
  }  
  // get the device ID
  //---------------------
  //---------------------
  status =
      clGetDeviceIDs(platform, CL_DEVICE_TYPE_ALL, 1, &device, &num_devices);
  if (status != CL_SUCCESS) {
    dump_error("Failed clGetDeviceIDs.", status);
    freeResources();
    return 1;
  }
  if (num_devices != 1) {
    printf("Found %d devices!\n", num_devices);
    freeResources();
    return 1;
  }

  // get the board name
  //---------------------
  //---------------------
  board_name = strdup(mb_get_board_name(device).c_str());

  // create a context
  //---------------------
  //---------------------
  context = clCreateContext(0, 1, &device, NULL, NULL, &status);
  if (status != CL_SUCCESS) {
    dump_error("Failed clCreateContext.", status);
    freeResources();
    return 1;
  }
  //---------------------
  //---------------------

  if (!device_has_svm(device)) {
    printf("Platform does not use SVM!\n");
    return 0;
  }
  printf("SVM enabled!\n");

  printf("Creating SVM buffers.\n");
  unsigned long int buf_size = vectorSize <= 0 ? 64 : vectorSize * 4;

  // allocate and initialize the input vectors
  //---------------------
  //---------------------
  hdatain = (unsigned int *)alloc_fpga_host_buffer(context, 0, buf_size , 1024);
  if (hdatain == NULL) {
    dump_error("Failed alloc_fpga_host_buffer.", status);
    freeResources();
    return 1;
  }
  //---------------------
  //---------------------
  hdataout = (unsigned int *)alloc_fpga_host_buffer(context, 0, buf_size, 1024);
  if (hdataout == NULL) {
    dump_error("Failed alloc_fpga_host_buffer.", status);
    freeResources();
    return 1;
  }
  printf("Creating DDR buffers.\n");
  //---------------------
  //---------------------
  buf_size = vectorSize <= 0 ? 64 : vectorSize * 4;
  hdata_ddr1 =
      clCreateBuffer(context, CL_MEM_READ_WRITE, buf_size, NULL, &status);
  if (status != CL_SUCCESS) {
    dump_error("Failed clCreateBuffer.", status);
    freeResources();
    return 1;
  }

  //---------------------
  //---------------------
  hdata_ddr2 =
      clCreateBuffer(context, CL_MEM_READ_WRITE, buf_size, NULL, &status);
  if (status != CL_SUCCESS) {
    dump_error("Failed clCreateBuffer.", status);
    freeResources();
    return 1;
  }

  //---------------------
  //---------------------
  hdatatemp = (unsigned int *)acl_aligned_malloc(buf_size);
  if (hdatatemp == NULL) {
    dump_error("Failed acl_aligned_malloc.", status);
    freeResources();
    return 1;
  }

  printf("Initializing data.\n");
  initializeVector_seq(hdatain, vectorSize);
  initializeVector(hdataout, vectorSize);

  // create a command queue
  //---------------------
  //---------------------
  queue =
      clCreateCommandQueue(context, device, CL_QUEUE_PROFILING_ENABLE, &status);
  if (status != CL_SUCCESS) {
    dump_error("Failed clCreateCommandQueue.", status);
    freeResources();
    return 1;
  }

  // create the program
  //---------------------
  //---------------------

  cl_int kernel_status;

  size_t binsize = 0;
  unsigned char *binary_file =
      loadBinaryFile("bin/mem_bandwidth_svm_ddr.aocx", &binsize);

  if (!binary_file) {
    dump_error("Failed loadBinaryFile.", status);
    freeResources();
    return 1;
  }
  //---------------------
  //---------------------
  program = clCreateProgramWithBinary(context, 1, &device, &binsize,
                                      (const unsigned char **)&binary_file,
                                      &kernel_status, &status);
  if (status != CL_SUCCESS) {
    dump_error("Failed clCreateProgramWithBinary.", status);
    freeResources();
    return 1;
  }
  delete[] binary_file;

  // build the program
  //---------------------
  //---------------------
  status = clBuildProgram(program, 0, NULL, "", NULL, NULL);
  if (status != CL_SUCCESS) {
    dump_error("Failed clBuildProgram.", status);
    freeResources();
    return 1;
  }

  //---------------------
  //---------------------
  printf("Creating nop kernel\n");
  kernel = clCreateKernel(program, "nop", &status);
  if (status != CL_SUCCESS) {
    dump_error("Failed clCreateKernel for nop", status);
    freeResources();
    return 1;
  }

  printf("Launching the kernel...\n");

  //---------------------
  //---------------------
  status = clEnqueueTask(queue, kernel, 0, NULL, NULL);
  if (status != CL_SUCCESS) {
    dump_error("Failed to launch kernel.", status);
    freeResources();
    return 1;
  }
  printf("after kernel nop launch\n");

  //---------------------
  //---------------------
  clFinish(queue);

  // Done kernel launch test
  //---------------------
  //---------------------
  printf("Starting memcopy kernel\n");
  initializeVector_seq(hdatain, vectorSize);
  initializeVector(hdataout, vectorSize);
  int failures = 0;
  int successes = 0;
  fflush(stdout);
  if (runkernel == 0 || runkernel == 2) {
    printf("Creating memcopy kernel (Host->Host)\n");
    // create the kernel
    kernel = clCreateKernel(program, "memcopy", &status);
    if (status != CL_SUCCESS) {
      dump_error("Failed clCreateKernel.", status);
      freeResources();
      return 1;
    }

    // set the arguments
    status = set_fpga_buffer_kernel_param(kernel, 0, (void *)hdatain);
    if (status != CL_SUCCESS) {
      dump_error("Failed set memcopy  arg 0.", status);
      return 1;
    }
    status = set_fpga_buffer_kernel_param(kernel, 1, (void *)hdataout);
    if (status != CL_SUCCESS) {
      dump_error("Failed Set memcopy arg 1.", status);
      freeResources();
      return 1;
    }
    cl_int arg_3 = lines;
    status = clSetKernelArg(kernel, 2, sizeof(cl_int), &(arg_3));
    if (status != CL_SUCCESS) {
      dump_error("Failed Set arg 2.", status);
      freeResources();
      return 1;
    }
    printf("Launching the kernel...\n");
    status = enqueue_fpga_buffer(queue, CL_TRUE, CL_MAP_READ | CL_MAP_WRITE,
                                 (void *)hdatain, buf_size, 0, NULL, NULL);
    if (status != CL_SUCCESS) {
      dump_error("Failed enqueue_fpga_buffer", status);
      freeResources();
      return 1;
    }
    status = enqueue_fpga_buffer(queue, CL_TRUE, CL_MAP_READ | CL_MAP_WRITE,
                                 (void *)hdataout, buf_size, 0, NULL, NULL);
    if (status != CL_SUCCESS) {
      dump_error("Failed enqueue_fpga_buffer", status);
      freeResources();
      return 1;
    }

    const double start_time = getCurrentTimestamp();
    status = clEnqueueTask(queue, kernel, 0, NULL, NULL);
    if (status != CL_SUCCESS) {
      dump_error("Failed to launch kernel.", status);
      freeResources();
      return 1;
    }
    clFinish(queue);
    const double end_time = getCurrentTimestamp();

    status = unenqueue_fpga_buffer(queue, (void *)hdatain, 0, NULL, NULL);
    if (status != CL_SUCCESS) {
      dump_error("Failed unenqueue_fpga_buffer", status);
      freeResources();
      return 1;
    }
    status = unenqueue_fpga_buffer(queue, (void *)hdataout, 0, NULL, NULL);
    if (status != CL_SUCCESS) {
      dump_error("Failed unenqueue_fpga_buffer", status);
      freeResources();
      return 1;
    }
    clFinish(queue);

    // Wall-clock time taken.
    float time = (end_time - start_time);

    bw = vectorSize / (time * 1000000.0f) * sizeof(unsigned int) * 2;
    printf("Processed %zu unsigned ints in %.4f us\n", vectorSize,
           time * 1000000.0f);
    printf("Read/Write Bandwidth = %.0f MB/s\n", bw);
    printf("Kernel execution is complete.\n");

    // Verify the output
    for (size_t i = 0; i < vectorSize; i++) {
      if (hdatain[i] != hdataout[i]) {
        if (failures < 32)
          printf("Verification_failure %zu: %d != %d, diff %d, line %zu\n", i,
                 hdatain[i], hdataout[i], hdatain[i] - hdataout[i],
                 i * 4 / 128);
        failures++;
      }
      else {
        successes++;
      }
    }
  }

  //---------------------
  //---------------------
  if (runkernel == 0 || runkernel == 2) {

    printf("Copying to DDR\n");
    status = clEnqueueWriteBuffer(queue, hdata_ddr1, CL_TRUE, 0, buf_size,hdatain, 0, NULL, NULL);

    printf("Creating memcopy_ddr kernel (DDR->DDR)\n");

    // create the kernel
    kernel = clCreateKernel(program, "memcopy_ddr", &status);

    if (status != CL_SUCCESS) {
      dump_error("Failed clCreateKernel.", status);
      freeResources();
      return 1;
    }

    // set the arguments
    status = clSetKernelArg(kernel, 0, sizeof(cl_mem), &hdata_ddr1);
    if (status != CL_SUCCESS) {
      dump_error("Failed set arg 0.", status);
      return 1;
    }
    status = clSetKernelArg(kernel, 1, sizeof(cl_mem), &hdata_ddr2);
    if (status != CL_SUCCESS) {
      dump_error("Failed Set arg 1.", status);
      freeResources();
      return 1;
    }

    cl_int arg_3 = lines;
    status = clSetKernelArg(kernel, 2, sizeof(cl_int), &(arg_3));
    if (status != CL_SUCCESS) {
      dump_error("Failed Set arg 2.", status);
      freeResources();
      return 1;
    }

    printf("Launching the kernel...\n");

     status = enqueue_fpga_buffer(queue, CL_TRUE, CL_MAP_READ | CL_MAP_WRITE,
       (void *)hdatain,buf_size, 0, NULL, NULL);
    if (status != CL_SUCCESS) {
      dump_error("Failed enqueue_fpga_buffer", status);
      freeResources();
      return 1;
    }
    status = enqueue_fpga_buffer(queue, CL_TRUE,  CL_MAP_READ | CL_MAP_WRITE,
        (void *)hdataout, buf_size, 0, NULL, NULL);
    if (status != CL_SUCCESS) {
      dump_error("Failed enqueue_fpga_buffer", status);
      freeResources();
      return 1;
    }


    printf("after buffer enqueue\n");

    const double start_time = getCurrentTimestamp();

    status = clEnqueueTask(queue, kernel, 0, NULL, NULL);
    if (status != CL_SUCCESS) {
      dump_error("Failed to launch kernel.", status);
      freeResources();
      return 1;
    }
    printf("after kernel launch\n");
    clFinish(queue);

    const double end_time = getCurrentTimestamp();

    status = unenqueue_fpga_buffer(queue, (void *)hdatain, 0, NULL, NULL);
    if (status != CL_SUCCESS) {
      dump_error("Failed unenqueue_fpga_buffer", status);
      freeResources();
      return 1;
    }
    status = unenqueue_fpga_buffer(queue, (void *)hdataout, 0, NULL, NULL);
    if (status != CL_SUCCESS) {
      dump_error("Failed unenqueue_fpga_buffer", status);
      freeResources();
      return 1;
    }

    clFinish(queue);

    // Wall-clock time taken.
    float time = (end_time - start_time);

    bw = vectorSize / (time * 1000000.0f) * sizeof(unsigned int) * 2;
    printf("Processed %zu unsigned ints in %.4f us\n", vectorSize,
           time * 1000000.0f);
    printf("Read/Write Bandwidth = %.0f MB/s\n", bw);
    printf("Kernel execution is complete.\n");

    printf("Copying from DDR\n");
    status = clEnqueueReadBuffer(queue, hdata_ddr2, CL_TRUE, 0, buf_size,
                                hdatatemp, 0, NULL, NULL);

    if (status != CL_SUCCESS) {
      dump_error("Failed clEnqueueReadBuffer", status);
      freeResources();
      return 1;
    }
    // Verify the output
    for (size_t i = 0; i < vectorSize; i++) {
      if (hdatain[i] != hdatatemp[i]) {
        if (failures < 32)
          printf("Verification_failure %zu: %d != %d, diff %d, line %zu\n", i,
                 hdatain[i], hdatatemp[i], hdatain[i] - hdatatemp[i],
                 i * 4 / 128);
           
        failures++;
      }
      else {
        successes++;
      }
    }
  }
  if (runkernel == 0 || runkernel == 2) {
    printf(
        "Creating memcopy_to_ddr and memcopy_from_ddr kernel "
        "(Host->DDR->Host)\n");
    // create the kernel
    kernel = clCreateKernel(program, "memcopy_to_ddr", &status);
    kernel2 = clCreateKernel(program, "memcopy_from_ddr", &status);
    if (status != CL_SUCCESS) {
      dump_error("Failed clCreateKernel.", status);
      freeResources();
      return 1;
    }

    // set the arguments
    status = set_fpga_buffer_kernel_param(kernel, 0, (void *)hdatain);
    if (status != CL_SUCCESS) {
      dump_error("Failed set memcopy_to_ddr  arg 0.", status);
      return 1;
    }
    status = clSetKernelArg(kernel, 1, sizeof(cl_mem), &hdata_ddr1);
    if (status != CL_SUCCESS) {
      dump_error("Failed Set memcopy_to_ddr arg 1.", status);
      freeResources();
      return 1;
    }
    // set the arguments
    status = clSetKernelArg(kernel2, 0, sizeof(cl_mem), &hdata_ddr1);
    if (status != CL_SUCCESS) {
      dump_error("Failed set memcopy_from_ddr arg 0.", status);
      return 1;
    }
    status = set_fpga_buffer_kernel_param(kernel2, 1, (void *)hdataout);
    if (status != CL_SUCCESS) {
      dump_error("Failed Set memcopy_from_ddr arg 1.", status);
      freeResources();
      return 1;
    }
    cl_int arg_3 = lines;
    status = clSetKernelArg(kernel, 2, sizeof(cl_int), &(arg_3));
    if (status != CL_SUCCESS) {
      dump_error("Failed Set arg 2.", status);
      freeResources();
      return 1;
    }
    arg_3 = lines;
    status = clSetKernelArg(kernel2, 2, sizeof(cl_int), &(arg_3));
    if (status != CL_SUCCESS) {
      dump_error("Failed Set arg 2.", status);
      freeResources();
      return 1;
    }
    printf("Launching the kernel...\n");
    status = enqueue_fpga_buffer(queue, CL_TRUE, CL_MAP_READ | CL_MAP_WRITE,
                                 (void *)hdatain, buf_size, 0, NULL, NULL);
    if (status != CL_SUCCESS) {
      dump_error("Failed enqueue_fpga_buffer", status);
      freeResources();
      return 1;
    }
    status = enqueue_fpga_buffer(queue, CL_TRUE, CL_MAP_READ | CL_MAP_WRITE,
                                 (void *)hdataout, buf_size, 0, NULL, NULL);
    if (status != CL_SUCCESS) {
      dump_error("Failed enqueue_fpga_buffer", status);
      freeResources();
      return 1;
    }

    const double start_time = getCurrentTimestamp();
    status = clEnqueueTask(queue, kernel, 0, NULL, NULL);
    if (status != CL_SUCCESS) {
      dump_error("Failed to launch kernel.", status);
      freeResources();
      return 1;
    }
    status = clEnqueueTask(queue, kernel2, 0, NULL, NULL);
    if (status != CL_SUCCESS) {
      dump_error("Failed to launch kernel.", status);
      freeResources();
      return 1;
    }
    clFinish(queue);
    const double end_time = getCurrentTimestamp();

    status = unenqueue_fpga_buffer(queue, (void *)hdatain, 0, NULL, NULL);
    if (status != CL_SUCCESS) {
      dump_error("Failed unenqueue_fpga_buffer", status);
      freeResources();
      return 1;
    }
    status = unenqueue_fpga_buffer(queue, (void *)hdataout, 0, NULL, NULL);
    if (status != CL_SUCCESS) {
      dump_error("Failed unenqueue_fpga_buffer", status);
      freeResources();
      return 1;
    }
    clFinish(queue);

    // Wall-clock time taken.
    float time = (end_time - start_time);

    bw = vectorSize / (time * 1000000.0f) * sizeof(unsigned int) * 2;
    printf("Processed %zu unsigned ints in %.4f us\n", vectorSize,
           time * 1000000.0f);
    printf("Read/Write Bandwidth = %.0f MB/s\n", bw);
    printf("Kernel execution is complete.\n");

    // Verify the output
    for (size_t i = 0; i < vectorSize; i++) {
      if (hdatain[i] != hdataout[i]) {
        if (failures < 32)
          printf("Verification_failure %zu: %d != %d, diff %d, line %zu\n", i,
                 hdatain[i], hdataout[i], hdatain[i] - hdataout[i],
                 i * 4 / 128);
        failures++;
      }
      else {
        successes++;
      }
    }
    printf("Read from DDR.\n");
    status = clEnqueueReadBuffer(queue, hdata_ddr1, CL_TRUE, 0, buf_size,
                                 hdatatemp, 0, NULL, NULL);

    if (status != CL_SUCCESS) {
      dump_error("Failed clEnqueueReadBuffer", status);
      freeResources();
      return 1;
    }
    // Verify the output
    for (size_t i = 0; i < vectorSize; i++) {
      if (hdatain[i] != hdatatemp[i]) {
        if (failures < 32)
          printf("Verification_failure %zu: %d != %d, diff %d, line %zu\n", i,
                 hdatain[i], hdataout[i], hdatain[i] - hdataout[i],
                 i * 4 / 128);
        failures++;
      }
      else {
        successes++;
      }
    }
  }

  if (runkernel == 0 || runkernel == 3) {
    printf("Creating memread kernel\n");
    kernel_read = clCreateKernel(program, "memread", &status);
    if (status != CL_SUCCESS) {
      dump_error("Failed clCreateKernel.", status);
      freeResources();
      return 1;
    }

    // set the arguments
    status = set_fpga_buffer_kernel_param(kernel_read, 0, (void *)hdatain);
    if (status != CL_SUCCESS) {
      dump_error("Failed set arg 0.", status);
      return 1;
    }
    status = set_fpga_buffer_kernel_param(kernel_read, 1, (void *)hdataout);
    if (status != CL_SUCCESS) {
      dump_error("Failed Set arg 1.", status);
      freeResources();
      return 1;
    }

    cl_int arg_3 = lines;
    status = clSetKernelArg(kernel_read, 2, sizeof(cl_int), &(arg_3));
    if (status != CL_SUCCESS) {
      dump_error("Failed Set arg 2.", status);
      freeResources();
      return 1;
    }
    printf("Launching the kernel...\n");
    status = enqueue_fpga_buffer(queue, CL_TRUE, CL_MAP_READ | CL_MAP_WRITE,
                                 (void *)hdatain, buf_size, 0, NULL, NULL);
    if (status != CL_SUCCESS) {
      dump_error("Failed enqueue_fpga_buffer", status);
      freeResources();
      return 1;
    }
    status = enqueue_fpga_buffer(queue, CL_TRUE, CL_MAP_READ | CL_MAP_WRITE,
                                 (void *)hdataout, buf_size, 0, NULL, NULL);
    if (status != CL_SUCCESS) {
      dump_error("Failed enqueue_fpga_buffer", status);
      freeResources();
      return 1;
    }

    // launch kernel
    const double start_time = getCurrentTimestamp();
    status = clEnqueueTask(queue, kernel_read, 0, NULL, NULL);
    if (status != CL_SUCCESS) {
      dump_error("Failed to launch kernel.", status);
      freeResources();
      return 1;
    }

    clFinish(queue);
    const double end_time = getCurrentTimestamp();

    status = unenqueue_fpga_buffer(queue, (void *)hdatain, 0, NULL, NULL);
    if (status != CL_SUCCESS) {
      dump_error("Failed unenqueue_fpga_buffer", status);
      freeResources();
      return 1;
    }
    status = unenqueue_fpga_buffer(queue, (void *)hdataout, 0, NULL, NULL);
    if (status != CL_SUCCESS) {
      dump_error("Failed unenqueue_fpga_buffer", status);
      freeResources();
      return 1;
    }

    clFinish(queue);

    // Wall-clock time taken.
    float time = (end_time - start_time);

    bw = vectorSize / (time * 1000000.0f) * sizeof(unsigned int);
    printf("Processed %zu unsigned ints in %.4f us\n", vectorSize,
           time * 1000000.0f);
    printf("Read Bandwidth = %.0f MB/s\n", bw);
    printf("Kernel execution is complete.\n");
  }

  if (runkernel == 0 || runkernel == 4) {
    printf("Creating memwrite kernel\n");
    kernel_write = clCreateKernel(program, "memwrite", &status);

    if (status != CL_SUCCESS) {
      dump_error("Failed clCreateKernel.", status);
      freeResources();
      return 1;
    }

    // set the arguments
    status = set_fpga_buffer_kernel_param(kernel_write, 0, (void *)hdatain);
    if (status != CL_SUCCESS) {
      dump_error("Failed set arg 0.", status);
      return 1;
    }
    status = set_fpga_buffer_kernel_param(kernel_write, 1, (void *)hdataout);
    if (status != CL_SUCCESS) {
      dump_error("Failed Set arg 1.", status);
      freeResources();
      return 1;
    }

    cl_int arg_3 = lines;
    status = clSetKernelArg(kernel_write, 2, sizeof(cl_int), &(arg_3));
    if (status != CL_SUCCESS) {
      dump_error("Failed Set arg 2.", status);
      freeResources();
      return 1;
    }
    status = enqueue_fpga_buffer(queue, CL_TRUE, CL_MAP_READ | CL_MAP_WRITE,
                                 (void *)hdatain, buf_size, 0, NULL, NULL);
    if (status != CL_SUCCESS) {
      dump_error("Failed enqueue_fpga_buffer", status);
      freeResources();
      return 1;
    }
    status = enqueue_fpga_buffer(queue, CL_TRUE, CL_MAP_READ | CL_MAP_WRITE,
                                 (void *)hdataout, buf_size, 0, NULL, NULL);
    if (status != CL_SUCCESS) {
      dump_error("Failed enqueue_fpga_buffer", status);
      freeResources();
      return 1;
    }

    printf("Launching the kernel...\n");

    const double start_time = getCurrentTimestamp();
    status = clEnqueueTask(queue, kernel_write, 0, NULL, NULL);
    if (status != CL_SUCCESS) {
      dump_error("Failed to launch kernel.", status);
      freeResources();
      return 1;
    }
    clFinish(queue);
    const double end_time = getCurrentTimestamp();

    // Wall-clock time taken.
    float time = (end_time - start_time);

    bw = vectorSize / (time * 1000000.0f) * sizeof(unsigned int);
    printf("Processed %zu unsigned ints in %.4f us\n", vectorSize,
           time * 1000000.0f);
    printf("Write Bandwidth = %.0f MB/s\n", bw);
    printf("Kernel execution is complete.\n");
  }

  if (failures == 0) {
    printf("Verification finished.\n");
  }
  else {
    printf("FAILURES %d - successes - %d\n", failures, successes);
  }

  freeResources();

  return 0;
}
