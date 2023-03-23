// Copyright 2022 Intel Corporation
// SPDX-License-Identifier: MIT

#include <assert.h>
#include <math.h>
#include <sstream>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "acl_aligned.h"
#include "ocl.h"

// ACL specific includes
#include "CL/opencl.h"

#if defined(WINDOWS)
#include <limits>
#define INFINITY std::numeric_limits<double>::infinity()
#endif // WINDOWS

#if defined(WINDOWS)
#define cl_ulong_printf "%llu"
#define cl_ulong_printfx "%llx"
#endif // WINDOWS
#if defined(LINUX)
#define cl_ulong_printf "%lu"
#define cl_ulong_printfx "%lx"
#endif // LINUX

// ACL runtime configuration
static cl_platform_id platform;
static cl_device_id device;
static cl_context context;
static cl_command_queue queue;
static cl_kernel kernel;
static cl_program program;
static cl_int status;

static cl_mem kernel_input;

float ocl_get_exec_time_ns(cl_event evt);

// free the resources allocated during initialization
static void freeResources() {
  if (kernel)
    clReleaseKernel(kernel);
  if (program)
    clReleaseProgram(program);
  if (queue)
    clReleaseCommandQueue(queue);
  if (context)
    clReleaseContext(context);
  if (kernel_input)
    clReleaseMemObject(kernel_input);
}

static void dump_error(const char *str, cl_int status) {
  printf("%s\n", str);
  printf("Error code: %d\n", status);
  freeResources();
  exit(-1);
}

void ocl_device_init(int maxbytes, char *device_name) {
  char buf[1000];

  cl_uint num_platforms = 0;
  cl_uint num_devices;
  cl_device_id *device_list = NULL;

  // get the platform ID
  status = clGetPlatformIDs(0, NULL, &num_platforms);
  if (status != CL_SUCCESS)
    dump_error("Failed clGetPlatformIDs.", status);
  status = clGetPlatformIDs(1, &platform, NULL);
  if (status != CL_SUCCESS)
    dump_error("Failed clGetPlatformIDs.", status);
  if (num_platforms != 1) {
    printf("Warning: Found %d platforms, using the first!\n", num_platforms);
  }
  char platform_name[256];
  clGetPlatformInfo(platform, CL_PLATFORM_NAME, 256, platform_name, NULL);
  printf("Using platform: %s\n", platform_name);

  // get the number of devices available
  status = clGetDeviceIDs(platform, CL_DEVICE_TYPE_ALL, 0, NULL, &num_devices);
  if (status != CL_SUCCESS)
    dump_error("Failed clGetDeviceIDs.", status);

  // Allocate buffer for the number of devices
  device_list = (cl_device_id *)malloc(num_devices * sizeof(cl_device_id));
  if (device_list == NULL)
    dump_error("Failed to allocate buffer for devices.", status);

  // get the device ID
  status = clGetDeviceIDs(platform, CL_DEVICE_TYPE_ALL, num_devices,
                          device_list, NULL);
  if (status != CL_SUCCESS) {
    free(device_list);
    dump_error("Failed clGetDeviceIDs.", status);
  }

  bool device_found = 0;
  for (cl_uint i = 0; i < num_devices; i++) {
    clGetDeviceInfo(device_list[i], CL_DEVICE_NAME, sizeof(buf), (void *)&buf,
                    NULL);
    std::string word;
    std::stringstream ss(buf);
    while (ss >> word) {
      std::string part(word.substr(0, 5));
      if (strcmp(part.c_str(), "(ofs_") == 0) {
        if (strcmp(device_name, word.substr(1, (word.length() - 2)).c_str()) ==
            0) {
          device = device_list[i];
          device_found = 1;
          break;
        }
      }
    }
    if (device_found == 1) {
      break;
    }
  }

  if (device_found == 0) {
    printf("Can't open device %s\n", device_name);
    free(device_list);
    freeResources();
    exit(-1);
  }

  free(device_list);

  status =
      clGetDeviceInfo(device, CL_DEVICE_NAME, sizeof(buf), (void *)&buf, NULL);
  printf("Using Device with name: %s\n", buf);
  status = clGetDeviceInfo(device, CL_DEVICE_VENDOR, sizeof(buf), (void *)&buf,
                           NULL);
  printf("Using Device from vendor: %s\n", buf);

  // create a context
  context = clCreateContext(0, 1, &device, NULL, NULL, &status);
  if (status != CL_SUCCESS)
    dump_error("Failed clCreateContext.", status);

  // create a command queue
  const cl_queue_properties properties[] = {
    CL_QUEUE_PROPERTIES, CL_QUEUE_PROFILING_ENABLE,
    0
  };
  queue =
      clCreateCommandQueueWithProperties(context, device, properties, &status);
  if (status != CL_SUCCESS)
    dump_error("Failed clCreateCommandQueueWithProperties.", status);

  if (ocl_test_all_global_memory() != 0)
    dump_error("Error: Global memory test failed\n", 0);

  // create the input buffer
  kernel_input = clCreateBuffer(context, CL_MEM_READ_WRITE, (size_t)maxbytes,
                                NULL, &status);
  if (status != CL_SUCCESS)
    dump_error("Failed clCreateBuffer.", status);
}

