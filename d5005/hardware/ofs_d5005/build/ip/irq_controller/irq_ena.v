// Copyright 2020 Intel Corporation.
//
// THIS SOFTWARE MAY CONTAIN PREPRODUCTION CODE AND IS PROVIDED BY THE
// COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED
// WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
// MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
// DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR
// BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
// WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
// OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
// EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
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

