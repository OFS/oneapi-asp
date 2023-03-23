// Copyright 2022 Intel Corporation
// SPDX-License-Identifier: MIT

#ifdef __cplusplus
extern "C" {
#endif

void *acl_util_aligned_malloc(size_t size);
void acl_util_aligned_free(void *ptr);

#ifdef __cplusplus
}
#endif
