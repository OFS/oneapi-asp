// Copyright 2022 Intel Corporation
// SPDX-License-Identifier: MIT

`include "ofs_plat_if.vh"
`include "opencl_bsp.vh"

module bsp_logic
import dc_bsp_pkg::*;
(
    // CCI-P Clocks and Resets
    input           logic             clk,
    input           logic             reset,
    input           logic             kernel_clk,
    input           logic             kernel_clk_reset,
    
    // Host memory (Avalon)
    ofs_plat_avalon_mem_rdwr_if.to_sink host_mem_if,

    // FPGA MMIO master (Avalon)
    ofs_plat_avalon_mem_if.to_source mmio64_if,

    // Local memory interface.
    ofs_plat_avalon_mem_if.to_slave local_mem[local_mem_cfg_pkg::LOCAL_MEM_NUM_BANKS],

   // OpenCL kernel signals
    opencl_kernel_control_intf.bsp opencl_kernel_control,
    kernel_mem_intf.bsp kernel_mem[dc_bsp_pkg::BSP_NUM_LOCAL_MEM_BANKS]
);

logic [OPENCL_MEMORY_BYTE_OFFSET-1:0] ddr4a_byte_address_bits;
logic [OPENCL_MEMORY_BYTE_OFFSET-1:0] ddr4b_byte_address_bits;
logic [OPENCL_MEMORY_BYTE_OFFSET-1:0] ddr4c_byte_address_bits;
logic [OPENCL_MEMORY_BYTE_OFFSET-1:0] ddr4d_byte_address_bits;
logic [17:0] avmm_mmio64_address;
logic wr_fence_flag,f2h_dma_wr_fence_flag;
logic [BSP_NUM_INTERRUPT_LINES-1:0] bsp_irq;
logic dma_irq_fpga2host, dma_irq_host2fpga;

ofs_plat_avalon_mem_rdwr_if
  #(
    `OFS_PLAT_AVALON_MEM_RDWR_IF_REPLICATE_PARAMS(host_mem_if)
    )
    bsp_mem_if();
    
// mmio64-if for the DMA controller
ofs_plat_avalon_mem_if
#(
    `OFS_PLAT_AVALON_MEM_IF_REPLICATE_PARAMS(mmio64_if)
) mmio64_if_dmac();

ofs_plat_avalon_mem_if 
  #(
    .ADDR_WIDTH(35),
    .DATA_WIDTH(512),
    .BURST_CNT_WIDTH(7)
  ) local_mem_rd_avmm_if();
  
ofs_plat_avalon_mem_if 
  #(
    .ADDR_WIDTH(35),
    .DATA_WIDTH(512),
    .BURST_CNT_WIDTH(7)
  ) local_mem_wr_avmm_if();
ofs_plat_avalon_mem_if 
  #(
    .ADDR_WIDTH(48),
    .DATA_WIDTH(512),
    .BURST_CNT_WIDTH(7)
  ) host_mem_rd_avmm_if();
ofs_plat_avalon_mem_if 
  #(
    .ADDR_WIDTH(48),
    .DATA_WIDTH(512),
    .BURST_CNT_WIDTH(7)
  ) host_mem_wr_avmm_if();

//for n-banks, need to tie off the unused banks
genvar m;
generate
    for (m = dc_bsp_pkg::BSP_NUM_LOCAL_MEM_BANKS; m < local_mem_cfg_pkg::LOCAL_MEM_NUM_BANKS; m=m+1) begin : tie_off_unused_local_mem
        always_comb begin
            //local_mem[m].waitrequest    =   input, no need to drive
            //local_mem[m].readdata       =   input, no need to drive
            //local_mem[m].readdatavalid  =   input, no need to drive
            local_mem[m].burstcount     = '0;
            local_mem[m].writedata      = '0;
            local_mem[m].address        = '0;
            local_mem[m].write          = '0;
            local_mem[m].read           = '0;
            local_mem[m].byteenable     = '0;
            local_mem[m].user           = '0;
        end //always_comb
    end //for
