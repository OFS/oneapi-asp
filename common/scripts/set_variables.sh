#!/bin/bash

## Copyright 2022 Intel Corporation
## SPDX-License-Identifier: MIT

###############################################################################
# Script to set variables common to multiple scripts in this directory.
# 
#
# Arguments take:
#
# Name of ASP to set variables around; name of directory holding ASP files. 
#
###############################################################################

###############################################################################

SCRIPT_DIR_PATH="$(dirname "$(readlink -e "${BASH_SOURCE[0]}")")"
ASP_COMMON_DIR="$SCRIPT_DIR_PATH/.."
ASP_TOP_DIR="$SCRIPT_DIR_PATH/../.."

# Specify device
if [ $# -eq 0 ] ; then
  echo "Please specify name of BSP directory and optionally hardware variant (default is ofs_<BSP Name>)."
  exit 1
fi 

if [ ! -d "$ASP_TOP_DIR/$1" ] ; then
  echo "$1 is not a directory in $ASP_TOP_DIR"
  exit 1
fi

BSP_ROOT="$(readlink -e "$ASP_TOP_DIR/$1")"
