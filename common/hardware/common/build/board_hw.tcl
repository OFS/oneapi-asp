package require -exact qsys 17.0

# module properties
set_module_property NAME {board}
set_module_property DISPLAY_NAME {oneAPI ASP board IP}
set_module_property VERSION {23.2}
set_module_property GROUP {oneAPI ASP Components}
set_module_property DESCRIPTION {toplevel instantiation of oneAPI ASP IP}
set_module_property AUTHOR {OFS}
set_module_property COMPOSITION_CALLBACK compose

# +-----------------------------------
# | parameters
# |
source parameters.tcl

add_parameter AFU_ID_H STD_LOGIC_VECTOR $p_AFU_ID_H
set_parameter_property AFU_ID_H DEFAULT_VALUE $p_AFU_ID_H
set_parameter_property AFU_ID_H DISPLAY_NAME "AFU ID H"
set_parameter_property AFU_ID_H AFFECTS_ELABORATION true
 
add_parameter AFU_ID_L STD_LOGIC_VECTOR $p_AFU_ID_L
set_parameter_property AFU_ID_L DEFAULT_VALUE $p_AFU_ID_L
set_parameter_property AFU_ID_L DISPLAY_NAME "AFU ID L"
set_parameter_property AFU_ID_L AFFECTS_ELABORATION true
 
add_parameter IOPIPE_SUPPORT BOOLEAN $p_IOPIPE_SUPPORT
set_parameter_property IOPIPE_SUPPORT DEFAULT_VALUE $p_IOPIPE_SUPPORT
set_parameter_property IOPIPE_SUPPORT DISPLAY_NAME "IO Pipe Support"
set_parameter_property IOPIPE_SUPPORT AFFECTS_ELABORATION true
 
add_parameter NUMBER_OF_MEMORY_BANKS INTEGER $p_NUMBER_OF_MEMORY_BANKS
set_parameter_property NUMBER_OF_MEMORY_BANKS DEFAULT_VALUE $p_NUMBER_OF_MEMORY_BANKS
set_parameter_property NUMBER_OF_MEMORY_BANKS DISPLAY_NAME "Number of Memory Banks"
set_parameter_property NUMBER_OF_MEMORY_BANKS AFFECTS_ELABORATION true

add_parameter NUMBER_OF_DMA_CHANNELS INTEGER $p_NUMBER_OF_DMA_CHANNELS
set_parameter_property NUMBER_OF_DMA_CHANNELS DEFAULT_VALUE $p_NUMBER_OF_DMA_CHANNELS
set_parameter_property NUMBER_OF_DMA_CHANNELS DISPLAY_NAME "Number of DMA Channels"
set_parameter_property NUMBER_OF_DMA_CHANNELS AFFECTS_ELABORATION true

add_parameter MEMORY_BANK_ADDRESS_WIDTH INTEGER $p_MEMORY_BANK_ADDRESS_WIDTH
set_parameter_property MEMORY_BANK_ADDRESS_WIDTH DEFAULT_VALUE $p_MEMORY_BANK_ADDRESS_WIDTH
set_parameter_property MEMORY_BANK_ADDRESS_WIDTH DISPLAY_NAME "Memory Bank Address Width"
set_parameter_property MEMORY_BANK_ADDRESS_WIDTH AFFECTS_ELABORATION true

add_parameter DATA_WIDTH INTEGER $p_DATA_WIDTH
set_parameter_property DATA_WIDTH DEFAULT_VALUE $p_DATA_WIDTH
set_parameter_property DATA_WIDTH DISPLAY_NAME "Data Width"
set_parameter_property DATA_WIDTH AFFECTS_ELABORATION true

add_parameter MAX_BURST_SIZE INTEGER $p_MAX_BURST_SIZE
set_parameter_property MAX_BURST_SIZE DEFAULT_VALUE $p_MAX_BURST_SIZE
set_parameter_property MAX_BURST_SIZE DISPLAY_NAME "Maximum Burst Size"
set_parameter_property MAX_BURST_SIZE AFFECTS_ELABORATION true

