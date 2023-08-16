package require -exact qsys 17.0

# module properties
set_module_property NAME {board}
set_module_property DISPLAY_NAME {oneAPI ASP board IP}
set_module_property VERSION {23.2}
set_module_property GROUP {oneAPI ASP Components}
set_module_property DESCRIPTION {toplevel instantiation of oneAPI shim IP}
set_module_property AUTHOR {OFS}
set_module_property COMPOSITION_CALLBACK compose

# +-----------------------------------
# | parameters
# | 

# | 
# +-----------------------------------

proc compose { } {
  # Instances and instance parameters
  add_instance clk_200 altera_clock_bridge 19.2.0
  set_instance_parameter_value clk_200 {EXPLICIT_CLOCK_RATE} {200000000.0}
  set_instance_parameter_value clk_200 {NUM_CLOCK_OUTPUTS} {1}
  
  add_instance kernel_clk_in altera_clock_bridge 19.2.0
  set_instance_parameter_value kernel_clk_in {EXPLICIT_CLOCK_RATE} {450000000.0}
  set_instance_parameter_value kernel_clk_in {NUM_CLOCK_OUTPUTS} {1}

  add_instance emif_ddr4a_clk altera_clock_bridge 19.2.0
  set_instance_parameter_value emif_ddr4a_clk {EXPLICIT_CLOCK_RATE} {300000000.0}
  set_instance_parameter_value emif_ddr4a_clk {NUM_CLOCK_OUTPUTS} {1}

  add_instance emif_ddr4b_clk altera_clock_bridge 19.2.0
  set_instance_parameter_value emif_ddr4b_clk {EXPLICIT_CLOCK_RATE} {300000000.0}
  set_instance_parameter_value emif_ddr4b_clk {NUM_CLOCK_OUTPUTS} {1}

  add_instance emif_ddr4c_clk altera_clock_bridge 19.2.0
  set_instance_parameter_value emif_ddr4c_clk {EXPLICIT_CLOCK_RATE} {300000000.0}
  set_instance_parameter_value emif_ddr4c_clk {NUM_CLOCK_OUTPUTS} {1}

  add_instance emif_ddr4d_clk altera_clock_bridge 19.2.0
  set_instance_parameter_value emif_ddr4d_clk {EXPLICIT_CLOCK_RATE} {300000000.0}
  set_instance_parameter_value emif_ddr4d_clk {NUM_CLOCK_OUTPUTS} {1}

  add_instance global_reset_in altera_reset_bridge 19.2.0
  set_instance_parameter_value global_reset_in {ACTIVE_LOW_RESET} {0}
  set_instance_parameter_value global_reset_in {SYNCHRONOUS_EDGES} {both}
  set_instance_parameter_value global_reset_in {NUM_RESET_OUTPUTS} {1}

  add_instance pipe_stage_dma_csr acl_avalon_mm_bridge_s10 16.930
  set_instance_parameter_value pipe_stage_dma_csr {DATA_WIDTH} {64}
  set_instance_parameter_value pipe_stage_dma_csr {SYMBOL_WIDTH} {8}
  set_instance_parameter_value pipe_stage_dma_csr {ADDRESS_WIDTH} {11}
  set_instance_parameter_value pipe_stage_dma_csr {ADDRESS_UNITS} {SYMBOLS}
  set_instance_parameter_value pipe_stage_dma_csr {MAX_BURST_SIZE} {1}
  set_instance_parameter_value pipe_stage_dma_csr {MAX_PENDING_RESPONSES} {1}
  set_instance_parameter_value pipe_stage_dma_csr {LINEWRAPBURSTS} {0}
  set_instance_parameter_value pipe_stage_dma_csr {SYNCHRONIZE_RESET} {1}
  set_instance_parameter_value pipe_stage_dma_csr {DISABLE_WAITREQUEST_BUFFERING} {0}
  set_instance_parameter_value pipe_stage_dma_csr {READDATA_PIPE_DEPTH} {1}
  set_instance_parameter_value pipe_stage_dma_csr {CMD_PIPE_DEPTH} {1}

  add_instance pipe_stage_host_ctrl acl_avalon_mm_bridge_s10 16.930
  set_instance_parameter_value pipe_stage_host_ctrl {DATA_WIDTH} {64}
  set_instance_parameter_value pipe_stage_host_ctrl {SYMBOL_WIDTH} {8}
  set_instance_parameter_value pipe_stage_host_ctrl {ADDRESS_WIDTH} {18}
  set_instance_parameter_value pipe_stage_host_ctrl {ADDRESS_UNITS} {SYMBOLS}
  set_instance_parameter_value pipe_stage_host_ctrl {MAX_BURST_SIZE} {1}
  set_instance_parameter_value pipe_stage_host_ctrl {MAX_PENDING_RESPONSES} {1}
  set_instance_parameter_value pipe_stage_host_ctrl {LINEWRAPBURSTS} {0}
  set_instance_parameter_value pipe_stage_host_ctrl {SYNCHRONIZE_RESET} {1}
  set_instance_parameter_value pipe_stage_host_ctrl {DISABLE_WAITREQUEST_BUFFERING} {0}
  set_instance_parameter_value pipe_stage_host_ctrl {READDATA_PIPE_DEPTH} {3}
  set_instance_parameter_value pipe_stage_host_ctrl {CMD_PIPE_DEPTH} {1}

  add_instance kernel_interface_s10 kernel_interface_s10 17.1
  set_instance_parameter_value kernel_interface_s10 {NUM_GLOBAL_MEMS} {1}

  add_instance board_kernel_cra_pipe acl_avalon_mm_bridge_s10 16.930
  set_instance_parameter_value board_kernel_cra_pipe {DATA_WIDTH} {64}
  set_instance_parameter_value board_kernel_cra_pipe {SYMBOL_WIDTH} {8}
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
  set_instance_parameter_value board_afu_id_avmm_slave {AFU_ID_H} {0x3bf773b04d4644d5}
  set_instance_parameter_value board_afu_id_avmm_slave {AFU_ID_L} {0x9067c884deef8c33}
  set_instance_parameter_value board_afu_id_avmm_slave {DFH_FEATURE_TYPE} {1}
  set_instance_parameter_value board_afu_id_avmm_slave {DFH_AFU_MINOR_REV} {0x0}
  set_instance_parameter_value board_afu_id_avmm_slave {DFH_AFU_MAJOR_REV} {0x0}
  set_instance_parameter_value board_afu_id_avmm_slave {DFH_END_OF_LIST} {0x0}
  set_instance_parameter_value board_afu_id_avmm_slave {DFH_NEXT_OFFSET} {0x020000}
  set_instance_parameter_value board_afu_id_avmm_slave {DFH_FEATURE_ID} {0x000}
  set_instance_parameter_value board_afu_id_avmm_slave {NEXT_AFU_OFFSET} {0x000000}
  set_instance_parameter_value board_afu_id_avmm_slave {CREATE_SCRATCH_REG} {0x0}

  add_instance ddr_board ddr_board 23.2

  # Connections and connection parameters
  # Clocks
  add_connection clk_200.out_clk global_reset_in.clk clock
  add_connection clk_200.out_clk pipe_stage_dma_csr.clk clock
  add_connection clk_200.out_clk pipe_stage_host_ctrl.clk clock
  add_connection clk_200.out_clk kernel_interface_s10.clk clock
  add_connection clk_200.out_clk board_irq_ctrl.Clock clock
  add_connection clk_200.out_clk board_afu_id_avmm_slave.clock clock
  add_connection clk_200.out_clk ddr_board.host_clk clock
  add_connection kernel_clk_in.out_clk kernel_interface_s10.kernel_clk clock
  add_connection kernel_clk_in.out_clk board_kernel_cra_pipe.clk clock
  add_connection kernel_clk_in.out_clk board_kernel_cra_reset.clk clock
  add_connection kernel_clk_in.out_clk kernel_clk_export.clk_in clock
  add_connection kernel_clk_in.out_clk ddr_board.kernel_clk clock
  add_connection emif_ddr4a_clk.out_clk ddr_board.ddr_clk_a clock
  add_connection emif_ddr4b_clk.out_clk ddr_board.ddr_clk_b clock
  add_connection emif_ddr4c_clk.out_clk ddr_board.ddr_clk_c clock
  add_connection emif_ddr4d_clk.out_clk ddr_board.ddr_clk_d clock

  # Resets
  add_connection global_reset_in.out_reset pipe_stage_dma_csr.reset reset
  add_connection global_reset_in.out_reset pipe_stage_host_ctrl.reset reset
  add_connection global_reset_in.out_reset kernel_interface_s10.reset reset
  add_connection global_reset_in.out_reset kernel_interface_s10.sw_reset_in reset
  add_connection global_reset_in.out_reset board_kernel_cra_reset.in_reset reset
  add_connection global_reset_in.out_reset board_irq_ctrl.Resetn reset
  add_connection global_reset_in.out_reset board_afu_id_avmm_slave.reset reset
  add_connection global_reset_in.out_reset ddr_board.global_reset reset
  add_connection kernel_interface_s10.kernel_reset kernel_clk_export.clk_in_reset reset
  add_connection kernel_interface_s10.kernel_reset ddr_board.kernel_reset reset
  add_connection board_kernel_cra_reset.out_reset board_kernel_cra_pipe.reset reset

  # IRQs
  add_connection board_irq_ctrl.interrupt_receiver kernel_interface_s10.kernel_irq_to_host irq

  # Conduits
  add_connection kernel_interface_s10.acl_bsp_memorg_host0x018 ddr_board.acl_bsp_memorg_host conduit

  # Data
  add_connection pipe_stage_host_ctrl.m0 pipe_stage_dma_csr.s0 avalon
  set_connection_parameter_value pipe_stage_host_ctrl.m0/pipe_stage_dma_csr.s0 arbitrationPriority {1}
  set_connection_parameter_value pipe_stage_host_ctrl.m0/pipe_stage_dma_csr.s0 baseAddress {0x20000}
  set_connection_parameter_value pipe_stage_host_ctrl.m0/pipe_stage_dma_csr.s0 defaultConnection {0}

  add_connection pipe_stage_host_ctrl.m0 kernel_interface_s10.ctrl avalon
  set_connection_parameter_value pipe_stage_host_ctrl.m0/kernel_interface_s10.ctrl arbitrationPriority {1}
  set_connection_parameter_value pipe_stage_host_ctrl.m0/kernel_interface_s10.ctrl baseAddress {0x4000}
  set_connection_parameter_value pipe_stage_host_ctrl.m0/kernel_interface_s10.ctrl defaultConnection {0}

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
  set_connection_parameter_value pipe_stage_host_ctrl.m0/ddr_board.null_dfh_id baseAddress {0x20800}
  set_connection_parameter_value pipe_stage_host_ctrl.m0/ddr_board.null_dfh_id defaultConnection {0}

  add_connection kernel_interface_s10.kernel_cra board_kernel_cra_pipe.s0 avalon
  set_connection_parameter_value kernel_interface_s10.kernel_cra/board_kernel_cra_pipe.s0 arbitrationPriority {1}
  set_connection_parameter_value kernel_interface_s10.kernel_cra/board_kernel_cra_pipe.s0 baseAddress {0x0}
  set_connection_parameter_value kernel_interface_s10.kernel_cra/board_kernel_cra_pipe.s0 defaultConnection {0}

  # Exported interfaces
  # Clocks
  add_interface clk_200 clock sink
  set_interface_property clk_200 EXPORT_OF clk_200.in_clk
  add_interface kernel_clk_in clock sink
  set_interface_property kernel_clk_in EXPORT_OF kernel_clk_in.in_clk
  add_interface emif_ddr4a_clk clock sink
  set_interface_property emif_ddr4a_clk EXPORT_OF emif_ddr4a_clk.in_clk
  add_interface emif_ddr4b_clk clock sink
  set_interface_property emif_ddr4b_clk EXPORT_OF emif_ddr4b_clk.in_clk
  add_interface emif_ddr4c_clk clock sink
  set_interface_property emif_ddr4c_clk EXPORT_OF emif_ddr4c_clk.in_clk
  add_interface emif_ddr4d_clk clock sink
  set_interface_property emif_ddr4d_clk EXPORT_OF emif_ddr4d_clk.in_clk
  add_interface kernel_clk clock source
  set_interface_property kernel_clk EXPORT_OF kernel_clk_export.clk
 
  # Resets
  add_interface global_reset reset sink
  set_interface_property global_reset EXPORT_OF global_reset_in.in_reset
  add_interface kernel_reset reset source
  set_interface_property kernel_reset EXPORT_OF kernel_clk_export.clk_reset

  # IRQs
  add_interface kernel_irq interrupt source
  set_interface_property kernel_irq EXPORT_OF kernel_interface_s10.kernel_irq_from_kernel
  add_interface host_kernel_irq interrupt sink
  set_interface_property host_kernel_irq EXPORT_OF board_irq_ctrl.interrupt_sender

  # Data
  add_interface avmm_mmio64 avalon slave
  set_interface_property avmm_mmio64 EXPORT_OF pipe_stage_host_ctrl.s0
  add_interface dma_csr_mmio64 avalon master
  set_interface_property dma_csr_mmio64 EXPORT_OF pipe_stage_dma_csr.m0
  add_interface kernel_cra avalon master
  set_interface_property kernel_cra EXPORT_OF board_kernel_cra_pipe.m0
  add_interface acl_internal_snoop avalon_streaming start
  set_interface_property acl_internal_snoop EXPORT_OF ddr_board.acl_bsp_snoop
  add_interface emif_ddr4a avalon master
  set_interface_property emif_ddr4a EXPORT_OF ddr_board.emif_ddr4a
  add_interface kernel_ddr4a avalon slave
  set_interface_property kernel_ddr4a EXPORT_OF ddr_board.kernel_ddr4a
  add_interface emif_ddr4b avalon master
  set_interface_property emif_ddr4b EXPORT_OF ddr_board.emif_ddr4b
  add_interface kernel_ddr4b avalon slave
  set_interface_property kernel_ddr4b EXPORT_OF ddr_board.kernel_ddr4b
  add_interface emif_ddr4c avalon master
  set_interface_property emif_ddr4c EXPORT_OF ddr_board.emif_ddr4c
  add_interface kernel_ddr4c avalon slave
  set_interface_property kernel_ddr4c EXPORT_OF ddr_board.kernel_ddr4c
  add_interface emif_ddr4d avalon master
  set_interface_property emif_ddr4d EXPORT_OF ddr_board.emif_ddr4d
  add_interface kernel_ddr4d avalon slave
  set_interface_property kernel_ddr4d EXPORT_OF ddr_board.kernel_ddr4d
  add_interface dma_localmem_rd avalon slave
  set_interface_property dma_localmem_rd EXPORT_OF ddr_board.dma_localmem_rd
  add_interface dma_localmem_wr avalon slave
  set_interface_property dma_localmem_wr EXPORT_OF ddr_board.dma_localmem_wr

  # Interconnect requirements
  set_interconnect_requirement {$system} {qsys_mm.clockCrossingAdapter} {HANDSHAKE}
  set_interconnect_requirement {$system} {qsys_mm.maxAdditionalLatency} {0}
}

