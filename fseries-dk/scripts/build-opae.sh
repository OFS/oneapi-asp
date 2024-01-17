#!/bin/bash

## Copyright 2022 Intel Corporation
## SPDX-License-Identifier: MIT

###############################################################################
# Script to build OPAE.
# Clones and builds OPAE and installs to build directory in ASP repo.
#
# Environment variables used in script:
#
# OFS_ASP_ENV_FIND_ROOT: used to specify alternate root location to look
#  for dependencies.
###############################################################################

###############################################################################


if [ -n "$OFS_ASP_ENV_DEBUG_SCRIPTS" ]; then
  set -x
fi

SCRIPT_DIR_PATH="$(dirname "$(readlink -e "${BASH_SOURCE[0]}")")"
BSP_ROOT="$(readlink -e "$SCRIPT_DIR_PATH/..")"

#clone and build json-c
JSONC_BUILD_PREFIX="$BSP_ROOT/build/json-c"
JSONC_BUILD_DIR="$JSONC_BUILD_PREFIX/build"
JSONC_INSTALL_DIR="$JSONC_BUILD_PREFIX/install"
# default json-c repo address
if [ -z "${JSON_C_REPO}" ]; then
    JSON_C_REPO="https://github.com/json-c/json-c.git"
fi
# Default branch to 'master' if the branch variable is not set
if [ -z "${JSON_C_REPO_BRANCH}" ]; then
    JSON_C_REPO_BRANCH="master"
fi
# Default location to clone is $BUILD_PREFIX/json-c
if [ -z "${JSON_C_PATH}" ]; then
    JSON_C_PATH="${JSONC_BUILD_PREFIX}/json-c"
fi

mkdir -p "$JSONC_BUILD_PREFIX"
cd "$JSONC_BUILD_PREFIX" || exit

echo "Cloning repo..."
# clone json-c repo
if [ ! -d "$JSONC_BUILD_PREFIX/json-c" ]; then
    (set -x; git clone -b "${JSON_C_REPO_BRANCH}" "${JSON_C_REPO}" "${JSON_C_PATH}")
else
   echo "Skipping cloning json-c. Directory exists: ${JSON_C_PATH}"
fi

mkdir -p "$JSONC_BUILD_DIR" || exit
mkdir -p "$JSONC_INSTALL_DIR" || exit

cd "$JSONC_BUILD_DIR" || exit
cmake -D CMAKE_INSTALL_PREFIX="$JSONC_INSTALL_DIR" ../json-c
make install
export OFS_ASP_ENV_FIND_ROOT=$OFS_ASP_ENV_FIND_ROOT:$JSONC_INSTALL_DIR
export PKG_CONFIG_PATH=$OFS_ASP_ENV_FIND_ROOT/lib64/pkgconfig:$PKG_CONFIG_PATH
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$OFS_ASP_ENV_FIND_ROOT/lib64
export CPLUS_INCLUDE_PATH=$CPLUS_INCLUDE_PATH:$OFS_ASP_ENV_FIND_ROOT/include
export C_INCLUDE_PATH=$C_INCLUDE_PATH:$OFS_ASP_ENV_FIND_ROOT/include

#done with json-c; now build OPAE

OPAESDK_BUILD_PREFIX="$BSP_ROOT/build/opae"
OPAESDK_BUILD_DIR="$OPAESDK_BUILD_PREFIX/build"
OPAESDK_INSTALL_DIR="$OPAESDK_BUILD_PREFIX/install"

# default opae-sdk repo address
if [ -z "${OPAE_SDK_REPO}" ]; then
    OPAE_SDK_REPO="https://github.com/OPAE/opae-sdk"
fi

# Default branch to 'master' if the branch variable is not set
if [ -z "${OPAE_SDK_REPO_BRANCH}" ]; then
    OPAE_SDK_REPO_BRANCH="master"
fi

# Default location to clone is $OPAESDK_BUILD_PREFIX/opae-sdk
if [ -z "${OPAE_SDK_PATH}" ]; then
    OPAE_SDK_PATH="${OPAESDK_BUILD_PREFIX}/opae-sdk"
fi

mkdir -p "$OPAESDK_BUILD_PREFIX"
cd "$OPAESDK_BUILD_PREFIX" || exit

