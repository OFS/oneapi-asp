#!/bin/bash

## Copyright 2022 Intel Corporation
## SPDX-License-Identifier: MIT

###############################################################################
# Compile the boadtest.aocx file and copy it to the default aocx location.
# This script requies setup-bsp.py to execute successfully first to geneate
# the required files in BSP HW folder.
###############################################################################

if [ -n "$OFS_OCL_ENV_DEBUG_SCRIPTS" ]; then
  set -x
fi

SCRIPT_DIR_PATH="$(dirname "$(readlink -e "${BASH_SOURCE[0]}")")"

BOARD_VARIANT=$1
BOARD_FAMILY="${BOARD_VARIANT%%_*}"
shift

. $SCRIPT_DIR_PATH/set_variables.sh "$BOARD_FAMILY"
if [ $? -eq 1 ] ; then
  exit 1
fi

BUILD_DIR="$BSP_ROOT/build/bringup"

while getopts ":b:f:h" arg; do
  case $arg in
    # b) BOARD="$OPTARG"
    b) BOARD=""
    ;;
    f) BSP_FLOW="$OPTARG"
    ;;
    *) echo -e "usage: $0 [-b board-type] [-f bsp-flow]\n"
       exit 1 ;;
  esac
done

# Check that board variant is configured
BOARD=${BOARD:-"ofs_$BOARD_VARIANT"}
if [ ! -f "$BSP_ROOT/hardware/$BOARD/build/ofs_top.qdb" ]; then
  echo "Error: cannot find required OFS TOP QDB file for board '$BOARD'"
  exit 1
fi
echo "Generating default aocx for board variant: $BOARD"

# Select cl file for building default aocx

# TODO: Makes sense to set this b/c existance is checked above right?
if [ ! -f "$BSP_ROOT/bringup/source/hello_world/device/hello_world.cl" ] ; then
  echo "Error: cannot find $BSP_ROOT/bringup/source/hello_world/device/hello_world.cl"
  exit 1
fi
CL_FILE="bringup/source/hello_world/device/hello_world.cl"
INTERLEAVE_OPTION=""

# case $BOARD in
#   ofs_n6001)
#     CL_FILE="bringup/source/hello_world/device/hello_world.cl"
#     INTERLEAVE_OPTION=""
#     ;;
#   ofs_n6001_usm)
#     CL_FILE="bringup/source/hello_world/device/hello_world.cl"
#     INTERLEAVE_OPTION="" 
#     ;;
#   ofs_d5005)
#     CL_FILE="bringup/source/hello_world/device/hello_world.cl"
#     INTERLEAVE_OPTION=""
#     ;;
#   ofs_d5005_usm)
#     CL_FILE="bringup/source/hello_world/device/hello_world.cl"
#     INTERLEAVE_OPTION="" 
#     ;;
#   *)
#     echo "Error: invalid board type: $BOARD"
#     exit 1
# esac

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