int ocl_test_all_global_memory() {
  cl_mem mem;
  cl_ulong max_buffer_size;
  cl_ulong max_alloc_size;
  const cl_ulong MB = 1024 * 1024;
  const cl_ulong MAX_HOST_CHUNK = 1024 * MB;
  const cl_ulong MINIMUM_HOST_CHUNK = 128 * MB;

  // 1. Get maximum size buffer
  status =
      clGetDeviceInfo(device, CL_DEVICE_GLOBAL_MEM_SIZE,
                      sizeof(max_buffer_size), (void *)&max_buffer_size, NULL);
  status =
      clGetDeviceInfo(device, CL_DEVICE_MAX_MEM_ALLOC_SIZE,
                      sizeof(max_alloc_size), (void *)&max_alloc_size, NULL);

#ifdef SMALL_MAX_ALLOC_SIZE
  max_alloc_size = 128 * 1024 * 1024;
  max_buffer_size = 128 * 1024 * 1024;
#endif

  printf("clGetDeviceInfo CL_DEVICE_GLOBAL_MEM_SIZE = " cl_ulong_printf "\n",
         max_buffer_size);
  printf("clGetDeviceInfo CL_DEVICE_MAX_MEM_ALLOC_SIZE = " cl_ulong_printf "\n",
         max_alloc_size);
  if (max_buffer_size > max_alloc_size)
    printf("Memory consumed for internal use = " cl_ulong_printf "\n",
           max_buffer_size - max_alloc_size);

  // 2. GetDeviceInfo may lie - so binary search to find true largest buffer
  cl_ulong low = 1;
  cl_ulong high =
      (max_buffer_size > max_alloc_size) ? max_buffer_size : max_alloc_size;
  status = CL_OUT_OF_RESOURCES;

  while (status != CL_SUCCESS || (low + 1 < high)) {
    cl_ulong mid = (low + high) / 2;

    mem = clCreateBuffer(context, CL_MEM_READ_WRITE, mid, NULL, &status);
    clReleaseMemObject(mem);
    if (status == CL_SUCCESS)
      low = mid;
    else
      high = mid;
  }

  mem = clCreateBuffer(context, CL_MEM_READ_WRITE, high, NULL, &status);
  clReleaseMemObject(mem);
  if (status != CL_SUCCESS)
    high = low;
  else
    printf("Allocated " cl_ulong_printf " bytes\n", high);
  cl_ulong max_size = high;
  printf("Actual maximum buffer size = " cl_ulong_printf " bytes\n", max_size);

  // 3. Allocate the buffer (should consume all of memory)
  mem = clCreateBuffer(context, CL_MEM_READ_WRITE, max_size, NULL, &status);
  assert(status == CL_SUCCESS);

  // 4. Initialize memory with data = addr
  printf("Writing " cl_ulong_printf " MB to global memory ...\n",
         max_size / MB);
  cl_ulong bytes_rem = max_size;
  cl_ulong offset = 0;
  double sum_time = 0;
  double max_bw = 0;
  double min_bw = INFINITY;
  cl_ulong *hostbuf = (cl_ulong *)acl_util_aligned_malloc(MAX_HOST_CHUNK);
  cl_ulong aligned_buf_size = MAX_HOST_CHUNK;

  while ((hostbuf == NULL) & (aligned_buf_size > MINIMUM_HOST_CHUNK)) {
    aligned_buf_size = aligned_buf_size / 2;
    hostbuf = (cl_ulong *)acl_util_aligned_malloc((size_t)aligned_buf_size);
  }
  if (hostbuf == NULL) {
    printf("Insufficient host memory for %lu Byte aligned buffer allocation\n",
           (long unsigned)aligned_buf_size);
    assert(hostbuf != NULL);
    exit(1); // Exit in case assertion doesn't trigger error
  }
  printf("Allocated %lu Bytes host buffer for large transfers\n",
         (long unsigned)aligned_buf_size);

  while (bytes_rem > 0) {
    cl_event e;
    cl_ulong chunk = bytes_rem;
    if (chunk > aligned_buf_size)
      chunk = aligned_buf_size;
    for (cl_ulong i = 0; i < chunk / sizeof(cl_ulong); ++i) {
      hostbuf[i] = offset + i;
    }
    status = clEnqueueWriteBuffer(queue, mem, CL_TRUE, offset, chunk,
                                  (void *)hostbuf, 0, NULL, &e);
    assert(status == CL_SUCCESS);

    // Transfer speed
    double write_time_ns = ocl_get_exec_time_ns(e);
    double bw = chunk * 1000.0 / write_time_ns;
    if (bw > max_bw)
      max_bw = bw;
    if (bw < min_bw)
      min_bw = bw;
    sum_time += write_time_ns;

    // Next iteration...
    clReleaseEvent(e);
    offset += chunk;
    bytes_rem -= chunk;
  }

  if (sum_time > 0) {
    printf("Write speed: %.2lf MB/s [%.2lf -> %.2lf]\n",
           max_size * 1000.0 / sum_time, min_bw, max_bw);
  } else {
    printf("Error measuring write speed\n");
  }

  // Read-back and verify
  printf("Reading and verifying " cl_ulong_printf
         " MB from global memory ...\n",
         max_size / MB);
  bytes_rem = max_size;
  offset = 0;
  cl_ulong errors = 0;
  sum_time = 0;
  max_bw = 0;
  min_bw = INFINITY;
  while (bytes_rem > 0) {
    cl_event e;
    cl_ulong chunk = bytes_rem;
    if (chunk > aligned_buf_size)
      chunk = aligned_buf_size;
    status = clEnqueueReadBuffer(queue, mem, CL_TRUE, offset, chunk,
                                 (void *)hostbuf, 0, NULL, &e);
    assert(status == CL_SUCCESS);

    // Transfer speed
    double read_time_ns = ocl_get_exec_time_ns(e);
    double bw = chunk * 1000.0 / read_time_ns;
    if (bw > max_bw)
      max_bw = bw;
    if (bw < min_bw)
      min_bw = bw;
    sum_time += read_time_ns;

    // Verify
    for (cl_ulong i = 0; i < chunk / sizeof(cl_ulong); ++i) {
      if (hostbuf[i] != (i + offset)) {
        ++errors;
        if (errors <= 32)
          printf("Verification failure at element " cl_ulong_printf
                 ", expected " cl_ulong_printfx
                 " but read back " cl_ulong_printfx "\n",
                 i, i, hostbuf[i]);
        if (errors == 32)
          printf("Suppressing error output, counting # of errors ...\n");
        if (errors == 1)
          printf("First failure at address " cl_ulong_printfx "\n",
                 i * (cl_ulong)sizeof(cl_ulong) + (max_buffer_size - max_size));
      }
    }

    // Next iteration...
    clReleaseEvent(e);
    offset += chunk;
    bytes_rem -= chunk;
  }
  if (sum_time > 0) {
    printf("Read speed: %.2lf MB/s [%.2lf -> %.2lf]\n",
           max_size * 1000.0 / sum_time, min_bw, max_bw);
  } else {
    printf("Error measuring read speed\n");
  }

  acl_util_aligned_free(hostbuf);
  clReleaseMemObject(mem);

  // 5. Do Verification
  if (errors == 0)
    printf("Successfully wrote and readback " cl_ulong_printf " MB buffer\n",
           max_size / 1024 / 1024);
  else
    printf("Failed write/readback test with " cl_ulong_printf " errors\n",
           errors);
  printf("\n");

  return (int)errors;
}

