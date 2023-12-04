// Copyright 2022 Intel Corporation
// SPDX-License-Identifier: MIT
//

`include "ofs_plat_if.vh"
`include "ofs_asp.vh"


module afu
import ofs_asp_pkg::*;
  (
    // Host memory (Avalon)
    ofs_plat_avalon_mem_rdwr_if.to_sink host_mem_if,

    // FPGA MMIO master (Avalon)
    ofs_plat_avalon_mem_if.to_source mmio64_if,

    // Local memory interface.
    ofs_plat_avalon_mem_if.to_slave local_mem[ASP_LOCALMEM_NUM_CHANNELS],
    
    `ifdef INCLUDE_IO_PIPES
        // Ethernet
        ofs_plat_hssi_channel_if hssi_pipes[IO_PIPES_NUM_CHAN],
    `endif

    // clocks and reset
    input logic pClk,                      //Primary interface clock
    input logic pClk_reset,                // ACTIVE HIGH Soft Reset
    input logic uClk_usr,                  // User clock domain. Refer to clock programming guide
    input logic uClk_usr_reset,
    input logic uClk_usrDiv2,              // User clock domain. Half the programmed frequency
    input logic uClk_usrDiv2_reset
);

logic reset, clk;
assign reset = pClk_reset;
assign clk   = pClk;

//local wires to connect between bsp_logic and kernel_wrapper - kernel control and memory-interface
kernel_control_intf kernel_control();
kernel_mem_intf kernel_mem[ASP_LOCALMEM_NUM_CHANNELS]();

// The width of the Avalon-MM user field is narrower on the AFU side
// of VTP, since VTP uses a bit to flag VTP page table traffic.
// Drop the high bit of the user field on the AFU side.
localparam AFU_AVMM_USER_WIDTH = host_mem_if.USER_WIDTH_ - 1;

// Virtual address interface for use by the DMA path.
ofs_plat_avalon_mem_rdwr_if
#(
    `OFS_PLAT_AVALON_MEM_RDWR_IF_REPLICATE_PARAMS_EXCEPT_TAGS(host_mem_if),
    .USER_WIDTH(AFU_AVMM_USER_WIDTH),
    .LOG_CLASS(ofs_plat_log_pkg::HOST_CHAN)
) host_mem_va_if_dma();

assign host_mem_va_if_dma.clk = host_mem_if.clk;
assign host_mem_va_if_dma.reset_n = host_mem_if.reset_n;
assign host_mem_va_if_dma.instance_number = host_mem_if.instance_number;

// mmio64-if for the BSP
ofs_plat_avalon_mem_if
#(
    `OFS_PLAT_AVALON_MEM_IF_REPLICATE_PARAMS(mmio64_if)
) mmio64_if_shim();

assign mmio64_if_shim.clk = mmio64_if.clk;
assign mmio64_if_shim.reset_n = mmio64_if.reset_n;
assign mmio64_if_shim.instance_number = mmio64_if.instance_number;

