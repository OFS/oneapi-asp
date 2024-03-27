// Copyright 2022 Intel Corporation
// SPDX-License-Identifier: MIT

`include "ofs_plat_if.vh"
`include "ofs_asp.vh"

module asp_logic
import ofs_asp_pkg::*;
(
    input           logic             clk,
    input           logic             reset,
    input           logic             kernel_clk,
    input           logic             kernel_clk_reset,
    
    // Host memory (Avalon)
    ofs_plat_avalon_mem_rdwr_if.to_sink host_mem_if [NUM_DMA_CHAN-1:0],

    // FPGA MMIO master (Avalon)
    ofs_plat_avalon_mem_if.to_source mmio64_if,

    // Local memory interface.
    ofs_plat_avalon_mem_if.to_slave local_mem[ASP_LOCALMEM_NUM_CHANNELS],
    
    `ifdef INCLUDE_IO_PIPES
        ofs_plat_avalon_mem_if.to_sink uoe_csr_avmm,
    `endif

   // kernel signals
    kernel_control_intf.asp kernel_control,
    kernel_mem_intf.asp kernel_mem[ASP_LOCALMEM_NUM_CHANNELS]
);

logic [KERNELSYSTEM_MEMORY_WORD_BYTE_OFFSET-1:0] ddr4_byte_address_bits [ASP_LOCALMEM_NUM_CHANNELS];
logic [ASP_MMIO_QSYS_ADDR_WIDTH-1:0] avmm_mmio64_address;
logic wr_fence_flag;
logic f2h_dma_wr_fence_flag;
logic [ASP_NUM_INTERRUPT_LINES-1:0] asp_irq;
logic dma_irq_fpga2host;
logic dma_irq_host2fpga;

