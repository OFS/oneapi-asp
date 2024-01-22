#!/bin/bash

## Copyright 2022 Intel Corporation
## SPDX-License-Identifier: MIT

###############################################################################
# Script to generate the tarball used for distributing the OneAPI ASP.  Creates
# tarball with directory prefix oneapi-asp-n6001 and includes files for hardware
# targets, MMD, and the default aocx in bringup directory.
###############################################################################

if [ -n "$OFS_ASP_ENV_DEBUG_SCRIPTS" ]; then
  set -x
fi

SCRIPT_DIR_PATH="$(dirname "$(readlink -e "${BASH_SOURCE[0]}")")"
BSP_ROOT="$(readlink -e "$SCRIPT_DIR_PATH/..")"

cd "$BSP_ROOT" || exit

bsp_files=("README.md" "scripts" "source" "hardware" "linux64" "board_env.xml" "pr_build_template")

for i in "${!bsp_files[@]}"; do
  if [ ! -e "${bsp_files[i]}" ]; then
    unset 'bsp_files[i]'
  fi
done

if [ -d "$BSP_ROOT/oneapi-asp-n6001" ]; then
    echo "$BSP_ROOT/oneapi-asp-n6001 exists; Removing it first"
    rm -rf $BSP_ROOT/oneapi-asp-n6001
fi

mkdir $BSP_ROOT/oneapi-asp-n6001

cp -rf "${bsp_files[@]}" $BSP_ROOT/oneapi-asp-n6001/

if [ -d "build/opae/install" ]; then
    mkdir -p $BSP_ROOT/oneapi-asp-n6001/build/opae && cp -rf build/opae/install $BSP_ROOT/oneapi-asp-n6001/build/opae/
fi
if [ -d "build/json-c/install" ]; then
    mkdir -p $BSP_ROOT/oneapi-asp-n6001/build/json-c && cp -rf build/json-c/install $BSP_ROOT/oneapi-asp-n6001/build/json-c/
fi
if [ -n "$(find ./bringup/ -name *.aocx)" ]; then
    mkdir -p $BSP_ROOT/oneapi-asp-n6001/bringup/aocxs && cp -f bringup/aocxs/*.aocx $BSP_ROOT/oneapi-asp-n6001/bringup/aocxs/
fi

tar czf oneapi-asp-n6001.tar.gz --owner=0 --group=0 --no-same-owner --no-same-permissions oneapi-asp-n6001

rm -rf "$BSP_ROOT/oneapi-asp-n6001"
