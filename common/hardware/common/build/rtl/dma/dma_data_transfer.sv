// Copyright 2022 Intel Corporation
// SPDX-License-Identifier: MIT
//

`include "ofs_plat_if.vh"
`include "dma.vh"

/*
This module manages the data transfer of a single DMA channel - source to destination
 The high-level functional description is:
    - config data comes from the Dispatcher; push into a cmdQ; pop from cmdQ
    - when 'start' pulse is received, start reading data from the source-start address.
    - manipulate the read-back data to align it for writing to the destination.        
    - push the aligned data into a scfifo (single clock domain)
    - when the scfifo is not empty, pop the data and write it to an AVMM pipeline bridge.
    - connect the AVMM pipeline bridge to the destination
    - when complete, send flag back to Dispatcher and/or issue write-fence/IRQ as required.
*/

module dma_data_transfer #(
    parameter SRC_RD_BURSTCOUNT_MAX     = 'h4,
    parameter DST_WR_BURSTCOUNT_MAX     = 'h4,
    parameter SRC_ADDR_WIDTH            = 0,
    parameter DST_ADDR_WIDTH            = 0,
    parameter XFER_LENGTH_WIDTH         = 0,
    parameter DIR_FPGA_TO_HOST          = 1'b1,
    parameter DMA_CHANNEL_NUM           = 0
) (
    input clk,
    input reset,

    //CSR interface to Dispatcher
    dma_ctrl_intf.ctrl disp_ctrl_if,
    
    //all parallel transfers are done - issue host-mem-write 
    //(magic-number) for completion notification to mmd
    input all_transfers_complete,
    
    //data-source AVMM
    ofs_plat_avalon_mem_if.to_sink src_avmm,
    
    //data-destination AVMM
    ofs_plat_avalon_mem_if.to_sink dst_avmm
);

    //FSM and DMA-specific packages
    import dma_controller_rd_fsm_pkg::*;
    import dma_controller_wr_fsm_pkg::*;
    import dma_pkg::*;
    
    //constants for this instantiation
    localparam SRC_RD_BURSTCOUNT_MAX_BYTES = SRC_RD_BURSTCOUNT_MAX * HOSTMEM_DATA_BYTES_PER_WORD;
    localparam SRC_RD_BURSTCOUNT_MAX_SZ = $clog2(SRC_RD_BURSTCOUNT_MAX);
    localparam SRC_RD_MAX_BYTES_PER_BURST_IN_BITS = $clog2(SRC_RD_BURSTCOUNT_MAX_BYTES);
    localparam DST_WR_BURSTCOUNT_MAX_BYTES = DST_WR_BURSTCOUNT_MAX * HOSTMEM_DATA_BYTES_PER_WORD;
    localparam DST_WR_MAX_BYTES_PER_BURST_IN_BITS = $clog2(DST_WR_BURSTCOUNT_MAX_BYTES);
    //shifting pipeline flush count - takes into account the various pipeline/shifting stages between
    //receiving the readdata from the source and pushing it into the data-buffer.
    localparam PIPELINE_FLUSH_THRESHOLD = 6;
    //flow-control for the read-from-source state machine - stop issuing reads if the databuffer
    // can't handle future readdatavalid's without data being popped from the FIFO.
    localparam DATA_BUFFER_SKID_SPACE = SRC_RD_BURSTCOUNT_MAX > 16 ? 
                                            SRC_RD_BURSTCOUNT_MAX << 2 :
                                            SRC_RD_BURSTCOUNT_MAX << 4;
    localparam WORD_COUNTER_SIZE = XFER_LENGTH_WIDTH-HOSTMEM_DATA_BYTES_PER_WORD_BITSHIFT;
    
    //pipeline stages for the src/dst/len information
    dma_ctrl_intf 
        #(.SRC_ADDR_WIDTH(SRC_ADDR_WIDTH),
          .DST_ADDR_WIDTH(DST_ADDR_WIDTH) )
          cmdq_dout(), cmdq_dout_0();
          
    //internal src_avmm interface - output of the local pipeline bridge
    ofs_plat_avalon_mem_if
    #(
        `OFS_PLAT_AVALON_MEM_IF_REPLICATE_PARAMS(src_avmm)
    ) src_avmm_int();
    //internal dst_avmm interface - input to the avmm-pipeline bridge
    ofs_plat_avalon_mem_if
    #(
        `OFS_PLAT_AVALON_MEM_IF_REPLICATE_PARAMS(dst_avmm)
    ) dst_avmm_int();

    //pipeline the init steps of each command - calculations, comparisons, etc that can
    //occur prior to actually starting execution of the transfer.
    logic latch_this_cmd,cmdq_rdack;
    logic [3:0] latch_this_cmd_pre;
    logic [2:0] latch_this_cmd_post;
    
    logic cmdq_empty, cmdq_full;
    logic controller_busy;
    
    //interfaces that separate the address into words and bytes
    split_addr_intf #(.WIDTH(SRC_ADDR_WIDTH)) cmd_split_src_addr();
    split_addr_intf #(.WIDTH(DST_ADDR_WIDTH)) cmd_split_dst_addr();
    split_addr_intf #(.WIDTH(XFER_LENGTH_WIDTH)) usable_rd_xfer_length(),
                                                 usable_rd_xfer_length_reg(),
                                                 usable_wr_xfer_length(),
                                                 usable_wr_xfer_length_reg();
    
    logic [WORD_COUNTER_SIZE:0] read_xfer_cnt_in_words, 
                                read_xfer_cnt_in_words_reg,
                                write_xfer_cnt_in_words,
                                write_xfer_cnt_in_words_reg,
                                rd_xfer_remaining,
                                readdatavalid_cntr, 
                                read_requests_cntr,
                                databuf_writes_cntr,
                                dst_write_cntr,
                                dst_write_cntr_plus1,
                                dst_write_cntr_wire,
                                wr_xfer_remaining,
                                wr_xfer_remaining_next;
    
    rd_state_e rd_state_cur, rd_state_nxt;
    logic rd_state_cur_is_idle, rd_state_cur_is_read, rd_state_cur_is_waitforrxdata, 
            rd_state_cur_is_flushrddatapipe;
    logic flush_pipeline_counter_done;
    wr_state_e wr_state_cur, wr_state_nxt;
    logic wr_state_cur_is_idle, wr_state_cur_is_wait_for_write_burst_data, wr_state_cur_is_write, 
          wr_state_cur_is_a_write_data_state, wr_state_cur_is_write_magic_num, 
          wr_state_nxt_is_write_magic_num, wr_state_is_write_magic_num, 
          wr_state_nxt_is_wait_for_write_burst_data, wr_state_cur_is_wait_to_write_magic_num;
    logic this_is_last_dst_write,this_is_last_dst_write_plus1_reg,this_is_last_dst_write_reg;
    logic rd_reqs_complete,rd_reqs_complete_reg,rd_reqs_complete_wire;
    logic [AVMM_BURSTCOUNT_BITS-1:0] src_burst_cnt, next_src_burst_cnt;
    logic [8:0] read_data_shift_value_bytes,write_data_shift_value_bytes;
    logic [SRC_ADDR_WIDTH-1:0]  src_addr_cntr;
    logic controller_busy_d, controller_busy_falling_edge;
    logic [3:0] pipeline_flush_count;
    
    logic [$clog2(RDDATA_BUFFER_DEPTH):0]   outstanding_read_reqs, 
                                            free_space_in_databuf, 
                                            readreqs_update,
                                            readreqs_minus_readdatavalid;
    logic there_is_space_in_databuf;
    logic databuffer_wr_req;
    logic do_pipe_step_wire;
    logic [AVMM_BYTEENABLE_WIDTH-1:0] first_dst_byteenable_value, last_dst_byteenable_value;
    logic first_dst_write_is_partial, last_dst_write_is_partial, this_write_is_partial;
    logic [HOSTMEM_DATA_BYTES_PER_WORD_SZ:0] last_dst_write_byte_cnt;
    logic [HOSTMEM_DATA_BYTES_PER_WORD-1:0] dst_avmm_byteenable;
    
    logic src_avmm_int_readdatavalid;
    logic [AVMM_DATA_WIDTH-1:0] src_avmm_int_readdata;
    logic [DST_ADDR_WIDTH-1:0] dst_avmm_address;
    localparam DST_AVMM_BURSTCOUNT_BITS = $clog2(DST_WR_BURSTCOUNT_MAX);
    logic [DST_AVMM_BURSTCOUNT_BITS:0] dst_avmm_burstcount;
    logic databuf_has_enough_data_for_this_burst,databuf_has_enough_data_for_next_burst;
    logic successful_dst_int_write;
    logic this_is_first_burst_word;
    logic all_transfers_complete_latched;
    
    logic rst;
    assign rst = reset | disp_ctrl_if.sclr;
    
    //pipeline and duplicate the reset signal
    localparam RESET_PIPE_DEPTH = 4;
    logic [RESET_PIPE_DEPTH-1:0] rst_pipe;
    logic rst_local;
    always_ff @(posedge clk) begin
        {rst_local,rst_pipe}  <= {rst_pipe[RESET_PIPE_DEPTH-1:0], 1'b0};
        if (rst) begin
            rst_local <= '1;
            rst_pipe  <= '1;
        end
    end
    
    //latch the incoming all_transfers_complete signal until we've sent the magic number (if appropriate)
    always_ff @(posedge clk) begin
        if (wr_state_cur_is_idle)
            all_transfers_complete_latched <= 'b0;
        else if (all_transfers_complete)
            all_transfers_complete_latched <= 'b1;
        else
            all_transfers_complete_latched <= all_transfers_complete_latched;
        if (rst_local)
            all_transfers_complete_latched <= 'b0;
    end
    
    //
    //Buffer the incoming commands from the Dispatcher.
    //  Always write into the FIFO (the host has access to
    //  all of the FIFO status signals so should never overflow).
    //  The FIFO is showahead, so we are using the read-acknowledge to 
    //  pop the command from the FIFO and latch it into active use..
    //
    scfifo
    #(
`ifdef PLATFORM_INTENDED_DEVICE_FAMILY
        .intended_device_family(`PLATFORM_INTENDED_DEVICE_FAMILY),
