// Copyright 2022 Intel Corporation
// SPDX-License-Identifier: MIT

`include "ofs_ip_cfg_mem_ss.vh"
`include "ofs_ip_cfg_hssi_ss.vh"

`ifndef ofs_asp_vh

    `define ofs_asp_vh

    `ifdef OFS_FIM_IP_CFG_MEM_SS_EN_MEM_0
        `define ASP_ENABLE_DDR4_BANK_0 1
    `endif
    `ifdef OFS_FIM_IP_CFG_MEM_SS_EN_MEM_1
        `define ASP_ENABLE_DDR4_BANK_1 1
    `endif
    `ifdef OFS_FIM_IP_CFG_MEM_SS_EN_MEM_2
        `define ASP_ENABLE_DDR4_BANK_2 1
    `endif
    `ifdef OFS_FIM_IP_CFG_MEM_SS_EN_MEM_3
        `define ASP_ENABLE_DDR4_BANK_3 1
    `endif
    
    //enable USM-support
    `define INCLUDE_USM_SUPPORT 1
    `define USM_DO_SINGLE_BURST_PARTIAL_WRITES 1
    
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

    
    //enable UDP offload engine and I/O channels
    `define INCLUDE_IO_PIPES 1
    `ifdef INCLUDE_HSSI_PORT_0
        `define ASP_ENABLE_IOPIPE_0 1
    `endif
    `ifdef INCLUDE_HSSI_PORT_1
        `define ASP_ENABLE_IOPIPE_1 1
    `endif
    `ifdef INCLUDE_HSSI_PORT_2
        `define ASP_ENABLE_IOPIPE_2 1
    `endif
    `ifdef INCLUDE_HSSI_PORT_3
        `define ASP_ENABLE_IOPIPE_3 1
    `endif
    `ifdef INCLUDE_HSSI_PORT_4
        `define ASP_ENABLE_IOPIPE_4 1
    `endif
    `ifdef INCLUDE_HSSI_PORT_5
        `define ASP_ENABLE_IOPIPE_5 1
    `endif
    `ifdef INCLUDE_HSSI_PORT_6
        `define ASP_ENABLE_IOPIPE_6 1
    `endif
    `ifdef INCLUDE_HSSI_PORT_7
        `define ASP_ENABLE_IOPIPE_7 1
    `endif
    `ifdef INCLUDE_HSSI_PORT_8
        `define ASP_ENABLE_IOPIPE_8 1
    `endif
    `ifdef INCLUDE_HSSI_PORT_9
        `define ASP_ENABLE_IOPIPE_9 1
    `endif
    `ifdef INCLUDE_HSSI_PORT_10
        `define ASP_ENABLE_IOPIPE_10 1
    `endif
    `ifdef INCLUDE_HSSI_PORT_11
        `define ASP_ENABLE_IOPIPE_11 1
    `endif
    `ifdef INCLUDE_HSSI_PORT_12
        `define ASP_ENABLE_IOPIPE_12 1
    `endif
    `ifdef INCLUDE_HSSI_PORT_12
        `define ASP_ENABLE_IOPIPE_12 1
    `endif
    `ifdef INCLUDE_HSSI_PORT_13
        `define ASP_ENABLE_IOPIPE_13 1
    `endif
    `ifdef INCLUDE_HSSI_PORT_13
        `define ASP_ENABLE_IOPIPE_13 1
    `endif
    `ifdef INCLUDE_HSSI_PORT_14
        `define ASP_ENABLE_IOPIPE_14 1
    `endif
    `ifdef INCLUDE_HSSI_PORT_15
        `define ASP_ENABLE_IOPIPE_15 1
    `endif
    
`endif
