// Copyright 2022 Intel Corporation
// SPDX-License-Identifier: MIT
//

//
//This module will track the per-burst write-acks from the AVMM-AXI conversion
//  and generate the appropriate number of per-word write-acks to the
//  kernel-system.
//

`include "ofs_plat_if.vh"

module avmm_wr_ack_gen
import ofs_asp_pkg::*;
import local_mem_cfg_pkg::*;
#(
    parameter AVMM_ADDR_WIDTH=LOCAL_MEM_ADDR_WIDTH,
    parameter AVMM_BURSTCNT_WIDTH=LOCAL_MEM_BURST_CNT_WIDTH
)
(
    //in-channel 0
    input logic kernel_avmm_clk,
    input logic kernel_avmm_reset,
    input logic kernel_avmm_waitreq,
    input logic kernel_avmm_wr,
    input logic [AVMM_BURSTCNT_WIDTH-1:0] kernel_avmm_burstcnt,
    input logic [AVMM_ADDR_WIDTH-1:0] kernel_avmm_address,
    output logic kernel_avmm_wr_ack,
    
    //out-channel
    input logic emif_avmm_clk,
    input logic emif_avmm_reset,
    input logic emif_avmm_waitreq,
    input logic emif_avmm_wr,
    input logic [AVMM_BURSTCNT_WIDTH-1:0] emif_avmm_burstcnt,
    input logic [AVMM_ADDR_WIDTH-1:0] emif_avmm_address,
    input logic emif_avmm_wr_ack
);

//register kernel clock for local use
logic [1:0] kernel_avmm_reset_d;
logic kernel_avmm_reset_lcl;
always_ff @(posedge kernel_avmm_clk or posedge kernel_avmm_reset) begin
    kernel_avmm_reset_d <= {kernel_avmm_reset_d[0], 1'b0};
    if (kernel_avmm_reset) kernel_avmm_reset_d <= 2'b11;
end
assign kernel_avmm_reset_lcl = kernel_avmm_reset_d[1];

//Theory of operation:
// Two sub-blocks - one to track the order of write-events between
//  the kernel-system and DMA controller and associated burst-count,
//  and one to generate the appropriate number of write-acks for the
//  kernel-system. The AVMM-AXI conversion generates one write-ack
//  per burst while the kernel-system expects one write-ack per word.
//
logic kernel_avmm_wr_ack_per_burst;
logic [AVMM_BURSTCNT_WIDTH-1:0] kernel_avmm_wr_ack_burstcnt;

// local-memory/DDR write-ack tracking
avmm_wr_ack_tracker avmm_wr_ack_tracker_inst (
    //in-channel 0
    .kernel_avmm_clk        ,
    .kernel_avmm_reset      (kernel_avmm_reset_lcl),
    .kernel_avmm_waitreq    ,
    .kernel_avmm_wr         ,
    .kernel_avmm_burstcnt   ,
    .kernel_avmm_address    ,
    .kernel_avmm_wr_ack         (kernel_avmm_wr_ack_per_burst),
    .kernel_avmm_wr_ack_burstcnt(kernel_avmm_wr_ack_burstcnt),
    
    //AVMM channel up to PIM (AVMM-AXI conversion with write-ack)
    .emif_avmm_clk          ,
    .emif_avmm_reset        ,
    .emif_avmm_waitreq      ,
    .emif_avmm_wr           ,
    .emif_avmm_burstcnt     ,
    .emif_avmm_address      ,
    .emif_avmm_wr_ack      
);


//write-ack multiplier
// write-acks from AVMM-AXI conversion was per-burst; kernel-system expets
//  per-word.
avmm_wr_ack_burst_to_word avmm_wr_ack_burst_to_word_inst
(
    .clk                    (kernel_avmm_clk),
    .reset                  (kernel_avmm_reset_lcl),
    .per_burst_write_ack_in (kernel_avmm_wr_ack_per_burst),
    .burstcnt               (kernel_avmm_wr_ack_burstcnt),
    .per_word_write_ack_out (kernel_avmm_wr_ack)
);


endmodule : avmm_wr_ack_gen
