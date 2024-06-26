#!/bin/bash

## Copyright 2022 Intel Corporation
## SPDX-License-Identifier: MIT

###############################################################################
# Script for building MMD. If needed calls script to build OPAE dependency
#
# Global variables
#  SCRIPT_DIR_PATH: path to location of script
#  ASP_ROOT: path to root of ASP repo
#  BUILD_TYPE: type of build (i.e. release or debug)
#  BUILD_DIR: directory used for building MMD
#
# Required environment variables
#  INTELFPGAOCLSDKROOT: must be set by running setvars.sh script
#
# Optional environment varialbes
#  LIBOPAE_C_ROOT: path to OPAE installation
#  OFS_ASP_ENV_DEBUG_SCRIPTS: print script debugging information if set
###############################################################################

SCRIPT_DIR_PATH="$(dirname "$(readlink -e "${BASH_SOURCE[0]}")")"
ASP_ROOT="$(readlink -e "$SCRIPT_DIR_PATH/..")"

if [ -n "$OFS_ASP_ENV_DEBUG_SCRIPTS" ]; then
  set -x
fi

if [ -z "$LIBOPAE_C_ROOT" ]; then
  export LIBOPAE_C_ROOT="$ASP_ROOT/build/opae/install"
fi

if [ ! -d "$INTELFPGAOCLSDKROOT" ]; then
  echo "Error: must set INTELFPGAOCLSDKROOT using setvars.sh before building MMD"
  exit 1
fi

if [ -e "$ASP_ROOT/../../.gitmodules" ]; then
  (cd "$ASP_ROOT/../common/source/extra/" && git clone https://github.com/OPAE/intel-fpga-bbb.git)
fi

BUILD_PREFIX="$ASP_ROOT/build"
BUILD_TYPE=${OFS_ASP_ENV_MMD_BUILD_TYPE:-"release"}
SET_ASE="OFF"
if [ -n "$OFS_ASP_ENV_ENABLE_ASE" ]; then
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

CMAKE_ASP_AFU_ID_ARG="-DASP_AFU_ID=N6001"

export CC=${CC:-$(which gcc)}
export CXX=${CXX:-$(which g++)}
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$ASP_ROOT/build/json-c/install/lib64
cmake -DCMAKE_BUILD_TYPE="$BUILD_TYPE" -DOPENCL_ASE_SIM="$SET_ASE" -DCMAKE_INSTALL_PREFIX="$ASP_ROOT/linux64" "$CMAKE_OPAE_ARG" "$CMAKE_ASP_AFU_ID_ARG" "$ASP_ROOT/../common/source" || exit
make install
