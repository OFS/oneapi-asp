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
# Compile the nightly test kernels for non-USM and USM board variants.
#   Set the OFS_OPENCL_BSP_TESTS environment variable to point to the kernels.
# This script requires setup-bsp.py to execute successfully first to generate
# the required files in BSP HW folder.
###############################################################################

#folder names will be build/bringup/<seed>/<board>/kernel

if [ -n "$OFS_OCL_ENV_DEBUG_SCRIPTS" ]; then
  set -x
fi

SCRIPT_DIR_PATH="$(dirname "$(readlink -e "${BASH_SOURCE[0]}")")"
BSP_ROOT="$(readlink -e "$SCRIPT_DIR_PATH/../..")"

#set up OpenCL test designs
if [ -z "$OFS_OPENCL_BSP_TESTS_PATH" ]; then
    BUILD_DIR="$BSP_ROOT/build"
    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR" || exit
    if [ ! -d "$BUILD_DIR/ofs-opencl-bsp-tests" ]; then
        echo "OFS_OPENCL_BSP_TESTS_PATH environment variable doesn't exist. Cloning it here: $BUILD_DIR."
        git clone https://github.com/intel-innersource/applications.fpga.ofs.high-level-design-shim.tests.git ofs-opencl-bsp-tests
    else
        echo "$BUILD_DIR/ofs-opencl-bsp-tests exists - using it as-is. Be sure the current state of the repo is how you want it to be."
    fi
    export OFS_OPENCL_BSP_TESTS_PATH="$BUILD_DIR/ofs-opencl-bsp-tests"
fi

#set up oneAPI test designs
if [ -z "$ONEAPI_SAMPLES_PATH" ]; then
    BUILD_DIR="$BSP_ROOT/build"
    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR" || exit
    if [ ! -d "$BUILD_DIR/oneAPI-samples" ]; then
        echo "ONEAPI_SAMPLES_PATH environment variable doesn't exist. Cloning it here: $BUILD_DIR."
        git clone https://github.com/oneapi-src/oneAPI-samples
    else
        echo "$BUILD_DIR/oneAPI-samples exists - using it as-is. Be sure the current state of the repo is how you want it to be."
    fi
    export ONEAPI_SAMPLES_PATH="$BUILD_DIR/oneAPI-samples"
fi

SEEDS="1"
FIRST_SEED="1"
BSP_FLOW="afu_flat"
BRINGUP_DIR_PATH="${BSP_ROOT}/build/bringup"
mkdir -p "${BRINGUP_DIR_PATH}"

while getopts ":b:f:s:h" arg; do
  case $arg in
    f) BSP_FLOW="$OPTARG"
    ;;
    s) SEEDS="$OPTARG"
    ;;
    *) echo -e "usage: $0 [-b board-type] [-f bsp-flow]\n"
       exit 1 ;;
  esac
done

NONUSM_BOARD="ofs_n6001"
USM_BOARD="ofs_n6001_usm"

# Check that board variant is configured
FAIL_CHECK="0"
if [ ! -f "$BSP_ROOT/hardware/$NONUSM_BOARD/build/ofs_top.qdb" ]; then
  echo "Error: cannot find required OFS FIM QDB file for board '$NONUSM_BOARD'"
  FAIL_CHECK="1"
fi
if [ ! -f "$BSP_ROOT/hardware/$USM_BOARD/build/ofs_top.qdb" ]; then
  echo "Error: cannot find required OFS FIM QDB file for board '$USM_BOARD'"
  FAIL_CHECK="1"
fi

if [ "$FAIL_CHECK" -eq 1 ]; then
    exit 1
else
    echo "Generating nightly-test aocxs for board variant: $NONUSM_BOARD"
    echo "Generating nightly-test aocxs for board variant: $USM_BOARD"
fi

# set cl files to build
CL_FILES="hello_world \
boardtest \
mem_bandwidth \
memspeed \
vector_add \
mem_bandwidth_svm_ddr"

MEMSPEED_ARGS="-no-interleaving=default"
BOARDTEST_ARGS="-no-interleaving=default"

# Check that BSP flow is valid
if [[ ! "$BSP_FLOW" =~ afu_flat|afu_flat_kclk ]]; then
  echo "Invalid bsp-flow specified: $BSP_FLOW"
  exit 1
fi
echo "Using build flow: '$BSP_FLOW'"

