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
    
    kernel_control_intf.kw kernel_control

    `ifdef ASP_ENABLE_GLOBAL_MEM_0
      ,kernel_mem_intf.ker kernel_mem0[ASP_GLOBAL_MEM_0_NUM_CHANNELS]
    `endif

    `ifdef ASP_ENABLE_GLOBAL_MEM_1
      ,kernel_mem_intf.ker kernel_mem1[ASP_GLOBAL_MEM_1_NUM_CHANNELS]
    `endif

    `ifdef ASP_ENABLE_GLOBAL_MEM_2
      ,kernel_mem_intf.ker kernel_mem2[ASP_GLOBAL_MEM_2_NUM_CHANNELS]
    `endif

    `ifdef ASP_ENABLE_GLOBAL_MEM_3
      ,kernel_mem_intf.ker kernel_mem3[ASP_GLOBAL_MEM_3_NUM_CHANNELS]
    `endif

    `ifdef INCLUDE_USM_SUPPORT
      ,ofs_plat_avalon_mem_if.to_sink kernel_svm [NUM_USM_CHAN-1:0]
    `endif

    `ifdef INCLUDE_IO_PIPES
      ,asp_avst_if.source udp_avst_from_kernel[IO_PIPES_NUM_CHAN-1:0]
      ,asp_avst_if.sink   udp_avst_to_kernel[IO_PIPES_NUM_CHAN-1:0]
    `endif
);

`ifdef ASP_ENABLE_GLOBAL_MEM_0
  kernel_mem_intf mem_avmm_bridge0 [ASP_GLOBAL_MEM_0_NUM_CHANNELS-1:0] ();
`endif

`ifdef ASP_ENABLE_GLOBAL_MEM_1
  kernel_mem_intf mem_avmm_bridge1 [ASP_GLOBAL_MEM_1_NUM_CHANNELS-1:0] ();
`endif

`ifdef ASP_ENABLE_GLOBAL_MEM_2
  kernel_mem_intf mem_avmm_bridge2 [ASP_GLOBAL_MEM_2_NUM_CHANNELS-1:0] ();
`endif

`ifdef ASP_ENABLE_GLOBAL_MEM_3
  kernel_mem_intf mem_avmm_bridge3 [ASP_GLOBAL_MEM_3_NUM_CHANNELS-1:0] ();
`endif

kernel_control_intf kernel_cra_avmm_bridge ();

always_comb begin
    kernel_control.kernel_irq                = kernel_cra_avmm_bridge.kernel_irq;
end

//add pipeline stages to the memory interfaces
genvar m;

// Global Memory 0
`ifdef ASP_ENABLE_GLOBAL_MEM_0
generate 
    for (m = 0; m<ASP_GLOBAL_MEM_0_NUM_CHANNELS; m=m+1) begin : mem_pipes0
    
        //pipeline bridge from the kernel to board.qsys
        acl_avalon_mm_bridge_s10 #(
            .DATA_WIDTH                     ( ASP_GLOBAL_MEM_0_AVMM_DATA_WIDTH ),
            .SYMBOL_WIDTH                   ( 8   ),
            .HDL_ADDR_WIDTH                 ( ASP_GLOBAL_MEM_0_AVMM_ADDR_WIDTH ),
            .BURSTCOUNT_WIDTH               ( ASP_GLOBAL_MEM_0_AVMM_BURSTCNT_WIDTH   ),
            .SYNCHRONIZE_RESET              ( 1   ),
            .DISABLE_WAITREQUEST_BUFFERING  ( KERNELWRAPPER_MEM_PIPELINE_DISABLEWAITREQBUFFERING),
            .READDATA_PIPE_DEPTH            ( KERNELWRAPPER_MEM_PIPELINE_STAGES_RDDATA)
        ) avmm_pipeline_inst (
            .clk               (clk),
            .reset             (!reset_n),
            .s0_waitrequest    (mem_avmm_bridge0[m].waitrequest  ),
            .s0_readdata       (mem_avmm_bridge0[m].readdata     ),
            .s0_readdatavalid  (mem_avmm_bridge0[m].readdatavalid),
            .s0_burstcount     (mem_avmm_bridge0[m].burstcount   ),
            .s0_writedata      (mem_avmm_bridge0[m].writedata    ),
            .s0_address        (mem_avmm_bridge0[m].address      ),
            .s0_write          (mem_avmm_bridge0[m].write        ),
            .s0_read           (mem_avmm_bridge0[m].read         ),
            .s0_byteenable     (mem_avmm_bridge0[m].byteenable   ),
            .m0_waitrequest    (kernel_mem0[m].waitrequest  ),
            .m0_readdata       (kernel_mem0[m].readdata     ),
            .m0_readdatavalid  (kernel_mem0[m].readdatavalid),
            .m0_burstcount     (kernel_mem0[m].burstcount   ),
            .m0_writedata      (kernel_mem0[m].writedata    ),
            .m0_address        (kernel_mem0[m].address      ),
            .m0_write          (kernel_mem0[m].write        ),
            .m0_read           (kernel_mem0[m].read         ),
            .m0_byteenable     (kernel_mem0[m].byteenable   )
        );
        
        always_ff @(posedge clk) begin
            mem_avmm_bridge0[m].writeack <= kernel_mem0[m].writeack;
            if (!reset_n) mem_avmm_bridge0[m].writeack <= 'b0;
        end
    end : mem_pipes0
endgenerate
`endif

// Global Memory 1
`ifdef ASP_ENABLE_GLOBAL_MEM_1
generate 
    for (m = 0; m<ASP_GLOBAL_MEM_1_NUM_CHANNELS; m=m+1) begin : mem_pipes1
    
        //pipeline bridge from the kernel to board.qsys
        acl_avalon_mm_bridge_s10 #(
            .DATA_WIDTH                     ( ASP_GLOBAL_MEM_1_AVMM_DATA_WIDTH ),
            .SYMBOL_WIDTH                   ( 8   ),
            .HDL_ADDR_WIDTH                 ( ASP_GLOBAL_MEM_1_AVMM_ADDR_WIDTH ),
            .BURSTCOUNT_WIDTH               ( ASP_GLOBAL_MEM_1_AVMM_BURSTCNT_WIDTH   ),
            .SYNCHRONIZE_RESET              ( 1   ),
            .DISABLE_WAITREQUEST_BUFFERING  ( KERNELWRAPPER_MEM_PIPELINE_DISABLEWAITREQBUFFERING),
            .READDATA_PIPE_DEPTH            ( KERNELWRAPPER_MEM_PIPELINE_STAGES_RDDATA)
        ) avmm_pipeline_inst (
            .clk               (clk),
            .reset             (!reset_n),
            .s0_waitrequest    (mem_avmm_bridge1[m].waitrequest  ),
            .s0_readdata       (mem_avmm_bridge1[m].readdata     ),
            .s0_readdatavalid  (mem_avmm_bridge1[m].readdatavalid),
            .s0_burstcount     (mem_avmm_bridge1[m].burstcount   ),
            .s0_writedata      (mem_avmm_bridge1[m].writedata    ),
            .s0_address        (mem_avmm_bridge1[m].address      ),
            .s0_write          (mem_avmm_bridge1[m].write        ),
            .s0_read           (mem_avmm_bridge1[m].read         ),
            .s0_byteenable     (mem_avmm_bridge1[m].byteenable   ),
            .m0_waitrequest    (kernel_mem1[m].waitrequest  ),
            .m0_readdata       (kernel_mem1[m].readdata     ),
            .m0_readdatavalid  (kernel_mem1[m].readdatavalid),
            .m0_burstcount     (kernel_mem1[m].burstcount   ),
            .m0_writedata      (kernel_mem1[m].writedata    ),
            .m0_address        (kernel_mem1[m].address      ),
            .m0_write          (kernel_mem1[m].write        ),
            .m0_read           (kernel_mem1[m].read         ),
            .m0_byteenable     (kernel_mem1[m].byteenable   )
        );
        
        always_ff @(posedge clk) begin
            mem_avmm_bridge1[m].writeack <= kernel_mem1[m].writeack;
            if (!reset_n) mem_avmm_bridge1[m].writeack <= 'b0;
        end
    end : mem_pipes1
endgenerate
`endif