`endif
        .lpm_numwords(CMDQ_DEPTH),
        .lpm_showahead("ON"),
        .lpm_type("scfifo"),
        .lpm_width(disp_ctrl_if.CMDQ_DATA_WIDTH),
        .lpm_widthu($clog2(CMDQ_DEPTH)),
        .almost_full_value(CMDQ_DEPTH - 'h2),
        .overflow_checking("OFF"),
        .underflow_checking("OFF"),
        .use_eab("ON"),
        .add_ram_output_register("ON")
        )
      cmd_pipeline
       (
        .clock(clk),
        .sclr(rst_local),

        .data(disp_ctrl_if.cmd),
        .wrreq(disp_ctrl_if.new_cmd),
        .full(cmdq_full),
        .almost_full(),

        .rdreq(cmdq_rdack),
        .q(cmdq_dout_0.cmd),
        .empty(cmdq_empty),
        .almost_empty(),

        .aclr(),
        .usedw(disp_ctrl_if.cmdq_status.usedw),
        .eccstatus()
    );
    //cmdQ status signals to the Dispatcher CSRs
    assign disp_ctrl_if.cmdq_status.empty = cmdq_empty;
    assign disp_ctrl_if.cmdq_status.full  = cmdq_full;
    always_ff @(posedge clk) begin
        if (rst_local) begin
            disp_ctrl_if.cmdq_status.underflow  <= 'b0;
            disp_ctrl_if.cmdq_status.overflow   <= 'b0;
        end else begin
            if (cmdq_empty && cmdq_rdack) 
                disp_ctrl_if.cmdq_status.underflow  <= 'b1;
            if (cmdq_full && disp_ctrl_if.new_cmd)
                disp_ctrl_if.cmdq_status.overflow  <= 'b1;
        end
    end
    
    //add another register stage on the output of the cmdQ FIFO.
    //This cmdq_dout.cmd data is what is actually used to control the transfer.
    always_ff @(posedge clk) begin
        if (rst_local)
            cmdq_dout.cmd <= 'b0;
        else if (latch_this_cmd_pre[0])
            cmdq_dout.cmd <= cmdq_dout_0.cmd;
    end
    
    //Pop descriptor from the cmdQ is not empty AND this data-transfer module 
    // is idle; only a single transfer is managed at a time.
    always_comb begin
        if (!cmdq_empty && !controller_busy)
            latch_this_cmd_pre[0] <= 'b1;
        else
            latch_this_cmd_pre[0] <= 'b0;
    end
    assign cmdq_rdack = latch_this_cmd_pre[0];
    
    //Pipeline the init steps - these signals are used for setup calculations to ease timing.
    always_ff @(posedge clk) begin
        latch_this_cmd_pre[3:1]     <= latch_this_cmd_pre[2:0];
        latch_this_cmd              <= latch_this_cmd_pre[3];
        latch_this_cmd_post[2:0]    <= {latch_this_cmd_post[1:0],latch_this_cmd};
    end
    
    //present the popped cmd data (src addr, dst addr, xfer length) in a split (word,byte) structure
    assign cmd_split_src_addr.sa = cmdq_dout.cmd.src_start_addr;
    assign cmd_split_dst_addr.sa = cmdq_dout.cmd.dst_start_addr;
    always_ff @(posedge clk) begin
        read_data_shift_value_bytes <= 63+cmd_split_src_addr.sa.byte_address;
        write_data_shift_value_bytes <= 127-cmd_split_dst_addr.sa.byte_address;
    end
    
    always_comb begin
        //the read-transfer length is actually the xfer_length value plus the source-address offset
        usable_rd_xfer_length.sa = cmdq_dout.cmd.xfer_length + cmd_split_src_addr.sa.byte_address;
        read_xfer_cnt_in_words = usable_rd_xfer_length_reg.sa.word_address + |usable_rd_xfer_length_reg.sa.byte_address;
    
        usable_wr_xfer_length.sa = cmdq_dout.cmd.xfer_length + cmd_split_dst_addr.sa.byte_address;
        write_xfer_cnt_in_words = usable_wr_xfer_length_reg.sa.word_address + |usable_wr_xfer_length_reg.sa.byte_address;
    end
    always_ff @(posedge clk) begin
        //the read-transfer length is actually the xfer_length value plus the source-address offset
        usable_rd_xfer_length_reg.sa <= usable_rd_xfer_length.sa;
        read_xfer_cnt_in_words_reg   <= read_xfer_cnt_in_words;
    
        //the write-transfer length is actually the xfer_length value plus the dest-address offset
        usable_wr_xfer_length_reg.sa <= usable_wr_xfer_length.sa;
        write_xfer_cnt_in_words_reg <= write_xfer_cnt_in_words;
    end
    
    ////
    // read data from the source memory location; push it into pipeline bridge, align it, then store it in scfifo
    //
    
    //AVMM pipeline bridge for source-reads
    logic src_avmm_write, src_avmm_read;
    acl_avalon_mm_bridge_s10 #(
        .DATA_WIDTH                     ( AVMM_DATA_WIDTH ),
        .SYMBOL_WIDTH                   ( 8   ),
        .HDL_ADDR_WIDTH                 ( SRC_ADDR_WIDTH ),
        .BURSTCOUNT_WIDTH               ( 7   ),
        .SYNCHRONIZE_RESET              ( 1   ),
        .READDATA_PIPE_DEPTH            ( 3   )
    ) src_avmm_pipeline_inst (
        .clk               (clk),
        .reset             (rst_local),
        .s0_waitrequest    (src_avmm_int.waitrequest  ),
        .s0_readdata       (src_avmm_int.readdata     ),
        .s0_readdatavalid  (src_avmm_int.readdatavalid),
        .s0_burstcount     (src_avmm_int.burstcount   ),
        .s0_writedata      (src_avmm_int.writedata    ),
        .s0_address        (src_avmm_int.address      ),
        .s0_write          (src_avmm_int.write        ),
        .s0_read           (src_avmm_int.read         ),
        .s0_byteenable     (src_avmm_int.byteenable   ),
        .m0_waitrequest    (src_avmm.waitrequest  ),
        .m0_readdata       (src_avmm.readdata     ),
        .m0_readdatavalid  (src_avmm.readdatavalid),
        .m0_burstcount     (src_avmm.burstcount   ),
        .m0_writedata      (src_avmm.writedata    ),
        .m0_address        (src_avmm.address      ),
        .m0_write          (src_avmm_write        ),
        .m0_read           (src_avmm_read         ),
        .m0_byteenable     (src_avmm.byteenable   )
    );
    // Higher-level interfaces don't like 'X' during simulation. Drive 0's when not 
    // driven by the bridge.
    always_comb begin
        //drive with the value from the kernel-system by default
        src_avmm.write = src_avmm_write;
        src_avmm.read  = src_avmm_read;
        //drive with the modified version during simulation
    // synthesis translate off
        src_avmm.write = src_avmm_write === 'X ? 'b0 : src_avmm_write;
        src_avmm.read  = src_avmm_read  === 'X ? 'b0 : src_avmm_read;
    // synthesis translate on
    end
    
    always_ff @(posedge clk) begin
        rd_state_cur <= rd_state_nxt;
        if (rst_local)    rd_state_cur <= IDLE;
    end

    always_comb begin
        rd_state_nxt = XXX;
        case (rd_state_cur)
            IDLE:   if (latch_this_cmd)         rd_state_nxt = READ;
                    else                        rd_state_nxt = IDLE;
            READ:   if (rd_reqs_complete)
                        rd_state_nxt = WAIT_FOR_RX_DATA;
                    else if (!there_is_space_in_databuf)
                        rd_state_nxt = PAUSE_READ;
                    else
                        rd_state_nxt = READ;
            PAUSE_READ: 
                    if (rd_reqs_complete)
                        rd_state_nxt = WAIT_FOR_RX_DATA;
                    else if (there_is_space_in_databuf)
                        rd_state_nxt = READ;
                    else
                        rd_state_nxt = PAUSE_READ;
            WAIT_FOR_RX_DATA:
                    if (readdatavalid_cntr > 'b0)
                        rd_state_nxt = WAIT_FOR_RX_DATA;
                    else
                        rd_state_nxt = FLUSH_RD_DATA_PIPE;
            FLUSH_RD_DATA_PIPE:
                    if (flush_pipeline_counter_done)
                        rd_state_nxt = IDLE;
                    else
                        rd_state_nxt = FLUSH_RD_DATA_PIPE;
        endcase
    end
    always_comb begin
        rd_state_cur_is_idle            = rd_state_cur == IDLE;
        rd_state_cur_is_read            = rd_state_cur == READ;
        rd_state_cur_is_waitforrxdata   = rd_state_cur == WAIT_FOR_RX_DATA;
        rd_state_cur_is_flushrddatapipe = rd_state_cur == FLUSH_RD_DATA_PIPE;
    end
    //pop the next cmd when the rd and wr components of the transfer controller are idle
    assign disp_ctrl_if.controller_busy_rd = !rd_state_cur_is_idle;
    
    //when wait-req is low, increment the next src-address by the burst-cnt (on a word-boundary)
    always_ff @(posedge clk) begin
        if (latch_this_cmd)
            src_addr_cntr <= cmdq_dout.cmd.src_start_addr;
        else if (src_avmm_int.read && !src_avmm_int.waitrequest) begin
            src_addr_cntr <= src_addr_cntr + (src_burst_cnt << HOSTMEM_DATA_BYTES_PER_WORD_BITSHIFT);
        end
    end
    
    //control burst-count
    //if the original xfer length is shorter than a full burst, that length is the burst size.
    //else if the last xfer length is shorter than a full burst, that length is the burst size.
    //else use the full burst size
    always_ff @(posedge clk) begin
        if (latch_this_cmd) begin
            if ( read_xfer_cnt_in_words_reg <= SRC_RD_BURSTCOUNT_MAX ) begin //first transfer, small
                //if transfer-length is less than a full burst, set burst-count to the number of 
                //  valid words plus any leftover bytes (if applicable); so we are rounding up.
                src_burst_cnt <= read_xfer_cnt_in_words_reg;
            end else //first transfer, and it isn't small
                src_burst_cnt <= SRC_RD_BURSTCOUNT_MAX;
        //if the AVMM-sink asserts waitrequest, hold the current value
        end else if (src_avmm_int.read & !src_avmm_int.waitrequest)
            src_burst_cnt <= next_src_burst_cnt;
        else
            src_burst_cnt <= src_burst_cnt;
    end
    always_comb begin
        if (rd_xfer_remaining < SRC_RD_BURSTCOUNT_MAX)
            next_src_burst_cnt <= rd_xfer_remaining;
        else
            next_src_burst_cnt <= SRC_RD_BURSTCOUNT_MAX;
    end
    
    //read bytes remaining countdown
    always_ff @(posedge clk) begin
        if (latch_this_cmd) begin
            if (read_xfer_cnt_in_words_reg <= SRC_RD_BURSTCOUNT_MAX)
                rd_xfer_remaining <= '0;
            else
                rd_xfer_remaining <= read_xfer_cnt_in_words_reg - SRC_RD_BURSTCOUNT_MAX;
        end else if (src_avmm_int.read && !src_avmm_int.waitrequest) begin
            if (rd_xfer_remaining <= SRC_RD_BURSTCOUNT_MAX)
                rd_xfer_remaining <= 'b0;//the end; don't decrement into negative numbers
            else
                rd_xfer_remaining <= rd_xfer_remaining - SRC_RD_BURSTCOUNT_MAX;
        end
        if (rst_local) rd_xfer_remaining <= 'b0;
    end
    logic rd_xfer_remaining_hi_bits;
    always_ff @(posedge clk) begin
        if (latch_this_cmd) begin
            if (read_xfer_cnt_in_words_reg <= SRC_RD_BURSTCOUNT_MAX)
                rd_xfer_remaining_hi_bits <= 'b0;
            //we know it is greater than SRC_RD_BURSTCOUNT_MAX but we don't care about precision
            else
                rd_xfer_remaining_hi_bits <= |read_xfer_cnt_in_words_reg;
        end else
            rd_xfer_remaining_hi_bits <= |rd_xfer_remaining[WORD_COUNTER_SIZE:SRC_RD_BURSTCOUNT_MAX_SZ+2];
    end
    
    //flag to indicate we have issued all the needed read requests
    always_ff @(posedge clk) begin
        if (controller_busy_falling_edge)
            rd_reqs_complete_reg <= 1'b0;
        else
            rd_reqs_complete_reg <= rd_reqs_complete_wire;
        
        if (rst_local) rd_reqs_complete_reg <= 1'b0;
    end
    assign rd_reqs_complete_wire = !(rd_xfer_remaining_hi_bits || rd_xfer_remaining[SRC_RD_BURSTCOUNT_MAX_SZ+2:0])
                                    && src_avmm_int.read && !src_avmm_int.waitrequest;
    assign rd_reqs_complete = rd_reqs_complete_wire || rd_reqs_complete_reg;

    //AVMM signals
    always_comb begin
        src_avmm_int.read = rd_state_cur_is_read;
        src_avmm_int.address = src_addr_cntr;
        src_avmm_int.burstcount = src_burst_cnt;
        src_avmm_int.byteenable = '1;
        //disable the write-signals as we are only reading from this memory with this controller (the
        // other DMA controller will write to this memory)
        src_avmm_int.write = '0;
        src_avmm_int.writedata = '0;
    end
    
    //the above code has issued the read-requests to the source memory.
    //the below code will receive the read-data/read-data-valid from the source memory.
    
    //register the incoming readdata and readdatavalid signals from the source.
    always_ff @(posedge clk) begin
        src_avmm_int_readdatavalid  <= src_avmm_int.readdatavalid;
        src_avmm_int_readdata       <= src_avmm_int.readdata;
        if (rst_local) begin
            src_avmm_int_readdatavalid  <= 'b0;
        end
    end
    
    //track the number of outstanding read requests sent to the source memory
    //  If new cmd, clear the tracker to 0.
    //  Else-if read & !waitreq, add the burstcount (and subtract the readdatavalid signal 
    //      in case we are getting a previous read back)
    //  Else decrement when readdatavalid is set.
    always_ff @(posedge clk) begin
        if (latch_this_cmd) 
            outstanding_read_reqs <= 'b0;
        else if (src_avmm_int.read && !src_avmm_int.waitrequest) 
            outstanding_read_reqs <= readreqs_update;
        else 
            outstanding_read_reqs <= readreqs_minus_readdatavalid;
    end
    assign readreqs_minus_readdatavalid = outstanding_read_reqs - src_avmm_int_readdatavalid;
    assign readreqs_update = readreqs_minus_readdatavalid + src_avmm_int.burstcount;
    
    //compare the outstanding_read_reqs tracker with the usedw output from the data_buffer FIFO
    always_ff @(posedge clk) begin
        if (latch_this_cmd)
            there_is_space_in_databuf <= 'b1;
        else if ( free_space_in_databuf > (outstanding_read_reqs + DATA_BUFFER_SKID_SPACE) )
            there_is_space_in_databuf <= 'b1;
        else
            there_is_space_in_databuf <= 'b0;
    end
    always_ff @(posedge clk) begin
        free_space_in_databuf <= (RDDATA_BUFFER_DEPTH - disp_ctrl_if.databuf_status.usedw);
        if (rst_local) free_space_in_databuf <= RDDATA_BUFFER_DEPTH;
    end
    
    //track the number of readdatavalid assertions we receive - this is the number of 512-bit 
    //  words have received from source memory. This is used to transition from the 
    //  WAIT_FOR_RX_DATA state to the FLUSH_RD_DATA_PIPE state.
    always_ff @(posedge clk) begin
        if (latch_this_cmd)
            readdatavalid_cntr <= read_xfer_cnt_in_words_reg;
        else
            readdatavalid_cntr <= readdatavalid_cntr - src_avmm_int_readdatavalid;
    end
    assign disp_ctrl_if.src_readdatavalid_counter = readdatavalid_cntr;
    
    //track the total number of read-requests we have issued for this command. This is only 
    // used for CSR information.
    always_ff @(posedge clk) begin
        if (latch_this_cmd)
            read_requests_cntr <= 'b0;
        else if (src_avmm_int.read & !src_avmm_int.waitrequest)
            read_requests_cntr <= read_requests_cntr + src_avmm_int.burstcount;
    end
    assign disp_ctrl_if.src_burst_cnt_counter = read_requests_cntr;
    
    //
    // buffer the read-back data after aligning it to be written to destination
    //  Align to the RHS/0 first; then align to the destination offset
    logic [9:0] pipeline_shifter;
    logic [AVMM_DATA_WIDTH-1:0] rddata_pipeline_stage0;
    logic [AVMM_DOUBLE_DATA_WIDTH-1:0] double_width_readdata;
    
    always_ff @(posedge clk) begin
        if (latch_this_cmd | flush_pipeline_counter_done)
            pipeline_shifter <= 'b0;
        else if (do_pipe_step_wire)
            pipeline_shifter <= {pipeline_shifter[8:0], 1'b1};

        if (rst_local) pipeline_shifter <= 'b0;
    end
    
    assign do_pipe_step_wire = src_avmm_int_readdatavalid | rd_state_cur_is_flushrddatapipe;
    
    always_ff @(posedge clk) begin
        if (latch_this_cmd)
            pipeline_flush_count <= 'b0;
        else
            pipeline_flush_count <= pipeline_flush_count + rd_state_cur_is_flushrddatapipe;
    end
    always_comb begin
        flush_pipeline_counter_done = pipeline_flush_count == PIPELINE_FLUSH_THRESHOLD;
    end
    
    //first stage of pipelining the incoming readdata from source.
    always_ff @(posedge clk) begin
        if (do_pipe_step_wire)
            rddata_pipeline_stage0 <= src_avmm_int_readdata;
    end
    
    //second/third stages - double the data width (in order to find the aligned source address)
    always_ff @(posedge clk) begin
        if (pipeline_shifter[0] && do_pipe_step_wire)
            double_width_readdata <= {rddata_pipeline_stage0, 
                                      double_width_readdata[AVMM_DBL_DATA_UWORD_BIT_HI:AVMM_DBL_DATA_UWORD_BIT_LO]};
    end
    
    //treat the double-wide data in terms of bytes rather than bits
    typedef logic [7:0]       t_my_byte;
    typedef t_my_byte [AVMM_DATA_WIDTH_IN_BYTES-1:0]  t_data_word;
    typedef t_my_byte [AVMM_DOUBLE_DATA_WIDTH_IN_BYTES-1:0] t_double_data_word;
    t_double_data_word dbl_readdata_bytes, dbl_writedata;
    t_data_word zero_aligned_readdata_bytes, shifted_write_data_bytes;
    
    assign dbl_readdata_bytes = double_width_readdata;
    
    //fourth stage - register the zero-aligned data.
    always_ff @(posedge clk) begin
        if (pipeline_shifter[2] && do_pipe_step_wire) begin
            zero_aligned_readdata_bytes <= dbl_readdata_bytes[read_data_shift_value_bytes-:AVMM_DATA_WIDTH_IN_BYTES];
        end
    end
    
    //fifth/sixth stages - double this aligned data (in order to find the destination-offset data_word)
    //now that the read-back data is zero-aligned (with right-shifts), prepare it for writing to the 
    //  destination with left-shifts.
    always_ff @(posedge clk) begin
        if (pipeline_shifter[3] && do_pipe_step_wire) begin
            dbl_writedata <= {zero_aligned_readdata_bytes, 
                              dbl_writedata[AVMM_DBL_DATA_UWORD_BYTES_BIT_HI:AVMM_DBL_DATA_UWORD_BYTES_BIT_LO]};
        end
    end
    
    //final pipeline stage - this registered data should now be aligned to the desired 
    //  destination address offset. Push it into a FIFO for the dst/wr FSM to manage.
    always_ff @(posedge clk) begin
        if (pipeline_shifter[4] && do_pipe_step_wire) begin
            shifted_write_data_bytes <= dbl_writedata[write_data_shift_value_bytes-:AVMM_DATA_WIDTH_IN_BYTES];
        end
    end
    
    //
    // Data buffer tracking and control
    //track the writes into the data buffer; stop after write_xfer_cnt_in_words_reg
    always_ff @(posedge clk) begin
        if (latch_this_cmd)
            databuf_writes_cntr <= write_xfer_cnt_in_words_reg;
        else if (databuffer_wr_req)
            databuf_writes_cntr <= databuf_writes_cntr - 'b1;
    end
    logic databuf_writes_cntr_hi_bits;
    always_ff @(posedge clk) begin
        databuf_writes_cntr_hi_bits <= |databuf_writes_cntr[WORD_COUNTER_SIZE:2];
    end
    
    //push into the databuffer when the pipeline is full and we rx new data or during flush
    assign databuffer_wr_req = pipeline_shifter[5] && 
                               (databuf_writes_cntr_hi_bits || |databuf_writes_cntr[1:0]) &&
                               do_pipe_step_wire;

    logic [src_avmm_int.DATA_WIDTH_-1:0] databuffer_q;
    logic databuffer_rdack, databuffer_empty;
    logic [$clog2(RDDATA_BUFFER_DEPTH)-1:0] local_databuf_usedw,local_databuf_usedw_next;
    scfifo
    #(
`ifdef PLATFORM_INTENDED_DEVICE_FAMILY
        .intended_device_family(`PLATFORM_INTENDED_DEVICE_FAMILY),
`endif
        .lpm_numwords(RDDATA_BUFFER_DEPTH),
        .lpm_showahead("ON"),
        .lpm_type("scfifo"),
        .lpm_width(AVMM_DATA_WIDTH),
        .lpm_widthu($clog2(RDDATA_BUFFER_DEPTH)),
        .almost_full_value(RDDATA_BUFFER_DEPTH - 'h2),
        .overflow_checking("OFF"),
        .underflow_checking("OFF"),
        .use_eab("ON"),
        .add_ram_output_register("ON")
        )
      data_buffer_shifted
       (
        .clock(clk),
        .sclr(rst_local | latch_this_cmd),

        .data(shifted_write_data_bytes),
        .wrreq(databuffer_wr_req),
        .full(disp_ctrl_if.databuf_status.full),
        .almost_full(),

        .rdreq(databuffer_rdack),
        .q(databuffer_q),
        .empty(databuffer_empty),
        .almost_empty(),

        .aclr(),
        .usedw(disp_ctrl_if.databuf_status.usedw),
        .eccstatus()
    );
    
    always_ff @(posedge clk) begin
        if (rst_local)
            disp_ctrl_if.databuf_status.usedw_highwater_mark <= 'b0;
        else if (disp_ctrl_if.databuf_status.usedw > disp_ctrl_if.databuf_status.usedw_highwater_mark)
            disp_ctrl_if.databuf_status.usedw_highwater_mark <= disp_ctrl_if.databuf_status.usedw;
    end
    
    //FIFO overflow detection. Sticky bit until sw resets it.
    always_ff @(posedge clk) begin
        if (disp_ctrl_if.databuf_status.full && databuffer_wr_req) disp_ctrl_if.databuf_status.overflow <= 'b1;
        if (rst_local)                                             disp_ctrl_if.databuf_status.overflow <= 'b0;
    end
    always_ff @(posedge clk) begin
        if (disp_ctrl_if.databuf_status.empty && databuffer_rdack) disp_ctrl_if.databuf_status.underflow <= 'b1;
        if (rst_local)                                             disp_ctrl_if.databuf_status.underflow <= 'b0;
    end
    
    assign disp_ctrl_if.databuf_status.empty = databuffer_empty;
    
    //
    // write data to the destination memory location
    //
    
    //pre-calculate a few values to save effort later. 
    //  - first word's byteenable value
    //  - middle/full word's byteenable value
    //  - last word's byteenable value
    //  - number of set-bits in first byteenable
    //  - number of set-bits in middle/full byteenable
    //  - number of set-bits in last byteenable
    //calculate the first and last byteenable values and hold them in registers until they are needed
    always_ff @(posedge clk) begin
        first_dst_byteenable_value <= FIND_FIRST_WR_BYTEENABLE(cmdq_dout.cmd.dst_start_addr, cmdq_dout.cmd.xfer_length);
        //is the first write word full or partial?
        first_dst_write_is_partial <= ! (&first_dst_byteenable_value);
    end
    
    //take one clock to calculate the number of bytes we will be writing in the final dst-write; then use
    // that value to pre-calculate the byteenable value that will be used when the time comes.
    always_ff @(posedge clk) begin
        //if the byte-offsets/lengths equal 0 bytes, the word is full
        if (!(usable_wr_xfer_length_reg.sa.byte_address))
            last_dst_write_byte_cnt <= HOSTMEM_DATA_BYTES_PER_WORD;
        else
            last_dst_write_byte_cnt <=  usable_wr_xfer_length_reg.sa.byte_address;
        if (rst_local) last_dst_write_byte_cnt <= HOSTMEM_DATA_BYTES_PER_WORD;
    end
    always_ff @(posedge clk) begin
        last_dst_byteenable_value  <= FIND_LAST_WR_BYTEENABLE(last_dst_write_byte_cnt);
        //is the last write word full or partial?
        last_dst_write_is_partial  <= ! (&last_dst_byteenable_value);
    end
    
    //
    //FSM handling the write-logic (pop data from FIFO, push to AVMM pipeline bridge)
    always_ff @(posedge clk) begin
        wr_state_cur <= wr_state_nxt;
        if (rst_local)    wr_state_cur <= WIDLE;
    end
        
    always_comb begin
        wr_state_nxt = WXXX;
        case (wr_state_cur)
            WIDLE:  
                if (latch_this_cmd)         
                    wr_state_nxt = WAIT_FOR_WRITE_BURST_DATA;
                else                        
                    wr_state_nxt = WIDLE;
            WAIT_FOR_WRITE_BURST_DATA:
                //if we have enough data for a complete burst (either a max burst or the only/final burst)
                if (databuf_has_enough_data_for_this_burst)
                    wr_state_nxt = WRITE_COMPLETE_BURST;
                //else we don't have enough data to send the entire burst; so we wait for more read-responses
                else
                    wr_state_nxt = WAIT_FOR_WRITE_BURST_DATA;
            WRITE_COMPLETE_BURST:
                //if end of this burst, check what to do next based on databuf.usedw and wr_xfer_remaining
                if (dst_avmm_int.burstcount == 'h1 && successful_dst_int_write) begin
                    //if we done sending data? Go back to idle or send magic-number
                    if (!wr_xfer_remaining_next) begin
                        if (DIR_FPGA_TO_HOST & DO_F2H_MAGIC_NUMBER_WRITE & (DMA_CHANNEL_NUM==0) )
                            wr_state_nxt = WAIT_TO_WRITE_MAGIC_NUM;
                        else
                            wr_state_nxt = WIDLE;
                    end
                    //elif there will be more data to send, but do we have enough in the databuf to send the 
                    //  next complete burst?
                    else if (databuf_has_enough_data_for_next_burst)
                        wr_state_nxt = WRITE_COMPLETE_BURST;
                    //else we don't have enough data for the next complete burst, so we need to wait
                    else
                        wr_state_nxt = WAIT_FOR_WRITE_BURST_DATA;
                end
                //else we are mid-burst, stay here until we're done
                else    
                    wr_state_nxt = WRITE_COMPLETE_BURST;
            WAIT_TO_WRITE_MAGIC_NUM:
                if (all_transfers_complete_latched)
                    wr_state_nxt = WRITE_MAGIC_NUM;
                else
                    wr_state_nxt = WAIT_TO_WRITE_MAGIC_NUM;
            WRITE_MAGIC_NUM: 
                if (successful_dst_int_write) 
                    wr_state_nxt = WIDLE;
                else
                    wr_state_nxt = WRITE_MAGIC_NUM;
        endcase
    end
    //We only want to write data when we have enough for a full burst (even if 'full' means 1 or less than
    // a maximal burst due to protocol translation limitations elsewhere). 
    //So, assert a signal when: - databuf usedw is greater than the maximal-burstcount OR
    //                          - databuf usedw is equal to the number of remaining writes OR
    //                          - F2H direction and the first write-word is partial and databuf usedw == 1
    assign databuf_has_enough_data_for_this_burst = (local_databuf_usedw >= DST_WR_BURSTCOUNT_MAX) |
                                                    (local_databuf_usedw == wr_xfer_remaining) |
                                                    (DIR_FPGA_TO_HOST & (local_databuf_usedw >= 'h1) & first_dst_write_is_partial & this_is_first_burst_word);
    assign databuf_has_enough_data_for_next_burst = (local_databuf_usedw_next >= DST_WR_BURSTCOUNT_MAX) |
                                                    (local_databuf_usedw_next == wr_xfer_remaining);
    always_comb begin
        wr_state_cur_is_idle                 = wr_state_cur == WIDLE;
        wr_state_cur_is_wait_for_write_burst_data = wr_state_cur == WAIT_FOR_WRITE_BURST_DATA;
        wr_state_nxt_is_wait_for_write_burst_data = wr_state_nxt == WAIT_FOR_WRITE_BURST_DATA;
        wr_state_cur_is_write                = wr_state_cur == WRITE_COMPLETE_BURST;
        wr_state_cur_is_a_write_data_state   = wr_state_cur_is_wait_for_write_burst_data | wr_state_cur_is_write;
        wr_state_cur_is_wait_to_write_magic_num = wr_state_cur == WAIT_TO_WRITE_MAGIC_NUM;
        wr_state_cur_is_write_magic_num      = wr_state_cur == WRITE_MAGIC_NUM;
        wr_state_nxt_is_write_magic_num      = wr_state_nxt == WRITE_MAGIC_NUM;
        wr_state_is_write_magic_num          = wr_state_cur_is_write_magic_num | wr_state_nxt_is_write_magic_num;
    end
    assign disp_ctrl_if.controller_busy_wr = !wr_state_cur_is_idle;
    
    //track the data-buffer usedw separate from the FF's counter, taking current-clock push/pop activity into account
    logic [3:0] databuffer_wr_req_d;
    always_ff @(posedge clk) begin
        if (rst_local)
            local_databuf_usedw <= 'b0;
        else if (latch_this_cmd)
            local_databuf_usedw <= 'b0;
        else
            local_databuf_usedw <= local_databuf_usedw_next;
    end
    always_comb begin
        //if we get both a push and a pop on the same cycle, don't change the counter
        if (databuffer_wr_req_d[3] & databuffer_rdack)
            local_databuf_usedw_next = local_databuf_usedw;
        //if just a push into the databuf fifo, increment the counter
        else if (databuffer_wr_req_d[3])
            local_databuf_usedw_next = local_databuf_usedw + 'b1;
        //if just a pop from the databuf fifo, decrement the counter
        else if (databuffer_rdack)
            local_databuf_usedw_next = local_databuf_usedw - 'b1;
        else
            local_databuf_usedw_next = local_databuf_usedw;
    end
    //delay databuffer_wr_req so we don't pop too eagerly
    always_ff @(posedge clk) begin
        if (rst_local) databuffer_wr_req_d <= 'b0;
        else           databuffer_wr_req_d <= {databuffer_wr_req_d[2:0],databuffer_wr_req};
    end
    
    //we should never get into the write-magic-num state if DIR_FPGA_TO_HOST is '0'.
    // synthesis translate_off
    always_comb begin
        if ( ( !DIR_FPGA_TO_HOST | (DIR_FPGA_TO_HOST & DO_F2H_MAGIC_NUMBER_WRITE & (DMA_CHANNEL_NUM != 0)) ) && (wr_state_is_write_magic_num) )
            $fatal("dma_data_transfer.sv: DIR_FPGA_TO_HOST is %s and DMA_CHANNEL_NUM is %s: We should never get into the write-magic-number state in the H2F DMA channel!", DIR_FPGA_TO_HOST, DMA_CHANNEL_NUM);
    end
    // synthesis translate_on
    
    //
    // pop data from databuffer; write it to the destination memory
    //
    //pop data from the databuf when we've written it out of the block (and waitreq isn't asserted)
    assign databuffer_rdack = successful_dst_int_write && !wr_state_cur_is_write_magic_num;
                              //&& !wr_state_nxt_is_wait_for_write_burst_data;
    
    always_comb begin
        dst_avmm_int.write      = wr_state_cur_is_write | wr_state_cur_is_write_magic_num;
        dst_avmm_int.writedata  = wr_state_cur_is_write_magic_num ? MAGIC_NUMBER : databuffer_q;
        dst_avmm_int.byteenable = dst_avmm_byteenable;
        dst_avmm_int.address    = dst_avmm_address;
        dst_avmm_int.burstcount = this_write_is_partial ? 'h1 : dst_avmm_burstcount;
        //tie off read-related signals since this interface will never issue any reads from the destination.
        dst_avmm_int.read       = 'b0;
    end
    
    //common signals
    //destination write and not waitreq
    assign successful_dst_int_write = dst_avmm_int.write && !dst_avmm_int.waitrequest;
    
    assign this_write_is_partial = ! (&dst_avmm_byteenable);
    
    //track the number of dst-writes; determine when we've reached the final write.
    always_ff @(posedge clk) begin
        if (latch_this_cmd) begin
            dst_write_cntr                   <= 'b0;
            this_is_last_dst_write_reg       <= 'b0;
            dst_write_cntr_plus1             <= 'b0;
            this_is_last_dst_write_plus1_reg <= 'b0;
        end else begin
            dst_write_cntr                   <= dst_write_cntr_wire;
            this_is_last_dst_write_reg       <= dst_write_cntr_wire == write_xfer_cnt_in_words_reg;
            dst_write_cntr_plus1             <= dst_write_cntr_wire + 'b1;
            this_is_last_dst_write_plus1_reg <= (dst_write_cntr_wire + 'b1) == write_xfer_cnt_in_words_reg;
        end
        
        if (rst_local) dst_write_cntr <= 'b0;
    end
    assign disp_ctrl_if.dst_write_counter = dst_write_cntr;
    assign dst_write_cntr_wire = successful_dst_int_write ? 
                                    dst_write_cntr_plus1 :
                                    dst_write_cntr;
    assign this_is_last_dst_write = successful_dst_int_write ? 
                                    this_is_last_dst_write_plus1_reg :
                                    this_is_last_dst_write_reg;
    
    always_ff @(posedge clk) begin
        if (latch_this_cmd)
            this_is_first_burst_word <= 1'b1;
        else if (DIR_FPGA_TO_HOST & wr_state_cur_is_write && 
                 dst_avmm_int.burstcount == 'h1 && successful_dst_int_write)
            this_is_first_burst_word <= 1'b0;
        else if (!DIR_FPGA_TO_HOST & wr_state_cur_is_write && successful_dst_int_write)
            this_is_first_burst_word <= 1'b0;
    end
    
    always_comb begin
        if (this_is_first_burst_word)
            dst_avmm_byteenable = first_dst_byteenable_value;
        else if (this_is_last_dst_write)
            dst_avmm_byteenable = last_dst_byteenable_value;
        else if (wr_state_cur_is_write_magic_num) //64-bit write-data
            dst_avmm_byteenable = MAGIC_NUMBER_BYTEENBLE_VALUE;
        else
            dst_avmm_byteenable = '1;
    end
    
    //wr-address counter
    always_ff @(posedge clk) begin
        if (latch_this_cmd)
            dst_avmm_address <= cmdq_dout.cmd.dst_start_addr;
        else if (wr_state_is_write_magic_num)
            dst_avmm_address <= disp_ctrl_if.host_mem_magicnumber_addr;
        else if (wr_state_cur_is_a_write_data_state & successful_dst_int_write)
            dst_avmm_address <= dst_avmm_address + HOSTMEM_DATA_BYTES_PER_WORD;
        else
            dst_avmm_address <= dst_avmm_address;
    end

    //wr-burst-count
`ifdef DMA_DO_SINGLE_BURST_PARTIAL_WRITES
    //the PIM doesn't completely support AVMM bursts when doing partial writes. A partial write
    // is required to be a single-word burst. The rest of the original burst would be grouped
    // into a burst, but not the partial writes, whether they are the first and/or last words in
    // the original burst.
    always_ff @(posedge clk) begin
        //first burstcount value
        if (latch_this_cmd_post[2]) begin
            //total words to write is less than the destination's max supported burst count.
            //if the first write is partial (unaligned or less than a full word), burstcnt is 1
            if (DIR_FPGA_TO_HOST & first_dst_write_is_partial)
                dst_avmm_burstcount <= 'h1;
            //less than (or equal to) a single max burst
            else if (write_xfer_cnt_in_words_reg <= DST_WR_BURSTCOUNT_MAX) begin
                //check if the last word is partial
                if (DIR_FPGA_TO_HOST & last_dst_write_is_partial)
                    //reduce the burstcnt by 1 because the final write will be a single partial word
                    dst_avmm_burstcount <= write_xfer_cnt_in_words_reg - 'h1;
                else //last word is not partial, include it in this burst
                    dst_avmm_burstcount <= write_xfer_cnt_in_words_reg;
            end else //more than a max burst still to send
                dst_avmm_burstcount <= DST_WR_BURSTCOUNT_MAX;
        //subsequent burstcount values
        end else if (successful_dst_int_write) begin
            //magic number is always just a single word write
            if (wr_state_nxt_is_write_magic_num | wr_state_cur_is_write_magic_num)
                dst_avmm_burstcount <= 'h1;
            //end of a burst
            else if (dst_avmm_burstcount == 'h1) begin
                //if small amount of data left, use that as the burst size
                if (wr_xfer_remaining_next <= DST_WR_BURSTCOUNT_MAX) begin
                    if (DIR_FPGA_TO_HOST & last_dst_write_is_partial)
                        dst_avmm_burstcount <= wr_xfer_remaining_next -'h1;
                    else //last word is not partial, include it in this burst
                        dst_avmm_burstcount <= wr_xfer_remaining_next;
                //more than one burst left, use max burst size
                end else
                    dst_avmm_burstcount <= DST_WR_BURSTCOUNT_MAX;
            end else
                dst_avmm_burstcount <= dst_avmm_burstcount - 'h1;
        end else if (wr_state_cur_is_write_magic_num)
            dst_avmm_burstcount <= 'h1;
    end
`else
    always_ff @(posedge clk) begin
        //first burstcount value
        if (latch_this_cmd_post[2]) begin
            if (write_xfer_cnt_in_words_reg < DST_WR_BURSTCOUNT_MAX)
                dst_avmm_burstcount <= write_xfer_cnt_in_words_reg;
            else
                dst_avmm_burstcount <= DST_WR_BURSTCOUNT_MAX;
        //subsequent burstcount values
        end else if (successful_dst_int_write) begin
            if (wr_state_nxt_is_write_magic_num | wr_state_cur_is_write_magic_num)
                dst_avmm_burstcount <= 'h1;
            //end of a burst
            else if (dst_avmm_burstcount == 'h1) begin
                //if small amount of data left, use that as the burst size
                if (wr_xfer_remaining_next < DST_WR_BURSTCOUNT_MAX)
                    dst_avmm_burstcount <= wr_xfer_remaining_next;
                //more than one burst left, use max burst size
                else
                    dst_avmm_burstcount <= DST_WR_BURSTCOUNT_MAX;
            end else
                dst_avmm_burstcount <= dst_avmm_burstcount - 'h1;
        end else if (wr_state_cur_is_write_magic_num)
            dst_avmm_burstcount <= 'h1;
    end
`endif
    
    //wr-xfer-counter - track the number of remaining words to xfer
    logic wr_xfer_remaining_hi_bits;
    always_ff @(posedge clk) begin
        wr_xfer_remaining_hi_bits <= |wr_xfer_remaining[WORD_COUNTER_SIZE:2];
    end
    always_ff @(posedge clk) begin
        //when latching a new command, set the remaining-words-counter 
        //  to the destination address offset + xfer_length.
        if (latch_this_cmd)
            wr_xfer_remaining <= write_xfer_cnt_in_words_reg;
        //after a valid write, reduce the counter by the 
        else if (successful_dst_int_write && 
                (wr_xfer_remaining_hi_bits || wr_xfer_remaining[1:0]) )
            wr_xfer_remaining <= wr_xfer_remaining_next;
    end
    assign wr_xfer_remaining_next = wr_xfer_remaining - 1'b1;
    
    //AVMM pipeline bridge for destination-writes
    logic  dst_avmm_write, dst_avmm_read;
    acl_avalon_mm_bridge_s10 #(
        .DATA_WIDTH                     ( AVMM_DATA_WIDTH ),
        .SYMBOL_WIDTH                   ( 8   ),
        .HDL_ADDR_WIDTH                 ( DST_ADDR_WIDTH ),
        .BURSTCOUNT_WIDTH               ( 7   ),
        .SYNCHRONIZE_RESET              ( 1   ),
        .READDATA_PIPE_DEPTH            ( 3   )
    ) dst_avmm_pipeline_inst (
        .clk               (clk),
        .reset             (rst_local),
        .s0_waitrequest    (dst_avmm_int.waitrequest  ),
        .s0_readdata       (dst_avmm_int.readdata     ),
        .s0_readdatavalid  (dst_avmm_int.readdatavalid),
        .s0_burstcount     (dst_avmm_int.burstcount   ),
        .s0_writedata      (dst_avmm_int.writedata    ),
        .s0_address        (dst_avmm_int.address      ),
        .s0_write          (dst_avmm_int.write        ),
        .s0_read           (dst_avmm_int.read         ),
        .s0_byteenable     (dst_avmm_int.byteenable   ),
        .m0_waitrequest    (dst_avmm.waitrequest  ),
        .m0_readdata       (dst_avmm.readdata     ),
        .m0_readdatavalid  (dst_avmm.readdatavalid),
        .m0_burstcount     (dst_avmm.burstcount   ),
        .m0_writedata      (dst_avmm.writedata    ),
        .m0_address        (dst_avmm.address      ),
        .m0_write          (dst_avmm_write        ),
        .m0_read           (dst_avmm_read         ),
        .m0_byteenable     (dst_avmm.byteenable   )
    );
    // Higher-level interfaces don't like 'X' during simulation. Drive 0's when not 
    // driven by the bridge.
    always_comb begin
        dst_avmm.write = dst_avmm_write;
        dst_avmm.read  = dst_avmm_read;
        //drive with the modified version during simulation
    // synthesis translate off
        dst_avmm.write = dst_avmm_write === 'X ? 'b0 : dst_avmm_write;
        dst_avmm.read  = dst_avmm_read  === 'X ? 'b0 : dst_avmm_read;
    // synthesis translate on
    end
        
    //only generate wr-fence signals for FPGA-to-HOST path on CH0
    always_comb begin
        if ( (DIR_FPGA_TO_HOST == 1'b1) && DO_F2H_MAGIC_NUMBER_WRITE & (DMA_CHANNEL_NUM == 0) )
            disp_ctrl_if.f2h_wr_fence_flag = wr_state_cur_is_write_magic_num && successful_dst_int_write;
        else
            disp_ctrl_if.f2h_wr_fence_flag = 'b0;
    end
    
    logic [15:0] magic_number_counter;
    always_ff @(posedge clk) begin
        if (wr_state_cur_is_write_magic_num && successful_dst_int_write)
            magic_number_counter <= magic_number_counter + 1'b1;
        if (rst_local) magic_number_counter <= 'b0;
    end
    assign disp_ctrl_if.magic_number_counter = magic_number_counter;
    
    //
    // control/status stuff - slightly different if this is DMA CH[0] and F2H or another channel
    //
    generate
    if (DIR_FPGA_TO_HOST & DO_F2H_MAGIC_NUMBER_WRITE & (DMA_CHANNEL_NUM==0) ) begin
        logic wr_state_cur_is_wait_to_write_magic_num_d;
                
        always_ff @(posedge clk) begin
            wr_state_cur_is_wait_to_write_magic_num_d <= wr_state_cur_is_wait_to_write_magic_num;
            if (rst_local)
                wr_state_cur_is_wait_to_write_magic_num_d <= 'b0;
        end
        assign disp_ctrl_if.f2h_wait_for_magic_num_wr_pulse = !wr_state_cur_is_wait_to_write_magic_num_d &
                                                                        wr_state_cur_is_wait_to_write_magic_num;
    end else begin
        assign disp_ctrl_if.f2h_wait_for_magic_num_wr_pulse = 'b0;
    end
    endgenerate
    
    always_comb begin
        controller_busy <= disp_ctrl_if.controller_busy_wr | disp_ctrl_if.controller_busy_rd;
    end
    
    //set interrupt on falling edge of controller-busy; clear when the clear-irq signal is asserted
    //create both a pulse and a level for the IRQ signal.
    always_ff @(posedge clk) begin
        controller_busy_d <= controller_busy;
        if (rst_local) controller_busy_d <= 'b0;
    end
    assign controller_busy_falling_edge = !controller_busy & controller_busy_d;
    always_ff @(posedge clk) begin
        if (latch_this_cmd)                 disp_ctrl_if.irq = 'b0;
        else if (controller_busy_falling_edge) disp_ctrl_if.irq = 'b1;
        else if (disp_ctrl_if.clear_irq)    disp_ctrl_if.irq = 'b0;
        if (rst_local)                            disp_ctrl_if.irq = 'b0;
    end
    assign disp_ctrl_if.irq_pulse = controller_busy_falling_edge;
    
    //controller status signals to the dispatcher and regsiters
    always_comb begin
        disp_ctrl_if.cntrl_sts.rd_ctrl_fsm_cs = rd_state_cur;
        disp_ctrl_if.cntrl_sts.rd_xfer_remaining = | (rd_xfer_remaining[WORD_COUNTER_SIZE:16]) ? '1 : rd_xfer_remaining[15:0];
        disp_ctrl_if.cntrl_sts.wr_ctrl_fsm_cs = wr_state_cur;
        disp_ctrl_if.cntrl_sts.wr_xfer_remaining = | (wr_xfer_remaining[WORD_COUNTER_SIZE:16]) ? '1 : wr_xfer_remaining[15:0];
    end

    //this function will be used to calculate the first-write's byteenable value based on the dst_addr and xfer_length
    function logic [HOSTMEM_DATA_BYTES_PER_WORD-1:0] FIND_FIRST_WR_BYTEENABLE;
        input logic [DST_ADDR_WIDTH-1:0]    dst_addr;
        input logic [XFER_LENGTH_WIDTH-1:0] xfer_length;
        begin
            //if start at address 0, set bits start at [0]
            if ( dst_addr[HOSTMEM_DATA_BYTES_PER_WORD_SZ-1:0] == 'b0 ) begin
                //if xfer_length is greater than or equal to a full burst of HOSTMEM_DATA_BYTES_PER_WORD bytes, set all HOSTMEM_DATA_BYTES_PER_WORD bits.
                if ( |xfer_length[XFER_LENGTH_WIDTH-1:HOSTMEM_DATA_BYTES_PER_WORD_SZ] )
                    FIND_FIRST_WR_BYTEENABLE = '1;
                //else we are writing less than a full word of useful data; set bits starting
                // at [0] and move set subsequent ones to the left.
                else begin
                    for (int i=0; i<HOSTMEM_DATA_BYTES_PER_WORD; i++) begin
                        FIND_FIRST_WR_BYTEENABLE[i] = i < xfer_length[HOSTMEM_DATA_BYTES_PER_WORD_SZ-1:0] ? 1'b1 : 1'b0;
                    end
                end
            //we are offset into the destination address; there will be zeros in the lsb location(s)
            //  and possibly also in the msb locations.
            end else begin
                for (int i=0; i<HOSTMEM_DATA_BYTES_PER_WORD; i++) begin
                    FIND_FIRST_WR_BYTEENABLE[i] =   i < dst_addr[HOSTMEM_DATA_BYTES_PER_WORD_SZ-1:0] ? 1'b0 :
                                                    i >= dst_addr[HOSTMEM_DATA_BYTES_PER_WORD_SZ-1:0] + xfer_length ? 1'b0 :
                                                    1'b1;
                end
            end
        end
    endfunction : FIND_FIRST_WR_BYTEENABLE
    
    function logic [HOSTMEM_DATA_BYTES_PER_WORD-1:0] FIND_LAST_WR_BYTEENABLE;
        input logic [HOSTMEM_DATA_BYTES_PER_WORD_SZ:0] xfer_length;
        begin
            for (int i=0; i<HOSTMEM_DATA_BYTES_PER_WORD; i++) begin
                FIND_LAST_WR_BYTEENABLE[i] = i < xfer_length ? 1'b1 : 1'b0;
            end
        end
    endfunction : FIND_LAST_WR_BYTEENABLE

    function logic [HOSTMEM_DATA_BYTES_PER_WORD_SZ:0] COUNT_SET_BITS;
        input logic [HOSTMEM_DATA_BYTES_PER_WORD-1:0]    din;
        begin
            COUNT_SET_BITS = '0;
            foreach(din[i])
                COUNT_SET_BITS += din[i];
        end
    endfunction : COUNT_SET_BITS

endmodule : dma_data_transfer