add_parameter KERNEL_GLOBALMEM_WAITREQUEST_ALLOWANCE INTEGER $p_KERNEL_GLOBALMEM_WAITREQUEST_ALLOWANCE
set_parameter_property KERNEL_GLOBALMEM_WAITREQUEST_ALLOWANCE DEFAULT_VALUE $p_KERNEL_GLOBALMEM_WAITREQUEST_ALLOWANCE
set_parameter_property KERNEL_GLOBALMEM_WAITREQUEST_ALLOWANCE DISPLAY_NAME "Kernel to global memory waitrequest allowance"
set_parameter_property KERNEL_GLOBALMEM_WAITREQUEST_ALLOWANCE AFFECTS_ELABORATION true

add_parameter SNOOP_PORT_ENABLE BOOLEAN $p_SNOOP_PORT_ENABLE
set_parameter_property SNOOP_PORT_ENABLE DEFAULT_VALUE $p_SNOOP_PORT_ENABLE
set_parameter_property SNOOP_PORT_ENABLE DISPLAY_NAME "Enable Snoop Port"
set_parameter_property SNOOP_PORT_ENABLE AFFECTS_ELABORATION true

add_parameter MBD_TO_MEMORY_PIPE_STAGES INTEGER $p_MBD_TO_MEMORY_PIPE_STAGES
set_parameter_property MBD_TO_MEMORY_PIPE_STAGES DEFAULT_VALUE $p_MBD_TO_MEMORY_PIPE_STAGES
set_parameter_property MBD_TO_MEMORY_PIPE_STAGES DISPLAY_NAME "MBD to Memory Pipeline Stages"
set_parameter_property MBD_TO_MEMORY_PIPE_STAGES AFFECTS_ELABORATION true
# | 
# +-----------------------------------

