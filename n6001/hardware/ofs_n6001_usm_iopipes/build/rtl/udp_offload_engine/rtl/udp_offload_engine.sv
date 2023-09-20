// Copyright 2022 Intel Corporation
// SPDX-License-Identifier: MIT
//

module udp_offload_engine
import dc_bsp_pkg::*;
(
    ofs_plat_hssi_channel_if hssi_pipes[IO_PIPES_NUM_CHAN],
    
    // kernel clock and reset 
    input logic         kernel_clk,
    input logic         kernel_resetn,
    
    // Avalon-ST interface from kernel
    shim_avst_if.sink   udp_avst_from_kernel[IO_PIPES_NUM_CHAN-1:0],
    
    // Avalon-ST interface to kernel
    shim_avst_if.source udp_avst_to_kernel[IO_PIPES_NUM_CHAN-1:0],
    
    // UDP offload engine CSR
    ofs_plat_avalon_mem_if.to_source uoe_csr_avmm
);

import udp_oe_pkg::*;

// MAC/IP/UDP parameters set by host through CSR
udp_oe_ctrl_if udp_oe_ctrl();
udp_oe_channel_if udp_oe_pipe_ctrl_sts[IO_PIPES_NUM_CHAN-1:0]();

logic [IO_PIPES_NUM_CHAN-1:0] arp_trigger;

ofs_fim_hssi_ss_tx_axis_if eth_tx_axis_int[IO_PIPES_NUM_CHAN-1:0]();
ofs_fim_hssi_ss_rx_axis_if eth_rx_axis_int[IO_PIPES_NUM_CHAN-1:0]();

genvar ch;
generate 
    for (ch = 0; ch < IO_PIPES_NUM_CHAN; ch++) begin : tx_rx_inst
        // FPGA TX path (kernel udp_out hostpipe through UDP offload engine to Ethernet MAC TX)
        simple_tx simple_tx
        (
            .kernel_clk,
            .kernel_resetn,
            .udp_oe_ctrl,
            .udp_oe_pipe_ctrl_sts(udp_oe_pipe_ctrl_sts[ch]),
            .eth_tx_axis(eth_tx_axis_int[ch]),
            .udp_avst_from_kernel(udp_avst_from_kernel[ch]),
            .arp_trigger(arp_trigger[ch])
        );
        
        // FPGA RX path (Ethernet MAC RX through UDP offload engine to kernel udp_in hostpipe)
        simple_rx simple_rx
        (
            .kernel_clk,
            .kernel_resetn,
            .udp_oe_ctrl,
            .udp_oe_pipe_ctrl_sts(udp_oe_pipe_ctrl_sts[ch]),
            .eth_rx_axis(eth_rx_axis_int[ch]),
            .udp_avst_to_kernel(udp_avst_to_kernel[ch]),
            .arp_trigger(arp_trigger[ch])
        );
        
        //bring-up / debugging : intra-ASP loopback of data generated by kernel-system
        //do tx-rx loopback or pass-through to hssi-ss
        
        //toggle the tx-tready signal to mimic the real HSSI-SS
        //kills throughput, but this is only used with the BSP-loopback logic (below),
        //so it isn't actually doing anything real, anyhow. This helps stress the 
        //simple_rx/tx modules and their state machines. It is optimized away when we
        //don't use intra-bsp-loopback.
        logic [1:0] freeze_cntr;
        always_ff @(posedge kernel_clk) begin
            if (!kernel_resetn) begin
                freeze_cntr <= 'b0;
            end else begin
                freeze_cntr <= freeze_cntr + 1'b1;
            end
        end

        always_comb begin 
            //if connecting the kernel's tx-to-rx (loopback)
            if (ENABLE_INTRABSP_HSSI_TXRX_LOOPBACK) begin
                eth_tx_axis_int[ch].tready = freeze_cntr == 'h0 ? 'b0 : 'b1;
                eth_tx_axis_int[ch].clk    = kernel_clk;
                eth_tx_axis_int[ch].rst_n  = kernel_resetn;
                
                eth_rx_axis_int[ch].clk    = kernel_clk;
                eth_rx_axis_int[ch].rst_n  = kernel_resetn;
                eth_rx_axis_int[ch].rx.tvalid = eth_tx_axis_int[ch].tx.tvalid & eth_tx_axis_int[ch].tready;
                eth_rx_axis_int[ch].rx.tlast  = eth_tx_axis_int[ch].tx.tlast;
                eth_rx_axis_int[ch].rx.tdata  = eth_tx_axis_int[ch].tx.tdata;
                eth_rx_axis_int[ch].rx.tkeep  = (freeze_cntr == 3) ? '1 : '0;
                eth_rx_axis_int[ch].rx.tuser  = eth_tx_axis_int[ch].tx.tuser;
                
                //tie off signals to hssi-ss
                hssi_pipes[ch].data_tx.tx.tvalid     = 'b0;
            //else connecting kernel to hssi-ss
            end else begin
                eth_tx_axis_int[ch].tready = hssi_pipes[ch].data_tx.tready;
                eth_tx_axis_int[ch].clk    = hssi_pipes[ch].data_tx.clk;
                eth_tx_axis_int[ch].rst_n  = hssi_pipes[ch].data_tx.rst_n;
                hssi_pipes[ch].data_tx.tx  = eth_tx_axis_int[ch].tx;
                
                eth_rx_axis_int[ch].clk    = hssi_pipes[ch].data_rx.clk;
                eth_rx_axis_int[ch].rst_n  = hssi_pipes[ch].data_rx.rst_n;
                eth_rx_axis_int[ch].rx     = hssi_pipes[ch].data_rx.rx;
            end
        end
    end //for
endgenerate

// UDP offload engine CSR
// host can set the following MAC/IP/UDP parameters:
udp_oe_csr udp_oe_csr
(
    .uoe_csr_avmm,
    .udp_oe_ctrl,
    .udp_oe_pipe_ctrl_sts
);

endmodule : udp_offload_engine
