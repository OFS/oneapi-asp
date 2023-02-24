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

`include "platform_if.vh"
`include "fpga_defines.vh"
`include "opencl_bsp.vh"

// kernel_wrapper
// Using kernel wrapper instead of kernel_system, since kernel_system is auto generated.
// kernel_system introduces boundary ports that are not used, and in PR they get preserved

module kernel_wrapper  
import dc_bsp_pkg::*;
(
    input       clk,
    input       clk2x,
    input       reset_n,
    
    opencl_kernel_control_intf.kw opencl_kernel_control,
    kernel_mem_intf.ker kernel_mem[BSP_NUM_LOCAL_MEM_BANKS]
    `ifdef INCLUDE_USM_SUPPORT
        , ofs_plat_avalon_mem_if.to_sink kernel_svm
    `endif
);

kernel_mem_intf mem_avmm_bridge [BSP_NUM_LOCAL_MEM_BANKS-1:0] ();
opencl_kernel_control_intf kernel_cra_avmm_bridge ();
logic [OPENCL_BSP_KERNEL_SVM_BURSTCOUNT_WIDTH-1:0] svm_avmm_bridge_burstcount;
logic [OPENCL_SVM_QSYS_ADDR_WIDTH-1:0] svm_avmm_bridge_address;

localparam USM_AVMM_BUFFER_WIDTH =  OPENCL_SVM_QSYS_ADDR_WIDTH +
                                    OPENCL_BSP_KERNEL_SVM_DATA_WIDTH +
                                    OPENCL_BSP_KERNEL_SVM_BURSTCOUNT_WIDTH +
                                    1 + //write req
                                    1 + //read req
                                    (OPENCL_BSP_KERNEL_SVM_DATA_WIDTH/8); //byteenable size
localparam USM_AVMM_BUFFER_DEPTH = 1024;
localparam USM_AVMM_BUFFER_SKID_SPACE = 64;
localparam USM_AVMM_BUFFER_ALMFULL_VALUE = USM_AVMM_BUFFER_DEPTH - USM_AVMM_BUFFER_SKID_SPACE;

typedef struct packed {
    logic read, write;
    logic [OPENCL_SVM_QSYS_ADDR_WIDTH-1:0] address;
    logic [OPENCL_BSP_KERNEL_SVM_BURSTCOUNT_WIDTH-1:0] burstcount;
    logic [(OPENCL_BSP_KERNEL_SVM_DATA_WIDTH/8)-1:0] byteenable;
    logic [OPENCL_BSP_KERNEL_SVM_DATA_WIDTH-1:0] writedata;
} usm_avmm_cmd_t;
usm_avmm_cmd_t usm_avmm_cmd_from_kernelsystem, usm_avmm_cmd_buf_out;
        
always_comb begin
    opencl_kernel_control.kernel_irq                = kernel_cra_avmm_bridge.kernel_irq;
end

//add pipeline stages to the memory interfaces
genvar m;
generate 
    for (m = 0; m<BSP_NUM_LOCAL_MEM_BANKS; m=m+1) begin : mem_pipes
    
        //pipeline bridge from the kernel to board.qsys
        acl_avalon_mm_bridge_s10 #(
            .DATA_WIDTH                     ( OPENCL_BSP_KERNEL_DATA_WIDTH ),
            .SYMBOL_WIDTH                   ( 8   ),
            .HDL_ADDR_WIDTH                 ( OPENCL_QSYS_ADDR_WIDTH ),
            .BURSTCOUNT_WIDTH               ( OPENCL_BSP_KERNEL_BURSTCOUNT_WIDTH   ),
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
    end : mem_pipes
endgenerate

`ifdef INCLUDE_USM_SUPPORT
    logic [OPENCL_MEMORY_BYTE_OFFSET-1:0] svm_addr_shift;
    logic kernel_system_svm_read, kernel_system_svm_write;
    
    ofs_plat_avalon_mem_if
    # (
        .ADDR_WIDTH (OPENCL_SVM_QSYS_ADDR_WIDTH),
        .DATA_WIDTH (OPENCL_BSP_KERNEL_SVM_DATA_WIDTH),
        .BURST_CNT_WIDTH (OPENCL_BSP_KERNEL_SVM_BURSTCOUNT_WIDTH)
    ) svm_avmm_bridge ();
    
    always_comb begin
        kernel_svm.user  = 'b0;
    end
    
    acl_avalon_mm_bridge_s10 #(
        .DATA_WIDTH                     ( OPENCL_BSP_KERNEL_SVM_DATA_WIDTH ),
        .SYMBOL_WIDTH                   ( 8   ),
        .HDL_ADDR_WIDTH                 ( OPENCL_SVM_QSYS_ADDR_WIDTH ),
        .BURSTCOUNT_WIDTH               ( OPENCL_BSP_KERNEL_SVM_BURSTCOUNT_WIDTH),
        .SYNCHRONIZE_RESET              ( 1   ),
        .DISABLE_WAITREQUEST_BUFFERING  ( 1   ),
        .READDATA_PIPE_DEPTH            ( KERNELWRAPPER_SVM_PIPELINE_STAGES_RDDATA   )
    )  kernel_mem_acl_avalon_mm_bridge_s10 (
        .clk                          (clk),
        .reset                        (!reset_n),
        .s0_waitrequest               (svm_avmm_bridge.waitrequest),
        .s0_readdata                  (svm_avmm_bridge.readdata),
        .s0_readdatavalid             (svm_avmm_bridge.readdatavalid),
        .s0_burstcount                (svm_avmm_bridge.burstcount),
        .s0_writedata                 (svm_avmm_bridge.writedata),
        .s0_address                   (svm_avmm_bridge.address),
        .s0_write                     (svm_avmm_bridge.write),
        .s0_read                      (svm_avmm_bridge.read),
        .s0_byteenable                (svm_avmm_bridge.byteenable),
        .m0_waitrequest               (kernel_svm.waitrequest),
        .m0_readdata                  (kernel_svm.readdata),
        .m0_readdatavalid             (kernel_svm.readdatavalid),
        .m0_burstcount                (kernel_svm.burstcount),
        .m0_writedata                 (kernel_svm.writedata),
        .m0_address                   (kernel_svm.address),
        .m0_write                     (kernel_svm.write),
        .m0_read                      (kernel_svm.read),
        .m0_byteenable                (kernel_svm.byteenable)
    );
