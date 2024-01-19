#!/bin/bash

## Copyright 2022 Intel Corporation
## SPDX-License-Identifier: MIT

###############################################################################
# Script to generate the tarball used for distributing the OneAPI ASP.  Creates
# tarball with directory prefix oneapi-asp-<platform_name> and includes files 
# for hardware targets, MMD, and the default binary in bringup directory.
###############################################################################

if [ -n "$OFS_ASP_ENV_DEBUG_SCRIPTS" ]; then
  set -x
fi

SCRIPT_DIR_PATH="$(dirname "$(readlink -e "${BASH_SOURCE[0]}")")"
ASP_ROOT="$(readlink -e "$SCRIPT_DIR_PATH/..")"
PLATFORM_NAME="$(basename $ASP_ROOT)"

cd "$ASP_ROOT" || exit

bsp_files=("README.md" "scripts" "source" "hardware" "linux64" "board_env.xml" "pr_build_template")

for i in "${!bsp_files[@]}"; do
  if [ ! -e "${bsp_files[i]}" ]; then
    unset 'bsp_files[i]'
  fi
done

if [ -d "$ASP_ROOT/oneapi-asp-$PLATFORM_NAME" ]; then
    echo "$ASP_ROOT/oneapi-asp-$PLATFORM_NAME exists; Removing it first"
    rm -rf $ASP_ROOT/oneapi-asp-$PLATFORM_NAME
fi

mkdir $ASP_ROOT/oneapi-asp-$PLATFORM_NAME

cp -rf "${bsp_files[@]}" $ASP_ROOT/oneapi-asp-$PLATFORM_NAME/

if [ -d "build/opae/install" ]; then
    mkdir -p $ASP_ROOT/oneapi-asp-$PLATFORM_NAME/build/opae && cp -rf build/opae/install $ASP_ROOT/oneapi-asp-$PLATFORM_NAME/build/opae/
fi
if [ -d "build/json-c/install" ]; then
    mkdir -p $ASP_ROOT/oneapi-asp-$PLATFORM_NAME/build/json-c && cp -rf build/json-c/install $ASP_ROOT/oneapi-asp-$PLATFORM_NAME/build/json-c/
fi
if [ -n "$(find ./bringup/ -name *.aocx)" ]; then
    mkdir -p $ASP_ROOT/oneapi-asp-$PLATFORM_NAME/bringup/aocxs && cp -f bringup/aocxs/*.aocx $ASP_ROOT/oneapi-asp-$PLATFORM_NAME/bringup/aocxs/
fi

tar czf oneapi-asp-$PLATFORM_NAME.tar.gz --owner=0 --group=0 --no-same-owner --no-same-permissions oneapi-asp-$PLATFORM_NAME

rm -rf "$ASP_ROOT/oneapi-asp-$PLATFORM_NAME"
