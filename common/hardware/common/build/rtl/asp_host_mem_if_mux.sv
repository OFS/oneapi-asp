// Copyright 2022 Intel Corporation
// SPDX-License-Identifier: MIT
//

`include "ofs_plat_if.vh"

//This module will multiplex the host_mem_if's write-channel between the write
//  DMA module and the ASP's IRQs.
//An IRQ is generated 
//An out-of-band AVMM signal, wr_user, is used to indicate an interrupt to the
//  PIM. Setting the appropriate bit (
//  wr_user[ofs_plat_host_chan_avalon_mem_pkg::HC_AVALON_UFLAG_INTERRUPT]) will 
//  cause the PIM to insert an IRQ on the FIM/PIM interface. 
//The PIM/FIM supports 4 IRQs from the AFU, and are indicated on the 
//  wr_address[1:0] bits. wr_write must be set and wr_burstcount needs to be
//  set to 1. 

module asp_host_mem_if_mux 
import ofs_asp_pkg::*;
#(
	parameter DMA_CHAN_NUM = 0
) (
    input clk,
    input reset,

    input [ASP_NUM_INTERRUPT_LINES-1:0] asp_irq,
    input wr_fence_flag,
    
    // Host memory (Avalon) (mux output)
    ofs_plat_avalon_mem_rdwr_if.to_sink host_mem_if,
    
    // AVMM from DMA channels in board.qsys
    ofs_plat_avalon_mem_rdwr_if.to_source asp_mem_if
);

logic [ASP_NUM_INTERRUPT_LINES-1:0] asp_irq_d;
logic [ASP_NUM_INTERRUPT_LINES-1:0] irq_pending;
logic [ASP_NUM_INTERRUPT_LINES-1:0] set_irq_pending;
logic [ASP_NUM_INTERRUPT_LINES-1:0] clear_irq_pending;

logic [9:0] burst_counter;
logic load_burst_counter;
logic enable_burst_counter;
logic [1:0] pending_irq_id;
logic send_irq_data;
logic send_wr_fence, send_wr_fence_d;
logic send_magic_number, send_magic_number_dly;

//pipeline and duplicate the reset signal
parameter RESET_PIPE_DEPTH = 4;
logic [RESET_PIPE_DEPTH-1:0] rst_pipe;
logic rst_local;
always_ff @(posedge clk) begin
    {rst_local,rst_pipe}  <= {rst_pipe[RESET_PIPE_DEPTH-1:0], 1'b0};
    if (reset) begin
        rst_local <= '1;
        rst_pipe  <= '1;
    end
end

//The asp_mem_if/host_mem_if signals are directly connected with no manipulation.
always_comb begin
    //from host to ASP - to_master
    asp_mem_if.rd_waitrequest       = host_mem_if.rd_waitrequest;
    asp_mem_if.rd_readdata          = host_mem_if.rd_readdata;
    asp_mem_if.rd_readdatavalid     = host_mem_if.rd_readdatavalid;
    asp_mem_if.rd_response          = host_mem_if.rd_response;
    asp_mem_if.rd_readresponseuser  = host_mem_if.rd_readresponseuser;
    
    //from ASP to host - to_slave
    host_mem_if.rd_address          = asp_mem_if.rd_address;
    host_mem_if.rd_read             = asp_mem_if.rd_read;
    host_mem_if.rd_burstcount       = asp_mem_if.rd_burstcount;
    host_mem_if.rd_byteenable       = asp_mem_if.rd_byteenable;
    host_mem_if.rd_user             = '0; //unused
end

//latch the incoming rising edge of the IRQ inputs; ignore the level after it has been latched
//because it will take some time for sw to clear it.
//only issue IRQs on (DMA_CHAN_NUM==0), otherwise hold this logic in reset.
genvar i;
generate
    for (i=0; i<ASP_NUM_INTERRUPT_LINES; i++) begin : irq_handling
        
        always_ff @(posedge clk) begin
            if (rst_local | (DMA_CHAN_NUM!=0))
                asp_irq_d[i] <= 'b0;
            else 
                asp_irq_d[i] <= asp_irq[i];
        end
        
        always_ff @(posedge clk) begin
            if (rst_local | (DMA_CHAN_NUM!=0))
                irq_pending[i] <= 'b0;
            else begin
                case ({set_irq_pending[i], clear_irq_pending[i]})
                    2'b01: irq_pending[i] <= 1'b0;
                    2'b10: irq_pending[i] <= 1'b1;
                    2'b11: irq_pending[i] <= 1'b1; //weird but possible to have the IRQ cleared and re-set on same clock
                    default: irq_pending[i] <= irq_pending[i];
                endcase
            end
        end
        
        //rising edge of the IRQ sets the pending flag
        assign set_irq_pending[i] = asp_irq[i] & ~asp_irq_d[i];
        
        //clear the pending flag once we've sent the IRQ data on wr_x interface
        assign clear_irq_pending[i] = send_irq_data & (pending_irq_id == i);
        
    end : irq_handling
endgenerate

assign pending_irq_id = irq_pending[0] ? 2'b00 :
                        irq_pending[1] ? 2'b01 :
                        irq_pending[2] ? 2'b10 : 2'b11;

assign send_irq_data = |irq_pending & (burst_counter == 'b0) & !host_mem_if.wr_waitrequest;

//wr_waitrequest is a combination of the waitrequest signal from the host/PIM and
//  the IRQ-write and wr-fence.
assign asp_mem_if.wr_waitrequest = host_mem_if.wr_waitrequest | send_irq_data | send_wr_fence;

//switch the wr_x signals between IRQ, wr-fence, and asp_mem_if based on the send_irq_data and send_wr_fence signals
always_comb begin
    host_mem_if.wr_burstcount   = send_irq_data ? 1                    : asp_mem_if.wr_burstcount;
    host_mem_if.wr_writedata    = send_irq_data ? '0                   : asp_mem_if.wr_writedata;
    host_mem_if.wr_address      = send_irq_data ? {'0, pending_irq_id} : asp_mem_if.wr_address;
    host_mem_if.wr_write        = send_irq_data ? 1'b1                 : asp_mem_if.wr_write;
    host_mem_if.wr_byteenable   = send_irq_data ? ~'0                  : asp_mem_if.wr_byteenable;
    
    host_mem_if.wr_user     = '0;
    if (send_irq_data) begin
        host_mem_if.wr_user[ofs_plat_host_chan_avalon_mem_pkg::HC_AVALON_UFLAG_INTERRUPT] = 1'b1;
    end else if (send_wr_fence) begin
        host_mem_if.wr_user[ofs_plat_host_chan_avalon_mem_pkg::HC_AVALON_UFLAG_FENCE] = 1'b1;
    end
end

//need to track the wr_write bursts to ensure we don't send an IRQ in the middle of a burst
assign load_burst_counter = (burst_counter == 'b0) & (asp_mem_if.wr_write) & !send_irq_data;
assign enable_burst_counter = (burst_counter != 'b0) & (asp_mem_if.wr_write) & !host_mem_if.wr_waitrequest;

always_ff @(posedge clk) begin
    if (rst_local)
        burst_counter <= 'b0;
    else if (load_burst_counter)
        burst_counter <= asp_mem_if.wr_burstcount - 1'b1;
    else if (enable_burst_counter && (burst_counter != '0))
        burst_counter <= burst_counter - 1'b1;
end

//write-fence logic
// when we get a write-fence signal from the DMA block we need to issue a write-fence event
// in the wr_user field, and then send a write of the magic number as issued by the DMA block.
assign send_wr_fence = !(|irq_pending) & asp_mem_if.wr_write & 
                        wr_fence_flag & !send_magic_number_dly & 
                        !send_wr_fence_d & !host_mem_if.wr_waitrequest;
assign send_magic_number = !(|irq_pending) & !send_wr_fence & send_magic_number_dly & 
                            !host_mem_if.wr_waitrequest & asp_mem_if.wr_write;

always_ff @(posedge clk) begin
    if (rst_local)
        send_wr_fence_d <= 'b0;
    else
        send_wr_fence_d <= send_wr_fence;
end
always_ff @(posedge clk) begin
    if (rst_local)
        send_magic_number_dly <= 1'b0;
    else if (send_magic_number)
        send_magic_number_dly <= 1'b0;
    else if (send_wr_fence)
        send_magic_number_dly <= 1'b1;
end


endmodule : asp_host_mem_if_mux
