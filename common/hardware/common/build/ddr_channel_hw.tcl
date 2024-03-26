package require -exact qsys 17.0

# module properties
set_module_property NAME {ddr_channel}
set_module_property DISPLAY_NAME {oneAPI ASP DDR channel IP}
set_module_property VERSION {23.2}
set_module_property GROUP {oneAPI ASP Components}
set_module_property DESCRIPTION {Clock crossers and pipeline stages to connect to DDR}
set_module_property AUTHOR {OFS}
set_module_property COMPOSITION_CALLBACK compose

# +-----------------------------------
# | parameters
# | 
add_parameter MEMORY_BANK_ADDRESS_WIDTH INTEGER 32
set_parameter_property MEMORY_BANK_ADDRESS_WIDTH DEFAULT_VALUE 32
set_parameter_property MEMORY_BANK_ADDRESS_WIDTH DISPLAY_NAME "Memory Bank Address Width"
set_parameter_property MEMORY_BANK_ADDRESS_WIDTH AFFECTS_ELABORATION true

add_parameter DATA_WIDTH INTEGER 512
set_parameter_property DATA_WIDTH DEFAULT_VALUE 512
set_parameter_property DATA_WIDTH DISPLAY_NAME "Data Width"
set_parameter_property DATA_WIDTH AFFECTS_ELABORATION true

add_parameter MAX_BURST_SIZE INTEGER 16
set_parameter_property MAX_BURST_SIZE DEFAULT_VALUE 16
set_parameter_property MAX_BURST_SIZE DISPLAY_NAME "Maximum Burst Size"
set_parameter_property MAX_BURST_SIZE AFFECTS_ELABORATION true

add_parameter KERNEL_GLOBALMEM_WAITREQUEST_ALLOWANCE INTEGER 6
set_parameter_property KERNEL_GLOBALMEM_WAITREQUEST_ALLOWANCE DEFAULT_VALUE 6
set_parameter_property KERNEL_GLOBALMEM_WAITREQUEST_ALLOWANCE DISPLAY_NAME "Kernel to global memory waitrequest allowance"
set_parameter_property KERNEL_GLOBALMEM_WAITREQUEST_ALLOWANCE AFFECTS_ELABORATION true

add_parameter MBD_TO_MEMORY_PIPE_STAGES INTEGER 0
set_parameter_property MBD_TO_MEMORY_PIPE_STAGES DEFAULT_VALUE 0
set_parameter_property MBD_TO_MEMORY_PIPE_STAGES DISPLAY_NAME "MBD to Memory Pipeline Stages"
set_parameter_property MBD_TO_MEMORY_PIPE_STAGES AFFECTS_ELABORATION true
# | 
# +-----------------------------------

