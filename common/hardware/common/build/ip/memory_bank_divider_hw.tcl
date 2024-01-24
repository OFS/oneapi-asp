package require -exact qsys 17.0

# module properties
set_module_property NAME {memory_bank_divider}
set_module_property DISPLAY_NAME {oneAPI Memory Bank Divider}

# default module properties
set_module_property VERSION {23.2}
set_module_property GROUP {oneAPI ASP Components}
set_module_property DESCRIPTION {Handles multiple global memory banks}
set_module_property AUTHOR {OFS}

# Set the name of the procedure to manipulate parameters
set_module_property COMPOSITION_CALLBACK compose

# +-----------------------------------
# | parameters
# | 
add_parameter NUM_BANKS INTEGER 2
set_parameter_property NUM_BANKS DEFAULT_VALUE 2
set_parameter_property NUM_BANKS ALLOWED_RANGES {1 2 4 8}
set_parameter_property NUM_BANKS DISPLAY_NAME "Number of banks"
set_parameter_property NUM_BANKS AFFECTS_ELABORATION true

add_parameter SEPARATE_RW_PORTS BOOLEAN false
set_parameter_property SEPARATE_RW_PORTS DEFAULT_VALUE false
set_parameter_property SEPARATE_RW_PORTS DISPLAY_NAME "Separate read/write ports"
set_parameter_property SEPARATE_RW_PORTS AFFECTS_ELABORATION true

add_parameter PIPELINE_OUTPUTS BOOLEAN false
set_parameter_property PIPELINE_OUTPUTS DEFAULT_VALUE false
set_parameter_property PIPELINE_OUTPUTS DISPLAY_NAME "Add pipeline stage to output"
set_parameter_property PIPELINE_OUTPUTS AFFECTS_ELABORATION true

add_parameter SPLIT_ON_BURSTBOUNDARY BOOLEAN false
set_parameter_property SPLIT_ON_BURSTBOUNDARY DEFAULT_VALUE false
set_parameter_property SPLIT_ON_BURSTBOUNDARY DISPLAY_NAME "Split read/write bursts on burst word boundary"
set_parameter_property SPLIT_ON_BURSTBOUNDARY AFFECTS_ELABORATION true

add_parameter DATA_WIDTH INTEGER 256
set_parameter_property DATA_WIDTH DEFAULT_VALUE 256
set_parameter_property DATA_WIDTH DISPLAY_NAME "Data Width"
set_parameter_property DATA_WIDTH UNITS "bits" 
set_parameter_property DATA_WIDTH AFFECTS_ELABORATION true
#set_parameter_property DATA_WIDTH SYSTEM_INFO {MAX_AGENT_DATA_WIDTH bank1}

add_parameter ADDRESS_WIDTH INTEGER 31
set_parameter_property ADDRESS_WIDTH DEFAULT_VALUE 31
set_parameter_property ADDRESS_WIDTH DISPLAY_NAME "Address Width (total addressable)"
set_parameter_property ADDRESS_WIDTH UNITS "bits"
set_parameter_property ADDRESS_WIDTH AFFECTS_ELABORATION true
#set_parameter_property ADDRESS_WIDTH SYSTEM_INFO {ADDRESS_WIDTH bank1}

add_parameter BURST_SIZE INTEGER 16
set_parameter_property BURST_SIZE DEFAULT_VALUE 16
set_parameter_property BURST_SIZE DISPLAY_NAME "Burst size (maximum)"
set_parameter_property BURST_SIZE UNITS ""
set_parameter_property BURST_SIZE AFFECTS_ELABORATION true

add_parameter MAX_PENDING_READS INTEGER 64
set_parameter_property MAX_PENDING_READS DEFAULT_VALUE 64
set_parameter_property MAX_PENDING_READS DISPLAY_NAME "Maximum Pending Reads"
set_parameter_property MAX_PENDING_READS UNITS ""
set_parameter_property MAX_PENDING_READS AFFECTS_ELABORATION true

add_parameter ASYNC_RESET INTEGER 1
set_parameter_property ASYNC_RESET DEFAULT_VALUE 1
set_parameter_property ASYNC_RESET DISPLAY_NAME "ASYNC_RESET"
set_parameter_property ASYNC_RESET UNITS ""
set_parameter_property ASYNC_RESET AFFECTS_ELABORATION true