float ocl_get_exec_time_ns(cl_event evt) {
  cl_ulong kernelEventQueued;
  cl_ulong kernelEventSubmit;
  cl_ulong kernelEventStart;
  cl_ulong kernelEventEnd;
  clGetEventProfilingInfo(evt, CL_PROFILING_COMMAND_QUEUED,
                          sizeof(unsigned long long), &kernelEventQueued, NULL);
  clGetEventProfilingInfo(evt, CL_PROFILING_COMMAND_SUBMIT,
                          sizeof(unsigned long long), &kernelEventSubmit, NULL);
  clGetEventProfilingInfo(evt, CL_PROFILING_COMMAND_START,
                          sizeof(unsigned long long), &kernelEventStart, NULL);
  clGetEventProfilingInfo(evt, CL_PROFILING_COMMAND_END,
                          sizeof(unsigned long long), &kernelEventEnd, NULL);
  cl_ulong exectime_ns = kernelEventEnd - kernelEventQueued;
  return (float)exectime_ns;
}

// Get execution time between Queueing of first and ending of last
float ocl_get_exec_time2_ns(cl_event evt_first, cl_event evt_last) {
  cl_ulong firstQueued;
  cl_ulong lastEnd;
  clGetEventProfilingInfo(evt_first, CL_PROFILING_COMMAND_QUEUED,
                          sizeof(unsigned long long), &firstQueued, NULL);
  clGetEventProfilingInfo(evt_last, CL_PROFILING_COMMAND_END,
                          sizeof(unsigned long long), &lastEnd, NULL);
  cl_ulong exectime_ns = lastEnd - firstQueued;
  return (float)exectime_ns;
}

