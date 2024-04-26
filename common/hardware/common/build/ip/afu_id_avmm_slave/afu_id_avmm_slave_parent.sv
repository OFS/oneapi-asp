// Copyright 2022 Intel Corporation
// SPDX-License-Identifier: MIT
//

`define AFU_ID_AVMM_SLAVE_DATA_WIDTH 64
`define AFU_ID_AVMM_SLAVE_ADDR_WIDTH 3

module afu_id_avmm_slave #(
        //uuid: 331db30c-9885-41ea-9081-f88b8f655caa
        parameter AFU_ID_H = 64'h331D_B30C_9885_41EA,
        parameter AFU_ID_L = 64'h9081_F88B_8F65_5CAA,
        
        parameter DFH_FEATURE_TYPE = 4'b0001,
        parameter DFH_AFU_MINOR_REV = 4'b0000,
        parameter DFH_AFU_MAJOR_REV = 4'b0000,
        parameter DFH_END_OF_LIST = 1'b1,
        parameter DFH_NEXT_OFFSET = 24'b0,
        parameter DFH_FEATURE_ID = 12'b0,
        
        parameter NEXT_AFU_OFFSET = 24'b0,
        
        parameter CREATE_SCRATCH_REG = 1'b0
	)
	(
	//input avmm_chipselect,
	input avmm_write,
	input avmm_read,
	//input 	[(`AFU_ID_AVMM_SLAVE_DATA_WIDTH/8)-1:0]	avmm_byteenable
	input [`AFU_ID_AVMM_SLAVE_DATA_WIDTH-1:0] avmm_writedata,
	output logic [`AFU_ID_AVMM_SLAVE_DATA_WIDTH-1:0] avmm_readdata,
	
	input [`AFU_ID_AVMM_SLAVE_ADDR_WIDTH-1:0]	avmm_address,
	
	input clk,
	input reset
);

    //hack to work around the fact this file is used for both the AFU DFH as well
    //as the null-DFH to set the end-of-list bit.
    logic this_is_main_parent_dfh = (AFU_ID_H == 64'hda1182b1b3444e23) ? 1'b0 : 1'b1;

    localparam NUM_CHILD_LINKS = 1;
    logic [`AFU_ID_AVMM_SLAVE_DATA_WIDTH-1:0] DFH_addr_5, DFH_addr_6, DFH_addr_7;

	always_ff @(posedge clk) begin
		avmm_readdata <= '0;
		if(reset) begin
			avmm_readdata <= '0;
		end
		else begin
			// serve MMIO read requests
			if(avmm_read) begin
				case(avmm_address)
					// AFU header
					4'h0: avmm_readdata <= this_is_main_parent_dfh ? {
						DFH_FEATURE_TYPE, // [63:60] Feature type = AFU(4'h1)
						8'h1,             // [59:52] DFH v1
						DFH_AFU_MINOR_REV,    // afu minor revision = 0
						7'b0,    // reserved
						DFH_END_OF_LIST,    // end of DFH list = 1 
						DFH_NEXT_OFFSET,   // next DFH offset = 0
						DFH_AFU_MAJOR_REV,    // afu major revision = 0
						DFH_FEATURE_ID    // feature ID = 0
					} : {
						DFH_FEATURE_TYPE, // Feature type = AFU
						8'b0,    // reserved
						DFH_AFU_MINOR_REV,    // afu minor revision = 0
						7'b0,    // reserved
						DFH_END_OF_LIST,    // end of DFH list = 1 
						DFH_NEXT_OFFSET,   // next DFH offset = 0
						DFH_AFU_MAJOR_REV,    // afu major revision = 0
						DFH_FEATURE_ID    // feature ID = 0
					};
					4'h1: avmm_readdata <= AFU_ID_L; // afu id low
					4'h2: avmm_readdata <= AFU_ID_H; // afu id hi
					4'h3: avmm_readdata <= {40'h0, NEXT_AFU_OFFSET}; // next AFU
					4'h4: avmm_readdata <= this_is_main_parent_dfh ? 
                                            {32'b0, 1'b1, 31'b0} : // feature has parameter(s)
                                            64'b0;
					4'h5: avmm_readdata <= this_is_main_parent_dfh ? DFH_addr_5 : 'b0;
                    4'h6: avmm_readdata <= this_is_main_parent_dfh ? DFH_addr_6 : 'b0;
                    4'h7: avmm_readdata <= this_is_main_parent_dfh ? DFH_addr_7 : 'b0;
					default:  avmm_readdata <= 64'h0;
				endcase
			end
		end
	end
    
    always_comb begin
        DFH_addr_5        = '0;
        // One parameter block -- the list of child GUIDs.
        // Size of parameter block (8 byte words)
        DFH_addr_5[63:35] = (2*NUM_CHILD_LINKS) + 1;
        // EOP
        DFH_addr_5[32]    = 1'b1;
        // Parameter ID (child AFUs).
        // See https://github.com/OFS/dfl-feature-id/blob/main/dfl-param-ids.rst
        DFH_addr_5[15:0]  = 2; 
        
        //child DFH_LO/HI
        DFH_addr_6 = 'b0;
        DFH_addr_7 = 'b0;
    end

endmodule
