// Copyright 2022 Intel Corporation
// SPDX-License-Identifier: MIT
//

//
//This module will convert a per-burst write-ack into a per-word write-ack
//

`include "ofs_plat_if.vh"

module avmm_wr_ack_burst_to_word
import ofs_asp_pkg::*;
import local_mem_cfg_pkg::*;
#(
    parameter AVMM_ADDR_WIDTH=LOCAL_MEM_ADDR_WIDTH,
    parameter AVMM_BURSTCNT_WIDTH=LOCAL_MEM_BURST_CNT_WIDTH
)
(
    input logic clk,
    input logic reset,
    
    input logic [AVMM_BURSTCNT_WIDTH-1:0] burstcnt,
    input logic per_burst_write_ack_in,
    
    output logic per_word_write_ack_out
);

//Theory of operation:
// Add burstcnt to the per_word_ack_counter upon reception of 
//   per_burst_write_ack_in.
// Decrement per_burst_write_ack_in each time we send a write-ack to 
//   the kernel-system.
// Don't forget about the case of simultaneous ack-in / ack-out.
//

logic [9:0] per_word_ack_counter;
logic per_burst_write_ack_in_d;
logic [AVMM_BURSTCNT_WIDTH-1:0] burstcnt_d;

//register the incoming write-ack and burst-count
always_ff @(posedge clk)
begin
    per_burst_write_ack_in_d    <= per_burst_write_ack_in;
    burstcnt_d                  <= burstcnt;
    if (reset) begin
        per_burst_write_ack_in_d    <= 'b0;
        burstcnt_d                  <= 'b0;
    end
end

//manage the per-word write-ack counter
// if ack-in and ack-out: add (burstcnt_d - 2)
// else if ack-in: add (burstcnt_d - 1)
// else if ack-out: decrement burstcnt_d
always_ff @(posedge clk)
begin
    if (per_burst_write_ack_in_d & !per_word_ack_counter)
        per_word_ack_counter <= burstcnt_d;
    else if (per_burst_write_ack_in_d)
        per_word_ack_counter <= per_word_ack_counter + burstcnt_d - per_word_write_ack_out;
    else if (per_word_write_ack_out && (|per_word_ack_counter) )
        per_word_ack_counter <= per_word_ack_counter - 1'b1;
    
    if (reset) 
        per_word_ack_counter <= 'b0;
end

//generate a per-word write-ack when the counter is non-zero
//always_ff @(posedge clk)
//begin
//    per_word_write_ack_out <= 1'b0;
//    if (|per_word_ack_counter)
//        per_word_write_ack_out <= 1'b1;
//    if (reset)
//        per_word_write_ack_out <= 1'b0;
//end
always_comb
begin
    per_word_write_ack_out = |per_word_ack_counter;
end

endmodule : avmm_wr_ack_burst_to_word
