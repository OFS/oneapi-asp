// Copyright 2022 Intel Corporation
// SPDX-License-Identifier: MIT
//

`define ENABLE_INTRABSP_HSSI_TXRX_LOOPBACK 1

module udp_offload_engine
import dc_bsp_pkg::*;
(
    ofs_fim_hssi_ss_tx_axis_if[IO_PIPES_NUM_CHAN-1:0].client   eth_tx_axis,
    ofs_fim_hssi_ss_rx_axis_if[IO_PIPES_NUM_CHAN-1:0].client   eth_rx_axis,
    ofs_fim_hssi_fc_if[IO_PIPES_NUM_CHAN-1:0].client           eth_fc,
    
    // kernel clock and reset 
    input logic         kernel_clk,
    input logic         kernel_resetn,
    
    // Avalon-ST interface from kernel
    shim_avst_if[IO_PIPES_NUM_CHAN-1:0].sink   udp_avst_from_kernel,
    
    // Avalon-ST interface to kernel
    shim_avst_if[IO_PIPES_NUM_CHAN-1:0].source udp_avst_to_kernel,
    
    // UDP offload engine CSR
    ofs_plat_avalon_mem_if.to_source uoe_csr_avmm
);

import udp_oe_pkg::*;

// MAC/IP/UDP parameters set by host through CSR
udp_oe_ctrl_if udp_oe_ctrl();

logic [IO_PIPES_NUM_CHAN-1:0] arp_trigger;

ofs_fim_hssi_ss_tx_axis_if [IO_PIPES_NUM_CHAN-1:0] eth_tx_axis_int();
ofs_fim_hssi_ss_rx_axis_if [IO_PIPES_NUM_CHAN-1:0] eth_rx_axis_int();

genvar ch;
generate 
    for (ch = 0; ch < IO_PIPES_NUM_CHAN; ch++) : begin : tx_rx_inst
        // FPGA TX path (kernel udp_out hostpipe through UDP offload engine to Ethernet MAC TX)
        simple_tx simple_tx
        (
            .kernel_clk,
            .kernel_resetn,
            .udp_oe_ctrl,
            .eth_tx_axis(eth_tx_axis_int[ch]),
            .udp_avst_from_kernel[ch],
            .arp_trigger[ch]
        );
        
        // FPGA RX path (Ethernet MAC RX through UDP offload engine to kernel udp_in hostpipe)
        simple_rx simple_rx
        (
            .kernel_clk,
            .kernel_resetn,
            .udp_oe_ctrl,
            .eth_rx_axis(eth_rx_axis_int[ch]),
            .udp_avst_to_kernel[ch],
            .arp_trigger[ch]
        );
        
        //bring-up / debugging : intra-ASP loopback of data generated by kernel-system
        //do tx-rx loopback or pass-through to hssi-ss
        always_comb begin 
            //if connecting the kernel's tx-to-rx (loopback)
            if (ENABLE_INTRABSP_HSSI_TXRX_LOOPBACK) begin
                eth_tx_axis_int[ch].tready = 'b1;
                eth_tx_axis_int[ch].clk    = kernel_clk;
                eth_tx_axis_int[ch].rst_n  = kernel_resetn;
                
                eth_rx_axis_int[ch].clk    = kernel_clk;
                eth_rx_axis_int[ch].rst_n  = kernel_resetn;
                eth_rx_axis_int[ch].rx.tvalid = eth_tx_axis_int[ch].tx.tvalid;
                eth_rx_axis_int[ch].rx.tlast  = eth_tx_axis_int[ch].tx.tlast;
                eth_rx_axis_int[ch].rx.tdata  = eth_tx_axis_int[ch].tx.tdata;
                eth_rx_axis_int[ch].rx.tkeep  = eth_tx_axis_int[ch].tx.tkeep;
                eth_rx_axis_int[ch].rx.tuser  = eth_tx_axis_int[ch].tx.tuser;
                
                //tie off signals to hssi-ss
                eth_tx_axis[ch].tx.tvalid     = 'b0;
            //else connecting kernel to hssi-ss
            end else begin
                eth_tx_axis_int[ch].tready = eth_tx_axis[ch].tready;
                eth_tx_axis_int[ch].clk    = eth_tx_axis[ch].clk;
                eth_tx_axis_int[ch].rst_n  = eth_tx_axis[ch].rst_n;
                eth_tx_axis[ch].tx         = eth_tx_axis_int[ch].tx;
                
                eth_rx_axis_int[ch].clk    = eth_rx_axis[ch].clk;
                eth_rx_axis_int[ch].rst_n  = eth_rx_axis[ch].rst_n;
                eth_rx_axis_int[ch].rx     = eth_rx_axis[ch].rx;
            end
        end
    end //for
endgenerate

// UDP offload engine CSR
// host can set the following MAC/IP/UDP parameters:
udp_oe_csr udp_oe_csr
(
    .uoe_csr_avmm,
    .udp_oe_ctrl
);

endmodule : udp_offload_engine