`endif

//avmm pipeline for kernel cra
acl_avalon_mm_bridge_s10 #(
    .DATA_WIDTH                     ( OPENCL_BSP_KERNEL_CRA_DATA_WIDTH ),
    .SYMBOL_WIDTH                   ( 8   ),
    .HDL_ADDR_WIDTH                 ( OPENCL_BSP_KERNEL_CRA_ADDR_WIDTH  ),
    .BURSTCOUNT_WIDTH               ( 1   ),
    .SYNCHRONIZE_RESET              ( 1   ),
    .DISABLE_WAITREQUEST_BUFFERING  ( KERNELWRAPPER_CRA_PIPELINE_DISABLEWAITREQBUFFERING),
    .READDATA_PIPE_DEPTH            ( KERNELWRAPPER_CRA_PIPELINE_STAGES_RDDATA)
) kernel_cra_avalon_mm_bridge_s10 (
    .clk               (clk),
    .reset             (!reset_n),
    .s0_waitrequest    (opencl_kernel_control.kernel_cra_waitrequest  ),
    .s0_readdata       (opencl_kernel_control.kernel_cra_readdata     ),
    .s0_readdatavalid  (opencl_kernel_control.kernel_cra_readdatavalid),
    .s0_burstcount     (opencl_kernel_control.kernel_cra_burstcount   ),
    .s0_writedata      (opencl_kernel_control.kernel_cra_writedata    ),
    .s0_address        (opencl_kernel_control.kernel_cra_address      ),
    .s0_write          (opencl_kernel_control.kernel_cra_write        ),
    .s0_read           (opencl_kernel_control.kernel_cra_read         ),
    .s0_byteenable     (opencl_kernel_control.kernel_cra_byteenable   ),
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
    
    `ifdef PAC_BSP_ENABLE_DDR4_BANK1
        .kernel_ddr4a_waitrequest     (mem_avmm_bridge[0].waitrequest  ),
        .kernel_ddr4a_readdata        (mem_avmm_bridge[0].readdata     ),
        .kernel_ddr4a_readdatavalid   (mem_avmm_bridge[0].readdatavalid),
        .kernel_ddr4a_burstcount      (mem_avmm_bridge[0].burstcount   ),
        .kernel_ddr4a_writedata       (mem_avmm_bridge[0].writedata    ),
        .kernel_ddr4a_address         (mem_avmm_bridge[0].address      ),
        .kernel_ddr4a_write           (mem_avmm_bridge[0].write        ),
        .kernel_ddr4a_read            (mem_avmm_bridge[0].read         ),
        .kernel_ddr4a_byteenable      (mem_avmm_bridge[0].byteenable   ),
    `endif
    `ifdef PAC_BSP_ENABLE_DDR4_BANK2
        .kernel_ddr4b_waitrequest     (mem_avmm_bridge[1].waitrequest  ),
        .kernel_ddr4b_readdata        (mem_avmm_bridge[1].readdata     ),
        .kernel_ddr4b_readdatavalid   (mem_avmm_bridge[1].readdatavalid),
        .kernel_ddr4b_burstcount      (mem_avmm_bridge[1].burstcount   ),
        .kernel_ddr4b_writedata       (mem_avmm_bridge[1].writedata    ),
        .kernel_ddr4b_address         (mem_avmm_bridge[1].address      ),
        .kernel_ddr4b_write           (mem_avmm_bridge[1].write        ),
        .kernel_ddr4b_read            (mem_avmm_bridge[1].read         ),
        .kernel_ddr4b_byteenable      (mem_avmm_bridge[1].byteenable   ),
    `endif
    `ifdef PAC_BSP_ENABLE_DDR4_BANK3
        .kernel_ddr4c_waitrequest     (mem_avmm_bridge[2].waitrequest  ),
        .kernel_ddr4c_readdata        (mem_avmm_bridge[2].readdata     ),
        .kernel_ddr4c_readdatavalid   (mem_avmm_bridge[2].readdatavalid),
        .kernel_ddr4c_burstcount      (mem_avmm_bridge[2].burstcount   ),
        .kernel_ddr4c_writedata       (mem_avmm_bridge[2].writedata    ),
        .kernel_ddr4c_address         (mem_avmm_bridge[2].address      ),
        .kernel_ddr4c_write           (mem_avmm_bridge[2].write        ),
        .kernel_ddr4c_read            (mem_avmm_bridge[2].read         ),
        .kernel_ddr4c_byteenable      (mem_avmm_bridge[2].byteenable   ),
    `endif
    `ifdef PAC_BSP_ENABLE_DDR4_BANK4
        .kernel_ddr4d_waitrequest     (mem_avmm_bridge[3].waitrequest  ),
        .kernel_ddr4d_readdata        (mem_avmm_bridge[3].readdata     ),
        .kernel_ddr4d_readdatavalid   (mem_avmm_bridge[3].readdatavalid),
        .kernel_ddr4d_burstcount      (mem_avmm_bridge[3].burstcount   ),
        .kernel_ddr4d_writedata       (mem_avmm_bridge[3].writedata    ),
        .kernel_ddr4d_address         (mem_avmm_bridge[3].address      ),
        .kernel_ddr4d_write           (mem_avmm_bridge[3].write        ),
        .kernel_ddr4d_read            (mem_avmm_bridge[3].read         ),
        .kernel_ddr4d_byteenable      (mem_avmm_bridge[3].byteenable   ),
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
        `ifdef USM_DO_SINGLE_BURST_PARTIAL_WRITES
            ,.kernel_mem_waitrequest    (usm_avmm_buffer_almfull),
            .kernel_mem_readdata        (svm_avmm_bridge.readdata),
            .kernel_mem_readdatavalid   (svm_avmm_bridge.readdatavalid),
            .kernel_mem_burstcount      (svm_avmm_bridge_burstcount),
            .kernel_mem_writedata       (usm_avmm_cmd_from_kernelsystem.writedata),
            .kernel_mem_address         ({svm_avmm_bridge_address,svm_addr_shift}),
            .kernel_mem_write           (usm_avmm_cmd_from_kernelsystem.write),
            .kernel_mem_read            (usm_avmm_cmd_from_kernelsystem.read),
            .kernel_mem_byteenable      (usm_avmm_cmd_from_kernelsystem.byteenable)
        `else // not USM_DO_SINGLE_BURST_PARTIAL_WRITES
            ,.kernel_mem_waitrequest    (svm_avmm_bridge.waitrequest),
            .kernel_mem_readdata        (svm_avmm_bridge.readdata),
            .kernel_mem_readdatavalid   (svm_avmm_bridge.readdatavalid),
            .kernel_mem_burstcount      (svm_avmm_bridge_burstcount),
            .kernel_mem_writedata       (svm_avmm_bridge.writedata),
            .kernel_mem_address         ({svm_avmm_bridge_address,svm_addr_shift}),
            .kernel_mem_write           (kernel_system_svm_write),
            .kernel_mem_read            (kernel_system_svm_read),
            .kernel_mem_byteenable      (svm_avmm_bridge.byteenable)
        `endif // USM_DO_SINGLE_BURST_PARTIAL_WRITES
    `endif //INCLUDE_USM_SUPPORT
);

