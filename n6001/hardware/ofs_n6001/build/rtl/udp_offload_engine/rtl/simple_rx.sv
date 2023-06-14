// Copyright 2022 Intel Corporation
// SPDX-License-Identifier: MIT
//

module simple_rx
(
  input logic         kernel_clk,
  input logic         kernel_resetn,

  udp_oe_ctrl_if.rx udp_oe_ctrl,
  
  // from Ethernet MAC
  ofs_fim_hssi_ss_rx_axis_if.client eth_rx_axis,

  // to kernel
  shim_avst_if.source udp_avst_to_kernel,

  // to TX of UDP offload engine for ARP response
  output logic        arp_trigger
);
  import dc_bsp_pkg::*;
  import udp_oe_pkg::*;
  
  logic         mac_eth_startofpacket;
  logic         mac_eth_endofpacket;
  logic         mac_eth_valid;
  logic [63:0]  mac_eth_data;
  
  logic eth_mac_startofpacket;
  logic is_rx_sop;
  
  logic [15:0] rx_word_counter;
  
  logic        wr_full;          // FIFO full
  logic        rd_empty;         // FIFO empty
  
  logic mac_eth_valid_sop;
  logic mac_eth_valid_eop;
  logic mac_eth_data_arp;
  logic mac_eth_data_hostmacadr47_32;
  
  always_comb begin
      mac_eth_startofpacket = eth_rx_axis.rx.tvalid & is_rx_sop;
      mac_eth_endofpacket = eth_rx_axis.rx.tvalid & eth_rx_axis.rx.tlast;
      mac_eth_valid = eth_rx_axis.rx.tvalid;
      mac_eth_data  = eth_rx_axis.rx.tdata;
      //mac_eth_empty = ofs_fim_eth_avst_if_pkg::eth_tkeep_to_empty(eth_rx_axis.rx.tkeep);
  end
  // Rx SOP always follows a tlast AXI-S flit
  always_ff @(posedge eth_rx_axis.clk)
  begin
     if (!eth_rx_axis.rst_n)
        is_rx_sop <= 1'b1;
     else if (eth_rx_axis.rx.tvalid)
        is_rx_sop <= eth_rx_axis.rx.tlast;
  end

  assign udp_avst_to_kernel.valid = ~rd_empty; // data valid for kernel when FIFO is non-empty

  acl_dcfifo #(
    .WIDTH         (64),     
    .DEPTH         (2048),
    .RAM_BLOCK_TYPE("M20K")  
  )
  rx_dcfifo
  (
    .async_resetn           (eth_rx_axis.rst_n),

    .wr_clock               (eth_rx_axis.clk),
    .wr_req                 (tok_udp_avst_ethclk.valid),
    .wr_data                (tok_udp_avst_ethclk.data),
    .wr_full                (wr_full),

    .rd_clock               (kernel_clk),
    .rd_ack                 (udp_avst_to_kernel.ready),
    .rd_empty               (rd_empty),
    .rd_data                (udp_avst_to_kernel.data)
  );

  shim_avst_if tok_udp_avst_ethclk();

  // FSM states
  // The data presented from the Ethernet MAC RX follows the depicted states below
  enum {
    STATE_IDLE,    // waiting for new UDP packet, 
                   // MAC header    (Destination MAC address[47:0], Source MAC address[47:32])
    STATE_MAC0,    // MAC header    (Source MAC address[31:0], IP header (0x0806, 0x4500))
    STATE_IP0,     // IP header     (IP packet length[15:0], 0x0000, 0x4000, 0x40, 0x11)
    STATE_IP1,     // IP header     (Checksum[15:0], Source IP address[31:0], Destination IP address[31:16])
    STATE_UDP0,    // IP/UDP header (Destination IP address[15:0], UDP Source port [15:0], UDP Destination port[15:0], UDP packet length[15:0])
    STATE_UDP1,    // UDP header    (Checksum[15:0], packet counter)
    STATE_PAYLOAD, // UDP Payload
    STATE_ARP_REQUEST0, //drop the data
    STATE_ARP_REQUEST1,
    STATE_ARP_REQUEST2,
    STATE_ARP_REQUEST3,
    STATE_ARP_REQUEST4,
    STATE_ARP_RESPONSE
  } state;

  // FSM for UDP packet decoding 
  // - always starts in IDLE state (for reset and after all payload is received which is indicated by mac_eth_endofpacket)
  // - FSM progresses through states in case received data from Ethernet is valid (mac_eth_valid)
  // - any mac_eth_startofpacket brings the FSM back to the MAC0 start (in case something goes wrong, e.g.
  //   packet was not complete because of link failure)
  // - all payload in UDP packet is forwarded to rx_dcfifo to be consumed by kernel 
  //   (qualified by mac_eth_valid as Ethernet MAC does not guarantee new valid data every clock cycle)
  //

  always_ff @(posedge eth_rx_axis.clk) begin
    if (~eth_rx_axis.rst_n) begin
      state                     <= STATE_IDLE;
      tok_udp_avst_ethclk.valid <= 1'b0;
      tok_udp_avst_ethclk.data  <= 'b0;
      arp_trigger               <= 1'b0;
    end else begin
      //default assignments for signals that are rarely asserted/cleared
      tok_udp_avst_ethclk.valid <= 1'b0;
      tok_udp_avst_ethclk.data  <= 'b0;
      arp_trigger               <= 1'b0;
      case (state) 
        STATE_IDLE: begin
          if (mac_eth_valid_sop) begin
            if (mac_eth_data_arp) begin
              // broadcast ARP packet or ARP request to FPGA
              state <= STATE_ARP_REQUEST0;
            end else if (mac_eth_data_hostmacadr47_32) begin
              // addressed packet to this FPGA
              state <= STATE_MAC0;
            end else begin
              state <= STATE_IDLE;
            end
          end else begin
            state <= STATE_IDLE;
          end
        end

        STATE_MAC0: begin
          //if valid+SOP
          if (mac_eth_valid_sop) begin
            // check for ARP request
            if (mac_eth_data_arp) begin
              // broadcast ARP packet or ARP request to FPGA
              state <= STATE_ARP_REQUEST0;
            // check for source (host) address matching register
            end else if (mac_eth_data_hostmacadr47_32) begin
              state <= STATE_MAC0;
            // invalid data, return to IDLE
            end else begin
              state <= STATE_IDLE;
            end
          //not SOP, check for the rest of the source (host) MAC address and IP header information
          //SA[31:0], EtherType[15:0], IPv4 version [3:0], IHL [3:0], DSCP[5:0], ECN [1:0]
          end else if (mac_eth_data[63:32] == udp_oe_ctrl.host_mac_adr[31:0]) begin //SA [31:0]
            //if IPv4 EtherType
            if (mac_eth_data[31:0] == { ETHERTYPE_IPv4,  //Type [15:0]
                                        IPv4_VERSION,    //Version [3:0]
                                        IPv4_IHL,        //IP Header length
                                        IPv4_DSCIP,      //IP DSCIP [5:0]
                                        IPv4_ECN         //IP ECN [1:0]
                                      }) begin
              state <= STATE_IP0;
            //if ARP EtherType
            end else if (mac_eth_data[31:16] == ETHERTYPE_ARP) begin
              state <= STATE_ARP_REQUEST1;
            //invalid EtherType type. return to IDLE
            end else begin
              state <= STATE_IDLE;
            end
          // invalid data, return to IDLE
          end else begin
            state <= STATE_IDLE;
          end
        end
        
        //ignore some of the IP header data: IP pkt length, IP hdr stuff
        STATE_IP0: begin
          if (mac_eth_valid) begin
            state            <= mac_eth_startofpacket ? STATE_MAC0 : STATE_IP1;
          end
        end

        STATE_IP1: begin
          //if valid+SOP
          if (mac_eth_valid_sop) begin
            // check for ARP request
            if (mac_eth_data_arp) begin
              // broadcast ARP packet or ARP request to FPGA
              state <= STATE_ARP_REQUEST0;
            // check for source (host) address matching register
            end else if (mac_eth_data_hostmacadr47_32) begin
              state <= STATE_MAC0;
            // invalid data, return to IDLE
            end else begin
              state <= STATE_IDLE;
            end
          //not SOP, check for the rest of the source (host) IP address and IP header information
          end else if (mac_eth_data[47:0] == {udp_oe_ctrl.host_ip_adr[31:0], udp_oe_ctrl.fpga_ip_adr[31:16]}) begin
            state <= STATE_UDP0;
          //invalid data, return to IDLE
          end else begin
            state <= STATE_IDLE;
          end
        end

        STATE_UDP0: begin
          //if valid+SOP
          if (mac_eth_valid_sop) begin
            // check for ARP request
            if (mac_eth_data_arp) begin
              // broadcast ARP packet or ARP request to FPGA
              state <= STATE_ARP_REQUEST0;
            // check for source (host) address matching register
            end else if (mac_eth_data_hostmacadr47_32) begin
              state <= STATE_MAC0;
            // invalid data, return to IDLE
            end else begin
              state <= STATE_IDLE;
            end
          //not SOP, check for the rest of the source (host) IP address and IP header information
          end else if (mac_eth_data[63:48] == udp_oe_ctrl.fpga_ip_adr[15:0]) begin
            state <= STATE_UDP1;
          //invalid data, return to IDLE
          end else begin
            state <= STATE_IDLE;
          end
        end

        STATE_UDP1: begin
          //if valid+SOP
          if (mac_eth_valid_sop) begin
            // check for ARP request
            if (mac_eth_data_arp) begin
              // broadcast ARP packet or ARP request to FPGA
              state <= STATE_ARP_REQUEST0;
            // check for source (host) address matching register
            end else if (mac_eth_data_hostmacadr47_32) begin
              state <= STATE_MAC0;
            // invalid data, return to IDLE
            end else begin
              state <= STATE_IDLE;
            end
          //not SOP, ignore checksum, packet counter, and dummy data; just go to payload state next
          end else begin
            state <= STATE_PAYLOAD;
          end
        end

        STATE_PAYLOAD: begin
          //if valid + EOP go to IDLE next
          if (mac_eth_valid_eop) begin
            state <= STATE_IDLE;
          //if valid+SOP
          end else if (mac_eth_valid_sop) begin
            // check for ARP request
            if (mac_eth_data_arp) begin
              // broadcast ARP packet or ARP request to FPGA
              state <= STATE_ARP_REQUEST0;
            // check for source (host) address matching register
            end else if (mac_eth_data_hostmacadr47_32) begin
              state <= STATE_MAC0;
            // invalid data, return to IDLE
            end else begin
              state <= STATE_IDLE;
            end
          //not SOP, this is payload
          end else begin
            state <= STATE_PAYLOAD;
          end
        
          tok_udp_avst_ethclk.valid <= mac_eth_valid;
          tok_udp_avst_ethclk.data  <= mac_eth_data;
          //tok_udp_avst_ethclk.data  <= ofs_fim_eth_avst_if_pkg::eth_axi_to_avst_data(mac_eth_data);
        end

        // ARP request and response
        STATE_ARP_REQUEST0: begin
          state <= mac_eth_valid ? STATE_ARP_REQUEST1 : STATE_ARP_REQUEST0;
        end
        STATE_ARP_REQUEST1: begin
          state <= mac_eth_valid ? STATE_ARP_REQUEST2 : STATE_ARP_REQUEST1;
        end
        STATE_ARP_REQUEST2: begin
          state <= mac_eth_valid ? STATE_ARP_REQUEST3 : STATE_ARP_REQUEST2;
        end
        STATE_ARP_REQUEST3: begin
          state <= mac_eth_valid ? STATE_ARP_REQUEST4 : STATE_ARP_REQUEST3;
        end
        STATE_ARP_REQUEST4: begin
          state <= mac_eth_valid ? STATE_ARP_RESPONSE : STATE_ARP_REQUEST4;
        end
        STATE_ARP_RESPONSE: begin
          arp_trigger <= 1'b1;
          state <= STATE_IDLE;
        end

      endcase // case (state)
    end // else: !if(~eth_rx_axis.rst_n)
  end // always_ff @ (posedge eth_rx_axis.clk)

  always_comb begin
    mac_eth_valid_sop = mac_eth_valid & mac_eth_startofpacket;
    mac_eth_valid_eop = mac_eth_valid & mac_eth_endofpacket;
    mac_eth_data_arp  = &(mac_eth_data[63:16]);
    mac_eth_data_hostmacadr47_32  = mac_eth_data[15:0] == udp_oe_ctrl.host_mac_adr[47:32];
  end

  always_ff @(posedge kernel_clk, negedge kernel_resetn)
    if (!kernel_resetn)
        rx_word_counter <= 'b0;
    else
        rx_word_counter <= rx_word_counter + udp_avst_to_kernel.valid;
  
  always_comb begin
    udp_oe_ctrl.rx_status.pkt_count = rx_word_counter;
    udp_oe_ctrl.rx_status.sm_state  = state;
  end
  
endmodule : simple_rx