add_parameter SYNCHRONIZE_RESET INTEGER 0
set_parameter_property SYNCHRONIZE_RESET DEFAULT_VALUE 0
set_parameter_property SYNCHRONIZE_RESET DISPLAY_NAME "SYNCHRONIZE_RESET"
set_parameter_property SYNCHRONIZE_RESET UNITS ""
set_parameter_property SYNCHRONIZE_RESET AFFECTS_ELABORATION true
# | 
# +-----------------------------------

proc add_burst_splitter { name width awidth burst_count pending_reads async_reset synchronize_reset} {
  add_instance $name burst_boundary_splitter 1.0

  set_instance_parameter_value $name WIDTH_D $width
  set_instance_parameter_value $name BYTE_WIDTH_A $awidth
  set_instance_parameter_value $name BURSTCOUNT_WIDTH $burst_count
  set_instance_parameter_value $name MAX_PENDING_READS $pending_reads
  set_instance_parameter_value $name ASYNC_RESET $async_reset
  set_instance_parameter_value $name SYNCHRONIZE_RESET $synchronize_reset
  
  add_connection clk.clk $name.clock
  add_connection clk.clk_reset $name.reset
}

proc add_pipeline_stage { name width awidth burst_width pending_reads } {
  add_instance $name acl_avalon_mm_bridge_s10 17.1
  set_instance_parameter_value $name {DATA_WIDTH} $width
  set_instance_parameter_value $name {SYMBOL_WIDTH} {8}
  set_instance_parameter_value $name {ADDRESS_WIDTH} $awidth
  set_instance_parameter_value $name {ADDRESS_UNITS} {SYMBOLS}
  set_instance_parameter_value $name {MAX_BURST_SIZE} [expr 1 << ( $burst_width - 1 ) ]
  set_instance_parameter_value $name {MAX_PENDING_RESPONSES} $pending_reads
  set_instance_parameter_value $name {LINEWRAPBURSTS} {0}
  set_instance_parameter_value $name {SYNCHRONIZE_RESET} {1}
  set_instance_parameter_value $name {DISABLE_WAITREQUEST_BUFFERING} {0}
  set_instance_parameter_value $name {READDATA_PIPE_DEPTH} {2}
  set_instance_parameter_value $name {CMD_PIPE_DEPTH} {1}

  add_connection clk.clk $name.clk
  add_connection clk.clk_reset $name.reset
}

proc export_bank { separate_rw_ports banknum banksplitter banksplitter_port width awidth burst_width pending_reads pipeline_outputs} {
  append bankname bank $banknum
  append bankname_r $bankname _r
  append bankname_w $bankname _w
  append dirsplitter acl_direction_splitter_ $banknum
  if { $separate_rw_ports == false } {
    add_interface $bankname avalon master
    if { $pipeline_outputs == false } {
      set_interface_property $bankname EXPORT_OF $banksplitter.$banksplitter_port
    } else {
      append pipe_stage_name pipe_stage_postsplitter $banknum

      add_pipeline_stage $pipe_stage_name $width $awidth $burst_width $pending_reads 

      add_connection $banksplitter.$banksplitter_port $pipe_stage_name.s0
      set_interface_property $bankname EXPORT_OF $pipe_stage_name.m0

    }
  } else {
    add_instance $dirsplitter acl_direction_splitter 13.0
    set_instance_parameter_value $dirsplitter WIDTH_D $width
    set_instance_parameter_value $dirsplitter BYTEENABLE_WIDTH [ expr $width / 8 ]
    set_instance_parameter_value $dirsplitter WIDTH_A $awidth
    set_instance_parameter_value $dirsplitter BURSTCOUNT_WIDTH $burst_width
    set_instance_parameter_value $dirsplitter MAX_PENDING_READS $pending_reads
    add_connection clk.clk $dirsplitter.clk
    add_connection clk.clk_reset $dirsplitter.clk_reset
    add_interface $bankname_r avalon master
    add_interface $bankname_w avalon master
    set_interface_property $bankname_r EXPORT_OF $dirsplitter.r
    set_interface_property $bankname_w EXPORT_OF $dirsplitter.w
    if { $pipeline_outputs == false } {
      add_connection $banksplitter.$banksplitter_port $dirsplitter.s
    } else {
      append pipe_stage_name pipe_stage_postsplitter $banknum

      # Add pipeline stage before direction splitter
      add_pipeline_stage $pipe_stage_name $width $awidth $burst_width $pending_reads 
      add_connection $banksplitter.$banksplitter_port $pipe_stage_name.s0
      add_connection $pipe_stage_name.m0 $dirsplitter.s
    }
  }
}