echo "Building the kernels here: $BRINGUP_DIR_PATH"
echo "Looking here for test kernels: ${OFS_OPENCL_BSP_TESTS_PATH}"
echo "The kernel-list is $CL_FILES"
SEED_CNT=0
THIS_SEED=$FIRST_SEED

while [ "$SEED_CNT" -lt "$SEEDS" ]
do
    BUILD_BASE_DIR="${BRINGUP_DIR_PATH}/seed-${THIS_SEED}-${BSP_FLOW}"
    echo "BUILD_BASE_DIR is ${BUILD_BASE_DIR}"
    if [ -d "${BUILD_BASE_DIR}" ]; then
        echo "${BUILD_BASE_DIR} already exists. Change the seed or delete the existing directory."
        exit 1
    fi
    mkdir "$BUILD_BASE_DIR"
    cd "$BUILD_BASE_DIR" || exit
    
    BUILD_DIR="${BUILD_BASE_DIR}/$NONUSM_BOARD"
    echo "BUILD_DIR is ${BUILD_DIR}"
    if [ -d "${BUILD_DIR}" ]; then
        echo "${BUILD_DIR} already exists. Change the seed or delete the existing directory."
        exit 1
    fi
    mkdir "$BUILD_DIR"
    cd "$BUILD_DIR" || exit
    
    BUILD_USM_DIR="${BUILD_BASE_DIR}/$USM_BOARD"
    echo "BUILD_USM_DIR is ${BUILD_USM_DIR}"
    if [ -d "${BUILD_USM_DIR}" ]; then
        echo "${BUILD_USM_DIR} already exists. Change the seed or delete the existing directory."
        exit 1
    fi
    mkdir "$BUILD_USM_DIR"
    cd "$BUILD_USM_DIR" || exit
    
    for i in $CL_FILES; do
        THIS_KERNEL_FILENAME="${i}.cl"
        THIS_KERNEL=`find ${OFS_OPENCL_BSP_TESTS_PATH} -name ${THIS_KERNEL_FILENAME} | grep -m1 .`
        
        if [ ! -f "$THIS_KERNEL" ]; then
            echo "Can't find the kernel here: $THIS_KERNEL. Skipping to the next kernel."
            continue
        fi
        if [ "${i}" == "mem_bandwidth_svm_ddr" ]; then
            THIS_KERNEL_BUILD_DIR="${BUILD_USM_DIR}/${i}"
            BOARD="$USM_BOARD"
        else
            THIS_KERNEL_BUILD_DIR="${BUILD_DIR}/${i}"
            BOARD="$NONUSM_BOARD"
        fi
        if [ -d "${THIS_KERNEL_BUILD_DIR}" ]; then
            echo "${THIS_KERNEL_BUILD_DIR} already exists. Change the seed or delete the existing directory."
            exit 1
        fi
        mkdir ${THIS_KERNEL_BUILD_DIR}
        cd ${THIS_KERNEL_BUILD_DIR}
        
        if [ "$i" == "boardtest" ]; then
            EXTRA_ARGS_CMD="$BOARDTEST_ARGS"
        elif [ "$i" == "memspeed" ]; then
            EXTRA_ARGS_CMD="$MEMSPEED_ARGS"
        else
            EXTRA_ARGS_CMD=""
        fi
        
        echo "Building kernel ${THIS_KERNEL}."
        echo "Build location: ${THIS_KERNEL_BUILD_DIR}"
        
        echo "---------------------------------------------------------------"
        echo "Starting compilation of kernel ${i} at: $(date)"
        echo -e "Using OpenCL version:\n$(aoc -version)\n"
        echo -e "Using Quartus version:\n$(quartus_sh --version)"
        echo "---------------------------------------------------------------"
        AOC_CMD="OFS_ASP_ROOT=$OFS_ASP_ROOT AOCL_BOARD_PACKAGE_ROOT=$AOCL_BOARD_PACKAGE_ROOT PYTHONPATH=$AOCL_BOARD_PACKAGE_ROOT/build/opae/install/lib/python3.8/site-packages aoc -no-env-check $EXTRA_ARGS_CMD -board-package=$BSP_ROOT -bsp-flow=$BSP_FLOW -board=$BOARD -v  $THIS_KERNEL -seed=$THIS_SEED"
        echo "The ARC command will be $AOC_CMD"
        arc submit node/"[memory>=32000]" priority=61 -- $AOC_CMD
        echo "Submitted build of ${i} to ARC."
        echo
    done
    ((SEED_CNT=SEED_CNT+1))
    ((THIS_SEED=THIS_SEED+1))
done
