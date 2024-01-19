#!/bin/bash

## Copyright 2022 Intel Corporation
## SPDX-License-Identifier: MIT

if [ -n "$OFS_ASP_ENV_DEBUG_SCRIPTS" ]; then
  echo "Running ${BASH_SOURCE[0]} with debug logging"
  set -x
fi

SCRIPT_DIR_PATH="$(dirname "$(readlink -e "${BASH_SOURCE[0]}")")"
ASP_ROOT="$(readlink -e "$SCRIPT_DIR_PATH/..")"
PLATFORM_NAME="$(basename $ASP_ROOT)"

# If hardlink is installed use it to deduplicate files in the hardware
# directory that are identical by hardlinking between the files
if command -v /usr/sbin/hardlink; then
  echo "Running hardlink to deduplicate files in hardware directory"
  /usr/sbin/hardlink "$ASP_ROOT/hardware"

# If hardlink not installed then check files that are known to consume large
# amount of disk space and see if they are the same in the non-USM board variant
# and USM board variant directories. If so replace the USM board variant copy with
# a hard link to version of the file in non-USM board variant directory
else
  echo "Deduplicating large files in hardware ofs_${PLATFORM_NAME} and ofs_${PLATFORM_NAME}_usm directory"
  dups=("build/output_files/ofs_fim.green_region.pmsf"
        "build/output_files/ofs_fim.static.msf"
        "build/output_files/ofs_fim.sof"
        "build/ofs_fim.qdb")

  for f in "${dups[@]}"; do
    if [[ -e "$ASP_ROOT/hardware/ofs_${PLATFORM_NAME}/$f" && 
          -e "$ASP_ROOT/hardware/ofs_${PLATFORM_NAME}_usm/$f" ]];
    then
      ln -f "$ASP_ROOT/hardware/ofs_${PLATFORM_NAME}/$f" "$ASP_ROOT/hardware/ofs_${PLATFORM_NAME}_usm/$f"
    fi
  done
fi
