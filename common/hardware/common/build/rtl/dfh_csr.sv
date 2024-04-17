// Copyright 2022 Intel Corporation
// SPDX-License-Identifier: MIT
//

module dfh_csr
import dfh_pkg::*;
import ofs_asp_pkg::*;
#(
    parameter DFH_ID_HI = 64'b0,
    parameter DFH_ID_LO = 64'b0,
    parameter DFH_EOL   = 1'b1,
    parameter MISC_DATA = 64'b0
)
(
  ofs_plat_avalon_mem_if.to_source dfh_avmm
);

    logic [MMIO64_DATA_WIDTH-1:0] dfh_header_data_reg;
    logic [MMIO64_DATA_WIDTH-1:0] scratchpad_reg;
    logic [MMIO64_DATA_WIDTH-1:0] dfh_reg_0x18, dfh_reg_0x20;
    integer i;
    
    //pipeline and duplicate the csr_rst signal
    parameter RESET_PIPE_DEPTH = 2;
    logic [RESET_PIPE_DEPTH-1:0] rst_pipe;
    logic rst_local;
    always_ff @(posedge dfh_avmm.clk) begin
        {rst_local,rst_pipe}  <= {rst_pipe[RESET_PIPE_DEPTH-1:0], 1'b0};
        if (~dfh_avmm.reset_n) begin
            rst_local <= '1;
            rst_pipe  <= '1;
        end
    end

    //the address is for bytes but register accesses are full words
    logic [9:0] this_address;
    assign this_address = dfh_avmm.address>>3;
        
    //we should probably never assert waitrequest (max requests is 1)
    assign dfh_avmm.waitrequest = 'b0;
    
    // read back CSR values
    always_ff @(posedge dfh_avmm.clk) begin
        if (rst_local) begin
            dfh_avmm.readdata <= 'b0;
            dfh_avmm.readdatavalid <= 1'b0;
        end else begin
            dfh_avmm.readdatavalid <= 1'b0;
            if (dfh_avmm.read) begin
                dfh_avmm.readdatavalid <= 1'b1;
                case (this_address)
                    // DFH registers
                    DFH_HEADER_ADDR:                dfh_avmm.readdata <= dfh_header_data_reg;
                    DFH_ID_LO_ADDR:                 dfh_avmm.readdata <= DFH_ID_LO + MISC_DATA;
                    DFH_ID_HI_ADDR:                 dfh_avmm.readdata <= DFH_ID_HI;
                    DFH_REG_ADDR_OFFSET_ADDR:       dfh_avmm.readdata <= dfh_reg_0x18;
                    DFH_REGSZ_PARAMS_GR_INST_ADDR:  dfh_avmm.readdata <= dfh_reg_0x20;

                    // Common registers
                    SCRATCHPAD_ADDR:                dfh_avmm.readdata <= scratchpad_reg;
                    default:                        dfh_avmm.readdata <= REG_RD_BADADDR_DATA;
                endcase
            end
        end
    end
   
    //writes
    always_ff @(posedge dfh_avmm.clk)
    begin
        if (dfh_avmm.write) begin
            case (this_address)
                SCRATCHPAD_ADDR:                scratchpad_reg              <= dfh_avmm.writedata;
            endcase
        end
    
        if (rst_local) begin
            scratchpad_reg                    <= 'h0;
        end
    end
  
    //verbose assignment of the DFHv1-header information (keep the register-logic clean by making
    //  assignments here; parameters defined in the package file.)
    always_comb begin
        dfh_header_data_reg = { DFH_HDR_FTYPE   ,
                                DFH_HDR_VER     ,
                                DFH_HDR_RSVD0   ,
                                DFH_EOL         ,
                                DFH_HDR_NEXT_DFH,
                                DFH_HDR_FEATURE_REV,
                                DFH_HDR_FEATURE_ID };
        dfh_reg_0x18 = {DFH_REG_ADDR_OFFSET, 
                        DFH_REL};
        dfh_reg_0x20 = {DFH_REG_SZ,
                        DFH_PARAMS,
                        DFH_GROUP,
                        DFH_INSTANCE};
    end
    
endmodule : dfh_csr
