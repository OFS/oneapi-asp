// Copyright 2022 Intel Corporation
// SPDX-License-Identifier: MIT
//

`include "platform_if.vh"
`include "fpga_defines.vh"
`include "ofs_asp.vh"

// kernel_wrapper
// Using kernel wrapper instead of kernel_system, since kernel_system is auto generated.
// kernel_system introduces boundary ports that are not used, and in PR they get preserved

module kernel_wrapper  
import ofs_asp_pkg::*;
(
    input       clk,
    input       clk2x,
    input       reset_n,
    
    kernel_control_intf.kw kernel_control,
    kernel_mem_intf.ker kernel_mem[ASP_LOCALMEM_NUM_CHANNELS]
    `ifdef INCLUDE_USM_SUPPORT
        , ofs_plat_avalon_mem_if.to_sink kernel_svm [NUM_USM_CHAN-1:0]
    `endif
    `ifdef INCLUDE_IO_PIPES
        ,asp_avst_if.source    udp_avst_from_kernel[IO_PIPES_NUM_CHAN-1:0],
        asp_avst_if.sink       udp_avst_to_kernel[IO_PIPES_NUM_CHAN-1:0]
    `endif
);

kernel_mem_intf mem_avmm_bridge [ASP_LOCALMEM_NUM_CHANNELS-1:0] ();
kernel_control_intf kernel_cra_avmm_bridge ();

always_comb begin
    kernel_control.kernel_irq                = kernel_cra_avmm_bridge.kernel_irq;
end

//add pipeline stages to the memory interfaces
genvar m;
generate 
    for (m = 0; m<ASP_LOCALMEM_NUM_CHANNELS; m=m+1) begin : mem_pipes
    
        //pipeline bridge from the kernel to board.qsys
        acl_avalon_mm_bridge_s10 #(
            .DATA_WIDTH                     ( ASP_LOCALMEM_AVMM_DATA_WIDTH ),
            .SYMBOL_WIDTH                   ( 8   ),
            .HDL_ADDR_WIDTH                 ( ASP_LOCALMEM_AVMM_ADDR_WIDTH ),
            .BURSTCOUNT_WIDTH               ( ASP_LOCALMEM_AVMM_BURSTCNT_WIDTH   ),
            .SYNCHRONIZE_RESET              ( 1   ),
            .DISABLE_WAITREQUEST_BUFFERING  ( KERNELWRAPPER_MEM_PIPELINE_DISABLEWAITREQBUFFERING),
            .READDATA_PIPE_DEPTH            ( KERNELWRAPPER_MEM_PIPELINE_STAGES_RDDATA)
        ) avmm_pipeline_inst (
            .clk               (clk),
            .reset             (!reset_n),
            .s0_waitrequest    (mem_avmm_bridge[m].waitrequest  ),
            .s0_readdata       (mem_avmm_bridge[m].readdata     ),
            .s0_readdatavalid  (mem_avmm_bridge[m].readdatavalid),
            .s0_burstcount     (mem_avmm_bridge[m].burstcount   ),
            .s0_writedata      (mem_avmm_bridge[m].writedata    ),
            .s0_address        (mem_avmm_bridge[m].address      ),
            .s0_write          (mem_avmm_bridge[m].write        ),
            .s0_read           (mem_avmm_bridge[m].read         ),
            .s0_byteenable     (mem_avmm_bridge[m].byteenable   ),
            .m0_waitrequest    (kernel_mem[m].waitrequest  ),
            .m0_readdata       (kernel_mem[m].readdata     ),
            .m0_readdatavalid  (kernel_mem[m].readdatavalid),
            .m0_burstcount     (kernel_mem[m].burstcount   ),
            .m0_writedata      (kernel_mem[m].writedata    ),
            .m0_address        (kernel_mem[m].address      ),
            .m0_write          (kernel_mem[m].write        ),
            .m0_read           (kernel_mem[m].read         ),
            .m0_byteenable     (kernel_mem[m].byteenable   )
        );
        
        always_ff @(posedge clk) begin
            mem_avmm_bridge[m].writeack <= kernel_mem[m].writeack;
            if (!reset_n) mem_avmm_bridge[m].writeack <= 'b0;
        end
    end : mem_pipes
endgenerate

`ifdef INCLUDE_USM_SUPPORT
    logic [KERNELSYSTEM_MEMORY_WORD_BYTE_OFFSET-1:0] svm_addr_shift [NUM_USM_CHAN-1:0];
    logic [56:0] svm_addr_kernel_system [NUM_USM_CHAN-1:0];
    
    ofs_plat_avalon_mem_if
    # (
        .ADDR_WIDTH (USM_AVMM_ADDR_WIDTH),
        .DATA_WIDTH (USM_AVMM_DATA_WIDTH),
        .BURST_CNT_WIDTH (USM_AVMM_BURSTCOUNT_WIDTH)
    ) svm_avmm_bridge [NUM_USM_CHAN-1:0] ();
    ofs_plat_avalon_mem_if
    # (
        .ADDR_WIDTH (USM_AVMM_ADDR_WIDTH),
        .DATA_WIDTH (USM_AVMM_DATA_WIDTH),
        .BURST_CNT_WIDTH (USM_AVMM_BURSTCOUNT_WIDTH)
    ) svm_avmm_kernelsystem [NUM_USM_CHAN-1:0] ();
    
    genvar u;
    generate
        for (u = 0; u < NUM_USM_CHAN; u=u+1) begin : usm_channels
            always_comb begin
                kernel_svm[u].user  = 'b0;
            end
            
            acl_avalon_mm_bridge_s10 #(
                .DATA_WIDTH                     ( USM_AVMM_DATA_WIDTH ),
                .SYMBOL_WIDTH                   ( 8   ),
                .HDL_ADDR_WIDTH                 ( USM_AVMM_ADDR_WIDTH ),
                .BURSTCOUNT_WIDTH               ( USM_AVMM_BURSTCOUNT_WIDTH),
                .SYNCHRONIZE_RESET              ( 1   ),
                .DISABLE_WAITREQUEST_BUFFERING  ( 1   ),
                .READDATA_PIPE_DEPTH            ( KERNELWRAPPER_SVM_PIPELINE_STAGES_RDDATA   )
            )  kernel_mem_acl_avalon_mm_bridge_s10 (
                .clk                          (clk),
                .reset                        (!reset_n),
                .s0_waitrequest               (svm_avmm_bridge[u].waitrequest),
                .s0_readdata                  (svm_avmm_bridge[u].readdata),
                .s0_readdatavalid             (svm_avmm_bridge[u].readdatavalid),
                .s0_burstcount                (svm_avmm_bridge[u].burstcount),
                .s0_writedata                 (svm_avmm_bridge[u].writedata),
                .s0_address                   (svm_avmm_bridge[u].address),
                .s0_write                     (svm_avmm_bridge[u].write),
                .s0_read                      (svm_avmm_bridge[u].read),
                .s0_byteenable                (svm_avmm_bridge[u].byteenable),
                .m0_waitrequest               (kernel_svm[u].waitrequest),
                .m0_readdata                  (kernel_svm[u].readdata),
                .m0_readdatavalid             (kernel_svm[u].readdatavalid),
                .m0_burstcount                (kernel_svm[u].burstcount),
                .m0_writedata                 (kernel_svm[u].writedata),
                .m0_address                   (kernel_svm[u].address),
                .m0_write                     (kernel_svm[u].write),
                .m0_read                      (kernel_svm[u].read),
                .m0_byteenable                (kernel_svm[u].byteenable)
            );
        end : usm_channels
    endgenerate