ofs_plat_avalon_mem_rdwr_if
  #(
    `OFS_PLAT_AVALON_MEM_RDWR_IF_REPLICATE_PARAMS(host_mem_if[0])
    )
    dma2mux_host_mem_if [NUM_DMA_CHAN-1:0] ();
    
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
  ) dma_local_mem_rd_avmm_if [NUM_DMA_CHAN-1:0] ();
  
ofs_plat_avalon_mem_if 
  #(
    .ADDR_WIDTH(dma_pkg::DEVICE_MEM_ADDR_WIDTH),
    .DATA_WIDTH(dma_pkg::AVMM_DATA_WIDTH),
    .BURST_CNT_WIDTH(dma_pkg::AVMM_BURSTCOUNT_BITS)
  ) dma_local_mem_wr_avmm_if [NUM_DMA_CHAN-1:0] ();
ofs_plat_avalon_mem_if 
  #(
    .ADDR_WIDTH(dma_pkg::HOST_MEM_ADDR_WIDTH),
    .DATA_WIDTH(dma_pkg::AVMM_DATA_WIDTH),
    .BURST_CNT_WIDTH(dma_pkg::AVMM_BURSTCOUNT_BITS)
  ) dma_host_mem_rd_avmm_if [NUM_DMA_CHAN-1:0] ();
ofs_plat_avalon_mem_if 
  #(
    .ADDR_WIDTH(dma_pkg::HOST_MEM_ADDR_WIDTH),
    .DATA_WIDTH(dma_pkg::AVMM_DATA_WIDTH),
    .BURST_CNT_WIDTH(dma_pkg::AVMM_BURSTCOUNT_BITS)
  ) dma_host_mem_wr_avmm_if [NUM_DMA_CHAN-1:0] ();

board board_inst (
    .clk_200_clk                        (clk),                          //   clk.clk
    .global_reset_reset                 (reset),                        //   global_reset.reset_n
    .kernel_clk_clk                     (),                             //   kernel_clk.clk (output from board.qsys)
    .kernel_clk_in_clk                  (kernel_clk),                   //   kernel_clk_in.clk (output from board.qsys)

    .kernel_cra_waitrequest             (kernel_control.kernel_cra_waitrequest),    //   kernel_cra.waitrequest
    .kernel_cra_readdata                (kernel_control.kernel_cra_readdata),       //             .readdata
    .kernel_cra_readdatavalid           (kernel_control.kernel_cra_readdatavalid),  //             .readdatavalid
    .kernel_cra_burstcount              (kernel_control.kernel_cra_burstcount),     //             .burstcount
    .kernel_cra_writedata               (kernel_control.kernel_cra_writedata),      //             .writedata
    .kernel_cra_address                 (kernel_control.kernel_cra_address),        //             .address
    .kernel_cra_write                   (kernel_control.kernel_cra_write),          //             .write
    .kernel_cra_read                    (kernel_control.kernel_cra_read),           //             .read
    .kernel_cra_byteenable              (kernel_control.kernel_cra_byteenable),     //             .byteenable
    .kernel_cra_debugaccess             (kernel_control.kernel_cra_debugaccess),    //             .debugaccess
    .kernel_irq_irq                     (kernel_control.kernel_irq),                //   kernel_irq.irq
    .kernel_reset_reset_n               (kernel_control.kernel_reset_n),            // kernel_reset.reset_n
    
    `ifdef ASP_ENABLE_DDR4_BANK_0
        .emif_ddr0_clk_clk         (local_mem[0].clk),
        .emif_ddr0_waitrequest     (local_mem[0].waitrequest),
        .emif_ddr0_readdata        (local_mem[0].readdata),
        .emif_ddr0_readdatavalid   (local_mem[0].readdatavalid),
        .emif_ddr0_burstcount      (local_mem[0].burstcount),
        .emif_ddr0_writedata       (local_mem[0].writedata),
        .emif_ddr0_address         ({local_mem[0].address, ddr4_byte_address_bits[0]}),
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
    `endif //ASP_ENABLE_DDR4_BANK_0
    `ifdef ASP_ENABLE_DDR4_BANK_1
        .emif_ddr1_clk_clk         (local_mem[1].clk),
        .emif_ddr1_waitrequest     (local_mem[1].waitrequest),
        .emif_ddr1_readdata        (local_mem[1].readdata),
        .emif_ddr1_readdatavalid   (local_mem[1].readdatavalid),
        .emif_ddr1_burstcount      (local_mem[1].burstcount),
        .emif_ddr1_writedata       (local_mem[1].writedata),
        .emif_ddr1_write           (local_mem[1].write),
        .emif_ddr1_read            (local_mem[1].read),
        .emif_ddr1_byteenable      (local_mem[1].byteenable),
        .emif_ddr1_address         ({local_mem[1].address, ddr4_byte_address_bits[1]}),
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
    `endif //ASP_ENABLE_DDR4_BANK_1
    `ifdef ASP_ENABLE_DDR4_BANK_2
        .emif_ddr2_clk_clk         (local_mem[2].clk),
        .emif_ddr2_waitrequest     (local_mem[2].waitrequest),
        .emif_ddr2_readdata        (local_mem[2].readdata),
        .emif_ddr2_readdatavalid   (local_mem[2].readdatavalid),
        .emif_ddr2_burstcount      (local_mem[2].burstcount),
        .emif_ddr2_writedata       (local_mem[2].writedata),
        .emif_ddr2_write           (local_mem[2].write),
        .emif_ddr2_read            (local_mem[2].read),
        .emif_ddr2_byteenable      (local_mem[2].byteenable),
        .emif_ddr2_address         ({local_mem[2].address, ddr4_byte_address_bits[2]}),
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
    `endif //ASP_ENABLE_DDR4_BANK_2
    `ifdef ASP_ENABLE_DDR4_BANK_3
        .emif_ddr3_clk_clk         (local_mem[3].clk),
        .emif_ddr3_waitrequest     (local_mem[3].waitrequest),
        .emif_ddr3_readdata        (local_mem[3].readdata),
        .emif_ddr3_readdatavalid   (local_mem[3].readdatavalid),
        .emif_ddr3_burstcount      (local_mem[3].burstcount),
        .emif_ddr3_writedata       (local_mem[3].writedata),
        .emif_ddr3_write           (local_mem[3].write),
        .emif_ddr3_read            (local_mem[3].read),
        .emif_ddr3_byteenable      (local_mem[3].byteenable),
        .emif_ddr3_address         ({local_mem[3].address, ddr4_byte_address_bits[3]}),
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
    `endif //ASP_ENABLE_DDR4_BANK_3

    .host_kernel_irq_irq                 (/*this port isn't used for kernel IRQ*/),
    
    .avmm_mmio64_waitrequest             (mmio64_if.waitrequest),
    .avmm_mmio64_readdata                (mmio64_if.readdata),
    .avmm_mmio64_readdatavalid           (mmio64_if.readdatavalid),
    .avmm_mmio64_burstcount              (mmio64_if.burstcount),
    .avmm_mmio64_writedata               (mmio64_if.writedata),
    .avmm_mmio64_address                 (avmm_mmio64_address[ASP_MMIO_QSYS_ADDR_WIDTH-1:0]), //manipulated below
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
    .dma_csr_mmio64_debugaccess             ()
    `ifdef INCLUDE_IO_PIPES
        //mmio64 signals for DMA controller
       ,.uoe_csr_mmio64_waitrequest             (uoe_csr_avmm.waitrequest),
        .uoe_csr_mmio64_readdata                (uoe_csr_avmm.readdata),
        .uoe_csr_mmio64_readdatavalid           (uoe_csr_avmm.readdatavalid),
        .uoe_csr_mmio64_burstcount              (uoe_csr_avmm.burstcount),
        .uoe_csr_mmio64_writedata               (uoe_csr_avmm.writedata),
        .uoe_csr_mmio64_address                 (uoe_csr_avmm.address),
        .uoe_csr_mmio64_write                   (uoe_csr_avmm.write),
        .uoe_csr_mmio64_read                    (uoe_csr_avmm.read),
        .uoe_csr_mmio64_byteenable              (uoe_csr_avmm.byteenable),
        .uoe_csr_mmio64_debugaccess             ()
    `endif //INCLUDE_IO_PIPES
    `ifdef ASP_ENABLE_DMA_CH_0
        //local-memory DMA reads
       ,.dma_localmem_rd_0_waitrequest             (dma_local_mem_rd_avmm_if[0].waitrequest),
        .dma_localmem_rd_0_readdata                (dma_local_mem_rd_avmm_if[0].readdata),
        .dma_localmem_rd_0_readdatavalid           (dma_local_mem_rd_avmm_if[0].readdatavalid),
        .dma_localmem_rd_0_burstcount              (dma_local_mem_rd_avmm_if[0].burstcount),
        .dma_localmem_rd_0_writedata               (dma_local_mem_rd_avmm_if[0].writedata),
        .dma_localmem_rd_0_address                 (dma_local_mem_rd_avmm_if[0].address),
        .dma_localmem_rd_0_write                   (dma_local_mem_rd_avmm_if[0].write),
        .dma_localmem_rd_0_read                    (dma_local_mem_rd_avmm_if[0].read),
        .dma_localmem_rd_0_byteenable              (dma_local_mem_rd_avmm_if[0].byteenable),
        .dma_localmem_rd_0_debugaccess             (),
        //local-memory DMA writes
        .dma_localmem_wr_0_waitrequest             (dma_local_mem_wr_avmm_if[0].waitrequest),
        .dma_localmem_wr_0_readdata                (dma_local_mem_wr_avmm_if[0].readdata),
        .dma_localmem_wr_0_readdatavalid           (dma_local_mem_wr_avmm_if[0].readdatavalid),
        .dma_localmem_wr_0_burstcount              (dma_local_mem_wr_avmm_if[0].burstcount),
        .dma_localmem_wr_0_writedata               (dma_local_mem_wr_avmm_if[0].writedata),
        .dma_localmem_wr_0_address                 (dma_local_mem_wr_avmm_if[0].address),
        .dma_localmem_wr_0_write                   (dma_local_mem_wr_avmm_if[0].write),
        .dma_localmem_wr_0_read                    (dma_local_mem_wr_avmm_if[0].read),
        .dma_localmem_wr_0_byteenable              (dma_local_mem_wr_avmm_if[0].byteenable),
        .dma_localmem_wr_0_debugaccess             ()
    `endif //ASP_ENABLE_DMA_CH_0
    `ifdef ASP_ENABLE_DMA_CH_1
        //local-memory DMA reads
       ,.dma_localmem_rd_1_waitrequest             (dma_local_mem_rd_avmm_if[1].waitrequest),
        .dma_localmem_rd_1_readdata                (dma_local_mem_rd_avmm_if[1].readdata),
        .dma_localmem_rd_1_readdatavalid           (dma_local_mem_rd_avmm_if[1].readdatavalid),
        .dma_localmem_rd_1_burstcount              (dma_local_mem_rd_avmm_if[1].burstcount),
        .dma_localmem_rd_1_writedata               (dma_local_mem_rd_avmm_if[1].writedata),
        .dma_localmem_rd_1_address                 (dma_local_mem_rd_avmm_if[1].address),
        .dma_localmem_rd_1_write                   (dma_local_mem_rd_avmm_if[1].write),
        .dma_localmem_rd_1_read                    (dma_local_mem_rd_avmm_if[1].read),
        .dma_localmem_rd_1_byteenable              (dma_local_mem_rd_avmm_if[1].byteenable),
        .dma_localmem_rd_1_debugaccess             (),
        //local-memory DMA writes
        .dma_localmem_wr_1_waitrequest             (dma_local_mem_wr_avmm_if[1].waitrequest),
        .dma_localmem_wr_1_readdata                (dma_local_mem_wr_avmm_if[1].readdata),
        .dma_localmem_wr_1_readdatavalid           (dma_local_mem_wr_avmm_if[1].readdatavalid),
        .dma_localmem_wr_1_burstcount              (dma_local_mem_wr_avmm_if[1].burstcount),
        .dma_localmem_wr_1_writedata               (dma_local_mem_wr_avmm_if[1].writedata),
        .dma_localmem_wr_1_address                 (dma_local_mem_wr_avmm_if[1].address),
        .dma_localmem_wr_1_write                   (dma_local_mem_wr_avmm_if[1].write),
        .dma_localmem_wr_1_read                    (dma_local_mem_wr_avmm_if[1].read),
        .dma_localmem_wr_1_byteenable              (dma_local_mem_wr_avmm_if[1].byteenable),
        .dma_localmem_wr_1_debugaccess             ()
    `endif //ASP_ENABLE_DMA_CH_1
    `ifdef ASP_ENABLE_DMA_CH_2
        //local-memory DMA reads
       ,.dma_localmem_rd_2_waitrequest             (dma_local_mem_rd_avmm_if[2].waitrequest),
        .dma_localmem_rd_2_readdata                (dma_local_mem_rd_avmm_if[2].readdata),
        .dma_localmem_rd_2_readdatavalid           (dma_local_mem_rd_avmm_if[2].readdatavalid),
        .dma_localmem_rd_2_burstcount              (dma_local_mem_rd_avmm_if[2].burstcount),
        .dma_localmem_rd_2_writedata               (dma_local_mem_rd_avmm_if[2].writedata),
        .dma_localmem_rd_2_address                 (dma_local_mem_rd_avmm_if[2].address),
        .dma_localmem_rd_2_write                   (dma_local_mem_rd_avmm_if[2].write),
        .dma_localmem_rd_2_read                    (dma_local_mem_rd_avmm_if[2].read),
        .dma_localmem_rd_2_byteenable              (dma_local_mem_rd_avmm_if[2].byteenable),
        .dma_localmem_rd_2_debugaccess             (),
        //local-memory DMA writes
        .dma_localmem_wr_2_waitrequest             (dma_local_mem_wr_avmm_if[2].waitrequest),
        .dma_localmem_wr_2_readdata                (dma_local_mem_wr_avmm_if[2].readdata),
        .dma_localmem_wr_2_readdatavalid           (dma_local_mem_wr_avmm_if[2].readdatavalid),
        .dma_localmem_wr_2_burstcount              (dma_local_mem_wr_avmm_if[2].burstcount),
        .dma_localmem_wr_2_writedata               (dma_local_mem_wr_avmm_if[2].writedata),
        .dma_localmem_wr_2_address                 (dma_local_mem_wr_avmm_if[2].address),
        .dma_localmem_wr_2_write                   (dma_local_mem_wr_avmm_if[2].write),
        .dma_localmem_wr_2_read                    (dma_local_mem_wr_avmm_if[2].read),
        .dma_localmem_wr_2_byteenable              (dma_local_mem_wr_avmm_if[2].byteenable),
        .dma_localmem_wr_2_debugaccess             ()
    `endif //ASP_ENABLE_DMA_CH_2
    `ifdef ASP_ENABLE_DMA_CH_3
        //local-memory DMA reads
       ,.dma_localmem_rd_3_waitrequest             (dma_local_mem_rd_avmm_if[3].waitrequest),
        .dma_localmem_rd_3_readdata                (dma_local_mem_rd_avmm_if[3].readdata),
        .dma_localmem_rd_3_readdatavalid           (dma_local_mem_rd_avmm_if[3].readdatavalid),
        .dma_localmem_rd_3_burstcount              (dma_local_mem_rd_avmm_if[3].burstcount),
        .dma_localmem_rd_3_writedata               (dma_local_mem_rd_avmm_if[3].writedata),
        .dma_localmem_rd_3_address                 (dma_local_mem_rd_avmm_if[3].address),
        .dma_localmem_rd_3_write                   (dma_local_mem_rd_avmm_if[3].write),
        .dma_localmem_rd_3_read                    (dma_local_mem_rd_avmm_if[3].read),
        .dma_localmem_rd_3_byteenable              (dma_local_mem_rd_avmm_if[3].byteenable),
        .dma_localmem_rd_3_debugaccess             (),
        //local-memory DMA writes
        .dma_localmem_wr_3_waitrequest             (dma_local_mem_wr_avmm_if[3].waitrequest),
        .dma_localmem_wr_3_readdata                (dma_local_mem_wr_avmm_if[3].readdata),
        .dma_localmem_wr_3_readdatavalid           (dma_local_mem_wr_avmm_if[3].readdatavalid),
        .dma_localmem_wr_3_burstcount              (dma_local_mem_wr_avmm_if[3].burstcount),
        .dma_localmem_wr_3_writedata               (dma_local_mem_wr_avmm_if[3].writedata),
        .dma_localmem_wr_3_address                 (dma_local_mem_wr_avmm_if[3].address),
        .dma_localmem_wr_3_write                   (dma_local_mem_wr_avmm_if[3].write),
        .dma_localmem_wr_3_read                    (dma_local_mem_wr_avmm_if[3].read),
        .dma_localmem_wr_3_byteenable              (dma_local_mem_wr_avmm_if[3].byteenable),
        .dma_localmem_wr_3_debugaccess             ()
    `endif //ASP_ENABLE_DMA_CH_3
);
//Create the mmio64-address based on:
//  [17:3] = mmio64_if.address left-shifted by 3
//  [2]    = (mmio64_if.byteenable == 8'hF0)
//  [1:0]  = 2'b0
always_comb begin
    avmm_mmio64_address [ASP_MMIO_QSYS_ADDR_WIDTH-1:3]    = mmio64_if.address;
    avmm_mmio64_address [2]       = (mmio64_if.byteenable == 8'hF0) ? 1'b1 : 1'b0;
    avmm_mmio64_address [1:0]     = 2'b0;
end

genvar lm;
generate
    for (lm=0;lm<ASP_LOCALMEM_NUM_CHANNELS;lm++) begin : local_mem_stuff
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
                .kernel_avmm_address    (kernel_mem[lm].address[ASP_LOCALMEM_AVMM_ADDR_WIDTH-1 : KERNELSYSTEM_MEMORY_WORD_BYTE_OFFSET]),
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
    for (i = ASP_NUM_IRQ_USED; i < ASP_NUM_INTERRUPT_LINES ; i = i + 1) begin : irq_clearing
        assign asp_irq[i] = 1'b0;
    end : irq_clearing
endgenerate

//combine separate avmm interfaces into a single rd/wr interface (per DMA channel)
genvar d0;
generate
    for (d0=0; d0 < NUM_DMA_CHAN; d0=d0+1) begin : dma_channels_0
    
        asp_host_mem_if_mux #(.DMA_CHAN_NUM(d0)) asp_host_mem_if_mux_inst (
            .clk,
            .reset,
            .asp_irq,
            .wr_fence_flag,
            .asp_mem_if (dma2mux_host_mem_if[d0]),
            .host_mem_if (host_mem_if[d0])
        );

        always_comb begin
            dma_host_mem_wr_avmm_if[d0].waitrequest     = dma2mux_host_mem_if[d0].wr_waitrequest;
            dma2mux_host_mem_if[d0].wr_writedata        = dma_host_mem_wr_avmm_if[d0].writedata;
            dma2mux_host_mem_if[d0].wr_write            = dma_host_mem_wr_avmm_if[d0].write;
            dma2mux_host_mem_if[d0].wr_address          = 'b0;
            dma2mux_host_mem_if[d0].wr_address          = dma_host_mem_wr_avmm_if[d0].address >> 6;
            dma2mux_host_mem_if[d0].wr_burstcount       = dma_host_mem_wr_avmm_if[d0].burstcount;
            dma2mux_host_mem_if[d0].wr_byteenable       = dma_host_mem_wr_avmm_if[d0].byteenable;
            
            dma_host_mem_rd_avmm_if[d0].waitrequest     = dma2mux_host_mem_if[d0].rd_waitrequest;
            dma_host_mem_rd_avmm_if[d0].readdata        = dma2mux_host_mem_if[d0].rd_readdata;
            dma_host_mem_rd_avmm_if[d0].readdatavalid   = dma2mux_host_mem_if[d0].rd_readdatavalid;
            dma2mux_host_mem_if[d0].rd_address          = 'b0;
            dma2mux_host_mem_if[d0].rd_address          = dma_host_mem_rd_avmm_if[d0].address >> 6;
            dma2mux_host_mem_if[d0].rd_burstcount       = dma_host_mem_rd_avmm_if[d0].burstcount;
            dma2mux_host_mem_if[d0].rd_read             = dma_host_mem_rd_avmm_if[d0].read;
            dma2mux_host_mem_if[d0].rd_byteenable       = dma_host_mem_rd_avmm_if[d0].byteenable;
        end
    end : dma_channels_0
endgenerate

// DMA-top module
`ifdef INCLUDE_ASP_DMA
    dma_top dma_controller_inst (
        .clk,
        .reset,
    
        // MMIO64 master from host (AVMM)
        .mmio64_if (mmio64_if_dmac),
        
        // host-memory writes (read from local memory, write to host memory)
        .host_mem_wr_avmm_if (dma_host_mem_wr_avmm_if),
        .local_mem_rd_avmm_if (dma_local_mem_rd_avmm_if),
        .dma_irq_fpga2host,
        .f2h_dma_wr_fence_flag,
        
        // host-memory reads (read from host memory, write to local memory)
        .host_mem_rd_avmm_if (dma_host_mem_rd_avmm_if),
        .local_mem_wr_avmm_if (dma_local_mem_wr_avmm_if),
        .dma_irq_host2fpga
    );
    `ifdef USE_H2F_IRQ
        assign asp_irq[ASP_DMA_0_IRQ_BIT] = dma_irq_host2fpga;
    `else
        assign asp_irq[ASP_DMA_0_IRQ_BIT] = 'b0;
    `endif
    
    `ifdef USE_F2H_IRQ
        assign asp_irq[ASP_DMA_1_IRQ_BIT] = dma_irq_fpga2host;
    `else
        assign asp_irq[ASP_DMA_1_IRQ_BIT] = 'b0;
    `endif
    
    `ifdef USE_WR_FENCE_FLAG
        assign wr_fence_flag = f2h_dma_wr_fence_flag;
    `else
        assign wr_fence_flag = 'b0;
    `endif
`else
    genvar d;
    generate
        for (d=0; d < NUM_DMA_CHAN; d=d+1) begin : dma_channels
            //the DMA controller is the host of each interface - drive '0' on 
            // read and write so that everything downstream is optimized away
            assign dma_local_mem_rd_avmm_if[d].write = 'b0;
            assign dma_local_mem_rd_avmm_if[d].read  = 'b0;
            assign dma_host_mem_wr_avmm_if[d].write  = 'b0;
            assign dma_host_mem_wr_avmm_if[d].read   = 'b0;
            assign dma_host_mem_rd_avmm_if[d].write  = 'b0;
            assign dma_host_mem_rd_avmm_if[d].read   = 'b0;
            assign dma_local_mem_wr_avmm_if[d].write = 'b0;
            assign dma_local_mem_wr_avmm_if[d].read  = 'b0;
            
        end : dma_channels
    endgenerate
    assign asp_irq[ASP_DMA_0_IRQ_BIT] = 'b0;
    assign asp_irq[ASP_DMA_1_IRQ_BIT] = 'b0;
    assign wr_fence_flag = 'b0;
`endif

`ifdef USE_KERNEL_IRQ
    logic [2:0] kernel_irq_sync;
    //sync the kernel interrupt into the host-clock domain
    always_ff @(posedge clk) begin
        kernel_irq_sync <= {kernel_irq_sync[1:0], kernel_control.kernel_irq};
        if (reset) kernel_irq_sync <= '0;
    end
    assign asp_irq[ASP_KERNEL_IRQ_BIT] = kernel_irq_sync[2];
`else
    assign asp_irq[ASP_KERNEL_IRQ_BIT] = 'b0;
`endif


endmodule : asp_logic
