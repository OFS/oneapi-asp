// Copyright 2022 Intel Corporation
// SPDX-License-Identifier: MIT
//

`include "ofs_plat_if.vh"


module dma_dispatcher (
    input clk,
    input reset,

    //Avalon mem if - mmio64
    ofs_plat_avalon_mem_if.to_source mmio64_if,
    
    //dispatcher-to-controller if - host-to-FPGA (read)
    dma_ctrl_intf.disp rd_ctrl,
    
    //dispatcher-to-controller if - FPGA-to-host (write)
    dma_ctrl_intf.disp wr_ctrl
);

    import dma_pkg::*;

    localparam reg_width = MMIO64_DATA_WIDTH;
    
    logic [reg_width-1:0] scratchpad_reg;
    logic [reg_width-1:0] dfh_header_data_reg;
    logic [reg_width-1:0] host_rd_status_reg_data, host_wr_status_reg_data;
    
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
    
    //the addres is for bytes but register accesses are full words
    logic [MMIO64_ADDR_WIDTH-1:0] this_address;
    assign this_address = mmio64_if.address>>3;
    
    //
    // create an Avalon-MM CSR-space to manage the DMA controller(s)
    //
    
    //writes
    always_ff @(posedge clk)
    begin
        //self-clearing / pulse
        rd_ctrl.new_cmd <= 1'b0;
        rd_ctrl.sclr <= 'b0;
        rd_ctrl.clear_irq <= 'b0;
        wr_ctrl.new_cmd <= 1'b0;
        wr_ctrl.sclr <= 'b0;
        wr_ctrl.clear_irq <= 'b0;
        if (mmio64_if.write)
        begin
            case (this_address)
                SCRATCHPAD_ADDR: scratchpad_reg                     <= mmio64_if.writedata;
                MAGICNUMBER_HOSTMEM_WR_ADDR: wr_ctrl.host_mem_magicnumber_addr <= mmio64_if.writedata;
                
                //Host-to-FPGA DMA channel (read)
                HOST_RD_START_SRC_ADDR: rd_ctrl.cmd.src_start_addr  <= mmio64_if.writedata;
                HOST_RD_START_DST_ADDR: rd_ctrl.cmd.dst_start_addr  <= mmio64_if.writedata;
                HOST_RD_TRANSFER_LENGTH_ADDR: 
                begin
                    rd_ctrl.cmd.xfer_length <= mmio64_if.writedata;
                    rd_ctrl.new_cmd         <= mmio64_if.writedata > 'h0 ? 1'b1 : 1'b0;
                end
                HOST_RD_CONFIG_ADDR:
                begin
                    rd_ctrl.sclr        <= mmio64_if.writedata[CONFIG_REG_SCLR_BIT];
                    rd_ctrl.clear_irq   <= mmio64_if.writedata[CONFIG_REG_CLEAR_IRQ_BIT];
                end
                
                //FPGA-to-host DMA channel (write)
                HOST_WR_START_SRC_ADDR: wr_ctrl.cmd.src_start_addr  <= mmio64_if.writedata;
                HOST_WR_START_DST_ADDR: wr_ctrl.cmd.dst_start_addr  <= mmio64_if.writedata;
                HOST_WR_TRANSFER_LENGTH_ADDR: 
                begin
                    wr_ctrl.cmd.xfer_length <= mmio64_if.writedata;
                    wr_ctrl.new_cmd         <= mmio64_if.writedata > 'h0 ? 1'b1 : 1'b0;
                end
                HOST_WR_CONFIG_ADDR:
                begin
                    wr_ctrl.sclr        <= mmio64_if.writedata[CONFIG_REG_SCLR_BIT];
                    wr_ctrl.clear_irq   <= mmio64_if.writedata[CONFIG_REG_CLEAR_IRQ_BIT];
                end
            endcase
        end
    
        if (rst_local) begin
            wr_ctrl.host_mem_magicnumber_addr <= 'h0;
            rd_ctrl.host_mem_magicnumber_addr <= 'h0;
            scratchpad_reg <= 'b0;
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
                MAGICNUMBER_HOSTMEM_WR_ADDR:    mmio64_if.readdata <= wr_ctrl.host_mem_magicnumber_addr;
                //host-to-FPGA transfers (read)
                HOST_RD_START_SRC_ADDR:         mmio64_if.readdata <= rd_ctrl.cmd.src_start_addr;
                HOST_RD_START_DST_ADDR:         mmio64_if.readdata <= rd_ctrl.cmd.dst_start_addr;
                HOST_RD_TRANSFER_LENGTH_ADDR:   mmio64_if.readdata <= rd_ctrl.cmd.xfer_length;
                HOST_RD_CMDQ_STATUS_ADDR:       mmio64_if.readdata <= rd_ctrl.cmdq_status;
                HOST_RD_DATABUF_STATUS_ADDR:    mmio64_if.readdata <= rd_ctrl.databuf_status;
                HOST_RD_CONFIG_ADDR:            mmio64_if.readdata <= 'b0;
                HOST_RD_STATUS_ADDR:            mmio64_if.readdata <= host_rd_status_reg_data;
                HOST_RD_BRSTCNT_CNT_ADDR:       mmio64_if.readdata <= rd_ctrl.src_burst_cnt_counter;
                HOST_RD_RDDATAVALID_CNT_ADDR:   mmio64_if.readdata <= rd_ctrl.src_readdatavalid_counter;
                HOST_RD_MAGICNUM_CNT_ADDR:      mmio64_if.readdata <= rd_ctrl.magic_number_counter;
                HOST_RD_WRDATA_CNT_ADDR:        mmio64_if.readdata <= rd_ctrl.dst_write_counter;
                HOST_RD_STATUS2_ADDR:           mmio64_if.readdata <= rd_ctrl.cntrl_sts;
                //FPGA-to-host transfers (write)
                HOST_WR_START_SRC_ADDR:         mmio64_if.readdata <= wr_ctrl.cmd.src_start_addr;
                HOST_WR_START_DST_ADDR:         mmio64_if.readdata <= wr_ctrl.cmd.dst_start_addr;
                HOST_WR_TRANSFER_LENGTH_ADDR:   mmio64_if.readdata <= wr_ctrl.cmd.xfer_length;
                HOST_WR_CMDQ_STATUS_ADDR:       mmio64_if.readdata <= wr_ctrl.cmdq_status;
                HOST_WR_DATABUF_STATUS_ADDR:    mmio64_if.readdata <= wr_ctrl.databuf_status;
                HOST_WR_CONFIG_ADDR:            mmio64_if.readdata <= 'b0;
                HOST_WR_STATUS_ADDR:            mmio64_if.readdata <= host_wr_status_reg_data;
                HOST_WR_BRSTCNT_CNT_ADDR:       mmio64_if.readdata <= wr_ctrl.src_burst_cnt_counter;
                HOST_WR_RDDATAVALID_CNT_ADDR:   mmio64_if.readdata <= wr_ctrl.src_readdatavalid_counter;
                HOST_WR_MAGICNUM_CNT_ADDR:      mmio64_if.readdata <= wr_ctrl.magic_number_counter;
                HOST_WR_WRDATA_CNT_ADDR:        mmio64_if.readdata <= wr_ctrl.dst_write_counter;
                HOST_WR_STATUS2_ADDR:           mmio64_if.readdata <= wr_ctrl.cntrl_sts;

                default:                        mmio64_if.readdata <= REG_RD_BADADDR_DATA;
            endcase
        end
        if (rst_local)           mmio64_if.readdata <= '0;
    end
    
    //disable the wait-req signal - we should always be able to accept commands
    always_comb begin
        mmio64_if.waitrequest = 'b0;
    end
    
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
    always_comb begin
        host_rd_status_reg_data = 'b0;
        host_rd_status_reg_data[0] = rd_ctrl.controller_busy_rd;
        host_rd_status_reg_data[1] = rd_ctrl.controller_busy_wr;
        host_rd_status_reg_data[2] = rd_ctrl.irq;
        
        host_wr_status_reg_data = 'b0;
        host_wr_status_reg_data[0] = wr_ctrl.controller_busy_rd;
        host_wr_status_reg_data[1] = wr_ctrl.controller_busy_wr;
        host_wr_status_reg_data[2] = wr_ctrl.irq;
    end

endmodule : dma_dispatcher
