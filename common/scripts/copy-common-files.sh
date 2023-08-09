#!/bin/bash

## Copyright 2022 Intel Corporation
## SPDX-License-Identifier: MIT

###############################################################################
# 
###############################################################################

###############################################################################

SCRIPT_DIR_PATH="$(dirname "$(readlink -e "${BASH_SOURCE[0]}")")"

. $SCRIPT_DIR_PATH/set_variables.sh "$1"
if [ $? -eq 1 ] ; then
  exit 1
fi

BOARD_DIR="$ASP_TOP_DIR/$1/hardware/$2"
COMMON_BOARD_DIR="$ASP_TOP_DIR/$1/hardware/common"

if [ ! -d "$BOARD_DIR" ] ; then
    echo "Board not set: $BOARD_DIR is not a directory"
    exit 1
fi

if [ ! -d "$COMMON_BOARD_DIR" ] ; then
    echo "Board not set: $COMMON_BOARD_DIR is not a directory"
    exit 1
fi

rsync -a --ignore-existing "$COMMON_BOARD_DIR/" "$BOARD_DIR"

exit 0