`ifdef INCLUDE_USM_SUPPORT
    // Host memory - Kernel-USM
    ofs_plat_avalon_mem_rdwr_if
    #(
        `OFS_PLAT_AVALON_MEM_RDWR_IF_REPLICATE_PARAMS_EXCEPT_TAGS(host_mem_if),
        .USER_WIDTH(AFU_AVMM_USER_WIDTH),
        .LOG_CLASS(ofs_plat_log_pkg::HOST_CHAN)
    ) host_mem_va_if_kernel();
    
    assign host_mem_va_if_kernel.clk = host_mem_if.clk;
    assign host_mem_va_if_kernel.reset_n = host_mem_if.reset_n;
    assign host_mem_va_if_kernel.instance_number = host_mem_if.instance_number;
    
    //cross kernel_svm from kernel-clock domain into host-clock domain
    ofs_plat_avalon_mem_if
    # (
        .ADDR_WIDTH (USM_AVMM_ADDR_WIDTH),
        .DATA_WIDTH (USM_AVMM_DATA_WIDTH),
        .BURST_CNT_WIDTH (USM_AVMM_BURSTCOUNT_WIDTH)
    ) kernel_svm_kclk ();
    assign kernel_svm_kclk.clk = uClk_usrDiv2;
    assign kernel_svm_kclk.reset_n = ~uClk_usrDiv2_reset;
    
    //shared Avalon-MM rd/wr interface from the kernel-system
    ofs_plat_avalon_mem_if
    # (
        .ADDR_WIDTH (USM_AVMM_ADDR_WIDTH),
        .DATA_WIDTH (USM_AVMM_DATA_WIDTH),
        .BURST_CNT_WIDTH (USM_AVMM_BURSTCOUNT_WIDTH)
    ) kernel_svm ();
    assign kernel_svm.clk = host_mem_if.clk;
    assign kernel_svm.reset_n = host_mem_if.reset_n;
    
    ofs_plat_avalon_mem_if_async_shim #(
        .RESPONSE_FIFO_DEPTH       (USM_CCB_RESPONSE_FIFO_DEPTH),
        .COMMAND_FIFO_DEPTH        (USM_CCB_COMMAND_FIFO_DEPTH),
        .COMMAND_ALMFULL_THRESHOLD (USM_CCB_COMMAND_ALMFULL_THRESHOLD)
    ) kernel_svm_avmm_ccb_inst (
        .mem_sink   (kernel_svm),
        .mem_source (kernel_svm_kclk)
    );
    
    //convert kernel_svm AVMM interface into host_mem_if
    ofs_plat_avalon_mem_if_to_rdwr_if ofs_plat_avalon_mem_if_to_rdwr_if_inst (
        .mem_sink   (host_mem_va_if_kernel),
        .mem_source (kernel_svm)
    );
`endif

host_mem_if_vtp host_mem_if_vtp_inst (
    .host_mem_if,
    .host_mem_va_if_dma,
    `ifdef INCLUDE_USM_SUPPORT
        .host_mem_va_if_kernel,
    `endif
    .mmio64_if,
    .mmio64_if_shim
);

`ifdef INCLUDE_IO_PIPES
//UDP/HSSI offload engine
    asp_avst_if udp_avst_from_kernel[IO_PIPES_NUM_CHAN-1:0]();
    asp_avst_if udp_avst_to_kernel[IO_PIPES_NUM_CHAN-1:0]();
    ofs_plat_avalon_mem_if #(
        `OFS_PLAT_AVALON_MEM_IF_REPLICATE_PARAMS(mmio64_if)
    ) uoe_csr_avmm();
    assign uoe_csr_avmm.clk     = clk;
    assign uoe_csr_avmm.reset_n = ~reset;
    
    udp_offload_engine udp_offload_engine_inst
    (
        //MAC interfaces
        .hssi_pipes,
    
        // kernel clock and reset
        .kernel_clk(uClk_usrDiv2),
        .kernel_resetn(kernel_control.kernel_reset_n),
    
        // from kernel
        .udp_avst_from_kernel,
        
        // to kernel
        .udp_avst_to_kernel,
    
        // CSR
        .uoe_csr_avmm
    );
`endif


bsp_logic bsp_logic_inst (
    .clk                    ( pClk ),
    .reset,
    .kernel_clk             ( uClk_usrDiv2 ),
    .kernel_clk_reset       ( uClk_usrDiv2_reset ),
    .host_mem_if            ( host_mem_va_if_dma ),
    .mmio64_if              ( mmio64_if_shim ),
    `ifdef INCLUDE_IO_PIPES
        .uoe_csr_avmm,
    `endif
    .local_mem,
    
    .kernel_control,
    .kernel_mem
);

kernel_wrapper kernel_wrapper_inst (
    .clk        (uClk_usrDiv2),
    .clk2x      (uClk_usr),
    .reset_n    (!uClk_usrDiv2_reset),
    
    .kernel_control,
    .kernel_mem
    `ifdef INCLUDE_USM_SUPPORT
        , .kernel_svm (kernel_svm_kclk)
    `endif

    `ifdef INCLUDE_IO_PIPES
        ,.udp_avst_from_kernel,
         .udp_avst_to_kernel
    `endif
);