// Global Memory 2
`ifdef ASP_ENABLE_GLOBAL_MEM_2
generate 
    for (m = 0; m<ASP_GLOBAL_MEM_2_NUM_CHANNELS; m=m+1) begin : mem_pipes2
    
        //pipeline bridge from the kernel to board.qsys
        acl_avalon_mm_bridge_s10 #(
            .DATA_WIDTH                     ( ASP_GLOBAL_MEM_2_AVMM_DATA_WIDTH ),
            .SYMBOL_WIDTH                   ( 8   ),
            .HDL_ADDR_WIDTH                 ( ASP_GLOBAL_MEM_2_AVMM_ADDR_WIDTH ),
            .BURSTCOUNT_WIDTH               ( ASP_GLOBAL_MEM_2_AVMM_BURSTCNT_WIDTH   ),
            .SYNCHRONIZE_RESET              ( 1   ),
            .DISABLE_WAITREQUEST_BUFFERING  ( KERNELWRAPPER_MEM_PIPELINE_DISABLEWAITREQBUFFERING),
            .READDATA_PIPE_DEPTH            ( KERNELWRAPPER_MEM_PIPELINE_STAGES_RDDATA)
        ) avmm_pipeline_inst (
            .clk               (clk),
            .reset             (!reset_n),
            .s0_waitrequest    (mem_avmm_bridge2[m].waitrequest  ),
            .s0_readdata       (mem_avmm_bridge2[m].readdata     ),
            .s0_readdatavalid  (mem_avmm_bridge2[m].readdatavalid),
            .s0_burstcount     (mem_avmm_bridge2[m].burstcount   ),
            .s0_writedata      (mem_avmm_bridge2[m].writedata    ),
            .s0_address        (mem_avmm_bridge2[m].address      ),
            .s0_write          (mem_avmm_bridge2[m].write        ),
            .s0_read           (mem_avmm_bridge2[m].read         ),
            .s0_byteenable     (mem_avmm_bridge2[m].byteenable   ),
            .m0_waitrequest    (kernel_mem2[m].waitrequest  ),
            .m0_readdata       (kernel_mem2[m].readdata     ),
            .m0_readdatavalid  (kernel_mem2[m].readdatavalid),
            .m0_burstcount     (kernel_mem2[m].burstcount   ),
            .m0_writedata      (kernel_mem2[m].writedata    ),
            .m0_address        (kernel_mem2[m].address      ),
            .m0_write          (kernel_mem2[m].write        ),
            .m0_read           (kernel_mem2[m].read         ),
            .m0_byteenable     (kernel_mem2[m].byteenable   )
        );
        
        always_ff @(posedge clk) begin
            mem_avmm_bridge2[m].writeack <= kernel_mem2[m].writeack;
            if (!reset_n) mem_avmm_bridge2[m].writeack <= 'b0;
        end
    end : mem_pipes2
endgenerate
`endif

