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
