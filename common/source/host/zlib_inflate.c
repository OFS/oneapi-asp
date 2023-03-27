// Copyright 2022 Intel Corporation
// SPDX-License-Identifier: MIT

/*
   based on downloaded zlib sample code that is public domain
   downloaded from https://zlib.net/zpipe.c
    6/27/17
*/

/* based on zpipe.c: example of proper use of zlib's inflate() and deflate()
   Not copyrighted -- provided to the public domain
   Version 1.4  11 December 2005  Mark Adler */

/* Version history:
   1.0  30 Oct 2004  First version
   1.1   8 Nov 2004  Add void casting for unused return values
                     Use switch statement for inflate() return values
   1.2   9 Nov 2004  Add assertions to document zlib guarantees
   1.3   6 Apr 2005  Remove incorrect assertion in inf()
   1.4  11 Dec 2005  Add hack to avoid MSDOS end-of-line conversions
                     Avoid some compiler warnings for input and output buffers
 */

#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "zlib.h"

#define CHUNK 16384
#define INITIAL_OUT_BUFFER_SIZE (32 * 1024 * 1024)

/** Decompress from file source to file dest until stream ends or EOF.
   inf() returns Z_OK on success, Z_MEM_ERROR if memory could not be
   allocated for processing, Z_DATA_ERROR if the deflate data is
   invalid or incomplete, Z_VERSION_ERROR if the version of zlib.h and
   the version of the library linked do not match, or Z_ERRNO if there
   is an error reading or writing the files. */
int inf(void *in_data, size_t in_size, void **out_data, size_t *out_size) {
  int ret;
  unsigned have;
  z_stream strm;
  unsigned char out[CHUNK];

  size_t remaining_buffer_size = in_size;
  unsigned char *in = in_data;
  size_t out_alloc_size = INITIAL_OUT_BUFFER_SIZE;

  assert(in_data);
  assert(in_size);
  assert(out_data);
  assert(out_size);

  *out_size = 0;

  *out_data = malloc(out_alloc_size);
  assert(*out_data);

  /* allocate inflate state */
  strm.zalloc = Z_NULL;
  strm.zfree = Z_NULL;
  strm.opaque = Z_NULL;
  strm.avail_in = 0;
  strm.next_in = Z_NULL;
  strm.total_in = 0;
  strm.total_out = 0;
  // notes from zlib.h
  // The default value is 15 if inflateInit is used
  // Add 32 to windowBits to enable zlib and gzip decoding with automatic header
  ret = inflateInit2(&strm, 15 + 32);
  if (ret != Z_OK)
    return ret;

  /* decompress until deflate stream ends or end of file */
  do {
    // strm.avail_in = fread(in, 1, CHUNK, source);
    if (remaining_buffer_size == 0) {
      (void)inflateEnd(&strm);
      return Z_ERRNO;
    }
    strm.avail_in = CHUNK;
    if (remaining_buffer_size < CHUNK)
      strm.avail_in = remaining_buffer_size;
    remaining_buffer_size -= strm.avail_in;

    if (strm.avail_in == 0)
      break;
    strm.next_in = in;

    /* run inflate() on input until output buffer not full */
    do {
      strm.avail_out = CHUNK;
      strm.next_out = out;
      ret = inflate(&strm, Z_NO_FLUSH);
      assert(ret != Z_STREAM_ERROR); /* state not clobbered */
      switch (ret) {
      case Z_NEED_DICT:
        ret = Z_DATA_ERROR; /* and fall through */
      case Z_DATA_ERROR:
      case Z_MEM_ERROR:
        (void)inflateEnd(&strm);
        return ret;
      }
      have = CHUNK - strm.avail_out;
      if (*out_size + have > out_alloc_size) {
        void *tmp = NULL;
        out_alloc_size *= 2;
        tmp = realloc(*out_data, out_alloc_size);
        if (tmp == NULL) {
          (void)inflateEnd(&strm);
          return Z_ERRNO;
        }
        *out_data = tmp;
      }
      memcpy(*out_data + *out_size, out, have);
      (*out_size) += have;
    } while (strm.avail_out == 0);

    in += CHUNK;
    /* done when inflate() says it's done */
  } while (ret != Z_STREAM_END);

  /* clean up and return */
  (void)inflateEnd(&strm);
  return ret == Z_STREAM_END ? Z_OK : Z_DATA_ERROR;
}
