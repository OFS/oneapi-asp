// Copyright 2022 Intel Corporation
// SPDX-License-Identifier: MIT

#ifndef __ZLIB_DEFLATE_H__
#define __ZLIB_DEFLATE_H__

#ifdef __cplusplus
extern "C" {
#endif

// example
/*
ret = inf(in_data, in_size, &out_data, &out_size);
if (ret != Z_OK)
        //ERROR!
free(in_data);
free(out_data);
*/

int inf(void *in_data, size_t in_size, void **out_data, size_t *out_size);

#ifdef __cplusplus
}
#endif

#endif // __ZLIB_DEFLATE_H__
