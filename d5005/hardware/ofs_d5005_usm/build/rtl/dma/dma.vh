// Copyright 2022 Intel Corporation
// SPDX-License-Identifier: MIT

`ifndef dma_vh

    `define dma_vh

    //Enable generation of FPGA-to-HOST memory writes of the magic number 
    //  at the end of a host-mem-write transaction
    `define DO_F2H_MAGIC_NUMBER_WRITE 1
    
    `define DMA_DO_SINGLE_BURST_PARTIAL_WRITES 1

`endif
