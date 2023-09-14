// Copyright 2022 Intel Corporation
// SPDX-License-Identifier: MIT
//

module irq_bridge
(
    // master inputs:
    clk,
    read,
    rst_n,

    // master outputs:
    readdata,
    
    // interrupt request ports:
    irq_i
);
  input             clk;
  input             read;
  input             rst_n;
  output reg [31:0] readdata;
  input      [31:0] irq_i;
  
  always @(posedge clk) begin
    if (read) begin
      readdata <= irq_i;
    end
  end

endmodule
