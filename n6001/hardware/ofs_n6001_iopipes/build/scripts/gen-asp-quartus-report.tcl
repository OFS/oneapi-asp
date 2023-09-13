# Copyright 2022 Intel Corporation
# SPDX-License-Identifier: MIT
#

# Required packages
package require ::quartus::project
package require ::quartus::report
package require ::quartus::flow

#returns the kernel clock information
proc get_kernel_clks { } {
    #open the output_files/user_clock_freq.txt file for reading
    set infile   [open "output_files/user_clock_freq.txt" r]
    set lines [split [read $infile] "\n"]
    set low_fmax 0
    set high_fmax 0
    set low_st "clock-frequency-low"
    set high_st "clock-frequency-high"
    foreach line $lines {
        if {[string first $low_st $line] != -1} {
            set start_idx [expr [string first ":" $line] + 1]
            set low_fmax [string range $line $start_idx [string length $line] ]
        } elseif {[string first $high_st $line] != -1} {
            set start_idx [expr [string first ":" $line] + 1]
            set high_fmax [string range $line $start_idx [string length $line] ]
        } 
    }
    #return the two values in an array
    close $infile
    return [list $low_fmax $high_fmax]
}

# Return values: [retval panel_id row_index]
#   panel_id and row_index are only valid if the query is successful
# retval: 
#    0: success
#   -1: not found
#   -2: panel not found (could be report not loaded)
#   -3: no rows found in panel
#   -4: multiple matches found
proc find_report_panel_row { panel_name col_index string_op string_pattern } {
    if {[catch {get_report_panel_id $panel_name} panel_id] || $panel_id == -1} {
        return -2;
    }

    if {[catch {get_number_of_rows -id $panel_id} num_rows] || $num_rows == -1} {
        return -3;
    }

    # Search for row match.
    set found 0
    set row_index -1;

    for {set r 1} {$r < $num_rows} {incr r} {
        if {[catch {get_report_panel_data -id $panel_id -row $r -col $col_index} value] == 0} {
            if {[string $string_op $string_pattern $value]} {
                if {$found == 0} {
                    # If multiple rows match, return the first
                    set row_index $r
                }
                incr found
            }
        }
    }

    if {$found > 1} {return [list -4 $panel_id $row_index]}
    if {$row_index == -1} {return -1}

    return [list 0 $panel_id $row_index]
}

##############################################################################
##############################       MAIN        #############################
##############################################################################

post_message "Running gen-asp-quartus-report.tcl script"

set project_name [lindex $quartus(args) 0]
set revision_name [lindex $quartus(args) 1]

post_message "Project name: $project_name"
post_message "Revision name: $revision_name"

project_open $project_name -revision $revision_name
load_report $revision_name

post_message "Generating acl_quartus_report.txt"
set outfile   [open "acl_quartus_report.txt" w]
set aluts_l   [regsub -all "," [get_fitter_resource_usage -alut] "" ]
if {[catch {set aluts_m [regsub -all "," [get_fitter_resource_usage -resource "Memory ALUT usage"] "" ]} result]} {
    set aluts_m 0
}
if { [string length $aluts_m] < 1 || ! [string is integer $aluts_m] } {
    set aluts_m 0
}
set aluts     [expr $aluts_l + $aluts_m]
set registers [get_fitter_resource_usage -reg]
set logicutil [get_fitter_resource_usage -utilization]
set io_pin    [get_fitter_resource_usage -io_pin]
set dsp       [get_fitter_resource_usage -resource "*DSP*"]
set mem_bit   [get_fitter_resource_usage -mem_bit]
set m9k       [get_fitter_resource_usage -resource "M?0K*"]

set kclks [get_kernel_clks]
set slow_clk [ lindex $kclks 0 ]
set fast_clk [ lindex $kclks 1 ]

#print to acl_quartus_report log
puts $outfile "ALUTs: $aluts"
puts $outfile "Registers: $registers"
puts $outfile "Logic utilization: $logicutil"
puts $outfile "I/O pins: $io_pin"
puts $outfile "DSP blocks: $dsp"
puts $outfile "Memory bits: $mem_bit"
puts $outfile "RAM blocks: $m9k"
puts $outfile "Actual clock freq: $slow_clk"
puts $outfile "Kernel fmax: $slow_clk"
puts $outfile "1x clock fmax: $slow_clk"
puts $outfile "2x clock fmax: $fast_clk"

#print to terminal/quartus_sh_compile.log, too.
post_message "asp_resources_analysis.tcl: ALUTs: $aluts"
post_message "asp_resources_analysis.tcl: Registers: $registers"
post_message "asp_resources_analysis.tcl: Logic utilization: $logicutil"
post_message "asp_resources_analysis.tcl: I/O pins: $io_pin"
post_message "asp_resources_analysis.tcl: DSP blocks: $dsp"
post_message "asp_resources_analysis.tcl: Memory bits: $mem_bit"
post_message "asp_resources_analysis.tcl: RAM blocks: $m9k"
post_message "asp_resources_analysis.tcl: Actual clock freq: $slow_clk"
post_message "asp_resources_analysis.tcl: Kernel fmax: $slow_clk"
post_message "asp_resources_analysis.tcl: 1x clock fmax: $slow_clk"
post_message "asp_resources_analysis.tcl: 2x clock fmax: $fast_clk"

# Highest non-global fanout signal
set result [find_report_panel_row "Fitter||Place Stage||Fitter Resource Usage Summary" 0 equal "Highest non-global fan-out"]
if {[lindex $result 0] < 0} {error "Error: Could not find highest non-global fan-out (error $retval)"}
set high_fanout_signal_fanout_count [get_report_panel_data -id [lindex $result 1] -row [lindex $result 2] -col 1]
puts $outfile "Highest non-global fanout: $high_fanout_signal_fanout_count"
close $outfile
# End little report

project_close

post_message -type info "The gen-asp-quartus-report.tcl script is done."
