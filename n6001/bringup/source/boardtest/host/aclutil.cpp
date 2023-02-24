#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <math.h>
#include <limits.h>
// ACL specific includes
#include "CL/opencl.h"
#include "aclutil.h"
#include "timer.h"
#include <stdlib.h>
extern bool g_enable_notifications;

#define ACL_ALIGNMENT 64

#ifdef LINUX
#include <stdlib.h>

void* acl_aligned_malloc (size_t size) {
  void *result = NULL;
  posix_memalign (&result, ACL_ALIGNMENT, size);
  return result;
}
void acl_aligned_free (void *ptr) {
  free (ptr);
}

#else // WINDOWS
#include <malloc.h>
#include < windows.h>
void* acl_aligned_malloc (size_t size) {
  return _aligned_malloc (size, ACL_ALIGNMENT);
}
void acl_aligned_free (void *ptr) {
  _aligned_free (ptr);
}

#endif // LINUX


unsigned char* load_file(const char* filename, size_t*size_ret)
{
  FILE* fp;
  size_t w = 0;
  size_t size = 0;
  unsigned char *result = 0;
  fp = fopen(filename, "rb");
  if (fp == NULL ) {
    printf("Error: failed to open aocx file %s\n", filename);
    return NULL;
  }
  // Get source file length
  fseek(fp, 0, SEEK_END);
  size = ftell(fp);
  rewind(fp);
  result = (unsigned char*)malloc(size);
  if ( !result )  return 0;
  if ( !fp ) return 0;
  w = fread(result, 1, size, fp);
  fclose(fp);
  *size_ret = w;
  return result;
}

cl_ulong get_max_mem_alloc_size(cl_context context, cl_command_queue queue, cl_device_id device)
{
  /************* Measuring maximum buffer size ******************** */
  cl_mem test = NULL;
  cl_ulong maxAlloc_size = 0;
  cl_ulong low = 1;
  cl_ulong high;

  int status = clGetDeviceInfo(device, CL_DEVICE_MAX_MEM_ALLOC_SIZE, sizeof(maxAlloc_size), (void*) &maxAlloc_size, NULL);
  printf("clGetDeviceInfo CL_DEVICE_MAX_MEM_ALLOC_SIZE = %llu bytes.\n", maxAlloc_size);
  high = maxAlloc_size;
  g_enable_notifications = false;
  //  printf("Ignore openCl notifications till the next message. \n");

  while (low + 1 < high)
  {
    cl_ulong mid = (low + high) / 2;
    if (mid == 0)
    {
      printf("Error in findind maximum memory allocation size. \n");
      return 0;
    }
    test = clCreateBuffer(context, CL_MEM_READ_WRITE, mid, NULL, &status);
    clReleaseMemObject(test);
    if (status == CL_SUCCESS)
      low = mid;
    else
      high = mid;
  }

  test = clCreateBuffer(context, CL_MEM_READ_WRITE, high, NULL, &status);
  clReleaseMemObject(test);

  if (status != CL_SUCCESS) {
    high = low;
  } else {
    test = NULL;
  }
  //printf("Do not ignore openCL notifications after this line. \n");
  g_enable_notifications = true;

  if (test)
    if (CL_SUCCESS == clReleaseMemObject(test))
      test = NULL;

  maxAlloc_size = high;
  printf("Available max buffer size = %llu bytes.\n", maxAlloc_size);
  /************* Finished measuring maximum buffer size ******************** */

  return maxAlloc_size;
}
