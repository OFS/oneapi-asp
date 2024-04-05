// Copyright 2022 Intel Corporation
// SPDX-License-Identifier: MIT
//

//DMA controller instance signals from Dispatcher
interface dma_ctrl_intf #(
    parameter SRC_ADDR_WIDTH        = 48,
    parameter DST_ADDR_WIDTH        = 48,
    parameter XFER_LENGTH_WIDTH     = 40,
    parameter CMDQ_USEDW_WIDTH      =  8,
    parameter DATABUF_USEDW_WIDTH   = 16,
    parameter DMA_DIR               = "NULL"
);
    localparam REGISTER_WIDTH = dma_pkg::MMIO64_DATA_WIDTH;
    localparam CMDQ_DATA_WIDTH = SRC_ADDR_WIDTH + DST_ADDR_WIDTH + XFER_LENGTH_WIDTH;

    logic sclr;
    logic controller_busy_rd;
    logic controller_busy_wr;
    logic new_cmd;
    logic irq;
    logic irq_pulse;
    logic clear_irq;
    logic [REGISTER_WIDTH-1:0] host_mem_magicnumber_addr;
    logic f2h_wr_fence_flag;
    logic [REGISTER_WIDTH-1:0] src_readdatavalid_counter, src_burst_cnt_counter, dst_write_counter;
    logic [15:0] magic_number_counter;
    logic f2h_wait_for_magic_num_wr_pulse;
    
    //DMA command-queue status signals
    typedef struct packed {
        logic empty, full, underflow, overflow;
        logic [CMDQ_USEDW_WIDTH-1:0] usedw;
    } cmdq_status_t;
    cmdq_status_t cmdq_status;
    
    //DMA data buffer status signals
    typedef struct packed {
        logic [DATABUF_USEDW_WIDTH-1:0] usedw_highwater_mark;
        logic empty, full, underflow, overflow;
        logic [DATABUF_USEDW_WIDTH-1:0] usedw;
    } databuf_status_t;
    databuf_status_t databuf_status;
    
    //DMA command details
    typedef struct packed {
        logic [SRC_ADDR_WIDTH-1:0]      src_start_addr;
        logic [DST_ADDR_WIDTH-1:0]      dst_start_addr;
        logic [XFER_LENGTH_WIDTH-1:0]   xfer_length;
    } dma_ctrl_cmd_t;
    dma_ctrl_cmd_t cmd;
    
    //DMA transfer controller status
    typedef struct packed {
        logic [3:0]      rd_ctrl_fsm_cs;
        logic [15:0]     rd_xfer_remaining;//'1 if greater than 16 bits
        logic [3:0]      wr_ctrl_fsm_cs;
        logic [15:0]     wr_xfer_remaining;//'1 if greater than 16 bits
    } dma_ctrl_sts_t;
    dma_ctrl_sts_t cntrl_sts;

    //Dispatcher
    modport disp (
        input   controller_busy_rd, controller_busy_wr,
                cmdq_status, databuf_status, irq, irq_pulse, cntrl_sts,
                src_burst_cnt_counter, src_readdatavalid_counter,
                dst_write_counter, magic_number_counter,
                f2h_wait_for_magic_num_wr_pulse,
        output  cmd, new_cmd, sclr, clear_irq,
                host_mem_magicnumber_addr
    );
    
    //controller
    modport ctrl (
        input   cmd, new_cmd, sclr, clear_irq,
                host_mem_magicnumber_addr, 
        output  controller_busy_rd, controller_busy_wr,
                cmdq_status, databuf_status, irq, irq_pulse,
                f2h_wr_fence_flag, cntrl_sts, src_burst_cnt_counter, 
                src_readdatavalid_counter, dst_write_counter,
                magic_number_counter, f2h_wait_for_magic_num_wr_pulse
    );

endinterface : dma_ctrl_intf


//an interface to split the word and byte bits
interface split_addr_intf #(
    parameter WIDTH = 48,
    parameter BYTE_WIDTH = 6
);
    
    typedef struct packed {
        logic [WIDTH-BYTE_WIDTH-1:0]    word_address;
        logic [BYTE_WIDTH-1:0]          byte_address;
    } split_addr_t;
    split_addr_t sa;

endinterface : split_addr_intf