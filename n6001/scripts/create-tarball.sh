#!/bin/bash

## Copyright 2022 Intel Corporation
## SPDX-License-Identifier: MIT

###############################################################################
# Script to generate the tarball used for distributing the OpenCL BSP.  Creates
# tarball with directory prefix opencl-bsp and includes files for hardward
# targets, MMD, and the default aocx in bringup directory.
###############################################################################

if [ -n "$OFS_OCL_ENV_DEBUG_SCRIPTS" ]; then
  set -x
fi

SCRIPT_DIR_PATH="$(dirname "$(readlink -e "${BASH_SOURCE[0]}")")"
BSP_ROOT="$(readlink -e "$SCRIPT_DIR_PATH/..")"

cd "$BSP_ROOT" || exit

bsp_files=("scripts/build-mmd.sh" "source" "hardware" "linux64/lib" "linux64/libexec" "board_env.xml" "build/opae/install" "build/json-c/install")

if [ -d "$OPAE_PLATFORM_ROOT" ]; then
    mkdir fim_binaries
    cp "$OPAE_PLATFORM_ROOT/hw/blue_bits/*.bin" fim_binaries/
    bsp_files+=("fim_binaries")
else
    echo "Warning: OPAE_PLATFORM_ROOT is not defined, so the FIM binary programming files will not be included in the tarball."
fi

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

tar --transform='s,^,opencl-bsp/,' --create --verbose --gzip \
    --file="$BSP_ROOT/oneapi-asp-n6001.tar.gz" --owner=0 --group=0  "${bsp_files[@]}"
