#!/bin/bash

# Copyright 2022 Intel Corporation
# SPDX-License-Identifier: MIT

ASE_DIR_PATH="$(dirname "$(readlink -e "${BASH_SOURCE[0]}")")"
BSP_ROOT="$(readlink -e "$ASE_DIR_PATH/..")"

if [ -n "$OFS_OCL_ENV_DEBUG_SCRIPTS" ]; then
  set -x
fi

if [ -z "$OFS_OCL_ENV_ENABLE_ASE" ]; then
  echo "Error: must setup ASE environment before compiling kernel"
  exit 1
fi 

function usage() {
  echo "Usage: $0 [-b board-type] <cl_file/path-to-OneAPI-Makefile>"
  exit 1
}

while getopts ":b:h" arg; do
  case $arg in
    b) BOARD="$OPTARG"
    ;;
    *) usage
  esac
done

shift $((OPTIND - 1))

if (($# == 0)); then
  usage
fi

DESIGN_SRC="$1"

# Check that board variant is valid
BOARD=${BOARD:-ofs_n6001}
if [ ! -f "$BSP_ROOT/hardware/$BOARD/build/ofs_top.qdb" ]; then
  echo "Error: cannot find required OFS FIM QDB file for board '$BOARD'"
  echo "Error: $BSP_ROOT/hardware/$BOARD/build/ofs_top.qdb does not exist. You must build the BSP first."
  exit 1
fi
echo "Running ASE for board variant: $BOARD"

if [ -f "$DESIGN_SRC" ]; then
    echo "Running ASE with design: $DESIGN_SRC"
    echo "aoc command is next"
    aoc -v -no-env-check  -board-package="$BSP_ROOT" -board="$BOARD" "$DESIGN_SRC"
elif [ -d "$DESIGN_SRC" ]; then
    echo "Running ASE with oneAPI design: $DESIGN_SRC"
    echo "pwd is  $PWD"
    mkdir -p n6001
    echo "pwd is $PWD"
    cd n6001
    echo "pwd is $PWD, cmake is next"
    export USM_TAIL=""
    if [ ${BOARD} == "ofs_n6001_usm" ]; then
        export USM_TAIL="_usm"
    fi
    export BOARD_TYPE=pac_a10${USM_TAIL}
    cmake "$DESIGN_SRC" -DFPGA_DEVICE=${BOARD_TYPE}
    echo "after cmake"
    sed -i "s/$BOARD_TYPE/$BOARD/g" src/CMakeFiles/*/link.txt
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
