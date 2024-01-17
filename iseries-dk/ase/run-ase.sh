#!/bin/bash

# Copyright 2022 Intel Corporation
# SPDX-License-Identifier: MIT

echo "Start of run-ase.sh"

ASE_DIR_PATH="$(dirname "$(readlink -e "${BASH_SOURCE[0]}")")"

if [ -n "$OFS_ASP_ENV_DEBUG_SCRIPTS" ]; then
  set -x
fi

if [ "$#" -lt 2 ]; then
  echo "Usage: $0 <cl file> <board name>"
  exit 1
fi

this_design="$1"
this_design="$(readlink -f "$1")"
board_name="$2"
if echo "${board_name}" | grep -qw "iseries-dk"; then
    device="Agilex7"
else
    device="S10"
fi
this_is_oneapi_design=0

if [ -f "$this_design" ]; then
    echo "Found OpenCL .cl file $this_design"
elif [ -d "$this_design" ]; then
    echo "Found OneAPI Makefile at $this_design"
    this_is_oneapi_design=1
else
  echo "Error: cannot find: $this_design"
  exit 1
fi

# shellcheck source=setup.sh
source "$ASE_DIR_PATH/setup.sh" || exit

SIM_DIR="$(mktemp -d --tmpdir="$PWD" "ase_sim-${board_name}-XXXXXX")"

cd "$SIM_DIR" || exit

mkdir -p kernel
pushd kernel || exit
"$ASE_DIR_PATH/compile-kernel.sh" -b "$board_name" -d "$device" "$this_design" || exit
if [ "$this_is_oneapi_design" -eq "1" ]; then
    aocx_file="$(readlink -f "$(ls -1 ./*/*.aocx)")"
else
    aocx_file="$(readlink -f "$(ls -1 ./*.aocx)")"
fi
popd || exit

mkdir -p sim
pushd sim || exit
"$ASE_DIR_PATH/simulate-aocx.sh" "$aocx_file" "$board_name" || exit
echo "Starting simulation in: $PWD"
make sim

echo "------------------------------------------------------------------------"
echo "Simulation complete"
echo "Simulation directory: $SIM_DIR/sim"
echo "Run 'make sim' from the simulation directory to restart simulation if desired"
echo "------------------------------------------------------------------------"
