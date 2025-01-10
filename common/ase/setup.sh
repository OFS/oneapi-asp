#!/bin/bash

# Copyright 2022 Intel Corporation
# SPDX-License-Identifier: MIT

echo "Start of setup.sh"

if [ -n "$OFS_ASP_ENV_DEBUG_SCRIPTS" ]; then
  echo "Running ${BASH_SOURCE[0]} with debug logging"
  set -x
fi

ASE_DIR_PATH="$(dirname "$(readlink -e "${BASH_SOURCE[0]}")")"
ASP_ROOT="$(readlink -e "$ASE_DIR_PATH/..")"
SCRIPT_DIR_PATH="$ASP_ROOT/scripts"

if [[ "$0" -ef "${BASH_SOURCE[0]}" ]]; then
  echo "Error: must source this script"
  return 1
fi

# Check for OpenCL SDK
if [ -z "$INTELFPGAOCLSDKROOT" ]; then
  echo "Error: must set INTELFPGAOCLSDKROOT before running ASE"
  return 1
fi

if [ -z "$AOCL_BOARD_PACKAGE_ROOT" ]; then
  export AOCL_BOARD_PACKAGE_ROOT="$ASP_ROOT"
elif [ "$(readlink -f  "$AOCL_BOARD_PACKAGE_ROOT")" != "$ASP_ROOT" ]; then
  echo "Error: AOCL_BOARD_PACKAGE_ROOT does not point to this repository"
fi

# Check for Quaruts
if [ -z "$QUARTUS_HOME" ]; then
  if [ -z "$QUARTUS_ROOTDIR" ]; then
    echo "Error: cannot find Quartus (must set QUARTUS_HOME or QUARTUS_ROOTDIR)"
    return 1
  else
    export QUARTUS_HOME="$QUARTUS_ROOTDIR"
  fi
fi


# If LIBOPAE_C_ROOT is not set then try to detect if OPAE is already installed
# on the system and use that location. Otherwise build OPAE from source.
# Note that this looks for libopae-c.so.2 because that version is required
# and older 1.0 version will not work. In the future this may need to be
# updated to work with newer versions of libopae-c too.
function set_libopae_c_root() {
  if [ -z "$LIBOPAE_C_ROOT" ]; then
    if /sbin/ldconfig -p | grep libopae-c.so.2 -q && afu_synth=$(command -v afu_synth_setup); then
      LIBOPAE_C_ROOT="$(dirname "$(dirname "$afu_synth")")"
    elif [ -d "$ASP_ROOT/build/opae/install" ]
    then
      echo "libopae-c-root exists : $ASP_ROOT/build/opae/install "
      LIBOPAE_C_ROOT="$ASP_ROOT/build/opae/install"
    else
        echo "libopae-c-root doesn't exist, running build-opae.sh"
      "$SCRIPT_DIR_PATH/build-opae.sh" || exit
      LIBOPAE_C_ROOT="$ASP_ROOT/build/opae/install"
    fi
  fi
  export LIBOPAE_C_ROOT
}

# Check for VCS simulator (change check if using other simulator). For
# Intel OFS EA release internal testing done with VCS only. Change this
# test if using a different simulator.
if ! command -v vcs; then
  echo "Error: VCS required simulator not found"
  return 1
fi

export OFS_ASP_ENV_ENABLE_ASE=1
#the qpf files are now symbolic links, so the previous check doesn't work anymore.
found_qpf_files=$(find $ASP_ROOT/hardware/ -name *.qpf 2>/dev/null)
if [[ -z "$found_qpf_files" ]]; then
  echo "The ASP hasn't been set up yet, so we need to run build-asp.sh"
  "$ASP_ROOT/scripts/build-asp.sh"
  set_libopae_c_root
else
  echo "ASP setup already complete (delete hardware setup files to regenerate)"
  # Build the MMD or use existing MMD if files already exist
  if [ ! -f "$ASP_ROOT/linux64/lib/libintel_opae_mmd.so" ]; then
    echo "mmd not built yet, run build-asp-sw.sh"
    "$SCRIPT_DIR_PATH/build-asp-sw.sh" || exit
    set_libopae_c_root
  else
    ldd "$ASP_ROOT/linux64/lib/libintel_opae_mmd.so" | grep -q libopae-c-ase
    ASE_NOT_LINKED="$?"
    if [ "$ASE_NOT_LINKED" == 1 ]; then
      "$SCRIPT_DIR_PATH/build-asp-sw.sh" || exit
      set_libopae_c_root
    else
      echo "INFO: existing MMD compiled for ASE"
      set_libopae_c_root
    fi
  fi
fi

export LIBOPAE_C_ASE_ROOT="$LIBOPAE_C_ROOT/../../opae-sim/install"

export ASE_SRC_PATH="$LIBOPAE_C_ASE_ROOT/share/opae/ase"
echo "ASE_SRC_PATH is $ASE_SRC_PATH"
export LD_LIBRARY_PATH="$LIBOPAE_C_ROOT/lib64/:$LIBOPAE_C_ASE_ROOT/lib64:$LD_LIBRARY_PATH"
echo "LD_LIBRARY_PATH is $LD_LIBRARY_PATH"
export CL_CONTEXT_COMPILER_MODE_INTELFPGA=3
echo "CL_CONTEXT_COMPILER_MODE_INTELFPGA is $CL_CONTEXT_COMPILER_MODE_INTELFPGA"
export PATH="$LIBOPAE_C_ROOT/bin:$LIBOPAE_C_ASE_ROOT/bin:$PATH"
echo "added libopae-c-root/bin to PATH"
echo "LIBOPAE_C_ROOT is $LIBOPAE_C_ROOT"
export OFS_ASP_ENV_ENABLE_ASE=1
echo "export OFS_ASP_ENV_ENABLE_ASE=1"

# shellcheck source=/dev/null
echo "About to run fpgavars.sh"
echo "INTELFPGAOCLSDKROOT is $INTELFPGAOCLSDKROOT"
source "$INTELFPGAOCLSDKROOT/fpgavars.sh"

echo "End of setup.sh"
