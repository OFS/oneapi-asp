#!/bin/bash

## Copyright 2022 Intel Corporation
## SPDX-License-Identifier: MIT

###############################################################################
# Script to generate the tarball used for distributing the OneAPI ASP.  Creates
# tarball with directory prefix oneapi-asp-fseriesdk and includes files for hardware
# targets, MMD, and the default aocx in bringup directory.
###############################################################################

if [ -n "$OFS_ASP_ENV_DEBUG_SCRIPTS" ]; then
  set -x
fi

SCRIPT_DIR_PATH="$(dirname "$(readlink -e "${BASH_SOURCE[0]}")")"
BSP_ROOT="$(readlink -e "$SCRIPT_DIR_PATH/..")"

cd "$BSP_ROOT" || exit

bsp_files=("README.md" "scripts" "source" "hardware" "linux64" "board_env.xml" "pr_build_template")

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

if [ -d "$BSP_ROOT/oneapi-asp-fseriesdk" ]; then
    echo "$BSP_ROOT/oneapi-asp-fseriesdk exists; Removing it first"
    rm -rf $BSP_ROOT/oneapi-asp-fseriesdk
fi

mkdir $BSP_ROOT/oneapi-asp-fseriesdk

cp -rf "${bsp_files[@]}" $BSP_ROOT/oneapi-asp-fseriesdk/

#"build/opae/install" "build/json-c/install" 
mkdir -p $BSP_ROOT/oneapi-asp-fseriesdk/build/opae && cp -rf build/opae/install $BSP_ROOT/oneapi-asp-fseriesdk/build/opae/
mkdir -p $BSP_ROOT/oneapi-asp-fseriesdk/build/json-c && cp -rf build/json-c/install $BSP_ROOT/oneapi-asp-fseriesdk/build/json-c/

tar czf oneapi-asp-fseriesdk.tar.gz --owner=0 --group=0 --no-same-owner --no-same-permissions oneapi-asp-fseriesdk

rm -rf "$BSP_ROOT/oneapi-asp-n6001"
