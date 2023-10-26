// Copyright 2022 Intel Corporation
// SPDX-License-Identifier: MIT

`ifndef ofs_asp_vh

    `define ofs_asp_vh

    `define PAC_BSP_ENABLE_DDR4_BANK1 1
    `define PAC_BSP_ENABLE_DDR4_BANK2 1
    `define PAC_BSP_ENABLE_DDR4_BANK3 1
    `define PAC_BSP_ENABLE_DDR4_BANK4 1
    
    //enable USM-support
    `define INCLUDE_USM_SUPPORT 1
    `define USM_DO_SINGLE_BURST_PARTIAL_WRITES 1

    //enable UDP offload engine and I/O channels
    `define INCLUDE_IO_PIPES 1
    `define ASP_ENABLE_IOPIPE0 1
    `define ASP_ENABLE_IOPIPE1 1
    `define ASP_ENABLE_IOPIPE2 1
    `define ASP_ENABLE_IOPIPE3 1
    `define ASP_ENABLE_IOPIPE4 1
    `define ASP_ENABLE_IOPIPE5 1
    `define ASP_ENABLE_IOPIPE6 1
    `define ASP_ENABLE_IOPIPE7 1
    //`define ASP_ENABLE_IOPIPE8 1
    //`define ASP_ENABLE_IOPIPE9 1
    //`define ASP_ENABLE_IOPIPE10 1
    //`define ASP_ENABLE_IOPIPE11 1
    //`define ASP_ENABLE_IOPIPE12 1
    //`define ASP_ENABLE_IOPIPE13 1
    //`define ASP_ENABLE_IOPIPE14 1
    //`define ASP_ENABLE_IOPIPE15 1
    
    //enable kernel interrupts
    //`define USE_KERNEL_IRQ 1
    
    //enable FPGA-to-Host DMA completion IRQ
    //`define USE_F2H_IRQ 1
    
    //enable Host-to-FPGA DMA completion IRQ
    `define USE_H2F_IRQ 1
    
    //enable FPGA-to-Host DMA write fence
    //`define USE_WR_FENCE_FLAG 1

    //enable the PIM's CDC for host-channel AND local memory interfaces
    //`define USE_KERNEL_CLK_EVERYWHERE_IN_PR_REGION 1
    //enable the PIM's CDC for host-channel
    //`define USE_PIM_CDC_FOR_HOSTCHAN 1
    //enable the PIM's CDC for local-memory interfaces
    //`define USE_PIM_CDC_FOR_LOCALMEM 1
    
    //enable write-acks for kernel-system writes to local memory
    //if this is disabled, you also need to remove the 
    // bsp_avmm_write_ack="1" setting(s) board_spec.xml.
    `define USE_WRITEACKS_FOR_KERNELSYSTEM_LOCALMEMORY_ACCESSES 1

`endif
