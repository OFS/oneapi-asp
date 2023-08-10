# Copyright 2022 Intel Corporation
# SPDX-License-Identifier: MIT

proc add_bbb_assignments { } {
	#mpf
	set_global_assignment -name VERILOG_MACRO "MPF_PLATFORM_DCP_PCIE=1"
	set CCI_MPF_SRC "./ip/BBB_cci_mpf"
	source "$CCI_MPF_SRC/hw/par/qsf_cci_mpf_PAR_files.qsf"
    
	##vtp
	#set BBB_MPF_VTP_SRC "./BBB_mpf_vtp"
	#source "$BBB_MPF_VTP_SRC/hw/par/qsf_cci_mpf_PAR_files.qsf"
}

# get flow type (from quartus(args) variable)
set flow [lindex $quartus(args) 0]

project_open -revision $flow d5005
add_bbb_assignments
export_assignments
project_close
