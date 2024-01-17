#!/bin/bash

# Copyright 2022 Intel Corporation
# SPDX-License-Identifier: MIT

if [ -n "$OFS_ASP_ENV_DEBUG_SCRIPTS" ]; then
  echo "Running ${BASH_SOURCE[0]} with debug logging"
  set -x
fi
set -e

if [ -e "$LIBOPAE_C_ROOT/../opae_src" ]; then
  echo "Error ASE environment not setup"
  exit 1
fi

if [[ -z "$ASE_SRC_PATH" ||  ! -e "$ASE_SRC_PATH"  ]]; then
  echo "Error: cannot find ASE_SRC_PATH: '$ASE_SRC_PATH'"
  exit 1
fi

# ASE simulation produces a lot of files. Recommend using a clean working
# directory before starting the simulation.
if [ $(ls -A $PWD) ]; then
  echo -n "Warning: working directory not empty. Are you sure you want to continue [y/N] "
  read answer
  if [ ! "$answer" == "y" ]; then
    echo "Exiting directory not empty"
    exit 1
  fi
fi


ASE_DIR_PATH="$(dirname "$(readlink -e "${BASH_SOURCE[0]}")")"
BSP_ROOT="$(readlink -e "$ASE_DIR_PATH/..")"

if [ "$#" -lt 2 ]; then
  echo "Usage: $0 <aocx file> <board name>"
  exit 1
fi

aocx_file="$1"
board_name="$2"

if [ ! -f "$aocx_file" ]; then
  echo "Error: cannot find aocx file $aocx_file"
  exit 1
fi

fpga_bin_path="fpga.bin"
aocl binedit "$aocx_file" get .acl.fpga.bin $fpga_bin_path

#uncompress and prepare modelsim files
tar -xf $fpga_bin_path

cp -r "$ASE_SRC_PATH"/* .
cp -rf "$BSP_ROOT"/ase/base/* .

# Construct dummy sources which we will feed to generate_ase_environment to
# build a simulation tree.
mkdir -p dummy_sources
touch dummy_sources/dummy_rtl_file.sv
touch dummy_sources/dummy_vhd_file.vhd
cp -rf "$BSP_ROOT/hardware/${board_name}/build/opencl_afu.json" dummy_sources/
ls -1 dummy_sources/* > dummy_sources.txt

################################################################################
# TODO: test using questa simulator. For Intel OFS EA only VCS has been tested
# Questa may work using the following options but likely requires some tuning.
#
# Parameters for QUESTA might be:
#TOOL_ARG="-t QUESTA"
#MTI_HOME must be set to modelsim_ae or Questa location
################################################################################

# VCS is only simulator tested for Intel OFS release
TOOL_ARG=(-t VCS)

# Generate a build tree. This will also generate the rules for building
# Quartus core simulation libraries for the appropriate technology.
scripts/generate_ase_environment.py "${TOOL_ARG[@]}" --source dummy_sources.txt

mkdir qsys_files
rm  -fr qsys_files/*

cp -R sim_files/* ./qsys_files
mkdir ./qsys_files_vhd
vhd_file_cnt=$(find . -maxdepth 1 -name '*.vhd' | wc -l)
echo > ./vhdl_files.list
echo ./qsys_files_vhd > ./vhdl_files.list
if [ "$vhd_file_cnt" -gt "0"  ]; then
    echo "vhd files exist, moving them into the qsys_files_vhd folder"
    ls qsys_files/*.vhd
    mv qsys_files/*.vhd ./qsys_files_vhd/
else
    echo "no vhd files exist, nothing to copy over"
fi

cp -prf vlog_files_base.list vlog_files.list

# Put package files first
{
  (find ./qsys_files | grep -v ./qsys_files/BBB_ | grep _pkg.sv | grep -v ofs_asp_pkg.sv)
  (find ./qsys_files | grep -v ./qsys_files/BBB_ | grep _interfaces.sv)
  (find ./qsys_files | grep -v ./qsys_files/BBB_ | grep -v _pkg.sv | grep -v _interfaces.sv) 
} >> ./vlog_files.list

#remove unwanted files (ones that shouldn't go through vlog)
sed -i '/.iv$/d' ./vlog_files.list
sed -i '/.vh$/d' ./vlog_files.list
sed -i '/.csv$/d' ./vlog_files.list
sed -i '/inst\.v$/d' ./vlog_files.list
sed -i '/.hex$/d' ./vlog_files.list

cp -prf "$ASE_DIR_PATH"/hack_ip_files/* ./qsys_files/
cp -prf "$ASE_DIR_PATH"/hack_ip_files/* ./sim_files/

OPAE_BASEDIR="$LIBOPAE_C_ROOT/../opae_src" make
cp ./*.hex ./work/

echo "########################################################################"
echo "Simulation setup complete. To start simulation run:"
echo "  make sim"
echo "########################################################################"
