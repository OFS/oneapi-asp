// Copyright 2022 Intel Corporation
// SPDX-License-Identifier: MIT
//

//This module will track the AVMM write-requests from 1 of 2 multiplexed 
// channels and manage send single wr-ack signal back to the appropriate 
// source.
// a-ch ---
//        |---c-ch
// b-ch ---
//

`include "ofs_plat_if.vh"

module avmm_wr_ack_tracker
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
    //per-burst write-ack and burstcnt information for ack-multiplier
    output logic kernel_avmm_wr_ack,
    output logic [AVMM_BURSTCNT_WIDTH-1:0] kernel_avmm_wr_ack_burstcnt,
    
    //out-channel
    input logic emif_avmm_clk,
    input logic emif_avmm_reset,
    input logic emif_avmm_waitreq,
    input logic emif_avmm_wr,
    input logic [AVMM_BURSTCNT_WIDTH-1:0] emif_avmm_burstcnt,
    input logic [AVMM_ADDR_WIDTH-1:0] emif_avmm_address,
    input logic emif_avmm_wr_ack
);

//Theory of operation:
//  - push the in-channel write event into a FIFO
//      - store the address, burstcnt
//  - push the out-channel write event into another DCFIFO
//      - store the address, burstcnt
//      - read-side is in channel-0 clock domain
//      - write-side is in out-channel clock domain
//  - push the  write-ack into a DCFIFO
//      - write-side is in out-channel clock domain
//      - read-side is in channel-0 clock domain
//  - pop the write-ack from the FIFO (ch0 clk domain)
//  - use the popped-wrack to pop from the out-channel FIFO.
//      - compare the address on the burst-channel Q output with
//        the output on the channel-0 Q output.
//          - if match, output the burstcnt and wrack signals to ch0
//          - else, output the burstcnt and wrack signals to ch1 (unused)
typedef struct packed {
    logic [AVMM_BURSTCNT_WIDTH-1:0] burstcnt;
    logic [AVMM_ADDR_WIDTH-1:0]     address;
} write_event_data;

localparam KERNEL_AVMM_WR_EVENT_FIFO_DEPTH = 512;
localparam KERNEL_AVMM_WR_EVENT_ALMOSTFULL_THRESHOLD = 10;
typedef enum {  ST_IDLE,
                ST_BURST,
                ST_XXX} write_event_state;
write_event_state we_cs, we_ns;

write_event_data kernel_avmm_wr_event_data;
write_event_data kernel_avmm_wr_event_data_q;
logic kernel_avmm_start_of_write;
logic kernel_avmm_wr_event_notFull;
logic kernel_avmm_wr_event_almostFull;
logic kernel_avmm_wr_event_deq;
logic kernel_avmm_wr_event_ff_notEmpty;
logic [AVMM_BURSTCNT_WIDTH-1:0] kernel_avmm_burstcntr;
logic kernel_avmm_valid_wr_req;

//two states to track the initial write-events - idle and in-burst
always_ff @(posedge kernel_avmm_clk)
begin
    we_cs  <= we_ns;
    if (kernel_avmm_reset) we_cs <= ST_IDLE;
end

always_comb
begin
    we_ns = ST_XXX;
    kernel_avmm_start_of_write = 'b0;
    case (we_cs)
        ST_IDLE:    if (kernel_avmm_valid_wr_req) begin
                        //this is the start of a write-event
                        kernel_avmm_start_of_write = 'b1;
                        //if burstcnt is > 1
                        if ( |(kernel_avmm_burstcnt>>1) ) begin
                            we_ns = ST_BURST;
                        end else begin
                            we_ns = ST_IDLE;
                        end
                    end else begin
                        we_ns = ST_IDLE;
                    end
        ST_BURST:   if (kernel_avmm_valid_wr_req) begin
                        if (kernel_avmm_burstcntr=='h1) begin
                            we_ns = ST_IDLE;
                        end else begin
                            we_ns = ST_BURST;
                        end
                    end else begin
                        we_ns = ST_BURST;
                    end
    endcase
end

//kernel-system has WRA>0, so wait-request doesn't negate the wr signal
assign kernel_avmm_valid_wr_req = kernel_avmm_wr;

always_ff @(posedge kernel_avmm_clk) 
begin
    if (kernel_avmm_start_of_write)
        kernel_avmm_burstcntr <= kernel_avmm_burstcnt - 1'b1;
    else if (kernel_avmm_valid_wr_req)
        kernel_avmm_burstcntr <= kernel_avmm_burstcntr - 1'b1;
    if (kernel_avmm_reset)
        kernel_avmm_burstcntr <= '1;
end

assign kernel_avmm_wr_event_data.burstcnt = kernel_avmm_burstcnt;
assign kernel_avmm_wr_event_data.address  = kernel_avmm_address;

ofs_plat_prim_fifo_dc 
#(
    .N_DATA_BITS(AVMM_ADDR_WIDTH+AVMM_BURSTCNT_WIDTH),
    .N_ENTRIES  (KERNEL_AVMM_WR_EVENT_FIFO_DEPTH),
    .THRESHOLD  (KERNEL_AVMM_WR_EVENT_ALMOSTFULL_THRESHOLD)
)
kernel_avmm_write_event_fifo
(
    .enq_clk    (kernel_avmm_clk),
    .enq_reset_n(!kernel_avmm_reset),
    .enq_data   (kernel_avmm_wr_event_data),
    .enq_en     (kernel_avmm_start_of_write),
    .notFull    (kernel_avmm_wr_event_notFull),
    .almostFull (kernel_avmm_wr_event_almostFull),

    .deq_clk    (kernel_avmm_clk),
    .deq_reset_n(!kernel_avmm_reset),
    .first      (kernel_avmm_wr_event_data_q),
    .deq_en     (kernel_avmm_wr_event_deq),
    .notEmpty   (kernel_avmm_wr_event_ff_notEmpty)
);



//
//Capture the local-memory write events
//

localparam EMIF_AVMM_WR_EVENT_FIFO_DEPTH = 512;
localparam EMIF_AVMM_WR_EVENT_ALMOSTFULL_THRESHOLD = 10;
write_event_state lwe_cs, lwe_ns;

write_event_data emif_avmm_wr_event_data;
write_event_data emif_avmm_wr_event_data_q;
logic emif_avmm_start_of_write;
logic emif_avmm_wr_event_notFull;
logic emif_avmm_wr_event_almostFull;
logic emif_avmm_wr_event_ff_deq;
logic emif_avmm_wr_event_ff_notEmpty;
logic emif_avmm_decrement_burstcntr;
logic [AVMM_BURSTCNT_WIDTH-1:0] emif_avmm_burstcntr;
logic emif_avmm_valid_wr_req;

//two states to track the initial write-events - idle and in-burst
always_ff @(posedge emif_avmm_clk)
begin
    lwe_cs  <= lwe_ns;
    if (emif_avmm_reset) lwe_cs <= ST_IDLE;
end

always_comb
begin
    lwe_ns = ST_XXX;
    emif_avmm_start_of_write = 'b0;
    case (lwe_cs)
        ST_IDLE:    if (emif_avmm_valid_wr_req) begin
                        //this is the start of a write-event
                        emif_avmm_start_of_write = 'b1;
                        //if burstcnt is > 1
                        if ( |(emif_avmm_burstcnt>>1) ) begin
                            lwe_ns = ST_BURST;
                        end else begin
                            lwe_ns = ST_IDLE;
                        end
                    end else begin
                        lwe_ns = ST_IDLE;
                    end
        ST_BURST:   if (emif_avmm_valid_wr_req) begin
                        if (emif_avmm_burstcntr=='h1) begin
                            lwe_ns = ST_IDLE;
                        end else begin
                            lwe_ns = ST_BURST;
                        end
                    end else begin
                        lwe_ns = ST_BURST;
                    end
    endcase
end

assign emif_avmm_valid_wr_req = emif_avmm_wr && !emif_avmm_waitreq;
always_ff @(posedge emif_avmm_clk) 
begin
    if (emif_avmm_start_of_write)
        emif_avmm_burstcntr <= emif_avmm_burstcnt - 1'b1;
    else if (emif_avmm_valid_wr_req)
        emif_avmm_burstcntr <= emif_avmm_burstcntr - 1'b1;
    if (emif_avmm_reset)
        emif_avmm_burstcntr <= '0;
end

assign emif_avmm_wr_event_data.address  = emif_avmm_address;
assign emif_avmm_wr_event_data.burstcnt = emif_avmm_burstcnt;

ofs_plat_prim_fifo_dc 
#(
    .N_DATA_BITS(AVMM_ADDR_WIDTH+AVMM_BURSTCNT_WIDTH),
    .N_ENTRIES  (EMIF_AVMM_WR_EVENT_FIFO_DEPTH),
    .THRESHOLD  (EMIF_AVMM_WR_EVENT_ALMOSTFULL_THRESHOLD)
)
emif_avmm_write_event_fifo
(
    .enq_clk    (emif_avmm_clk),
    .enq_reset_n(!emif_avmm_reset),
    .enq_data   (emif_avmm_wr_event_data),
    .enq_en     (emif_avmm_start_of_write),
    .notFull    (emif_avmm_wr_event_notFull),
    .almostFull (emif_avmm_wr_event_almostFull),

    .deq_clk    (kernel_avmm_clk),
    .deq_reset_n(!kernel_avmm_reset),
    .first      (emif_avmm_wr_event_data_q),
    .deq_en     (emif_avmm_wr_event_ff_deq),
    .notEmpty   (emif_avmm_wr_event_ff_notEmpty)
);

//sync the incoming emif_avmm_wr_ack signal into the kernel-clock domain
logic emif_avmm_wr_ack_ff_notFull;
logic emif_avmm_wr_ack_ff_almostFull;
logic emif_avmm_wr_ack_ff_notEmpty;
logic emif_avmm_wr_ack_ff_deq;
ofs_plat_prim_fifo_dc 
#(
    .N_DATA_BITS(1),
    .N_ENTRIES  (256),
    .THRESHOLD  (2)
)
emif_avmm_write_ack_fifo
(
    .enq_clk    (emif_avmm_clk),
    .enq_reset_n(!emif_avmm_reset),
    .enq_data   (1'b1),
    .enq_en     (emif_avmm_wr_ack),
    .notFull    (emif_avmm_wr_ack_ff_notFull),
    .almostFull (emif_avmm_wr_ack_ff_almostFull),

    .deq_clk    (kernel_avmm_clk),
    .deq_reset_n(!kernel_avmm_reset),
    .first      (), //unused; just the notEmpty flag is needed
    .deq_en     (emif_avmm_wr_ack_ff_deq),
    .notEmpty   (emif_avmm_wr_ack_ff_notEmpty)
);
assign emif_avmm_wr_ack_ff_deq = emif_avmm_wr_ack_ff_notEmpty;

//
//the above two blocks capture the burst-cnt information for the kernel-system and local-memory requests
//
assign emif_avmm_wr_event_ff_deq = emif_avmm_wr_event_ff_notEmpty && emif_avmm_wr_ack_ff_notEmpty;

always_ff @(posedge kernel_avmm_clk)
begin
    kernel_avmm_wr_ack <= 'b0;
    
    if (emif_avmm_wr_ack_ff_notEmpty & emif_avmm_wr_event_ff_notEmpty & kernel_avmm_wr_event_ff_notEmpty) begin
        if (kernel_avmm_wr_event_data_q.address == emif_avmm_wr_event_data_q.address) begin
            kernel_avmm_wr_ack <= 'b1;
            kernel_avmm_wr_ack_burstcnt <= emif_avmm_wr_event_data_q.burstcnt;
        end
    end
    if (kernel_avmm_reset) begin
        kernel_avmm_wr_ack <= 'b0;
        kernel_avmm_wr_ack_burstcnt <= 'b0;
    end
end

//popping from the kernel's AVMM write-event FIFO needs to happen immediately
//assign kernel_avmm_wr_event_deq = kernel_avmm_wr_ack;
always_comb
begin
    if (emif_avmm_wr_ack_ff_notEmpty & emif_avmm_wr_event_ff_notEmpty & kernel_avmm_wr_event_ff_notEmpty &
        (kernel_avmm_wr_event_data_q.address == emif_avmm_wr_event_data_q.address) )
            kernel_avmm_wr_event_deq = 'b1;
    else
            kernel_avmm_wr_event_deq = 'b0;
end

endmodule : avmm_wr_ack_tracker
