// Copyright 2022 Intel Corporation
// SPDX-License-Identifier: MIT

`include "dma.vh"

package dma_pkg;

    //Static register values for the DMA DFH Information
    parameter DFH_HDR_FTYPE             = 4'h2;
    parameter DFH_HDR_RSVD0             = 8'h00;
    parameter DFH_HDR_VERSION_MINOR     = 4'h0;
    parameter DFH_HDR_RSVD1             = 7'h00;
    parameter DFH_HDR_END_OF_LIST       = 1'b0;
    parameter DFH_HDR_NEXT_DFH_OFFSET   = 24'h800;
    parameter DFH_HDR_VERSION_MAJOR     = 4'h0;
    parameter DFH_HDR_FEATURE_ID        = 12'h000;

    parameter DFH_ID_LO = 64'h575F_BAB5_B61A_8DAE;
    parameter DFH_ID_HI = 64'hBC24_AD4F_8738_F840;
    parameter MAGIC_NUMBER = 64'h5772_745F_5379_6e63;
    parameter MAGIC_NUMBER_BYTEENBLE_VALUE = {56'h0000_0000_0000_00,8'hFF};

	parameter DO_F2H_MAGIC_NUMBER_WRITE = 1;

    parameter DFH_NEXT_AFU_OFFSET = 24'h01_0000;
	
	parameter NUM_DMA_CHAN_BITS = $clog2(ofs_asp_pkg::NUM_DMA_CHAN);
	
    //address widths
    parameter HOST_MEM_ADDR_WIDTH = ofs_asp_pkg::HOSTMEM_BYTE_ADDR_WIDTH;
    parameter DEVICE_MEM_ADDR_WIDTH = $clog2(ofs_asp_pkg::ASP_LOCALMEM_NUM_CHANNELS) + ofs_asp_pkg::ASP_LOCALMEM_AVMM_ADDR_WIDTH;
    parameter XFER_SIZE_WIDTH   = 40;

    //DMA command-queue FIFO usedw width
    parameter CMDQ_USEDW_WIDTH = 8;

    // MMIO64 widths
    parameter MMIO64_ADDR_WIDTH = 8;
    parameter MMIO64_DATA_WIDTH = ofs_asp_pkg::ASP_MMIO_DATA_WIDTH;
    
    // DMA AVMM widths
    parameter AVMM_DATA_WIDTH = ofs_asp_pkg::ASP_LOCALMEM_AVMM_DATA_WIDTH;
    parameter AVMM_DOUBLE_DATA_WIDTH = AVMM_DATA_WIDTH*2;
    parameter AVMM_BYTEENABLE_WIDTH = AVMM_DATA_WIDTH/8;
    parameter AVMM_DBL_DATA_UWORD_BIT_HI = AVMM_DOUBLE_DATA_WIDTH-1;
    parameter AVMM_DBL_DATA_UWORD_BIT_LO = AVMM_DATA_WIDTH;
    parameter AVMM_DATA_WIDTH_IN_BYTES = AVMM_DATA_WIDTH/8;
    parameter AVMM_DOUBLE_DATA_WIDTH_IN_BYTES = AVMM_DOUBLE_DATA_WIDTH/8;
    parameter AVMM_DBL_DATA_UWORD_BYTES_BIT_HI = AVMM_DOUBLE_DATA_WIDTH_IN_BYTES-1;
    parameter AVMM_DBL_DATA_UWORD_BYTES_BIT_LO = AVMM_DATA_WIDTH_IN_BYTES;
    parameter AVMM_BURSTCOUNT_BITS = 7;
    
    //host memory data width
    parameter HOSTMEM_DATA_WIDTH = ofs_asp_pkg::HOSTMEM_DATA_WIDTH;
    parameter HOSTMEM_DATA_BYTES_PER_WORD = HOSTMEM_DATA_WIDTH / 8;
    parameter HOSTMEM_DATA_BYTES_PER_WORD_BITSHIFT = 6;
    parameter HOSTMEM_DATA_BYTES_PER_WORD_SZ = $clog2(HOSTMEM_DATA_BYTES_PER_WORD);

    //
    // Dispatcher register addresses
    //misc/DFH regs
    parameter REG_ASP_GEN_BASE_ADDR         = 'h00;
    parameter DFH_HEADER_ADDR               = REG_ASP_GEN_BASE_ADDR + 'h00;
    parameter ID_LO_ADDR                    = REG_ASP_GEN_BASE_ADDR + 'h01;
    parameter ID_HI_ADDR                    = REG_ASP_GEN_BASE_ADDR + 'h02;
    parameter DFH_NEXT_AFU_OFFSET_ADDR      = REG_ASP_GEN_BASE_ADDR + 'h03;
    parameter SCRATCHPAD_ADDR               = REG_ASP_GEN_BASE_ADDR + 'h05;
    parameter MAGICNUMBER_HOSTMEM_WR_ADDR   = REG_ASP_GEN_BASE_ADDR + 'h06;
	parameter NUM_DMA_CHAN_ADDR				= REG_ASP_GEN_BASE_ADDR + 'h07;
    
    //general data-transfer control registers
    parameter REG_HOSTRD_BASE_ADDR          = 'h10;
    parameter REG_HOSTWR_BASE_ADDR          = 'h20;
    //specific register offsets (common between host-mem read and write controllers)
    parameter REG_START_SRC_ADDR_OFFSET     = 'h00;
    parameter REG_START_DST_ADDR_OFFSET     = 'h01;
    parameter REG_TRANSFER_LENGTH_OFFSET    = 'h02;
    parameter REG_CMDQ_STATUS_OFFSET        = 'h03;
    parameter REG_DATABUF_STATUS_OFFSET     = 'h04;
    parameter REG_CONFIG_OFFSET             = 'h05;
    parameter REG_STATUS_OFFSET             = 'h06;
    parameter REG_SRC_BURSTCNT_CNT          = 'h07;
    parameter REG_SRC_READDATAVALID_CNT     = 'h08;
    parameter REG_WR_MAGICNUM_CNT           = 'h09;
    parameter REG_DST_WRDATA_CNT            = 'h0A;
    parameter REG_STATUS2_OFFSET            = 'h0B;
	parameter REG_THIS_CHAN_SRC_ADDR_OFFSET = 'h0C;
	parameter REG_THIS_CHAN_DST_ADDR_OFFSET = 'h0D;
	parameter REG_THIS_CHAN_XFER_LEN_ADDR_OFFSET = 'h0E;
	parameter REG_THIS_CHAN_NUM_ADDR_OFFSET = 'h0F;
	//a read of this offset will increment the mux-counter in the CSR/dispatcher block.
	parameter LAST_PER_CHAN_REG_ADDR_OFFSET = 'h0F;
    
    //combined address names
    //host-to-FPGA transfers (read)
    parameter HOST_RD_START_SRC_ADDR        = REG_HOSTRD_BASE_ADDR + REG_START_SRC_ADDR_OFFSET ;
    parameter HOST_RD_START_DST_ADDR        = REG_HOSTRD_BASE_ADDR + REG_START_DST_ADDR_OFFSET ;
    parameter HOST_RD_TRANSFER_LENGTH_ADDR  = REG_HOSTRD_BASE_ADDR + REG_TRANSFER_LENGTH_OFFSET;
    parameter HOST_RD_CMDQ_STATUS_ADDR      = REG_HOSTRD_BASE_ADDR + REG_CMDQ_STATUS_OFFSET    ;
    parameter HOST_RD_DATABUF_STATUS_ADDR   = REG_HOSTRD_BASE_ADDR + REG_DATABUF_STATUS_OFFSET ;
    parameter HOST_RD_CONFIG_ADDR           = REG_HOSTRD_BASE_ADDR + REG_CONFIG_OFFSET         ;
    parameter HOST_RD_STATUS_ADDR           = REG_HOSTRD_BASE_ADDR + REG_STATUS_OFFSET         ;
    parameter HOST_RD_BRSTCNT_CNT_ADDR      = REG_HOSTRD_BASE_ADDR + REG_SRC_BURSTCNT_CNT      ;
    parameter HOST_RD_RDDATAVALID_CNT_ADDR  = REG_HOSTRD_BASE_ADDR + REG_SRC_READDATAVALID_CNT ;
    parameter HOST_RD_MAGICNUM_CNT_ADDR     = REG_HOSTRD_BASE_ADDR + REG_WR_MAGICNUM_CNT ;
    parameter HOST_RD_WRDATA_CNT_ADDR       = REG_HOSTRD_BASE_ADDR + REG_DST_WRDATA_CNT ;
    parameter HOST_RD_STATUS2_ADDR          = REG_HOSTRD_BASE_ADDR + REG_STATUS2_OFFSET        ;
	parameter HOST_RD_THIS_CHAN_SRC_ADDR    = REG_HOSTRD_BASE_ADDR + REG_THIS_CHAN_SRC_ADDR_OFFSET;
	parameter HOST_RD_THIS_CHAN_DST_ADDR    = REG_HOSTRD_BASE_ADDR + REG_THIS_CHAN_DST_ADDR_OFFSET;
	parameter HOST_RD_THIS_CHAN_XFER_LEN_ADDR = REG_HOSTRD_BASE_ADDR + REG_THIS_CHAN_XFER_LEN_ADDR_OFFSET;
	parameter HOST_RD_THIS_CHAN_NUM_ADDR    = REG_HOSTRD_BASE_ADDR + REG_THIS_CHAN_NUM_ADDR_OFFSET;
	parameter HOST_RD_LAST_REG_ADDR         = REG_HOSTRD_BASE_ADDR + LAST_PER_CHAN_REG_ADDR_OFFSET;
    //FPGA-to-host transfers (write)
    parameter HOST_WR_START_SRC_ADDR        = REG_HOSTWR_BASE_ADDR + REG_START_SRC_ADDR_OFFSET ;
    parameter HOST_WR_START_DST_ADDR        = REG_HOSTWR_BASE_ADDR + REG_START_DST_ADDR_OFFSET ;
    parameter HOST_WR_TRANSFER_LENGTH_ADDR  = REG_HOSTWR_BASE_ADDR + REG_TRANSFER_LENGTH_OFFSET;
    parameter HOST_WR_CMDQ_STATUS_ADDR      = REG_HOSTWR_BASE_ADDR + REG_CMDQ_STATUS_OFFSET    ;
    parameter HOST_WR_DATABUF_STATUS_ADDR   = REG_HOSTWR_BASE_ADDR + REG_DATABUF_STATUS_OFFSET ;
    parameter HOST_WR_CONFIG_ADDR           = REG_HOSTWR_BASE_ADDR + REG_CONFIG_OFFSET         ;
    parameter HOST_WR_STATUS_ADDR           = REG_HOSTWR_BASE_ADDR + REG_STATUS_OFFSET         ;
    parameter HOST_WR_BRSTCNT_CNT_ADDR      = REG_HOSTWR_BASE_ADDR + REG_SRC_BURSTCNT_CNT      ;
    parameter HOST_WR_RDDATAVALID_CNT_ADDR  = REG_HOSTWR_BASE_ADDR + REG_SRC_READDATAVALID_CNT ;
    parameter HOST_WR_MAGICNUM_CNT_ADDR     = REG_HOSTWR_BASE_ADDR + REG_WR_MAGICNUM_CNT ;
    parameter HOST_WR_WRDATA_CNT_ADDR       = REG_HOSTWR_BASE_ADDR + REG_DST_WRDATA_CNT ;
    parameter HOST_WR_STATUS2_ADDR          = REG_HOSTWR_BASE_ADDR + REG_STATUS2_OFFSET        ;
	parameter HOST_WR_THIS_CHAN_SRC_ADDR    = REG_HOSTWR_BASE_ADDR + REG_THIS_CHAN_SRC_ADDR_OFFSET;
	parameter HOST_WR_THIS_CHAN_DST_ADDR    = REG_HOSTWR_BASE_ADDR + REG_THIS_CHAN_DST_ADDR_OFFSET;
	parameter HOST_WR_THIS_CHAN_XFER_LEN_ADDR = REG_HOSTWR_BASE_ADDR + REG_THIS_CHAN_XFER_LEN_ADDR_OFFSET;
	parameter HOST_WR_THIS_CHAN_NUM_ADDR    = REG_HOSTWR_BASE_ADDR + REG_THIS_CHAN_NUM_ADDR_OFFSET;
	parameter HOST_WR_LAST_REG_ADDR         = REG_HOSTWR_BASE_ADDR + LAST_PER_CHAN_REG_ADDR_OFFSET;

    //data to return on a read that ends up in the default case
    parameter REG_RD_BADADDR_DATA = 64'h0BAD_0ADD_0BAD_0ADD;
    
    //read-data buffer scfifo depth
    parameter RDDATA_BUFFER_DEPTH = 1024;
    
    parameter CMDQ_DEPTH = 16;
    
    //AVMM transfer details
    parameter LOCAL_MEM_RD_BURSTCOUNT_MAX = 'h10;
    parameter LOCAL_MEM_WR_BURSTCOUNT_MAX = 'h10;
    parameter HOST_MEM_RD_BURSTCOUNT_MAX = 'h4;
    parameter HOST_MEM_WR_BURSTCOUNT_MAX = 'h4;
    
    //dispatcher register bit locations - status register
    parameter STATUS_REG_RD_BUSY_BIT = 0;
    parameter STATUS_REG_WR_BUSY_BIT = 1;
    parameter STATUS_REG_IRQ_BIT     = 2;
    
    //dispatcher register bit locations - config register
    parameter CONFIG_REG_SCLR_BIT       = 0;
    parameter CONFIG_REG_CLEAR_IRQ_BIT  = 1;
    
endpackage : dma_pkg
