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
