// Copyright 2022 Intel Corporation
// SPDX-License-Identifier: MIT

`include "ofs_plat_if.vh"
`include "opencl_bsp.vh"

module bsp_logic
import dc_bsp_pkg::*;
(
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
    
`ifdef INCLUDE_UDP_OFFLOAD_ENGINE
    ofs_plat_avalon_mem_if.to_sink uoe_csr_avmm,
`endif

   // OpenCL kernel signals
    opencl_kernel_control_intf.bsp opencl_kernel_control,
    kernel_mem_intf.bsp kernel_mem[dc_bsp_pkg::BSP_NUM_LOCAL_MEM_BANKS]
);

logic [OPENCL_MEMORY_BYTE_OFFSET-1:0] ddr0_byte_address_bits;
logic [OPENCL_MEMORY_BYTE_OFFSET-1:0] ddr1_byte_address_bits;
logic [OPENCL_MEMORY_BYTE_OFFSET-1:0] ddr2_byte_address_bits;
logic [OPENCL_MEMORY_BYTE_OFFSET-1:0] ddr3_byte_address_bits;
logic [MMIO64_AVMM_ADDR_WIDTH-1:0] avmm_mmio64_address;
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
    .ADDR_WIDTH(dma_pkg::DEVICE_MEM_ADDR_WIDTH),
    .DATA_WIDTH(dma_pkg::AVMM_DATA_WIDTH),
    .BURST_CNT_WIDTH(dma_pkg::AVMM_BURSTCOUNT_BITS)
  ) local_mem_rd_avmm_if();
  
ofs_plat_avalon_mem_if 
  #(
    .ADDR_WIDTH(dma_pkg::DEVICE_MEM_ADDR_WIDTH),
    .DATA_WIDTH(dma_pkg::AVMM_DATA_WIDTH),
    .BURST_CNT_WIDTH(dma_pkg::AVMM_BURSTCOUNT_BITS)
  ) local_mem_wr_avmm_if();
ofs_plat_avalon_mem_if 
  #(
    .ADDR_WIDTH(dma_pkg::HOST_MEM_ADDR_WIDTH),
    .DATA_WIDTH(dma_pkg::AVMM_DATA_WIDTH),
    .BURST_CNT_WIDTH(dma_pkg::AVMM_BURSTCOUNT_BITS)
  ) host_mem_rd_avmm_if();
