// Copyright 2020 Intel Corporation.
//
// THIS SOFTWARE MAY CONTAIN PREPRODUCTION CODE AND IS PROVIDED BY THE
// COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED
// WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
// MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
// DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR
// BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
// WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
// OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
// EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//

package udp_oe_pkg;

    //Static register values for the UDP OE DFH Information
    parameter DFH_HDR_FTYPE             = 4'h2;
    parameter DFH_HDR_RSVD0             = 8'h00;
    parameter DFH_HDR_VERSION_MINOR     = 4'h0;
    parameter DFH_HDR_RSVD1             = 7'h00;
    parameter DFH_HDR_END_OF_LIST       = 1'b0;
    parameter DFH_HDR_NEXT_DFH_OFFSET   = 24'h3800;
    parameter DFH_HDR_VERSION_MAJOR     = 4'h0;
    parameter DFH_HDR_FEATURE_ID        = 12'h000;
    parameter DFH_ID_LO = 64'h966d_1f07_871d_4396;
    parameter DFH_ID_HI = 64'h9c85_60c5_729f_f873;
    parameter DFH_NEXT_AFU_OFFSET = 24'h01_0000;

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

    //
    // Dispatcher register addresses
    //misc/DFH regs
    parameter REG_BSP_GEN_BASE_ADDR         = 'h00;
    parameter DFH_HEADER_ADDR               = REG_BSP_GEN_BASE_ADDR + 'h00;
    parameter ID_LO_ADDR                    = REG_BSP_GEN_BASE_ADDR + 'h01;
    parameter ID_HI_ADDR                    = REG_BSP_GEN_BASE_ADDR + 'h02;
    parameter DFH_NEXT_AFU_OFFSET_ADDR      = REG_BSP_GEN_BASE_ADDR + 'h03;
    parameter SCRATCHPAD_ADDR               = REG_BSP_GEN_BASE_ADDR + 'h05;
    
    //UDP Offload Engine registers
    parameter REG_UDPOE_BASE_ADDR          = 'h10;

    parameter CSR_FPGA_MAC_ADR_ADDR         = REG_UDPOE_BASE_ADDR + 'h00;
    parameter CSR_FPGA_IP_ADR_ADDR          = REG_UDPOE_BASE_ADDR + 'h01;
    parameter CSR_FPGA_UDP_PORT_ADDR        = REG_UDPOE_BASE_ADDR + 'h02;
    parameter CSR_FPGA_NETMASK_ADDR         = REG_UDPOE_BASE_ADDR + 'h03;
    parameter CSR_HOST_MAC_ADR_ADDR         = REG_UDPOE_BASE_ADDR + 'h04;
    parameter CSR_HOST_IP_ADR_ADDR          = REG_UDPOE_BASE_ADDR + 'h05;
    parameter CSR_HOST_UDP_PORT_ADDR        = REG_UDPOE_BASE_ADDR + 'h06;
    parameter CSR_PAYLOAD_PER_PACKET_ADDR   = REG_UDPOE_BASE_ADDR + 'h07;
    parameter CSR_CHECKSUM_IP_ADDR          = REG_UDPOE_BASE_ADDR + 'h08;
    parameter CSR_RESET_REG_ADDR            = REG_UDPOE_BASE_ADDR + 'h09;
    parameter CSR_STATUS_REG_ADDR           = REG_UDPOE_BASE_ADDR + 'h0A;
    parameter CSR_MISC_CTRL_REG_ADDR        = REG_UDPOE_BASE_ADDR + 'h0B;

    //data to return on a read that ends up in the default case
    parameter REG_RD_BADADDR_DATA = 64'h0BAD_0ADD_0BAD_0ADD;
    
    // TX DCFIFO parameters
    parameter TX_DCFIFO_DEPTH = 2048;
    parameter TX_DCFIFO_ALMOST_EMPTY_CUTOFF = 2;//orig = 511 ToDo: raise this back to a higher number
    
    //allow intra-BSP loopback?
    parameter ENABLE_INTRABSP_HSSI_TXRX_LOOPBACK = 1;
    
endpackage : udp_oe_pkg
