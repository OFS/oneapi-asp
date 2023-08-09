#!/bin/bash

## Copyright 2022 Intel Corporation
## SPDX-License-Identifier: MIT

###############################################################################
# Script to generate BSP based on current repoistory state. Script will
# clone required respositories and build OPAE if needed.  
#
# Global variables in scripts:
# - Environment variables used as input to control script behvaior
#
#   OFS_PLATFORM_AFU_BBB: root of OFS platform used for BSP
#   LIBOPAE_C_ROOT: path to location where OPAE is installed
#   OPENCL_ASE_SIM: used as input for setup-bsp.py to determine if ASE is used
#   OPAE_PLATFORM_ROOT: point to location where platform files are located
#   ARC_SITE: only set for Intel PSG compute farm
#
# - Variables used within script
#
#   SCRIPT_DIR_PATH: path to location of script
#   BSP_ROOT: path to root of BSP repository
#   OFS_PLATFORM_AFU_BBB: path to ofs-platform-afu-bbb repository
###############################################################################

if [ -n "$OFS_OCL_ENV_DEBUG_SCRIPTS" ]; then
  echo "Running ${BASH_SOURCE[0]} with debug logging"
  set -x
fi

SCRIPT_DIR_PATH="$(dirname "$(readlink -e "${BASH_SOURCE[0]}")")"

. $SCRIPT_DIR_PATH/set_variables.sh "$1"
if [ $? -eq 1 ] ; then
  exit 1
fi

ALL_BOARDS=false
BOARD_VARIANTS=()

