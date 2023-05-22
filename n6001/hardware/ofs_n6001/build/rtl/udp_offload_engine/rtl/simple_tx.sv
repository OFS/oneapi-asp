module simple_tx
(
  input logic         kernel_clk,
  input logic         kernel_resetn,
  
  udp_oe_ctrl_if.tx   udp_oe_ctrl,

  // to Ethernet MAC
  ofs_fim_hssi_ss_tx_axis_if.client   eth_tx_axis,

  // from kernel
  shim_avst_if.sink   udp_avst_from_kernel,

  // from RX of UDP offload engine for ARP response
  input logic         arp_trigger
);

  import dc_bsp_pkg::*;
  import udp_oe_pkg::*;
  
  // The packets should be as follows:
  //DA[47:0], SA[47:32]
  //SA[31:0], EtherType[15:0], IPv4 version [3:0], IHL [3:0], DSCP[5:0], ECN [1:0]
  //IP-length[15:0], IP packet ID[15:0], IP header flags (DF) [2:0], Fragment Offset [12:0], Time to Live [7:0], Protocol [7:0]
  //Checksum-IP[15:0], IP SA[31:0], IP DA[31:16]
  //IP DA[15:0], UDP SA[15:0], UDP DA[15:0], UDP length[15:0]
  //UDP checksum[15:0], extra/padding header data [47:0]
  //UDP payload
  
  //Parameter values:
  // Ethernet packet:
  //    EtherType: 
  //        IPv4 = 0x0800
  //        ARP  = 0x0806
  // IP header:
  //    IPv4 version = 0x4
  //    IHL  (IP Header length) = 0x5
  //    DSCIP  = 0x0
  //    ECN    = 0x0
  //    Flags  = 0x2 (set bit 1: Don't Fragment)
  //    Time to Live = 0x40 (from original code)
  //    IP Protocol Number = 0x11 (UDP)
  
  //UDP header size = 0xA bytes
  localparam UDP_HEADER_SIZE_IN_BYTES = 16'h000A;
  //IP header size = 0x1E bytes
  localparam IP_HEADER_SIZE_IN_BYTES = 16'h001E;

  logic [15:0] length_ip;
  logic [15:0] length_udp;
  logic [15:0] checksum_udp;
  logic [15:0] packet_id;

  assign length_ip = IP_HEADER_SIZE_IN_BYTES + udp_oe_ctrl.payload_per_packet;
  assign length_udp = UDP_HEADER_SIZE_IN_BYTES + udp_oe_ctrl.payload_per_packet;
  assign checksum_udp = 16'h0000;
  
  localparam HEADER_PADDING_DATA = 48'h0123_4567_89AB;
  
  localparam BYTES_PER_WORD = 16'h0008;
  
  logic [15:0] payload_counter;
  
  // clock crosser for kernel IO pipe signals (from kernel clock to Ethernet MAC TX clock)
  shim_avst_if dcff_avst_ethclk();

  logic        wr_full;
  logic        rd_empty;  
  logic        rd_almost_empty;
  
  logic [15:0] tx_word_counter;

  assign udp_avst_from_kernel.ready = ~wr_full;
  assign dcff_avst_ethclk.valid = ~rd_empty;
  
  //convert between AXIS and AVST
  logic        eth_mac_endofpacket;
  logic        eth_mac_valid;
  logic [63:0] eth_mac_data;
  logic [1:0]  eth_mac_empty;
  logic        eth_mac_error;
  logic        mac_eth_ready;
  
  //stats registers
  logic [11:0] tx_word_counter;
  
  // FSM states
  enum {
    STATE_IDLE,
    STATE_MAC_IP0,
    STATE_IP1,
    STATE_IP2,
    STATE_IP3_UDP0,
    STATE_UDP1,
    STATE_PAYLOAD,
    STATE_ARP_RESPONSE0,
    STATE_ARP_RESPONSE1,
    STATE_ARP_RESPONSE2,
    STATE_ARP_RESPONSE3,
    STATE_ARP_RESPONSE4,
    STATE_ARP_RESPONSE5,
    STATE_ARP_RESPONSE6,
    STATE_ARP_RESPONSE7
  } state;
  
  // hardcode error and empty signals 
  assign eth_mac_error = 1'b0;
  assign eth_mac_empty = 2'b0;
  
  always_comb begin
      eth_tx_axis.tx.tvalid   = eth_mac_valid;
      eth_tx_axis.tx.tlast    = eth_mac_valid & eth_mac_endofpacket;
      eth_tx_axis.tx.tdata    = eth_mac_data;
      eth_tx_axis.tx.tkeep    = ofs_fim_eth_avst_if_pkg::eth_empty_to_tkeep(eth_mac_empty);
      eth_tx_axis.tx.tuser    = 'b0;
      mac_eth_ready           = eth_tx_axis.tready;
  end

  acl_dcfifo #(
    .WIDTH         (SHIM_AVST_DATA_WIDTH),
    .DEPTH         (TX_DCFIFO_DEPTH),
    .RAM_BLOCK_TYPE("M20K"),
    .ALMOST_EMPTY_CUTOFF(TX_DCFIFO_ALMOST_EMPTY_CUTOFF)
  )
  tx_dcfifo
  (
    .async_resetn           (eth_tx_axis.rst_n),

    .wr_clock               (kernel_clk),
    .wr_req                 (udp_avst_from_kernel.valid),
    .wr_data                (udp_avst_from_kernel.data),
    .wr_full                (wr_full),

    .rd_clock               (eth_tx_axis.clk),
    .rd_ack                 (dcff_avst_ethclk.ready),
    .rd_empty               (rd_empty),
    .rd_almost_empty        (rd_almost_empty),
    .rd_data                (dcff_avst_ethclk.data)
  );

  assign dcff_avst_ethclk.ready = (state == STATE_PAYLOAD) & mac_eth_ready;

  always_ff @(posedge eth_tx_axis.clk) begin
    if (~eth_tx_axis.rst_n) begin
      state                 <= STATE_IDLE;
      payload_counter       <= 'b0;
      packet_id             <= 'b0;
      eth_mac_endofpacket   <= 1'b0;
      eth_mac_valid         <= 1'b0;
      eth_mac_data          <= 'b0;
    end else begin
      //default assignments for signals that are rarely asserted/cleared (eg eop, sop)
      eth_mac_endofpacket   <= 1'b0;
      eth_mac_valid         <= 1'b1;
      case (state) 
        STATE_IDLE: begin
          // new kernel data to be transmitted is available in FIFO
          if (~rd_almost_empty) begin
            // proceed to UDP packet transmission when Ethernet MAC is ready
            if (mac_eth_ready) begin
              state                 <= STATE_MAC_IP0;
              // Header word 1
              //DA[47:0], SA[47:32]
              eth_mac_data          <= {udp_oe_ctrl.host_mac_adr[47:0],udp_oe_ctrl.fpga_mac_adr[47:32]};
            end
          end else begin
            state                 <= STATE_IDLE;
            eth_mac_valid         <= 1'b0;
            // Data
            eth_mac_data          <= 'b0;
          end
          // ARP requested, need to respond
          if (arp_trigger) begin
            state <= STATE_ARP_RESPONSE0;
          end
        end

        STATE_MAC_IP0: begin
          if (mac_eth_ready) begin
            state                 <= STATE_IP1;
            // Header word 2
            //SA[31:0], EtherType[15:0], IPv4 version [3:0], IHL [3:0], DSCP[5:0], ECN [1:0]
            eth_mac_data          <= {udp_oe_ctrl.fpga_mac_adr[31:0],   //SA [31:0] 32'h08004500
                                      ETHERTYPE_IPv4,                   //Type [15:0]
                                      IPv4_VERSION,                     //Version [3:0]
                                      IPv4_IHL,                         //IP Header length
                                      IPv4_DSCIP,                       //IP DSCIP [5:0]
                                      IPv4_ECN                          //IP ECN [1:0]
                                      };
            packet_id             <= packet_id + 'b1;
          end
        end

        STATE_IP1: begin
          if (mac_eth_ready) begin
            state                 <= STATE_IP2;
            // Header word 3
            //IP-length[15:0], IP packet ID[15:0], IP header flags (DF) [2:0], Fragment Offset [12:0], Time to Live [7:0], Protocol [7:0]
            eth_mac_data          <= {length_ip[15:0],//[15:0]
                                      packet_id[15:0],//[15:0]
                                      IPv4_FLAGS,//[2:0]
                                      IPv4_FOFFSET,//[12:0]
                                      IPv4_TTL,//[7:0]
                                      IP_PROTOCOL_NUMBER_UDP//[7:0]
                                     };
          end
        end

        STATE_IP2: begin
          if (mac_eth_ready) begin
            state                 <= STATE_IP3_UDP0;
            // Header word 7 - Checksum of IP packet, Source IP address
            eth_mac_data          <= {udp_oe_ctrl.checksum_ip[15:0], 
                                      udp_oe_ctrl.fpga_ip_adr[31:0],
                                      udp_oe_ctrl.host_ip_adr[31:16]
                                     };
          end
        end

        STATE_IP3_UDP0: begin
          if (mac_eth_ready) begin
            state                 <= STATE_UDP1;
            // Header word 9 - Destination IP address, Source UDP port
            eth_mac_data          <= {udp_oe_ctrl.host_ip_adr[15:0], 
                                      udp_oe_ctrl.fpga_udp_port[15:0],
                                      udp_oe_ctrl.host_udp_port[15:0], 
                                      length_udp[15:0]
                                     };
          end
        end

        STATE_UDP1: begin
          if (mac_eth_ready) begin
            state                 <= STATE_PAYLOAD;
            payload_counter       <= udp_oe_ctrl.payload_per_packet;
            // Header word 11 - Checksum of UDP packet, Data
            eth_mac_data          <= {checksum_udp[15:0], 
                                      HEADER_PADDING_DATA};
          end
        end

        STATE_PAYLOAD: begin
          if (mac_eth_ready) begin
            // last word to be added
            if (payload_counter <= BYTES_PER_WORD) begin
              state                 <= dcff_avst_ethclk.valid ? STATE_IDLE : STATE_PAYLOAD;
              eth_mac_endofpacket   <= dcff_avst_ethclk.valid;
            end
            else begin
              state                 <= STATE_PAYLOAD;
            end
            
            payload_counter       <= dcff_avst_ethclk.valid ? (payload_counter - BYTES_PER_WORD) : payload_counter;
            eth_mac_valid         <= dcff_avst_ethclk.valid;
            // Data
            eth_mac_data          <= dcff_avst_ethclk.data;
            //eth_mac_data          <= ofs_fim_eth_avst_if_pkg::eth_avst_to_axi_data(dcff_avst_ethclk.data);
          end
        end

        // generate ARP response
        STATE_ARP_RESPONSE0: begin
          state                 <= STATE_ARP_RESPONSE1;
          eth_mac_data          <= {udp_oe_ctrl.host_mac_adr[47:0],udp_oe_ctrl.fpga_mac_adr[47:32]};
        end
        STATE_ARP_RESPONSE1: begin
          state                 <= STATE_ARP_RESPONSE2;
          eth_mac_data          <= {udp_oe_ctrl.fpga_mac_adr[31:0],
                                    ETHERTYPE_ARP,
                                    ARP_HTYPE
                                   };
        end
        STATE_ARP_RESPONSE2: begin
          state                 <= STATE_ARP_RESPONSE3;
          eth_mac_data          <= {ARP_FTYPE,
                                    ARP_HLEN,
                                    ARP_PLEN,
                                    ARP_OPER,
                                    udp_oe_ctrl.fpga_mac_adr[47:32]
                                   };
        end
        STATE_ARP_RESPONSE3: begin
          state                 <= STATE_ARP_RESPONSE4;
          eth_mac_data          <= {udp_oe_ctrl.fpga_mac_adr[31:0], udp_oe_ctrl.fpga_ip_adr[31:0]};
        end
        STATE_ARP_RESPONSE4: begin
          state                 <= STATE_ARP_RESPONSE5;
          eth_mac_data          <= {udp_oe_ctrl.host_mac_adr[47:0],
                                    udp_oe_ctrl.host_ip_adr[31:16]
                                   };
        end
        STATE_ARP_RESPONSE5: begin
          state                 <= STATE_ARP_RESPONSE6;
          eth_mac_data          <= {udp_oe_ctrl.host_ip_adr[15:0],48'h0};
        end
        STATE_ARP_RESPONSE6: begin
          state                 <= STATE_ARP_RESPONSE7;
          eth_mac_data          <= 'b0;
        end
        STATE_ARP_RESPONSE7: begin
          state                 <= STATE_IDLE;
          eth_mac_endofpacket   <= 1'b1;
          eth_mac_data          <= 'b0;
        end
      endcase // case (state)
    end // else: !if(~eth_tx_axis.rst_n)
  end // always_ff @ (posedge eth_tx_axis.clk)

  //tracking counters
  always_ff @(posedge eth_tx_axis.clk, negedge eth_tx_axis.rst_n)
    if (!eth_tx_axis.rst_n)
        tx_word_counter <= 'b0;
    else
        tx_word_counter <= tx_word_counter + eth_mac_valid;
  
  always_comb begin
    udp_oe_ctrl.tx_status.pkt_count = tx_word_counter;
    udp_oe_ctrl.tx_status.sm_state  = state;
  end
  
endmodule // simple_tx
