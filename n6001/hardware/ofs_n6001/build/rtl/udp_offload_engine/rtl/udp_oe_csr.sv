// Copyright 2022 Intel Corporation
// SPDX-License-Identifier: MIT
//

module udp_oe_csr
import ofs_asp_pkg::*;
(
  ofs_plat_avalon_mem_if.to_source uoe_csr_avmm,
  
  udp_oe_ctrl_if.csr    udp_oe_ctrl,
  
  udp_oe_channel_if.csr udp_oe_pipe_ctrl_sts[IO_PIPES_NUM_CHAN-1:0]
);

    import udp_oe_pkg::*;
    
    logic [MMIO64_DATA_WIDTH-1:0] dfh_header_data_reg;
    logic [MMIO64_DATA_WIDTH-1:0] scratchpad_reg;
    logic [MMIO64_DATA_WIDTH-1:0] dfh_reg_0x18, dfh_reg_0x20;
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
    
    //create an array of registers to handle CSR stuff for a programmable number of channels
    //without adding a lot of duplicative case() entries.
    logic [MMIO64_DATA_WIDTH-1:0] csr [IO_PIPES_NUM_CHAN*CSR_ADDR_PER_CHANNEL-1:0];
    logic [7:0] ch_csr_addr;
    localparam START_OF_CH_CSR_ADDR = UDPOE_CHAN_BASE_ADDR;
    localparam END_OF_CH_CSR_ADDR   = UDPOE_CHAN_BASE_ADDR + (IO_PIPES_NUM_CHAN*CSR_ADDR_PER_CHANNEL) - 1;
    genvar c;
    generate
        for (c = 0; c < IO_PIPES_NUM_CHAN; c++) begin: ch_csrs
            logic [7:0] this_channel;
            assign this_channel = c;
            always_comb begin
                csr[c*CSR_ADDR_PER_CHANNEL+CSR_CHAN_INFO_REG_ADDR]    = {47'h0,1'b0,this_channel,8'h10};
                csr[c*CSR_ADDR_PER_CHANNEL+CSR_RESET_REG_ADDR    ]    = {62'b0, udp_oe_pipe_ctrl_sts[c].tx_rst,udp_oe_pipe_ctrl_sts[c].rx_rst};
                csr[c*CSR_ADDR_PER_CHANNEL+CSR_STATUS_REG_ADDR   ]    = {udp_oe_pipe_ctrl_sts[c].tx_status,udp_oe_pipe_ctrl_sts[c].rx_status};
                csr[c*CSR_ADDR_PER_CHANNEL+CSR_MISC_CTRL_REG_ADDR]    = udp_oe_ctrl.misc_ctrl;
                csr[c*CSR_ADDR_PER_CHANNEL+CSR_TX_STATUS_REG_ADDR]    = 'b0;
                csr[c*CSR_ADDR_PER_CHANNEL+CSR_RX_STATUS_REG_ADDR]    = 'b0;
            end //always_comb
        end //for
    endgenerate
    assign ch_csr_addr = this_address - UDPOE_CHAN_BASE_ADDR;
    
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
                    UDPOE_NUM_CHANNELS_ADDR:         uoe_csr_avmm.readdata <= IO_PIPES_NUM_CHAN;
                    CSR_FPGA_MAC_ADR_ADDR:           uoe_csr_avmm.readdata <= {16'b0, udp_oe_ctrl.fpga_mac_adr};
                    CSR_FPGA_IP_ADR_ADDR:            uoe_csr_avmm.readdata <= {32'b0, udp_oe_ctrl.fpga_ip_adr}; 
                    CSR_FPGA_UDP_PORT_ADDR:          uoe_csr_avmm.readdata <= {48'b0, udp_oe_ctrl.fpga_udp_port};
                    CSR_FPGA_NETMASK_ADDR:           uoe_csr_avmm.readdata <= {32'b0, udp_oe_ctrl.fpga_netmask};
                    CSR_HOST_MAC_ADR_ADDR:           uoe_csr_avmm.readdata <= {16'b0, udp_oe_ctrl.host_mac_adr};
                    CSR_HOST_IP_ADR_ADDR:            uoe_csr_avmm.readdata <= {32'b0, udp_oe_ctrl.host_ip_adr};
                    CSR_HOST_UDP_PORT_ADDR:          uoe_csr_avmm.readdata <= {48'b0, udp_oe_ctrl.host_udp_port};
                    CSR_PAYLOAD_PER_PACKET_ADDR:     uoe_csr_avmm.readdata <= {48'b0, udp_oe_ctrl.payload_per_packet};
                    CSR_CHECKSUM_IP_ADDR:            uoe_csr_avmm.readdata <= {32'b0, udp_oe_ctrl.checksum_ip};

                    default:                        begin
                                                        if (this_address >= START_OF_CH_CSR_ADDR && this_address <= END_OF_CH_CSR_ADDR) begin
                                                            uoe_csr_avmm.readdata <= csr[ch_csr_addr];
                                                        end else begin
                                                            uoe_csr_avmm.readdata <= REG_RD_BADADDR_DATA;
                                                        end
                                                    end //default
                endcase
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
                CSR_RESET_REG_ADDR_CH0:             {udp_oe_pipe_ctrl_sts[0].tx_rst, udp_oe_pipe_ctrl_sts[0].rx_rst} <= uoe_csr_avmm.writedata[1:0];
                CSR_MISC_CTRL_REG_ADDR_CH0:         udp_oe_ctrl.misc_ctrl                 <= uoe_csr_avmm.writedata;
                //Channel-1
                `ifdef ASP_ENABLE_IOPIPE1
                    CSR_RESET_REG_ADDR_CH1:             {udp_oe_pipe_ctrl_sts[1].tx_rst, udp_oe_pipe_ctrl_sts[1].rx_rst} <= uoe_csr_avmm.writedata[1:0];
                    CSR_MISC_CTRL_REG_ADDR_CH1:         udp_oe_ctrl.misc_ctrl                 <= uoe_csr_avmm.writedata;
                `endif //ASP_ENABLE_IOPIPE1
                //Channel-2
                `ifdef ASP_ENABLE_IOPIPE2
                    CSR_RESET_REG_ADDR_CH2:             {udp_oe_pipe_ctrl_sts[2].tx_rst, udp_oe_pipe_ctrl_sts[2].rx_rst} <= uoe_csr_avmm.writedata[1:0];
                    CSR_MISC_CTRL_REG_ADDR_CH2:         udp_oe_ctrl.misc_ctrl                 <= uoe_csr_avmm.writedata;
                `endif //ASP_ENABLE_IOPIPE2
                //Channel-3
                `ifdef ASP_ENABLE_IOPIPE3
                    CSR_RESET_REG_ADDR_CH3:             {udp_oe_pipe_ctrl_sts[3].tx_rst, udp_oe_pipe_ctrl_sts[3].rx_rst} <= uoe_csr_avmm.writedata[1:0];
                    CSR_MISC_CTRL_REG_ADDR_CH3:         udp_oe_ctrl.misc_ctrl                 <= uoe_csr_avmm.writedata;
                `endif //ASP_ENABLE_IOPIPE3
                //Channel-4
                `ifdef ASP_ENABLE_IOPIPE4
                    CSR_RESET_REG_ADDR_CH4:             {udp_oe_pipe_ctrl_sts[4].tx_rst, udp_oe_pipe_ctrl_sts[4].rx_rst} <= uoe_csr_avmm.writedata[1:0];
                    CSR_MISC_CTRL_REG_ADDR_CH4:         udp_oe_ctrl.misc_ctrl                 <= uoe_csr_avmm.writedata;
                `endif //ASP_ENABLE_IOPIPE4
                //Channel-5
                `ifdef ASP_ENABLE_IOPIPE5
                    CSR_RESET_REG_ADDR_CH5:             {udp_oe_pipe_ctrl_sts[5].tx_rst, udp_oe_pipe_ctrl_sts[5].rx_rst} <= uoe_csr_avmm.writedata[1:0];
                    CSR_MISC_CTRL_REG_ADDR_CH5:         udp_oe_ctrl.misc_ctrl                 <= uoe_csr_avmm.writedata;
                `endif //ASP_ENABLE_IOPIPE5
                //Channel-6
                `ifdef ASP_ENABLE_IOPIPE6
                    CSR_RESET_REG_ADDR_CH6:             {udp_oe_pipe_ctrl_sts[6].tx_rst, udp_oe_pipe_ctrl_sts[6].rx_rst} <= uoe_csr_avmm.writedata[1:0];
                    CSR_MISC_CTRL_REG_ADDR_CH6:         udp_oe_ctrl.misc_ctrl                 <= uoe_csr_avmm.writedata;
                `endif //ASP_ENABLE_IOPIPE6
                //Channel-7
                `ifdef ASP_ENABLE_IOPIPE7
                    CSR_RESET_REG_ADDR_CH7:             {udp_oe_pipe_ctrl_sts[7].tx_rst, udp_oe_pipe_ctrl_sts[7].rx_rst} <= uoe_csr_avmm.writedata[1:0];
                    CSR_MISC_CTRL_REG_ADDR_CH7:         udp_oe_ctrl.misc_ctrl                 <= uoe_csr_avmm.writedata;
                `endif //ASP_ENABLE_IOPIPE7
                //Channel-8
                `ifdef ASP_ENABLE_IOPIPE8
                    CSR_RESET_REG_ADDR_CH8:             {udp_oe_pipe_ctrl_sts[8].tx_rst, udp_oe_pipe_ctrl_sts[8].rx_rst} <= uoe_csr_avmm.writedata[1:0];
                    CSR_MISC_CTRL_REG_ADDR_CH8:         udp_oe_ctrl.misc_ctrl                 <= uoe_csr_avmm.writedata;
                `endif //ASP_ENABLE_IOPIPE8
                //Channel-9
                `ifdef ASP_ENABLE_IOPIPE9
                    CSR_RESET_REG_ADDR_CH9:             {udp_oe_pipe_ctrl_sts[9].tx_rst, udp_oe_pipe_ctrl_sts[9].rx_rst} <= uoe_csr_avmm.writedata[1:0];
                    CSR_MISC_CTRL_REG_ADDR_CH9:         udp_oe_ctrl.misc_ctrl                 <= uoe_csr_avmm.writedata;
                `endif //ASP_ENABLE_IOPIPE9
                //Channel-10
                `ifdef ASP_ENABLE_IOPIPE10
                    CSR_RESET_REG_ADDR_CH10:             {udp_oe_pipe_ctrl_sts[10].tx_rst, udp_oe_pipe_ctrl_sts[10].rx_rst} <= uoe_csr_avmm.writedata[1:0];
                    CSR_MISC_CTRL_REG_ADDR_CH10:         udp_oe_ctrl.misc_ctrl                 <= uoe_csr_avmm.writedata;
                `endif //ASP_ENABLE_IOPIPE10
                //Channel-11
                `ifdef ASP_ENABLE_IOPIPE11
                    CSR_RESET_REG_ADDR_CH11:             {udp_oe_pipe_ctrl_sts[11].tx_rst, udp_oe_pipe_ctrl_sts[11].rx_rst} <= uoe_csr_avmm.writedata[1:0];
                    CSR_MISC_CTRL_REG_ADDR_CH11:         udp_oe_ctrl.misc_ctrl                 <= uoe_csr_avmm.writedata;
                `endif //ASP_ENABLE_IOPIPE11
                //Channel-12
                `ifdef ASP_ENABLE_IOPIPE12
                    CSR_RESET_REG_ADDR_CH12:             {udp_oe_pipe_ctrl_sts[12].tx_rst, udp_oe_pipe_ctrl_sts[12].rx_rst} <= uoe_csr_avmm.writedata[1:0];
                    CSR_MISC_CTRL_REG_ADDR_CH12:         udp_oe_ctrl.misc_ctrl                 <= uoe_csr_avmm.writedata;
                `endif //ASP_ENABLE_IOPIPE12
                //Channel-13
                `ifdef ASP_ENABLE_IOPIPE13
                    CSR_RESET_REG_ADDR_CH13:             {udp_oe_pipe_ctrl_sts[13].tx_rst, udp_oe_pipe_ctrl_sts[13].rx_rst} <= uoe_csr_avmm.writedata[1:0];
                    CSR_MISC_CTRL_REG_ADDR_CH13:         udp_oe_ctrl.misc_ctrl                 <= uoe_csr_avmm.writedata;
                `endif //ASP_ENABLE_IOPIPE13
                //Channel-14
                `ifdef ASP_ENABLE_IOPIPE14
                    CSR_RESET_REG_ADDR_CH14:             {udp_oe_pipe_ctrl_sts[14].tx_rst, udp_oe_pipe_ctrl_sts[14].rx_rst} <= uoe_csr_avmm.writedata[1:0];
                    CSR_MISC_CTRL_REG_ADDR_CH14:         udp_oe_ctrl.misc_ctrl                 <= uoe_csr_avmm.writedata;
                `endif //ASP_ENABLE_IOPIPE14
                //Channel-15
                `ifdef ASP_ENABLE_IOPIPE15
                    CSR_RESET_REG_ADDR_CH15:             {udp_oe_pipe_ctrl_sts[15].tx_rst, udp_oe_pipe_ctrl_sts[15].rx_rst} <= uoe_csr_avmm.writedata[1:0];
                    CSR_MISC_CTRL_REG_ADDR_CH15:         udp_oe_ctrl.misc_ctrl                 <= uoe_csr_avmm.writedata;
                `endif //ASP_ENABLE_IOPIPE15
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
            udp_oe_ctrl.payload_per_packet    <= DEFAULT_PAYLOAD_PER_PACKET;
            udp_oe_ctrl.checksum_ip           <= 'h0;
            udp_oe_ctrl.csr_rst               <= 'h0;
            udp_oe_ctrl.misc_ctrl             <= 'h0;
            
            udp_oe_pipe_ctrl_sts[0].tx_rst    <= 'b0;
            udp_oe_pipe_ctrl_sts[0].rx_rst    <= 'b0;
            //Channel-1
            `ifdef ASP_ENABLE_IOPIPE1
                udp_oe_pipe_ctrl_sts[1].tx_rst    <= 'b0;
                udp_oe_pipe_ctrl_sts[1].rx_rst    <= 'b0;
            `endif //ASP_ENABLE_IOPIPE1
            //Channel-2
            `ifdef ASP_ENABLE_IOPIPE2
                udp_oe_pipe_ctrl_sts[2].tx_rst    <= 'b0;
                udp_oe_pipe_ctrl_sts[2].rx_rst    <= 'b0;
            `endif //ASP_ENABLE_IOPIPE2
            //Channel-3
            `ifdef ASP_ENABLE_IOPIPE3
                udp_oe_pipe_ctrl_sts[3].tx_rst    <= 'b0;
                udp_oe_pipe_ctrl_sts[3].rx_rst    <= 'b0;
            `endif //ASP_ENABLE_IOPIPE3
            //Channel-4
            `ifdef ASP_ENABLE_IOPIPE4
                udp_oe_pipe_ctrl_sts[4].tx_rst    <= 'b0;
                udp_oe_pipe_ctrl_sts[4].rx_rst    <= 'b0;
            `endif //ASP_ENABLE_IOPIPE4
            //Channel-5
            `ifdef ASP_ENABLE_IOPIPE5
                udp_oe_pipe_ctrl_sts[5].tx_rst    <= 'b0;
                udp_oe_pipe_ctrl_sts[5].rx_rst    <= 'b0;
            `endif //ASP_ENABLE_IOPIPE5
            //Channel-6
            `ifdef ASP_ENABLE_IOPIPE6
                udp_oe_pipe_ctrl_sts[6].tx_rst    <= 'b0;
                udp_oe_pipe_ctrl_sts[6].rx_rst    <= 'b0;
            `endif //ASP_ENABLE_IOPIPE6
            //Channel-7
            `ifdef ASP_ENABLE_IOPIPE7
                udp_oe_pipe_ctrl_sts[7].tx_rst    <= 'b0;
                udp_oe_pipe_ctrl_sts[7].rx_rst    <= 'b0;
            `endif //ASP_ENABLE_IOPIPE7
            //Channel-8
            `ifdef ASP_ENABLE_IOPIPE8
                udp_oe_pipe_ctrl_sts[8].tx_rst    <= 'b0;
                udp_oe_pipe_ctrl_sts[8].rx_rst    <= 'b0;
            `endif //ASP_ENABLE_IOPIPE8
            //Channel-9
            `ifdef ASP_ENABLE_IOPIPE9
                udp_oe_pipe_ctrl_sts[9].tx_rst    <= 'b0;
                udp_oe_pipe_ctrl_sts[9].rx_rst    <= 'b0;
            `endif //ASP_ENABLE_IOPIPE9
            //Channel-10
            `ifdef ASP_ENABLE_IOPIPE10
                udp_oe_pipe_ctrl_sts[10].tx_rst    <= 'b0;
                udp_oe_pipe_ctrl_sts[10].rx_rst    <= 'b0;
            `endif //ASP_ENABLE_IOPIPE10
            //Channel-11
            `ifdef ASP_ENABLE_IOPIPE11
                udp_oe_pipe_ctrl_sts[11].tx_rst    <= 'b0;
                udp_oe_pipe_ctrl_sts[11].rx_rst    <= 'b0;
            `endif //ASP_ENABLE_IOPIPE11
            //Channel-12
            `ifdef ASP_ENABLE_IOPIPE12
                udp_oe_pipe_ctrl_sts[12].tx_rst    <= 'b0;
                udp_oe_pipe_ctrl_sts[12].rx_rst    <= 'b0;
            `endif //ASP_ENABLE_IOPIPE12
            //Channel-13
            `ifdef ASP_ENABLE_IOPIPE13
                udp_oe_pipe_ctrl_sts[13].tx_rst    <= 'b0;
                udp_oe_pipe_ctrl_sts[13].rx_rst    <= 'b0;
            `endif //ASP_ENABLE_IOPIPE13
            //Channel-14
            `ifdef ASP_ENABLE_IOPIPE14
                udp_oe_pipe_ctrl_sts[14].tx_rst    <= 'b0;
                udp_oe_pipe_ctrl_sts[14].rx_rst    <= 'b0;
            `endif //ASP_ENABLE_IOPIPE14
            //Channel-15
            `ifdef ASP_ENABLE_IOPIPE15
                udp_oe_pipe_ctrl_sts[15].tx_rst    <= 'b0;
                udp_oe_pipe_ctrl_sts[15].rx_rst    <= 'b0;
            `endif //ASP_ENABLE_IOPIPE15
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
