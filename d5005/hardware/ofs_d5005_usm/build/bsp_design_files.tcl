# Copyright 2022 Intel Corporation
# SPDX-License-Identifier: MIT
#
#--------------------
# IPs
#--------------------
set_global_assignment -name QSYS_FILE "board.qsys"
set_global_assignment -name QSYS_FILE "ddr_channel.qsys"
set_global_assignment -name QSYS_FILE "ddr_board.qsys"

#--------------------
# DMA controller
#--------------------
set_global_assignment -name SOURCE_TCL_SCRIPT_FILE  "./rtl/dma/par/dma_controller_filelist.tcl"

#--------------------
# MPF VTP files
#--------------------
source "mpf_vtp.qsf"

#--------------------
# BSP RTL files
#--------------------
set_global_assignment -name SYSTEMVERILOG_FILE "rtl/ofs_plat_afu.sv"
set_global_assignment -name SYSTEMVERILOG_FILE "rtl/afu.sv"
set_global_assignment -name SYSTEMVERILOG_FILE "rtl/host_mem_if_vtp.sv"
set_global_assignment -name SYSTEMVERILOG_FILE "rtl/kernel_wrapper.v"
set_global_assignment -name SYSTEMVERILOG_FILE "rtl/bsp_logic.sv"
set_global_assignment -name SYSTEMVERILOG_FILE "rtl/dc_bsp_interfaces.sv"
set_global_assignment -name SYSTEMVERILOG_FILE "rtl/dc_bsp_pkg.sv"
set_global_assignment -name SYSTEMVERILOG_FILE "rtl/bsp_host_mem_if_mux.sv"

#--------------------
# Search paths (for headers, etc)
#--------------------
set_global_assignment -name SEARCH_PATH rtl/

#--------------------
# SDC
#--------------------
set_global_assignment -name SDC_FILE "user_clock.sdc"
set_global_assignment -name SDC_FILE "reset.sdc"
set_global_assignment -name SDC_FILE "opencl_bsp.sdc"
