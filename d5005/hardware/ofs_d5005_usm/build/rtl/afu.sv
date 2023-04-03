// Copyright 2022 Intel Corporation
// SPDX-License-Identifier: MIT

`include "ofs_plat_if.vh"
`include "opencl_bsp.vh"

module afu
import dc_bsp_pkg::*;
  #(
    parameter NUM_LOCAL_MEM_BANKS = 4
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

logic  reset, clk;
assign reset = pClk_reset;
assign clk   = pClk;

//local wires to connect between bsp_logic and kernel_wrapper - kernel control and memory-interface
opencl_kernel_control_intf opencl_kernel_control();
kernel_mem_intf kernel_mem[BSP_NUM_LOCAL_MEM_BANKS]();

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
) host_mem_va_if_dma();

assign host_mem_va_if_dma.clk = host_mem_if.clk;
assign host_mem_va_if_dma.reset_n = host_mem_if.reset_n;
assign host_mem_va_if_dma.instance_number = host_mem_if.instance_number;

// mmio64-if for the BSP
ofs_plat_avalon_mem_if
#(
    `OFS_PLAT_AVALON_MEM_IF_REPLICATE_PARAMS(mmio64_if)
) mmio64_if_shim();

assign mmio64_if_shim.clk = mmio64_if.clk;
assign mmio64_if_shim.reset_n = mmio64_if.reset_n;
assign mmio64_if_shim.instance_number = mmio64_if.instance_number;

// Host memory - Kernel-USM
ofs_plat_avalon_mem_rdwr_if
#(
    `OFS_PLAT_AVALON_MEM_RDWR_IF_REPLICATE_PARAMS_EXCEPT_TAGS(host_mem_if),
    .USER_WIDTH(AFU_AVMM_USER_WIDTH),
    .LOG_CLASS(ofs_plat_log_pkg::HOST_CHAN)
) host_mem_va_if_kernel();

assign host_mem_va_if_kernel.clk = host_mem_if.clk;
assign host_mem_va_if_kernel.reset_n = host_mem_if.reset_n;
assign host_mem_va_if_kernel.instance_number = host_mem_if.instance_number;

//cross kernel_svm from kernel-clock domain into host-clock domain
ofs_plat_avalon_mem_if
# (
    .ADDR_WIDTH (dc_bsp_pkg::OPENCL_SVM_QSYS_ADDR_WIDTH),
    .DATA_WIDTH (dc_bsp_pkg::OPENCL_BSP_KERNEL_SVM_DATA_WIDTH),
    .BURST_CNT_WIDTH (dc_bsp_pkg::OPENCL_BSP_KERNEL_SVM_BURSTCOUNT_WIDTH)
) kernel_svm_kclk ();
assign kernel_svm_kclk.clk = uClk_usrDiv2;
assign kernel_svm_kclk.reset_n = ~uClk_usrDiv2_reset;

//shared Avalon-MM rd/wr interface from the kernel-system
ofs_plat_avalon_mem_if
# (
    .ADDR_WIDTH (dc_bsp_pkg::OPENCL_SVM_QSYS_ADDR_WIDTH),
    .DATA_WIDTH (dc_bsp_pkg::OPENCL_BSP_KERNEL_SVM_DATA_WIDTH),
    .BURST_CNT_WIDTH (dc_bsp_pkg::OPENCL_BSP_KERNEL_SVM_BURSTCOUNT_WIDTH)
) kernel_svm ();
assign kernel_svm.clk = host_mem_if.clk;
assign kernel_svm.reset_n = host_mem_if.reset_n;

ofs_plat_avalon_mem_if_async_shim #(
    //change waitreq to be more like 'almost-full' rather than 'full'
    .COMMAND_ALMFULL_THRESHOLD (8),
    .RESPONSE_FIFO_DEPTH (USM_CCB_RESPONSE_FIFO_DEPTH)
) kernel_svm_avmm_ccb_inst (
    .mem_sink   (kernel_svm),
    .mem_source (kernel_svm_kclk)
);

//convert kernel_svm AVMM interface into host_mem_if
ofs_plat_avalon_mem_if_to_rdwr_if ofs_plat_avalon_mem_if_to_rdwr_if_inst (
    .mem_sink   (host_mem_va_if_kernel),
    .mem_source (kernel_svm)
);

host_mem_if_vtp host_mem_if_vtp_inst (
    .host_mem_if,
    .host_mem_va_if_dma,
    .host_mem_va_if_kernel,
    .mmio64_if,
    .mmio64_if_shim
);

//wrapper file for board.qsys (Platform Designer)
bsp_logic bsp_logic_inst (
    .clk                    ( pClk ),
    .reset,
    .kernel_clk             ( uClk_usrDiv2 ),
    .kernel_clk_reset       ( uClk_usrDiv2_reset ),
    .host_mem_if            ( host_mem_va_if_dma ),
    .mmio64_if              ( mmio64_if_shim ),
    .local_mem,
    
    .opencl_kernel_control,
    .kernel_mem
);

//wrapper for the kernel-region
kernel_wrapper kernel_wrapper_inst (
    .clk        (uClk_usrDiv2),
    .clk2x      (uClk_usr),
    .reset_n    (!uClk_usrDiv2_reset),
    
    .opencl_kernel_control,
    .kernel_mem
    `ifdef INCLUDE_USM_SUPPORT
        , .kernel_svm (kernel_svm_kclk)
    `endif
);

endmodule : afu
