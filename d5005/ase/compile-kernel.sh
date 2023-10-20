#!/bin/bash

# Copyright 2022 Intel Corporation
# SPDX-License-Identifier: MIT

ASE_DIR_PATH="$(dirname "$(readlink -e "${BASH_SOURCE[0]}")")"
BSP_ROOT="$(readlink -e "$ASE_DIR_PATH/..")"

if [ -n "$OFS_ASP_ENV_DEBUG_SCRIPTS" ]; then
  set -x
fi

if [ -z "$OFS_ASP_ENV_ENABLE_ASE" ]; then
  echo "Error: must setup ASE environment before compiling kernel"
  exit 1
fi 

function usage() {
  echo "Usage: $0 [-b board-type] <cl_file/path-to-OneAPI-Makefile>"
  exit 1
}

while getopts ":b:d:h" arg; do
  case $arg in
    b) BOARD="$OPTARG"
    ;;
    d) DEVICE="$OPTARG"
    ;;
    *) usage
  esac
done

shift $((OPTIND - 1))

if (($# == 0)); then
    usage
fi

DESIGN_SRC="$1"

echo "Running ASE for board variant: $BOARD, device: $OPTARG"

if [ -f "$DESIGN_SRC" ]; then
    echo "Running ASE with design: $DESIGN_SRC"
    echo "aoc command is next"
    aoc -v -board-package="$BSP_ROOT" -board="$BOARD" "$DESIGN_SRC"
elif [ -d "$DESIGN_SRC" ]; then
    echo "Running ASE with oneAPI design: $DESIGN_SRC"
    echo "pwd is  $PWD"
    mkdir -p ${BOARD} 
    echo "pwd is $PWD"
    cd ${BOARD}
    echo "pwd is $PWD, cmake is next"
    cmake "$DESIGN_SRC" -DFPGA_DEVICE=${OFS_ASP_ROOT}:${BOARD} -DIS_BSP=1
    echo "after cmake"
    make fpga
    echo "make fpga is done; break out the aocx file"
    FPGAFILE=`ls *.fpga`
    AOCXFILE=`echo $FPGAFILE | sed 's/fpga/aocx/g'`
    echo "FPGAFILE is $FPGAFILE"
    echo "AOCXFILE is $AOCXFILE"
    ${INTELFPGAOCLSDKROOT}/host/linux64/bin/aocl-extract-aocx -i $FPGAFILE -o $AOCXFILE
else
    echo "Error: cannot find: '$DESIGN_SRC'"
    exit 1
fi

echo "Done with compile-kernel.sh."
