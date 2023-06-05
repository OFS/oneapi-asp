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

`include "ofs_plat_if.vh"
`include "opencl_bsp.vh"

module ofs_plat_afu
   (
    // All platform wires, wrapped in one interface.
    ofs_plat_if plat_ifc
    );
    
    import cci_mpf_shim_pkg::t_cci_mpf_shim_mdata_value;

    // ====================================================================
    //
    //  Get an Avalon host channel collection from the platform.
    //
    // ====================================================================

    // User bits in the Avalon interface are used to tag page table
    // traffic from VTP. Make sure there are enough user bits available.
    // They must start beyond the PIM's user flags (used for interrupts
    // and fences).
    localparam AV_USER_BIT_START_IDX = ofs_plat_host_chan_avalon_mem_pkg::HC_AVALON_UFLAG_MAX + 1;
    localparam AV_USER_WIDTH = AV_USER_BIT_START_IDX +
                               $bits(t_cci_mpf_shim_mdata_value) + // VTP tag
                               1;                                  // VTP traffic flag

    // Host memory AFU source
    ofs_plat_avalon_mem_rdwr_if
      #(
        `HOST_CHAN_AVALON_MEM_RDWR_PARAMS,
        // When using VTP, bursts can't cross physical page boundaries.
        // The PIM's ofs_plat_axi_mem_if_map_bursts() module is used to
        // split page-crossing bursts. It depends on the maximum burst
        // size being no larger than half a page.
        .BURST_CNT_WIDTH(6),
        .USER_WIDTH(AV_USER_WIDTH),
        .LOG_CLASS(ofs_plat_log_pkg::HOST_CHAN)
        )
        host_mem_to_afu();

    // 64 bit read/write MMIO AFU sink
    ofs_plat_avalon_mem_if
      #(
        `HOST_CHAN_AVALON_MMIO_PARAMS(64),
        .LOG_CLASS(ofs_plat_log_pkg::HOST_CHAN)
        )
        mmio64_to_afu();

    ofs_plat_host_chan_as_avalon_mem_rdwr_with_mmio
      #(
        .ADD_CLOCK_CROSSING(dc_bsp_pkg::USE_PIM_CDC_HOSTCHAN),
        .ADD_TIMING_REG_STAGES(1)
        )
      primary_avalon
       (
        .to_fiu(plat_ifc.host_chan.ports[0]),
        .host_mem_to_afu,
        .mmio_to_afu(mmio64_to_afu),

        //these are only used if ADD_CLOCK_CROSSING is non-zero; ignored otherwise.
        .afu_clk(plat_ifc.clocks.uClk_usrDiv2.clk),
        .afu_reset_n(plat_ifc.clocks.uClk_usrDiv2.reset_n)
        );

    // ====================================================================
    //
    //  Get local memory from the platform.
    //
    // ====================================================================

    ofs_plat_avalon_mem_if
      #(
        `LOCAL_MEM_AVALON_MEM_PARAMS_DEFAULT
        )
      local_mem_to_afu[local_mem_cfg_pkg::LOCAL_MEM_NUM_BANKS]();

    // Map each bank individually
    genvar b;
    generate
        for (b = 0; b < local_mem_cfg_pkg::LOCAL_MEM_NUM_BANKS; b = b + 1)
        begin : mb
            ofs_plat_local_mem_as_avalon_mem
              #(
                // EMIF closs crossings occur in the BSP Qsys-system
                .ADD_CLOCK_CROSSING(dc_bsp_pkg::USE_PIM_CDC_LOCALMEM),
                .ADD_TIMING_REG_STAGES(3)
                )
              shim
               (
                .to_fiu(plat_ifc.local_mem.banks[b]),
                .to_afu(local_mem_to_afu[b]),
                
                //these are only used if ADD_CLOCK_CROSSING is non-zero; ignored otherwise.
                .afu_clk(plat_ifc.clocks.uClk_usrDiv2.clk),
                .afu_reset_n(plat_ifc.clocks.uClk_usrDiv2.reset_n)
                );
        end
    endgenerate

   // ====================================================================
   //
   //  Map Ethernet channels to Avalon streams
   //
   // ====================================================================

   localparam NUM_ETH = plat_ifc.hssi.NUM_CHANNELS;

    //separate AXI-ST interfaces used between the AVST-AXIST bridge
    //  and PIM-mapper
    //ofs_fim_hssi_ss_rx_axis_if eth_rx_axis[NUM_ETH-1:0]();
    //ofs_fim_hssi_ss_tx_axis_if eth_tx_axis[NUM_ETH-1:0]();
    //ofs_fim_hssi_fc_if eth_fc[NUM_ETH-1:0]();
    
    //separate AVT-ST interfaces
   // Data streams
   //ofs_fim_eth_tx_avst_if eth_tx_st [NUM_ETH-1:0]();
   //ofs_fim_eth_rx_avst_if eth_rx_st [NUM_ETH-1:0]();
   // Sideband streams (control flow)
   //ofs_fim_eth_sideband_tx_avst_if eth_sb_tx [NUM_ETH-1:0]();
   //ofs_fim_eth_sideband_rx_avst_if eth_sb_rx [NUM_ETH-1:0]();

   // The PIM provides a mapping from the native stream encoding to
   // Avalon streams.
   //generate
   //   for (genvar c = 0; c < NUM_ETH; c = c + 1) begin : ec
   //         //ofs_plat_hssi_as_axi_st axist_inst
   //         //(
   //         //    .to_fiu(plat_ifc.hssi.channels[c]),
   //         //    .tx_st(eth_tx_axis[c]),
   //         //    .rx_st(eth_rx_axis[c]),
   //         //    .fc(eth_fc[c]),
   //         //    .afu_clk(),
   //         //    .afu_reset_n()
   //         //);
   //         //always_comb begin
   //             //eth_rx_axis[c] = plat_ifc.hssi.channels[c].data_rx;
   //             
   //             //eth_tx_axis[c].clk    = plat_ifc.hssi.channels[c].data_tx.clk;
   //             //eth_tx_axis[c].rst_n  = plat_ifc.hssi.channels[c].data_tx.rst_n;
   //             //eth_tx_axis[c].tready = plat_ifc.hssi.channels[c].data_tx.tready;
   //             //plat_ifc.hssi.channels[c].data_tx.tx = eth_tx_axis[c].tx;
   //         //end
   //   end
   //endgenerate

   
   
    // ====================================================================
    //
    //  Tie off unused ports.
    //
    // ====================================================================

    ofs_plat_if_tie_off_unused
      #(
        // Masks are bit masks, with bit 0 corresponding to port/bank zero.
        // Set a bit in the mask when a port is IN USE by the design.
        // This way, the AFU does not need to know about every available
        // device. By default, devices are tied off.
        .HOST_CHAN_IN_USE_MASK(1),
        // All banks are used
        .LOCAL_MEM_IN_USE_MASK(-1),
        // The argument to each parameter is a bit mask of channels used.
        // Passing "-1" indicates all available channels are in use.
        .HSSI_IN_USE_MASK(1)
        )
        tie_off(plat_ifc);


    // ====================================================================
    //
    //  Pass the constructed interfaces to the AFU.
    //
    // ====================================================================

    //set pClk depending on if we are using PIM for PCIe/host-channel CDC
    logic pclk_bsp,pclk_bsp_reset;
    assign pclk_bsp = dc_bsp_pkg::USE_PIM_CDC_HOSTCHAN ? plat_ifc.clocks.uClk_usrDiv2.clk :
                                                         plat_ifc.clocks.pClk.clk;
    assign pclk_bsp_reset = dc_bsp_pkg::USE_PIM_CDC_HOSTCHAN ? ~plat_ifc.clocks.uClk_usrDiv2.reset_n :
                                                               ~plat_ifc.clocks.pClk.reset_n;

    afu
     #(
        .NUM_LOCAL_MEM_BANKS(local_mem_cfg_pkg::LOCAL_MEM_NUM_BANKS),
        .NUM_ETH(NUM_ETH)
       )
     afu
      (
        .host_mem_if(host_mem_to_afu),
        .mmio64_if(mmio64_to_afu),
        .local_mem(local_mem_to_afu),

        .eth_tx_axis(plat_ifc.hssi.channels[0].data_tx),
        .eth_rx_axis(plat_ifc.hssi.channels[0].data_rx),
        .eth_fc(plat_ifc.hssi.channels[0].fc),
       
        .pClk(pclk_bsp),
        .pClk_reset(pclk_bsp_reset),

        .uClk_usr(plat_ifc.clocks.uClk_usr.clk),
        .uClk_usr_reset(~plat_ifc.clocks.uClk_usr.reset_n),
        .uClk_usrDiv2(plat_ifc.clocks.uClk_usrDiv2.clk),
        .uClk_usrDiv2_reset(~plat_ifc.clocks.uClk_usrDiv2.reset_n)
       );

endmodule // afu_top_ofs_plat

