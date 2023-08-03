#!/bin/bash

## Copyright 2022 Intel Corporation
## SPDX-License-Identifier: MIT

###############################################################################
# Script to generate the tarball used for distributing the OneAPI ASP.  Creates
# tarball with directory prefix opencl-bsp and includes files for hardware
# targets, MMD, and the default aocx in bringup directory.
###############################################################################

if [ -n "$OFS_OCL_ENV_DEBUG_SCRIPTS" ]; then
  set -x
fi

SCRIPT_DIR_PATH="$(dirname "$(readlink -e "${BASH_SOURCE[0]}")")"
BSP_ROOT="$(readlink -e "$SCRIPT_DIR_PATH/..")"

cd "$BSP_ROOT" || exit

bsp_files=("README.md" "scripts" "source" "hardware" "linux64/lib" "linux64/libexec" "board_env.xml" "build/opae/install" "build/json-c/install" "pr_build_template/hw/blue_bits")

search_dir=bringup/aocxs
for entry in "$search_dir"/*.aocx
do
  bsp_files+=($entry)
done

for i in "${!bsp_files[@]}"; do
  if [ ! -e "${bsp_files[i]}" ]; then
    unset 'bsp_files[i]'
  fi
done

tar --transform='s,^,oneapi-asp-n6001/,' --create --gzip \
    --file="$BSP_ROOT/oneapi-asp-n6001.tar.gz" --owner=0 --group=0  "${bsp_files[@]}"