struct speed ocl_readspeed(char *buf, int block_bytes, int bytes) {
  size_t num_xfers = bytes / block_bytes;

  assert(num_xfers > 0);
  if (num_xfers <= 0) {
    exit(1);
  }

  cl_event *evt = new cl_event[(size_t)num_xfers];

  for (size_t i = 0; i < num_xfers; i++) {

    // read the input
    status = clEnqueueReadBuffer(
        queue, kernel_input, CL_TRUE, (size_t)(i * block_bytes),
        (size_t)block_bytes, (void *)&buf[i * block_bytes], 0, NULL, &evt[i]);
    if (status != CL_SUCCESS)
      dump_error("Failed to enqueue buffer.", status);
  }

  // Make sure everything is done
  clFinish(queue);

  struct speed speed;
  speed.average = 0.0f;
  speed.fastest = 0.0f;
  speed.slowest = 10000000.0f;
  speed.total = (float)((float)bytes * 1000.0f /
                        ocl_get_exec_time2_ns(evt[0], evt[num_xfers - 1]));

  for (size_t i = 0; i < num_xfers; i++) {
    float time_ns = ocl_get_exec_time_ns(evt[i]);
    float speed_MBps = (float)block_bytes * 1000.0f / time_ns;

    if (speed_MBps > speed.fastest)
      speed.fastest = speed_MBps;
    if (speed_MBps < speed.slowest)
      speed.slowest = speed_MBps;

    speed.average += time_ns;
    clReleaseEvent(evt[i]);
  }
  if (speed.average != 0.0f) {
    speed.average = (float)((float)bytes * 1000.0f / speed.average);
  }

  delete[] evt;
  return speed;
}

struct speed ocl_writespeed(char *buf, int block_bytes, int bytes) {
  size_t num_xfers = bytes / block_bytes;

  assert(num_xfers > 0);
  if (num_xfers <= 0) {
    exit(1);
  }
  cl_event *evt = new cl_event[(size_t)num_xfers];

  for (size_t i = 0; i < num_xfers; i++) {
    // Write the input
    status = clEnqueueWriteBuffer(
        queue, kernel_input, CL_TRUE, (size_t)(i * block_bytes),
        (size_t)block_bytes, (void *)&buf[i * block_bytes], 0, NULL, &evt[i]);
    if (status != CL_SUCCESS)
      dump_error("Failed to enqueue buffer write.", status);
  }

  // Make sure everything is done
  clFinish(queue);

  struct speed speed;
  speed.average = 0.0f;
  speed.fastest = 0.0f;
  speed.slowest = 10000000.0f;

  speed.total = (float)((float)bytes * 1000.0f /
                        ocl_get_exec_time2_ns(evt[0], evt[num_xfers - 1]));

  for (size_t i = 0; i < num_xfers; i++) {
    float time_ns = ocl_get_exec_time_ns(evt[i]);
    float speed_MBps = (float)block_bytes * 1000.0f / time_ns;

    if (speed_MBps > speed.fastest)
      speed.fastest = speed_MBps;
    if (speed_MBps < speed.slowest)
      speed.slowest = speed_MBps;

    speed.average += time_ns;
    clReleaseEvent(evt[i]);
  }
  if (speed.average != 0.0f) {
    speed.average = (float)((float)bytes * 1000.0f / speed.average);
  }

  delete[] evt;
  return speed;
}
