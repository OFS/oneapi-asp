// Copyright 2022 Intel Corporation
// SPDX-License-Identifier: MIT
//

`include "platform_if.vh"
`include "fpga_defines.vh"
`include "opencl_bsp.vh"

// avmm_single_burst_partial_writes
// Split an AVMM interface's partial writes into a single partial-write and 
//  a re-grouped burst. Handles partial writes on either/or end of the burst
//  (start and/or end), as well as initial bursts of 1.

module avmm_single_burst_partial_writes  
import dc_bsp_pkg::*;
(
    input       clk,
    input       reset_n,

    ofs_plat_avalon_mem_if.to_source to_avmm_source,
    ofs_plat_avalon_mem_if.to_sink to_avmm_sink
);

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

//the readdata-path is just passed-through
always_comb begin
    to_avmm_source.readdata = to_avmm_sink.readdata;
    to_avmm_source.readdatavalid = to_avmm_sink.readdatavalid;
end

always_comb begin
    to_avmm_source.address    = to_avmm_source.write ? to_avmm_source.address + svm_addr_cnt : to_avmm_source.address;
    to_avmm_source.burstcount = to_avmm_source.write ? 'h1 : to_avmm_source.burstcount;
end

always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        svm_addr_cnt <= 'h0;
    end else begin
        if (svm_addr_cnt == (to_avmm_source.burstcount-'b1) ) begin
            if (to_avmm_source.write) begin
                svm_addr_cnt <= 'b0;
            end else begin
                svm_addr_cnt <= svm_addr_cnt;
            end
        end else begin
            svm_addr_cnt <= svm_addr_cnt + to_avmm_source.write;
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
    .wrreq(to_avmm_source.write | to_avmm_source.read),
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

//waitrequest is based on the almost-full signal from the scfifo
assign to_avmm_source.waitrequest = usm_avmm_buffer_almfull;

always_comb begin
    to_avmm_sink.write = usm_avmm_fifo_rd & usm_avmm_cmd_buf_out.write;
    to_avmm_sink.read  = usm_avmm_fifo_rd & usm_avmm_cmd_buf_out.read;
    //higher-level interfaces don't like 'X' during simulation. Drive 0's when not driven
    // by the kernel-system.
    // synthesis translate off
        to_avmm_sink.write = (usm_avmm_fifo_rd & usm_avmm_cmd_buf_out.write) === 'X ? 'b0 : kernel_system_svm_write;
        to_avmm_sink.read  = (usm_avmm_fifo_rd & usm_avmm_cmd_buf_out.read)  === 'X ? 'b0 : kernel_system_svm_read;
    // synthesis translate on
    
    to_avmm_sink.address    = usm_avmm_cmd_buf_out.address;
    to_avmm_sink.writedata  = usm_avmm_cmd_buf_out.writedata;
    to_avmm_sink.burstcount = usm_avmm_cmd_buf_out.write ? usm_avmm_fifo_rd_remaining : usm_avmm_cmd_buf_out.burstcount;
    to_avmm_sink.byteenable = usm_avmm_cmd_buf_out.byteenable;
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
        if (to_avmm_source.read) begin
            usm_burstcnt_wdog <= 'h0;
            //if we were tracking a write-burst and a read comes in, send both the write and read in order
            if (current_bcnt > 'h1) begin
                usm_burstcnt[1].burstcount <= current_bcnt - 'b1;
                usm_burstcnt[1].valid <= 1'b1;
                usm_burstcnt[1].write <= 1'b1;
                usm_burstcnt[1].read <= 1'b0;
            end
            usm_burstcnt[0].burstcount <= to_avmm_source.burstcount;
            usm_burstcnt[0].valid <= 1'b1;
            usm_burstcnt[0].write <= 1'b0;
            usm_burstcnt[0].read <= 1'b1;
            current_bcnt <= 'h1;
        //if it is a write req from kernel-system, need to figure out the maximal burst
        end else if (to_avmm_source.write) begin
            usm_burstcnt_wdog <= 'h0;
            //if original burst-cnt is 1, leave it as 1
            if (to_avmm_source.burstcount == 'h1) begin
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
                if ( !(&to_avmm_source.byteenable) ) begin
                    usm_burstcnt[0].burstcount <= 'h1;
                    usm_burstcnt[0].valid <= 1'b1;
                    usm_burstcnt[0].write <= 1'b1;
                    usm_burstcnt[0].read <= 1'b0;
                end else begin
                    prev_address_plus1 <= to_avmm_source.address + 'h1;
                    current_bcnt <= 'h2;
                end
            //if continuous address
            end else if (prev_address_plus1 == to_avmm_source.address) begin
                //if partial write, send burst and singleton
                if ( !(&to_avmm_source.byteenable) ) begin
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
                prev_address_plus1 <= to_avmm_source.address + 'h1;
            //not a continuous address, send the previous burst and start tracking the new one
            end else begin
                //if partial write, send burst and singleton
                if ( !(&to_avmm_source.byteenable) ) begin
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
                    prev_address_plus1 <= to_avmm_source.address + 'h1;
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
        ST_SET_BCNT:    if (!usm_burstcnt_buffer_empty && !to_avmm_sink.waitrequest) begin
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
        ST_DO_WR_BURST: if (usm_avmm_fifo_rd_remaining == 'h1 && !to_avmm_sink.waitrequest) begin
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
        if (!usm_burstcnt_buffer_empty && !to_avmm_sink.waitrequest && (usm_bcnt_st_is_setbcnt || 
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
assign usm_avmm_fifo_rd = usm_avmm_fifo_rd_remaining && !to_avmm_sink.waitrequest;
//pop the next usm_bcnt value when? When it is first popped, so that the next value is already 
// waiting on the FIFO output when we are done with the current burst.
assign usm_bcnt_fifo_rd =   !usm_burstcnt_buffer_empty && !to_avmm_sink.waitrequest && (usm_bcnt_st_is_setbcnt || 
                            (usm_bcnt_st_is_do_wr_burst && usm_avmm_fifo_rd_remaining == 'h1) );

    //`else
    //    always_comb begin
    //        to_avmm_sink.address    = to_avmm_source.address;
    //        to_avmm_sink.burstcount = to_avmm_source.burstcount;
    //    end
    //`endif
    
endmodule : avmm_single_burst_partial_writes
