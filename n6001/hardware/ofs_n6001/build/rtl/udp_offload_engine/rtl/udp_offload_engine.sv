`define ENABLE_INTRABSP_HSSI_TXRX_LOOPBACK 1

module udp_offload_engine
(
    ofs_fim_hssi_ss_tx_axis_if.client   eth_tx_axis,
    ofs_fim_hssi_ss_rx_axis_if.client   eth_rx_axis,
    ofs_fim_hssi_fc_if.client           eth_fc,
    
    // kernel clock and reset 
    input logic         kernel_clk,
    input logic         kernel_resetn,
    
    // Avalon-ST interface from kernel
    shim_avst_if.sink   udp_avst_from_kernel,
    
    // Avalon-ST interface to kernel
    shim_avst_if.source udp_avst_to_kernel,
    
    // UDP offload engine CSR
    ofs_plat_avalon_mem_if.to_source uoe_csr_avmm
);

import udp_oe_pkg::*;

// MAC/IP/UDP parameters set by host through CSR
udp_oe_ctrl_if udp_oe_ctrl();

logic arp_trigger;

ofs_fim_hssi_ss_tx_axis_if eth_tx_axis_int();
ofs_fim_hssi_ss_rx_axis_if eth_rx_axis_int();

// FPGA TX path (kernel udp_out hostpipe through UDP offload engine to Ethernet MAC TX)
simple_tx simple_tx
(
    .kernel_clk,
    .kernel_resetn,
    .udp_oe_ctrl,
    .eth_tx_axis(eth_tx_axis_int),
    .udp_avst_from_kernel,
    .arp_trigger
);

// FPGA RX path (Ethernet MAC RX through UDP offload engine to kernel udp_in hostpipe)
simple_rx simple_rx
(
    .kernel_clk,
    .kernel_resetn,
    .udp_oe_ctrl,
    .eth_rx_axis(eth_rx_axis_int),
    .udp_avst_to_kernel,
    .arp_trigger
);

// UDP offload engine CSR
// host can set the following MAC/IP/UDP parameters:
user_csr user_csr
(
    .uoe_csr_avmm,
    .udp_oe_ctrl
);

//do tx-rx loopback or pass-through to hssi-ss
always_comb begin 
    //if connecting the kernel's tx-to-rx (loopback)
    if (udp_oe_ctrl.misc_ctrl.intrabsp_txrx_loopback & ENABLE_INTRABSP_HSSI_TXRX_LOOPBACK) begin
        eth_tx_axis_int.tready = 'b1;
        eth_tx_axis_int.clk    = kernel_clk;
        eth_tx_axis_int.rst_n  = kernel_resetn;
        
        eth_rx_axis_int.clk    = kernel_clk;
        eth_rx_axis_int.rst_n  = kernel_resetn;
        eth_rx_axis_int.rx.tvalid = eth_tx_axis_int.tx.tvalid;
        eth_rx_axis_int.rx.tlast = eth_tx_axis_int.tx.tlast;
        eth_rx_axis_int.rx.tdata = eth_tx_axis_int.tx.tdata;
        eth_rx_axis_int.rx.tkeep = eth_tx_axis_int.tx.tkeep;
        eth_rx_axis_int.rx.tuser = eth_tx_axis_int.tx.tuser;
        
        //tie off signals to hssi-ss
        eth_tx_axis.tx.tvalid     = 'b0;
    //else connecting kernel to hssi-ss
    end else begin
        eth_tx_axis_int.tready = eth_tx_axis.tready;
        eth_tx_axis_int.clk    = eth_tx_axis.clk;
        eth_tx_axis_int.rst_n  = eth_tx_axis.rst_n;
        eth_tx_axis.tx         = eth_tx_axis_int.tx;
        
        eth_rx_axis_int.clk    = eth_rx_axis.clk;
        eth_rx_axis_int.rst_n  = eth_rx_axis.rst_n;
        eth_rx_axis_int.rx     = eth_rx_axis.rx;
    end
end

endmodule // udp_offload_engine
