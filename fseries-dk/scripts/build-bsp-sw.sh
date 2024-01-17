#!/bin/bash

## Copyright 2022 Intel Corporation
## SPDX-License-Identifier: MIT

###############################################################################
# Script to build MMD needed for the BSP. The script first looks for the
# LIBOPAE_C_ROOT environment variable. If that is not found then it builds
# OPAE from source.
#
# The reason for this is that we are not currently installing
# OPAE on systems that also have Quartus installed. So default behavior of
# buildling required resources from source is most common. In the future
# we may want to detect the version of OPAE that is installed and only
# build from source if compatible OPAE not found. For now using an installed
# OPAE requires setting the LIBOPAE_C_ROOT environment variable to the
# install location, even if that is standard system location.
###############################################################################

if [ -n "$OFS_ASP_ENV_DEBUG_SCRIPTS" ]; then
  set -x
fi

SCRIPT_DIR_PATH="$(dirname "$(readlink -e "${BASH_SOURCE[0]}")")"
BSP_ROOT="$(readlink -e "$SCRIPT_DIR_PATH/..")"

if [ -z "$LIBOPAE_C_ROOT" ]; then
    "$SCRIPT_DIR_PATH/build-opae.sh"
    export LIBOPAE_C_ROOT="$BSP_ROOT/build/opae/install"
    export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$BSP_ROOT/build/json-c/install/lib64
fi

export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$BSP_ROOT/build/json-c/install/lib64
"$SCRIPT_DIR_PATH/build-mmd.sh" || exit
