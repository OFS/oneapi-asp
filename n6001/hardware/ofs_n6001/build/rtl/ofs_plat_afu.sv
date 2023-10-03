// Copyright 2022 Intel Corporation
// SPDX-License-Identifier: MIT
//

`include "ofs_plat_if.vh"
`include "ofs_asp.vh"

module ofs_plat_afu
   (
    // All platform wires, wrapped in one interface.
    ofs_plat_if plat_ifc
    );
    
    import cci_mpf_shim_pkg::t_cci_mpf_shim_mdata_value;
    import ofs_asp_pkg::*;
    
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
        .ADD_CLOCK_CROSSING(USE_PIM_CDC_HOSTCHAN),
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
                .ADD_CLOCK_CROSSING(USE_PIM_CDC_LOCALMEM),
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
        .LOCAL_MEM_IN_USE_MASK(-1)
        `ifdef INCLUDE_IO_PIPES
            // The argument to each parameter is a bit mask of channels used.
            // Passing "-1" indicates all available channels are in use.
            ,.HSSI_IN_USE_MASK({IO_PIPES_NUM_CHAN{1'b1}})
        `endif //INCLUDE_IO_PIPES
        )
        tie_off(plat_ifc);

    
    `ifdef INCLUDE_IO_PIPES
        //ensure the ASP supports/expects no more IO Pipes than the FIM provides; fatal at compile-time
        generate
            if (IO_PIPES_NUM_CHAN > plat_ifc.hssi.NUM_CHANNELS) begin : Illegal_IO_Pipes_Num_Chan
                $fatal("Error: The IO_PIPES_NUM_CHAN parameter defined in the ASP, %d, is larger than NUM_CHANNELS supported by the FIM, %d.",IO_PIPES_NUM_CHAN, plat_ifc.hssi.NUM_CHANNELS);
            end
        endgenerate
    `endif //INCLUDE_IO_PIPES

    // ====================================================================
    //
    //  Pass the constructed interfaces to the AFU.
    //
    // ====================================================================

    //set pClk depending on if we are using PIM for PCIe/host-channel CDC
    logic pclk_bsp,pclk_bsp_reset;
    assign pclk_bsp = USE_PIM_CDC_HOSTCHAN ? plat_ifc.clocks.uClk_usrDiv2.clk :
                                                         plat_ifc.clocks.pClk.clk;
    assign pclk_bsp_reset = USE_PIM_CDC_HOSTCHAN ? ~plat_ifc.clocks.uClk_usrDiv2.reset_n :
                                                               ~plat_ifc.clocks.pClk.reset_n;

    afu afu_inst
      (
        .host_mem_if(host_mem_to_afu),
        .mmio64_if(mmio64_to_afu),
        .local_mem(local_mem_to_afu),
        `ifdef INCLUDE_IO_PIPES
            .hssi_pipes(plat_ifc.hssi.channels[0:IO_PIPES_NUM_CHAN-1]),
        `endif
       
        .pClk(pclk_bsp),
        .pClk_reset(pclk_bsp_reset),

        .uClk_usr(plat_ifc.clocks.uClk_usr.clk),
        .uClk_usr_reset(~plat_ifc.clocks.uClk_usr.reset_n),
        .uClk_usrDiv2(plat_ifc.clocks.uClk_usrDiv2.clk),
        .uClk_usrDiv2_reset(~plat_ifc.clocks.uClk_usrDiv2.reset_n)
       );

endmodule // afu_top_ofs_plat

