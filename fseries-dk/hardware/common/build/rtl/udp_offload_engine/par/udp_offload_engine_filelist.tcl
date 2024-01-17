# Copyright 2022 Intel Corporation
# SPDX-License-Identifier: MIT
#


# Directory of script
set THIS_DIR [file dirname [info script]]

set_global_assignment -name SEARCH_PATH "${THIS_DIR}/.."

set_global_assignment -name SYSTEMVERILOG_FILE "${THIS_DIR}/../rtl/udp_oe_csr.sv"
set_global_assignment -name SYSTEMVERILOG_FILE "${THIS_DIR}/../rtl/udp_offload_engine.sv"
set_global_assignment -name SYSTEMVERILOG_FILE "${THIS_DIR}/../rtl/simple_tx.sv"
set_global_assignment -name SYSTEMVERILOG_FILE "${THIS_DIR}/../rtl/simple_rx.sv"
set_global_assignment -name SYSTEMVERILOG_FILE "${THIS_DIR}/../rtl/udp_oe_pkg.sv"
set_global_assignment -name SYSTEMVERILOG_FILE "${THIS_DIR}/../rtl/udp_oe_interfaces.sv"
set_global_assignment -name IP_FILE "${THIS_DIR}/../ip/asp_dcfifo.ip"

set_global_assignment -name SDC_FILE "${THIS_DIR}/shim_udp_offload_engine.sdc"