proc compose { } {
  # Get parameters
  set memory_bank_address_width              [ get_parameter_value MEMORY_BANK_ADDRESS_WIDTH ]
  set data_width                             [ get_parameter_value DATA_WIDTH ]
  set max_burst_size                         [ get_parameter_value MAX_BURST_SIZE ]
  set kernel_globalmem_waitrequest_allowance [ get_parameter_value KERNEL_GLOBALMEM_WAITREQUEST_ALLOWANCE ]
  set mbd_to_memory_pipe_stages              [ get_parameter_value MBD_TO_MEMORY_PIPE_STAGES ]

  # Compute parameters
  set log2_burst [ expr log($max_burst_size) / log(2) ]
  set log2_burst_plus_one [ expr $log2_burst + 1 ]
  set symbol_width 8
  set symbols_per_data_word [ expr $data_width / $symbol_width ]

  # Instances and instance parameters
  add_instance host_clk altera_clock_bridge 19.2.0
  set_instance_parameter_value host_clk {EXPLICIT_CLOCK_RATE} {0.0}
  set_instance_parameter_value host_clk {NUM_CLOCK_OUTPUTS} {1}
  
  add_instance kernel_clk altera_clock_bridge 19.2.0
  set_instance_parameter_value kernel_clk {EXPLICIT_CLOCK_RATE} {0.0}
  set_instance_parameter_value kernel_clk {NUM_CLOCK_OUTPUTS} {1}

  add_instance ddr_clk altera_clock_bridge 19.2.0
  set_instance_parameter_value ddr_clk {EXPLICIT_CLOCK_RATE} {0.0}
  set_instance_parameter_value ddr_clk {NUM_CLOCK_OUTPUTS} {1}

  add_instance global_reset altera_reset_bridge 19.2.0
  set_instance_parameter_value global_reset {ACTIVE_LOW_RESET} {0}
  set_instance_parameter_value global_reset {SYNCHRONOUS_EDGES} {deassert}
  set_instance_parameter_value global_reset {NUM_RESET_OUTPUTS} {1}

  add_instance ddr4_emif_pipe acl_avalon_mm_bridge_s10 16.930
  set_instance_parameter_value ddr4_emif_pipe {DATA_WIDTH} $data_width
  set_instance_parameter_value ddr4_emif_pipe {SYMBOL_WIDTH} $symbol_width
  set_instance_parameter_value ddr4_emif_pipe {ADDRESS_WIDTH} $memory_bank_address_width
  set_instance_parameter_value ddr4_emif_pipe {ADDRESS_UNITS} {SYMBOLS}
  set_instance_parameter_value ddr4_emif_pipe {MAX_BURST_SIZE} $max_burst_size
  set_instance_parameter_value ddr4_emif_pipe {MAX_PENDING_RESPONSES} {16}
  set_instance_parameter_value ddr4_emif_pipe {LINEWRAPBURSTS} {0}
  set_instance_parameter_value ddr4_emif_pipe {SYNCHRONIZE_RESET} {1}
  set_instance_parameter_value ddr4_emif_pipe {DISABLE_WAITREQUEST_BUFFERING} {0}
  set_instance_parameter_value ddr4_emif_pipe {READDATA_PIPE_DEPTH} {1}
  set_instance_parameter_value ddr4_emif_pipe {CMD_PIPE_DEPTH} {1}

  add_instance ddr4_cross_to_kernel acl_clock_crossing_bridge 1.0
  set_instance_parameter_value ddr4_cross_to_kernel {ADDRESS_WIDTH} $memory_bank_address_width
  set_instance_parameter_value ddr4_cross_to_kernel {DATA_WIDTH} $data_width
  set_instance_parameter_value ddr4_cross_to_kernel {BURSTCOUNT_WIDTH} $log2_burst_plus_one
  set_instance_parameter_value ddr4_cross_to_kernel {BYTEENABLE_WIDTH} $symbols_per_data_word
  set_instance_parameter_value ddr4_cross_to_kernel {CMD_DCFIFO_MIN_DEPTH} {512}
  set_instance_parameter_value ddr4_cross_to_kernel {RSP_DCFIFO_MIN_DEPTH} {512}
  set_instance_parameter_value ddr4_cross_to_kernel {AGENT_STALL_LATENCY} $kernel_globalmem_waitrequest_allowance
  set_instance_parameter_value ddr4_cross_to_kernel {HOST_STALL_LATENCY} {0}
  set_instance_parameter_value ddr4_cross_to_kernel {USE_WRITE_ACK} {0}

  add_instance ddr4_pipe_to_kernel acl_avalon_mm_bridge_s10 16.930
  set_instance_parameter_value ddr4_pipe_to_kernel {DATA_WIDTH} $data_width
  set_instance_parameter_value ddr4_pipe_to_kernel {SYMBOL_WIDTH} $symbol_width
  set_instance_parameter_value ddr4_pipe_to_kernel {ADDRESS_WIDTH} $memory_bank_address_width
  set_instance_parameter_value ddr4_pipe_to_kernel {ADDRESS_UNITS} {SYMBOLS}
  set_instance_parameter_value ddr4_pipe_to_kernel {MAX_BURST_SIZE} $max_burst_size
  set_instance_parameter_value ddr4_pipe_to_kernel {MAX_PENDING_RESPONSES} {256}
  set_instance_parameter_value ddr4_pipe_to_kernel {LINEWRAPBURSTS} {0}
  set_instance_parameter_value ddr4_pipe_to_kernel {SYNCHRONIZE_RESET} {1}
  set_instance_parameter_value ddr4_pipe_to_kernel {DISABLE_WAITREQUEST_BUFFERING} {1}
  set_instance_parameter_value ddr4_pipe_to_kernel {READDATA_PIPE_DEPTH} {1}
  set_instance_parameter_value ddr4_pipe_to_kernel {CMD_PIPE_DEPTH} {1}

  add_instance ddr4_cross_to_host acl_clock_crossing_bridge 1.0
  set_instance_parameter_value ddr4_cross_to_host {ADDRESS_WIDTH} $memory_bank_address_width
  set_instance_parameter_value ddr4_cross_to_host {DATA_WIDTH} $data_width
  set_instance_parameter_value ddr4_cross_to_host {BURSTCOUNT_WIDTH} $log2_burst_plus_one
  set_instance_parameter_value ddr4_cross_to_host {BYTEENABLE_WIDTH} $symbols_per_data_word
  set_instance_parameter_value ddr4_cross_to_host {CMD_DCFIFO_MIN_DEPTH} {512}
  set_instance_parameter_value ddr4_cross_to_host {RSP_DCFIFO_MIN_DEPTH} {512}
  set_instance_parameter_value ddr4_cross_to_host {AGENT_STALL_LATENCY} {0}
  set_instance_parameter_value ddr4_cross_to_host {HOST_STALL_LATENCY} {0}
  set_instance_parameter_value ddr4_cross_to_host {USE_WRITE_ACK} {0}

  for { set i 0} { $i < $mbd_to_memory_pipe_stages} {incr i} {
    add_instance ddr4_pipe_to_bankdiv$i acl_avalon_mm_bridge_s10 16.930
    set_instance_parameter_value ddr4_pipe_to_bankdiv$i {DATA_WIDTH} $data_width
    set_instance_parameter_value ddr4_pipe_to_bankdiv$i {SYMBOL_WIDTH} $symbol_width
    set_instance_parameter_value ddr4_pipe_to_bankdiv$i {ADDRESS_WIDTH} $memory_bank_address_width
    set_instance_parameter_value ddr4_pipe_to_bankdiv$i {ADDRESS_UNITS} {SYMBOLS}
    set_instance_parameter_value ddr4_pipe_to_bankdiv$i {MAX_BURST_SIZE} $max_burst_size
    set_instance_parameter_value ddr4_pipe_to_bankdiv$i {MAX_PENDING_RESPONSES} {256}
    set_instance_parameter_value ddr4_pipe_to_bankdiv$i {LINEWRAPBURSTS} {0}
    set_instance_parameter_value ddr4_pipe_to_bankdiv$i {SYNCHRONIZE_RESET} {1}
    set_instance_parameter_value ddr4_pipe_to_bankdiv$i {DISABLE_WAITREQUEST_BUFFERING} {0}
    set_instance_parameter_value ddr4_pipe_to_bankdiv$i {READDATA_PIPE_DEPTH} {1}
    set_instance_parameter_value ddr4_pipe_to_bankdiv$i {CMD_PIPE_DEPTH} {1}
  }  

  # Connections and connection parameters
  # Clocks
  add_connection host_clk.out_clk global_reset.clk clock
  add_connection host_clk.out_clk ddr4_cross_to_host.agent_clk clock

  for { set i 0} { $i < $mbd_to_memory_pipe_stages} {incr i} {
    add_connection host_clk.out_clk ddr4_pipe_to_bankdiv$i.clk clock
  }

  add_connection kernel_clk.out_clk ddr4_cross_to_kernel.agent_clk clock
  add_connection kernel_clk.out_clk ddr4_pipe_to_kernel.clk clock
  add_connection ddr_clk.out_clk ddr4_emif_pipe.clk clock
  add_connection ddr_clk.out_clk ddr4_cross_to_kernel.host_clk clock
  add_connection ddr_clk.out_clk ddr4_cross_to_host.host_clk clock

  # Resets
  add_connection global_reset.out_reset ddr4_emif_pipe.reset reset
  add_connection global_reset.out_reset ddr4_cross_to_kernel.host_reset reset
  add_connection global_reset.out_reset ddr4_pipe_to_kernel.reset reset
  add_connection global_reset.out_reset ddr4_cross_to_host.host_reset reset

  for { set i 0} { $i < $mbd_to_memory_pipe_stages} {incr i} {
    add_connection global_reset.out_reset ddr4_pipe_to_bankdiv$i.reset reset
  }

  # Data
  add_connection ddr4_cross_to_host.host ddr4_emif_pipe.s0 avalon
  set_connection_parameter_value ddr4_cross_to_host.host/ddr4_emif_pipe.s0 arbitrationPriority {1}
  set_connection_parameter_value ddr4_cross_to_host.host/ddr4_emif_pipe.s0 baseAddress {0x0}
  set_connection_parameter_value ddr4_cross_to_host.host/ddr4_emif_pipe.s0 defaultConnection {0}

  add_connection ddr4_cross_to_kernel.host ddr4_emif_pipe.s0 avalon
  set_connection_parameter_value ddr4_cross_to_kernel.host/ddr4_emif_pipe.s0 arbitrationPriority {1}
  set_connection_parameter_value ddr4_cross_to_kernel.host/ddr4_emif_pipe.s0 baseAddress {0x0}
  set_connection_parameter_value ddr4_cross_to_kernel.host/ddr4_emif_pipe.s0 defaultConnection {0}

  add_connection ddr4_pipe_to_kernel.m0 ddr4_cross_to_kernel.agent avalon
  set_connection_parameter_value ddr4_pipe_to_kernel.m0/ddr4_cross_to_kernel.agent arbitrationPriority {1}
  set_connection_parameter_value ddr4_pipe_to_kernel.m0/ddr4_cross_to_kernel.agent baseAddress {0x0}
  set_connection_parameter_value ddr4_pipe_to_kernel.m0/ddr4_cross_to_kernel.agent defaultConnection {0}

  if { $mbd_to_memory_pipe_stages >= 1 } {
    add_connection ddr4_pipe_to_bankdiv0.m0 ddr4_cross_to_host.agent avalon
    set_connection_parameter_value ddr4_pipe_to_bankdiv0.m0/ddr4_cross_to_host.agent arbitrationPriority {1}
    set_connection_parameter_value ddr4_pipe_to_bankdiv0.m0/ddr4_cross_to_host.agent baseAddress {0x0}
    set_connection_parameter_value ddr4_pipe_to_bankdiv0.m0/ddr4_cross_to_host.agent defaultConnection {0}
  }
  
  for { set i 0} { $i < [ expr $mbd_to_memory_pipe_stages - 1] } {incr i} {
    set bankdiv_index [ expr $i + 1 ]
    add_connection ddr4_pipe_to_bankdiv${bankdiv_index}.m0 ddr4_pipe_to_bankdiv$i.s0 avalon
    set_connection_parameter_value ddr4_pipe_to_bankdiv${bankdiv_index}.m0/ddr4_pipe_to_bankdiv$i.s0 arbitrationPriority {1}
    set_connection_parameter_value ddr4_pipe_to_bankdiv${bankdiv_index}.m0/ddr4_pipe_to_bankdiv$i.s0 baseAddress {0x0}
    set_connection_parameter_value ddr4_pipe_to_bankdiv${bankdiv_index}.m0/ddr4_pipe_to_bankdiv$i.s0 defaultConnection {0}
  }

  # Exported interfaces
  # Clocks
  add_interface host_clk clock sink
  set_interface_property host_clk EXPORT_OF host_clk.in_clk
  add_interface kernel_clk clock sink
  set_interface_property kernel_clk EXPORT_OF kernel_clk.in_clk
  add_interface ddr_clk clock sink
  set_interface_property ddr_clk EXPORT_OF ddr_clk.in_clk
  
  # Resets
  add_interface global_reset reset sink
  set_interface_property global_reset EXPORT_OF global_reset.in_reset
   
  # Data 
  add_interface ddr4_emif avalon master
  set_interface_property ddr4_emif EXPORT_OF ddr4_emif_pipe.m0
  add_interface kernel_ddr4 avalon slave
  set_interface_property kernel_ddr4 EXPORT_OF ddr4_pipe_to_kernel.s0
  add_interface ddr4_pipe_to_bankdiv avalon slave
  
  if { $mbd_to_memory_pipe_stages == 0 } {
    set_interface_property ddr4_pipe_to_bankdiv EXPORT_OF ddr4_cross_to_host.agent
  } else {
    set pipe_stage_index [ expr $mbd_to_memory_pipe_stages - 1 ]
    set_interface_property ddr4_pipe_to_bankdiv EXPORT_OF ddr4_pipe_to_bankdiv$pipe_stage_index.s0
  }

  # Interconnect requirements
  set_interconnect_requirement {$system} {qsys_mm.clockCrossingAdapter} {HANDSHAKE}
  set_interconnect_requirement {$system} {qsys_mm.maxAdditionalLatency} {0}
}

