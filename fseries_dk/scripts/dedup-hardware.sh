#!/bin/bash

## Copyright 2022 Intel Corporation
## SPDX-License-Identifier: MIT

if [ -n "$OFS_ASP_ENV_DEBUG_SCRIPTS" ]; then
  echo "Running ${BASH_SOURCE[0]} with debug logging"
  set -x
fi

SCRIPT_DIR_PATH="$(dirname "$(readlink -e "${BASH_SOURCE[0]}")")"
BSP_ROOT="$(readlink -e "$SCRIPT_DIR_PATH/..")"

# If hardlink is installed use it to deduplicate files in the hardware
# directory that are identical by hardlinking between the files
if command -v /usr/sbin/hardlink; then
  echo "Running hardlink to deduplicate files in hardware directory"
  /usr/sbin/hardlink "$BSP_ROOT/hardware"

# If hardlink not installed then check files that are known to consume large
# amount of disk space and see if they are the same in the ofs_fseries_dk
# and ofs_fseries_dk_usm directories. If so replace the ofs_fseries_dk_usm copy with
# a hard link to version of the file in ofs_fseries_dk directory
else
  echo "Deduplicating large files in hardware ofs_fseries_dk and ofs_fseries_dk_usm direcotry"
  dups=("build/output_files/ofs_fim.green_region.pmsf"
        "build/output_files/ofs_fim.static.msf"
        "build/output_files/ofs_fim.sof"
        "build/ofs_fim.qdb")

  for f in "${dups[@]}"; do
    if [[ -e "$BSP_ROOT/hardware/ofs_fseries_dk/$f" && 
          -e "$BSP_ROOT/hardware/ofs_fseries_dk_usm/$f" ]];
    then
      ln -f "$BSP_ROOT/hardware/ofs_fseries_dk/$f" "$BSP_ROOT/hardware/ofs_fseries_dk_usm/$f"
    fi
  done
fi
