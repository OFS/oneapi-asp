// Copyright 2022 Intel Corporation
// SPDX-License-Identifier: MIT
//

`include "ofs_plat_if.vh"
`include "ofs_asp.vh"


module afu
import ofs_asp_pkg::*;
  (
    // Host memory (Avalon)
    ofs_plat_avalon_mem_rdwr_if.to_sink host_mem_if [NUM_HOSTMEM_CHAN],

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

//print some package/parameter information during synthesis
`ifdef PRINT_OFS_ASP_PKG_PARAMETERS_DURING_SYNTHESIS
	initial begin
		ofs_asp_pkg::func_print_ofs_asp_pkg_parameters_during_synthesis();
	end
`endif

logic reset, clk;
assign reset = pClk_reset;
assign clk   = pClk;

//local wires to connect between asp_logic and kernel_wrapper - kernel control and memory-interface
kernel_control_intf kernel_control();
kernel_mem_intf kernel_mem[ASP_LOCALMEM_NUM_CHANNELS]();

// The width of the Avalon-MM user field is narrower on the AFU side
// of VTP, since VTP uses a bit to flag VTP page table traffic.
// Drop the high bit of the user field on the AFU side.
localparam AFU_AVMM_USER_WIDTH = host_mem_if[HOSTMEM_CHAN_VTP_SVC].USER_WIDTH_ - 1;

// mmio64-if for the ASP
ofs_plat_avalon_mem_if
#(
    `OFS_PLAT_AVALON_MEM_IF_REPLICATE_PARAMS(mmio64_if)
) mmio64_if_shim();
assign mmio64_if_shim.clk = mmio64_if.clk;
assign mmio64_if_shim.reset_n = mmio64_if.reset_n;
assign mmio64_if_shim.instance_number = mmio64_if.instance_number;

// Virtual address interface for use by the DMA path.
ofs_plat_avalon_mem_rdwr_if
#(
    `OFS_PLAT_AVALON_MEM_RDWR_IF_REPLICATE_PARAMS_EXCEPT_TAGS(host_mem_if[HOSTMEM_CHAN_VTP_SVC]),
    .USER_WIDTH(AFU_AVMM_USER_WIDTH),
    .LOG_CLASS(ofs_plat_log_pkg::HOST_CHAN)
) host_mem_va_if_dma [NUM_DMA_CHAN-1:0] ();

genvar d;
generate
	for (d=0; d < NUM_DMA_CHAN; d=d+1) begin : dma_channels
		assign host_mem_va_if_dma[d].clk = host_mem_if[d].clk;
		assign host_mem_va_if_dma[d].reset_n = host_mem_if[d].reset_n;
		assign host_mem_va_if_dma[d].instance_number = host_mem_if[d].instance_number;
	end : dma_channels
endgenerate

`ifdef INCLUDE_USM_SUPPORT
    // Host memory - Kernel-USM
    ofs_plat_avalon_mem_rdwr_if
    #(
        `OFS_PLAT_AVALON_MEM_RDWR_IF_REPLICATE_PARAMS_EXCEPT_TAGS(host_mem_if[HOSTMEM_CHAN_VTP_SVC]),
        .USER_WIDTH(AFU_AVMM_USER_WIDTH),
        .LOG_CLASS(ofs_plat_log_pkg::HOST_CHAN)
    ) host_mem_va_if_kernel [NUM_USM_CHAN-1:0] ();
        
    //cross kernel_svm from kernel-clock domain into host-clock domain
    ofs_plat_avalon_mem_if
    # (
        .ADDR_WIDTH (USM_AVMM_ADDR_WIDTH),
        .DATA_WIDTH (USM_AVMM_DATA_WIDTH),
        .BURST_CNT_WIDTH (USM_AVMM_BURSTCOUNT_WIDTH)
    ) kernel_svm_kclk [NUM_USM_CHAN-1:0] ();
	
    //shared Avalon-MM rd/wr interface from the kernel-system
    ofs_plat_avalon_mem_if
    # (
        .ADDR_WIDTH (USM_AVMM_ADDR_WIDTH),
        .DATA_WIDTH (USM_AVMM_DATA_WIDTH),
        .BURST_CNT_WIDTH (USM_AVMM_BURSTCOUNT_WIDTH)
    ) kernel_svm [NUM_USM_CHAN-1:0] ();
	genvar u;
	generate
		for (u=0; u < NUM_USM_CHAN; u=u+1) begin : usm_channels
			
			assign kernel_svm[u].clk = host_mem_if[u].clk;
			assign kernel_svm[u].reset_n = host_mem_if[u].reset_n;
			assign host_mem_va_if_kernel[u].clk = host_mem_if[u].clk;
			assign host_mem_va_if_kernel[u].reset_n = host_mem_if[u].reset_n;
			assign host_mem_va_if_kernel[u].instance_number = host_mem_if[u].instance_number;
			assign kernel_svm_kclk[u].clk = uClk_usrDiv2;
			assign kernel_svm_kclk[u].reset_n = ~uClk_usrDiv2_reset;
    
			ofs_plat_avalon_mem_if_async_shim #(
				.RESPONSE_FIFO_DEPTH       (USM_CCB_RESPONSE_FIFO_DEPTH),
				.COMMAND_FIFO_DEPTH        (USM_CCB_COMMAND_FIFO_DEPTH),
				.COMMAND_ALMFULL_THRESHOLD (USM_CCB_COMMAND_ALMFULL_THRESHOLD)
			) kernel_svm_avmm_ccb_inst (
				.mem_sink   (kernel_svm[u]),
				.mem_source (kernel_svm_kclk[u])
			);
    
			//convert kernel_svm AVMM interface into host_mem_if
			ofs_plat_avalon_mem_if_to_rdwr_if ofs_plat_avalon_mem_if_to_rdwr_if_inst (
				.mem_sink   (host_mem_va_if_kernel[u]),
				.mem_source (kernel_svm[u])
			);
		end : usm_channels
	endgenerate
`endif

host_mem_if_vtp host_mem_if_vtp_inst (
    .host_mem_if,
	`ifdef INCLUDE_ASP_DMA
		.host_mem_va_if_dma,
	`endif
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


asp_logic asp_logic_inst (
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

endmodule : afu
