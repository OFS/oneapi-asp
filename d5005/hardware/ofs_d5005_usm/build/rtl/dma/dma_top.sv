// Copyright 2022 Intel Corporation
// SPDX-License-Identifier: MIT
//

`include "ofs_plat_if.vh"

/*
This is the top-level of the DMA controller.
- main interfaces are clk, reset, MMIO64 from host, 4xAVMM memory interfaces
*/

module dma_top (
    input clk,
    input reset,

    // MMIO64 master from host (AVMM)
    ofs_plat_avalon_mem_if.to_source mmio64_if,
    
    // host-memory writes (read from local memory, write to host memory)
    ofs_plat_avalon_mem_if.to_sink host_mem_wr_avmm_if,
    ofs_plat_avalon_mem_if.to_sink local_mem_rd_avmm_if,
    output logic dma_irq_fpga2host,
    output logic f2h_dma_wr_fence_flag,
    
    // host-memory reads (read from host memory, write to local memory)
    ofs_plat_avalon_mem_if.to_sink host_mem_rd_avmm_if,
    ofs_plat_avalon_mem_if.to_sink local_mem_wr_avmm_if,
    output logic dma_irq_host2fpga
);

import dma_pkg::*;

dma_ctrl_intf 
    #(.DMA_DIR("H2F"),
      .SRC_ADDR_WIDTH(HOST_MEM_ADDR_WIDTH),
      .DST_ADDR_WIDTH(DEVICE_MEM_ADDR_WIDTH) )
    rd_ctrl ();
dma_ctrl_intf 
    #(.DMA_DIR("F2H"),
      .SRC_ADDR_WIDTH(DEVICE_MEM_ADDR_WIDTH),
      .DST_ADDR_WIDTH(HOST_MEM_ADDR_WIDTH) )
    wr_ctrl ();

//pipeline and duplicate the reset signal
parameter RESET_PIPE_DEPTH = 4;
logic [RESET_PIPE_DEPTH-1:0] rst_pipe;
logic rst_local;
always_ff @(posedge clk) begin
    {rst_local,rst_pipe}  <= {rst_pipe[RESET_PIPE_DEPTH-1:0], 'b0};
    if (reset) begin
        rst_local <= '1;
        rst_pipe  <= '1;
    end
end
    
//dispatcher module for CSR of this DMA block
dma_dispatcher dma_dispatcher_inst (
    .clk,
    .reset (rst_local),
    //Avalon mem if - mmio64
    .mmio64_if,
    //dispatcher-to-controller if - host-to-FPGA (read)
    .rd_ctrl,
    //dispatcher-to-controller if - FPGA-to-host (write)
    .wr_ctrl
);

//data transfer - host memory reads
// read from host memory, write to local memory
dma_data_transfer #(
    .SRC_RD_BURSTCOUNT_MAX  (HOST_MEM_RD_BURSTCOUNT_MAX),
    .DST_WR_BURSTCOUNT_MAX  (LOCAL_MEM_WR_BURSTCOUNT_MAX),
    .SRC_ADDR_WIDTH         (HOST_MEM_ADDR_WIDTH),
    .DST_ADDR_WIDTH         (DEVICE_MEM_ADDR_WIDTH),
    .XFER_LENGTH_WIDTH      (XFER_SIZE_WIDTH),
    .DIR_FPGA_TO_HOST       (1'b0)
) dma_data_transfer_host2fpga_inst (
    .clk,
    .reset (rst_local),
    //CSR interface to Dispatcher
    .disp_ctrl_if (rd_ctrl),
    //data-source AVMM
    .src_avmm (host_mem_rd_avmm_if),
    //data-destination AVMM
    .dst_avmm (local_mem_wr_avmm_if)
);
assign dma_irq_host2fpga = rd_ctrl.irq_pulse;

//data transfer - host memory writes
// read from local memory, write to host memory
dma_data_transfer #(
    .SRC_RD_BURSTCOUNT_MAX  (LOCAL_MEM_RD_BURSTCOUNT_MAX),
    .DST_WR_BURSTCOUNT_MAX  (HOST_MEM_WR_BURSTCOUNT_MAX),
    .SRC_ADDR_WIDTH         (DEVICE_MEM_ADDR_WIDTH),
    .DST_ADDR_WIDTH         (HOST_MEM_ADDR_WIDTH),
    .XFER_LENGTH_WIDTH      (XFER_SIZE_WIDTH),
    .DIR_FPGA_TO_HOST       (1'b1)
) dma_data_transfer_fpga2host_inst (
    .clk,
    .reset (rst_local),
    //CSR interface to Dispatcher
    .disp_ctrl_if (wr_ctrl),
    //data-source AVMM
    .src_avmm (local_mem_rd_avmm_if),
    //data-destination AVMM
    .dst_avmm (host_mem_wr_avmm_if)
);
assign dma_irq_fpga2host = wr_ctrl.irq_pulse;
assign f2h_dma_wr_fence_flag = wr_ctrl.f2h_wr_fence_flag;

endmodule : dma_top
