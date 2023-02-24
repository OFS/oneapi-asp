#!/bin/bash

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

###############################################################################
# Script for building MMD. If needed calls script to build OPAE dependency
#
# Global variables
#  SCRIPT_DIR_PATH: path to location of script
#  BSP_ROOT: path to root of BSP repo
#  BUILD_TYPE: type of build (i.e. release or debug)
#  BUILD_DIR: directory used for building MMD
#
# Required environment variables
#  INTELFPGAOCLSDKROOT: must be set by running init_opencl.sh script
#
# Optional environment varialbes
#  LIBOPAE_C_ROOT: path to OPAE installation
#  OFS_OCL_ENV_DEBUG_SCRIPTS: print script debugging information if set
###############################################################################

SCRIPT_DIR_PATH="$(dirname "$(readlink -e "${BASH_SOURCE[0]}")")"
BSP_ROOT="$(readlink -e "$SCRIPT_DIR_PATH/..")"

# Copying source files from common
#copy_delete_list=(cmake CMakeLists.txt CODING_STYLE.txt host include util)
#for item in "${copy_delete_list[@]}"
#  do
#	echo $item
#     cp -r -n "$BSP_ROOT/../common/source/$item" "$BSP_ROOT/source/$item"
#  done
#cp -r -n $BSP_ROOT../common/source/* source/.

if [ -n "$OFS_OCL_ENV_DEBUG_SCRIPTS" ]; then
  set -x
fi

export LIBOPAE_C_ROOT="$BSP_ROOT/build/opae/install"

if [ ! -d "$INTELFPGAOCLSDKROOT" ]; then
  echo "Error: must set INTELFPGAOCLSDKROOT using init_opencl.sh before building MMD"
  exit 1
fi

if [ -e "$BSP_ROOT/../.gitmodules" ]; then
  (cd "$BSP_ROOT/.." && git submodule update --init common/source/extra/intel-fpga-bbb)
fi

BUILD_PREFIX="$BSP_ROOT/build"
BUILD_TYPE=${OFS_OCL_ENV_MMD_BUILD_TYPE:-"release"}
SET_ASE="OFF"
if [ -n "$OFS_OCL_ENV_ENABLE_ASE" ]; then
  SET_ASE="ON"
  BUILD_DIR="$BUILD_PREFIX/ase-${BUILD_TYPE}"
else
  BUILD_DIR="$BUILD_PREFIX/$BUILD_TYPE"
fi

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR" || exit

if [ -n "$LIBOPAE_C_ROOT" ]; then
  CMAKE_OPAE_ARG="-DLIBOPAE-C_ROOT:PATH=$LIBOPAE_C_ROOT"
else
  CMAKE_OPAE_ARG=""
fi

CMAKE_OCL_BSP_AFU_ID_ARG="-DOCL_BSP_AFU_ID=N6001"

export CC=${CC:-$(which gcc)}
export CXX=${CXX:-$(which g++)}
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$BSP_ROOT/build/json-c/install/lib64
cmake -DCMAKE_BUILD_TYPE="$BUILD_TYPE" -DOPENCL_ASE_SIM="$SET_ASE" -DCMAKE_INSTALL_PREFIX="$BSP_ROOT/linux64" "$CMAKE_OPAE_ARG" "$CMAKE_OCL_BSP_AFU_ID_ARG" "$BSP_ROOT/../common/source" || exit
make install
