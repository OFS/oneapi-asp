#include <stdio.h>
#include <string.h>
#include <string>
#include <stdlib.h>
#include <math.h>
#include <limits.h>
#include <fstream>
#include <iostream>
using namespace std;
// ACL specific includes
#include "CL/opencl.h"
#include "aclutil.h"
#include "timer.h"
extern bool g_enable_notifications;

// This is highest power-of-2 global size supported by runtime
static const size_t MAX_GLOBAL_WORK_SIZE = 0x40000000;

static const size_t V = 16;
static const size_t wgSize = 1024 * 32;
static size_t vectorSize;
static size_t numVectors = 0;
static const size_t NUM_KERNELS = 1;
static const char *kernel_name[] = { "mem_read_writestream" };


// ACL runtime configuration
static cl_platform_id platform;
static cl_device_id device;
static cl_context context;
static cl_command_queue queue;
static cl_kernel kernel[NUM_KERNELS];
static cl_program program;
static cl_int status;

static cl_mem *ddatain;

// input and output vectors
static unsigned int *hdatain, *hdataout;

static void initializeVector(unsigned int * vector, size_t size, unsigned int offset) {
  unsigned int i = 0;
  for (i; i < size; ++i) {
    vector[i] = offset + i;
  }
}

static void dump_error(const char *str, cl_int status) {
  printf("%s\n", str);
  printf("Error code: %d\n", status);
}

// free the resources allocated during initialization
static void freeResources() {
  for (int k = 0; k < NUM_KERNELS; k++)
    if (kernel[k])
      clReleaseKernel(kernel[k]);

  if (ddatain) {
    for (int vecID = 0; vecID < numVectors; vecID++) {
      if (ddatain[vecID]) {
        clReleaseMemObject(ddatain[vecID]);
      }
    }
    free(ddatain);
  }

  clFinish(queue);
}