ofs_plat_avalon_mem_if 
  #(
    .ADDR_WIDTH(dma_pkg::HOST_MEM_ADDR_WIDTH),
    .DATA_WIDTH(dma_pkg::AVMM_DATA_WIDTH),
    .BURST_CNT_WIDTH(dma_pkg::AVMM_BURSTCOUNT_BITS)
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
        .emif_ddr0_clk_clk         (local_mem[0].clk),
        .emif_ddr0_waitrequest     (local_mem[0].waitrequest),
        .emif_ddr0_readdata        (local_mem[0].readdata),
        .emif_ddr0_readdatavalid   (local_mem[0].readdatavalid),
        .emif_ddr0_burstcount      (local_mem[0].burstcount),
        .emif_ddr0_writedata       (local_mem[0].writedata),
        .emif_ddr0_address         ({local_mem[0].address, ddr0_byte_address_bits}),
        .emif_ddr0_write           (local_mem[0].write),
        .emif_ddr0_read            (local_mem[0].read),
        .emif_ddr0_byteenable      (local_mem[0].byteenable),
        .emif_ddr0_debugaccess     (),
        .kernel_ddr0_waitrequest   (kernel_mem[0].waitrequest),
        .kernel_ddr0_readdata      (kernel_mem[0].readdata),
        .kernel_ddr0_readdatavalid (kernel_mem[0].readdatavalid),
        .kernel_ddr0_burstcount    (kernel_mem[0].burstcount),
        .kernel_ddr0_writedata     (kernel_mem[0].writedata),
        .kernel_ddr0_address       (kernel_mem[0].address),
        .kernel_ddr0_write         (kernel_mem[0].write),
        .kernel_ddr0_read          (kernel_mem[0].read),
        .kernel_ddr0_byteenable    (kernel_mem[0].byteenable),
    `endif
    `ifdef PAC_BSP_ENABLE_DDR4_BANK2
        .emif_ddr1_clk_clk         (local_mem[1].clk),
        .emif_ddr1_waitrequest     (local_mem[1].waitrequest),
        .emif_ddr1_readdata        (local_mem[1].readdata),
        .emif_ddr1_readdatavalid   (local_mem[1].readdatavalid),
        .emif_ddr1_burstcount      (local_mem[1].burstcount),
        .emif_ddr1_writedata       (local_mem[1].writedata),
        .emif_ddr1_write           (local_mem[1].write),
        .emif_ddr1_read            (local_mem[1].read),
        .emif_ddr1_byteenable      (local_mem[1].byteenable),
        .emif_ddr1_address         ({local_mem[1].address, ddr1_byte_address_bits}),
        .emif_ddr1_debugaccess     (),
        .kernel_ddr1_waitrequest   (kernel_mem[1].waitrequest),
        .kernel_ddr1_readdata      (kernel_mem[1].readdata),
        .kernel_ddr1_readdatavalid (kernel_mem[1].readdatavalid),
        .kernel_ddr1_burstcount    (kernel_mem[1].burstcount),
        .kernel_ddr1_writedata     (kernel_mem[1].writedata),
        .kernel_ddr1_address       (kernel_mem[1].address),
        .kernel_ddr1_write         (kernel_mem[1].write),
        .kernel_ddr1_read          (kernel_mem[1].read),
        .kernel_ddr1_byteenable    (kernel_mem[1].byteenable),
    `endif
    `ifdef PAC_BSP_ENABLE_DDR4_BANK3
        .emif_ddr2_clk_clk         (local_mem[2].clk),
        .emif_ddr2_waitrequest     (local_mem[2].waitrequest),
        .emif_ddr2_readdata        (local_mem[2].readdata),
        .emif_ddr2_readdatavalid   (local_mem[2].readdatavalid),
        .emif_ddr2_burstcount      (local_mem[2].burstcount),
        .emif_ddr2_writedata       (local_mem[2].writedata),
        .emif_ddr2_write           (local_mem[2].write),
        .emif_ddr2_read            (local_mem[2].read),
        .emif_ddr2_byteenable      (local_mem[2].byteenable),
        .emif_ddr2_address         ({local_mem[2].address, ddr2_byte_address_bits}),
        .emif_ddr2_debugaccess     (),
        .kernel_ddr2_waitrequest   (kernel_mem[2].waitrequest),
        .kernel_ddr2_readdata      (kernel_mem[2].readdata),
        .kernel_ddr2_readdatavalid (kernel_mem[2].readdatavalid),
        .kernel_ddr2_burstcount    (kernel_mem[2].burstcount),
        .kernel_ddr2_writedata     (kernel_mem[2].writedata),
        .kernel_ddr2_address       (kernel_mem[2].address),
        .kernel_ddr2_write         (kernel_mem[2].write),
        .kernel_ddr2_read          (kernel_mem[2].read),
        .kernel_ddr2_byteenable    (kernel_mem[2].byteenable),
    `endif
    `ifdef PAC_BSP_ENABLE_DDR4_BANK4
        .emif_ddr3_clk_clk         (local_mem[3].clk),
        .emif_ddr3_waitrequest     (local_mem[3].waitrequest),
        .emif_ddr3_readdata        (local_mem[3].readdata),
        .emif_ddr3_readdatavalid   (local_mem[3].readdatavalid),
        .emif_ddr3_burstcount      (local_mem[3].burstcount),
        .emif_ddr3_writedata       (local_mem[3].writedata),
        .emif_ddr3_write           (local_mem[3].write),
        .emif_ddr3_read            (local_mem[3].read),
        .emif_ddr3_byteenable      (local_mem[3].byteenable),
        .emif_ddr3_address         ({local_mem[3].address, ddr3_byte_address_bits}),
        .emif_ddr3_debugaccess     (),
        .kernel_ddr3_waitrequest   (kernel_mem[3].waitrequest),
        .kernel_ddr3_readdata      (kernel_mem[3].readdata),
        .kernel_ddr3_readdatavalid (kernel_mem[3].readdatavalid),
        .kernel_ddr3_burstcount    (kernel_mem[3].burstcount),
        .kernel_ddr3_writedata     (kernel_mem[3].writedata),
        .kernel_ddr3_address       (kernel_mem[3].address),
        .kernel_ddr3_write         (kernel_mem[3].write),
        .kernel_ddr3_read          (kernel_mem[3].read),
        .kernel_ddr3_byteenable    (kernel_mem[3].byteenable),
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
`ifdef INCLUDE_UDP_OFFLOAD_ENGINE
    .uoe_csr_mmio64_waitrequest             (uoe_csr_avmm.waitrequest),
    .uoe_csr_mmio64_readdata                (uoe_csr_avmm.readdata),
    .uoe_csr_mmio64_readdatavalid           (uoe_csr_avmm.readdatavalid),
    .uoe_csr_mmio64_burstcount              (uoe_csr_avmm.burstcount),
    .uoe_csr_mmio64_writedata               (uoe_csr_avmm.writedata),
    .uoe_csr_mmio64_address                 (uoe_csr_avmm.address),
    .uoe_csr_mmio64_write                   (uoe_csr_avmm.write),
    .uoe_csr_mmio64_read                    (uoe_csr_avmm.read),
    .uoe_csr_mmio64_byteenable              (uoe_csr_avmm.byteenable),
    .uoe_csr_mmio64_debugaccess             (),
`endif
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
//  [17:3] = mmio64_if.address left-shifted by 3
//  [2]    = (mmio64_if.byteenable == 8'hF0)
//  [1:0]  = 2'b0
always_comb begin
    avmm_mmio64_address [MMIO64_AVMM_ADDR_WIDTH-1:3]    = mmio64_if.address;
    avmm_mmio64_address [2]       = (mmio64_if.byteenable == 8'hF0) ? 1'b1 : 1'b0;
    avmm_mmio64_address [1:0]     = 2'b0;
end

genvar lm;
generate
    for (lm=0;lm<dc_bsp_pkg::BSP_NUM_LOCAL_MEM_BANKS;lm++) begin : local_mem_stuff
        assign local_mem[lm].user = 'b0;
        
        `ifdef USE_WRITEACKS_FOR_KERNELSYSTEM_LOCALMEMORY_ACCESSES
            // local-memory/DDR write-ack tracking
            avmm_wr_ack_gen avmm_wr_ack_gen_inst (
                //AVMM from kernel-system to mux/emif
                .kernel_avmm_clk        (kernel_clk),
                .kernel_avmm_reset      (kernel_clk_reset),
                .kernel_avmm_waitreq    (kernel_mem[lm].waitrequest),
                .kernel_avmm_wr         (kernel_mem[lm].write),
                .kernel_avmm_burstcnt   (kernel_mem[lm].burstcount),
                .kernel_avmm_address    (kernel_mem[lm].address>>OPENCL_MEMORY_BYTE_OFFSET),
                .kernel_avmm_wr_ack     (kernel_mem[lm].writeack),
                
                //AVMM channel up to PIM (AVMM-AXI conversion with write-ack)
                .emif_avmm_clk          (local_mem[lm].clk),
                .emif_avmm_reset        (!local_mem[lm].reset_n),
                .emif_avmm_waitreq      (local_mem[lm].waitrequest),
                .emif_avmm_wr           (local_mem[lm].write),
                .emif_avmm_burstcnt     (local_mem[lm].burstcount),
                .emif_avmm_address      (local_mem[lm].address),
                .emif_avmm_wr_ack       (local_mem[lm].writeresponsevalid)
            );
        `else // not USE_WRITEACKS_FOR_KERNELSYSTEM_LOCALMEMORY_ACCESSES
            assign kernel_mem[lm].writeack = 'b0;
        `endif
    end //for
endgenerate

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
