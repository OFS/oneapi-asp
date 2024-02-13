#!/bin/bash

## Copyright 2022 Intel Corporation
## SPDX-License-Identifier: MIT

###############################################################################
# Compile the simple-add-buffers.fpga file and copy it to the default binary 
# location. This script requires setup-asp.py to execute successfully first to 
# generate the required files in ASP HW folder.
###############################################################################

if [ -n "$OFS_ASP_ENV_DEBUG_SCRIPTS" ]; then
  set -x
fi

SCRIPT_DIR_PATH="$(dirname "$(readlink -e "${BASH_SOURCE[0]}")")"
ASP_ROOT="$(readlink -e "$SCRIPT_DIR_PATH/..")"

BUILD_DIR="$ASP_ROOT/build/bringup"

while getopts ":b:f:h" arg; do
  case $arg in
    b) BOARD="$OPTARG"
    ;;
    f) ASP_FLOW="$OPTARG"
    ;;
    *) echo -e "usage: $0 [-b board-type] [-f asp-flow]\n"
       exit 1 ;;
  esac
done

# Check that board variant is configured
BOARD=${BOARD:-all}
QDB_FILES="$(find $ASP_ROOT/hardware -name *.qdb)"
if [ -z "$QDB_FILES" ]; then
  echo "Error: cannot find required OFS TOP QDB files. Please set up the ASP first."
  exit 1
fi

if [ "$BOARD" == "all" ] ; then
  variant_list=()
  for dir in $ASP_ROOT/hardware/*/ ; do
    variant_name=$(basename $dir)
    if [ "$variant_name" != "common" ]; then	  
      variant_list+=($variant_name)  
    fi  
  done
else
    declare -a variant_list=("$BOARD")
fi
echo "Generating default binaries for board variant(s): ${variant_list[@]}"

# Using the simple-add-buffers.cpp design for the default source
CPP_FILE="bringup/source/simple-add-buffers/simple-add-buffers.cpp"

# Check that ASP flow is valid
ASP_FLOW=${ASP_FLOW:-afu_flat}
if [[ ! "$ASP_FLOW" =~ afu_flat|afu_flat_kclk ]]; then
  echo "Invalid asp-flow specified: $ASP_FLOW"
  exit 1
fi
echo "Using build flow: '$ASP_FLOW'"

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR" || exit

for this_variant in "${variant_list[@]}"
do
    echo "---------------------------------------------------------------"
    echo "Starting default ${this_variant} binary compile at: $(date)"
    echo -e "Using oneAPI compiler version:\n$(icpx --version)\n"
    echo -e "Using Quartus version:\n$(quartus_sh --version)"
    echo "---------------------------------------------------------------"
    this_cmd="icpx -fsycl -fintelfpga -Xshardware -Xstarget="$ASP_ROOT":"$this_variant" -Xsbsp-flow="$ASP_FLOW" "$ASP_ROOT/$CPP_FILE" -DFPGA_HARDWARE -o "$this_variant".fpga"
    #display the build cmd we'll run
    echo "Running this command: ${this_cmd}"
    #run the command
    $this_cmd
    echo "Finished binary compile at: $(date)"
    
    if [ -f "$BUILD_DIR/${this_variant}.fpga" ]; then
        mkdir -p "$ASP_ROOT/bringup/binaries"
        cp "$BUILD_DIR/${this_variant}.fpga" "$ASP_ROOT/bringup/binaries/${this_variant}.fpga"
    else
        echo "Error failed to generate default binary"
        exit 1
    fi
done
