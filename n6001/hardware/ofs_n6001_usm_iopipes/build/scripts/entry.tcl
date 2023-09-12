# Copyright 2022 Intel Corporation
# SPDX-License-Identifier: MIT

#Full compiles are not supported on Windows
switch $tcl_platform(platform) {
  windows {
    post_message -type error "Full compiles to generate hardware for the FPGA are available on supported Linux platforms only. Please add -rtl to your invocation of aoc to compile without building hardware. Otherwise please run your compile on a supported Linux distribution."
    exit 2
  }
  default {
    #Get revision name from quartus args
    if { [llength $quartus(args)] > 0 } {
      set revision_name [lindex $quartus(args) 0]
    } else {
      set revision_name import
    }
    post_message "Compiling revision $revision_name"
    set FIM_BOARD_PATH [glob  -directory fim_platform/build/syn/board/ -type d *]
    post_message "FIM_BOARD_PATH is $FIM_BOARD_PATH"
    if {[catch {qexec "bash $FIM_BOARD_PATH/syn_top/scripts/run.sh $revision_name"} result]} {
	post_message -type error "OneAPI ASP build failed. Please see quartus_sh_compile.log for more information."
    }
  }
}