// for hang debug with signaltap
reg [31:0] kernel_mem0_rd_counter /* synthesis preserve */;
reg [31:0] kernel_mem0_rdlinereq_counter /* synthesis preserve */;
reg [31:0] kernel_mem0_rdresp_counter /* synthesis preserve */;
reg [31:0] kernel_mem0_wr_counter /* synthesis preserve */;
reg [31:0] local_mem0_rd_counter /* synthesis preserve */;
reg [31:0] local_mem0_rdlinereq_counter /* synthesis preserve */;
reg [31:0] local_mem0_rdresp_counter /* synthesis preserve */;
reg [31:0] local_mem0_wr_counter /* synthesis preserve */;
reg [31:0] kernel_mem1_rd_counter /* synthesis preserve */;
reg [31:0] kernel_mem1_rdlinereq_counter /* synthesis preserve */;
reg [31:0] kernel_mem1_rdresp_counter /* synthesis preserve */;
reg [31:0] kernel_mem1_wr_counter /* synthesis preserve */;
reg [31:0] local_mem1_rd_counter /* synthesis preserve */;
reg [31:0] local_mem1_rdlinereq_counter /* synthesis preserve */;
reg [31:0] local_mem1_rdresp_counter /* synthesis preserve */;
reg [31:0] local_mem1_wr_counter /* synthesis preserve */;
reg [31:0] kernel_mem2_rd_counter /* synthesis preserve */;
reg [31:0] kernel_mem2_rdlinereq_counter /* synthesis preserve */;
reg [31:0] kernel_mem2_rdresp_counter /* synthesis preserve */;
reg [31:0] kernel_mem2_wr_counter /* synthesis preserve */;
reg [31:0] local_mem2_rd_counter /* synthesis preserve */;
reg [31:0] local_mem2_rdlinereq_counter /* synthesis preserve */;
reg [31:0] local_mem2_rdresp_counter /* synthesis preserve */;
reg [31:0] local_mem2_wr_counter /* synthesis preserve */;
reg [31:0] kernel_mem3_rd_counter /* synthesis preserve */;
reg [31:0] kernel_mem3_rdlinereq_counter /* synthesis preserve */;
reg [31:0] kernel_mem3_rdresp_counter /* synthesis preserve */;
reg [31:0] kernel_mem3_wr_counter /* synthesis preserve */;
reg [31:0] local_mem3_rd_counter /* synthesis preserve */;
reg [31:0] local_mem3_rdlinereq_counter /* synthesis preserve */;
reg [31:0] local_mem3_rdresp_counter /* synthesis preserve */;
reg [31:0] local_mem3_wr_counter /* synthesis preserve */;
always @(posedge host_mem_if.clk) begin
  if (kernel_mem[0].read & !kernel_mem[0].waitrequest) 
  begin
    kernel_mem0_rd_counter <= kernel_mem0_rd_counter + 1;
    kernel_mem0_rdlinereq_counter <= kernel_mem0_rdlinereq_counter + kernel_mem[0].burstcount;
  end

  if (kernel_mem[0].readdatavalid)
  begin
    kernel_mem0_rdresp_counter <= kernel_mem0_rdresp_counter + 1;
  end

  if (kernel_mem[0].write & !kernel_mem[0].waitrequest) 
  begin
    kernel_mem0_wr_counter <= kernel_mem0_wr_counter + 1;
  end

  if (local_mem[0].read & !local_mem[0].waitrequest) 
  begin
    local_mem0_rd_counter <= local_mem0_rd_counter + 1;
    local_mem0_rdlinereq_counter <= local_mem0_rdlinereq_counter + local_mem[0].burstcount;
  end

  if (local_mem[0].readdatavalid)
  begin
    local_mem0_rdresp_counter <= local_mem0_rdresp_counter + 1;
  end

  if (local_mem[0].write & !local_mem[0].waitrequest) 
  begin
    local_mem0_wr_counter <= local_mem0_wr_counter + 1;
  end

  if (kernel_mem[1].read & !kernel_mem[1].waitrequest) 
  begin
    kernel_mem1_rd_counter <= kernel_mem1_rd_counter + 1;
    kernel_mem1_rdlinereq_counter <= kernel_mem1_rdlinereq_counter + kernel_mem[1].burstcount;
  end

  if (kernel_mem[1].readdatavalid)
  begin
    kernel_mem1_rdresp_counter <= kernel_mem1_rdresp_counter + 1;
  end

  if (kernel_mem[1].write & !kernel_mem[1].waitrequest) 
  begin
    kernel_mem1_wr_counter <= kernel_mem1_wr_counter + 1;
  end

  if (local_mem[1].read & !local_mem[1].waitrequest) 
  begin
    local_mem1_rd_counter <= local_mem1_rd_counter + 1;
    local_mem1_rdlinereq_counter <= local_mem1_rdlinereq_counter + local_mem[1].burstcount;
  end

  if (local_mem[1].readdatavalid)
  begin
    local_mem1_rdresp_counter <= local_mem1_rdresp_counter + 1;
  end

  if (local_mem[1].write & !local_mem[1].waitrequest) 
  begin
    local_mem1_wr_counter <= local_mem1_wr_counter + 1;
  end

  if (kernel_mem[2].read & !kernel_mem[2].waitrequest) 
  begin
    kernel_mem2_rd_counter <= kernel_mem2_rd_counter + 1;
    kernel_mem2_rdlinereq_counter <= kernel_mem2_rdlinereq_counter + kernel_mem[2].burstcount;
  end

  if (kernel_mem[2].readdatavalid)
  begin
    kernel_mem2_rdresp_counter <= kernel_mem2_rdresp_counter + 1;
  end

  if (kernel_mem[2].write & !kernel_mem[2].waitrequest) 
  begin
    kernel_mem2_wr_counter <= kernel_mem2_wr_counter + 1;
  end

  if (local_mem[2].read & !local_mem[2].waitrequest) 
  begin
    local_mem2_rd_counter <= local_mem2_rd_counter + 1;
    local_mem2_rdlinereq_counter <= local_mem2_rdlinereq_counter + local_mem[2].burstcount;
  end

  if (local_mem[2].readdatavalid)
  begin
    local_mem2_rdresp_counter <= local_mem2_rdresp_counter + 1;
  end

  if (local_mem[2].write & !local_mem[2].waitrequest) 
  begin
    local_mem2_wr_counter <= local_mem2_wr_counter + 1;
  end

  if (kernel_mem[3].read & !kernel_mem[3].waitrequest) 
  begin
    kernel_mem3_rd_counter <= kernel_mem3_rd_counter + 1;
    kernel_mem3_rdlinereq_counter <= kernel_mem3_rdlinereq_counter + kernel_mem[3].burstcount;
  end

  if (kernel_mem[3].readdatavalid)
  begin
    kernel_mem3_rdresp_counter <= kernel_mem3_rdresp_counter + 1;
  end

  if (kernel_mem[3].write & !kernel_mem[3].waitrequest) 
  begin
    kernel_mem3_wr_counter <= kernel_mem3_wr_counter + 1;
  end

  if (local_mem[3].read & !local_mem[3].waitrequest) 
  begin
    local_mem3_rd_counter <= local_mem3_rd_counter + 1;
    local_mem3_rdlinereq_counter <= local_mem3_rdlinereq_counter + local_mem[3].burstcount;
  end

  if (local_mem[3].readdatavalid)
  begin
    local_mem3_rdresp_counter <= local_mem3_rdresp_counter + 1;
  end

  if (local_mem[3].write & !local_mem[3].waitrequest) 
  begin
    local_mem3_wr_counter <= local_mem3_wr_counter + 1;
  end

  if (!host_mem_if.reset_n)
  begin
    kernel_mem0_rd_counter        <= 0;
    kernel_mem0_rdlinereq_counter <= 0;
    kernel_mem0_rdresp_counter    <= 0;
    kernel_mem0_wr_counter        <= 0;
    local_mem0_rd_counter         <= 0;
    local_mem0_rdlinereq_counter  <= 0;
    local_mem0_rdresp_counter     <= 0;
    local_mem0_wr_counter         <= 0;
    kernel_mem1_rd_counter        <= 0;
    kernel_mem1_rdlinereq_counter <= 0;
    kernel_mem1_rdresp_counter    <= 0;
    kernel_mem1_wr_counter        <= 0;
    local_mem1_rd_counter         <= 0;
    local_mem1_rdlinereq_counter  <= 0;
    local_mem1_rdresp_counter     <= 0;
    local_mem1_wr_counter         <= 0;
    kernel_mem2_rd_counter        <= 0;
    kernel_mem2_rdlinereq_counter <= 0;
    kernel_mem2_rdresp_counter    <= 0;
    kernel_mem2_wr_counter        <= 0;
    local_mem2_rd_counter         <= 0;
    local_mem2_rdlinereq_counter  <= 0;
    local_mem2_rdresp_counter     <= 0;
    local_mem2_wr_counter         <= 0;
    kernel_mem3_rd_counter        <= 0;
    kernel_mem3_rdlinereq_counter <= 0;
    kernel_mem3_rdresp_counter    <= 0;
    kernel_mem3_wr_counter        <= 0;
    local_mem3_rd_counter         <= 0;
    local_mem3_rdlinereq_counter  <= 0;
    local_mem3_rdresp_counter     <= 0;
    local_mem3_wr_counter         <= 0;
  end