endgenerate

board board_inst (
    .clk_200_clk                        (clk),                          //   clk.clk
    .global_reset_reset                 (reset),                        //   global_reset.reset_n
    .kernel_clk_clk                     (),                             //   kernel_clk.clk (output from board.qsys)
    .kernel_clk_in_clk                  (kernel_clk),                   //   kernel_clk_in.clk (output from board.qsys)

    .kernel_cra_waitrequest             (opencl_kernel_control.kernel_cra_waitrequest),                    //   kernel_cra.waitrequest
    .kernel_cra_readdata                (opencl_kernel_control.kernel_cra_readdata),                       //             .readdata
    .kernel_cra_readdatavalid           (opencl_kernel_control.kernel_cra_readdatavalid),                  //             .readdatavalid
    .kernel_cra_burstcount              (opencl_kernel_control.kernel_cra_burstcount),                     //             .burstcount
    .kernel_cra_writedata               (opencl_kernel_control.kernel_cra_writedata),                      //             .writedata
    .kernel_cra_address                 (opencl_kernel_control.kernel_cra_address),                        //             .address
    .kernel_cra_write                   (opencl_kernel_control.kernel_cra_write),                          //             .write
    .kernel_cra_read                    (opencl_kernel_control.kernel_cra_read),                           //             .read
    .kernel_cra_byteenable              (opencl_kernel_control.kernel_cra_byteenable),                     //             .byteenable
    .kernel_cra_debugaccess             (opencl_kernel_control.kernel_cra_debugaccess),                    //             .debugaccess
    .kernel_irq_irq                     (opencl_kernel_control.kernel_irq),                                //   kernel_irq.irq
    .kernel_reset_reset_n               (opencl_kernel_control.kernel_reset_n),                            // kernel_reset.reset_n
    
    `ifdef PAC_BSP_ENABLE_DDR4_BANK1
        .emif_ddr4a_clk_clk(local_mem[0].clk),
        .emif_ddr4a_waitrequest     (local_mem[0].waitrequest),
        .emif_ddr4a_readdata        (local_mem[0].readdata),
        .emif_ddr4a_readdatavalid   (local_mem[0].readdatavalid),
        .emif_ddr4a_burstcount      (local_mem[0].burstcount),
        .emif_ddr4a_writedata       (local_mem[0].writedata),
        .emif_ddr4a_address         ({local_mem[0].address, ddr4a_byte_address_bits}),
        .emif_ddr4a_write           (local_mem[0].write),
        .emif_ddr4a_read            (local_mem[0].read),
        .emif_ddr4a_byteenable      (local_mem[0].byteenable),
        .emif_ddr4a_debugaccess     (),
        .kernel_ddr4a_waitrequest   (kernel_mem[0].waitrequest),
        .kernel_ddr4a_readdata      (kernel_mem[0].readdata),
        .kernel_ddr4a_readdatavalid (kernel_mem[0].readdatavalid),
        .kernel_ddr4a_burstcount    (kernel_mem[0].burstcount),
        .kernel_ddr4a_writedata     (kernel_mem[0].writedata),
        .kernel_ddr4a_address       (kernel_mem[0].address),
        .kernel_ddr4a_write         (kernel_mem[0].write),
        .kernel_ddr4a_read          (kernel_mem[0].read),
        .kernel_ddr4a_byteenable    (kernel_mem[0].byteenable),
    `endif
    `ifdef PAC_BSP_ENABLE_DDR4_BANK2
        .emif_ddr4b_clk_clk         (local_mem[1].clk),
        .emif_ddr4b_waitrequest     (local_mem[1].waitrequest),
        .emif_ddr4b_readdata        (local_mem[1].readdata),
        .emif_ddr4b_readdatavalid   (local_mem[1].readdatavalid),
        .emif_ddr4b_burstcount      (local_mem[1].burstcount),
        .emif_ddr4b_writedata       (local_mem[1].writedata),
        .emif_ddr4b_write           (local_mem[1].write),
        .emif_ddr4b_read            (local_mem[1].read),
        .emif_ddr4b_byteenable      (local_mem[1].byteenable),
        .emif_ddr4b_address         ({local_mem[1].address, ddr4b_byte_address_bits}),
        .emif_ddr4b_debugaccess     (),
        .kernel_ddr4b_waitrequest   (kernel_mem[1].waitrequest),
        .kernel_ddr4b_readdata      (kernel_mem[1].readdata),
        .kernel_ddr4b_readdatavalid (kernel_mem[1].readdatavalid),
        .kernel_ddr4b_burstcount    (kernel_mem[1].burstcount),
        .kernel_ddr4b_writedata     (kernel_mem[1].writedata),
        .kernel_ddr4b_address       (kernel_mem[1].address),
        .kernel_ddr4b_write         (kernel_mem[1].write),
        .kernel_ddr4b_read          (kernel_mem[1].read),
        .kernel_ddr4b_byteenable    (kernel_mem[1].byteenable),
    `endif
    `ifdef PAC_BSP_ENABLE_DDR4_BANK3
        .emif_ddr4c_clk_clk         (local_mem[2].clk),
        .emif_ddr4c_waitrequest     (local_mem[2].waitrequest),
        .emif_ddr4c_readdata        (local_mem[2].readdata),
        .emif_ddr4c_readdatavalid   (local_mem[2].readdatavalid),
        .emif_ddr4c_burstcount      (local_mem[2].burstcount),
        .emif_ddr4c_writedata       (local_mem[2].writedata),
        .emif_ddr4c_write           (local_mem[2].write),
        .emif_ddr4c_read            (local_mem[2].read),
        .emif_ddr4c_byteenable      (local_mem[2].byteenable),
        .emif_ddr4c_address         ({local_mem[2].address, ddr4c_byte_address_bits}),
        .emif_ddr4c_debugaccess     (),
        .kernel_ddr4c_waitrequest   (kernel_mem[2].waitrequest),
        .kernel_ddr4c_readdata      (kernel_mem[2].readdata),
        .kernel_ddr4c_readdatavalid (kernel_mem[2].readdatavalid),
        .kernel_ddr4c_burstcount    (kernel_mem[2].burstcount),
        .kernel_ddr4c_writedata     (kernel_mem[2].writedata),
        .kernel_ddr4c_address       (kernel_mem[2].address),
        .kernel_ddr4c_write         (kernel_mem[2].write),
        .kernel_ddr4c_read          (kernel_mem[2].read),
        .kernel_ddr4c_byteenable    (kernel_mem[2].byteenable),
    `endif
    `ifdef PAC_BSP_ENABLE_DDR4_BANK4
        .emif_ddr4d_clk_clk         (local_mem[3].clk),
        .emif_ddr4d_waitrequest     (local_mem[3].waitrequest),
        .emif_ddr4d_readdata        (local_mem[3].readdata),
        .emif_ddr4d_readdatavalid   (local_mem[3].readdatavalid),
        .emif_ddr4d_burstcount      (local_mem[3].burstcount),
        .emif_ddr4d_writedata       (local_mem[3].writedata),
        .emif_ddr4d_write           (local_mem[3].write),
        .emif_ddr4d_read            (local_mem[3].read),
        .emif_ddr4d_byteenable      (local_mem[3].byteenable),
        .emif_ddr4d_address         ({local_mem[3].address, ddr4d_byte_address_bits}),
        .emif_ddr4d_debugaccess     (),
        .kernel_ddr4d_waitrequest   (kernel_mem[3].waitrequest),
        .kernel_ddr4d_readdata      (kernel_mem[3].readdata),
        .kernel_ddr4d_readdatavalid (kernel_mem[3].readdatavalid),
        .kernel_ddr4d_burstcount    (kernel_mem[3].burstcount),
        .kernel_ddr4d_writedata     (kernel_mem[3].writedata),
        .kernel_ddr4d_address       (kernel_mem[3].address),
        .kernel_ddr4d_write         (kernel_mem[3].write),
        .kernel_ddr4d_read          (kernel_mem[3].read),
        .kernel_ddr4d_byteenable    (kernel_mem[3].byteenable),
    `endif

    .host_kernel_irq_irq                 (/*this port isn't used for kernel IRQ*/),
    
    .avmm_mmio64_waitrequest             (mmio64_if.waitrequest),
    .avmm_mmio64_readdata                (mmio64_if.readdata),
    .avmm_mmio64_readdatavalid           (mmio64_if.readdatavalid),
    .avmm_mmio64_burstcount              (mmio64_if.burstcount),
    .avmm_mmio64_writedata               (mmio64_if.writedata),
    .avmm_mmio64_address                 , //manipulated below
    .avmm_mmio64_write                   (mmio64_if.write),
    .avmm_mmio64_read                    (mmio64_if.read),
    .avmm_mmio64_byteenable              (mmio64_if.byteenable),
    .avmm_mmio64_debugaccess             (),
    //mmio64 signals for DMA controller
    .dma_csr_mmio64_waitrequest             (mmio64_if_dmac.waitrequest),
    .dma_csr_mmio64_readdata                (mmio64_if_dmac.readdata),
    .dma_csr_mmio64_readdatavalid           (mmio64_if_dmac.readdatavalid),
    .dma_csr_mmio64_burstcount              (mmio64_if_dmac.burstcount),
    .dma_csr_mmio64_writedata               (mmio64_if_dmac.writedata),
    .dma_csr_mmio64_address                 (mmio64_if_dmac.address),
    .dma_csr_mmio64_write                   (mmio64_if_dmac.write),
    .dma_csr_mmio64_read                    (mmio64_if_dmac.read),
    .dma_csr_mmio64_byteenable              (mmio64_if_dmac.byteenable),
    .dma_csr_mmio64_debugaccess             (),
    //local-memory DMA reads
    .dma_localmem_rd_waitrequest             (local_mem_rd_avmm_if.waitrequest),
    .dma_localmem_rd_readdata                (local_mem_rd_avmm_if.readdata),
    .dma_localmem_rd_readdatavalid           (local_mem_rd_avmm_if.readdatavalid),
    .dma_localmem_rd_burstcount              (local_mem_rd_avmm_if.burstcount),
    .dma_localmem_rd_writedata               (local_mem_rd_avmm_if.writedata),
    .dma_localmem_rd_address                 (local_mem_rd_avmm_if.address),
    .dma_localmem_rd_write                   (local_mem_rd_avmm_if.write),
    .dma_localmem_rd_read                    (local_mem_rd_avmm_if.read),
    .dma_localmem_rd_byteenable              (local_mem_rd_avmm_if.byteenable),
    .dma_localmem_rd_debugaccess             (),
    //local-memory DMA writes
    .dma_localmem_wr_waitrequest             (local_mem_wr_avmm_if.waitrequest),
    .dma_localmem_wr_readdata                (local_mem_wr_avmm_if.readdata),
    .dma_localmem_wr_readdatavalid           (local_mem_wr_avmm_if.readdatavalid),
    .dma_localmem_wr_burstcount              (local_mem_wr_avmm_if.burstcount),
    .dma_localmem_wr_writedata               (local_mem_wr_avmm_if.writedata),
    .dma_localmem_wr_address                 (local_mem_wr_avmm_if.address),
    .dma_localmem_wr_write                   (local_mem_wr_avmm_if.write),
    .dma_localmem_wr_read                    (local_mem_wr_avmm_if.read),
    .dma_localmem_wr_byteenable              (local_mem_wr_avmm_if.byteenable),
    .dma_localmem_wr_debugaccess             ()
);
//Create the mmio64-address based on:
//  [17:3] = mmio64_if.address let-shifted by 3
//  [2]    = (mmio64_if.byteenable == 8'hF0)
//  [1:0]  = 2'b0
always_comb begin
    avmm_mmio64_address [17:3]    = mmio64_if.address;
    avmm_mmio64_address [2]       = (mmio64_if.byteenable == 8'hF0) ? 1'b1 : 1'b0;
    avmm_mmio64_address [1:0]     = 2'b0;
end

//set unused interrupt lines to 0
genvar i;
generate
    for (i = BSP_AVMM_NUM_IRQ_USED; i < BSP_NUM_INTERRUPT_LINES ; i = i + 1) begin
        assign bsp_irq[i] = 1'b0;
    end
endgenerate

bsp_host_mem_if_mux bsp_host_mem_if_mux_inst (
    .clk,
    .reset,
    .bsp_irq,
    .wr_fence_flag,
    .bsp_mem_if,
    .host_mem_if
);

//combine separate avmm interfaces into a single rd/wr interface
always_comb begin
    host_mem_wr_avmm_if.waitrequest     = bsp_mem_if.wr_waitrequest;
    bsp_mem_if.wr_writedata             = host_mem_wr_avmm_if.writedata;
    bsp_mem_if.wr_write                 = host_mem_wr_avmm_if.write;
    bsp_mem_if.wr_address               = 'b0;
    bsp_mem_if.wr_address               = host_mem_wr_avmm_if.address >> 6;
    bsp_mem_if.wr_burstcount            = host_mem_wr_avmm_if.burstcount;
    bsp_mem_if.wr_byteenable            = host_mem_wr_avmm_if.byteenable;
    
    host_mem_rd_avmm_if.waitrequest     = bsp_mem_if.rd_waitrequest;
    host_mem_rd_avmm_if.readdata        = bsp_mem_if.rd_readdata;
    host_mem_rd_avmm_if.readdatavalid   = bsp_mem_if.rd_readdatavalid;
    bsp_mem_if.rd_address               = 'b0;
    bsp_mem_if.rd_address               = host_mem_rd_avmm_if.address >> 6;
    bsp_mem_if.rd_burstcount            = host_mem_rd_avmm_if.burstcount;
    bsp_mem_if.rd_read                  = host_mem_rd_avmm_if.read;
    bsp_mem_if.rd_byteenable            = host_mem_rd_avmm_if.byteenable;
end

// DMA-top module
dma_top dma_controller_inst (
    .clk,
    .reset,

    // MMIO64 master from host (AVMM)
    .mmio64_if (mmio64_if_dmac),
    
    // host-memory writes (read from local memory, write to host memory)
    .host_mem_wr_avmm_if,
    .local_mem_rd_avmm_if,
    .dma_irq_fpga2host,
    .f2h_dma_wr_fence_flag,
    
    // host-memory reads (read from host memory, write to local memory)
    .host_mem_rd_avmm_if,
    .local_mem_wr_avmm_if,
    .dma_irq_host2fpga
);

`ifdef USE_KERNEL_IRQ
    logic [2:0] kernel_irq_sync;
    //sync the kernel interrupt into the host-clock domain
    always_ff @(posedge clk) begin
        kernel_irq_sync <= {kernel_irq_sync[1:0], opencl_kernel_control.kernel_irq};
        if (reset) kernel_irq_sync <= '0;
    end
    assign bsp_irq[BSP_KERNEL_IRQ_BIT] = kernel_irq_sync[2];
`else
    assign bsp_irq[BSP_KERNEL_IRQ_BIT] = 'b0;
`endif
`ifdef USE_H2F_IRQ
    assign bsp_irq[BSP_DMA_0_IRQ_BIT] = dma_irq_host2fpga;
`else
    assign bsp_irq[BSP_DMA_0_IRQ_BIT] = 'b0;
`endif
`ifdef USE_F2H_IRQ
    assign bsp_irq[BSP_DMA_1_IRQ_BIT] = dma_irq_fpga2host;
`else
assign bsp_irq[BSP_DMA_1_IRQ_BIT] = 'b0;
`endif

`ifdef USE_WR_FENCE_FLAG
    assign wr_fence_flag = f2h_dma_wr_fence_flag;
`else
    assign wr_fence_flag = 'b0;
`endif

endmodule : bsp_logic
