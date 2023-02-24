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

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "aocl_mmd.h"
#include "mmd.h"

/* given filename, load its content into memory.
 * Returns file size in file_size_out ptr and ptr to buffer (allocated
 * with malloc() by this function that contains the content of the file.*/
unsigned char *acl_loadFileIntoMemory(const char *in_file,
                                      size_t *file_size_out) {

  FILE *f = NULL;
  unsigned char *buf;
  size_t file_size;

  // When reading as binary file, no new-line translation is done.
  f = fopen(in_file, "rb");
  if (f == NULL) {
    fprintf(stderr, "Couldn't open file %s for reading\n", in_file);
    return NULL;
  }

  // get file size
  fseek(f, 0, SEEK_END);
  file_size = (size_t)ftell(f);
  rewind(f);

  // slurp the whole file into allocated buf
  buf = (unsigned char *)malloc(sizeof(char) * file_size);
  if (!buf) {
    fprintf(stderr, "Error cannot allocate memory\n");
    exit(-1);
  }
  *file_size_out = fread(buf, sizeof(char), file_size, f);
  fclose(f);

  if (*file_size_out != file_size) {
    fprintf(stderr, "Error reading %s. Read only %lu out of %lu bytes\n",
            in_file, *file_size_out, file_size);
    free(buf);
    return NULL;
  }
  return buf;
}

int main(int argc, char **argv) {

  char *device_name = NULL;
  char *aocx_filename_from_cmd = NULL;

  unsigned char *aocx_file = NULL;
  size_t aocx_filesize;

  if (argc != 4) {
    printf("Error: Invalid number of arguments.\n");
    return 1;
  }

  // The 'aocl' command passes the device_name in argv[1] and the aocx filename
  // in argv[3]. It also passed the fpga_bin filename in argv[2] which is not
  // used by DCP
  device_name = argv[1];
  aocx_filename_from_cmd = argv[3];

  aocx_file = acl_loadFileIntoMemory(aocx_filename_from_cmd, &aocx_filesize);
  if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : Loading aocx file in memory using acl_loadFileIntoMemory() \n");
  }
  if (aocx_file == NULL) {
    printf("Error: Failed to find aocx\n");
    exit(-1);
  }

  if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : Entering mmd_device_reprogram()\n");
  }

  int res = mmd_device_reprogram(device_name, aocx_file, aocx_filesize);
  if (res > 0) {
    printf("Program succeed. \n");
    if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : mmd_device_reprogram() was successful. Program succeed.\n");
    }
    return 0;
  } else {
    printf("Error programming device.\n");
    if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : mmd_device_reprogram() was unsuccessful. Error programming device.\n");
    }
    return 1;
  }
}
