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
# Compile the boadtest.aocx file and copy it to the default aocx location.
# This script requies setup-bsp.py to execute successfully first to geneate
# the required files in BSP HW folder.
###############################################################################

if [ -n "$OFS_OCL_ENV_DEBUG_SCRIPTS" ]; then
  set -x
fi

SCRIPT_DIR_PATH="$(dirname "$(readlink -e "${BASH_SOURCE[0]}")")"
BSP_ROOT="$(readlink -e "$SCRIPT_DIR_PATH/..")"

BUILD_DIR="$BSP_ROOT/build/bringup"

while getopts ":b:f:h" arg; do
  case $arg in
    b) BOARD="$OPTARG"
    ;;
    f) BSP_FLOW="$OPTARG"
    ;;
    *) echo -e "usage: $0 [-b board-type] [-f bsp-flow]\n"
       exit 1 ;;
  esac
done

# Check that board variant is configured
BOARD=${BOARD:-ofs_d5005}
if [ ! -f "$BSP_ROOT/hardware/$BOARD/build/d5005.qdb" ]; then
  echo "Error: cannot find required OFS FIM QDB file for board '$BOARD'"
  exit 1
fi
echo "Generating default aocx for board variant: $BOARD"

# Select cl file for building default aocx
case $BOARD in
  ofs_d5005)
    CL_FILE="bringup/source/boardtest/boardtest.cl"
    INTERLEAVE_OPTION="-no-interleaving=default"
    ;;
  ofs_d5005_usm)
    CL_FILE="bringup/source/mem_bandwidth_svm/device/mem_bandwidth_svm_ddr.cl"
    INTERLEAVE_OPTION="" 
    ;;
  *)
    echo "Error: invalid board type: $BOARD"
    exit 1
esac

# Check that BSP flow is valid
BSP_FLOW=${BSP_FLOW:-afu_flat}
if [[ ! "$BSP_FLOW" =~ afu_flat|afu_flat_kclk ]]; then
  echo "Invalid bsp-flow specified: $BSP_FLOW"
  exit 1
fi
echo "Using build flow: '$BSP_FLOW'"

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR" || exit

echo "---------------------------------------------------------------"
echo "Starting aocx compile at: $(date)"
echo -e "Using OpenCL version:\n$(aoc -version)\n"
echo -e "Using Quartus version:\n$(quartus_sh --version)"
echo "---------------------------------------------------------------"
echo -e "aoc -board-package="$BSP_ROOT" -bsp-flow="$BSP_FLOW" -board="$BOARD" "$INTERLEAVE_OPTION" -v -o "$BOARD" "$BSP_ROOT/$CL_FILE""
aoc -board-package="$BSP_ROOT" -bsp-flow="$BSP_FLOW" -board="$BOARD" "$INTERLEAVE_OPTION" -v -o "$BOARD" "$BSP_ROOT/$CL_FILE"
echo "Finished aocx compile at: $(date)"

if [ -f "$BUILD_DIR/${BOARD}.aocx" ]; then
  mkdir -p "$BSP_ROOT/bringup/aocxs"
  cp "$BUILD_DIR/${BOARD}.aocx" "$BSP_ROOT/bringup/aocxs/${BOARD}.aocx"
else
  echo "Error failed to generate default aocx"
  exit 1
fi
