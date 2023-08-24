#!/bin/bash

## Copyright 2022 Intel Corporation
## SPDX-License-Identifier: MIT

###############################################################################
# Compile the boadtest.aocx file and copy it to the default aocx location.
# This script requies setup-bsp.py to execute successfully first to geneate
# the required files in BSP HW folder.
###############################################################################

if [ -n "$OFS_ASP_ENV_DEBUG_SCRIPTS" ]; then
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
BOARD=${BOARD:-all}
QDB_FILES="$(find $BSP_ROOT/hardware -name d5005.qdb)"
if [ -z "$QDB_FILES" ]; then
  echo "Error: cannot find required OFS FIM QDB files. Please set up the ASP first."
  exit 1
fi

if [ "$BOARD" == "all" ] ; then
    declare -a variant_list=("ofs_d5005" "ofs_d5005_usm")
else
    declare -a variant_list=("$BOARD")
fi
echo "Generating default aocx for board variant(s): ${variant_list[@]]}"

# Using the same hello_world.cl file for the default source
CL_FILE="bringup/source/hello_world/device/hello_world.cl"

# Check that BSP flow is valid
BSP_FLOW=${BSP_FLOW:-afu_flat}
if [[ ! "$BSP_FLOW" =~ afu_flat|afu_flat_kclk ]]; then
  echo "Invalid bsp-flow specified: $BSP_FLOW"
  exit 1
fi
echo "Using build flow: '$BSP_FLOW'"

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR" || exit

for this_variant in "${variant_list[@]]}"
do
    echo "---------------------------------------------------------------"
    echo "Starting default ${this_variant} aocx compile at: $(date)"
    echo -e "Using OpenCL version:\n$(aoc -version)\n"
    echo -e "Using Quartus version:\n$(quartus_sh --version)"
    echo "---------------------------------------------------------------"
    this_cmd="aoc -board-package="$BSP_ROOT" -no-env-check -bsp-flow="$BSP_FLOW" -board="$this_variant" -v -o "$this_variant" "$BSP_ROOT/$CL_FILE""
    #display the build cmd we'll run
    echo "Running this command: ${this_cmd}"
    #run the command
    $this_cmd
    echo "Finished aocx compile at: $(date)"
    
    if [ -f "$BUILD_DIR/${this_variant}.aocx" ]; then
        mkdir -p "$BSP_ROOT/bringup/aocxs"
        cp "$BUILD_DIR/${this_variant}.aocx" "$BSP_ROOT/bringup/aocxs/${this_variant}.aocx"
    else
        echo "Error failed to generate default aocx"
        exit 1
    fi
done
