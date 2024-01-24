// Copyright 2022 Intel Corporation
// SPDX-License-Identifier: MIT
//

package udp_oe_pkg;

    parameter BYTES_PER_WORD = 16'h0008;

    //Static register values for the UDP OE DFHv1 Information
    parameter DFH_HDR_FTYPE             = 4'h2;
    parameter DFH_HDR_VER               = 8'h01;
    parameter DFH_HDR_RSVD0             = 11'h0;
    parameter DFH_HDL_EOL               = 1'b0;
    parameter DFH_HDR_NEXT_DFH          = 24'h3800;
    parameter DFH_HDR_FEATURE_REV       = 4'h0;
    parameter DFH_HDR_FEATURE_ID        = 12'h0;

    parameter DFH_ID_LO = 64'h966d_1f07_871d_4396;
    parameter DFH_ID_HI = 64'h9c85_60c5_729f_f873;
    
    parameter DFH_NEXT_AFU_OFFSET = 24'h01_0000;

    parameter DFH_REG_ADDR_OFFSET = 63'b0;
    parameter DFH_REL             = 1'b0;
    
    parameter DFH_REG_SZ   = 32'd512;
    parameter DFH_PARAMS   = 1'b0;
    parameter DFH_GROUP    = 15'h0;
    parameter DFH_INSTANCE = 16'h0;
    
    // MMIO64 widths
    parameter MMIO64_ADDR_WIDTH = 8;
    parameter MMIO64_DATA_WIDTH = 64;
    
    //some packet header definitions
    parameter ETHERTYPE_IPv4 = 16'h0800;
    parameter ETHERTYPE_ARP  = 16'h0806;
    parameter IP_PROTOCOL_NUMBER_UDP = 8'h11;
    
    parameter IPv4_VERSION   = 4'h4;
    parameter IPv4_IHL       = 4'h5;
    parameter IPv4_DSCIP     = 6'h0;
    parameter IPv4_ECN       = 2'h0;
    parameter IPv4_FLAGS     = 3'h2; //don't fragment (DF)
    parameter IPv4_FOFFSET   = 13'h0;
    parameter IPv4_TTL       = 8'h40;
    parameter IPv4_PROTOCOL  = IP_PROTOCOL_NUMBER_UDP;
    
    parameter ARP_HTYPE      = 16'h0001;
    parameter ARP_FTYPE      = 16'h0800;
    parameter ARP_HLEN       = 8'h06;
    parameter ARP_PLEN       = 8'h04;
    parameter ARP_OPER       = 16'h0002;

    //data to return on a read that ends up in the default case
    parameter REG_RD_BADADDR_DATA = 64'h0BAD_0ADD_0BAD_0ADD;
    
    // TX DCFIFO parameters
    parameter TX_DCFIFO_DEPTH = 2048;
    parameter TX_DCFIFO_ALMOST_EMPTY_CUTOFF = 2;//orig = 511 ToDo: raise this back to a higher number
    parameter TX_DCFIFO_ALMOST_FULL_CUTOFF = TX_DCFIFO_DEPTH - 16;
    parameter DEFAULT_PAYLOAD_PER_PACKET = 2 * BYTES_PER_WORD;
    
    // RX DCFIFO parameters
    parameter RX_DCFIFO_DEPTH = 2048;
    
    //allow intra-ASP loopback?
    parameter ENABLE_INTRAASP_HSSI_TXRX_LOOPBACK = 0;
    
    //
    // Dispatcher register addresses
    //misc/DFH regs
    parameter DFHv1_GEN_BASE_ADDR           = 'h00;
    parameter DFH_HEADER_ADDR               = DFHv1_GEN_BASE_ADDR + 'h00;//ro
    parameter DFH_ID_LO_ADDR                = DFHv1_GEN_BASE_ADDR + 'h01;//ro
    parameter DFH_ID_HI_ADDR                = DFHv1_GEN_BASE_ADDR + 'h02;//ro
    parameter DFH_REG_ADDR_OFFSET_ADDR      = DFHv1_GEN_BASE_ADDR + 'h03;//ro
    parameter DFH_REGSZ_PARAMS_GR_INST_ADDR = DFHv1_GEN_BASE_ADDR + 'h04;//ro
    
    //UDP Offload Engine registers - common across all channels
    parameter REG_UDPOE_BASE_ADDR           = DFHv1_GEN_BASE_ADDR + 'h10;
    parameter SCRATCHPAD_ADDR               = REG_UDPOE_BASE_ADDR + 'h00;//rw
    parameter UDPOE_NUM_CHANNELS_ADDR       = REG_UDPOE_BASE_ADDR + 'h01;//ro
    parameter CSR_FPGA_MAC_ADR_ADDR         = REG_UDPOE_BASE_ADDR + 'h02;//rw
    parameter CSR_FPGA_IP_ADR_ADDR          = REG_UDPOE_BASE_ADDR + 'h03;//rw
    parameter CSR_FPGA_UDP_PORT_ADDR        = REG_UDPOE_BASE_ADDR + 'h04;//rw
    parameter CSR_FPGA_NETMASK_ADDR         = REG_UDPOE_BASE_ADDR + 'h05;//rw
    parameter CSR_HOST_MAC_ADR_ADDR         = REG_UDPOE_BASE_ADDR + 'h06;//rw
    parameter CSR_HOST_IP_ADR_ADDR          = REG_UDPOE_BASE_ADDR + 'h07;//rw
    parameter CSR_HOST_UDP_PORT_ADDR        = REG_UDPOE_BASE_ADDR + 'h08;//rw
    parameter CSR_PAYLOAD_PER_PACKET_ADDR   = REG_UDPOE_BASE_ADDR + 'h09;//rw
    parameter CSR_CHECKSUM_IP_ADDR          = REG_UDPOE_BASE_ADDR + 'h0A;//rw
    
    //UDP Offload Engine registers - per-channel
    parameter UDPOE_CHAN_BASE_ADDR          = REG_UDPOE_BASE_ADDR + 'h10;
    
    //generic offsets
    parameter CSR_ADDR_PER_CHANNEL      = 16;
    parameter CSR_CHAN_INFO_REG_ADDR    = 'h00;//ro
    parameter CSR_RESET_REG_ADDR        = 'h01;//rw
    parameter CSR_STATUS_REG_ADDR       = 'h02;//ro
    parameter CSR_MISC_CTRL_REG_ADDR    = 'h03;//rw
    parameter CSR_TX_STATUS_REG_ADDR    = 'h04;//ro
    parameter CSR_RX_STATUS_REG_ADDR    = 'h05;//ro
    
    
    parameter UDPOE_CHAN0_BASE_ADDR         = UDPOE_CHAN_BASE_ADDR;
    parameter CSR_CHAN_INFO_REG_ADDR_CH0    = UDPOE_CHAN0_BASE_ADDR + 'h00;//ro
    parameter CSR_RESET_REG_ADDR_CH0        = UDPOE_CHAN0_BASE_ADDR + 'h01;//rw
    parameter CSR_STATUS_REG_ADDR_CH0       = UDPOE_CHAN0_BASE_ADDR + 'h02;//ro
    parameter CSR_MISC_CTRL_REG_ADDR_CH0    = UDPOE_CHAN0_BASE_ADDR + 'h03;//rw
    parameter CSR_TX_STATUS_REG_ADDR_CH0    = UDPOE_CHAN0_BASE_ADDR + 'h04;//ro
    parameter CSR_RX_STATUS_REG_ADDR_CH0    = UDPOE_CHAN0_BASE_ADDR + 'h05;//ro
    
    parameter UDPOE_CHAN1_BASE_ADDR         = UDPOE_CHAN0_BASE_ADDR + 'h10;
    parameter CSR_CHAN_INFO_REG_ADDR_CH1    = UDPOE_CHAN1_BASE_ADDR + 'h00;//ro
    parameter CSR_RESET_REG_ADDR_CH1        = UDPOE_CHAN1_BASE_ADDR + 'h01;//rw
    parameter CSR_STATUS_REG_ADDR_CH1       = UDPOE_CHAN1_BASE_ADDR + 'h02;//ro
    parameter CSR_MISC_CTRL_REG_ADDR_CH1    = UDPOE_CHAN1_BASE_ADDR + 'h03;//rw
    parameter CSR_TX_STATUS_REG_ADDR_CH1    = UDPOE_CHAN1_BASE_ADDR + 'h04;//ro
    parameter CSR_RX_STATUS_REG_ADDR_CH1    = UDPOE_CHAN1_BASE_ADDR + 'h05;//ro
    
    parameter UDPOE_CHAN2_BASE_ADDR         = UDPOE_CHAN1_BASE_ADDR + 'h10;
    parameter CSR_CHAN_INFO_REG_ADDR_CH2    = UDPOE_CHAN2_BASE_ADDR + 'h00;//ro
    parameter CSR_RESET_REG_ADDR_CH2        = UDPOE_CHAN2_BASE_ADDR + 'h01;//rw
    parameter CSR_STATUS_REG_ADDR_CH2       = UDPOE_CHAN2_BASE_ADDR + 'h02;//ro
    parameter CSR_MISC_CTRL_REG_ADDR_CH2    = UDPOE_CHAN2_BASE_ADDR + 'h03;//rw
    parameter CSR_TX_STATUS_REG_ADDR_CH2    = UDPOE_CHAN2_BASE_ADDR + 'h04;//ro
    parameter CSR_RX_STATUS_REG_ADDR_CH2    = UDPOE_CHAN2_BASE_ADDR + 'h05;//ro
    
    parameter UDPOE_CHAN3_BASE_ADDR         = UDPOE_CHAN2_BASE_ADDR + 'h10;
    parameter CSR_CHAN_INFO_REG_ADDR_CH3    = UDPOE_CHAN3_BASE_ADDR + 'h00;//ro
    parameter CSR_RESET_REG_ADDR_CH3        = UDPOE_CHAN3_BASE_ADDR + 'h01;//rw
    parameter CSR_STATUS_REG_ADDR_CH3       = UDPOE_CHAN3_BASE_ADDR + 'h02;//ro
    parameter CSR_MISC_CTRL_REG_ADDR_CH3    = UDPOE_CHAN3_BASE_ADDR + 'h03;//rw
    parameter CSR_TX_STATUS_REG_ADDR_CH3    = UDPOE_CHAN3_BASE_ADDR + 'h04;//ro
    parameter CSR_RX_STATUS_REG_ADDR_CH3    = UDPOE_CHAN3_BASE_ADDR + 'h05;//ro
    
    parameter UDPOE_CHAN4_BASE_ADDR         = UDPOE_CHAN3_BASE_ADDR + 'h10;
    parameter CSR_CHAN_INFO_REG_ADDR_CH4    = UDPOE_CHAN4_BASE_ADDR + 'h00;//ro
    parameter CSR_RESET_REG_ADDR_CH4        = UDPOE_CHAN4_BASE_ADDR + 'h01;//rw
    parameter CSR_STATUS_REG_ADDR_CH4       = UDPOE_CHAN4_BASE_ADDR + 'h02;//ro
    parameter CSR_MISC_CTRL_REG_ADDR_CH4    = UDPOE_CHAN4_BASE_ADDR + 'h03;//rw
    parameter CSR_TX_STATUS_REG_ADDR_CH4    = UDPOE_CHAN4_BASE_ADDR + 'h04;//ro
    parameter CSR_RX_STATUS_REG_ADDR_CH4    = UDPOE_CHAN4_BASE_ADDR + 'h05;//ro
    
    parameter UDPOE_CHAN5_BASE_ADDR         = UDPOE_CHAN4_BASE_ADDR + 'h10;
    parameter CSR_CHAN_INFO_REG_ADDR_CH5    = UDPOE_CHAN5_BASE_ADDR + 'h00;//ro
    parameter CSR_RESET_REG_ADDR_CH5        = UDPOE_CHAN5_BASE_ADDR + 'h01;//rw
    parameter CSR_STATUS_REG_ADDR_CH5       = UDPOE_CHAN5_BASE_ADDR + 'h02;//ro
    parameter CSR_MISC_CTRL_REG_ADDR_CH5    = UDPOE_CHAN5_BASE_ADDR + 'h03;//rw
    parameter CSR_TX_STATUS_REG_ADDR_CH5    = UDPOE_CHAN5_BASE_ADDR + 'h04;//ro
    parameter CSR_RX_STATUS_REG_ADDR_CH5    = UDPOE_CHAN5_BASE_ADDR + 'h05;//ro
    
    parameter UDPOE_CHAN6_BASE_ADDR         = UDPOE_CHAN5_BASE_ADDR + 'h10;
    parameter CSR_CHAN_INFO_REG_ADDR_CH6    = UDPOE_CHAN6_BASE_ADDR + 'h00;//ro
    parameter CSR_RESET_REG_ADDR_CH6        = UDPOE_CHAN6_BASE_ADDR + 'h01;//rw
    parameter CSR_STATUS_REG_ADDR_CH6       = UDPOE_CHAN6_BASE_ADDR + 'h02;//ro
    parameter CSR_MISC_CTRL_REG_ADDR_CH6    = UDPOE_CHAN6_BASE_ADDR + 'h03;//rw
    parameter CSR_TX_STATUS_REG_ADDR_CH6    = UDPOE_CHAN6_BASE_ADDR + 'h04;//ro
    parameter CSR_RX_STATUS_REG_ADDR_CH6    = UDPOE_CHAN6_BASE_ADDR + 'h05;//ro
    
    parameter UDPOE_CHAN7_BASE_ADDR         = UDPOE_CHAN6_BASE_ADDR + 'h10;
    parameter CSR_CHAN_INFO_REG_ADDR_CH7    = UDPOE_CHAN7_BASE_ADDR + 'h00;//ro
    parameter CSR_RESET_REG_ADDR_CH7        = UDPOE_CHAN7_BASE_ADDR + 'h01;//rw
    parameter CSR_STATUS_REG_ADDR_CH7       = UDPOE_CHAN7_BASE_ADDR + 'h02;//ro
    parameter CSR_MISC_CTRL_REG_ADDR_CH7    = UDPOE_CHAN7_BASE_ADDR + 'h03;//rw
    parameter CSR_TX_STATUS_REG_ADDR_CH7    = UDPOE_CHAN7_BASE_ADDR + 'h04;//ro
    parameter CSR_RX_STATUS_REG_ADDR_CH7    = UDPOE_CHAN7_BASE_ADDR + 'h05;//ro
    
    parameter UDPOE_CHAN8_BASE_ADDR         = UDPOE_CHAN7_BASE_ADDR + 'h10;
    parameter CSR_CHAN_INFO_REG_ADDR_CH8    = UDPOE_CHAN8_BASE_ADDR + 'h00;//ro
    parameter CSR_RESET_REG_ADDR_CH8        = UDPOE_CHAN8_BASE_ADDR + 'h01;//rw
    parameter CSR_STATUS_REG_ADDR_CH8       = UDPOE_CHAN8_BASE_ADDR + 'h02;//ro
    parameter CSR_MISC_CTRL_REG_ADDR_CH8    = UDPOE_CHAN8_BASE_ADDR + 'h03;//rw
    parameter CSR_TX_STATUS_REG_ADDR_CH8    = UDPOE_CHAN8_BASE_ADDR + 'h04;//ro
    parameter CSR_RX_STATUS_REG_ADDR_CH8    = UDPOE_CHAN8_BASE_ADDR + 'h05;//ro
    
    parameter UDPOE_CHAN9_BASE_ADDR         = UDPOE_CHAN8_BASE_ADDR + 'h10;
    parameter CSR_CHAN_INFO_REG_ADDR_CH9    = UDPOE_CHAN9_BASE_ADDR + 'h00;//ro
    parameter CSR_RESET_REG_ADDR_CH9        = UDPOE_CHAN9_BASE_ADDR + 'h01;//rw
    parameter CSR_STATUS_REG_ADDR_CH9       = UDPOE_CHAN9_BASE_ADDR + 'h02;//ro
    parameter CSR_MISC_CTRL_REG_ADDR_CH9    = UDPOE_CHAN9_BASE_ADDR + 'h03;//rw
    parameter CSR_TX_STATUS_REG_ADDR_CH9    = UDPOE_CHAN9_BASE_ADDR + 'h04;//ro
    parameter CSR_RX_STATUS_REG_ADDR_CH9    = UDPOE_CHAN9_BASE_ADDR + 'h05;//ro
    
    parameter UDPOE_CHAN10_BASE_ADDR         = UDPOE_CHAN9_BASE_ADDR + 'h10;
    parameter CSR_CHAN_INFO_REG_ADDR_CH10    = UDPOE_CHAN10_BASE_ADDR + 'h00;//ro
    parameter CSR_RESET_REG_ADDR_CH10        = UDPOE_CHAN10_BASE_ADDR + 'h01;//rw
    parameter CSR_STATUS_REG_ADDR_CH10       = UDPOE_CHAN10_BASE_ADDR + 'h02;//ro
    parameter CSR_MISC_CTRL_REG_ADDR_CH10    = UDPOE_CHAN10_BASE_ADDR + 'h03;//rw
    parameter CSR_TX_STATUS_REG_ADDR_CH10    = UDPOE_CHAN10_BASE_ADDR + 'h04;//ro
    parameter CSR_RX_STATUS_REG_ADDR_CH10    = UDPOE_CHAN10_BASE_ADDR + 'h05;//ro
    
    parameter UDPOE_CHAN11_BASE_ADDR         = UDPOE_CHAN10_BASE_ADDR + 'h10;
    parameter CSR_CHAN_INFO_REG_ADDR_CH11    = UDPOE_CHAN11_BASE_ADDR + 'h00;//ro
    parameter CSR_RESET_REG_ADDR_CH11        = UDPOE_CHAN11_BASE_ADDR + 'h01;//rw
    parameter CSR_STATUS_REG_ADDR_CH11       = UDPOE_CHAN11_BASE_ADDR + 'h02;//ro
    parameter CSR_MISC_CTRL_REG_ADDR_CH11    = UDPOE_CHAN11_BASE_ADDR + 'h03;//rw
    parameter CSR_TX_STATUS_REG_ADDR_CH11    = UDPOE_CHAN11_BASE_ADDR + 'h04;//ro
    parameter CSR_RX_STATUS_REG_ADDR_CH11    = UDPOE_CHAN11_BASE_ADDR + 'h05;//ro
    
    parameter UDPOE_CHAN12_BASE_ADDR         = UDPOE_CHAN11_BASE_ADDR + 'h10;
    parameter CSR_CHAN_INFO_REG_ADDR_CH12    = UDPOE_CHAN12_BASE_ADDR + 'h00;//ro
    parameter CSR_RESET_REG_ADDR_CH12        = UDPOE_CHAN12_BASE_ADDR + 'h01;//rw
    parameter CSR_STATUS_REG_ADDR_CH12       = UDPOE_CHAN12_BASE_ADDR + 'h02;//ro
    parameter CSR_MISC_CTRL_REG_ADDR_CH12    = UDPOE_CHAN12_BASE_ADDR + 'h03;//rw
    parameter CSR_TX_STATUS_REG_ADDR_CH12    = UDPOE_CHAN12_BASE_ADDR + 'h04;//ro
    parameter CSR_RX_STATUS_REG_ADDR_CH12    = UDPOE_CHAN12_BASE_ADDR + 'h05;//ro
    
    parameter UDPOE_CHAN13_BASE_ADDR         = UDPOE_CHAN12_BASE_ADDR + 'h10;
    parameter CSR_CHAN_INFO_REG_ADDR_CH13    = UDPOE_CHAN13_BASE_ADDR + 'h00;//ro
    parameter CSR_RESET_REG_ADDR_CH13        = UDPOE_CHAN13_BASE_ADDR + 'h01;//rw
    parameter CSR_STATUS_REG_ADDR_CH13       = UDPOE_CHAN13_BASE_ADDR + 'h02;//ro
    parameter CSR_MISC_CTRL_REG_ADDR_CH13    = UDPOE_CHAN13_BASE_ADDR + 'h03;//rw
    parameter CSR_TX_STATUS_REG_ADDR_CH13    = UDPOE_CHAN13_BASE_ADDR + 'h04;//ro
    parameter CSR_RX_STATUS_REG_ADDR_CH13    = UDPOE_CHAN13_BASE_ADDR + 'h05;//ro
    
    parameter UDPOE_CHAN14_BASE_ADDR         = UDPOE_CHAN13_BASE_ADDR + 'h10;
    parameter CSR_CHAN_INFO_REG_ADDR_CH14    = UDPOE_CHAN14_BASE_ADDR + 'h00;//ro
    parameter CSR_RESET_REG_ADDR_CH14        = UDPOE_CHAN14_BASE_ADDR + 'h01;//rw
    parameter CSR_STATUS_REG_ADDR_CH14       = UDPOE_CHAN14_BASE_ADDR + 'h02;//ro
    parameter CSR_MISC_CTRL_REG_ADDR_CH14    = UDPOE_CHAN14_BASE_ADDR + 'h03;//rw
    parameter CSR_TX_STATUS_REG_ADDR_CH14    = UDPOE_CHAN14_BASE_ADDR + 'h04;//ro
    parameter CSR_RX_STATUS_REG_ADDR_CH14    = UDPOE_CHAN14_BASE_ADDR + 'h05;//ro
    
    parameter UDPOE_CHAN15_BASE_ADDR         = UDPOE_CHAN14_BASE_ADDR + 'h10;
    parameter CSR_CHAN_INFO_REG_ADDR_CH15    = UDPOE_CHAN15_BASE_ADDR + 'h00;//ro
    parameter CSR_RESET_REG_ADDR_CH15        = UDPOE_CHAN15_BASE_ADDR + 'h01;//rw
    parameter CSR_STATUS_REG_ADDR_CH15       = UDPOE_CHAN15_BASE_ADDR + 'h02;//ro
    parameter CSR_MISC_CTRL_REG_ADDR_CH15    = UDPOE_CHAN15_BASE_ADDR + 'h03;//rw
    parameter CSR_TX_STATUS_REG_ADDR_CH15    = UDPOE_CHAN15_BASE_ADDR + 'h04;//ro
    parameter CSR_RX_STATUS_REG_ADDR_CH15    = UDPOE_CHAN15_BASE_ADDR + 'h05;//ro
    
    
endpackage : udp_oe_pkg
