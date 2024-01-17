package require -exact qsys 17.0

# module properties
set_module_property NAME {ddr_board}
set_module_property DISPLAY_NAME {oneAPI ASP DDR board IP}
set_module_property VERSION {23.2}
set_module_property GROUP {oneAPI ASP Components}
set_module_property DESCRIPTION {Instantiation of multiple DDR channels}
set_module_property AUTHOR {OFS}
set_module_property COMPOSITION_CALLBACK compose

# +-----------------------------------
# | parameters
# |
add_parameter NUMBER_OF_MEMORY_BANKS INTEGER 4
set_parameter_property NUMBER_OF_MEMORY_BANKS DEFAULT_VALUE 4
set_parameter_property NUMBER_OF_MEMORY_BANKS DISPLAY_NAME "Number of Memory Banks"
set_parameter_property NUMBER_OF_MEMORY_BANKS AFFECTS_ELABORATION true

add_parameter MEMORY_BANK_ADDRESS_WIDTH INTEGER 32
set_parameter_property MEMORY_BANK_ADDRESS_WIDTH DEFAULT_VALUE 32
set_parameter_property MEMORY_BANK_ADDRESS_WIDTH DISPLAY_NAME "Memory Bank Address Width"
set_parameter_property MEMORY_BANK_ADDRESS_WIDTH AFFECTS_ELABORATION true

add_parameter SNOOP_PORT_ENABLE BOOLEAN false
set_parameter_property SNOOP_PORT_ENABLE DEFAULT_VALUE false
set_parameter_property SNOOP_PORT_ENABLE DISPLAY_NAME "Enable Snoop Port"
set_parameter_property SNOOP_PORT_ENABLE AFFECTS_ELABORATION true

add_parameter MBD_TO_MEMORY_PIPE_STAGES INTEGER 0
set_parameter_property MBD_TO_MEMORY_PIPE_STAGES DEFAULT_VALUE 0
set_parameter_property MBD_TO_MEMORY_PIPE_STAGES DISPLAY_NAME "MBD to Memory Pipeline Stages"
set_parameter_property MBD_TO_MEMORY_PIPE_STAGES AFFECTS_ELABORATION true
# | 
# +-----------------------------------

