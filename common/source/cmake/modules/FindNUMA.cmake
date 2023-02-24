# Copyright 2020 Intel Corporation.
#
# THIS SOFTWARE MAY CONTAIN PREPRODUCTION CODE AND IS PROVIDED BY THE
# COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED
# WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR
# BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
# WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
# OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
# EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

# - Try to find libnuma
# Once done will define:
#
# libnuma_FOUND - system has libnuma
# libnuma_INCLUDE_DIRS - include directory with numa.h
# libnuma_LIBRARIES - link with this for libnuma

find_path(libnuma_INCLUDE_DIR
  NAMES numa.h
  PATHS
  ${LIBNUMA_ROOT}/include
  /usr/include

  # XXX: when compiling in arc libnuma may not be available
  /p/psg/swip/w/gsouther/shared/libs/libnuma/include
  /data/gsouther/shared/libs/libnuma/include
  )

find_library(libnuma_LIBRARIES
  NAMES numa
  PATHS
  ${LIBNUMA_ROOT}/lib
  ${LIBNUMA_ROOT}/lib64
  /usr/lib
  /usr/lib64

  # XXX: when compiling in arc libnuma may not be available
  /p/psg/swip/w/gsouther/shared/libs/libnuma/lib
  /data/gsouther/shared/libs/libnuma/lib
  )

if(libnuma_INCLUDE_DIR AND libnuma_LIBRARIES)
  set(libnuma_FOUND true)
endif(libnuma_INCLUDE_DIR AND libnuma_LIBRARIES)
