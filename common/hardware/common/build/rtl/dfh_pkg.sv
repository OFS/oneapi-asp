// Copyright 2022 Intel Corporation
// SPDX-License-Identifier: MIT
//

package dfh_pkg;

    parameter BYTES_PER_WORD = 16'h0008;

    //Static register values for the UDP OE DFHv1 Information
    parameter DFH_HDR_FTYPE             = 4'h2;
    parameter DFH_HDR_VER               = 8'h01;
    parameter DFH_HDR_RSVD0             = 11'h0;
    parameter DFH_HDR_EOL               = 1'b1;
    parameter DFH_HDR_NEXT_DFH          = 24'h0;
    parameter DFH_HDR_FEATURE_REV       = 4'h0;
    parameter DFH_HDR_FEATURE_ID        = 12'h0;

    parameter DFH_ID_LO = 64'h0;
    parameter DFH_ID_HI = 64'h0;
    
    parameter DFH_NEXT_AFU_OFFSET = 24'h01_0000;

    parameter DFH_REG_ADDR_OFFSET = 63'b0;
    parameter DFH_REL             = 1'b0;
    
    parameter DFH_REG_SZ   = 32'd512;
    parameter DFH_PARAMS   = 1'b0;
    parameter DFH_GROUP    = 15'h0;
    parameter DFH_INSTANCE = 16'h0;
    
    // MMIO64 widths
    parameter MMIO64_ADDR_WIDTH = 8;
    parameter MMIO64_DATA_WIDTH = 64;
    
    //data to return on a read that ends up in the default case
    parameter REG_RD_BADADDR_DATA = 64'h0BAD_0ADD_0BAD_0ADD;
        
    //
    // Dispatcher register addresses
    //misc/DFH regs
    parameter DFHv1_GEN_BASE_ADDR           = 'h00;
    parameter DFH_HEADER_ADDR               = DFHv1_GEN_BASE_ADDR + 'h00;//ro
    parameter DFH_ID_LO_ADDR                = DFHv1_GEN_BASE_ADDR + 'h01;//ro
    parameter DFH_ID_HI_ADDR                = DFHv1_GEN_BASE_ADDR + 'h02;//ro
    parameter DFH_REG_ADDR_OFFSET_ADDR      = DFHv1_GEN_BASE_ADDR + 'h03;//ro
    parameter DFH_REGSZ_PARAMS_GR_INST_ADDR = DFHv1_GEN_BASE_ADDR + 'h04;//ro
    
    //DFH Feature registers
    parameter REG_FEATURE_BASE_ADDR         = DFHv1_GEN_BASE_ADDR + 'h10;
    parameter SCRATCHPAD_ADDR               = REG_FEATURE_BASE_ADDR + 'h00;//rw
    
endpackage : dfh_pkg
