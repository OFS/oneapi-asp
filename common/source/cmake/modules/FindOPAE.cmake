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

# - Try to find libintelfpga
# Once done, this will define
#
#  libopae-c_FOUND - system has libopae-c
#  libopae-c_INCLUDE_DIRS - the libopae-c include directories
#  libopae-c_LIBRARIES - link these to use libopae-c

find_package(PkgConfig)
pkg_check_modules(PC_OPAE QUIET opae-c)

# Use pkg-config to get hints about paths
execute_process(COMMAND pkg-config --cflags opae-c --silence-errors
  COMMAND cut -d I -f 2
  OUTPUT_VARIABLE OPAE-C_PKG_CONFIG_INCLUDE_DIRS)
set(OPAE-C_PKG_CONFIG_INCLUDE_DIRS "${OPAE-C_PKG_CONFIG_INCLUDE_DIRS}" CACHE STRING "Compiler flags for OPAE-C library")

# Include dir
find_path(libopae-c_INCLUDE_DIRS
  NAMES opae/fpga.h
  PATHS ${LIBOPAE-C_ROOT}/include
  NO_DEFAULT_PATH
  )

find_path(libopae-c_INCLUDE_DIRS
  NAMES opae/fpga.h
  PATHS ${LIBOPAE-C_ROOT}/include
  ${OPAE-C_PKG_CONFIG_INCLUDE_DIRS}
  /usr/local/include
  /usr/include
  ${CMAKE_EXTRA_INCLUDES})

# The library itself
find_library(libopae-c_LIBRARIES
  NAMES opae-c
  PATHS ${LIBOPAE-C_ROOT}/lib
  NO_DEFAULT_PATH
  )

find_library(libopae-c_LIBRARIES
  NAMES opae-c
  PATHS ${LIBOPAE-C_ROOT}/lib
  ${LIBOPAE-C_ROOT}/lib64
  /usr/local/lib
  /usr/lib
  /lib
  /usr/lib/x86_64-linux-gnu
  ${CMAKE_EXTRA_LIBS})

if(libopae-c_LIBRARIES AND libopae-c_INCLUDE_DIRS)
  set(libopae-c_FOUND true)
endif(libopae-c_LIBRARIES AND libopae-c_INCLUDE_DIRS)
