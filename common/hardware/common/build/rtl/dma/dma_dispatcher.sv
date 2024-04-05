// Copyright 2022 Intel Corporation
// SPDX-License-Identifier: MIT
//

`include "ofs_plat_if.vh"


module dma_dispatcher
import dma_pkg::*;
import ofs_asp_pkg::*;
(
    input clk,
    input reset,
    
    output logic host_mem_rd_xfer_done,
    output logic host_mem_wr_xfer_done,

    //Avalon mem if - mmio64
    ofs_plat_avalon_mem_if.to_source mmio64_if,
    
    //dispatcher-to-controller if - host-to-FPGA (read)
    dma_ctrl_intf.disp rd_ctrl [NUM_DMA_CHAN-1:0],
    
    //dispatcher-to-controller if - FPGA-to-host (write)
    dma_ctrl_intf.disp wr_ctrl [NUM_DMA_CHAN-1:0]
);

    localparam reg_width = MMIO64_DATA_WIDTH;

    logic [reg_width-1:0] scratchpad_reg;
    logic [reg_width-1:0] dfh_header_data_reg;
    logic [reg_width-1:0] host_rd_status_reg_data, host_wr_status_reg_data;
    logic [reg_width-1:0] wr_ctrl_host_mem_magicnumber_addr;
    logic rd_ctrl_clear_irq, rd_ctrl_sclr;
    logic wr_ctrl_clear_irq, wr_ctrl_sclr;
    logic [reg_width-1:0] rd_ctrl_cmd_src_start_addr, rd_ctrl_cmd_dst_start_addr, rd_ctrl_cmd_xfer_length, 
                          rd_ctrl_cmd_xfer_length_ch0, rd_ctrl_cmd_src_start_addr_ch1, rd_ctrl_cmd_dst_start_addr_ch1,
                          wr_ctrl_cmd_xfer_length_ch0, wr_ctrl_cmd_src_start_addr_ch1, wr_ctrl_cmd_dst_start_addr_ch1;
    logic rd_ctrl_new_cmd;
    logic [reg_width-1:0] wr_ctrl_cmd_src_start_addr, wr_ctrl_cmd_dst_start_addr, wr_ctrl_cmd_xfer_length;
    logic wr_ctrl_new_cmd;
    logic [2:0] rd_ctrl_new_cmd_d, wr_ctrl_new_cmd_d;
    logic [NUM_DMA_CHAN_BITS-1:0] rd_ctrl_chan_cntr, wr_ctrl_chan_cntr;
    logic [NUM_DMA_CHAN-1:0] rd_rxd_irq, rd_wait_irq, wr_rxd_irq, wr_wait_irq;

    
    //pipeline and duplicate the reset signal
    parameter RESET_PIPE_DEPTH = 2;
    logic [RESET_PIPE_DEPTH-1:0] rst_pipe;
    logic rst_local;
    always_ff @(posedge clk) begin
        {rst_local,rst_pipe}  <= {rst_pipe[RESET_PIPE_DEPTH-1:0], 1'b0};
        if (reset) begin
            rst_local <= '1;
            rst_pipe  <= '1;
        end
    end
    
    //the address is for bytes but register accesses are full 64-bit words
    logic [MMIO64_ADDR_WIDTH-1:0] this_address;
    assign this_address = mmio64_if.address>>3;
    
    //
    // create an Avalon-MM CSR-space to manage the DMA controller(s)
    //
    
    //writes
    always_ff @(posedge clk)
    begin
        //self-clearing / pulse
        rd_ctrl_new_cmd <= 1'b0;
        rd_ctrl_sclr <= 'b0;
        rd_ctrl_clear_irq <= 'b0;
        wr_ctrl_new_cmd <= 1'b0;
        wr_ctrl_sclr <= 'b0;
        wr_ctrl_clear_irq <= 'b0;
        if (mmio64_if.write)
        begin
            case (this_address)
                SCRATCHPAD_ADDR: scratchpad_reg                     <= mmio64_if.writedata;
                MAGICNUMBER_HOSTMEM_WR_ADDR: wr_ctrl_host_mem_magicnumber_addr <= mmio64_if.writedata;
                
                //Host-to-FPGA DMA channel (read)
                HOST_RD_START_SRC_ADDR: rd_ctrl_cmd_src_start_addr  <= mmio64_if.writedata;
                HOST_RD_START_DST_ADDR: rd_ctrl_cmd_dst_start_addr  <= mmio64_if.writedata;
                HOST_RD_TRANSFER_LENGTH_ADDR: 
                begin
                    rd_ctrl_cmd_xfer_length <= mmio64_if.writedata;
                    rd_ctrl_new_cmd         <= mmio64_if.writedata > 'h0 ? 1'b1 : 1'b0;
                end
                HOST_RD_CONFIG_ADDR:
                begin
                    rd_ctrl_sclr        <= mmio64_if.writedata[CONFIG_REG_SCLR_BIT];
                    rd_ctrl_clear_irq   <= mmio64_if.writedata[CONFIG_REG_CLEAR_IRQ_BIT];
                end
                
                //FPGA-to-host DMA channel (write)
                HOST_WR_START_SRC_ADDR: wr_ctrl_cmd_src_start_addr  <= mmio64_if.writedata;
                HOST_WR_START_DST_ADDR: wr_ctrl_cmd_dst_start_addr  <= mmio64_if.writedata;
                HOST_WR_TRANSFER_LENGTH_ADDR: 
                begin
                    wr_ctrl_cmd_xfer_length <= mmio64_if.writedata;
                    wr_ctrl_new_cmd         <= mmio64_if.writedata > 'h0 ? 1'b1 : 1'b0;
                end
                HOST_WR_CONFIG_ADDR:
                begin
                    wr_ctrl_sclr        <= mmio64_if.writedata[CONFIG_REG_SCLR_BIT];
                    wr_ctrl_clear_irq   <= mmio64_if.writedata[CONFIG_REG_CLEAR_IRQ_BIT];
                end
            endcase
        end
    
        if (rst_local) begin
            wr_ctrl_host_mem_magicnumber_addr <= 'h0;
            scratchpad_reg <= 'b0;
            rd_ctrl_new_cmd <= 'b0;
            wr_ctrl_new_cmd <= 'b0;
        end
    end
    
    //reads
    always_ff @(posedge clk)
    begin
        //self-clearing / pulse
        mmio64_if.readdatavalid <= 1'b0;
        if (mmio64_if.read)
        begin
            //response is valid on the next clock
            mmio64_if.readdatavalid <= 1'b1;
            case (this_address)
                DFH_HEADER_ADDR:                mmio64_if.readdata <= dfh_header_data_reg;
                ID_LO_ADDR:                     mmio64_if.readdata <= DFH_ID_LO;
                ID_HI_ADDR:                     mmio64_if.readdata <= DFH_ID_HI;
                DFH_NEXT_AFU_OFFSET_ADDR:       mmio64_if.readdata <= DFH_NEXT_AFU_OFFSET;
                SCRATCHPAD_ADDR:                mmio64_if.readdata <= scratchpad_reg;
                MAGICNUMBER_HOSTMEM_WR_ADDR:    mmio64_if.readdata <= wr_ctrl_host_mem_magicnumber_addr;
                NUM_DMA_CHAN_ADDR:              mmio64_if.readdata <= NUM_DMA_CHAN;
                //host-to-FPGA transfers (read)
                HOST_RD_START_SRC_ADDR:         mmio64_if.readdata <= rd_ctrl_cmd_src_start_addr;
                HOST_RD_START_DST_ADDR:         mmio64_if.readdata <= rd_ctrl_cmd_dst_start_addr;
                HOST_RD_TRANSFER_LENGTH_ADDR:   mmio64_if.readdata <= rd_ctrl_cmd_xfer_length;
                //HOST_RD_CMDQ_STATUS_ADDR:       mmio64_if.readdata <= rd_ctrl[rd_ctrl_chan_cntr].cmdq_status;
                //HOST_RD_DATABUF_STATUS_ADDR:    mmio64_if.readdata <= rd_ctrl[rd_ctrl_chan_cntr].databuf_status;
                //HOST_RD_CONFIG_ADDR:            mmio64_if.readdata <= 'b0;
                //HOST_RD_STATUS_ADDR:            mmio64_if.readdata <= host_rd_status_reg_data;
                //HOST_RD_BRSTCNT_CNT_ADDR:       mmio64_if.readdata <= rd_ctrl[rd_ctrl_chan_cntr].src_burst_cnt_counter;
                //HOST_RD_RDDATAVALID_CNT_ADDR:   mmio64_if.readdata <= rd_ctrl[rd_ctrl_chan_cntr].src_readdatavalid_counter;
                //HOST_RD_MAGICNUM_CNT_ADDR:      mmio64_if.readdata <= rd_ctrl[rd_ctrl_chan_cntr].magic_number_counter;
                //HOST_RD_WRDATA_CNT_ADDR:        mmio64_if.readdata <= rd_ctrl[rd_ctrl_chan_cntr].dst_write_counter;
                //HOST_RD_STATUS2_ADDR:           mmio64_if.readdata <= rd_ctrl[rd_ctrl_chan_cntr].cntrl_sts;
                //HOST_RD_THIS_CHAN_SRC_ADDR:     mmio64_if.readdata <= rd_ctrl[rd_ctrl_chan_cntr].cmd.src_start_addr;
                //HOST_RD_THIS_CHAN_DST_ADDR:     mmio64_if.readdata <= rd_ctrl[rd_ctrl_chan_cntr].cmd.dst_start_addr;
                //HOST_RD_THIS_CHAN_XFER_LEN_ADDR: mmio64_if.readdata <= rd_ctrl[rd_ctrl_chan_cntr].cmd.xfer_length;
                //HOST_RD_THIS_CHAN_NUM_ADDR:     mmio64_if.readdata <= rd_ctrl_chan_cntr;
                //FPGA-to-host transfers (write)
                HOST_WR_START_SRC_ADDR:         mmio64_if.readdata <= wr_ctrl_cmd_src_start_addr;
                HOST_WR_START_DST_ADDR:         mmio64_if.readdata <= wr_ctrl_cmd_dst_start_addr;
                HOST_WR_TRANSFER_LENGTH_ADDR:   mmio64_if.readdata <= wr_ctrl_cmd_xfer_length;
                //HOST_WR_CMDQ_STATUS_ADDR:       mmio64_if.readdata <= wr_ctrl[wr_ctrl_chan_cntr].cmdq_status;
                //HOST_WR_DATABUF_STATUS_ADDR:    mmio64_if.readdata <= wr_ctrl[wr_ctrl_chan_cntr].databuf_status;
                //HOST_WR_CONFIG_ADDR:            mmio64_if.readdata <= 'b0;
                //HOST_WR_STATUS_ADDR:            mmio64_if.readdata <= host_wr_status_reg_data;
                //HOST_WR_BRSTCNT_CNT_ADDR:       mmio64_if.readdata <= wr_ctrl[wr_ctrl_chan_cntr].src_burst_cnt_counter;
                //HOST_WR_RDDATAVALID_CNT_ADDR:   mmio64_if.readdata <= wr_ctrl[wr_ctrl_chan_cntr].src_readdatavalid_counter;
                //HOST_WR_MAGICNUM_CNT_ADDR:      mmio64_if.readdata <= wr_ctrl[wr_ctrl_chan_cntr].magic_number_counter;
                //HOST_WR_WRDATA_CNT_ADDR:        mmio64_if.readdata <= wr_ctrl[wr_ctrl_chan_cntr].dst_write_counter;
                //HOST_WR_STATUS2_ADDR:           mmio64_if.readdata <= wr_ctrl[wr_ctrl_chan_cntr].cntrl_sts;
                //HOST_WR_THIS_CHAN_SRC_ADDR:     mmio64_if.readdata <= wr_ctrl[wr_ctrl_chan_cntr].cmd.src_start_addr;
                //HOST_WR_THIS_CHAN_DST_ADDR:     mmio64_if.readdata <= wr_ctrl[wr_ctrl_chan_cntr].cmd.dst_start_addr;
                //HOST_WR_THIS_CHAN_XFER_LEN_ADDR: mmio64_if.readdata <= wr_ctrl[wr_ctrl_chan_cntr].cmd.xfer_length;
                //HOST_WR_THIS_CHAN_NUM_ADDR:     mmio64_if.readdata <= wr_ctrl_chan_cntr;

                default:                        mmio64_if.readdata <= REG_RD_BADADDR_DATA;
            endcase
        end
        if (rst_local)           mmio64_if.readdata <= '0;
    end
    
    //disable the wait-req signal - we should always be able to accept commands
    always_comb begin
        mmio64_if.waitrequest = 'b0;
    end
    
    //when reading the status registers we expect the sw to read all of the relevant registers, one-at-a-time and
    //in order; when the final relevant register is read, we'll increment the DMA-channel that is accessed. This 
    //prevents us from needing to to implement many copies of the registers and simply multiplex the existing addresses.
    logic go_to_next_rd_chan_registers, go_to_next_wr_chan_registers;
    assign go_to_next_rd_chan_registers = mmio64_if.readdatavalid && (this_address == HOST_RD_LAST_REG_ADDR);
    assign go_to_next_wr_chan_registers = mmio64_if.readdatavalid && (this_address == HOST_WR_LAST_REG_ADDR);
    always_ff @(posedge clk) begin
        if (rd_ctrl_new_cmd)
            rd_ctrl_chan_cntr <= 'b0;
        else if (go_to_next_rd_chan_registers)
            rd_ctrl_chan_cntr <= rd_ctrl_chan_cntr + 1'b1;
        if (rst_local)
            rd_ctrl_chan_cntr <= 'b0;
    end
    always_ff @(posedge clk) begin
        if (wr_ctrl_new_cmd)
            wr_ctrl_chan_cntr <= 'b0;
        else if (go_to_next_wr_chan_registers)
            wr_ctrl_chan_cntr <= wr_ctrl_chan_cntr + 1'b1;
        if (rst_local)
            wr_ctrl_chan_cntr <= 'b0;
    end
    
    //support multiple DMA channels, spread transfers across multiple channels
    genvar d;
    generate
        for (d=0; d < NUM_DMA_CHAN; d=d+1) begin : dma_ctrl
            always_comb begin
                rd_ctrl[d].sclr                      = rd_ctrl_sclr;
                rd_ctrl[d].clear_irq                 = rd_ctrl_clear_irq;
                wr_ctrl[d].host_mem_magicnumber_addr = wr_ctrl_host_mem_magicnumber_addr;
                wr_ctrl[d].sclr                      = wr_ctrl_sclr;
                wr_ctrl[d].clear_irq                 = wr_ctrl_clear_irq;
            end
        end : dma_ctrl
    endgenerate
    
    //this should eventually be moved into a clevel loop to support future implementations with
    //more than 2 DMA/PCIe interfaces.
    generate
    if (NUM_DMA_CHAN == 1) begin
        always_ff @(posedge clk) begin
            //host-mem read commands
            rd_ctrl[0].cmd.src_start_addr <= rd_ctrl_cmd_src_start_addr;
            rd_ctrl[0].cmd.dst_start_addr <= rd_ctrl_cmd_dst_start_addr;
            rd_ctrl[0].cmd.xfer_length <= rd_ctrl_cmd_xfer_length;
            rd_ctrl[0].new_cmd <= rd_ctrl_new_cmd;
            //host-mem write commands
            wr_ctrl[0].cmd.src_start_addr <= wr_ctrl_cmd_src_start_addr;
            wr_ctrl[0].cmd.dst_start_addr <= wr_ctrl_cmd_dst_start_addr;
            wr_ctrl[0].cmd.xfer_length <= wr_ctrl_cmd_xfer_length;
            wr_ctrl[0].new_cmd <= wr_ctrl_new_cmd;
            if (rst_local) begin
                rd_ctrl[0].new_cmd <= 'b0;
                wr_ctrl[0].new_cmd <= 'b0;
            end
        end
        always_ff @(posedge clk) begin
            //since there is only 1 DMA channel, pass along the 1 irq as the 'done' signal
            host_mem_rd_xfer_done <= rd_ctrl[0].irq_pulse;
            host_mem_wr_xfer_done <= wr_ctrl[0].f2h_wait_for_magic_num_wr_pulse;
        end
    end
    else if (NUM_DMA_CHAN == 2) begin
        always_ff @(posedge clk) begin
            //host-mem read commands for ch0 - use original src/dst addresses,
            //also include any uneven number of bytes relative to # of channels.
            rd_ctrl[0].cmd.src_start_addr <= rd_ctrl_cmd_src_start_addr;
            rd_ctrl[0].cmd.dst_start_addr <= rd_ctrl_cmd_dst_start_addr;
            rd_ctrl[0].cmd.xfer_length <= rd_ctrl_cmd_xfer_length_ch0;
            rd_ctrl[0].new_cmd <= rd_ctrl_new_cmd_d[2];
            //host-mem read command for ch1 : src address is (ch0 source plus ch0 xfer length)
            //host-mem read command for ch1 : dest address is (ch0 dest plus ch0 xfer length)
            //host-mem read command for ch1 : xfer-length is (floor(original xfer-length right-shifted by 1))
            //issue new-cmd when the xfer-length and src/dst addresses are calculated
            rd_ctrl[1].cmd.src_start_addr <= rd_ctrl_cmd_src_start_addr_ch1;
            rd_ctrl[1].cmd.dst_start_addr <= rd_ctrl_cmd_dst_start_addr_ch1;
            rd_ctrl[1].cmd.xfer_length <= (rd_ctrl_cmd_xfer_length>>NUM_DMA_CHAN_BITS);
            //if the transfer is very small it might only land on
            //CH0; if so, don't issue a 'new-cmd' flag to CH1.
            rd_ctrl[1].new_cmd <= (rd_ctrl_cmd_xfer_length>>NUM_DMA_CHAN_BITS) ? rd_ctrl_new_cmd_d[2] : 'b0;
            
            //host-mem write commands for ch0 - use original src/dst addresses,
            //also include any uneven number of bytes relative to # of channels.
            wr_ctrl[0].cmd.src_start_addr <= wr_ctrl_cmd_src_start_addr;
            wr_ctrl[0].cmd.dst_start_addr <= wr_ctrl_cmd_dst_start_addr;
            wr_ctrl[0].cmd.xfer_length <= wr_ctrl_cmd_xfer_length_ch0;
            wr_ctrl[0].new_cmd <= wr_ctrl_new_cmd_d[2];
            //host-mem write command for ch1 : src address is (ch0 source plus ch0 xfer length)
            //host-mem write command for ch1 : dest address is (ch0 dest plus ch0 xfer length)
            //host-mem write command for ch1 : xfer-length is (floor(original xfer-length right-shifted by 1))
            //issue new-cmd when the xfer-length and src/dst addresses are calculated
            wr_ctrl[1].cmd.src_start_addr <= wr_ctrl_cmd_src_start_addr_ch1;
            wr_ctrl[1].cmd.dst_start_addr <= wr_ctrl_cmd_dst_start_addr_ch1;
            wr_ctrl[1].cmd.xfer_length <= (wr_ctrl_cmd_xfer_length>>NUM_DMA_CHAN_BITS);
            //if the transfer is very small it might only land on
            //CH0; if so, don't issue a 'new-cmd' flag to CH1.
            wr_ctrl[1].new_cmd <= (wr_ctrl_cmd_xfer_length>>NUM_DMA_CHAN_BITS) ? wr_ctrl_new_cmd_d[2] : 'b0;
            if (rst_local) begin
                rd_ctrl[0].new_cmd <= 'b0;
                wr_ctrl[0].new_cmd <= 'b0;
                rd_ctrl[1].new_cmd <= 'b0;
                wr_ctrl[1].new_cmd <= 'b0;
            end
        end
        
        always_ff @(posedge clk) begin
            //rd-command address/size manipulation. One clock cycle to find the ch0 xfer length, another clock
            // to find the ch1 src/dst start addresses.
            rd_ctrl_new_cmd_d <= {rd_ctrl_new_cmd_d[1:0],rd_ctrl_new_cmd};
            if (rd_ctrl_new_cmd)
                rd_ctrl_cmd_xfer_length_ch0 = (rd_ctrl_cmd_xfer_length>>NUM_DMA_CHAN_BITS) + rd_ctrl_cmd_xfer_length[NUM_DMA_CHAN_BITS-1:0];
            if (rd_ctrl_new_cmd_d[0]) begin
                rd_ctrl_cmd_src_start_addr_ch1 = rd_ctrl_cmd_src_start_addr + rd_ctrl_cmd_xfer_length_ch0;
                rd_ctrl_cmd_dst_start_addr_ch1 = rd_ctrl_cmd_dst_start_addr + rd_ctrl_cmd_xfer_length_ch0;
            end
            if (rst_local)
                rd_ctrl_new_cmd_d <= 'b0;
            //wr-command address/size manipulation. One clock cycle to find the ch0 xfer length, another clock
            // to find the ch1 src/dst start addresses.
            wr_ctrl_new_cmd_d <= {wr_ctrl_new_cmd_d[1:0],wr_ctrl_new_cmd};
            if (wr_ctrl_new_cmd)
                wr_ctrl_cmd_xfer_length_ch0 = (wr_ctrl_cmd_xfer_length>>NUM_DMA_CHAN_BITS) + wr_ctrl_cmd_xfer_length[NUM_DMA_CHAN_BITS-1:0];
            if (wr_ctrl_new_cmd_d[0]) begin
                wr_ctrl_cmd_src_start_addr_ch1 = wr_ctrl_cmd_src_start_addr + wr_ctrl_cmd_xfer_length_ch0;
                wr_ctrl_cmd_dst_start_addr_ch1 = wr_ctrl_cmd_dst_start_addr + wr_ctrl_cmd_xfer_length_ch0;
            end
            if (rst_local)
                wr_ctrl_new_cmd_d <= 'b0;
        end
        
        //aggregate the done-signal information from each data_transfer module to generate a single
        //'done' flag.
        //latch which data_transfer block expects an IRQ signal; latch the IRQs as they are received;
        //when all expected IRQs are received the total transfer is complete.
        always_ff @(posedge clk) begin
            //clear with a new command or when the expected IRQs have been rx'd 
            //and the 'done' flag sent from the DMA controller.
            //host memory read flags
            if (host_mem_rd_xfer_done | rd_ctrl_new_cmd) begin
                rd_rxd_irq[0] <= 'b0;
                rd_rxd_irq[1] <= 'b0;
            end else begin
                rd_rxd_irq[0] <= rd_ctrl[0].irq_pulse ? 'b1 : rd_rxd_irq[0];
                rd_rxd_irq[1] <= rd_ctrl[1].irq_pulse ? 'b1 : rd_rxd_irq[1];
            end
            if (host_mem_rd_xfer_done) begin
                rd_wait_irq[0] <= 'b0;
                rd_wait_irq[1] <= 'b0;
            end else begin
                rd_wait_irq[0] <= rd_ctrl[0].new_cmd ? 'b1 : rd_wait_irq[0];
                rd_wait_irq[1] <= rd_ctrl[1].new_cmd ? 'b1 : rd_wait_irq[1];
            end
            if (rst_local) begin
                rd_wait_irq <= 'b0;
                rd_rxd_irq  <= 'b0;
            end
            host_mem_rd_xfer_done <= !host_mem_rd_xfer_done && &(rd_wait_irq & rd_rxd_irq);
            //host memory write flags
            if (host_mem_wr_xfer_done | wr_ctrl_new_cmd) begin
                wr_rxd_irq[0] <= 'b0;
                wr_rxd_irq[1] <= 'b0;
            end else begin
                wr_rxd_irq[0] <= wr_ctrl[0].f2h_wait_for_magic_num_wr_pulse ? 'b1 : wr_rxd_irq[0];
                wr_rxd_irq[1] <= wr_ctrl[1].irq_pulse ? 'b1 : wr_rxd_irq[1];
            end
            if (host_mem_wr_xfer_done) begin
                wr_wait_irq[0] <= 'b0;
                wr_wait_irq[1] <= 'b0;
            end else begin
                wr_wait_irq[0] <= wr_ctrl[0].new_cmd ? 'b1 : wr_wait_irq[0];
                wr_wait_irq[1] <= wr_ctrl[1].new_cmd ? 'b1 : wr_wait_irq[1];
            end
            if (rst_local) begin
                wr_wait_irq <= 'b0;
                wr_rxd_irq  <= 'b0;
            end
            host_mem_wr_xfer_done <= !host_mem_wr_xfer_done && &(wr_wait_irq & wr_rxd_irq);//(wr_wait_irq[0] & wr_rxd_irq[0]) && (wr_wait_irq[1] & wr_rxd_irq[1]);
        end
    end
    else begin
        $fatal("Error: NUM_DMA_CHAN value of %d is invalid.", NUM_DMA_CHAN);
    end
    endgenerate 
    
    //verbose assignment of the DFH-header information (keep the register-logic clean by making
    //  assignments here; parameters defined in the package file.)
    always_comb begin
        dfh_header_data_reg = { DFH_HDR_FTYPE          ,
                                DFH_HDR_RSVD0          ,
                                DFH_HDR_VERSION_MINOR  ,
                                DFH_HDR_RSVD1          ,
                                DFH_HDR_END_OF_LIST    ,
                                DFH_HDR_NEXT_DFH_OFFSET,
                                DFH_HDR_VERSION_MAJOR  ,
                                DFH_HDR_FEATURE_ID};
    end
    
    //aggregate some status signals from the data transfer blocks
    //always_comb begin
    //    host_rd_status_reg_data = 'b0;
    //    host_rd_status_reg_data[0] = rd_ctrl[rd_ctrl_chan_cntr].controller_busy_rd;
    //    host_rd_status_reg_data[1] = rd_ctrl[rd_ctrl_chan_cntr].controller_busy_wr;
    //    host_rd_status_reg_data[2] = rd_ctrl[rd_ctrl_chan_cntr].irq;
    //    
    //    host_wr_status_reg_data = 'b0;
    //    host_wr_status_reg_data[0] = wr_ctrl[wr_ctrl_chan_cntr].controller_busy_rd;
    //    host_wr_status_reg_data[1] = wr_ctrl[wr_ctrl_chan_cntr].controller_busy_wr;
    //    host_wr_status_reg_data[2] = wr_ctrl[wr_ctrl_chan_cntr].irq;
    //end

endmodule : dma_dispatcher
