// Copyright 2022 Intel Corporation
// SPDX-License-Identifier: MIT

`include "opencl_bsp.vh"

package dc_bsp_pkg;

    //Each memory bank is 8GB. 512b/(8b/B)*(27'1)=8GB.
    parameter OPENCL_DDR_ADDR_WIDTH = 27;
    // SVM
    parameter OPENCL_MEMORY_ADDR_WIDTH = 42;
    //OpenCL can only access on a per-word basis. The data bus
    //  to the EMIF is 512 bits (64 bytes), so we need to
    //  zero-out the 6 lsbs.
    parameter OPENCL_MEMORY_BYTE_OFFSET = 6;
    //Add the EMIF address width to the byte-offset width to get the
    //  address size for the QSYS components.
    parameter OPENCL_QSYS_ADDR_WIDTH = OPENCL_DDR_ADDR_WIDTH + OPENCL_MEMORY_BYTE_OFFSET;

    // Offset for SVM
    parameter OPENCL_SVM_QSYS_ADDR_WIDTH = OPENCL_MEMORY_ADDR_WIDTH + OPENCL_MEMORY_BYTE_OFFSET;

    parameter OPENCL_BSP_KERNEL_SVM_DATA_WIDTH = 512;
    parameter OPENCL_BSP_KERNEL_SVM_BURSTCOUNT_WIDTH = 5;
    parameter OPENCL_BSP_KERNEL_SVM_BYTEENABLE_WIDTH = 64;

    parameter OPENCL_BSP_KERNEL_DATA_WIDTH = 512;
    parameter OPENCL_BSP_KERNEL_BURSTCOUNT_WIDTH = 5;
    parameter OPENCL_BSP_KERNEL_BYTEENABLE_WIDTH = 64;
    parameter BSP_NUM_LOCAL_MEM_BANKS = 2;
    parameter BSP_MAX_AVAIL_PLATFORM_LOCAL_MEM_BANKS = 2;

    parameter OPENCL_BSP_KERNEL_CRA_DATA_WIDTH = 64;
    parameter OPENCL_BSP_KERNEL_CRA_ADDR_WIDTH = 30;
    parameter OPENCL_BSP_KERNEL_CRA_BURSTCOUNT_WIDTH = 5;
    
    //width of ASP MMIO AVMM address as seen by board.qsys
    parameter MMIO64_AVMM_ADDR_WIDTH = 18;

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

    parameter BSP_NUM_INTERRUPT_LINES = 4;
    parameter BSP_AVMM_NUM_IRQ_USED = 3; //DMA_0, kernel, DMA_1
    parameter BSP_DMA_0_IRQ_BIT    = 0;
    parameter BSP_KERNEL_IRQ_BIT   = 1;
    parameter BSP_DMA_1_IRQ_BIT    = 2;
    
    // parameters to differentiate between DMA-only and DMA+USM BSPs
    `ifdef INCLUDE_USM_SUPPORT
        parameter NUM_VTP_PORTS = 4;
        parameter NUM_SOURCE_PORTS = 2;
    `else
        parameter NUM_VTP_PORTS = 2;
        parameter NUM_SOURCE_PORTS = 1;
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
    
endpackage : dc_bsp_pkg
