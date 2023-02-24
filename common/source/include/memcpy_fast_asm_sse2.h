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

#ifndef MEMCPY_FAST_ASM_SSE2_H_
#define MEMCPY_FAST_ASM_SSE2_H_ 

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif // __cplusplus

// Constants needed in memcpy routines
// Arbitrary crossover point for using SSE2 over rep movsb
#define MIN_SSE2_SIZE 4096

// TODO: hidden environment variables to experiment with performance
// in production software are not a good idea in my opinion. Commenting out
// for now but hopefully can remove this code completely in the long term.
//#define USE_MEMCPY_ENV		"OFS_MEMCPY"

#define CACHE_LINE_SIZE 64
#define ALIGN_TO_CL(x) ((uint64_t)(x) & ~(CACHE_LINE_SIZE - 1))
#define IS_CL_ALIGNED(x) (((uint64_t)(x) & (CACHE_LINE_SIZE - 1)) == 0)

// Convenience macros
#if 0
#ifdef DEBUG_MEM
#define debug_print(fmt, ...)                                                  \
  do {                                                                         \
    if (FPGA_DMA_DEBUG) {                                                      \
      fprintf(stderr, "%s (%d) : ", __FUNCTION__, __LINE__);                   \
      fprintf(stderr, fmt, ##__VA_ARGS__);                                     \
    }                                                                          \
  } while (0)

#define error_print(fmt, ...)                                                  \
  do {                                                                         \
    fprintf(stderr, "%s (%d) : ", __FUNCTION__, __LINE__);                     \
    fprintf(stderr, fmt, ##__VA_ARGS__);                                       \
    err_cnt++;                                                                 \
  } while (0)
#else
#define debug_print(...)
#define error_print(...)
#endif
#endif

typedef void *(*memcpy_fn_t)(void *dst, size_t max, const void *src,
                             size_t len);

extern memcpy_fn_t p_memcpy;

#define memcpy_fast_asm_sse2(a, b, c, d) p_memcpy(a, b, c, d)

#ifdef __cplusplus
}
#endif // __cplusplus

#endif // MEMCPY_FAST_ASM_SSE2_H
