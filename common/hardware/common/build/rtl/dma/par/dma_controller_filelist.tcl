# Copyright 2022 Intel Corporation
# SPDX-License-Identifier: MIT

# Directory of script
set THIS_DIR [file dirname [info script]]

set_global_assignment -name SEARCH_PATH "${THIS_DIR}/.."

set_global_assignment -name SYSTEMVERILOG_FILE "${THIS_DIR}/../dma.vh"
set_global_assignment -name SYSTEMVERILOG_FILE "${THIS_DIR}/../dma_controller_rd_fsm_pkg.sv"
set_global_assignment -name SYSTEMVERILOG_FILE "${THIS_DIR}/../dma_controller_wr_fsm_pkg.sv"
set_global_assignment -name SYSTEMVERILOG_FILE "${THIS_DIR}/../dma_data_transfer.sv"
set_global_assignment -name SYSTEMVERILOG_FILE "${THIS_DIR}/../dma_dispatcher.sv"
set_global_assignment -name SYSTEMVERILOG_FILE "${THIS_DIR}/../dma_interfaces.sv"
set_global_assignment -name SYSTEMVERILOG_FILE "${THIS_DIR}/../dma_pkg.sv"
set_global_assignment -name SYSTEMVERILOG_FILE "${THIS_DIR}/../dma_top.sv"
