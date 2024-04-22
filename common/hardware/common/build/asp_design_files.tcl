# Copyright 2022 Intel Corporation
# SPDX-License-Identifier: MIT
#
#--------------------
# IPs
#--------------------
set_global_assignment -name IP_FILE "board.ip"

#--------------------
# DMA controller
#--------------------
set_global_assignment -name SOURCE_TCL_SCRIPT_FILE  "./rtl/dma/par/dma_controller_filelist.tcl"

#--------------------
# UDP Engine
#--------------------
set_global_assignment -name SOURCE_TCL_SCRIPT_FILE  "./rtl/udp_offload_engine/par/udp_offload_engine_filelist.tcl"

#--------------------
# MPF VTP files
#--------------------
source "mpf_vtp.qsf"

#--------------------
# ASP RTL files
#--------------------
set_global_assignment -name SYSTEMVERILOG_FILE "rtl/ofs_plat_afu.sv"
set_global_assignment -name SYSTEMVERILOG_FILE "rtl/afu.sv"
set_global_assignment -name SYSTEMVERILOG_FILE "rtl/host_mem_if_vtp.sv"
set_global_assignment -name SYSTEMVERILOG_FILE "rtl/kernel_wrapper.v"
set_global_assignment -name SYSTEMVERILOG_FILE "rtl/asp_logic.sv"
set_global_assignment -name SYSTEMVERILOG_FILE "rtl/ofs_asp_interfaces.sv"
set_global_assignment -name SYSTEMVERILOG_FILE "rtl/ofs_asp_pkg.sv"
set_global_assignment -name SYSTEMVERILOG_FILE "rtl/asp_host_mem_if_mux.sv"
set_global_assignment -name SYSTEMVERILOG_FILE "rtl/avmm_wr_ack_gen.sv"
set_global_assignment -name SYSTEMVERILOG_FILE "rtl/avmm_wr_ack_burst_to_word.sv"
set_global_assignment -name SYSTEMVERILOG_FILE "rtl/avmm_wr_ack_tracker.sv"
set_global_assignment -name SYSTEMVERILOG_FILE "rtl/avmm_single_burst_partial_writes.sv"

#--------------------
# Search paths (for headers, etc)
#--------------------
set_global_assignment -name SEARCH_PATH rtl/

#--------------------
# SDC
#--------------------
set_global_assignment -name SDC_FILE "ofs_asp.sdc"
