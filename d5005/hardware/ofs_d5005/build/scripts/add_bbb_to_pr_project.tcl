# (C) 2017 Intel Corporation. All rights reserved.
# Your use of Intel Corporation's design tools, logic functions and other
# software and tools, and its AMPP partner logic functions, and any output
# files any of the foregoing (including device programming or simulation
# files), and any associated documentation or information are expressly subject
# to the terms and conditions of the Intel Program License Subscription
# Agreement, Intel MegaCore Function License Agreement, or other applicable
# license agreement, including, without limitation, that your use is for the
# sole purpose of programming logic devices manufactured by Intel and sold by
# Intel or its authorized distributors.  Please refer to the applicable
# agreement for further details.

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

project_open -revision afu_$flow d5005
add_bbb_assignments
export_assignments
project_close