proc compose { } {
  # Get parameters
  set afu_id_h                               [ get_parameter_value AFU_ID_H ]
  set afu_id_l                               [ get_parameter_value AFU_ID_L ]
  set iopipe_support                         [ get_parameter_value IOPIPE_SUPPORT ]
  set number_of_memory_banks                 [ get_parameter_value NUMBER_OF_MEMORY_BANKS ]
  set number_of_dma_channels                 [ get_parameter_value NUMBER_OF_DMA_CHANNELS ]
  set memory_bank_address_width              [ get_parameter_value MEMORY_BANK_ADDRESS_WIDTH ]
  set data_width                             [ get_parameter_value DATA_WIDTH ]
  set max_burst_size                         [ get_parameter_value MAX_BURST_SIZE ]
  set kernel_globalmem_waitrequest_allowance [ get_parameter_value KERNEL_GLOBALMEM_WAITREQUEST_ALLOWANCE ]
  set snoop_port_enable                      [ get_parameter_value SNOOP_PORT_ENABLE ]
  set mbd_to_memory_pipe_stages              [ get_parameter_value MBD_TO_MEMORY_PIPE_STAGES ]

  # Compute parameters
  set symbol_width 8
  set csr_data_width 64

  # Instances and instance parameters
  add_instance clk_200 altera_clock_bridge 19.2.0
  set_instance_parameter_value clk_200 {EXPLICIT_CLOCK_RATE} {200000000.0}
  set_instance_parameter_value clk_200 {NUM_CLOCK_OUTPUTS} {1}
  
  add_instance kernel_clk_in altera_clock_bridge 19.2.0
  set_instance_parameter_value kernel_clk_in {EXPLICIT_CLOCK_RATE} {450000000.0}
  set_instance_parameter_value kernel_clk_in {NUM_CLOCK_OUTPUTS} {1}

  for { set i 0} { $i < $number_of_memory_banks } {incr i} {
    add_instance emif_ddr${i}_clk altera_clock_bridge 19.2.0
    set_instance_parameter_value emif_ddr${i}_clk {EXPLICIT_CLOCK_RATE} {300000000.0}
    set_instance_parameter_value emif_ddr${i}_clk {NUM_CLOCK_OUTPUTS} {1}
  }

  add_instance global_reset_in altera_reset_bridge 19.2.0
  set_instance_parameter_value global_reset_in {ACTIVE_LOW_RESET} {0}
  set_instance_parameter_value global_reset_in {SYNCHRONOUS_EDGES} {both}
  set_instance_parameter_value global_reset_in {NUM_RESET_OUTPUTS} {1}

  add_instance pipe_stage_dma_csr acl_avalon_mm_bridge_s10 16.930
  set_instance_parameter_value pipe_stage_dma_csr {DATA_WIDTH} $csr_data_width
  set_instance_parameter_value pipe_stage_dma_csr {SYMBOL_WIDTH} $symbol_width
  set_instance_parameter_value pipe_stage_dma_csr {ADDRESS_WIDTH} {11}
  set_instance_parameter_value pipe_stage_dma_csr {ADDRESS_UNITS} {SYMBOLS}
  set_instance_parameter_value pipe_stage_dma_csr {MAX_BURST_SIZE} {1}
  set_instance_parameter_value pipe_stage_dma_csr {MAX_PENDING_RESPONSES} {1}
  set_instance_parameter_value pipe_stage_dma_csr {LINEWRAPBURSTS} {0}
  set_instance_parameter_value pipe_stage_dma_csr {SYNCHRONIZE_RESET} {1}
  set_instance_parameter_value pipe_stage_dma_csr {DISABLE_WAITREQUEST_BUFFERING} {0}
  set_instance_parameter_value pipe_stage_dma_csr {READDATA_PIPE_DEPTH} {1}
  set_instance_parameter_value pipe_stage_dma_csr {CMD_PIPE_DEPTH} {1}
 
  if { $iopipe_support == true } {
    add_instance pipe_stage_uoe_csr acl_avalon_mm_bridge_s10 16.930
    set_instance_parameter_value pipe_stage_uoe_csr {DATA_WIDTH} $csr_data_width
    set_instance_parameter_value pipe_stage_uoe_csr {SYMBOL_WIDTH} $symbol_width
    set_instance_parameter_value pipe_stage_uoe_csr {ADDRESS_WIDTH} {11}
    set_instance_parameter_value pipe_stage_uoe_csr {ADDRESS_UNITS} {SYMBOLS}
    set_instance_parameter_value pipe_stage_uoe_csr {MAX_BURST_SIZE} {1}
    set_instance_parameter_value pipe_stage_uoe_csr {MAX_PENDING_RESPONSES} {1}
    set_instance_parameter_value pipe_stage_uoe_csr {LINEWRAPBURSTS} {0}
    set_instance_parameter_value pipe_stage_uoe_csr {SYNCHRONIZE_RESET} {1}
    set_instance_parameter_value pipe_stage_uoe_csr {DISABLE_WAITREQUEST_BUFFERING} {0}
    set_instance_parameter_value pipe_stage_uoe_csr {READDATA_PIPE_DEPTH} {1}
    set_instance_parameter_value pipe_stage_uoe_csr {CMD_PIPE_DEPTH} {1}
  }

  add_instance pipe_stage_host_ctrl acl_avalon_mm_bridge_s10 16.930
  set_instance_parameter_value pipe_stage_host_ctrl {DATA_WIDTH} $csr_data_width
  set_instance_parameter_value pipe_stage_host_ctrl {SYMBOL_WIDTH} $symbol_width
  set_instance_parameter_value pipe_stage_host_ctrl {ADDRESS_WIDTH} {18}
  set_instance_parameter_value pipe_stage_host_ctrl {ADDRESS_UNITS} {SYMBOLS}
  set_instance_parameter_value pipe_stage_host_ctrl {MAX_BURST_SIZE} {1}
  set_instance_parameter_value pipe_stage_host_ctrl {MAX_PENDING_RESPONSES} {1}
  set_instance_parameter_value pipe_stage_host_ctrl {LINEWRAPBURSTS} {0}
  set_instance_parameter_value pipe_stage_host_ctrl {SYNCHRONIZE_RESET} {1}
  set_instance_parameter_value pipe_stage_host_ctrl {DISABLE_WAITREQUEST_BUFFERING} {0}
  set_instance_parameter_value pipe_stage_host_ctrl {READDATA_PIPE_DEPTH} {3}
  set_instance_parameter_value pipe_stage_host_ctrl {CMD_PIPE_DEPTH} {1}

  add_instance kernel_interface kernel_interface 23.2
  set_instance_parameter_value kernel_interface {NUM_GLOBAL_MEMS} {1}

  add_instance board_kernel_cra_pipe acl_avalon_mm_bridge_s10 16.930
  set_instance_parameter_value board_kernel_cra_pipe {DATA_WIDTH} $csr_data_width
  set_instance_parameter_value board_kernel_cra_pipe {SYMBOL_WIDTH} $symbol_width
  set_instance_parameter_value board_kernel_cra_pipe {ADDRESS_WIDTH} {30}
  set_instance_parameter_value board_kernel_cra_pipe {ADDRESS_UNITS} {SYMBOLS}
  set_instance_parameter_value board_kernel_cra_pipe {MAX_BURST_SIZE} {1}
  set_instance_parameter_value board_kernel_cra_pipe {MAX_PENDING_RESPONSES} {1}
  set_instance_parameter_value board_kernel_cra_pipe {LINEWRAPBURSTS} {0}
  set_instance_parameter_value board_kernel_cra_pipe {SYNCHRONIZE_RESET} {1}
  set_instance_parameter_value board_kernel_cra_pipe {DISABLE_WAITREQUEST_BUFFERING} {1}
  set_instance_parameter_value board_kernel_cra_pipe {READDATA_PIPE_DEPTH} {1}
  set_instance_parameter_value board_kernel_cra_pipe {CMD_PIPE_DEPTH} {1}

  add_instance board_kernel_cra_reset altera_reset_bridge 19.2.0
  set_instance_parameter_value board_kernel_cra_reset {ACTIVE_LOW_RESET} {0}
  set_instance_parameter_value board_kernel_cra_reset {SYNCHRONOUS_EDGES} {deassert}
  set_instance_parameter_value board_kernel_cra_reset {NUM_RESET_OUTPUTS} {1}

  add_instance kernel_clk_export clock_source 17.1
  set_instance_parameter_value kernel_clk_export {clockFrequency} {450000000.0}
  set_instance_parameter_value kernel_clk_export {clockFrequencyKnown} {1}
  set_instance_parameter_value kernel_clk_export {resetSynchronousEdges} {deassert}

  add_instance board_irq_ctrl irq_ctrl 1.0

  add_instance board_afu_id_avmm_slave afu_id_avmm_slave 1.0
  set_instance_parameter_value board_afu_id_avmm_slave {AFU_ID_H} $afu_id_h
  set_instance_parameter_value board_afu_id_avmm_slave {AFU_ID_L} $afu_id_l
  set_instance_parameter_value board_afu_id_avmm_slave {DFH_FEATURE_TYPE} {1}
  set_instance_parameter_value board_afu_id_avmm_slave {DFH_AFU_MINOR_REV} {0x0}
  set_instance_parameter_value board_afu_id_avmm_slave {DFH_AFU_MAJOR_REV} {0x0}
  set_instance_parameter_value board_afu_id_avmm_slave {DFH_END_OF_LIST} {0x0}
  set_instance_parameter_value board_afu_id_avmm_slave {DFH_NEXT_OFFSET} {0x020000}
  set_instance_parameter_value board_afu_id_avmm_slave {DFH_FEATURE_ID} {0x000}
  set_instance_parameter_value board_afu_id_avmm_slave {NEXT_AFU_OFFSET} {0x000000}
  set_instance_parameter_value board_afu_id_avmm_slave {CREATE_SCRATCH_REG} {0x0}

  add_instance ddr_board ddr_board 23.2
  set_instance_parameter_value ddr_board {NUMBER_OF_MEMORY_BANKS} $number_of_memory_banks
  set_instance_parameter_value ddr_board {MEMORY_BANK_ADDRESS_WIDTH} $memory_bank_address_width
  set_instance_parameter_value ddr_board {DATA_WIDTH} $data_width
  set_instance_parameter_value ddr_board {MAX_BURST_SIZE} $max_burst_size
  set_instance_parameter_value ddr_board {KERNEL_GLOBALMEM_WAITREQUEST_ALLOWANCE} $kernel_globalmem_waitrequest_allowance
  set_instance_parameter_value ddr_board {SNOOP_PORT_ENABLE} $snoop_port_enable
  set_instance_parameter_value ddr_board {MBD_TO_MEMORY_PIPE_STAGES} $mbd_to_memory_pipe_stages

  # Connections and connection parameters
  # Clocks
  add_connection clk_200.out_clk global_reset_in.clk clock
  add_connection clk_200.out_clk pipe_stage_dma_csr.clk clock

  if { $iopipe_support == true } {
    add_connection clk_200.out_clk pipe_stage_uoe_csr.clk clock
  }

  add_connection clk_200.out_clk pipe_stage_host_ctrl.clk clock
  add_connection clk_200.out_clk kernel_interface.clk clock
  add_connection clk_200.out_clk board_irq_ctrl.Clock clock
  add_connection clk_200.out_clk board_afu_id_avmm_slave.clock clock
  add_connection clk_200.out_clk ddr_board.host_clk clock
  add_connection kernel_clk_in.out_clk kernel_interface.kernel_clk clock
  add_connection kernel_clk_in.out_clk board_kernel_cra_pipe.clk clock
  add_connection kernel_clk_in.out_clk board_kernel_cra_reset.clk clock
  add_connection kernel_clk_in.out_clk kernel_clk_export.clk_in clock
  add_connection kernel_clk_in.out_clk ddr_board.kernel_clk clock

  for { set i 0} { $i < $number_of_memory_banks } {incr i} {
    add_connection emif_ddr${i}_clk.out_clk ddr_board.ddr_clk$i clock
  }

  # Resets
  add_connection global_reset_in.out_reset pipe_stage_dma_csr.reset reset

  if { $iopipe_support == true } {
    add_connection global_reset_in.out_reset pipe_stage_uoe_csr.reset reset
  }

  add_connection global_reset_in.out_reset pipe_stage_host_ctrl.reset reset
  add_connection global_reset_in.out_reset kernel_interface.reset reset
  add_connection global_reset_in.out_reset kernel_interface.sw_reset_in reset
  add_connection global_reset_in.out_reset board_kernel_cra_reset.in_reset reset
  add_connection global_reset_in.out_reset board_irq_ctrl.Resetn reset
  add_connection global_reset_in.out_reset board_afu_id_avmm_slave.reset reset
  add_connection global_reset_in.out_reset ddr_board.global_reset reset
  add_connection kernel_interface.kernel_reset kernel_clk_export.clk_in_reset reset
  add_connection kernel_interface.kernel_reset ddr_board.kernel_reset reset
  add_connection board_kernel_cra_reset.out_reset board_kernel_cra_pipe.reset reset

  # IRQs
  add_connection board_irq_ctrl.interrupt_receiver kernel_interface.kernel_irq_to_host irq

  # Conduits
  add_connection kernel_interface.acl_asp_memorg_host0x018 ddr_board.acl_asp_memorg_host conduit

  # Data
  add_connection pipe_stage_host_ctrl.m0 pipe_stage_dma_csr.s0 avalon
  set_connection_parameter_value pipe_stage_host_ctrl.m0/pipe_stage_dma_csr.s0 arbitrationPriority {1}
  set_connection_parameter_value pipe_stage_host_ctrl.m0/pipe_stage_dma_csr.s0 baseAddress {0x20000}
  set_connection_parameter_value pipe_stage_host_ctrl.m0/pipe_stage_dma_csr.s0 defaultConnection {0}

  if { $iopipe_support == true } {
    add_connection pipe_stage_host_ctrl.m0 pipe_stage_uoe_csr.s0 avalon
    set_connection_parameter_value pipe_stage_host_ctrl.m0/pipe_stage_uoe_csr.s0 arbitrationPriority {1}
    set_connection_parameter_value pipe_stage_host_ctrl.m0/pipe_stage_uoe_csr.s0 baseAddress {0x20800}
    set_connection_parameter_value pipe_stage_host_ctrl.m0/pipe_stage_uoe_csr.s0 defaultConnection {0}
  }

  add_connection pipe_stage_host_ctrl.m0 kernel_interface.ctrl avalon
  set_connection_parameter_value pipe_stage_host_ctrl.m0/kernel_interface.ctrl arbitrationPriority {1}
  set_connection_parameter_value pipe_stage_host_ctrl.m0/kernel_interface.ctrl baseAddress {0x4000}
  set_connection_parameter_value pipe_stage_host_ctrl.m0/kernel_interface.ctrl defaultConnection {0}

  add_connection pipe_stage_host_ctrl.m0 board_irq_ctrl.IRQ_Mask_Slave avalon
  set_connection_parameter_value pipe_stage_host_ctrl.m0/board_irq_ctrl.IRQ_Mask_Slave arbitrationPriority {1}
  set_connection_parameter_value pipe_stage_host_ctrl.m0/board_irq_ctrl.IRQ_Mask_Slave baseAddress {0x108}
  set_connection_parameter_value pipe_stage_host_ctrl.m0/board_irq_ctrl.IRQ_Mask_Slave defaultConnection {0}

  add_connection pipe_stage_host_ctrl.m0 board_irq_ctrl.IRQ_Read_Slave avalon
  set_connection_parameter_value pipe_stage_host_ctrl.m0/board_irq_ctrl.IRQ_Read_Slave arbitrationPriority {1}
  set_connection_parameter_value pipe_stage_host_ctrl.m0/board_irq_ctrl.IRQ_Read_Slave baseAddress {0x100}
  set_connection_parameter_value pipe_stage_host_ctrl.m0/board_irq_ctrl.IRQ_Read_Slave defaultConnection {0}

  add_connection pipe_stage_host_ctrl.m0 board_afu_id_avmm_slave.afu_cfg_slave avalon
  set_connection_parameter_value pipe_stage_host_ctrl.m0/board_afu_id_avmm_slave.afu_cfg_slave arbitrationPriority {1}
  set_connection_parameter_value pipe_stage_host_ctrl.m0/board_afu_id_avmm_slave.afu_cfg_slave baseAddress {0x0}
  set_connection_parameter_value pipe_stage_host_ctrl.m0/board_afu_id_avmm_slave.afu_cfg_slave defaultConnection {0}

  add_connection pipe_stage_host_ctrl.m0 ddr_board.null_dfh_id avalon
  set_connection_parameter_value pipe_stage_host_ctrl.m0/ddr_board.null_dfh_id arbitrationPriority {1}
  if { $iopipe_support == true } {
    set_connection_parameter_value pipe_stage_host_ctrl.m0/ddr_board.null_dfh_id baseAddress {0x21000}
  } else {
    set_connection_parameter_value pipe_stage_host_ctrl.m0/ddr_board.null_dfh_id baseAddress {0x20800}
  }
  set_connection_parameter_value pipe_stage_host_ctrl.m0/ddr_board.null_dfh_id defaultConnection {0}

  add_connection kernel_interface.kernel_cra board_kernel_cra_pipe.s0 avalon
  set_connection_parameter_value kernel_interface.kernel_cra/board_kernel_cra_pipe.s0 arbitrationPriority {1}
  set_connection_parameter_value kernel_interface.kernel_cra/board_kernel_cra_pipe.s0 baseAddress {0x0}
  set_connection_parameter_value kernel_interface.kernel_cra/board_kernel_cra_pipe.s0 defaultConnection {0}

  # Exported interfaces
  # Clocks
  add_interface clk_200 clock sink
  set_interface_property clk_200 EXPORT_OF clk_200.in_clk
  add_interface kernel_clk_in clock sink
  set_interface_property kernel_clk_in EXPORT_OF kernel_clk_in.in_clk

  for { set i 0} { $i < $number_of_memory_banks } {incr i} {
    add_interface emif_ddr${i}_clk clock sink
    set_interface_property emif_ddr${i}_clk EXPORT_OF emif_ddr${i}_clk.in_clk

  }

  add_interface kernel_clk clock source
  set_interface_property kernel_clk EXPORT_OF kernel_clk_export.clk
 
  # Resets
  add_interface global_reset reset sink
  set_interface_property global_reset EXPORT_OF global_reset_in.in_reset
  add_interface kernel_reset reset source
  set_interface_property kernel_reset EXPORT_OF kernel_clk_export.clk_reset

  # IRQs
  add_interface kernel_irq interrupt source
  set_interface_property kernel_irq EXPORT_OF kernel_interface.kernel_irq_from_kernel
  add_interface host_kernel_irq interrupt sink
  set_interface_property host_kernel_irq EXPORT_OF board_irq_ctrl.interrupt_sender

  # Data
  add_interface avmm_mmio64 avalon slave
  set_interface_property avmm_mmio64 EXPORT_OF pipe_stage_host_ctrl.s0
  add_interface dma_csr_mmio64 avalon master
  set_interface_property dma_csr_mmio64 EXPORT_OF pipe_stage_dma_csr.m0
  
  if { $iopipe_support == true } {
    add_interface uoe_csr_mmio64 avalon master
    set_interface_property uoe_csr_mmio64 EXPORT_OF pipe_stage_uoe_csr.m0
  }

  add_interface kernel_cra avalon master
  set_interface_property kernel_cra EXPORT_OF board_kernel_cra_pipe.m0

  if { $snoop_port_enable == true } {
    add_interface acl_internal_snoop avalon_streaming start
    set_interface_property acl_internal_snoop EXPORT_OF ddr_board.acl_asp_snoop
  }

  for { set i 0} { $i < $number_of_memory_banks } {incr i} {
    add_interface emif_ddr$i avalon master
    set_interface_property emif_ddr$i EXPORT_OF ddr_board.emif_ddr$i
    add_interface kernel_ddr$i avalon slave
    set_interface_property kernel_ddr$i EXPORT_OF ddr_board.kernel_ddr$i
  }

  for { set i 0} { $i < $number_of_dma_channels } {incr i} {
    add_interface dma_localmem_rd_$i avalon slave
    set_interface_property dma_localmem_rd_$i EXPORT_OF ddr_board.dma_localmem_rd_$i
    add_interface dma_localmem_wr_$i avalon slave
    set_interface_property dma_localmem_wr_$i EXPORT_OF ddr_board.dma_localmem_wr_$i
  }

  # Interconnect requirements
  set_interconnect_requirement {$system} {qsys_mm.clockCrossingAdapter} {HANDSHAKE}
  set_interconnect_requirement {$system} {qsys_mm.maxAdditionalLatency} {0}
}

