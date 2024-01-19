# Copyright 2022 Intel Corporation
# SPDX-License-Identifier: MIT
set script_path [ file dirname [ file normalize [ info script ] ] ]

#The path to the syn_top directory from the FIM-build was written to 
#the syn_top_relpath.tcl file during the execution of setup-asp.py.
#We use it here to find the location to do the Quartus build.
source $script_path/syn_top_relpath.tcl

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
    post_message "SYN_TOP_RELPATH is $SYN_TOP_RELPATH"
    if {[catch {qexec "bash $SYN_TOP_RELPATH/scripts/run.sh $revision_name"} result]} {
        post_message -type error "OneAPI ASP build failed. Please see quartus_sh_compile.log for more information."
    }
  }
}