// Global Memory 3
`ifdef ASP_ENABLE_GLOBAL_MEM_3
generate 
    for (m = 0; m<ASP_GLOBAL_MEM_3_NUM_CHANNELS; m=m+1) begin : mem_pipes3
    
        //pipeline bridge from the kernel to board.qsys
        acl_avalon_mm_bridge_s10 #(
            .DATA_WIDTH                     ( ASP_GLOBAL_MEM_3_AVMM_DATA_WIDTH ),
            .SYMBOL_WIDTH                   ( 8   ),
            .HDL_ADDR_WIDTH                 ( ASP_GLOBAL_MEM_3_AVMM_ADDR_WIDTH ),
            .BURSTCOUNT_WIDTH               ( ASP_GLOBAL_MEM_3_AVMM_BURSTCNT_WIDTH   ),
            .SYNCHRONIZE_RESET              ( 1   ),
            .DISABLE_WAITREQUEST_BUFFERING  ( KERNELWRAPPER_MEM_PIPELINE_DISABLEWAITREQBUFFERING),
            .READDATA_PIPE_DEPTH            ( KERNELWRAPPER_MEM_PIPELINE_STAGES_RDDATA)
        ) avmm_pipeline_inst (
            .clk               (clk),
            .reset             (!reset_n),
            .s0_waitrequest    (mem_avmm_bridge3[m].waitrequest  ),
            .s0_readdata       (mem_avmm_bridge3[m].readdata     ),
            .s0_readdatavalid  (mem_avmm_bridge3[m].readdatavalid),
            .s0_burstcount     (mem_avmm_bridge3[m].burstcount   ),
            .s0_writedata      (mem_avmm_bridge3[m].writedata    ),
            .s0_address        (mem_avmm_bridge3[m].address      ),
            .s0_write          (mem_avmm_bridge3[m].write        ),
            .s0_read           (mem_avmm_bridge3[m].read         ),
            .s0_byteenable     (mem_avmm_bridge3[m].byteenable   ),
            .m0_waitrequest    (kernel_mem3[m].waitrequest  ),
            .m0_readdata       (kernel_mem3[m].readdata     ),
            .m0_readdatavalid  (kernel_mem3[m].readdatavalid),
            .m0_burstcount     (kernel_mem3[m].burstcount   ),
            .m0_writedata      (kernel_mem3[m].writedata    ),
            .m0_address        (kernel_mem3[m].address      ),
            .m0_write          (kernel_mem3[m].write        ),
            .m0_read           (kernel_mem3[m].read         ),
            .m0_byteenable     (kernel_mem3[m].byteenable   )
        );
        
        always_ff @(posedge clk) begin
            mem_avmm_bridge3[m].writeack <= kernel_mem3[m].writeack;
            if (!reset_n) mem_avmm_bridge3[m].writeack <= 'b0;
        end
    end : mem_pipes3
endgenerate
`endif

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
   
    // Global Memory 0 
    `ifdef ASP_ENABLE_GLOBAL_MEM_0_BANK_0
        .kernel_device0_0_waitrequest     (mem_avmm_bridge0[0].waitrequest  ),
        .kernel_device0_0_readdata        (mem_avmm_bridge0[0].readdata     ),
        .kernel_device0_0_readdatavalid   (mem_avmm_bridge0[0].readdatavalid),
        .kernel_device0_0_burstcount      (mem_avmm_bridge0[0].burstcount   ),
        .kernel_device0_0_writedata       (mem_avmm_bridge0[0].writedata    ),
        .kernel_device0_0_address         (mem_avmm_bridge0[0].address      ),
        .kernel_device0_0_write           (mem_avmm_bridge0[0].write        ),
        .kernel_device0_0_read            (mem_avmm_bridge0[0].read         ),
        .kernel_device0_0_byteenable      (mem_avmm_bridge0[0].byteenable   ),
    `ifdef USE_WRITEACKS_FOR_KERNELSYSTEM_GLOBAL_MEMORY_0_ACCESSES
        .kernel_device0_0_writeack        (mem_avmm_bridge0[0].writeack     ),
    `endif
    `endif
    `ifdef ASP_ENABLE_GLOBAL_MEM_0_BANK_1
        .kernel_device0_1_waitrequest     (mem_avmm_bridge0[1].waitrequest  ),
        .kernel_device0_1_readdata        (mem_avmm_bridge0[1].readdata     ),
        .kernel_device0_1_readdatavalid   (mem_avmm_bridge0[1].readdatavalid),
        .kernel_device0_1_burstcount      (mem_avmm_bridge0[1].burstcount   ),
        .kernel_device0_1_writedata       (mem_avmm_bridge0[1].writedata    ),
        .kernel_device0_1_address         (mem_avmm_bridge0[1].address      ),
        .kernel_device0_1_write           (mem_avmm_bridge0[1].write        ),
        .kernel_device0_1_read            (mem_avmm_bridge0[1].read         ),
        .kernel_device0_1_byteenable      (mem_avmm_bridge0[1].byteenable   ),
    `ifdef USE_WRITEACKS_FOR_KERNELSYSTEM_GLOBAL_MEMORY_0_ACCESSES
        .kernel_device0_1_writeack        (mem_avmm_bridge0[1].writeack     ),
    `endif
    `endif
    `ifdef ASP_ENABLE_GLOBAL_MEM_0_BANK_2
        .kernel_device0_2_waitrequest     (mem_avmm_bridge0[2].waitrequest  ),
        .kernel_device0_2_readdata        (mem_avmm_bridge0[2].readdata     ),
        .kernel_device0_2_readdatavalid   (mem_avmm_bridge0[2].readdatavalid),
        .kernel_device0_2_burstcount      (mem_avmm_bridge0[2].burstcount   ),
        .kernel_device0_2_writedata       (mem_avmm_bridge0[2].writedata    ),
        .kernel_device0_2_address         (mem_avmm_bridge0[2].address      ),
        .kernel_device0_2_write           (mem_avmm_bridge0[2].write        ),
        .kernel_device0_2_read            (mem_avmm_bridge0[2].read         ),
        .kernel_device0_2_byteenable      (mem_avmm_bridge0[2].byteenable   ),
    `ifdef USE_WRITEACKS_FOR_KERNELSYSTEM_GLOBAL_MEMORY_0_ACCESSES
        .kernel_device0_2_writeack        (mem_avmm_bridge0[2].writeack     ),
    `endif
    `endif
    `ifdef ASP_ENABLE_GLOBAL_MEM_0_BANK_3
        .kernel_device0_3_waitrequest     (mem_avmm_bridge0[3].waitrequest  ),
        .kernel_device0_3_readdata        (mem_avmm_bridge0[3].readdata     ),
        .kernel_device0_3_readdatavalid   (mem_avmm_bridge0[3].readdatavalid),
        .kernel_device0_3_burstcount      (mem_avmm_bridge0[3].burstcount   ),
        .kernel_device0_3_writedata       (mem_avmm_bridge0[3].writedata    ),
        .kernel_device0_3_address         (mem_avmm_bridge0[3].address      ),
        .kernel_device0_3_write           (mem_avmm_bridge0[3].write        ),
        .kernel_device0_3_read            (mem_avmm_bridge0[3].read         ),
        .kernel_device0_3_byteenable      (mem_avmm_bridge0[3].byteenable   ),
    `ifdef USE_WRITEACKS_FOR_KERNELSYSTEM_GLOBAL_MEMORY_0_ACCESSES
        .kernel_device0_3_writeack        (mem_avmm_bridge0[3].writeack     ),
    `endif
    `endif
    `ifdef ASP_ENABLE_GLOBAL_MEM_0_BANK_4
        .kernel_device0_4_waitrequest     (mem_avmm_bridge0[4].waitrequest  ),
        .kernel_device0_4_readdata        (mem_avmm_bridge0[4].readdata     ),
        .kernel_device0_4_readdatavalid   (mem_avmm_bridge0[4].readdatavalid),
        .kernel_device0_4_burstcount      (mem_avmm_bridge0[4].burstcount   ),
        .kernel_device0_4_writedata       (mem_avmm_bridge0[4].writedata    ),
        .kernel_device0_4_address         (mem_avmm_bridge0[4].address      ),
        .kernel_device0_4_write           (mem_avmm_bridge0[4].write        ),
        .kernel_device0_4_read            (mem_avmm_bridge0[4].read         ),
        .kernel_device0_4_byteenable      (mem_avmm_bridge0[4].byteenable   ),
    `ifdef USE_WRITEACKS_FOR_KERNELSYSTEM_GLOBAL_MEMORY_0_ACCESSES
        .kernel_device0_4_writeack        (mem_avmm_bridge0[4].writeack     ),
    `endif
    `endif
    `ifdef ASP_ENABLE_GLOBAL_MEM_0_BANK_5
        .kernel_device0_5_waitrequest     (mem_avmm_bridge0[5].waitrequest  ),
        .kernel_device0_5_readdata        (mem_avmm_bridge0[5].readdata     ),
        .kernel_device0_5_readdatavalid   (mem_avmm_bridge0[5].readdatavalid),
        .kernel_device0_5_burstcount      (mem_avmm_bridge0[5].burstcount   ),
        .kernel_device0_5_writedata       (mem_avmm_bridge0[5].writedata    ),
        .kernel_device0_5_address         (mem_avmm_bridge0[5].address      ),
        .kernel_device0_5_write           (mem_avmm_bridge0[5].write        ),
        .kernel_device0_5_read            (mem_avmm_bridge0[5].read         ),
        .kernel_device0_5_byteenable      (mem_avmm_bridge0[5].byteenable   ),
    `ifdef USE_WRITEACKS_FOR_KERNELSYSTEM_GLOBAL_MEMORY_0_ACCESSES
        .kernel_device0_5_writeack        (mem_avmm_bridge0[5].writeack     ),
    `endif
    `endif
    `ifdef ASP_ENABLE_GLOBAL_MEM_0_BANK_6
        .kernel_device0_6_waitrequest     (mem_avmm_bridge0[6].waitrequest  ),
        .kernel_device0_6_readdata        (mem_avmm_bridge0[6].readdata     ),
        .kernel_device0_6_readdatavalid   (mem_avmm_bridge0[6].readdatavalid),
        .kernel_device0_6_burstcount      (mem_avmm_bridge0[6].burstcount   ),
        .kernel_device0_6_writedata       (mem_avmm_bridge0[6].writedata    ),
        .kernel_device0_6_address         (mem_avmm_bridge0[6].address      ),
        .kernel_device0_6_write           (mem_avmm_bridge0[6].write        ),
        .kernel_device0_6_read            (mem_avmm_bridge0[6].read         ),
        .kernel_device0_6_byteenable      (mem_avmm_bridge0[6].byteenable   ),
    `ifdef USE_WRITEACKS_FOR_KERNELSYSTEM_GLOBAL_MEMORY_0_ACCESSES
        .kernel_device0_6_writeack        (mem_avmm_bridge0[6].writeack     ),
    `endif
    `endif
    `ifdef ASP_ENABLE_GLOBAL_MEM_0_BANK_7
        .kernel_device0_7_waitrequest     (mem_avmm_bridge0[7].waitrequest  ),
        .kernel_device0_7_readdata        (mem_avmm_bridge0[7].readdata     ),
        .kernel_device0_7_readdatavalid   (mem_avmm_bridge0[7].readdatavalid),
        .kernel_device0_7_burstcount      (mem_avmm_bridge0[7].burstcount   ),
        .kernel_device0_7_writedata       (mem_avmm_bridge0[7].writedata    ),
        .kernel_device0_7_address         (mem_avmm_bridge0[7].address      ),
        .kernel_device0_7_write           (mem_avmm_bridge0[7].write        ),
        .kernel_device0_7_read            (mem_avmm_bridge0[7].read         ),
        .kernel_device0_7_byteenable      (mem_avmm_bridge0[7].byteenable   ),
    `ifdef USE_WRITEACKS_FOR_KERNELSYSTEM_GLOBAL_MEMORY_0_ACCESSES
        .kernel_device0_7_writeack        (mem_avmm_bridge0[7].writeack     ),
    `endif
    `endif

    // Global Memory 1
    `ifdef ASP_ENABLE_GLOBAL_MEM_1_BANK_0
        .kernel_device1_0_waitrequest     (mem_avmm_bridge1[0].waitrequest  ),
        .kernel_device1_0_readdata        (mem_avmm_bridge1[0].readdata     ),
        .kernel_device1_0_readdatavalid   (mem_avmm_bridge1[0].readdatavalid),
        .kernel_device1_0_burstcount      (mem_avmm_bridge1[0].burstcount   ),
        .kernel_device1_0_writedata       (mem_avmm_bridge1[0].writedata    ),
        .kernel_device1_0_address         (mem_avmm_bridge1[0].address      ),
        .kernel_device1_0_write           (mem_avmm_bridge1[0].write        ),
        .kernel_device1_0_read            (mem_avmm_bridge1[0].read         ),
        .kernel_device1_0_byteenable      (mem_avmm_bridge1[0].byteenable   ),
    `ifdef USE_WRITEACKS_FOR_KERNELSYSTEM_GLOBAL_MEMORY_1_ACCESSES
        .kernel_device1_0_writeack        (mem_avmm_bridge1[0].writeack     ),
    `endif
    `endif
    `ifdef ASP_ENABLE_GLOBAL_MEM_1_BANK_1
        .kernel_device1_1_waitrequest     (mem_avmm_bridge1[1].waitrequest  ),
        .kernel_device1_1_readdata        (mem_avmm_bridge1[1].readdata     ),
        .kernel_device1_1_readdatavalid   (mem_avmm_bridge1[1].readdatavalid),
        .kernel_device1_1_burstcount      (mem_avmm_bridge1[1].burstcount   ),
        .kernel_device1_1_writedata       (mem_avmm_bridge1[1].writedata    ),
        .kernel_device1_1_address         (mem_avmm_bridge1[1].address      ),
        .kernel_device1_1_write           (mem_avmm_bridge1[1].write        ),
        .kernel_device1_1_read            (mem_avmm_bridge1[1].read         ),
        .kernel_device1_1_byteenable      (mem_avmm_bridge1[1].byteenable   ),
    `ifdef USE_WRITEACKS_FOR_KERNELSYSTEM_GLOBAL_MEMORY_1_ACCESSES
        .kernel_device1_1_writeack        (mem_avmm_bridge1[1].writeack     ),
    `endif
    `endif
    `ifdef ASP_ENABLE_GLOBAL_MEM_1_BANK_2
        .kernel_device1_2_waitrequest     (mem_avmm_bridge1[2].waitrequest  ),
        .kernel_device1_2_readdata        (mem_avmm_bridge1[2].readdata     ),
        .kernel_device1_2_readdatavalid   (mem_avmm_bridge1[2].readdatavalid),
        .kernel_device1_2_burstcount      (mem_avmm_bridge1[2].burstcount   ),
        .kernel_device1_2_writedata       (mem_avmm_bridge1[2].writedata    ),
        .kernel_device1_2_address         (mem_avmm_bridge1[2].address      ),
        .kernel_device1_2_write           (mem_avmm_bridge1[2].write        ),
        .kernel_device1_2_read            (mem_avmm_bridge1[2].read         ),
        .kernel_device1_2_byteenable      (mem_avmm_bridge1[2].byteenable   ),
    `ifdef USE_WRITEACKS_FOR_KERNELSYSTEM_GLOBAL_MEMORY_1_ACCESSES
        .kernel_device1_2_writeack        (mem_avmm_bridge1[2].writeack     ),
    `endif
    `endif
    `ifdef ASP_ENABLE_GLOBAL_MEM_1_BANK_3
        .kernel_device1_3_waitrequest     (mem_avmm_bridge1[3].waitrequest  ),
        .kernel_device1_3_readdata        (mem_avmm_bridge1[3].readdata     ),
        .kernel_device1_3_readdatavalid   (mem_avmm_bridge1[3].readdatavalid),
        .kernel_device1_3_burstcount      (mem_avmm_bridge1[3].burstcount   ),
        .kernel_device1_3_writedata       (mem_avmm_bridge1[3].writedata    ),
        .kernel_device1_3_address         (mem_avmm_bridge1[3].address      ),
        .kernel_device1_3_write           (mem_avmm_bridge1[3].write        ),
        .kernel_device1_3_read            (mem_avmm_bridge1[3].read         ),
        .kernel_device1_3_byteenable      (mem_avmm_bridge1[3].byteenable   ),
    `ifdef USE_WRITEACKS_FOR_KERNELSYSTEM_GLOBAL_MEMORY_1_ACCESSES
        .kernel_device1_3_writeack        (mem_avmm_bridge1[3].writeack     ),
    `endif
    `endif
    `ifdef ASP_ENABLE_GLOBAL_MEM_1_BANK_4
        .kernel_device1_4_waitrequest     (mem_avmm_bridge1[4].waitrequest  ),
        .kernel_device1_4_readdata        (mem_avmm_bridge1[4].readdata     ),
        .kernel_device1_4_readdatavalid   (mem_avmm_bridge1[4].readdatavalid),
        .kernel_device1_4_burstcount      (mem_avmm_bridge1[4].burstcount   ),
        .kernel_device1_4_writedata       (mem_avmm_bridge1[4].writedata    ),
        .kernel_device1_4_address         (mem_avmm_bridge1[4].address      ),
        .kernel_device1_4_write           (mem_avmm_bridge1[4].write        ),
        .kernel_device1_4_read            (mem_avmm_bridge1[4].read         ),
        .kernel_device1_4_byteenable      (mem_avmm_bridge1[4].byteenable   ),
    `ifdef USE_WRITEACKS_FOR_KERNELSYSTEM_GLOBAL_MEMORY_1_ACCESSES
        .kernel_device1_4_writeack        (mem_avmm_bridge1[4].writeack     ),
    `endif
    `endif
    `ifdef ASP_ENABLE_GLOBAL_MEM_1_BANK_5
        .kernel_device1_5_waitrequest     (mem_avmm_bridge1[5].waitrequest  ),
        .kernel_device1_5_readdata        (mem_avmm_bridge1[5].readdata     ),
        .kernel_device1_5_readdatavalid   (mem_avmm_bridge1[5].readdatavalid),
        .kernel_device1_5_burstcount      (mem_avmm_bridge1[5].burstcount   ),
        .kernel_device1_5_writedata       (mem_avmm_bridge1[5].writedata    ),
        .kernel_device1_5_address         (mem_avmm_bridge1[5].address      ),
        .kernel_device1_5_write           (mem_avmm_bridge1[5].write        ),
        .kernel_device1_5_read            (mem_avmm_bridge1[5].read         ),
        .kernel_device1_5_byteenable      (mem_avmm_bridge1[5].byteenable   ),
    `ifdef USE_WRITEACKS_FOR_KERNELSYSTEM_GLOBAL_MEMORY_1_ACCESSES
        .kernel_device1_5_writeack        (mem_avmm_bridge1[5].writeack     ),
    `endif
    `endif
    `ifdef ASP_ENABLE_GLOBAL_MEM_1_BANK_6
        .kernel_device1_6_waitrequest     (mem_avmm_bridge1[6].waitrequest  ),
        .kernel_device1_6_readdata        (mem_avmm_bridge1[6].readdata     ),
        .kernel_device1_6_readdatavalid   (mem_avmm_bridge1[6].readdatavalid),
        .kernel_device1_6_burstcount      (mem_avmm_bridge1[6].burstcount   ),
        .kernel_device1_6_writedata       (mem_avmm_bridge1[6].writedata    ),
        .kernel_device1_6_address         (mem_avmm_bridge1[6].address      ),
        .kernel_device1_6_write           (mem_avmm_bridge1[6].write        ),
        .kernel_device1_6_read            (mem_avmm_bridge1[6].read         ),
        .kernel_device1_6_byteenable      (mem_avmm_bridge1[6].byteenable   ),
    `ifdef USE_WRITEACKS_FOR_KERNELSYSTEM_GLOBAL_MEMORY_1_ACCESSES
        .kernel_device1_6_writeack        (mem_avmm_bridge1[6].writeack     ),
    `endif
    `endif
    `ifdef ASP_ENABLE_GLOBAL_MEM_1_BANK_7
        .kernel_device1_7_waitrequest     (mem_avmm_bridge1[7].waitrequest  ),
        .kernel_device1_7_readdata        (mem_avmm_bridge1[7].readdata     ),
        .kernel_device1_7_readdatavalid   (mem_avmm_bridge1[7].readdatavalid),
        .kernel_device1_7_burstcount      (mem_avmm_bridge1[7].burstcount   ),
        .kernel_device1_7_writedata       (mem_avmm_bridge1[7].writedata    ),
        .kernel_device1_7_address         (mem_avmm_bridge1[7].address      ),
        .kernel_device1_7_write           (mem_avmm_bridge1[7].write        ),
        .kernel_device1_7_read            (mem_avmm_bridge1[7].read         ),
        .kernel_device1_7_byteenable      (mem_avmm_bridge1[7].byteenable   ),
    `ifdef USE_WRITEACKS_FOR_KERNELSYSTEM_GLOBAL_MEMORY_1_ACCESSES
        .kernel_device1_7_writeack        (mem_avmm_bridge1[7].writeack     ),
    `endif
    `endif

    // Global Memory 2
    `ifdef ASP_ENABLE_GLOBAL_MEM_2_BANK_0
        .kernel_device2_0_waitrequest     (mem_avmm_bridge2[0].waitrequest  ),
        .kernel_device2_0_readdata        (mem_avmm_bridge2[0].readdata     ),
        .kernel_device2_0_readdatavalid   (mem_avmm_bridge2[0].readdatavalid),
        .kernel_device2_0_burstcount      (mem_avmm_bridge2[0].burstcount   ),
        .kernel_device2_0_writedata       (mem_avmm_bridge2[0].writedata    ),
        .kernel_device2_0_address         (mem_avmm_bridge2[0].address      ),
        .kernel_device2_0_write           (mem_avmm_bridge2[0].write        ),
        .kernel_device2_0_read            (mem_avmm_bridge2[0].read         ),
        .kernel_device2_0_byteenable      (mem_avmm_bridge2[0].byteenable   ),
    `ifdef USE_WRITEACKS_FOR_KERNELSYSTEM_GLOBAL_MEMORY_2_ACCESSES
        .kernel_device2_0_writeack    (mem_avmm_bridge2[0].writeack     ),
    `endif
    `endif
    `ifdef ASP_ENABLE_GLOBAL_MEM_2_BANK_1
        .kernel_device2_1_waitrequest     (mem_avmm_bridge2[1].waitrequest  ),
        .kernel_device2_1_readdata        (mem_avmm_bridge2[1].readdata     ),
        .kernel_device2_1_readdatavalid   (mem_avmm_bridge2[1].readdatavalid),
        .kernel_device2_1_burstcount      (mem_avmm_bridge2[1].burstcount   ),
        .kernel_device2_1_writedata       (mem_avmm_bridge2[1].writedata    ),
        .kernel_device2_1_address         (mem_avmm_bridge2[1].address      ),
        .kernel_device2_1_write           (mem_avmm_bridge2[1].write        ),
        .kernel_device2_1_read            (mem_avmm_bridge2[1].read         ),
        .kernel_device2_1_byteenable      (mem_avmm_bridge2[1].byteenable   ),
    `ifdef USE_WRITEACKS_FOR_KERNELSYSTEM_GLOBAL_MEMORY_2_ACCESSES
        .kernel_device2_1_writeack        (mem_avmm_bridge2[1].writeack     ),
    `endif
    `endif
    `ifdef ASP_ENABLE_GLOBAL_MEM_2_BANK_2
        .kernel_device2_2_waitrequest     (mem_avmm_bridge2[2].waitrequest  ),
        .kernel_device2_2_readdata        (mem_avmm_bridge2[2].readdata     ),
        .kernel_device2_2_readdatavalid   (mem_avmm_bridge2[2].readdatavalid),
        .kernel_device2_2_burstcount      (mem_avmm_bridge2[2].burstcount   ),
        .kernel_device2_2_writedata       (mem_avmm_bridge2[2].writedata    ),
        .kernel_device2_2_address         (mem_avmm_bridge2[2].address      ),
        .kernel_device2_2_write           (mem_avmm_bridge2[2].write        ),
        .kernel_device2_2_read            (mem_avmm_bridge2[2].read         ),
        .kernel_device2_2_byteenable      (mem_avmm_bridge2[2].byteenable   ),
    `ifdef USE_WRITEACKS_FOR_KERNELSYSTEM_GLOBAL_MEMORY_2_ACCESSES
        .kernel_device2_2_writeack        (mem_avmm_bridge2[2].writeack     ),
    `endif
    `endif
    `ifdef ASP_ENABLE_GLOBAL_MEM_2_BANK_3
        .kernel_device2_3_waitrequest     (mem_avmm_bridge2[3].waitrequest  ),
        .kernel_device2_3_readdata        (mem_avmm_bridge2[3].readdata     ),
        .kernel_device2_3_readdatavalid   (mem_avmm_bridge2[3].readdatavalid),
        .kernel_device2_3_burstcount      (mem_avmm_bridge2[3].burstcount   ),
        .kernel_device2_3_writedata       (mem_avmm_bridge2[3].writedata    ),
        .kernel_device2_3_address         (mem_avmm_bridge2[3].address      ),
        .kernel_device2_3_write           (mem_avmm_bridge2[3].write        ),
        .kernel_device2_3_read            (mem_avmm_bridge2[3].read         ),
        .kernel_device2_3_byteenable      (mem_avmm_bridge2[3].byteenable   ),
    `ifdef USE_WRITEACKS_FOR_KERNELSYSTEM_GLOBAL_MEMORY_2_ACCESSES
        .kernel_device2_3_writeack        (mem_avmm_bridge2[3].writeack     ),
    `endif
    `endif
    `ifdef ASP_ENABLE_GLOBAL_MEM_2_BANK_4
        .kernel_device2_4_waitrequest     (mem_avmm_bridge2[4].waitrequest  ),
        .kernel_device2_4_readdata        (mem_avmm_bridge2[4].readdata     ),
        .kernel_device2_4_readdatavalid   (mem_avmm_bridge2[4].readdatavalid),
        .kernel_device2_4_burstcount      (mem_avmm_bridge2[4].burstcount   ),
        .kernel_device2_4_writedata       (mem_avmm_bridge2[4].writedata    ),
        .kernel_device2_4_address         (mem_avmm_bridge2[4].address      ),
        .kernel_device2_4_write           (mem_avmm_bridge2[4].write        ),
        .kernel_device2_4_read            (mem_avmm_bridge2[4].read         ),
        .kernel_device2_4_byteenable      (mem_avmm_bridge2[4].byteenable   ),
    `ifdef USE_WRITEACKS_FOR_KERNELSYSTEM_GLOBAL_MEMORY_2_ACCESSES
        .kernel_device2_4_writeack        (mem_avmm_bridge2[4].writeack     ),
    `endif
    `endif
    `ifdef ASP_ENABLE_GLOBAL_MEM_2_BANK_5
        .kernel_device2_5_waitrequest     (mem_avmm_bridge2[5].waitrequest  ),
        .kernel_device2_5_readdata        (mem_avmm_bridge2[5].readdata     ),
        .kernel_device2_5_readdatavalid   (mem_avmm_bridge2[5].readdatavalid),
        .kernel_device2_5_burstcount      (mem_avmm_bridge2[5].burstcount   ),
        .kernel_device2_5_writedata       (mem_avmm_bridge2[5].writedata    ),
        .kernel_device2_5_address         (mem_avmm_bridge2[5].address      ),
        .kernel_device2_5_write           (mem_avmm_bridge2[5].write        ),
        .kernel_device2_5_read            (mem_avmm_bridge2[5].read         ),
        .kernel_device2_5_byteenable      (mem_avmm_bridge2[5].byteenable   ),
    `ifdef USE_WRITEACKS_FOR_KERNELSYSTEM_GLOBAL_MEMORY_2_ACCESSES
        .kernel_device2_5_writeack        (mem_avmm_bridge2[5].writeack     ),
    `endif
    `endif
    `ifdef ASP_ENABLE_GLOBAL_MEM_2_BANK_6
        .kernel_device2_6_waitrequest     (mem_avmm_bridge2[6].waitrequest  ),
        .kernel_device2_6_readdata        (mem_avmm_bridge2[6].readdata     ),
        .kernel_device2_6_readdatavalid   (mem_avmm_bridge2[6].readdatavalid),
        .kernel_device2_6_burstcount      (mem_avmm_bridge2[6].burstcount   ),
        .kernel_device2_6_writedata       (mem_avmm_bridge2[6].writedata    ),
        .kernel_device2_6_address         (mem_avmm_bridge2[6].address      ),
        .kernel_device2_6_write           (mem_avmm_bridge2[6].write        ),
        .kernel_device2_6_read            (mem_avmm_bridge2[6].read         ),
        .kernel_device2_6_byteenable      (mem_avmm_bridge2[6].byteenable   ),
    `ifdef USE_WRITEACKS_FOR_KERNELSYSTEM_GLOBAL_MEMORY_2_ACCESSES
        .kernel_device2_6_writeack        (mem_avmm_bridge2[6].writeack     ),
    `endif
    `endif
    `ifdef ASP_ENABLE_GLOBAL_MEM_2_BANK_7
        .kernel_device2_7_waitrequest     (mem_avmm_bridge2[7].waitrequest  ),
        .kernel_device2_7_readdata        (mem_avmm_bridge2[7].readdata     ),
        .kernel_device2_7_readdatavalid   (mem_avmm_bridge2[7].readdatavalid),
        .kernel_device2_7_burstcount      (mem_avmm_bridge2[7].burstcount   ),
        .kernel_device2_7_writedata       (mem_avmm_bridge2[7].writedata    ),
        .kernel_device2_7_address         (mem_avmm_bridge2[7].address      ),
        .kernel_device2_7_write           (mem_avmm_bridge2[7].write        ),
        .kernel_device2_7_read            (mem_avmm_bridge2[7].read         ),
        .kernel_device2_7_byteenable      (mem_avmm_bridge2[7].byteenable   ),
    `ifdef USE_WRITEACKS_FOR_KERNELSYSTEM_GLOBAL_MEMORY_2_ACCESSES
        .kernel_device2_7_writeack        (mem_avmm_bridge2[7].writeack     ),
    `endif
    `endif

    // Global Memory 3
    `ifdef ASP_ENABLE_GLOBAL_MEM_3_BANK_0
        .kernel_device3_0_waitrequest     (mem_avmm_bridge3[0].waitrequest  ),
        .kernel_device3_0_readdata        (mem_avmm_bridge3[0].readdata     ),
        .kernel_device3_0_readdatavalid   (mem_avmm_bridge3[0].readdatavalid),
        .kernel_device3_0_burstcount      (mem_avmm_bridge3[0].burstcount   ),
        .kernel_device3_0_writedata       (mem_avmm_bridge3[0].writedata    ),
        .kernel_device3_0_address         (mem_avmm_bridge3[0].address      ),
        .kernel_device3_0_write           (mem_avmm_bridge3[0].write        ),
        .kernel_device3_0_read            (mem_avmm_bridge3[0].read         ),
        .kernel_device3_0_byteenable      (mem_avmm_bridge3[0].byteenable   ),
    `ifdef USE_WRITEACKS_FOR_KERNELSYSTEM_GLOBAL_MEMORY_3_ACCESSES
        .kernel_device3_0_writeack        (mem_avmm_bridge3[0].writeack     ),
    `endif
    `endif
    `ifdef ASP_ENABLE_GLOBAL_MEM_3_BANK_1
        .kernel_device3_1_waitrequest     (mem_avmm_bridge3[1].waitrequest  ),
        .kernel_device3_1_readdata        (mem_avmm_bridge3[1].readdata     ),
        .kernel_device3_1_readdatavalid   (mem_avmm_bridge3[1].readdatavalid),
        .kernel_device3_1_burstcount      (mem_avmm_bridge3[1].burstcount   ),
        .kernel_device3_1_writedata       (mem_avmm_bridge3[1].writedata    ),
        .kernel_device3_1_address         (mem_avmm_bridge3[1].address      ),
        .kernel_device3_1_write           (mem_avmm_bridge3[1].write        ),
        .kernel_device3_1_read            (mem_avmm_bridge3[1].read         ),
        .kernel_device3_1_byteenable      (mem_avmm_bridge3[1].byteenable   ),
    `ifdef USE_WRITEACKS_FOR_KERNELSYSTEM_GLOBAL_MEMORY_3_ACCESSES
        .kernel_device3_1_writeack        (mem_avmm_bridge3[1].writeack     ),
    `endif
    `endif
    `ifdef ASP_ENABLE_GLOBAL_MEM_3_BANK_2
        .kernel_device3_2_waitrequest     (mem_avmm_bridge3[2].waitrequest  ),
        .kernel_device3_2_readdata        (mem_avmm_bridge3[2].readdata     ),
        .kernel_device3_2_readdatavalid   (mem_avmm_bridge3[2].readdatavalid),
        .kernel_device3_2_burstcount      (mem_avmm_bridge3[2].burstcount   ),
        .kernel_device3_2_writedata       (mem_avmm_bridge3[2].writedata    ),
        .kernel_device3_2_address         (mem_avmm_bridge3[2].address      ),
        .kernel_device3_2_write           (mem_avmm_bridge3[2].write        ),
        .kernel_device3_2_read            (mem_avmm_bridge3[2].read         ),
        .kernel_device3_2_byteenable      (mem_avmm_bridge3[2].byteenable   ),
    `ifdef USE_WRITEACKS_FOR_KERNELSYSTEM_GLOBAL_MEMORY_3_ACCESSES
        .kernel_device3_2_writeack        (mem_avmm_bridge3[2].writeack     ),
    `endif
    `endif
    `ifdef ASP_ENABLE_GLOBAL_MEM_3_BANK_3
        .kernel_device3_3_waitrequest     (mem_avmm_bridge3[3].waitrequest  ),
        .kernel_device3_3_readdata        (mem_avmm_bridge3[3].readdata     ),
        .kernel_device3_3_readdatavalid   (mem_avmm_bridge3[3].readdatavalid),
        .kernel_device3_3_burstcount      (mem_avmm_bridge3[3].burstcount   ),
        .kernel_device3_3_writedata       (mem_avmm_bridge3[3].writedata    ),
        .kernel_device3_3_address         (mem_avmm_bridge3[3].address      ),
        .kernel_device3_3_write           (mem_avmm_bridge3[3].write        ),
        .kernel_device3_3_read            (mem_avmm_bridge3[3].read         ),
        .kernel_device3_3_byteenable      (mem_avmm_bridge3[3].byteenable   ),
    `ifdef USE_WRITEACKS_FOR_KERNELSYSTEM_GLOBAL_MEMORY_3_ACCESSES
        .kernel_device3_3_writeack        (mem_avmm_bridge3[3].writeack     ),
    `endif
    `endif
    `ifdef ASP_ENABLE_GLOBAL_MEM_3_BANK_4
        .kernel_device3_4_waitrequest     (mem_avmm_bridge3[4].waitrequest  ),
        .kernel_device3_4_readdata        (mem_avmm_bridge3[4].readdata     ),
        .kernel_device3_4_readdatavalid   (mem_avmm_bridge3[4].readdatavalid),
        .kernel_device3_4_burstcount      (mem_avmm_bridge3[4].burstcount   ),
        .kernel_device3_4_writedata       (mem_avmm_bridge3[4].writedata    ),
        .kernel_device3_4_address         (mem_avmm_bridge3[4].address      ),
        .kernel_device3_4_write           (mem_avmm_bridge3[4].write        ),
        .kernel_device3_4_read            (mem_avmm_bridge3[4].read         ),
        .kernel_device3_4_byteenable      (mem_avmm_bridge3[4].byteenable   ),
    `ifdef USE_WRITEACKS_FOR_KERNELSYSTEM_GLOBAL_MEMORY_3_ACCESSES
        .kernel_device3_4_writeack        (mem_avmm_bridge3[4].writeack     ),
    `endif
    `endif
    `ifdef ASP_ENABLE_GLOBAL_MEM_3_BANK_5
        .kernel_device3_5_waitrequest     (mem_avmm_bridge3[5].waitrequest  ),
        .kernel_device3_5_readdata        (mem_avmm_bridge3[5].readdata     ),
        .kernel_device3_5_readdatavalid   (mem_avmm_bridge3[5].readdatavalid),
        .kernel_device3_5_burstcount      (mem_avmm_bridge3[5].burstcount   ),
        .kernel_device3_5_writedata       (mem_avmm_bridge3[5].writedata    ),
        .kernel_device3_5_address         (mem_avmm_bridge3[5].address      ),
        .kernel_device3_5_write           (mem_avmm_bridge3[5].write        ),
        .kernel_device3_5_read            (mem_avmm_bridge3[5].read         ),
        .kernel_device3_5_byteenable      (mem_avmm_bridge3[5].byteenable   ),
    `ifdef USE_WRITEACKS_FOR_KERNELSYSTEM_GLOBAL_MEMORY_3_ACCESSES
        .kernel_device3_5_writeack        (mem_avmm_bridge3[5].writeack     ),
    `endif
    `endif
    `ifdef ASP_ENABLE_GLOBAL_MEM_3_BANK_6
        .kernel_device3_6_waitrequest     (mem_avmm_bridge3[6].waitrequest  ),
        .kernel_device3_6_readdata        (mem_avmm_bridge3[6].readdata     ),
        .kernel_device3_6_readdatavalid   (mem_avmm_bridge3[6].readdatavalid),
        .kernel_device3_6_burstcount      (mem_avmm_bridge3[6].burstcount   ),
        .kernel_device3_6_writedata       (mem_avmm_bridge3[6].writedata    ),
        .kernel_device3_6_address         (mem_avmm_bridge3[6].address      ),
        .kernel_device3_6_write           (mem_avmm_bridge3[6].write        ),
        .kernel_device3_6_read            (mem_avmm_bridge3[6].read         ),
        .kernel_device3_6_byteenable      (mem_avmm_bridge3[6].byteenable   ),
    `ifdef USE_WRITEACKS_FOR_KERNELSYSTEM_GLOBAL_MEMORY_3_ACCESSES
        .kernel_device3_6_writeack        (mem_avmm_bridge3[6].writeack     ),
    `endif
    `endif
    `ifdef ASP_ENABLE_GLOBAL_MEM_3_BANK_7
        .kernel_device3_7_waitrequest     (mem_avmm_bridge3[7].waitrequest  ),
        .kernel_device3_7_readdata        (mem_avmm_bridge3[7].readdata     ),
        .kernel_device3_7_readdatavalid   (mem_avmm_bridge3[7].readdatavalid),
        .kernel_device3_7_burstcount      (mem_avmm_bridge3[7].burstcount   ),
        .kernel_device3_7_writedata       (mem_avmm_bridge3[7].writedata    ),
        .kernel_device3_7_address         (mem_avmm_bridge3[7].address      ),
        .kernel_device3_7_write           (mem_avmm_bridge3[7].write        ),
        .kernel_device3_7_read            (mem_avmm_bridge3[7].read         ),
        .kernel_device3_7_byteenable      (mem_avmm_bridge3[7].byteenable   ),
    `ifdef USE_WRITEACKS_FOR_KERNELSYSTEM_GLOBAL_MEMORY_3_ACCESSES
        .kernel_device3_7_writeack        (mem_avmm_bridge3[7].writeack     ),
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
            ,.kernel_host0_waitrequest    (svm_avmm_kernelsystem[0].waitrequest),
            .kernel_host0_readdata        (svm_avmm_kernelsystem[0].readdata),
            .kernel_host0_readdatavalid   (svm_avmm_kernelsystem[0].readdatavalid),
            .kernel_host0_burstcount      (svm_avmm_kernelsystem[0].burstcount),
            .kernel_host0_writedata       (svm_avmm_kernelsystem[0].writedata),
            .kernel_host0_address         ({svm_avmm_kernelsystem[0].address,svm_addr_shift[0]}),
            .kernel_host0_write           (svm_avmm_kernelsystem[0].write),
            .kernel_host0_read            (svm_avmm_kernelsystem[0].read),
            .kernel_host0_byteenable      (svm_avmm_kernelsystem[0].byteenable)
        `endif //ASP_ENABLE_USM_CH_0
        `ifdef ASP_ENABLE_USM_CH_1
            ,.kernel_host1_waitrequest    (svm_avmm_kernelsystem[1].waitrequest),
            .kernel_host1_readdata        (svm_avmm_kernelsystem[1].readdata),
            .kernel_host1_readdatavalid   (svm_avmm_kernelsystem[1].readdatavalid),
            .kernel_host1_burstcount      (svm_avmm_kernelsystem[1].burstcount),
            .kernel_host1_writedata       (svm_avmm_kernelsystem[1].writedata),
            .kernel_host1_address         ({svm_avmm_kernelsystem[1].address,svm_addr_shift[1]}),
            .kernel_host1_write           (svm_avmm_kernelsystem[1].write),
            .kernel_host1_read            (svm_avmm_kernelsystem[1].read),
            .kernel_host1_byteenable      (svm_avmm_kernelsystem[1].byteenable)
        `endif //ASP_ENABLE_USM_CH_1
        `ifdef ASP_ENABLE_USM_CH_2
            ,.kernel_host2_waitrequest    (svm_avmm_kernelsystem[2].waitrequest),
            .kernel_host2_readdata        (svm_avmm_kernelsystem[2].readdata),
            .kernel_host2_readdatavalid   (svm_avmm_kernelsystem[2].readdatavalid),
            .kernel_host2_burstcount      (svm_avmm_kernelsystem[2].burstcount),
            .kernel_host2_writedata       (svm_avmm_kernelsystem[2].writedata),
            .kernel_host2_address         ({svm_avmm_kernelsystem[2].address,svm_addr_shift[2]}),
            .kernel_host2_write           (svm_avmm_kernelsystem[2].write),
            .kernel_host2_read            (svm_avmm_kernelsystem[2].read),
            .kernel_host2_byteenable      (svm_avmm_kernelsystem[2].byteenable)
        `endif //ASP_ENABLE_USM_CH_2
        `ifdef ASP_ENABLE_USM_CH_3
            ,.kernel_host3_waitrequest    (svm_avmm_kernelsystem[3].waitrequest),
            .kernel_host3_readdata        (svm_avmm_kernelsystem[3].readdata),
            .kernel_host3_readdatavalid   (svm_avmm_kernelsystem[3].readdatavalid),
            .kernel_host3_burstcount      (svm_avmm_kernelsystem[3].burstcount),
            .kernel_host3_writedata       (svm_avmm_kernelsystem[3].writedata),
            .kernel_host3_address         ({svm_avmm_kernelsystem[3].address,svm_addr_shift[3]}),
            .kernel_host3_write           (svm_avmm_kernelsystem[3].write),
            .kernel_host3_read            (svm_avmm_kernelsystem[3].read),
            .kernel_host3_byteenable      (svm_avmm_kernelsystem[3].byteenable)
        `endif //ASP_ENABLE_USM_CH_3
    `endif //INCLUDE_USM_SUPPORT
    
    `ifdef INCLUDE_IO_PIPES
        `ifdef ASP_ENABLE_IOPIPE_0
            ,.udp_out_0_valid        (udp_avst_from_kernel[0].valid),
            .udp_out_0_data          (udp_avst_from_kernel[0].data),
            .udp_out_0_ready         (udp_avst_from_kernel[0].ready),
            .udp_in_0_valid          (udp_avst_to_kernel[0].valid),
            .udp_in_0_data           (udp_avst_to_kernel[0].data),
            .udp_in_0_ready          (udp_avst_to_kernel[0].ready)
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
    `ifndef ASP_ENABLE_USM_CH_1
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
    `endif
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
