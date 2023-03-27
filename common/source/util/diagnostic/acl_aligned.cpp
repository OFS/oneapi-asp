// Copyright 2022 Intel Corporation
// SPDX-License-Identifier: MIT

#ifdef __cplusplus
extern "C" {
#endif

// Min good alignment for DMA
#define ACL_ALIGNMENT 64

#ifdef LINUX
#include <stdio.h>
#include <stdlib.h>
void *acl_util_aligned_malloc(size_t size) {
  void *result = NULL;
  int res = posix_memalign(&result, ACL_ALIGNMENT, size);
  if (res) {
    fprintf(stderr, "Error: memory allocation failed: %d\n", res);
  }
  return result;
}
void acl_util_aligned_free(void *ptr) { free(ptr); }

#else // WINDOWS

#include <malloc.h>

void *acl_util_aligned_malloc(size_t size) {
  return _aligned_malloc(size, ACL_ALIGNMENT);
}
void acl_util_aligned_free(void *ptr) { _aligned_free(ptr); }

#endif // LINUX

#ifdef __cplusplus
}
#endif
