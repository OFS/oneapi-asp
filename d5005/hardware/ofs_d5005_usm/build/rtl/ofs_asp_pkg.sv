// Copyright 2022 Intel Corporation
// SPDX-License-Identifier: MIT

`include "ofs_asp.vh"

package ofs_asp_pkg;

    parameter BITS_PER_BYTE = 8;

    parameter HOSTMEM_DATA_WIDTH = ofs_plat_host_chan_pkg::DATA_WIDTH;
    
    parameter ASP_MMIO_DATA_WIDTH = ofs_plat_host_chan_pkg::MMIO_DATA_WIDTH;
    parameter ASP_MMIO_ADDR_WIDTH = ofs_plat_host_chan_pkg::MMIO_ADDR_WIDTH_BYTES;
    parameter ASP_MMIO_QSYS_ADDR_WIDTH = 18;
    
    parameter ASP_LOCALMEM_NUM_CHANNELS     = local_mem_cfg_pkg::LOCAL_MEM_NUM_BANKS;
    parameter ASP_LOCALMEM_AVMM_DATA_WIDTH  = local_mem_cfg_pkg::LOCAL_MEM_DATA_WIDTH;
    parameter ASP_LOCALMEM_AVMM_ADDR_WIDTH  = local_mem_cfg_pkg::LOCAL_MEM_BYTE_ADDR_WIDTH;
    parameter ASP_LOCALMEM_AVMM_BURSTCNT_WIDTH = local_mem_cfg_pkg::LOCAL_MEM_BURST_CNT_WIDTH;
    parameter ASP_LOCALMEM_AVMM_BYTEENABLE_WIDTH = ASP_LOCALMEM_AVMM_DATA_WIDTH/8;
    
    //some parameters for QSYS/kernel-system
    parameter ASP_LOCALMEM_QSYS_BURSTCNT_WIDTH = 5; //burstcount limit of 16

    //The kernel-system can only access on a per-word basis. The data bus
    //  to the EMIF is ASP_LOCALMEM_AVMM_DATA_WIDTH bits. Use clog2() to figure out
    //  how many lsbs to zero-out or shift.
    parameter KERNELSYSTEM_MEMORY_WORD_BYTE_OFFSET = $clog2(HOSTMEM_DATA_WIDTH/BITS_PER_BYTE);
    
    parameter KERNELSYSTEM_LOCALMEM_ADDR_WIDTH = ASP_LOCALMEM_AVMM_ADDR_WIDTH-KERNELSYSTEM_MEMORY_WORD_BYTE_OFFSET;
    
    // Host Memory
    parameter HOSTMEM_WORD_ADDR_WIDTH = ofs_plat_host_chan_pkg::ADDR_WIDTH_LINES;
    parameter HOSTMEM_BYTE_ADDR_WIDTH = ofs_plat_host_chan_pkg::ADDR_WIDTH_BYTES;

    // Parameters for USM
    parameter USM_AVMM_ADDR_WIDTH = HOSTMEM_WORD_ADDR_WIDTH + KERNELSYSTEM_MEMORY_WORD_BYTE_OFFSET;
    parameter USM_AVMM_DATA_WIDTH = HOSTMEM_DATA_WIDTH;
    parameter USM_AVMM_BURSTCOUNT_WIDTH = 5;
    parameter USM_BURSTCOUNT_MAX = 16;

    parameter KERNEL_CRA_DATA_WIDTH = ASP_MMIO_DATA_WIDTH;
    parameter KERNEL_CRA_ADDR_WIDTH = 30;
    parameter KERNEL_CRA_BYTEENABLE_WIDTH = KERNEL_CRA_DATA_WIDTH/8;

    //Some parameters for the kernel-wrapper's AVMM pipeline bridges
    // memory pipelines
    parameter KERNELWRAPPER_MEM_PIPELINE_STAGES_RDDATA = 2;
    parameter KERNELWRAPPER_MEM_PIPELINE_STAGES_CMD    = 1;
    //this wait-req needs to be reflected in both the board_spc.xml and ccb (cross-to-kernel) settings
    parameter KERNELWRAPPER_MEM_PIPELINE_DISABLEWAITREQBUFFERING = 1;
    // CRA pipelines
    parameter KERNELWRAPPER_CRA_PIPELINE_STAGES_RDDATA = 2;
    parameter KERNELWRAPPER_CRA_PIPELINE_STAGES_CMD    = 1;
    //this wait-req needs to be reflected in both the board_spc.xml and ccb settings
    parameter KERNELWRAPPER_CRA_PIPELINE_DISABLEWAITREQBUFFERING = 1;
    //USM memory pipelines
    parameter KERNELWRAPPER_SVM_PIPELINE_STAGES_RDDATA = 3;
    parameter KERNELWRAPPER_SVM_PIPELINE_STAGES_CMD    = 1;
    //this wait-req needs to be reflected in both the board_spc.xml and ccb (cross-to-kernel) settings
    parameter KERNELWRAPPER_SVM_PIPELINE_DISABLEWAITREQBUFFERING = 1;
    
    //Interrupt parameters
    parameter ASP_NUM_INTERRUPT_LINES = 4;
    parameter ASP_NUM_IRQ_USED     = 3; //DMA_0, kernel, DMA_1
    parameter ASP_DMA_0_IRQ_BIT    = 0;
    parameter ASP_KERNEL_IRQ_BIT   = 1;
    parameter ASP_DMA_1_IRQ_BIT    = 2;
    
    // parameters to differentiate between DMA-only and DMA+USM BSPs
    `ifdef INCLUDE_USM_SUPPORT
        parameter NUM_VTP_PORTS = 4;
    `else
        parameter NUM_VTP_PORTS = 2;
    `endif
    
    `ifdef USE_KERNEL_CLK_EVERYWHERE_IN_PR_REGION
        parameter USE_PIM_CDC_HOSTCHAN = 1;
        `define USE_PIM_CDC_FOR_HOSTCHAN 1
        parameter USE_PIM_CDC_LOCALMEM = 1;
        `define USE_PIM_CDC_FOR_LOCALMEM 1
    `else
        `ifdef USE_PIM_CDC_FOR_HOSTCHAN
            parameter USE_PIM_CDC_HOSTCHAN = 1;
        `else
            parameter USE_PIM_CDC_HOSTCHAN = 0;
        `endif
        `ifdef USE_PIM_CDC_FOR_LOCALMEM
            parameter USE_PIM_CDC_LOCALMEM = 1;
         `else
            parameter USE_PIM_CDC_LOCALMEM = 0;
         `endif
    `endif
    // Byte address of VTP CSRs
    parameter VTP_SVC_MMIO_BASE_ADDR = 'h2_4000;
    // DFH end-of-list flag - '0' means this is the end of the DFH list
    parameter MPF_VTP_DFH_NEXT_ADDR = 0;
    
    // USM kernel clock crossing bridge
    parameter USM_CCB_RESPONSE_FIFO_DEPTH       = 512;
    parameter USM_CCB_COMMAND_FIFO_DEPTH        = 256;
    parameter USM_CCB_COMMAND_ALMFULL_THRESHOLD = 16;
    
    //number of IO Channels/Pipes enabled in the ASP.
    `ifdef INCLUDE_IO_PIPES
        parameter IO_PIPES_NUM_CHAN = `OFS_FIM_IP_CFG_HSSI_SS_NUM_ETH_PORTS;
    `else
        parameter IO_PIPES_NUM_CHAN = 0;
    `endif
    //Avalon Streaming data width - I/O Pipe connection to kernel-system
    parameter ASP_ETH_PKT_DATA_WIDTH = ofs_fim_eth_if_pkg::ETH_PACKET_WIDTH;
    
endpackage : ofs_asp_pkg