# Compile all if none or 'all' argument is specified, otherwise take arguments as board variants
if [ -z "$2" ] || [ "$2" = "all" ] ; then
  ALL_BOARDS=true
  for dir in "$BSP_ROOT"/hardware/*/ ; do
  
    if [[ "$dir" != *common/ ]] ; then
      echo "$dir"
      BOARD_VARIANTS+=($(basename $dir))   
    fi
  done
else
  ALL_BOARDS=false
  for ((i = 2 ; i <= $# ; i++)) ; do
    BOARD_VARIANTS+=("${!i}")
  done
fi

# Verify board variants are valid
for board in "${BOARD_VARIANTS[@]}"; do
  if [ ! -d "$BSP_ROOT/hardware/$board" ]; then
    echo -e "Usage: $0 [board variants]\n"
    echo "Error: '$board' is invalid board variant"
    exit 1
  fi
done

failed_bsps=""
# Copy files from common board directory 
for board in "${BOARD_VARIANTS[@]}"; do
  if ! sh "$SCRIPT_DIR_PATH/copy-common-files.sh" "$1" "$board"; then
    failed_bsps="${failed_bsps:+$failed_bsps }$board"
    continue
  fi
done 

# Use existing OFS_PLATFORM_AFU_BBB or clone ofs-platform-afu-bbb
BUILD_DIR="$BSP_ROOT/build"
if [ -d $BUILD_DIR ] ; then
  rm -rf $BUILD_DIR
fi
mkdir -p "$BUILD_DIR"
if [ -z "$OFS_PLATFORM_AFU_BBB" ]; then
  cd "$BUILD_DIR" || exit
  if [ ! -d "$BUILD_DIR/ofs-platform-afu-bbb" ]; then
    git clone https://github.com/OPAE/ofs-platform-afu-bbb.git -b master ofs-platform-afu-bbb || exit
  fi
  export OFS_PLATFORM_AFU_BBB="$BSP_ROOT/build/ofs-platform-afu-bbb"
fi

# Check that ofs-platform-afu-bbb exist
if [ ! -d "$OFS_PLATFORM_AFU_BBB" ]; then
  echo "Error cannot find ofs-platform-afu-bbb at $OFS_PLATFORM_AFU_BBB"
  exit 1
fi

echo "OFS_PLATFORM_AFU_BBB Setup" #TOREMOVE

# If LIBOPAE_C_ROOT is not set then try to detect if OPAE is already installed
# on the system and use that location. Otherwise build OPAE from source.
# Note that this looks for libopae-c.so.2 because that version is required
# and older 1.0 version will not work. In the future this may need to be
# updated to work with newer versions of libopae-c too.
if [ -z "$LIBOPAE_C_ROOT" ]; then
  if /sbin/ldconfig -p | grep libopae-c.so.2 -q && afu_synth=$(command -v afu_synth_setup); then
    LIBOPAE_C_ROOT="$(dirname "$(dirname "$afu_synth")")"
  else
    sh $SCRIPT_DIR_PATH/build-opae.sh $1 || exit ########### TODO: HERE ###########
    LIBOPAE_C_ROOT="$BSP_ROOT/build/opae/install"
  fi
fi

# Check that OPAE is installed by looking for required include file
if [ ! -f "$LIBOPAE_C_ROOT/include/opae/fpga.h" ]; then
  echo "Error: cannot find required OPAE files in $LIBOPAE_C_ROOT"
  exit 1
fi
export LIBOPAE_C_ROOT

echo "OPAE Setup" #TOREMOVE

##################

# Build the MMD or use existing MMD if files already exist
if [ ! -f "$BSP_ROOT/linux64/lib/libintel_opae_mmd.so" ]; then
  sh $SCRIPT_DIR_PATH/build-bsp-sw.sh "$1"
else
  ldd "$BSP_ROOT/linux64/lib/libintel_opae_mmd.so" | grep -q libopae-c-ase
  ASE_NOT_LINKED="$?"
  if [ -n "$OPENCL_ASE_SIM" ]; then
    if [ "$ASE_NOT_LINKED" == 1 ]; then
      sh $SCRIPT_DIR_PATH/build-bsp-sw.sh "$1"
    else
      echo "INFO: existing MMD compiled for ASE"
    fi
  elif [ "$ASE_NOT_LINKED" == 0 ]; then
    sh $SCRIPT_DIR_PATH/build-bsp-sw.sh "$1"
  else
    echo "INFO: existing MMD compiled for hardware"
  fi
fi

echo "MMD Exists" #TOREMOVE

# Check that MMD was built
if [ ! -f "$BSP_ROOT/linux64/lib/libintel_opae_mmd.so" ]; then
  echo "Error: MMD was not built correctly"
  exit 1
fi

echo "MMD Setup" #TOREMOVE

if [ -z "$OPAE_PLATFORM_ROOT" ]; then
  echo "Error: Must set OPAE_PLATFORM_ROOT environment variable"
  exit 1
fi

echo "OPAE_PLATFORM_ROOT Setup" #TOREMOVE

# Use existing INTEL_FPGA_BBB or source/extra/intel-fpga-bbb
if [ -z "$INTEL_FPGA_BBB" ]; then
    #export INTEL_FPGA_BBB="$BSP_ROOT/source/extra/intel-fpga-bbb"
    export INTEL_FPGA_BBB="$BSP_ROOT/../common/source/extra/intel-fpga-bbb"
fi

# Check that intel-fpga-bbb exist
if [ ! -d "$INTEL_FPGA_BBB" ]; then
  echo "Error cannot find intel-fpga-bbb at $INTEL_FPGA_BBB"
  exit 1
fi

echo "INTEL_FPGA_BBB Setup" #TOREMOVE

# Generate BSP
echo "---------------------------------------------------------------"
echo "Generating BSP using setup-bsp.py using environment variables:"
echo "LIBOPAE_C_ROOT=\"$LIBOPAE_C_ROOT\""
echo "OPAE_PLATFORM_ROOT=\"$OPAE_PLATFORM_ROOT\""
echo "OPAE_PLATFORM_DB_PATH=\"$OPAE_PLATFORM_DB_PATH\""
echo "OPENCL_ASE_SIM=\"$OPENCL_ASE_SIM\""
echo "OFS_PLATFORM_AFU_BBB=\"$OFS_PLATFORM_AFU_BBB\""
echo "INTEL_FPGA_BBB=\"$INTEL_FPGA_BBB\""
echo "---------------------------------------------------------------"

for board in "${BOARD_VARIANTS[@]}"; do
  echo "---------------------------------------------------------------"
  echo -e "Setup BSP for board variant: $board\n"
  if ! python3 "$SCRIPT_DIR_PATH/setup-bsp.py" "$1" "$board"; then
    failed_bsps="${failed_bsps:+$failed_bsps }$board"
  fi
  echo "---------------------------------------------------------------"
done
if [ -n "$failed_bsps" ]; then
  printf 'Error: BSP build failed for...\n'
  # shellcheck disable=SC2086
  printf '    %s\n' $failed_bsps
  exit 1
fi
