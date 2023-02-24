#ifndef ACLUTIL_H
#define ACLUTIL_H
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <math.h>
#include <limits.h>
// ACL specific includes
#include "CL/opencl.h"
#include "aclutil.h"
#include "timer.h"

// Allocate and free memory aligned to value that's good for
// Altera OpenCL performance.
void *acl_aligned_malloc (size_t size);
void  acl_aligned_free (void *ptr);
unsigned char* load_file(const char* filename, size_t*size_ret);
cl_ulong get_max_mem_alloc_size(cl_context context, cl_command_queue queue, cl_device_id device);
#endif