end


// for hang debug with signaltap
reg [13:0] counter /* synthesis preserve */;
always @(posedge host_mem_if.clk) begin
  if (!host_mem_if_wr_sop) 
  begin
    counter <= counter + 1;
  end

  if (host_mem_if_wr_sop)
  begin
    counter <= 0;
  end
end

logic [5:0] host_mem_if_wr_bursts_rem;
logic host_mem_if_wr_sop;
assign host_mem_if_wr_sop = (host_mem_if_wr_bursts_rem == 0);

// Track burst count
always @(posedge host_mem_if.clk)
begin
  if (host_mem_if.wr_write && !host_mem_if.wr_waitrequest)
  begin
    // Track write bursts in order to print "sop"
    if (host_mem_if_wr_bursts_rem == 0)
    begin
      host_mem_if_wr_bursts_rem <= host_mem_if.wr_burstcount - 1;
    end
    else
    begin
      host_mem_if_wr_bursts_rem <= host_mem_if_wr_bursts_rem - 1;
    end
  end

  if (!host_mem_if.reset_n)
  begin
    host_mem_if_wr_bursts_rem <= 0;
  end
end

logic [5:0] host_mem_va_if_dma_wr_bursts_rem;
logic host_mem_va_if_dma_wr_sop;
assign host_mem_va_if_dma_wr_sop = (host_mem_va_if_dma_wr_bursts_rem == 0);

// Track burst count
always_ff @(posedge host_mem_va_if_dma.clk)
begin
  if (host_mem_va_if_dma.wr_write && !host_mem_va_if_dma.wr_waitrequest)
  begin
    // Track write bursts in order to print "sop"
    if (host_mem_va_if_dma_wr_bursts_rem == 0)
    begin
      host_mem_va_if_dma_wr_bursts_rem <= host_mem_va_if_dma.wr_burstcount - 1;
    end
    else
    begin
      host_mem_va_if_dma_wr_bursts_rem <= host_mem_va_if_dma_wr_bursts_rem - 1;
    end
  end

  if (!host_mem_va_if_dma.reset_n)
  begin
    host_mem_va_if_dma_wr_bursts_rem <= 0;
  end
end
 

endmodule : afu
