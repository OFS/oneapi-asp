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

module irq_ctrl
(
// Slave Inteface
   input            Clk_i,             // MSI-X structure slave
   input            Rstn_i,          
 
// IRQ interface               
   input   [31:0]   Irq_i,                           
 
// PCIe HIP interface
   output           Irq_o,
 
// Irq Bridge Interface
   input            IrqRead_i,          
   output  [31:0]   IrqReadData_o,
 
// Irq Mask
  input    [31:0]   MaskWritedata_i,
  input             MaskRead_i,
  input             MaskWrite_i,
  input    [3:0]    MaskByteenable_i,
  output   [31:0]   MaskReaddata_o,
  output            MaskWaitrequest_o
);
      
   wire    [31:0]   Irq_masked;

   assign Irq_o = |Irq_masked;

/// IRQ Bridge
irq_bridge irq_ports
(
    .clk(Clk_i),
    .read(IrqRead_i),
    .rst_n(Rstn_i),
    .readdata(IrqReadData_o),
    .irq_i(Irq_i)
);

/// IRQ Mask
irq_ena irq_enable_mask
(
    .clk(Clk_i),
    .resetn(Rstn_i),
    .irq(Irq_i),
    .slave_writedata(MaskWritedata_i),
    .slave_read(MaskRead_i),
    .slave_write(MaskWrite_i),
    .slave_byteenable(MaskByteenable_i),
    .slave_readdata(MaskReaddata_o),
    .slave_waitrequest(MaskWaitrequest_o),
    .irq_out(Irq_masked)
);

endmodule              
