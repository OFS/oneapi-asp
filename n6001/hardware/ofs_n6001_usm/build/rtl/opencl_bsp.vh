// Copyright 2022 Intel Corporation
// SPDX-License-Identifier: MIT

`ifndef opencl_bsp_vh

    `define opencl_bsp_vh

    `define PAC_BSP_ENABLE_DDR4_BANK1 1
    `define PAC_BSP_ENABLE_DDR4_BANK2 1
    `define PAC_BSP_ENABLE_DDR4_BANK3 1
    `define PAC_BSP_ENABLE_DDR4_BANK4 1

    //Use the MPF-VTP functionality in the host-memory DMA datapath.
    `define USE_MPF_VTP 1
    
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

`endif