`endif

//avmm pipeline for kernel cra
acl_avalon_mm_bridge_s10 #(
    .DATA_WIDTH                     ( KERNEL_CRA_DATA_WIDTH ),
    .SYMBOL_WIDTH                   ( 8   ),
    .HDL_ADDR_WIDTH                 ( KERNEL_CRA_ADDR_WIDTH  ),
    .BURSTCOUNT_WIDTH               ( 1   ),
    .SYNCHRONIZE_RESET              ( 1   ),
    .DISABLE_WAITREQUEST_BUFFERING  ( KERNELWRAPPER_CRA_PIPELINE_DISABLEWAITREQBUFFERING),
    .READDATA_PIPE_DEPTH            ( KERNELWRAPPER_CRA_PIPELINE_STAGES_RDDATA)
) kernel_cra_avalon_mm_bridge_s10 (
    .clk               (clk),
    .reset             (!reset_n),
    .s0_waitrequest    (kernel_control.kernel_cra_waitrequest  ),
    .s0_readdata       (kernel_control.kernel_cra_readdata     ),
    .s0_readdatavalid  (kernel_control.kernel_cra_readdatavalid),
    .s0_burstcount     (kernel_control.kernel_cra_burstcount   ),
    .s0_writedata      (kernel_control.kernel_cra_writedata    ),
    .s0_address        (kernel_control.kernel_cra_address      ),
    .s0_write          (kernel_control.kernel_cra_write        ),
    .s0_read           (kernel_control.kernel_cra_read         ),
    .s0_byteenable     (kernel_control.kernel_cra_byteenable   ),
    .m0_waitrequest    (kernel_cra_avmm_bridge.kernel_cra_waitrequest  ),
    .m0_readdata       (kernel_cra_avmm_bridge.kernel_cra_readdata     ),
    .m0_readdatavalid  (kernel_cra_avmm_bridge.kernel_cra_readdatavalid),
    .m0_burstcount     (kernel_cra_avmm_bridge.kernel_cra_burstcount   ),
    .m0_writedata      (kernel_cra_avmm_bridge.kernel_cra_writedata    ),
    .m0_address        (kernel_cra_avmm_bridge.kernel_cra_address      ),
    .m0_write          (kernel_cra_avmm_bridge.kernel_cra_write        ),
    .m0_read           (kernel_cra_avmm_bridge.kernel_cra_read         ),
    .m0_byteenable     (kernel_cra_avmm_bridge.kernel_cra_byteenable   )
);

//the pretty SV interfaces need to be expanded here because kernel_system is verbosely generated by Quartus.
//=======================================================
//  kernel_system instantiation
//=======================================================
kernel_system kernel_system_inst (
    .clock_reset_clk              (clk),
    .clock_reset2x_clk            (clk2x),
    .clock_reset_reset_reset_n    (reset_n),
    
    `ifdef ASP_ENABLE_DDR4_BANK_0
        .kernel_ddr4a_waitrequest     (mem_avmm_bridge[0].waitrequest  ),
        .kernel_ddr4a_readdata        (mem_avmm_bridge[0].readdata     ),
        .kernel_ddr4a_readdatavalid   (mem_avmm_bridge[0].readdatavalid),
        .kernel_ddr4a_burstcount      (mem_avmm_bridge[0].burstcount   ),
        .kernel_ddr4a_writedata       (mem_avmm_bridge[0].writedata    ),
        .kernel_ddr4a_address         (mem_avmm_bridge[0].address      ),
        .kernel_ddr4a_write           (mem_avmm_bridge[0].write        ),
        .kernel_ddr4a_read            (mem_avmm_bridge[0].read         ),
        .kernel_ddr4a_byteenable      (mem_avmm_bridge[0].byteenable   ),
    `ifdef USE_WRITEACKS_FOR_KERNELSYSTEM_LOCALMEMORY_ACCESSES
            .kernel_ddr4a_writeack    (mem_avmm_bridge[0].writeack     ),
    `endif
    `endif
    `ifdef ASP_ENABLE_DDR4_BANK_1
        .kernel_ddr4b_waitrequest     (mem_avmm_bridge[1].waitrequest  ),
        .kernel_ddr4b_readdata        (mem_avmm_bridge[1].readdata     ),
        .kernel_ddr4b_readdatavalid   (mem_avmm_bridge[1].readdatavalid),
        .kernel_ddr4b_burstcount      (mem_avmm_bridge[1].burstcount   ),
        .kernel_ddr4b_writedata       (mem_avmm_bridge[1].writedata    ),
        .kernel_ddr4b_address         (mem_avmm_bridge[1].address      ),
        .kernel_ddr4b_write           (mem_avmm_bridge[1].write        ),
        .kernel_ddr4b_read            (mem_avmm_bridge[1].read         ),
        .kernel_ddr4b_byteenable      (mem_avmm_bridge[1].byteenable   ),
    `ifdef USE_WRITEACKS_FOR_KERNELSYSTEM_LOCALMEMORY_ACCESSES
        .kernel_ddr4b_writeack        (mem_avmm_bridge[1].writeack     ),
    `endif
    `endif
    `ifdef ASP_ENABLE_DDR4_BANK_2
        .kernel_ddr4c_waitrequest     (mem_avmm_bridge[2].waitrequest  ),
        .kernel_ddr4c_readdata        (mem_avmm_bridge[2].readdata     ),
        .kernel_ddr4c_readdatavalid   (mem_avmm_bridge[2].readdatavalid),
        .kernel_ddr4c_burstcount      (mem_avmm_bridge[2].burstcount   ),
        .kernel_ddr4c_writedata       (mem_avmm_bridge[2].writedata    ),
        .kernel_ddr4c_address         (mem_avmm_bridge[2].address      ),
        .kernel_ddr4c_write           (mem_avmm_bridge[2].write        ),
        .kernel_ddr4c_read            (mem_avmm_bridge[2].read         ),
        .kernel_ddr4c_byteenable      (mem_avmm_bridge[2].byteenable   ),
    `ifdef USE_WRITEACKS_FOR_KERNELSYSTEM_LOCALMEMORY_ACCESSES
            .kernel_ddr4c_writeack    (mem_avmm_bridge[2].writeack     ),
    `endif
    `endif
    `ifdef ASP_ENABLE_DDR4_BANK_3
        .kernel_ddr4d_waitrequest     (mem_avmm_bridge[3].waitrequest  ),
        .kernel_ddr4d_readdata        (mem_avmm_bridge[3].readdata     ),
        .kernel_ddr4d_readdatavalid   (mem_avmm_bridge[3].readdatavalid),
        .kernel_ddr4d_burstcount      (mem_avmm_bridge[3].burstcount   ),
        .kernel_ddr4d_writedata       (mem_avmm_bridge[3].writedata    ),
        .kernel_ddr4d_address         (mem_avmm_bridge[3].address      ),
        .kernel_ddr4d_write           (mem_avmm_bridge[3].write        ),
        .kernel_ddr4d_read            (mem_avmm_bridge[3].read         ),
        .kernel_ddr4d_byteenable      (mem_avmm_bridge[3].byteenable   ),
    `ifdef USE_WRITEACKS_FOR_KERNELSYSTEM_LOCALMEMORY_ACCESSES
        .kernel_ddr4d_writeack        (mem_avmm_bridge[3].writeack     ),
    `endif
    `endif

    .kernel_irq_irq                 (kernel_cra_avmm_bridge.kernel_irq),
    .kernel_cra_waitrequest         (kernel_cra_avmm_bridge.kernel_cra_waitrequest),
    .kernel_cra_readdata            (kernel_cra_avmm_bridge.kernel_cra_readdata),
    .kernel_cra_readdatavalid       (kernel_cra_avmm_bridge.kernel_cra_readdatavalid),
    .kernel_cra_burstcount          (kernel_cra_avmm_bridge.kernel_cra_burstcount),
    .kernel_cra_writedata           (kernel_cra_avmm_bridge.kernel_cra_writedata),
    .kernel_cra_address             (kernel_cra_avmm_bridge.kernel_cra_address),
    .kernel_cra_write               (kernel_cra_avmm_bridge.kernel_cra_write),
    .kernel_cra_read                (kernel_cra_avmm_bridge.kernel_cra_read),
    .kernel_cra_byteenable          (kernel_cra_avmm_bridge.kernel_cra_byteenable),
    .kernel_cra_debugaccess         (kernel_cra_avmm_bridge.kernel_cra_debugaccess)
    
    `ifdef INCLUDE_USM_SUPPORT
        `ifdef ASP_ENABLE_USM_CH_0
            ,.kernel_mem_waitrequest    (svm_avmm_kernelsystem[0].waitrequest),
            .kernel_mem_readdata        (svm_avmm_kernelsystem[0].readdata),
            .kernel_mem_readdatavalid   (svm_avmm_kernelsystem[0].readdatavalid),
            .kernel_mem_burstcount      (svm_avmm_kernelsystem[0].burstcount),
            .kernel_mem_writedata       (svm_avmm_kernelsystem[0].writedata),
            .kernel_mem_address         ({svm_avmm_kernelsystem[0].address,svm_addr_shift[0]}),
            .kernel_mem_write           (svm_avmm_kernelsystem[0].write),
            .kernel_mem_read            (svm_avmm_kernelsystem[0].read),
            .kernel_mem_byteenable      (svm_avmm_kernelsystem[0].byteenable)
        `endif //ASP_ENABLE_USM_CH_0
        `ifdef ASP_ENABLE_USM_CH_1
            ,.kernel_mem_1_waitrequest    (svm_avmm_kernelsystem[1].waitrequest),
            .kernel_mem_1_readdata        (svm_avmm_kernelsystem[1].readdata),
            .kernel_mem_1_readdatavalid   (svm_avmm_kernelsystem[1].readdatavalid),
            .kernel_mem_1_burstcount      (svm_avmm_kernelsystem[1].burstcount),
            .kernel_mem_1_writedata       (svm_avmm_kernelsystem[1].writedata),
            .kernel_mem_1_address         ({svm_avmm_kernelsystem[1].address,svm_addr_shift[1]}),
            .kernel_mem_1_write           (svm_avmm_kernelsystem[1].write),
            .kernel_mem_1_read            (svm_avmm_kernelsystem[1].read),
            .kernel_mem_1_byteenable      (svm_avmm_kernelsystem[1].byteenable)
        `endif //ASP_ENABLE_USM_CH_1
        `ifdef ASP_ENABLE_USM_CH_2
            ,.kernel_mem_2_waitrequest    (svm_avmm_kernelsystem[2].waitrequest),
            .kernel_mem_2_readdata        (svm_avmm_kernelsystem[2].readdata),
            .kernel_mem_2_readdatavalid   (svm_avmm_kernelsystem[2].readdatavalid),
            .kernel_mem_2_burstcount      (svm_avmm_kernelsystem[2].burstcount),
            .kernel_mem_2_writedata       (svm_avmm_kernelsystem[2].writedata),
            .kernel_mem_2_address         ({svm_avmm_kernelsystem[2].address,svm_addr_shift[2]}),
            .kernel_mem_2_write           (svm_avmm_kernelsystem[2].write),
            .kernel_mem_2_read            (svm_avmm_kernelsystem[2].read),
            .kernel_mem_2_byteenable      (svm_avmm_kernelsystem[2].byteenable)
        `endif //ASP_ENABLE_USM_CH_2
        `ifdef ASP_ENABLE_USM_CH_3
            ,.kernel_mem_3_waitrequest    (svm_avmm_kernelsystem[3].waitrequest),
            .kernel_mem_3_readdata        (svm_avmm_kernelsystem[3].readdata),
            .kernel_mem_3_readdatavalid   (svm_avmm_kernelsystem[3].readdatavalid),
            .kernel_mem_3_burstcount      (svm_avmm_kernelsystem[3].burstcount),
            .kernel_mem_3_writedata       (svm_avmm_kernelsystem[3].writedata),
            .kernel_mem_3_address         ({svm_avmm_kernelsystem[3].address,svm_addr_shift[3]}),
            .kernel_mem_3_write           (svm_avmm_kernelsystem[3].write),
            .kernel_mem_3_read            (svm_avmm_kernelsystem[3].read),
            .kernel_mem_3_byteenable      (svm_avmm_kernelsystem[3].byteenable)
        `endif //ASP_ENABLE_USM_CH_3
    `endif //INCLUDE_USM_SUPPORT
    
    `ifdef INCLUDE_IO_PIPES
        `ifdef ASP_ENABLE_IOPIPE_0
            ,.udp_out_valid        (udp_avst_from_kernel[0].valid),
            .udp_out_data          (udp_avst_from_kernel[0].data),
            .udp_out_ready         (udp_avst_from_kernel[0].ready),
            .udp_in_valid          (udp_avst_to_kernel[0].valid),
            .udp_in_data           (udp_avst_to_kernel[0].data),
            .udp_in_ready          (udp_avst_to_kernel[0].ready)
        `endif //ASP_ENABLE_IOPIPE_0
        `ifdef ASP_ENABLE_IOPIPE_1
            ,.udp_out_1_valid        (udp_avst_from_kernel[1].valid),
            .udp_out_1_data          (udp_avst_from_kernel[1].data),
            .udp_out_1_ready         (udp_avst_from_kernel[1].ready),
            .udp_in_1_valid          (udp_avst_to_kernel[1].valid),
            .udp_in_1_data           (udp_avst_to_kernel[1].data),
            .udp_in_1_ready          (udp_avst_to_kernel[1].ready)
        `endif //ASP_ENABLE_IOPIPE_1
        `ifdef ASP_ENABLE_IOPIPE_2
            ,.udp_out_2_valid        (udp_avst_from_kernel[2].valid),
            .udp_out_2_data          (udp_avst_from_kernel[2].data),
            .udp_out_2_ready         (udp_avst_from_kernel[2].ready),
            .udp_in_2_valid          (udp_avst_to_kernel[2].valid),
            .udp_in_2_data           (udp_avst_to_kernel[2].data),
            .udp_in_2_ready          (udp_avst_to_kernel[2].ready)
        `endif //ASP_ENABLE_IOPIPE_2
        `ifdef ASP_ENABLE_IOPIPE_3
            ,.udp_out_3_valid        (udp_avst_from_kernel[3].valid),
            .udp_out_3_data          (udp_avst_from_kernel[3].data),
            .udp_out_3_ready         (udp_avst_from_kernel[3].ready),
            .udp_in_3_valid          (udp_avst_to_kernel[3].valid),
            .udp_in_3_data           (udp_avst_to_kernel[3].data),
            .udp_in_3_ready          (udp_avst_to_kernel[3].ready)
        `endif //ASP_ENABLE_IOPIPE_3
        `ifdef ASP_ENABLE_IOPIPE_4
            ,.udp_out_4_valid        (udp_avst_from_kernel[4].valid),
            .udp_out_4_data          (udp_avst_from_kernel[4].data),
            .udp_out_4_ready         (udp_avst_from_kernel[4].ready),
            .udp_in_4_valid          (udp_avst_to_kernel[4].valid),
            .udp_in_4_data           (udp_avst_to_kernel[4].data),
            .udp_in_4_ready          (udp_avst_to_kernel[4].ready)
        `endif //ASP_ENABLE_IOPIPE_4
        `ifdef ASP_ENABLE_IOPIPE_5
            ,.udp_out_5_valid        (udp_avst_from_kernel[5].valid),
            .udp_out_5_data          (udp_avst_from_kernel[5].data),
            .udp_out_5_ready         (udp_avst_from_kernel[5].ready),
            .udp_in_5_valid          (udp_avst_to_kernel[5].valid),
            .udp_in_5_data           (udp_avst_to_kernel[5].data),
            .udp_in_5_ready          (udp_avst_to_kernel[5].ready)
        `endif //ASP_ENABLE_IOPIPE_5
        `ifdef ASP_ENABLE_IOPIPE_6
            ,.udp_out_6_valid        (udp_avst_from_kernel[6].valid),
            .udp_out_6_data          (udp_avst_from_kernel[6].data),
            .udp_out_6_ready         (udp_avst_from_kernel[6].ready),
            .udp_in_6_valid          (udp_avst_to_kernel[6].valid),
            .udp_in_6_data           (udp_avst_to_kernel[6].data),
            .udp_in_6_ready          (udp_avst_to_kernel[6].ready)
        `endif //ASP_ENABLE_IOPIPE_6
        `ifdef ASP_ENABLE_IOPIPE_7
            ,.udp_out_7_valid        (udp_avst_from_kernel[7].valid),
            .udp_out_7_data          (udp_avst_from_kernel[7].data),
            .udp_out_7_ready         (udp_avst_from_kernel[7].ready),
            .udp_in_7_valid          (udp_avst_to_kernel[7].valid),
            .udp_in_7_data           (udp_avst_to_kernel[7].data),
            .udp_in_7_ready          (udp_avst_to_kernel[7].ready)
        `endif //ASP_ENABLE_IOPIPE_7
        `ifdef ASP_ENABLE_IOPIPE_8
            ,.udp_out_8_valid        (udp_avst_from_kernel[8].valid),
            .udp_out_8_data          (udp_avst_from_kernel[8].data),
            .udp_out_8_ready         (udp_avst_from_kernel[8].ready),
            .udp_in_8_valid          (udp_avst_to_kernel[8].valid),
            .udp_in_8_data           (udp_avst_to_kernel[8].data),
            .udp_in_8_ready          (udp_avst_to_kernel[8].ready)
        `endif //ASP_ENABLE_IOPIPE_8
        `ifdef ASP_ENABLE_IOPIPE_9
            ,.udp_out_9_valid        (udp_avst_from_kernel[9].valid),
            .udp_out_9_data          (udp_avst_from_kernel[9].data),
            .udp_out_9_ready         (udp_avst_from_kernel[9].ready),
            .udp_in_9_valid          (udp_avst_to_kernel[9].valid),
            .udp_in_9_data           (udp_avst_to_kernel[9].data),
            .udp_in_9_ready          (udp_avst_to_kernel[9].ready)
        `endif //ASP_ENABLE_IOPIPE_9
        `ifdef ASP_ENABLE_IOPIPE_10
            ,.udp_out_10_valid        (udp_avst_from_kernel[10].valid),
            .udp_out_10_data          (udp_avst_from_kernel[10].data),
            .udp_out_10_ready         (udp_avst_from_kernel[10].ready),
            .udp_in_10_valid          (udp_avst_to_kernel[10].valid),
            .udp_in_10_data           (udp_avst_to_kernel[10].data),
            .udp_in_10_ready          (udp_avst_to_kernel[10].ready)
        `endif //ASP_ENABLE_IOPIPE_10
        `ifdef ASP_ENABLE_IOPIPE_11
            ,.udp_out_11_valid        (udp_avst_from_kernel[11].valid),
            .udp_out_11_data          (udp_avst_from_kernel[11].data),
            .udp_out_11_ready         (udp_avst_from_kernel[11].ready),
            .udp_in_11_valid          (udp_avst_to_kernel[11].valid),
            .udp_in_11_data           (udp_avst_to_kernel[11].data),
            .udp_in_11_ready          (udp_avst_to_kernel[11].ready)
        `endif //ASP_ENABLE_IOPIPE_11
        `ifdef ASP_ENABLE_IOPIPE_12
            ,.udp_out_12_valid        (udp_avst_from_kernel[12].valid),
            .udp_out_12_data          (udp_avst_from_kernel[12].data),
            .udp_out_12_ready         (udp_avst_from_kernel[12].ready),
            .udp_in_12_valid          (udp_avst_to_kernel[12].valid),
            .udp_in_12_data           (udp_avst_to_kernel[12].data),
            .udp_in_12_ready          (udp_avst_to_kernel[12].ready)
        `endif //ASP_ENABLE_IOPIPE_12
        `ifdef ASP_ENABLE_IOPIPE_13
            ,.udp_out_13_valid        (udp_avst_from_kernel[13].valid),
            .udp_out_13_data          (udp_avst_from_kernel[13].data),
            .udp_out_13_ready         (udp_avst_from_kernel[13].ready),
            .udp_in_13_valid          (udp_avst_to_kernel[13].valid),
            .udp_in_13_data           (udp_avst_to_kernel[13].data),
            .udp_in_13_ready          (udp_avst_to_kernel[13].ready)
        `endif //ASP_ENABLE_IOPIPE_13
        `ifdef ASP_ENABLE_IOPIPE_14
            ,.udp_out_14_valid        (udp_avst_from_kernel[14].valid),
            .udp_out_14_data          (udp_avst_from_kernel[14].data),
            .udp_out_14_ready         (udp_avst_from_kernel[14].ready),
            .udp_in_14_valid          (udp_avst_to_kernel[14].valid),
            .udp_in_14_data           (udp_avst_to_kernel[14].data),
            .udp_in_14_ready          (udp_avst_to_kernel[14].ready)
        `endif //ASP_ENABLE_IOPIPE_14
        `ifdef ASP_ENABLE_IOPIPE_15
            ,.udp_out_15_valid        (udp_avst_from_kernel[15].valid),
            .udp_out_15_data          (udp_avst_from_kernel[15].data),
            .udp_out_15_ready         (udp_avst_from_kernel[15].ready),
            .udp_in_15_valid          (udp_avst_to_kernel[15].valid),
            .udp_in_15_data           (udp_avst_to_kernel[15].data),
            .udp_in_15_ready          (udp_avst_to_kernel[15].ready)
        `endif //ASP_ENABLE_IOPIPE_15
    `endif
);

`ifdef INCLUDE_USM_SUPPORT
    //Until we sort out the ASP/compiler support for multiple USM channels I'm tying them
    //off here for channels higher than [0]. 
    genvar i;
    generate for (i=1; i<NUM_USM_CHAN; i=i+1) begin: tie_off_extra_usm_chans
        assign svm_avmm_kernelsystem[i].burstcount = 0;
        assign svm_avmm_kernelsystem[i].writedata = 0;
        assign svm_avmm_kernelsystem[i].address = 0;
        assign svm_avmm_kernelsystem[i].write = 0;
        assign svm_avmm_kernelsystem[i].read = 0;
        assign svm_avmm_kernelsystem[i].byteenable = 0;
    end : tie_off_extra_usm_chans
    endgenerate
    `ifdef USM_DO_SINGLE_BURST_PARTIAL_WRITES
        genvar uu;
        generate
            for (uu=0; uu < NUM_USM_CHAN; uu=uu+1) begin : usm_channels_partial_writes
                avmm_single_burst_partial_writes avmm_single_burst_partial_writes_inst
                (
                    .clk      ,
                    .reset_n  ,
                    .to_avmm_source (svm_avmm_kernelsystem[uu]),
                    .to_avmm_sink   (svm_avmm_bridge[uu])
                );
            end : usm_channels_partial_writes
        endgenerate
    `else
        genvar uu;
        generate
            for (uu=0; uu < NUM_USM_CHAN; uu=uu+1) begin : usm_channels_partial_writes
                //if not requiring partial-writes splitting, just pass the signals through
                always_comb begin
                    svm_avmm_kernelsystem[uu].waitrequest    = svm_avmm_bridge[uu].waitrequest;
                    svm_avmm_kernelsystem[uu].readdata       = svm_avmm_bridge[uu].readdata;
                    svm_avmm_kernelsystem[uu].readdatavalid  = svm_avmm_bridge[uu].readdatavalid;
                    
                    svm_avmm_bridge[uu].burstcount     = svm_avmm_kernelsystem[uu].burstcount;
                    svm_avmm_bridge[uu].writedata      = svm_avmm_kernelsystem[uu].writedata ;
                    svm_avmm_bridge[uu].address        = svm_avmm_kernelsystem[uu].address   ;
                    svm_avmm_bridge[uu].byteenable     = svm_avmm_kernelsystem[uu].byteenable;
                    svm_avmm_bridge[uu].write          = svm_avmm_kernelsystem[uu].write     ;
                    svm_avmm_bridge[uu].read           = svm_avmm_kernelsystem[uu].read      ;
                    // Higher-level interfaces don't like 'X' during simulation. Drive 0's when not 
                    // driven by the kernel-system.
                    //drive with the modified version during simulation
                    // synthesis translate off
                        svm_avmm_bridge[uu].write = svm_avmm_kernelsystem[uu].write === 'X ? 'b0 : svm_avmm_kernelsystem[uu].write;
                        svm_avmm_bridge[uu].read  = svm_avmm_kernelsystem[uu].read  === 'X ? 'b0 : svm_avmm_kernelsystem[uu].read;
                    // synthesis translate on
                end
            end : usm_channels_partial_writes
        endgenerate
    `endif
`endif

endmodule : kernel_wrapper
