// Copyright 2022 Intel Corporation
// SPDX-License-Identifier: MIT
//

`include "ofs_plat_if.vh"
`include "opencl_bsp.vh"


module afu
import dc_bsp_pkg::*;
  #(
    parameter NUM_LOCAL_MEM_BANKS = 0
   )
  (
    // Host memory (Avalon)
    ofs_plat_avalon_mem_rdwr_if.to_sink host_mem_if,

    // FPGA MMIO master (Avalon)
    ofs_plat_avalon_mem_if.to_source mmio64_if,

    // Local memory interface.
    ofs_plat_avalon_mem_if.to_slave local_mem[NUM_LOCAL_MEM_BANKS],
    
    // clocks and reset
    input logic pClk,                      //Primary interface clock
    input logic pClk_reset,                // ACTIVE HIGH Soft Reset
    input logic uClk_usr,                  // User clock domain. Refer to clock programming guide
    input logic uClk_usr_reset,
    input logic uClk_usrDiv2,              // User clock domain. Half the programmed frequency
    input logic uClk_usrDiv2_reset
);

import dma_pkg::*;

logic reset, clk;
assign reset = pClk_reset;
assign clk   = pClk;

//local wires to connect between bsp_logic and kernel_wrapper - kernel control and memory-interface
opencl_kernel_control_intf opencl_kernel_control();
kernel_mem_intf kernel_mem[BSP_NUM_LOCAL_MEM_BANKS]();

`ifdef USE_MPF_VTP
    // The width of the Avalon-MM user field is narrower on the AFU side
    // of VTP, since VTP uses a bit to flag VTP page table traffic.
    // Drop the high bit of the user field on the AFU side.
    localparam AFU_AVMM_USER_WIDTH = host_mem_if.USER_WIDTH_ - 1;
    
    // Virtual address interface for use by the DMA path.
    ofs_plat_avalon_mem_rdwr_if
    #(
        `OFS_PLAT_AVALON_MEM_RDWR_IF_REPLICATE_PARAMS_EXCEPT_TAGS(host_mem_if),
        .USER_WIDTH(AFU_AVMM_USER_WIDTH),
        .LOG_CLASS(ofs_plat_log_pkg::HOST_CHAN)
    ) host_mem_va_if();
    
    assign host_mem_va_if.clk = host_mem_if.clk;
    assign host_mem_va_if.reset_n = host_mem_if.reset_n;
    assign host_mem_va_if.instance_number = host_mem_if.instance_number;
    
    // mmio64-if for the BSP
    ofs_plat_avalon_mem_if
    #(
        `OFS_PLAT_AVALON_MEM_IF_REPLICATE_PARAMS(mmio64_if)
    ) mmio64_if_shim();
    
    assign mmio64_if_shim.clk = mmio64_if.clk;
    assign mmio64_if_shim.reset_n = mmio64_if.reset_n;
    assign mmio64_if_shim.instance_number = mmio64_if.instance_number;
    
    mem_if_vtp mem_if_vtp_inst (
        .host_mem_if,
        .host_mem_va_if,
        .mmio64_if,
        .mmio64_if_shim
    );
`endif


bsp_logic bsp_logic_inst (
    .clk                    ( pClk ),
    .reset,
    .kernel_clk             ( uClk_usrDiv2 ),
    .kernel_clk_reset       ( uClk_usrDiv2_reset ),
    `ifdef USE_MPF_VTP
        .host_mem_if        ( host_mem_va_if ),
        .mmio64_if          ( mmio64_if_shim ),
    `else
        .host_mem_if        ( host_mem_if ),
        .mmio64_if          ( mmio64_if ),
    `endif
    .local_mem,
    
    .opencl_kernel_control,
    .kernel_mem
);

kernel_wrapper kernel_wrapper_inst (
    .clk        (uClk_usrDiv2),
    .clk2x      (uClk_usr),
    .reset_n    (!uClk_usrDiv2_reset),
    .opencl_kernel_control,
    .kernel_mem
);

endmodule : afu
