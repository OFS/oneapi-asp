# Copyright 2022 Intel Corporation
# SPDX-License-Identifier: MIT
#

# Required packages
package require ::quartus::project
package require ::quartus::report
package require ::quartus::flow

# Definitions
#normal/slow clock
set k_clk_name "afu_top|port_gasket|user_clock|qph_user_clk|qph_user_clk_iopll|iopll_0_outclk1"
#double/fast clock
set k_clk2x_name "afu_top|port_gasket|user_clock|qph_user_clk|qph_user_clk_iopll|iopll_0_outclk0"
set k_fmax -1
set jitter_compensation 0.01
set unused_clock_freq 10000
set max_num_loops 10
set use_normalized_recovery_slack 0
#this constraint matches the multicycle setting on the reset signals in reset.sdc
set arst_multicycle_cnt 4.0
#fmax limit on the PLL
set PLL_1x_MAX 600
set PLL_1x2x_MAX 400
set DISABLE_MPW_CHECK_ON_UNUSED_FAST_CLK 0

proc list_plls_in_design { } {
    post_message "Found the following IOPLLs in design:"
    foreach_in_collection node [get_atom_nodes -type IOPLL] {
        set name [get_atom_node_info -key NAME -node $node]
        post_message "   $name"
    }
}


proc find_kernel_pll_in_design {pll_search_string} {
    foreach_in_collection node [get_atom_nodes -type IOPLL] {
            set node_name [ get_atom_node_info -key NAME -node $node]
        set name [get_atom_node_info -key NAME -node $node]
                if { [ string match $pll_search_string $node_name ] == 1} {
                post_message "Found kernel_pll: $node_name"
                set kernel_pll_name $node_name
                return $kernel_pll_name
            }
    }
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


# get_fmax_from_report: Determines the fmax for the given clock. The fmax value returned
# will meet all timing requirements (setup, hold, recovery, removal, minimum pulse width)
# across all corners.  The return value is a 4-element list consisting of the
# fmax, clk name, violation-flag, and negative slack.
proc get_fmax_from_report { clkname required jitter_compensation} {
    global unused_clock_freq
    global arst_multicycle_cnt
    global use_normalized_recovery_slack
    # Find the clock period.
    set result [find_report_panel_row "Timing Analyzer||Clocks" 0 match $clkname]
    set retval [lindex $result 0]
    set this_clk_had_violation 0
    set neg_wc_slack 0
   
    if {$retval == -1} { 
        if {$required == 1} {
           error "Error: Could not find clock: $clkname" 
        } else {
           post_message -type warning "Could not find clock: $clkname.  Clock is not required assuming 10 GHz and proceeding."
           return [list $unused_clock_freq $clkname 0 0]
        }
    } elseif {$retval < 0} { 
        error "Error: Failed search for clock $clkname (error $retval)"
    }

    # Update clock name to full clock name ($clkname as passed in may contain wildcards).
    set panel_id [lindex $result 1]
    set row_index [lindex $result 2]
    set clkname [get_report_panel_data -id $panel_id -row $row_index -col 0]
    set clk_period [get_report_panel_data -id $panel_id -row $row_index -col 2]

    post_message "Clock $clkname"
    post_message "  Period: $clk_period"

    # Determine the most negative slack across all relevant timing metrics (setup, recovery, minimum pulse width)
    # and across all timing corners. Hold and removal metrics are not taken into account
    # because their slack values are independent on the clock period (for kernel clocks at least).
    #
    # Paths that involve both a posedge and negedge of the kernel clocks are not handled properly (slack
    # adjustment needs to be doubled).
    set timing_metrics [list "Setup" "Recovery" "Minimum Pulse Width"]
    set timing_metric_colindex [list 1 3 5 ]
    set timing_metric_required [list 1 0 0]
    set wc_slack $clk_period
    set has_slack 0
    set fmax_from_summary 5000.0

    # Find the "Fmax Summary" numbers reported in Quartus.  This may not
    # account for clock transfers but it does account for pos-to-neg edge same
    # clock transfers.  Whatever we calculate should be less than this.
    set fmax_panel_name "Timing Analyzer||* Model||* Model Fmax Summary"
    foreach panel_name [get_report_panel_names] {
      if {[string match $fmax_panel_name $panel_name] == 1} {
        set result [find_report_panel_row $panel_name 2 equal $clkname]
        set retval [lindex $result 0]
        if {$retval == 0} {
          set restricted_fmax_field [get_report_panel_data -id [lindex $result 1] -row [lindex $result 2] -col 1]
          regexp {([0-9\.]+)} $restricted_fmax_field restricted_fmax 
          if {$restricted_fmax < $fmax_from_summary} {
            set fmax_from_summary $restricted_fmax
          }
        }
      }
    }
    post_message "  Restricted Fmax from STA: $fmax_from_summary"

    # Find the worst case slack across all corners and metrics
    foreach metric $timing_metrics metric_required $timing_metric_required col_ndx $timing_metric_colindex {
      set panel_name "Timing Analyzer||Multicorner Timing Analysis Summary"
      set panel_id [get_report_panel_id $panel_name] 
      set result [find_report_panel_row $panel_name 0 equal " $clkname"]
      set retval [lindex $result 0]

      if {$retval == -1} { 
        if {$required == 1 && $metric_required == 1} {
          error "Error: Could not find clock: $clkname" 
        }
      } elseif {$retval < 0 && $retval != -4 } { 
        error "Error: Failed search for clock $clkname (error $retval)"
      }

      if {$retval == 0 || $retval == -4} {
        set slack [get_report_panel_data -id [lindex $result 1] -row [lindex $result 2] -col $col_ndx ]
        post_message "    $metric slack: $slack"
        if {$slack != "N/A"} {
          if {$metric == "Setup" || $metric == "Recovery"} {
            set has_slack 1
            if {$metric == "Recovery" && $use_normalized_recovery_slack == 1} {
              set normalized_slack [ expr $slack / $arst_multicycle_cnt ]
              post_message "    normalized $metric slack: $normalized_slack"
              set slack $normalized_slack
            }
          }
        } 
        # Keep track of the most negative slack.
        if {$slack < $wc_slack} {
          set wc_slack $slack
          set wc_metric $metric
        }
      }
    }

    if {$has_slack == 1} {
        post_message "  Worst-case slack for clock $clkname is $wc_slack."
        #round the wc-slack to next 10ps-increment
        if {$wc_slack > -0.01 && $wc_slack < 0.0} {
            set wc_slack -0.010
            post_message "  Round up to the next 10-ps increment to ensure the frequency is modified, too."
        }
        # Adjust the clock period to meet the worst-case slack requirement.
        set clk_period [expr $clk_period - $wc_slack + $jitter_compensation]
        post_message "  Adjusted period: $clk_period ([format %+0.3f [expr -$wc_slack]], $wc_metric)"

        # Compute fmax from clock period. Clock period is in nanoseconds and the
        # fmax number should be in MHz.
        set fmax [expr 1000 / $clk_period]

        if {$fmax_from_summary < $fmax} {
            post_message "  Restricted Fmax from STA is lower than $fmax, using it instead."
            set fmax $fmax_from_summary
        }

        # Truncate to two decimal places. Truncate (not round to nearest) to avoid the
        # very small chance of going over the clock period when doing the computation.
        set fmax [expr floor($fmax * 100) / 100]
        post_message "  Fmax: $fmax"
        
        #check here for negative slack - set flag indicating this clock has been modified
        if { $wc_slack < 0 } {
            set this_clk_had_violation 1
            set neg_wc_slack [expr -$wc_slack]
        }
    } else {
        post_message -type warning "No slack found for clock $clkname - assuming 10 GHz."
        set fmax $unused_clock_freq
    }

    return [list $fmax $clkname $this_clk_had_violation $neg_wc_slack]
}

# Returns [k_fmax fmax1 k_clk_name fmax2 k_clk2x_name]
proc get_kernel_clks_and_fmax { k_clk_name k_clk2x_name jitter_compensation} {
    global unused_clock_freq
    set result [list]
    # Read in the achieved fmax
    post_message "Calculating maximum fmax..."
    set x [ get_fmax_from_report $k_clk_name 1 $jitter_compensation]
    set fmax1 [ lindex $x 0 ]
    set k_clk_name [ lindex $x 1 ]
    set k_clk_had_violation [ lindex $x 2 ]
    set k_clk_wc_slack [ lindex $x 3 ]
    set x [ get_fmax_from_report $k_clk2x_name 0 0.0]
    set fmax2 [ lindex $x 0 ]
    set k_clk2x_name [ lindex $x 1 ]
    set k_clk2x_had_violation [ lindex $x 2 ]
    set k_clk2x_wc_slack [ lindex $x 3 ]

    #initial assignments if everything is timing-clean; will be updated in subsequent if/else
    set k_fmax $fmax1
    
    #if only 1x clock is used, only use 1x clock numbers.
    #else if both clocks are used, use the larger neg_wc_slack value to define the change of the other clock
    if { $fmax2 == $unused_clock_freq } {
        if { $k_clk_had_violation == 1 } {
            #do nothing since clk2x isn't used and clk1x was fixed in the return values from get_fmax_from_report
            set fmax2 $fmax2
        }
    } else {
        post_message "Both kernel clocks are used in this design."
        post_message "clk1x worst-case negative slack is $k_clk_wc_slack"
        post_message "clk2x worst-case negative slack is $k_clk2x_wc_slack"
    }
    
    return [list $k_fmax $fmax1 $k_clk_name $fmax2 $k_clk2x_name]
}

##############################################################################
##############################       MAIN        #############################
##############################################################################

set timing_loop_cnt 1
set timing_clean 0

while { $timing_clean == 0 && $timing_loop_cnt <= $max_num_loops} {
    set kernel_timing_err_cnt 0
    
    post_message "Running adjust PLLs script - loop $timing_loop_cnt"
    
    set project_name [lindex $quartus(args) 0]
    set revision_name [lindex $quartus(args) 1]
    
    post_message "Project name: $project_name"
    post_message "Revision name: $revision_name"
    
    load_package design
    project_open $project_name -revision $revision_name
    design::load_design -writeable -snapshot final
    load_report $revision_name
    
    set panel_names [get_report_panel_names]
    
    # adjust PLL settings
    set k_clk_name_full   $k_clk_name
    set k_clk2x_name_full $k_clk2x_name
    
    # Process arguments.
    set fmax1 unknown
    set fmax2 unknown
    set pll_search_string "*kernel_pll*"
    
    # get device speedgrade
    set part_name [get_global_assignment -name DEVICE]
    post_message "Device part name is $part_name"
    set report [report_part_info $part_name]
    regexp {Speed Grade.*$} $report speedgradeline
    regexp {(\d+)} $speedgradeline speedgrade
    if { $speedgrade < 1 || $speedgrade > 8 } {
        post_message "Speedgrade is $speedgrade and not in the range of 1 to 8"
        post_message "Terminating post-flow script"
        return TCL_ERROR
    }
    post_message "Speedgrade is $speedgrade"
    
    set x [get_kernel_clks_and_fmax $k_clk_name $k_clk2x_name $jitter_compensation]
    set k_fmax       [ lindex $x 0 ]
    set fmax1        [ lindex $x 1 ]
    set k_clk_name_full   [ lindex $x 2 ]
    set fmax2        [ lindex $x 3 ]
    set k_clk2x_name_full [ lindex $x 4 ]
    
    post_message "Kernel Fmax1 determined to be $fmax1";
    post_message "Kernel Fmax2 determined to be $fmax2";
    
    design::unload_design
    
    project_open $project_name -revision $revision_name
    load_report $revision_name
    
    post_message "Generating acl_quartus_report.txt"
    set outfile   [open "acl_quartus_report.txt" w]
    set aluts_l   [regsub "," [get_fitter_resource_usage -alut] "" ]
    if {[catch {set aluts_m [regsub "," [get_fitter_resource_usage -resource "Memory ALUT usage"] "" ]} result]} {
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
    
    set pll_1x_setting [expr int($fmax1)]
    set pll_2x_setting [expr int($fmax2)]
    if { $fmax2 < $unused_clock_freq} {
	#the 1x kernel clock will be limited by the 2x kernel clock
        set pll_1x_setting [expr min($pll_1x_setting, $PLL_1x2x_MAX, $pll_2x_setting / 2)]
        set pll_2x_setting [expr int($pll_1x_setting * 2)]
        set clk2x_has_no_fanout 0
    } else {
        post_message "clk2x has no fanout."
        #1x clock is limited to PLL_1x_MAX
        set pll_1x_setting [expr min($pll_1x_setting,$PLL_1x_MAX) ]
        #if the 1x clock is greater than the 1x2x limit, the 1x and 2x clocks are 
        # set to the same frequencies by OPAE/driver/FIM
        if { $pll_1x_setting > $PLL_1x2x_MAX } {
            post_message "1x clock is > 400 MHz, so the 2x clock will match the 1x clock. This is to prevent Minimum Pulse Width violations on the unused 2x clock."
            set pll_2x_setting $pll_1x_setting
        } else {
            set pll_2x_setting [expr int($pll_1x_setting * 2)]
        }
        set clk2x_has_no_fanout 1
    }
    #the pll_metadata.txt and user_clock.sdc assignments should be based on the same data.
    set fmax1 $pll_1x_setting
    set fmax2 $pll_2x_setting

    #print to acl_quartus_report log
    puts $outfile "ALUTs: $aluts"
    puts $outfile "Registers: $registers"
    puts $outfile "Logic utilization: $logicutil"
    puts $outfile "I/O pins: $io_pin"
    puts $outfile "DSP blocks: $dsp"
    puts $outfile "Memory bits: $mem_bit"
    puts $outfile "RAM blocks: $m9k"
    puts $outfile "Actual clock freq: $pll_1x_setting"
    puts $outfile "Kernel fmax: $fmax1"
    puts $outfile "1x clock fmax: $fmax1"
    puts $outfile "2x clock fmax: $fmax2"

    #print to terminal/quartus_sh_compile.log, too.
    post_message "adjust_plls.tcl: ALUTs: $aluts"
    post_message "adjust_plls.tcl: Registers: $registers"
    post_message "adjust_plls.tcl: Logic utilization: $logicutil"
    post_message "adjust_plls.tcl: I/O pins: $io_pin"
    post_message "adjust_plls.tcl: DSP blocks: $dsp"
    post_message "adjust_plls.tcl: Memory bits: $mem_bit"
    post_message "adjust_plls.tcl: RAM blocks: $m9k"
    post_message "adjust_plls.tcl: Actual clock freq: $pll_1x_setting"
    post_message "adjust_plls.tcl: Kernel fmax: $fmax1"
    post_message "adjust_plls.tcl: 1x clock fmax: $fmax1"
    post_message "adjust_plls.tcl: 2x clock fmax: $fmax2"
    
    # Highest non-global fanout signal
    set result [find_report_panel_row "Fitter||Place Stage||Fitter Resource Usage Summary" 0 equal "Highest non-global fan-out"]
    if {[lindex $result 0] < 0} {error "Error: Could not find highest non-global fan-out (error $retval)"}
    set high_fanout_signal_fanout_count [get_report_panel_data -id [lindex $result 1] -row [lindex $result 2] -col 1]
    puts $outfile "Highest non-global fanout: $high_fanout_signal_fanout_count"
    close $outfile
    # End little report
    
    # write  file for kernel freq metadata
    set clockfile   [open "pll_metadata.txt" w]
    puts $clockfile "clock-frequency-low:$pll_1x_setting clock-frequency-high:$pll_2x_setting"
    close $clockfile
    
    # convert frequency (used in the OPAE packager) to period (used in user_clock.sdc)
    set period [expr 1000.0 / $fmax1]
    #cut off to 2 decimal places
    set period [expr {double(round(100*$period))/100}]
    
    set period2 [expr 1000.0 / $fmax2]
    #cut off to 2 decimal places
    set period2 [expr {double(round(100*$period2))/100}]
    
    #If the fast-kernel-clock has no real fanout,
    # disable the minimum-pulse-width timing warning because it isn't relevant. Write the constraint to the user_clock.sdc file.
    set disable_mpw_sdccmd " "
    if {$DISABLE_MPW_CHECK_ON_UNUSED_FAST_CLK == 1} {
        if {$clk2x_has_no_fanout == 1} {
            post_message "If clk2x isn't used, a Minimum Pulse Width violation might be flagged."
            post_message "Disabling it on this clock because it has no real targets in this design."
            set disable_mpw_sdccmd "disable_min_pulse_width $k_clk2x_name; disable_min_pulse_width $k_clk2x_altname"
        }
    }
    post_message "clk1x period: $period"
    post_message "clk2x period: $period2"
    
    set saved_user_clock_filename "user_clock_orig_${timing_loop_cnt}.sdc"
    file rename -force user_clock.sdc $saved_user_clock_filename
    
    set sdcfile   [open "user_clock.sdc" w]
    puts $sdcfile "#updated user-clock.sdc assignments based on fmax from previous fit attempt."
    puts $sdcfile "puts \"Updated user-clock constraints based on fmax from previous fit attempt.\" "
    puts $sdcfile "create_clock -name {afu_top|port_gasket|user_clock|qph_user_clk|qph_user_clk_iopll|iopll_0_outclk0} -period $period2 \[get_pins {afu_top|port_gasket|user_clock|qph_user_clk|qph_user_clk_iopll|iopll_0|tennm_pll|outclk[1]}]"
    puts $sdcfile "create_clock -name {afu_top|port_gasket|user_clock|qph_user_clk|qph_user_clk_iopll|iopll_0_outclk1} -period $period \[get_pins {afu_top|port_gasket|user_clock|qph_user_clk|qph_user_clk_iopll|iopll_0|tennm_pll|outclk[2]}] "
    puts $sdcfile "$disable_mpw_sdccmd"
    close $sdcfile
    
    # Force sta timing netlist to be rebuilt
    file delete [glob -nocomplain db/$revision_name.sta_cmp.*.tdb]
    file delete [glob -nocomplain qdb/_compiler/$revision_name/root_partition/*/final/1/*cache*]
    file delete [glob -nocomplain qdb/_compiler/$revision_name/root_partition/*/final/1/timing_netlist*]
    
    # Re-run STA
    file delete [glob -nocomplain *.failing_clocks.rpt]
    file delete [glob -nocomplain *.failing_paths.rpt]
    set sdk_root [string map {"\\" "/"} $::env(INTELFPGAOCLSDKROOT)]
    post_message "Launching STA with report script $sdk_root/ip/board/bsp/failing_clocks.tcl"
    if {[catch {execute_module -tool sta -args "--report_script=$sdk_root/ip/board/bsp/failing_clocks.tcl"} result]} {
        post_message -type error "Error! Timing analysis failed $result"
    }
    
    project_close
    
    set failing_clocks_filename "${revision_name}.failing_clocks.rpt"
    #look for the kernel clocks having setup violations in the failing_clocks output report; if they exist, repeat the loop with the new kernel clock settings
    post_message "Looking for the kernel-clocks being mentioned with setup violations in the failing-clocks reports..."
    if {[catch {exec grep ${k_clk_name} ${failing_clocks_filename} | grep {Setup} } result]} {
        post_message "No setup violations on ${k_clk_name}."
    } else {
        post_message "There is a setup violation on ${k_clk_name}."
        incr kernel_timing_err_cnt
    }
    if {[catch {exec grep ${k_clk2x_name} ${failing_clocks_filename} | grep {Setup} } result]} {
        post_message "No setup violations on ${k_clk2x_name}."
    } else {
        post_message "There is a setup violation on ${k_clk2x_name}."
        incr kernel_timing_err_cnt
    }
    #look for the kernel clocks having recovery violations in the failing_clocks output report; if they exist, repeat the loop with the new kernel clock settings
    post_message "Looking for the kernel-clocks being mentioned with recovery violations in the failing-clocks reports..."
    if {[catch {exec grep ${k_clk_name} ${failing_clocks_filename} | grep {Recovery} } result]} {
        post_message "No recovery violations on ${k_clk_name}."
    } else {
        post_message "There is a recovery violation on ${k_clk_name}."
        incr kernel_timing_err_cnt
    }
    if {[catch {exec grep ${k_clk2x_name} ${failing_clocks_filename} | grep {Recovery} } result]} {
        post_message "No recovery violations on ${k_clk2x_name}."
    } else {
        post_message "There is a recovery violation on ${k_clk2x_name}."
        incr kernel_timing_err_cnt
    }
    if {$kernel_timing_err_cnt == 0} { set timing_clean 1}
    
    incr timing_loop_cnt
}

post_message -type info "The Adjust PLLs script is done."
