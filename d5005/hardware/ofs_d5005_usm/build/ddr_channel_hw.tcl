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
# | 
# +-----------------------------------

proc compose { } {
  # Get parameters
  set memory_bank_address_width [ get_parameter_value MEMORY_BANK_ADDRESS_WIDTH ]

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
  set_instance_parameter_value ddr4_emif_pipe {DATA_WIDTH} {512}
  set_instance_parameter_value ddr4_emif_pipe {SYMBOL_WIDTH} {8}
  set_instance_parameter_value ddr4_emif_pipe {ADDRESS_WIDTH} $memory_bank_address_width
  set_instance_parameter_value ddr4_emif_pipe {ADDRESS_UNITS} {SYMBOLS}
  set_instance_parameter_value ddr4_emif_pipe {MAX_BURST_SIZE} {16}
  set_instance_parameter_value ddr4_emif_pipe {MAX_PENDING_RESPONSES} {64}
  set_instance_parameter_value ddr4_emif_pipe {LINEWRAPBURSTS} {0}
  set_instance_parameter_value ddr4_emif_pipe {SYNCHRONIZE_RESET} {1}
  set_instance_parameter_value ddr4_emif_pipe {DISABLE_WAITREQUEST_BUFFERING} {0}
  set_instance_parameter_value ddr4_emif_pipe {READDATA_PIPE_DEPTH} {1}
  set_instance_parameter_value ddr4_emif_pipe {CMD_PIPE_DEPTH} {1}

  add_instance ddr4_cross_to_kernel acl_clock_crossing_bridge 1.0
  set_instance_parameter_value ddr4_cross_to_kernel {ADDRESS_WIDTH} $memory_bank_address_width
  set_instance_parameter_value ddr4_cross_to_kernel {DATA_WIDTH} {512}
  set_instance_parameter_value ddr4_cross_to_kernel {BURSTCOUNT_WIDTH} {5}
  set_instance_parameter_value ddr4_cross_to_kernel {BYTEENABLE_WIDTH} {64}
  set_instance_parameter_value ddr4_cross_to_kernel {CMD_DCFIFO_MIN_DEPTH} {512}
  set_instance_parameter_value ddr4_cross_to_kernel {RSP_DCFIFO_MIN_DEPTH} {512}
  set_instance_parameter_value ddr4_cross_to_kernel {SLAVE_STALL_LATENCY} {6}
  set_instance_parameter_value ddr4_cross_to_kernel {MASTER_STALL_LATENCY} {0}
  set_instance_parameter_value ddr4_cross_to_kernel {USE_WRITE_ACK} {0}

  add_instance ddr4_pipe_to_kernel acl_avalon_mm_bridge_s10 16.930
  set_instance_parameter_value ddr4_pipe_to_kernel {DATA_WIDTH} {512}
  set_instance_parameter_value ddr4_pipe_to_kernel {SYMBOL_WIDTH} {8}
  set_instance_parameter_value ddr4_pipe_to_kernel {ADDRESS_WIDTH} $memory_bank_address_width
  set_instance_parameter_value ddr4_pipe_to_kernel {ADDRESS_UNITS} {SYMBOLS}
  set_instance_parameter_value ddr4_pipe_to_kernel {MAX_BURST_SIZE} {16}
  set_instance_parameter_value ddr4_pipe_to_kernel {MAX_PENDING_RESPONSES} {256}
  set_instance_parameter_value ddr4_pipe_to_kernel {LINEWRAPBURSTS} {0}
  set_instance_parameter_value ddr4_pipe_to_kernel {SYNCHRONIZE_RESET} {1}
  set_instance_parameter_value ddr4_pipe_to_kernel {DISABLE_WAITREQUEST_BUFFERING} {1}
  set_instance_parameter_value ddr4_pipe_to_kernel {READDATA_PIPE_DEPTH} {1}
  set_instance_parameter_value ddr4_pipe_to_kernel {CMD_PIPE_DEPTH} {1}

  add_instance ddr4_cross_to_host acl_clock_crossing_bridge 1.0
  set_instance_parameter_value ddr4_cross_to_host {ADDRESS_WIDTH} $memory_bank_address_width
  set_instance_parameter_value ddr4_cross_to_host {DATA_WIDTH} {512}
  set_instance_parameter_value ddr4_cross_to_host {BURSTCOUNT_WIDTH} {5}
  set_instance_parameter_value ddr4_cross_to_host {BYTEENABLE_WIDTH} {64}
  set_instance_parameter_value ddr4_cross_to_host {CMD_DCFIFO_MIN_DEPTH} {512}
  set_instance_parameter_value ddr4_cross_to_host {RSP_DCFIFO_MIN_DEPTH} {512}
  set_instance_parameter_value ddr4_cross_to_host {SLAVE_STALL_LATENCY} {0}
  set_instance_parameter_value ddr4_cross_to_host {MASTER_STALL_LATENCY} {0}
  set_instance_parameter_value ddr4_cross_to_host {USE_WRITE_ACK} {0}

  add_instance ddr4_pipe_to_bankdiv_0 acl_avalon_mm_bridge_s10 16.930
  set_instance_parameter_value ddr4_pipe_to_bankdiv_0 {DATA_WIDTH} {512}
  set_instance_parameter_value ddr4_pipe_to_bankdiv_0 {SYMBOL_WIDTH} {8}
  set_instance_parameter_value ddr4_pipe_to_bankdiv_0 {ADDRESS_WIDTH} {33}
  set_instance_parameter_value ddr4_pipe_to_bankdiv_0 {ADDRESS_UNITS} {SYMBOLS}
  set_instance_parameter_value ddr4_pipe_to_bankdiv_0 {MAX_BURST_SIZE} {16}
  set_instance_parameter_value ddr4_pipe_to_bankdiv_0 {MAX_PENDING_RESPONSES} {256}
  set_instance_parameter_value ddr4_pipe_to_bankdiv_0 {LINEWRAPBURSTS} {0}
  set_instance_parameter_value ddr4_pipe_to_bankdiv_0 {SYNCHRONIZE_RESET} {1}
  set_instance_parameter_value ddr4_pipe_to_bankdiv_0 {DISABLE_WAITREQUEST_BUFFERING} {0}
  set_instance_parameter_value ddr4_pipe_to_bankdiv_0 {READDATA_PIPE_DEPTH} {1}
  set_instance_parameter_value ddr4_pipe_to_bankdiv_0 {CMD_PIPE_DEPTH} {1}

  add_instance ddr4_pipe_to_bankdiv_1 acl_avalon_mm_bridge_s10 16.930
  set_instance_parameter_value ddr4_pipe_to_bankdiv_1 {DATA_WIDTH} {512}
  set_instance_parameter_value ddr4_pipe_to_bankdiv_1 {SYMBOL_WIDTH} {8}
  set_instance_parameter_value ddr4_pipe_to_bankdiv_1 {ADDRESS_WIDTH} {33}
  set_instance_parameter_value ddr4_pipe_to_bankdiv_1 {ADDRESS_UNITS} {SYMBOLS}
  set_instance_parameter_value ddr4_pipe_to_bankdiv_1 {MAX_BURST_SIZE} {16}
  set_instance_parameter_value ddr4_pipe_to_bankdiv_1 {MAX_PENDING_RESPONSES} {256}
  set_instance_parameter_value ddr4_pipe_to_bankdiv_1 {LINEWRAPBURSTS} {0}
  set_instance_parameter_value ddr4_pipe_to_bankdiv_1 {SYNCHRONIZE_RESET} {1}
  set_instance_parameter_value ddr4_pipe_to_bankdiv_1 {DISABLE_WAITREQUEST_BUFFERING} {0}
  set_instance_parameter_value ddr4_pipe_to_bankdiv_1 {READDATA_PIPE_DEPTH} {1}
  set_instance_parameter_value ddr4_pipe_to_bankdiv_1 {CMD_PIPE_DEPTH} {1}

  add_instance ddr4_pipe_to_bankdiv_2 acl_avalon_mm_bridge_s10 16.930
  set_instance_parameter_value ddr4_pipe_to_bankdiv_2 {DATA_WIDTH} {512}
  set_instance_parameter_value ddr4_pipe_to_bankdiv_2 {SYMBOL_WIDTH} {8}
  set_instance_parameter_value ddr4_pipe_to_bankdiv_2 {ADDRESS_WIDTH} {33}
  set_instance_parameter_value ddr4_pipe_to_bankdiv_2 {ADDRESS_UNITS} {SYMBOLS}
  set_instance_parameter_value ddr4_pipe_to_bankdiv_2 {MAX_BURST_SIZE} {16}
  set_instance_parameter_value ddr4_pipe_to_bankdiv_2 {MAX_PENDING_RESPONSES} {256}
  set_instance_parameter_value ddr4_pipe_to_bankdiv_2 {LINEWRAPBURSTS} {0}
  set_instance_parameter_value ddr4_pipe_to_bankdiv_2 {SYNCHRONIZE_RESET} {1}
  set_instance_parameter_value ddr4_pipe_to_bankdiv_2 {DISABLE_WAITREQUEST_BUFFERING} {0}
  set_instance_parameter_value ddr4_pipe_to_bankdiv_2 {READDATA_PIPE_DEPTH} {1}
  set_instance_parameter_value ddr4_pipe_to_bankdiv_2 {CMD_PIPE_DEPTH} {1}

  # Connections and connection parameters
  # Clocks
  add_connection host_clk.out_clk global_reset.clk clock
  add_connection host_clk.out_clk ddr4_cross_to_host.slave_clk clock
  add_connection host_clk.out_clk ddr4_pipe_to_bankdiv_0.clk clock
  add_connection host_clk.out_clk ddr4_pipe_to_bankdiv_1.clk clock
  add_connection host_clk.out_clk ddr4_pipe_to_bankdiv_2.clk clock
  add_connection kernel_clk.out_clk ddr4_cross_to_kernel.slave_clk clock
  add_connection kernel_clk.out_clk ddr4_pipe_to_kernel.clk clock
  add_connection ddr_clk.out_clk ddr4_emif_pipe.clk clock
  add_connection ddr_clk.out_clk ddr4_cross_to_kernel.master_clk clock
  add_connection ddr_clk.out_clk ddr4_cross_to_host.master_clk clock

  # Resets
  add_connection global_reset.out_reset ddr4_emif_pipe.reset reset
  add_connection global_reset.out_reset ddr4_cross_to_kernel.master_reset reset
  add_connection global_reset.out_reset ddr4_pipe_to_kernel.reset reset
  add_connection global_reset.out_reset ddr4_cross_to_host.master_reset reset
  add_connection global_reset.out_reset ddr4_pipe_to_bankdiv_0.reset reset
  add_connection global_reset.out_reset ddr4_pipe_to_bankdiv_1.reset reset
  add_connection global_reset.out_reset ddr4_pipe_to_bankdiv_2.reset reset

  # Data
  add_connection ddr4_cross_to_host.master ddr4_emif_pipe.s0 avalon
  set_connection_parameter_value ddr4_cross_to_host.master/ddr4_emif_pipe.s0 arbitrationPriority {1}
  set_connection_parameter_value ddr4_cross_to_host.master/ddr4_emif_pipe.s0 baseAddress {0x0}
  set_connection_parameter_value ddr4_cross_to_host.master/ddr4_emif_pipe.s0 defaultConnection {0}

  add_connection ddr4_cross_to_kernel.master ddr4_emif_pipe.s0 avalon
  set_connection_parameter_value ddr4_cross_to_kernel.master/ddr4_emif_pipe.s0 arbitrationPriority {1}
  set_connection_parameter_value ddr4_cross_to_kernel.master/ddr4_emif_pipe.s0 baseAddress {0x0}
  set_connection_parameter_value ddr4_cross_to_kernel.master/ddr4_emif_pipe.s0 defaultConnection {0}

  add_connection ddr4_pipe_to_kernel.m0 ddr4_cross_to_kernel.slave avalon
  set_connection_parameter_value ddr4_pipe_to_kernel.m0/ddr4_cross_to_kernel.slave arbitrationPriority {1}
  set_connection_parameter_value ddr4_pipe_to_kernel.m0/ddr4_cross_to_kernel.slave baseAddress {0x0}
  set_connection_parameter_value ddr4_pipe_to_kernel.m0/ddr4_cross_to_kernel.slave defaultConnection {0}

  add_connection ddr4_pipe_to_bankdiv_2.m0 ddr4_pipe_to_bankdiv_1.s0 avalon
  set_connection_parameter_value ddr4_pipe_to_bankdiv_2.m0/ddr4_pipe_to_bankdiv_1.s0 arbitrationPriority {1}
  set_connection_parameter_value ddr4_pipe_to_bankdiv_2.m0/ddr4_pipe_to_bankdiv_1.s0 baseAddress {0x0}
  set_connection_parameter_value ddr4_pipe_to_bankdiv_2.m0/ddr4_pipe_to_bankdiv_1.s0 defaultConnection {0}

  add_connection ddr4_pipe_to_bankdiv_1.m0 ddr4_pipe_to_bankdiv_0.s0 avalon
  set_connection_parameter_value ddr4_pipe_to_bankdiv_1.m0/ddr4_pipe_to_bankdiv_0.s0 arbitrationPriority {1}
  set_connection_parameter_value ddr4_pipe_to_bankdiv_1.m0/ddr4_pipe_to_bankdiv_0.s0 baseAddress {0x0}
  set_connection_parameter_value ddr4_pipe_to_bankdiv_1.m0/ddr4_pipe_to_bankdiv_0.s0 defaultConnection {0}

  add_connection ddr4_pipe_to_bankdiv_0.m0 ddr4_cross_to_host.slave avalon
  set_connection_parameter_value ddr4_pipe_to_bankdiv_0.m0/ddr4_cross_to_host.slave arbitrationPriority {1}
  set_connection_parameter_value ddr4_pipe_to_bankdiv_0.m0/ddr4_cross_to_host.slave baseAddress {0x0}
  set_connection_parameter_value ddr4_pipe_to_bankdiv_0.m0/ddr4_cross_to_host.slave defaultConnection {0}

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
  set_interface_property ddr4_pipe_to_bankdiv EXPORT_OF ddr4_pipe_to_bankdiv_2.s0

  # Interconnect requirements
  set_interconnect_requirement {$system} {qsys_mm.clockCrossingAdapter} {HANDSHAKE}
  set_interconnect_requirement {$system} {qsys_mm.maxAdditionalLatency} {0}
}

