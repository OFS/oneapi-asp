#!/bin/bash

# Copyright 2022 Intel Corporation
# SPDX-License-Identifier: MIT

ip-make-ipx --source-directory="ccip_iface/*/,ip/*/,$INTELFPGAOCLSDKROOT/ip/board" --output=iface.ipx  --relative-vars=INTELFPGAOCLSDKROOT

#clean up the generated iipx files to remove absolute paths
sed -i 's/=".*\/build\/ip/="ip/g' *.iipx
