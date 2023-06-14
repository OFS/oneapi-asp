// Copyright 2022 Intel Corporation
// SPDX-License-Identifier: MIT
//

interface udp_oe_ctrl_if;
    
    logic [47:0]     fpga_mac_adr;
    logic [31:0]     fpga_ip_adr;
    logic [15:0]     fpga_udp_port;
    logic [31:0]     fpga_netmask;

    logic [47:0]     host_mac_adr;
    logic [31:0]     host_ip_adr;
    logic [15:0]     host_udp_port;

    logic [15:0]     payload_per_packet;
    logic [15:0]     checksum_ip;

    //logic [MAX_NUM_CHANNELS-1:0] num_channels;
    
    logic            tx_rst;
    logic            rx_rst;
    logic            csr_rst;
    
    typedef struct packed {
        logic [15:0] pkt_count;
        logic [15:0] sm_state;
    } t_status;
    t_status tx_status, rx_status;
    
    typedef struct packed {
        logic   intrabsp_txrx_loopback;
    } t_misc_ctrl;
    t_misc_ctrl misc_ctrl;

    //CSR module (source)
    modport csr (
        input   tx_status, rx_status,
        output  fpga_mac_adr,
                fpga_ip_adr,
                fpga_udp_port,
                fpga_netmask,
                host_mac_adr,
                host_ip_adr,
                host_udp_port,
                payload_per_packet,
                checksum_ip,
                tx_rst,
                rx_rst,
                csr_rst,
                misc_ctrl
    );
    
    //TX path
    modport tx (
        output  tx_status, 
        input   fpga_mac_adr,
                fpga_ip_adr,
                fpga_udp_port,
                fpga_netmask,
                host_mac_adr,
                host_ip_adr,
                host_udp_port,
                payload_per_packet,
                checksum_ip,
                tx_rst
    );
    
    //RX path
    modport rx (
        output  rx_status, 
        input   fpga_ip_adr,
                host_ip_adr,
                host_mac_adr,
                rx_rst
    );

endinterface : udp_oe_ctrl_if

//interface udpoe_channel_if;
    

//endinterface : udpoe_channel_if