`ifdef INCLUDE_USM_SUPPORT
    `ifdef USM_DO_SINGLE_BURST_PARTIAL_WRITES
        
        typedef struct packed {
            logic [OPENCL_BSP_KERNEL_SVM_BURSTCOUNT_WIDTH-1:0] burstcount;
            logic valid;
            logic read;
            logic write;
        } usm_avmm_burstcnt_t;
        localparam USM_BCNT_DWIDTH = OPENCL_BSP_KERNEL_SVM_BURSTCOUNT_WIDTH + 1 + 1 + 1;
        usm_avmm_burstcnt_t [1:0] usm_burstcnt;
        usm_avmm_burstcnt_t usm_burstcnt_dout;
        logic [OPENCL_BSP_KERNEL_SVM_BURSTCOUNT_WIDTH-1:0] current_bcnt;
        logic [OPENCL_SVM_QSYS_ADDR_WIDTH-1:0] prev_address_plus1;
        localparam USM_BCNT_WDOG_WIDTH = 10;
        logic [USM_BCNT_WDOG_WIDTH-1:0] usm_burstcnt_wdog;
        logic usm_burstcnt_buffer_full, usm_burstcnt_buffer_almfull, usm_burstcnt_buffer_empty;
        logic [9:0] usm_burstcnt_buffer_usedw;
        typedef enum {  ST_SET_BCNT,
                        ST_DO_WR_BURST,
                        XXX } usm_bcnt_st_e;
        usm_bcnt_st_e usm_bcnt_cs, usm_bcnt_ns;
        logic usm_bcnt_st_is_setbcnt, usm_bcnt_st_is_do_wr_burst;
        logic [OPENCL_BSP_KERNEL_SVM_BURSTCOUNT_WIDTH-1:0] usm_avmm_fifo_rd_remaining;
        logic usm_avmm_fifo_rd, usm_bcnt_fifo_rd;
        logic [7:0] svm_addr_cnt;
        
        //Work around the PIM's partial-host-memory-write limitations
        always_comb begin
            usm_avmm_cmd_from_kernelsystem.address    = usm_avmm_cmd_from_kernelsystem.write ? svm_avmm_bridge_address + svm_addr_cnt : svm_avmm_bridge_address;
            usm_avmm_cmd_from_kernelsystem.burstcount = usm_avmm_cmd_from_kernelsystem.write ? 'h1 : svm_avmm_bridge_burstcount;
        end
        
        always_ff @(posedge clk or negedge reset_n) begin
            if (!reset_n) begin
                svm_addr_cnt <= 'h0;
            end else begin
                if (svm_addr_cnt == (svm_avmm_bridge_burstcount-'b1) ) begin
                    if (usm_avmm_cmd_from_kernelsystem.write) begin
                        svm_addr_cnt <= 'b0;
                    end else begin
                        svm_addr_cnt <= svm_addr_cnt;
                    end
                end else begin
                    svm_addr_cnt <= svm_addr_cnt + usm_avmm_cmd_from_kernelsystem.write;
                end
            end
        end
        
        //due to WRA I need to add a buffer here, using almost-full to generate waitrequest to kernel.
        logic usm_avmm_buffer_full, usm_avmm_buffer_almfull, usm_avmm_buffer_empty;
        logic [9:0] usm_avmm_buffer_usedw;
        scfifo
        #(
            .lpm_numwords(USM_AVMM_BUFFER_DEPTH),
            .lpm_showahead("ON"),
            .lpm_type("scfifo"),
            .lpm_width(USM_AVMM_BUFFER_WIDTH),
            .lpm_widthu($clog2(USM_AVMM_BUFFER_DEPTH)),
            .almost_full_value(USM_AVMM_BUFFER_ALMFULL_VALUE),
            .overflow_checking("OFF"),
            .underflow_checking("OFF"),
            .use_eab("ON"),
            .add_ram_output_register("ON")
            )
        usm_avmm_buffer
        (
            .clock(clk),
            .sclr(!reset_n),
    
            .data(usm_avmm_cmd_from_kernelsystem),
            .wrreq(usm_avmm_cmd_from_kernelsystem.write | usm_avmm_cmd_from_kernelsystem.read),
            .full(usm_avmm_buffer_full),
            .almost_full(usm_avmm_buffer_almfull),
    
            .rdreq(usm_avmm_fifo_rd),
            .q(usm_avmm_cmd_buf_out),
            .empty(usm_avmm_buffer_empty),
            .almost_empty(),
    
            .aclr(),
            .usedw(usm_avmm_buffer_usedw),
            .eccstatus()
        );
        
        always_comb begin
            kernel_system_svm_write = usm_avmm_fifo_rd & usm_avmm_cmd_buf_out.write;
            kernel_system_svm_read  = usm_avmm_fifo_rd & usm_avmm_cmd_buf_out.read;
            
            svm_avmm_bridge.address    = usm_avmm_cmd_buf_out.address;
            svm_avmm_bridge.writedata  = usm_avmm_cmd_buf_out.writedata;
            svm_avmm_bridge.burstcount = usm_avmm_cmd_buf_out.write ? usm_avmm_fifo_rd_remaining : usm_avmm_cmd_buf_out.burstcount;
            svm_avmm_bridge.byteenable = usm_avmm_cmd_buf_out.byteenable;
        end
        
        //re-create the burst-count data based on byteenable, address, and original burst-count
        //Every partial-write (where byteenable is not all 1's) must result in be a burst-count of '1'.
        //Other writes should be grouped together into maximal-sized bursts.
        //
        //
        
        always_ff @(posedge clk) begin
            if (!reset_n) begin
                usm_burstcnt <= 'h0;
                current_bcnt <= 'h1;
                prev_address_plus1 <= 'b0;
                usm_burstcnt_wdog <= 'b0;
            end else begin
                //when tracking a write-burst, we might need to flush it out because we don't know when the
                //write from the kernel-system is actually complete.
                usm_burstcnt_wdog <= current_bcnt > 'h1 ? {usm_burstcnt_wdog[0 +: (USM_BCNT_WDOG_WIDTH-1)], 1'b1} : '0;
                //push in a 0 to create a pulse for a follow-up partial write burstcount of 1
                //it will be over-written later in the block if/when necessary.
                usm_burstcnt[1] <= usm_burstcnt[0];
                usm_burstcnt[0].valid <= 1'b0;
                //if it is a read req from the kernel-system, just use that burstcount value
                if (usm_avmm_cmd_from_kernelsystem.read) begin
                    usm_burstcnt_wdog <= 'h0;
                    //if we were tracking a write-burst and a read comes in, send both the write and read in order
                    if (current_bcnt > 'h1) begin
                        usm_burstcnt[1].burstcount <= current_bcnt - 'b1;
                        usm_burstcnt[1].valid <= 1'b1;
                        usm_burstcnt[1].write <= 1'b1;
                        usm_burstcnt[1].read <= 1'b0;
                    end
                    usm_burstcnt[0].burstcount <= svm_avmm_bridge_burstcount;
                    usm_burstcnt[0].valid <= 1'b1;
                    usm_burstcnt[0].write <= 1'b0;
                    usm_burstcnt[0].read <= 1'b1;
                    current_bcnt <= 'h1;
                //if it is a write req from kernel-system, need to figure out the maximal burst
                end else if (usm_avmm_cmd_from_kernelsystem.write) begin
                    usm_burstcnt_wdog <= 'h0;
                    //if original burst-cnt is 1, leave it as 1
                    if (svm_avmm_bridge_burstcount == 'h1) begin
                        //if need to send the previous burst, too.
                        if (current_bcnt > 'h1) begin
                            usm_burstcnt[1].burstcount <= current_bcnt - 'b1;
                            usm_burstcnt[1].valid <= 1'b1;
                            usm_burstcnt[1].write <= 1'b1;
                            usm_burstcnt[1].read <= 1'b0;
                        end
                        usm_burstcnt[0].burstcount <= 'h1;
                        usm_burstcnt[0].valid <= 1'b1;
                        usm_burstcnt[0].write <= 1'b1;
                        usm_burstcnt[0].read  <= 1'b0;
                        current_bcnt <= 'h1;
                    //original burst-cnt is not 1; this is the first word of the burst
                    end else if (current_bcnt == 'h1) begin
                        if ( !(&usm_avmm_cmd_from_kernelsystem.byteenable) ) begin
                            usm_burstcnt[0].burstcount <= 'h1;
                            usm_burstcnt[0].valid <= 1'b1;
                            usm_burstcnt[0].write <= 1'b1;
                            usm_burstcnt[0].read <= 1'b0;
                        end else begin
                            prev_address_plus1 <= usm_avmm_cmd_from_kernelsystem.address + 'h1;
                            current_bcnt <= 'h2;
                        end
                    //if continuous address
                    end else if (prev_address_plus1 == usm_avmm_cmd_from_kernelsystem.address) begin
                        //if partial write, send burst and singleton
                        if ( !(&usm_avmm_cmd_from_kernelsystem.byteenable) ) begin
                            usm_burstcnt[1].burstcount <= current_bcnt - 'b1;
                            usm_burstcnt[1].valid <= 1'b1;
                            usm_burstcnt[1].write <= 1'b1;
                            usm_burstcnt[1].read <= 1'b0;
                            usm_burstcnt[0].burstcount <= 'h1;
                            usm_burstcnt[0].valid <= 1'b1;
                            usm_burstcnt[0].write <= 1'b1;
                            usm_burstcnt[0].read <= 1'b0;
                            current_bcnt <= 'h1;
                        //not a partial write and not a full burst, so keep adding to burstcount
                        end else if (current_bcnt < OPENCL_BSP_KERNEL_SVM_BURSTCOUNT_MAX) begin
                            current_bcnt <= current_bcnt + 'h1;
                        //full burst, so send burst and start again
                        end else begin
                            usm_burstcnt[0].burstcount <= current_bcnt;
                            usm_burstcnt[0].valid <= 1'b1;
                            usm_burstcnt[0].write <= 1'b1;
                            usm_burstcnt[0].read <= 1'b0;
                            current_bcnt <= 'h1;
                        end
                        prev_address_plus1 <= usm_avmm_cmd_from_kernelsystem.address + 'h1;
                    //not a continuous address, send the previous burst and start tracking the new one
                    end else begin
                        //if partial write, send burst and singleton
                        if ( !(&usm_avmm_cmd_from_kernelsystem.byteenable) ) begin
                            usm_burstcnt[1].burstcount <= current_bcnt - 'b1;
                            usm_burstcnt[1].valid <= 1'b1;
                            usm_burstcnt[1].write <= 1'b1;
                            usm_burstcnt[1].read <= 1'b0;
                            usm_burstcnt[0].burstcount <= 'h1;
                            usm_burstcnt[0].valid <= 1'b1;
                            usm_burstcnt[0].write <= 1'b1;
                            usm_burstcnt[0].read <= 1'b0;
                            current_bcnt <= 'h1;
                        //not partial burst, so send previous burst and continue tracking the new one
                        end else begin
                            usm_burstcnt[0].burstcount <= current_bcnt - 'b1;
                            usm_burstcnt[0].valid <= 1'b1;
                            usm_burstcnt[0].write <= 1'b1;
                            usm_burstcnt[0].read <= 1'b0;
                            current_bcnt <= 'h1;
                            prev_address_plus1 <= usm_avmm_cmd_from_kernelsystem.address + 'h1;
                        end
                    end
                //watchdog to flush out any final write request. 
                end else if (&usm_burstcnt_wdog) begin
                    usm_burstcnt[0].burstcount <= current_bcnt - 'b1;
                    usm_burstcnt[0].valid <= 1'b1;
                    usm_burstcnt[0].write <= 1'b1;
                    usm_burstcnt[0].read <= 1'b0;
                    current_bcnt <= 'h1;
                    usm_burstcnt_wdog <= 'b0;
                end
            end
        end
        
        //push the burst-count info into a scFIFO
        scfifo
        #(
            .lpm_numwords(USM_AVMM_BUFFER_DEPTH),
            .lpm_showahead("ON"),
            .lpm_type("scfifo"),
            .lpm_width(USM_BCNT_DWIDTH),
            .lpm_widthu($clog2(USM_AVMM_BUFFER_DEPTH)),
            .almost_full_value(USM_AVMM_BUFFER_ALMFULL_VALUE),
            .overflow_checking("OFF"),
            .underflow_checking("OFF"),
            .use_eab("ON"),
            .add_ram_output_register("ON")
            )
        usm_burstcnt_buffer
        (
            .clock(clk),
            .sclr(!reset_n),
    
            .data(usm_burstcnt[1]),
            .wrreq(usm_burstcnt[1].valid),
            .full(usm_burstcnt_buffer_full),
            .almost_full(usm_burstcnt_buffer_almfull),
    
            .rdreq(usm_bcnt_fifo_rd),
            .q(usm_burstcnt_dout),
            .empty(usm_burstcnt_buffer_empty),
            .almost_empty(),
    
            .aclr(),
            .usedw(usm_burstcnt_buffer_usedw),
            .eccstatus()
        );
        
        
        //will require some state machine to track coordination of popping from the 2 FIFOs
        // can't pop from the main FIFO until something exists in the bcnt FIFO.
        // for each entry in the bcnt FIFO, pop that number of elements from the main FIFO.
        // the main FIFO is populated prior to the bcnt FIFO having data, so we are guaranteed
        //   the main FIFO will always have enough data in it to satisfy the bcnt size.
        always_ff @(posedge clk)
            if (!reset_n)
                usm_bcnt_cs <= ST_SET_BCNT;
            else
                usm_bcnt_cs <= usm_bcnt_ns;
        
        always_comb begin
            usm_bcnt_ns = XXX;
            case (usm_bcnt_cs)
                ST_SET_BCNT:    if (!usm_burstcnt_buffer_empty && !svm_avmm_bridge.waitrequest) begin
                                    //if read or (bcnt == 1) stay here so we're ready 
                                    // for the next one on the next cycle
                                    if (usm_burstcnt_dout.read == 'b1 || 
                                        usm_burstcnt_dout.burstcount == 'h1) begin
                                        usm_bcnt_ns = ST_SET_BCNT;
                                    end else begin
                                        usm_bcnt_ns = ST_DO_WR_BURST;
                                    end
                                end else begin
                                    usm_bcnt_ns = ST_SET_BCNT;
                                end
                                //if final word of this burst and not waitreq
                ST_DO_WR_BURST: if (usm_avmm_fifo_rd_remaining == 'h1 && !svm_avmm_bridge.waitrequest) begin
                                    //if there is another burst waiting to go, stay here and start new burst
                                    if (!usm_burstcnt_buffer_empty && usm_burstcnt_dout.write == 'b1 && usm_burstcnt_dout.burstcount != 'h1) begin
                                        usm_bcnt_ns = ST_DO_WR_BURST;
                                    end else begin
                                        usm_bcnt_ns = ST_SET_BCNT;
                                    end
                                end else begin
                                    usm_bcnt_ns = ST_DO_WR_BURST;
                                end
            endcase
        end
        
        assign usm_bcnt_st_is_setbcnt = usm_bcnt_cs == ST_SET_BCNT;
        assign usm_bcnt_st_is_do_wr_burst = usm_bcnt_cs == ST_DO_WR_BURST;
        
        //use a counter to manage popping from the usm_avmm FIFO.
        always_ff @(posedge clk)
            if (!reset_n)
                usm_avmm_fifo_rd_remaining <= 'b0;
            else begin
                //if burstcount fifo isn't empty and !waitreq
                if (!usm_burstcnt_buffer_empty && !svm_avmm_bridge.waitrequest && (usm_bcnt_st_is_setbcnt || 
                   (usm_bcnt_st_is_do_wr_burst && usm_avmm_fifo_rd_remaining == 'h1) ) ) begin
                    usm_avmm_fifo_rd_remaining <= usm_burstcnt_dout.read ? 'h1 : usm_burstcnt_dout.burstcount;
                //pop from usm_avmm FIFO as long as the counter is non-zero and !waitreq
                end else if (usm_avmm_fifo_rd)
                    usm_avmm_fifo_rd_remaining <= usm_avmm_fifo_rd_remaining - 'h1;
                else 
                    usm_avmm_fifo_rd_remaining <= usm_avmm_fifo_rd_remaining;
            end

        //we know there is sufficient data in the usm_avmm FIFO because the bcnt FIFO isn't written-to until the 
        // original burst has been pushed into the usm_avmm FIFO.
        assign usm_avmm_fifo_rd = usm_avmm_fifo_rd_remaining && !svm_avmm_bridge.waitrequest;
        //pop the next usm_bcnt value when? When it is first popped, so that the next value is already 
        // waiting on the FIFO output when we are done with the current burst.
        assign usm_bcnt_fifo_rd =   !usm_burstcnt_buffer_empty && !svm_avmm_bridge.waitrequest && (usm_bcnt_st_is_setbcnt || 
                                    (usm_bcnt_st_is_do_wr_burst && usm_avmm_fifo_rd_remaining == 'h1) );
        
    `else
        always_comb begin
            svm_avmm_bridge.address    = svm_avmm_bridge_address;
            svm_avmm_bridge.burstcount = svm_avmm_bridge_burstcount;
        end
    `endif
    
    // Higher-level interfaces don't like 'X' during simulation. Drive 0's when not 
    // driven by the kernel-system.
    always_comb begin
        //drive with the value from the kernel-system by default
        svm_avmm_bridge.write = kernel_system_svm_write;
        svm_avmm_bridge.read  = kernel_system_svm_read;
        //drive with the modified version during simulation
    // synthesis translate off
        svm_avmm_bridge.write = kernel_system_svm_write === 'X ? 'b0 : kernel_system_svm_write;
        svm_avmm_bridge.read  = kernel_system_svm_read  === 'X ? 'b0 : kernel_system_svm_read;
    // synthesis translate on
    end
`endif

endmodule : kernel_wrapper