echo "Cloning repo..."
# clone opae-sdk repo
if [ ! -d "$OPAESDK_BUILD_PREFIX/opae-sdk" ]; then
    (set -x; git clone -b "${OPAE_SDK_REPO_BRANCH}" "${OPAE_SDK_REPO}" "${OPAE_SDK_PATH}")
else
   echo "Skipping cloning opae-sdk. Directory exists: ${OPAE_SDK_PATH}"
fi

mkdir -p "$OPAESDK_BUILD_DIR" || exit
mkdir -p "$OPAESDK_INSTALL_DIR" || exit

cd "$OPAESDK_BUILD_DIR" || exit

if [ -n "$OFS_ASP_ENV_FIND_ROOT" ]; then
  CMAKE_FIND_ROOT_ARG="-DCMAKE_FIND_ROOT_PATH=$OFS_ASP_ENV_FIND_ROOT"
  echo "Using CMAKE_FIND_ROOT_PATH: $OFS_ASP_ENV_FIND_ROOT"
  echo "Using PKG_CONFIG_PATH: $PKG_CONFIG_PATH"
fi

CMAKE_PREFIX_PATH="$JSONC_INSTALL_DIR" cmake "$CMAKE_FIND_ROOT_ARG" -DOPAE_WITH_TBB=OFF -DCMAKE_INSTALL_PREFIX="$OPAESDK_INSTALL_DIR" -DCMAKE_C_COMPILER=gcc -DOPAE_BUILD_SAMPLES=no "$OPAESDK_BUILD_PREFIX/opae-sdk" || exit
make install

if [ -n "$OFS_ASP_ENV_ENABLE_ASE" ]; then
    echo "ASE is enabled - clone and build opae-sim"
    #clone and build opae-sim
    OPAESIM_BUILD_PREFIX="$BSP_ROOT/build/opae-sim"
    OPAESIM_BUILD_DIR="$OPAESIM_BUILD_PREFIX/build"
    OPAESIM_INSTALL_DIR="$OPAESIM_BUILD_PREFIX/install"
    # default opae-sim repo address
    if [ -z "${OPAESIM_REPO}" ]; then
        OPAESIM_REPO="https://github.com/OFS/opae-sim.git"
    fi
    # Default branch to 'master' if the branch variable is not set
    if [ -z "${OPAESIM_REPO_BRANCH}" ]; then
        OPAESIM_REPO_BRANCH="release/2.5.0"
    fi
    # Default location to clone is $BUILD_PREFIX/opae-sim
    if [ -z "${OPAESIM_PATH}" ]; then
        OPAESIM_PATH="${OPAESIM_BUILD_PREFIX}/opae-sim"
    fi

    mkdir -p "$OPAESIM_BUILD_PREFIX"
    cd "$OPAESIM_BUILD_PREFIX" || exit

    echo "Cloning repo..."
    # clone opae-sim repo
    if [ ! -d "$OPAESIM_PATH" ]; then
        (set -x; git clone -b "${OPAESIM_REPO_BRANCH}" "${OPAESIM_REPO}" "${OPAESIM_PATH}")
    else
        echo "Skipping cloning opae-sim. Directory exists: ${OPAESIM_PATH}"
    fi

    mkdir -p "$OPAESIM_BUILD_DIR" || exit
    mkdir -p "$OPAESIM_INSTALL_DIR" || exit

    cd "$OPAESIM_BUILD_DIR" || exit
    CMAKE_PREFIX_PATH="$OPAESDK_INSTALL_DIR" cmake -DLIBJSON-C_ROOT="$JSONC_INSTALL_DIR" -DCMAKE_INSTALL_PREFIX="$OPAESIM_INSTALL_DIR" ../opae-sim
    make install
    export OFS_ASP_ENV_FIND_ROOT=$OFS_ASP_ENV_FIND_ROOT:$OPAESIM_INSTALL_DIR
    export PKG_CONFIG_PATH=$OFS_ASP_ENV_FIND_ROOT/lib64/pkgconfig:$PKG_CONFIG_PATH
    export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$OFS_ASP_ENV_FIND_ROOT/lib64
    export CPLUS_INCLUDE_PATH=$CPLUS_INCLUDE_PATH:$OFS_ASP_ENV_FIND_ROOT/include
    export C_INCLUDE_PATH=$C_INCLUDE_PATH:$OFS_ASP_ENV_FIND_ROOT/include
    
fi
    