proc compose {} {

  # interconnect requirements
  set_interconnect_requirement {$system} {qsys_mm.clockCrossingAdapter} {FIFO}
  set_interconnect_requirement {$system} {qsys_mm.maxAdditionalLatency} {4}

  # Instances and instance parameters
  # (disabled instances are intentionally culled)
  add_instance clk clock_source 21.3
  set_instance_parameter_value clk clockFrequency {100000000.0}
  set_instance_parameter_value clk clockFrequencyKnown {1}
  set_instance_parameter_value clk resetSynchronousEdges {DEASSERT}

  add_instance acl_snoop_adapter acl_snoop_adapter 11.0

  add_instance kernel_clk clock_source 21.3
  set_instance_parameter_value kernel_clk clockFrequency {100000000.0}
  set_instance_parameter_value kernel_clk clockFrequencyKnown {1}
  set_instance_parameter_value kernel_clk resetSynchronousEdges {NONE}

  add_connection kernel_clk.clk acl_snoop_adapter.kernel_clk
  add_connection kernel_clk.clk_reset acl_snoop_adapter.kernel_reset
  add_connection clk.clk_reset acl_snoop_adapter.clk_reset
  add_connection clk.clk acl_snoop_adapter.clk

  # exported interfaces
  add_interface clk clock sink
  set_interface_property clk EXPORT_OF clk.clk_in
  add_interface reset reset sink
  set_interface_property reset EXPORT_OF clk.clk_in_reset
  add_interface kernel_clk clock sink
  set_interface_property kernel_clk EXPORT_OF kernel_clk.clk_in
  add_interface kernel_reset reset sink
  set_interface_property kernel_reset EXPORT_OF kernel_clk.clk_in_reset
  add_interface acl_asp_snoop avalon_streaming source
  set_interface_property acl_asp_snoop EXPORT_OF acl_snoop_adapter.snoop

  # manipulate parameters in here
  set width [get_parameter_value DATA_WIDTH]
  set pending_reads [get_parameter_value MAX_PENDING_READS]
  set num_banks [ get_parameter_value NUM_BANKS]
  set separate_rw_ports [ get_parameter_value SEPARATE_RW_PORTS]
  set pipeline_outputs [ get_parameter_value PIPELINE_OUTPUTS]
  set split_bursts [ get_parameter_value SPLIT_ON_BURSTBOUNDARY]
  set log2_num_banks [ expr log($num_banks) / log(2) ]
  set log2_bank_byte_width [ expr log([get_parameter_value DATA_WIDTH]) / log(2) - 3 ]
  set aggr_awidth [ get_parameter_value ADDRESS_WIDTH ]
  set bank_awidth [expr $aggr_awidth - $log2_num_banks ]
  set burst_size [get_parameter_value BURST_SIZE]
  set burst_width [ expr int(log($burst_size)/log(2)) + 1]
  set async_reset [get_parameter_value ASYNC_RESET]
  set synchronize_reset [get_parameter_value SYNCHRONIZE_RESET]
  
  if { $split_bursts == true } {
    append burst_split_ip_name burst_splitter
    add_burst_splitter $burst_split_ip_name $width $aggr_awidth $burst_width $pending_reads $async_reset $synchronize_reset
    add_interface s avalon slave
    set_interface_property s EXPORT_OF $burst_split_ip_name.agent
    add_connection $burst_split_ip_name.host acl_snoop_adapter.s1
  } else {
    add_interface s avalon slave
    set_interface_property s EXPORT_OF acl_snoop_adapter.s1
  }

  set_instance_parameter_value acl_snoop_adapter BYTE_ADDRESS_WIDTH $aggr_awidth
  set_instance_parameter_value acl_snoop_adapter BURSTCOUNT_WIDTH $burst_width
  set_instance_parameter_value acl_snoop_adapter NUM_BYTES [expr $width / 8]
  set_instance_parameter_value acl_snoop_adapter PENDING_READS $pending_reads

  if { $num_banks > 1 }  {
    add_instance mem_splitter mem_splitter 21.3
    set_instance_parameter_value mem_splitter NUM_BANKS $num_banks
    set_instance_parameter_value mem_splitter WIDTH_D $width
    set_instance_parameter_value mem_splitter M_WIDTH_A $bank_awidth
    set_instance_parameter_value mem_splitter BURSTCOUNT_WIDTH $burst_width
    set_instance_parameter_value mem_splitter MAX_PENDING_READS $pending_reads
    set_instance_parameter_value mem_splitter ASYNC_RESET $async_reset
    set_instance_parameter_value mem_splitter SYNCHRONIZE_RESET $synchronize_reset

    add_instance pipe_stage_presplitter acl_avalon_mm_bridge_s10 17.1
    set_instance_parameter_value pipe_stage_presplitter {DATA_WIDTH} $width
    set_instance_parameter_value pipe_stage_presplitter {SYMBOL_WIDTH} {8}
    set_instance_parameter_value pipe_stage_presplitter {ADDRESS_WIDTH} $aggr_awidth
    set_instance_parameter_value pipe_stage_presplitter {ADDRESS_UNITS} {SYMBOLS}
    set_instance_parameter_value pipe_stage_presplitter {MAX_BURST_SIZE} $burst_size
    set_instance_parameter_value pipe_stage_presplitter {MAX_PENDING_RESPONSES} $pending_reads
    set_instance_parameter_value pipe_stage_presplitter {LINEWRAPBURSTS} {0}
    set_instance_parameter_value pipe_stage_presplitter {SYNCHRONIZE_RESET} {1}
    set_instance_parameter_value pipe_stage_presplitter {DISABLE_WAITREQUEST_BUFFERING} {0}
    set_instance_parameter_value pipe_stage_presplitter {READDATA_PIPE_DEPTH} {2}
    set_instance_parameter_value pipe_stage_presplitter {CMD_PIPE_DEPTH} {1}

    # connections and connection parameters
    add_connection acl_snoop_adapter.m1 pipe_stage_presplitter.s0
    set_connection_parameter_value acl_snoop_adapter.m1/pipe_stage_presplitter.s0 arbitrationPriority {1}
    set_connection_parameter_value acl_snoop_adapter.m1/pipe_stage_presplitter.s0 baseAddress {0x0000}

    add_connection pipe_stage_presplitter.m0 mem_splitter.s
    set_connection_parameter_value pipe_stage_presplitter.m0/mem_splitter.s arbitrationPriority {1}
    set_connection_parameter_value pipe_stage_presplitter.m0/mem_splitter.s baseAddress {0x0000}

    add_connection clk.clk pipe_stage_presplitter.clk

    add_connection clk.clk mem_splitter.clk

    add_connection clk.clk_reset mem_splitter.clk_reset

    add_connection clk.clk_reset pipe_stage_presplitter.reset

    add_interface acl_asp_memorg_host conduit end
    set_interface_property acl_asp_memorg_host EXPORT_OF mem_splitter.mode

    export_bank $separate_rw_ports 1 mem_splitter bank1 $width $bank_awidth $burst_width $pending_reads $pipeline_outputs
       
    if { $num_banks >= 2 } {
      export_bank $separate_rw_ports 2 mem_splitter bank2 $width $bank_awidth $burst_width $pending_reads $pipeline_outputs
    }
    
    if { $num_banks >= 3 } {
      export_bank $separate_rw_ports 3 mem_splitter bank3 $width $bank_awidth $burst_width $pending_reads $pipeline_outputs
    }
    
    if { $num_banks >= 4 } {
      export_bank $separate_rw_ports 4 mem_splitter bank4 $width $bank_awidth $burst_width $pending_reads $pipeline_outputs
    }
    
    if { $num_banks >= 5 } {
      export_bank $separate_rw_ports 5 mem_splitter bank5 $width $bank_awidth $burst_width $pending_reads $pipeline_outputs
    }
    
    if { $num_banks >= 6 } {
      export_bank $separate_rw_ports 6 mem_splitter bank6 $width $bank_awidth $burst_width $pending_reads $pipeline_outputs
    }
    
    if { $num_banks >= 7 } {
      export_bank $separate_rw_ports 7 mem_splitter bank7 $width $bank_awidth $burst_width $pending_reads $pipeline_outputs
    }
    
    if { $num_banks >= 8 } {
      export_bank $separate_rw_ports 8 mem_splitter bank8 $width $bank_awidth $burst_width $pending_reads $pipeline_outputs
    }

  } else { 
    # NUM_BANKS == 1
    export_bank $separate_rw_ports 1 acl_snoop_adapter m1 $width $bank_awidth $burst_width $pending_reads $pipeline_outputs
  }
}