int memRW(
    cl_platform_id in_platform,
    cl_device_id in_device,
    cl_context in_context,
    cl_command_queue in_queue, cl_program in_program
) {
  platform = in_platform;
  device = in_device;
  context = in_context;
  queue = in_queue;
  program = in_program;
  for (int k = 0; k < NUM_KERNELS; k++) {
    // create the kernel
    kernel[k] = clCreateKernel(program, kernel_name[k], &status);
    if (status != CL_SUCCESS) {
      dump_error("Failed clCreateKernel.", status);
      freeResources();
      return 1;
    }
    printf("Launching kernel %s ...\n", kernel_name[k]);
    cl_ulong maxAlloc_size = get_max_mem_alloc_size(context, queue, device);
    if (maxAlloc_size == 0) return 1;
    vectorSize = maxAlloc_size / sizeof(unsigned);

    // allocate and initialize the input vectors
    // Limit host_vectorSize to max vector size supported by runtime
    size_t host_vectorSize = (vectorSize > MAX_GLOBAL_WORK_SIZE) ?
          MAX_GLOBAL_WORK_SIZE : vectorSize;
    hdatain = (unsigned *)acl_aligned_malloc(host_vectorSize * sizeof(unsigned));
    hdataout = (unsigned *)acl_aligned_malloc(host_vectorSize * sizeof(unsigned));
    while (hdatain == NULL || hdataout == NULL) {
      host_vectorSize = host_vectorSize / 2;
      hdatain = (unsigned *)acl_aligned_malloc(host_vectorSize * sizeof(unsigned));
      hdataout = (unsigned *)acl_aligned_malloc(host_vectorSize * sizeof(unsigned));
    }
    size_t host_vectorSize_bytes = host_vectorSize * sizeof(unsigned);
    printf("Finished initializing host vectors.  \n");

    printf("Creating kernel buffer. \n");

    // If vectorSize > MAX_GLOBAL_WORK_SIZE, multiple kernel enqueues are needed
    // to access the whole global memory address space from Kernel.
    // Create vector set for each kernel enqueue
    numVectors = (vectorSize + MAX_GLOBAL_WORK_SIZE - 1) / MAX_GLOBAL_WORK_SIZE;
    ddatain = (cl_mem *) malloc(numVectors * sizeof(cl_mem));
    if (ddatain == NULL) {
      fprintf(stderr, "Failed to allocate ddatain buffer.\n");
      freeResources();
      return 1;
    }
    memset(ddatain, 0, numVectors * sizeof(cl_mem));

    // Create global memory buffer for each vector set and initalize it in mem
    for (int vecID = 0; vecID < numVectors; vecID++) {
      size_t global_offset = vecID * MAX_GLOBAL_WORK_SIZE;
      size_t currentVectorSize = MAX_GLOBAL_WORK_SIZE;

      // Remaining vectors for last set
      if (vecID == (numVectors - 1)) {
        currentVectorSize = vectorSize - global_offset;
      }

      size_t currentVectorSize_bytes = currentVectorSize * sizeof(unsigned);
      ddatain[vecID] = clCreateBuffer(context, CL_MEM_READ_WRITE,
                  currentVectorSize_bytes, NULL, &status);
      if (status != CL_SUCCESS) {
        dump_error("Failed clCreateBuffer.", status);
        freeResources();
        return 1;
      }

      // If host buffer, hdatain is smaller than ddatain[vecID],
      // need to transfer data over with multiple clEnqueuewrite
      cl_ulong offset_bytes = 0;
      cl_ulong bytes_rem = currentVectorSize_bytes;

      while (bytes_rem > 0)
      {
        cl_ulong chunk = bytes_rem;
        if (chunk > host_vectorSize_bytes)
          chunk = host_vectorSize_bytes;
        host_vectorSize = chunk / sizeof(unsigned);
        unsigned int offset = offset_bytes / sizeof(unsigned);
        initializeVector(hdatain, host_vectorSize, (unsigned int)(global_offset + offset));
        // Transfer chunk size data to ddatain[vecID]
        status = clEnqueueWriteBuffer(queue, ddatain[vecID], CL_TRUE,
                  offset_bytes, chunk, hdatain, 0, NULL, NULL);
        if (status != CL_SUCCESS) {
          dump_error("Failed to clEnqueueWrite.", status);
          freeResources();
          return 1;
        }
        clFinish(queue);
        offset_bytes += chunk;
        bytes_rem -= chunk;
      }
    }
    printf("Finished writing to device buffers. \n");

    // Enqueue kernel to access all of global memory
    // Multiple enqueues are needed if vectorSize > MAX_GLOBAL_WORK_SIZE
    for (int vecID = 0; vecID < numVectors; vecID++) {
      size_t global_offset = vecID * MAX_GLOBAL_WORK_SIZE;
      size_t currentVectorSize = MAX_GLOBAL_WORK_SIZE;

      if (vecID == (numVectors - 1)) {
        currentVectorSize = vectorSize - global_offset;
      }

      status = clSetKernelArg(kernel[k], 0, sizeof(cl_mem), (void*)&ddatain[vecID]);
      if (status != CL_SUCCESS) {
        dump_error("Failed set arg 0.", status);
        return 1;
      }
      unsigned int arg = 1;
      status = clSetKernelArg(kernel[k], 1, sizeof(unsigned int), &arg);
      unsigned int arg2 = 0;
      status |= clSetKernelArg(kernel[k], 2, sizeof(unsigned int), &arg2);
      if (status != CL_SUCCESS) {
        dump_error("Failed Set arg 1 and/or 2.", status);
        freeResources();
        return 1;
      }
      printf("Finished setting kernel args for vector offset %zu\n", global_offset);
      // launch kernel
      size_t gsize = currentVectorSize;
      size_t lsize = wgSize;
      if (gsize % lsize != 0) lsize = 1;
      status = clEnqueueNDRangeKernel(queue, kernel[k], 1, NULL, &gsize, &lsize, 0, NULL, NULL);
      if (status != CL_SUCCESS) {
        dump_error("Failed to launch kernel.", status);
        freeResources();
        return 1;
      }
    }
    clFinish(queue);
    printf("Kernel finished execution. \n");

    // Read global memory back and verify read value
    for (int vecID = 0; vecID < numVectors; vecID++) {
      size_t global_offset = vecID * MAX_GLOBAL_WORK_SIZE;
      size_t currentVectorSize = MAX_GLOBAL_WORK_SIZE;

      if (vecID == (numVectors - 1)) {
        currentVectorSize = vectorSize - global_offset;
      }

      size_t currentVectorSize_bytes = currentVectorSize * sizeof(unsigned);
      cl_ulong bytes_rem = currentVectorSize_bytes;
      cl_ulong offset_bytes = 0;
      while (bytes_rem > 0)
      {
        cl_ulong chunk = bytes_rem;
        if (chunk > host_vectorSize_bytes)
          chunk = host_vectorSize_bytes;
        host_vectorSize = chunk / sizeof(unsigned);
        int offset = offset_bytes / sizeof(unsigned);
        status = clEnqueueReadBuffer(queue, ddatain[vecID], CL_TRUE, offset_bytes, chunk, hdataout, 0, NULL, NULL);
        if (status != CL_SUCCESS) {
          dump_error("Failed to enqueue buffer read.", status);
          freeResources();
          return 1;
        }
        clFinish(queue);

        // verify the output - Read and write stream kernel updates the buffer ddatain (src)
        // - src[gid] = oldvalue + 2,
        for (unsigned int i = 0; i < host_vectorSize; i++) {
          if (hdataout[i] != (unsigned int)(global_offset + offset + i + 2)) {
            printf("Verification failed %d: %d != %zu \n",
                 i, hdataout[i], global_offset + offset + i + 2);
            if (hdatain)
              acl_aligned_free(hdatain);
            if (hdataout)
              acl_aligned_free(hdataout);
            freeResources();
            return 1;
          }
        }
        offset_bytes += chunk;
        bytes_rem -= chunk;
      }
    }
    printf("Finished Verification. \n");
    if (hdatain)
      acl_aligned_free(hdatain);
    if (hdataout)
      acl_aligned_free(hdataout);

    for (int vecID = 0; vecID < numVectors; vecID++) {
      if (ddatain[vecID]) {
        if (CL_SUCCESS == clReleaseMemObject(ddatain[vecID])) {
          ddatain[vecID] = NULL;
        }
      }
    }
    free(ddatain);
    ddatain = NULL;
  }

  printf("KERNEL MEMORY READ WRITE TEST PASSED. \n");

  // free the resources allocated
  freeResources();
  return 0;
}
