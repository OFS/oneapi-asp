// Copyright 2022 Intel Corporation
// SPDX-License-Identifier: MIT
//

module irq_ena
(
   input         clk,
   input         resetn,
   input  [31:0] irq,

   input  [31:0] slave_writedata,
   input  	     slave_read,
   input         slave_write,
   input  [3:0]  slave_byteenable,
   output [31:0] slave_readdata,
   output        slave_waitrequest,

   output [31:0] irq_out
);

reg [31:0] ena_state;

initial   
    ena_state <= 32'h0000;

always@(posedge clk or negedge resetn)
  if (!resetn)
    ena_state <= 32'h0000;
  else if (slave_write)
    ena_state <= slave_writedata;

assign irq_out = irq & ena_state;

assign slave_waitrequest = 1'b0;
assign slave_readdata = ena_state;
  
endmodule

