#!/bin/bash

## Copyright 2022 Intel Corporation
## SPDX-License-Identifier: MIT

###############################################################################
# Compile the simple-add-buffers.fpga file and copy it to the default binary location.
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
QDB_FILES="$(find $BSP_ROOT/hardware -name ofs_top.qdb)"
if [ -z "$QDB_FILES" ]; then
  echo "Error: cannot find required OFS TOP QDB files. Please set up the ASP first."
  exit 1
fi

if [ "$BOARD" == "all" ] ; then
    declare -a variant_list=("ofs_fseries_dk" "ofs_fseries_dk_iopipes" "ofs_fseries_dk_usm" "ofs_fseries_dk_usm_iopipes")
else
    declare -a variant_list=("$BOARD")
fi
echo "Generating default binaries for board variant(s): ${variant_list[@]}"

# Using the simple-add-buffers.cpp design for the default source
CPP_FILE="bringup/source/simple-add-buffers/simple-add-buffers.cpp"

# Check that BSP flow is valid
BSP_FLOW=${BSP_FLOW:-afu_flat}
if [[ ! "$BSP_FLOW" =~ afu_flat|afu_flat_kclk ]]; then
  echo "Invalid bsp-flow specified: $BSP_FLOW"
  exit 1
fi
echo "Using build flow: '$BSP_FLOW'"

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR" || exit

for this_variant in "${variant_list[@]}"
do
    echo "---------------------------------------------------------------"
    echo "Starting default ${this_variant} binary compile at: $(date)"
    echo -e "Using oneAPI compiler version:\n$(icpx --version)\n"
    echo -e "Using Quartus version:\n$(quartus_sh --version)"
    echo "---------------------------------------------------------------"
    this_cmd="icpx -fsycl -fintelfpga -Xshardware -Xsboard-package="$BSP_ROOT" -Xstarget="$this_variant" -Xsbsp-flow="$BSP_FLOW" -Xsno-interleaving=default "$BSP_ROOT/$CPP_FILE" -o "$this_variant".fpga"
    #display the build cmd we'll run
    echo "Running this command: ${this_cmd}"
    #run the command
    $this_cmd
    echo "Finished binary compile at: $(date)"
    
    if [ -f "$BUILD_DIR/${this_variant}.fpga" ]; then
        mkdir -p "$BSP_ROOT/bringup/binaries"
        cp "$BUILD_DIR/${this_variant}.fpga" "$BSP_ROOT/bringup/binaries/${this_variant}.fpga"
    else
        echo "Error failed to generate default binary"
        exit 1
    fi
done
