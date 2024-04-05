// Copyright 2022 Intel Corporation
// SPDX-License-Identifier: MIT
//

`include "ofs_plat_if.vh"

/*
This is the top-level of the DMA controller.
- main interfaces are clk, reset, MMIO64 from host, 4xAVMM memory interfaces
- High-level description
    - Single dispatch/register/CSR module. Registers contain information for mmd describing
      what is instantiated (number of channels, more?)
    - generate loop for each instance of transfer channels
*/

module dma_top
import dma_pkg::*;
import ofs_asp_pkg::*;
(
    input clk,
    input reset,

    // MMIO64 master from host (AVMM)
    ofs_plat_avalon_mem_if.to_source mmio64_if,
    
    // host-memory writes (read from local memory, write to host memory)
    ofs_plat_avalon_mem_if.to_sink host_mem_wr_avmm_if [NUM_DMA_CHAN-1:0],
    ofs_plat_avalon_mem_if.to_sink local_mem_rd_avmm_if [NUM_DMA_CHAN-1:0],
    output logic dma_irq_fpga2host,
    output logic f2h_dma_wr_fence_flag,
    
    // host-memory reads (read from host memory, write to local memory)
    ofs_plat_avalon_mem_if.to_sink host_mem_rd_avmm_if [NUM_DMA_CHAN-1:0],
    ofs_plat_avalon_mem_if.to_sink local_mem_wr_avmm_if [NUM_DMA_CHAN-1:0],
    output logic dma_irq_host2fpga
);

dma_ctrl_intf 
    #(.DMA_DIR("H2F"),
      .SRC_ADDR_WIDTH(HOST_MEM_ADDR_WIDTH),
      .DST_ADDR_WIDTH(DEVICE_MEM_ADDR_WIDTH) )
    rd_ctrl [NUM_DMA_CHAN-1:0] ();
dma_ctrl_intf 
    #(.DMA_DIR("F2H"),
      .SRC_ADDR_WIDTH(DEVICE_MEM_ADDR_WIDTH),
      .DST_ADDR_WIDTH(HOST_MEM_ADDR_WIDTH) )
    wr_ctrl [NUM_DMA_CHAN-1:0] ();

logic host_mem_rd_xfer_done, host_mem_wr_xfer_done;

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
    
//dispatcher module for CSR of this DMA block
dma_dispatcher dma_dispatcher_inst (
    .clk,
    .reset (rst_local),
	.host_mem_rd_xfer_done,
	.host_mem_wr_xfer_done,
    //Avalon mem if - mmio64
    .mmio64_if,
    //dispatcher-to-controller if - host-to-FPGA (read)
    .rd_ctrl,
    //dispatcher-to-controller if - FPGA-to-host (write)
    .wr_ctrl
);

assign dma_irq_host2fpga = host_mem_rd_xfer_done;
assign dma_irq_fpga2host = host_mem_wr_xfer_done;
assign f2h_dma_wr_fence_flag = 'b0;

genvar d;
generate
	for (d=0; d < NUM_DMA_CHAN; d=d+1) begin : dma_channels

		//data transfer - host memory reads
		// read from host memory, write to local memory
		dma_data_transfer #(
			.SRC_RD_BURSTCOUNT_MAX  (HOST_MEM_RD_BURSTCOUNT_MAX),
			.DST_WR_BURSTCOUNT_MAX  (LOCAL_MEM_WR_BURSTCOUNT_MAX),
			.SRC_ADDR_WIDTH         (HOST_MEM_ADDR_WIDTH),
			.DST_ADDR_WIDTH         (DEVICE_MEM_ADDR_WIDTH),
			.XFER_LENGTH_WIDTH      (XFER_SIZE_WIDTH),
			.DIR_FPGA_TO_HOST       (1'b0),
			.DMA_CHANNEL_NUM        (d)
		) dma_data_transfer_host2fpga_inst (
			.clk,
			.reset (rst_local),
			//CSR interface to Dispatcher
			.disp_ctrl_if (rd_ctrl[d]),
			//all parallel transfers are done - issue host-mem-write 
			//(magic-number) for completion notification to mmd
			.all_transfers_complete (host_mem_rd_xfer_done),
			//data-source AVMM
			.src_avmm (host_mem_rd_avmm_if[d]),
			//data-destination AVMM
			.dst_avmm (local_mem_wr_avmm_if[d])
		);
		
		//data transfer - host memory writes
		// read from local memory, write to host memory
		dma_data_transfer #(
			.SRC_RD_BURSTCOUNT_MAX  (LOCAL_MEM_RD_BURSTCOUNT_MAX),
			.DST_WR_BURSTCOUNT_MAX  (HOST_MEM_WR_BURSTCOUNT_MAX),
			.SRC_ADDR_WIDTH         (DEVICE_MEM_ADDR_WIDTH),
			.DST_ADDR_WIDTH         (HOST_MEM_ADDR_WIDTH),
			.XFER_LENGTH_WIDTH      (XFER_SIZE_WIDTH),
			.DIR_FPGA_TO_HOST       (1'b1),
			.DMA_CHANNEL_NUM		(d)
		) dma_data_transfer_fpga2host_inst (
			.clk,
			.reset (rst_local),
			//CSR interface to Dispatcher
			.disp_ctrl_if (wr_ctrl[d]),
			//all parallel transfers are done - issue host-mem-write 
			//(magic-number) for completion notification to mmd
			.all_transfers_complete (host_mem_wr_xfer_done),
			//data-source AVMM
			.src_avmm (local_mem_rd_avmm_if[d]),
			//data-destination AVMM
			.dst_avmm (host_mem_wr_avmm_if[d])
		);
	end : dma_channels
endgenerate

endmodule : dma_top
