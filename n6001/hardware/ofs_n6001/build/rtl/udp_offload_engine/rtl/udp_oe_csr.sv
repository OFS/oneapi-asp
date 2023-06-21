// Copyright 2022 Intel Corporation
// SPDX-License-Identifier: MIT
//

module udp_oe_csr
(
  ofs_plat_avalon_mem_if.to_source uoe_csr_avmm,
  
  udp_oe_ctrl_if.csr    udp_oe_ctrl,
  
  udp_oe_channel_if.csr udp_oe_pipe_ctrl_sts[dc_bsp_pkg::IO_PIPES_NUM_CHAN-1:0]
);

    import udp_oe_pkg::*;
    
    logic [63:0] dfh_header_data_reg;
    logic [63:0] scratchpad_reg;
    logic [63:0] dfh_reg_0x18, dfh_reg_0x20;
    integer i;
    
    //pipeline and duplicate the csr_rst signal
    parameter RESET_PIPE_DEPTH = 2;
    logic [RESET_PIPE_DEPTH-1:0] rst_pipe;
    logic rst_local;
    always_ff @(posedge uoe_csr_avmm.clk) begin
        {rst_local,rst_pipe}  <= {rst_pipe[RESET_PIPE_DEPTH-1:0], 1'b0};
        if (~uoe_csr_avmm.reset_n) begin
            rst_local <= '1;
            rst_pipe  <= '1;
        end
    end

    //the address is for bytes but register accesses are full words
    logic [9:0] this_address;
    assign this_address = uoe_csr_avmm.address>>3;
    
    //we should probably never assert waitrequest (max requests is 1)
    assign uoe_csr_avmm.waitrequest = 'b0;
    
    // read back CSR values
    always_ff @(posedge uoe_csr_avmm.clk) begin
        if (rst_local) begin
            uoe_csr_avmm.readdata <= 'b0;
            uoe_csr_avmm.readdatavalid <= 1'b0;
        end else begin
            uoe_csr_avmm.readdatavalid <= 1'b0;
            if (uoe_csr_avmm.read) begin
                uoe_csr_avmm.readdatavalid <= 1'b1;
                case (this_address)
                    // DFH registers
                    DFH_HEADER_ADDR:                uoe_csr_avmm.readdata <= dfh_header_data_reg;
                    DFH_ID_LO_ADDR:                 uoe_csr_avmm.readdata <= DFH_ID_LO;
                    DFH_ID_HI_ADDR:                 uoe_csr_avmm.readdata <= DFH_ID_HI;
                    DFH_REG_ADDR_OFFSET_ADDR:       uoe_csr_avmm.readdata <= dfh_reg_0x18;
                    DFH_REGSZ_PARAMS_GR_INST_ADDR:  uoe_csr_avmm.readdata <= dfh_reg_0x20;

                    // Common registers
                    SCRATCHPAD_ADDR:                 uoe_csr_avmm.readdata <= scratchpad_reg;
                    UDPOE_NUM_CHANNELS_ADDR:         uoe_csr_avmm.readdata <= dc_bsp_pkg::IO_PIPES_NUM_CHAN;
                    CSR_FPGA_MAC_ADR_ADDR:           uoe_csr_avmm.readdata <= {16'b0, udp_oe_ctrl.fpga_mac_adr};
                    CSR_FPGA_IP_ADR_ADDR:            uoe_csr_avmm.readdata <= {32'b0, udp_oe_ctrl.fpga_ip_adr}; 
                    CSR_FPGA_UDP_PORT_ADDR:          uoe_csr_avmm.readdata <= {48'b0, udp_oe_ctrl.fpga_udp_port};
                    CSR_FPGA_NETMASK_ADDR:           uoe_csr_avmm.readdata <= {32'b0, udp_oe_ctrl.fpga_netmask};
                    CSR_HOST_MAC_ADR_ADDR:           uoe_csr_avmm.readdata <= {16'b0, udp_oe_ctrl.host_mac_adr};
                    CSR_HOST_IP_ADR_ADDR:            uoe_csr_avmm.readdata <= {32'b0, udp_oe_ctrl.host_ip_adr};
                    CSR_HOST_UDP_PORT_ADDR:          uoe_csr_avmm.readdata <= {48'b0, udp_oe_ctrl.host_udp_port};
                    CSR_PAYLOAD_PER_PACKET_ADDR:     uoe_csr_avmm.readdata <= {48'b0, udp_oe_ctrl.payload_per_packet};
                    CSR_CHECKSUM_IP_ADDR:            uoe_csr_avmm.readdata <= {32'b0, udp_oe_ctrl.checksum_ip};
                    
                    //per-channel registers are handled outside this case statement
                    //
                    CSR_CHAN_INFO_REG_ADDR_CH0:         uoe_csr_avmm.readdata <= {47'h0,1'b0,8'h0,8'h10};
                    CSR_RESET_REG_ADDR_CH0    :         uoe_csr_avmm.readdata <= {62'b0, udp_oe_pipe_ctrl_sts[0].tx_rst,udp_oe_pipe_ctrl_sts[0].rx_rst};
                    CSR_STATUS_REG_ADDR_CH0   :         uoe_csr_avmm.readdata <= {udp_oe_pipe_ctrl_sts[0].tx_status,udp_oe_pipe_ctrl_sts[0].rx_status};
                    CSR_MISC_CTRL_REG_ADDR_CH0:         uoe_csr_avmm.readdata <= udp_oe_ctrl.misc_ctrl;
                    CSR_TX_STATUS_REG_ADDR_CH0:         uoe_csr_avmm.readdata <= 'b0;
                    CSR_RX_STATUS_REG_ADDR_CH0:         uoe_csr_avmm.readdata <= 'b0;
                    
                    //Channel-1
                    CSR_CHAN_INFO_REG_ADDR_CH1:         uoe_csr_avmm.readdata <= {47'h0,1'b1,8'h1,8'h10};
                    //CSR_RESET_REG_ADDR_CH1    :         uoe_csr_avmm.readdata <= {62'b0, udp_oe_pipe_ctrl_sts[1].tx_rst,udp_oe_pipe_ctrl_sts[1].rx_rst};
                    //CSR_STATUS_REG_ADDR_CH1   :         uoe_csr_avmm.readdata <= {udp_oe_pipe_ctrl_sts[1].tx_status,udp_oe_pipe_ctrl_sts[1].rx_status};
                    //CSR_MISC_CTRL_REG_ADDR_CH1:         uoe_csr_avmm.readdata <= udp_oe_ctrl.misc_ctrl;
                    //CSR_TX_STATUS_REG_ADDR_CH1:         uoe_csr_avmm.readdata <= 'b0;
                    //CSR_RX_STATUS_REG_ADDR_CH1:         uoe_csr_avmm.readdata <= 'b0;
                    
                    default:                         uoe_csr_avmm.readdata <= REG_RD_BADADDR_DATA;
                endcase
                //if (this_address >= UDPOE_CHAN_BASE_ADDR) begin
                //    //chan-info register is: 
                //        //63:17 rsvd
                //        //  16  end of channel list
                //        // 15:8 this channel ID
                //        // 7:0  offset to start of next channel CSRs (in words)
                //    //Channel-0
                //    CSR_CHAN_INFO_REG_ADDR_CH0:         uoe_csr_avmm.readdata <= {47'h0,1'b0,8'h0,8'h10};
                //    CSR_RESET_REG_ADDR_CH0    :         uoe_csr_avmm.readdata <= {61'b0, udp_oe_ctrl.tx_rst, 
                //                                                                     udp_oe_ctrl.rx_rst, 
                //                                                                     udp_oe_ctrl.csr_rst};
                //    CSR_STATUS_REG_ADDR_CH0   :         uoe_csr_avmm.readdata <= { udp_oe_ctrl.tx_status,udp_oe_ctrl.rx_status};
                //    CSR_MISC_CTRL_REG_ADDR_CH0:         uoe_csr_avmm.readdata <= udp_oe_ctrl.misc_ctrl;
                //    CSR_TX_STATUS_REG_ADDR_CH0:         uoe_csr_avmm.readdata <= 'b0;
                //    CSR_RX_STATUS_REG_ADDR_CH0:         uoe_csr_avmm.readdata <= 'b0;
                //    
                //    //Channel-1
                //    CSR_CHAN_INFO_REG_ADDR_CH1:         uoe_csr_avmm.readdata <= {47'h0,1'b1,8'h1,8'h10};
                //    CSR_RESET_REG_ADDR_CH1    :         uoe_csr_avmm.readdata <= {61'b0, udp_oe_ctrl.tx_rst, 
                //                                                              udp_oe_ctrl.rx_rst, 
                //                                                              udp_oe_ctrl.csr_rst};
                //    CSR_STATUS_REG_ADDR_CH1   :         uoe_csr_avmm.readdata <= { udp_oe_ctrl.tx_status,udp_oe_ctrl.rx_status};
                //    CSR_MISC_CTRL_REG_ADDR_CH1:         uoe_csr_avmm.readdata <= udp_oe_ctrl.misc_ctrl;
                //    CSR_TX_STATUS_REG_ADDR_CH1:         uoe_csr_avmm.readdata <= 'b0;
                //    CSR_RX_STATUS_REG_ADDR_CH1:         uoe_csr_avmm.readdata <= 'b0;
                //    //somehow need to wrap this up nicely in a for loop or something
                //    //case (this_address - UDPOE_CHAN_BASE_ADDR)
                //    //endcase
                //end
            end
        end
    end
   
    //writes
    always_ff @(posedge uoe_csr_avmm.clk)
    begin
        if (uoe_csr_avmm.write) begin
            case (this_address)
                SCRATCHPAD_ADDR:                scratchpad_reg              <= uoe_csr_avmm.writedata;
                // UDP Offload Engine registers
                //common/shared between all channels
                // FPGA MAC address
                CSR_FPGA_MAC_ADR_ADDR:          udp_oe_ctrl.fpga_mac_adr[47:0]        <= uoe_csr_avmm.writedata[47:0];
                // FPGA IP address
                CSR_FPGA_IP_ADR_ADDR:           udp_oe_ctrl.fpga_ip_adr[31:0]         <= uoe_csr_avmm.writedata[31:0];
                // FPGA UDP port
                CSR_FPGA_UDP_PORT_ADDR:         udp_oe_ctrl.fpga_udp_port[15:0]       <= uoe_csr_avmm.writedata[15:0];
                // FPGA Netmask
                CSR_FPGA_NETMASK_ADDR:          udp_oe_ctrl.fpga_netmask[31:0]        <= uoe_csr_avmm.writedata[31:0];
                // Host MAC address
                CSR_HOST_MAC_ADR_ADDR:          udp_oe_ctrl.host_mac_adr[47:0]        <= uoe_csr_avmm.writedata[47:0];
                // Host IP address
                CSR_HOST_IP_ADR_ADDR:           udp_oe_ctrl.host_ip_adr[31:0]         <= uoe_csr_avmm.writedata[31:0];
                // Host UDP port
                CSR_HOST_UDP_PORT_ADDR:         udp_oe_ctrl.host_udp_port[15:0]       <= uoe_csr_avmm.writedata[15:0];
                // Payload per packet
                CSR_PAYLOAD_PER_PACKET_ADDR:    udp_oe_ctrl.payload_per_packet[15:0]  <= uoe_csr_avmm.writedata[15:0];
                // IP checksum
                CSR_CHECKSUM_IP_ADDR:           udp_oe_ctrl.checksum_ip[15:0]         <= uoe_csr_avmm.writedata[15:0];
                //per-channel registers
                //need to clean this up with a for-loop and/or an array
                CSR_RESET_REG_ADDR_CH0:             {udp_oe_pipe_ctrl_sts[0].tx_rst, udp_oe_pipe_ctrl_sts[0].rx_rst} <= uoe_csr_avmm.writedata[1:0];
                CSR_MISC_CTRL_REG_ADDR_CH0:         udp_oe_ctrl.misc_ctrl                 <= uoe_csr_avmm.writedata;
                //CSR_RESET_REG_ADDR_CH1:             {udp_oe_pipe_ctrl_sts[1].tx_rst, udp_oe_pipe_ctrl_sts[1].rx_rst} <= uoe_csr_avmm.writedata[1:0];
                //CSR_MISC_CTRL_REG_ADDR_CH1:         udp_oe_ctrl.misc_ctrl                 <= uoe_csr_avmm.writedata;
            endcase
        end
    
        if (rst_local) begin
            scratchpad_reg                    <= 'h0;
            udp_oe_ctrl.fpga_mac_adr          <= 'h0;
            udp_oe_ctrl.fpga_ip_adr           <= 'h0;
            udp_oe_ctrl.fpga_mac_adr          <= 'h0;
            udp_oe_ctrl.fpga_ip_adr           <= 'h0;
            udp_oe_ctrl.fpga_udp_port         <= 'h0;
            udp_oe_ctrl.fpga_netmask          <= 'h0;
            udp_oe_ctrl.host_mac_adr          <= 'h0;
            udp_oe_ctrl.host_ip_adr           <= 'h0;
            udp_oe_ctrl.host_udp_port         <= 'h0;
            udp_oe_ctrl.payload_per_packet    <= 'h0;
            udp_oe_ctrl.checksum_ip           <= 'h0;
            udp_oe_ctrl.csr_rst               <= 'h0;
            udp_oe_ctrl.misc_ctrl             <= 'h0;
            
            //for (i = 0; i < dc_bsp_pkg::IO_PIPES_NUM_CHAN; i++) begin
                udp_oe_pipe_ctrl_sts[0].tx_rst    <= 'b0;
                udp_oe_pipe_ctrl_sts[0].rx_rst    <= 'b0;
                //udp_oe_pipe_ctrl_sts[1].tx_rst    <= 'b0;
                //udp_oe_pipe_ctrl_sts[1].rx_rst    <= 'b0;
            //end
            //udp_oe_pipe_ctrl_sts[1].tx_rst    <= 'b0;
            //udp_oe_pipe_ctrl_sts[1].rx_rst    <= 'b0;
        end
    end
  
    //verbose assignment of the DFHv1-header information (keep the register-logic clean by making
    //  assignments here; parameters defined in the package file.)
    always_comb begin
        dfh_header_data_reg = { DFH_HDR_FTYPE   ,
                                DFH_HDR_VER     ,
                                DFH_HDR_RSVD0   ,
                                DFH_HDL_EOL     ,
                                DFH_HDR_NEXT_DFH,
                                DFH_HDR_FEATURE_REV,
                                DFH_HDR_FEATURE_ID };
        dfh_reg_0x18 = {DFH_REG_ADDR_OFFSET, 
                        DFH_REL};
        dfh_reg_0x20 = {DFH_REG_SZ,
                        DFH_PARAMS,
                        DFH_GROUP,
                        DFH_INSTANCE};
    end
    
endmodule : udp_oe_csr