proc compose { } {
  # Get parameters
  set number_of_memory_banks    [ get_parameter_value NUMBER_OF_MEMORY_BANKS ]
  set memory_bank_address_width [ get_parameter_value MEMORY_BANK_ADDRESS_WIDTH ]
  set snoop_port_enable         [ get_parameter_value SNOOP_PORT_ENABLE ]
  set mbd_to_memory_pipe_stages [ get_parameter_value MBD_TO_MEMORY_PIPE_STAGES ]

  # Compute parameters
  set log2_num_banks [ expr log($number_of_memory_banks) / log(2) ]
  set total_address_width [ expr $memory_bank_address_width + $log2_num_banks ]

  # Instances and instance parameters
  add_instance host_clk altera_clock_bridge 19.2.0
  set_instance_parameter_value host_clk {EXPLICIT_CLOCK_RATE} {0.0}
  set_instance_parameter_value host_clk {NUM_CLOCK_OUTPUTS} {1}
  
  add_instance kernel_clk altera_clock_bridge 19.2.0
  set_instance_parameter_value kernel_clk {EXPLICIT_CLOCK_RATE} {0.0}
  set_instance_parameter_value kernel_clk {NUM_CLOCK_OUTPUTS} {1}

  for { set i 0} { $i < $number_of_memory_banks } {incr i} {
    add_instance ddr_clk$i altera_clock_bridge 19.2.0
    set_instance_parameter_value ddr_clk$i {EXPLICIT_CLOCK_RATE} {0.0}
    set_instance_parameter_value ddr_clk$i {NUM_CLOCK_OUTPUTS} {1}
  }

  set global_reset_outputs [expr $number_of_memory_banks + 1]
  add_instance global_reset altera_reset_bridge 19.2.0
  set_instance_parameter_value global_reset {ACTIVE_LOW_RESET} {0}
  set_instance_parameter_value global_reset {SYNCHRONOUS_EDGES} {both}
  set_instance_parameter_value global_reset {NUM_RESET_OUTPUTS} $global_reset_outputs

  add_instance kernel_reset altera_reset_bridge 19.2.0
  set_instance_parameter_value kernel_reset {ACTIVE_LOW_RESET} {0}
  set_instance_parameter_value kernel_reset {SYNCHRONOUS_EDGES} {deassert}
  set_instance_parameter_value kernel_reset {NUM_RESET_OUTPUTS} {1}

  for { set i 0} { $i < $number_of_memory_banks } {incr i} {
    add_instance ddr_channel$i ddr_channel 23.2
    set_instance_parameter_value ddr_channel$i {MEMORY_BANK_ADDRESS_WIDTH} $memory_bank_address_width
    set_instance_parameter_value ddr_channel$i {MBD_TO_MEMORY_PIPE_STAGES} $mbd_to_memory_pipe_stages
  }

  add_instance memory_bank_divider memory_bank_divider 21.3
  set_instance_parameter_value memory_bank_divider {NUM_BANKS} $number_of_memory_banks
  set_instance_parameter_value memory_bank_divider {SEPARATE_RW_PORTS} {false}
  set_instance_parameter_value memory_bank_divider {PIPELINE_OUTPUTS} {true}
  set_instance_parameter_value memory_bank_divider {SPLIT_ON_BURSTBOUNDARY} {true}
  set_instance_parameter_value memory_bank_divider {DATA_WIDTH} {512}
  set_instance_parameter_value memory_bank_divider {ADDRESS_WIDTH} $total_address_width
  set_instance_parameter_value memory_bank_divider {BURST_SIZE} {64}
  set_instance_parameter_value memory_bank_divider {MAX_PENDING_READS} {512}
  set_instance_parameter_value memory_bank_divider {ASYNC_RESET} {1}
  set_instance_parameter_value memory_bank_divider {SYNCHRONIZE_RESET} {1}

  add_instance dma_localmem_rdwr_pipe acl_avalon_mm_bridge_s10 16.930
  set_instance_parameter_value dma_localmem_rdwr_pipe {DATA_WIDTH} {512}
  set_instance_parameter_value dma_localmem_rdwr_pipe {SYMBOL_WIDTH} {8}
  set_instance_parameter_value dma_localmem_rdwr_pipe {ADDRESS_WIDTH} $total_address_width
  set_instance_parameter_value dma_localmem_rdwr_pipe {ADDRESS_UNITS} {SYMBOLS}
  set_instance_parameter_value dma_localmem_rdwr_pipe {MAX_BURST_SIZE} {64}
  set_instance_parameter_value dma_localmem_rdwr_pipe {MAX_PENDING_RESPONSES} {64}
  set_instance_parameter_value dma_localmem_rdwr_pipe {LINEWRAPBURSTS} {0}
  set_instance_parameter_value dma_localmem_rdwr_pipe {SYNCHRONIZE_RESET} {1}
  set_instance_parameter_value dma_localmem_rdwr_pipe {DISABLE_WAITREQUEST_BUFFERING} {0}
  set_instance_parameter_value dma_localmem_rdwr_pipe {READDATA_PIPE_DEPTH} {2}
  set_instance_parameter_value dma_localmem_rdwr_pipe {CMD_PIPE_DEPTH} {1}

  add_instance dma_localmem_rd_pipe acl_avalon_mm_bridge_s10 16.930
  set_instance_parameter_value dma_localmem_rd_pipe {DATA_WIDTH} {512}
  set_instance_parameter_value dma_localmem_rd_pipe {SYMBOL_WIDTH} {8}
  set_instance_parameter_value dma_localmem_rd_pipe {ADDRESS_WIDTH} $total_address_width
  set_instance_parameter_value dma_localmem_rd_pipe {ADDRESS_UNITS} {SYMBOLS}
  set_instance_parameter_value dma_localmem_rd_pipe {MAX_BURST_SIZE} {16}
  set_instance_parameter_value dma_localmem_rd_pipe {MAX_PENDING_RESPONSES} {64}
  set_instance_parameter_value dma_localmem_rd_pipe {LINEWRAPBURSTS} {0}
  set_instance_parameter_value dma_localmem_rd_pipe {SYNCHRONIZE_RESET} {1}
  set_instance_parameter_value dma_localmem_rd_pipe {DISABLE_WAITREQUEST_BUFFERING} {0}
  set_instance_parameter_value dma_localmem_rd_pipe {READDATA_PIPE_DEPTH} {2}
  set_instance_parameter_value dma_localmem_rd_pipe {CMD_PIPE_DEPTH} {1}

  add_instance dma_localmem_wr_pipe acl_avalon_mm_bridge_s10 16.930
  set_instance_parameter_value dma_localmem_wr_pipe {DATA_WIDTH} {512}
  set_instance_parameter_value dma_localmem_wr_pipe {SYMBOL_WIDTH} {8}
  set_instance_parameter_value dma_localmem_wr_pipe {ADDRESS_WIDTH} $total_address_width
  set_instance_parameter_value dma_localmem_wr_pipe {ADDRESS_UNITS} {SYMBOLS}
  set_instance_parameter_value dma_localmem_wr_pipe {MAX_BURST_SIZE} {16}
  set_instance_parameter_value dma_localmem_wr_pipe {MAX_PENDING_RESPONSES} {1}
  set_instance_parameter_value dma_localmem_wr_pipe {LINEWRAPBURSTS} {0}
  set_instance_parameter_value dma_localmem_wr_pipe {SYNCHRONIZE_RESET} {1}
  set_instance_parameter_value dma_localmem_wr_pipe {DISABLE_WAITREQUEST_BUFFERING} {0}
  set_instance_parameter_value dma_localmem_wr_pipe {READDATA_PIPE_DEPTH} {2}
  set_instance_parameter_value dma_localmem_wr_pipe {CMD_PIPE_DEPTH} {1}

  add_instance null_dfh_inst afu_id_avmm_slave 1.0
  set_instance_parameter_value null_dfh_inst {AFU_ID_H} {0xda1182b1b3444e23}
  set_instance_parameter_value null_dfh_inst {AFU_ID_L} {0x90fe6aab12a0132f}
  set_instance_parameter_value null_dfh_inst {DFH_FEATURE_TYPE} {2}
  set_instance_parameter_value null_dfh_inst {DFH_AFU_MINOR_REV} {0x0}
  set_instance_parameter_value null_dfh_inst {DFH_AFU_MAJOR_REV} {0x0}
  set_instance_parameter_value null_dfh_inst {DFH_END_OF_LIST} {0x1}
  set_instance_parameter_value null_dfh_inst {DFH_NEXT_OFFSET} {0x000000}
  set_instance_parameter_value null_dfh_inst {DFH_FEATURE_ID} {0x000}
  set_instance_parameter_value null_dfh_inst {NEXT_AFU_OFFSET} {0x000000}
  set_instance_parameter_value null_dfh_inst {CREATE_SCRATCH_REG} {0x0}

  # Connections and connection parameters
  # Clocks
  add_connection host_clk.out_clk global_reset.clk clock

  for { set i 0} { $i < $number_of_memory_banks } {incr i} {
    add_connection host_clk.out_clk ddr_channel$i.host_clk clock
  }

  add_connection host_clk.out_clk memory_bank_divider.clk clock
  add_connection host_clk.out_clk dma_localmem_rdwr_pipe.clk clock
  add_connection host_clk.out_clk dma_localmem_rd_pipe.clk clock
  add_connection host_clk.out_clk dma_localmem_wr_pipe.clk clock
  add_connection host_clk.out_clk null_dfh_inst.clock clock
  add_connection kernel_clk.out_clk kernel_reset.clk clock

  for { set i 0} { $i < $number_of_memory_banks } {incr i} {
    add_connection kernel_clk.out_clk ddr_channel$i.kernel_clk clock
  }

  add_connection kernel_clk.out_clk memory_bank_divider.kernel_clk clock

  for { set i 0} { $i < $number_of_memory_banks } {incr i} {
    add_connection ddr_clk$i.out_clk ddr_channel$i.ddr_clk clock
  }

  # Resets
  add_connection global_reset.out_reset memory_bank_divider.reset reset
  add_connection global_reset.out_reset dma_localmem_rdwr_pipe.reset reset
  add_connection global_reset.out_reset dma_localmem_rd_pipe.reset reset
  add_connection global_reset.out_reset dma_localmem_wr_pipe.reset reset
  add_connection global_reset.out_reset null_dfh_inst.reset reset

  for { set i 0} { $i < $number_of_memory_banks } {incr i} {
    set j [expr $i + 1]
    add_connection global_reset.out_reset_$j ddr_channel$i.global_reset reset
  }

  add_connection kernel_reset.out_reset memory_bank_divider.kernel_reset reset

  # Data
  add_connection dma_localmem_wr_pipe.m0 dma_localmem_rdwr_pipe.s0 avalon
  set_connection_parameter_value dma_localmem_wr_pipe.m0/dma_localmem_rdwr_pipe.s0 arbitrationPriority {1}
  set_connection_parameter_value dma_localmem_wr_pipe.m0/dma_localmem_rdwr_pipe.s0 baseAddress {0x0}
  set_connection_parameter_value dma_localmem_wr_pipe.m0/dma_localmem_rdwr_pipe.s0 defaultConnection {0}

  add_connection dma_localmem_rd_pipe.m0 dma_localmem_rdwr_pipe.s0 avalon
  set_connection_parameter_value dma_localmem_rd_pipe.m0/dma_localmem_rdwr_pipe.s0 arbitrationPriority {1}
  set_connection_parameter_value dma_localmem_rd_pipe.m0/dma_localmem_rdwr_pipe.s0 baseAddress {0x0}
  set_connection_parameter_value dma_localmem_rd_pipe.m0/dma_localmem_rdwr_pipe.s0 defaultConnection {0}

  add_connection dma_localmem_rdwr_pipe.m0 memory_bank_divider.s avalon
  set_connection_parameter_value dma_localmem_rdwr_pipe.m0/memory_bank_divider.s arbitrationPriority {1}
  set_connection_parameter_value dma_localmem_rdwr_pipe.m0/memory_bank_divider.s baseAddress {0x0}
  set_connection_parameter_value dma_localmem_rdwr_pipe.m0/memory_bank_divider.s defaultConnection {0}

  for { set i 0} { $i < $number_of_memory_banks } {incr i} {
    set j [expr $i + 1]
    add_connection memory_bank_divider.bank$j ddr_channel$i.ddr4_pipe_to_bankdiv avalon
    set_connection_parameter_value memory_bank_divider.bank$j/ddr_channel$i.ddr4_pipe_to_bankdiv arbitrationPriority {1}
    set_connection_parameter_value memory_bank_divider.bank$j/ddr_channel$i.ddr4_pipe_to_bankdiv baseAddress {0x0}
    set_connection_parameter_value memory_bank_divider.bank$j/ddr_channel$i.ddr4_pipe_to_bankdiv defaultConnection {0}
  }

  # Exported interfaces
  # Clocks
  add_interface host_clk clock sink
  set_interface_property host_clk EXPORT_OF host_clk.in_clk
  add_interface kernel_clk clock sink
  set_interface_property kernel_clk EXPORT_OF kernel_clk.in_clk

  for { set i 0} { $i < $number_of_memory_banks } {incr i} {
    add_interface ddr_clk$i clock sink
    set_interface_property ddr_clk$i EXPORT_OF ddr_clk$i.in_clk
  }

  # Resets
  add_interface global_reset reset sink
  set_interface_property global_reset EXPORT_OF global_reset.in_reset
  add_interface kernel_reset reset sink
  set_interface_property kernel_reset EXPORT_OF kernel_reset.in_reset
 
  # Data
  for { set i 0} { $i < $number_of_memory_banks } {incr i} {
    add_interface emif_ddr$i avalon master
    set_interface_property emif_ddr$i EXPORT_OF ddr_channel$i.ddr4_emif
    add_interface kernel_ddr$i avalon slave
    set_interface_property kernel_ddr$i EXPORT_OF ddr_channel$i.kernel_ddr4
  }

  if { $snoop_port_enable == true } {    
    add_interface acl_bsp_snoop avalon_streaming start 
    set_interface_property acl_bsp_snoop EXPORT_OF memory_bank_divider.acl_bsp_snoop
  }
  
  add_interface acl_bsp_memorg_host conduit end
  set_interface_property acl_bsp_memorg_host EXPORT_OF memory_bank_divider.acl_bsp_memorg_host
  add_interface dma_localmem_rd avalon slave
  set_interface_property dma_localmem_rd EXPORT_OF dma_localmem_rd_pipe.s0
  add_interface dma_localmem_wr avalon slave
  set_interface_property dma_localmem_wr EXPORT_OF dma_localmem_wr_pipe.s0
  add_interface null_dfh_id avalon slave
  set_interface_property null_dfh_id EXPORT_OF null_dfh_inst.afu_cfg_slave

  # Interconnect requirements
  set_interconnect_requirement {$system} {qsys_mm.clockCrossingAdapter} {HANDSHAKE}
  set_interconnect_requirement {$system} {qsys_mm.maxAdditionalLatency} {0}
}

