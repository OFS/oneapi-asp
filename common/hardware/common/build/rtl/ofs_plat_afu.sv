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
        host_mem_to_afu [NUM_HOSTMEM_CHAN] ();

    // 64 bit read/write MMIO AFU sink
    ofs_plat_avalon_mem_if
      #(
        `HOST_CHAN_AVALON_MMIO_PARAMS(ASP_MMIO_DATA_WIDTH),
        .LOG_CLASS(ofs_plat_log_pkg::HOST_CHAN)
        )
        mmio64_to_afu ();

	//this is the default/primary hostmem interface - used for VTP_SVC + MMIO as well 
    //as basic host memory accesses.
    
    // Instantiate the parent feature at MMIO offset 0. The parent feature
    // contains a parameter that lists the children. OPAE will discover the
    // parameter and load children along with the parent.
    //
    // This module acts as a shim that implements only the one DFL entry.
    // Other traffic to/from the AFU flows on host_chan_with_dfh.
    ofs_plat_host_chan_as_avalon_mem_rdwr_with_mmio
      #(
        .ADD_CLOCK_CROSSING(USE_PIM_CDC_HOSTCHAN),
        .ADD_TIMING_REG_STAGES(1)
        )
      primary_avalon
       (
        .to_fiu(plat_ifc.host_chan.ports[0]),
        .host_mem_to_afu (host_mem_to_afu[HOSTMEM_CHAN_DEFAULT_WITH_MMIO]),
        .mmio_to_afu(mmio64_to_afu),

        //these are only used if ADD_CLOCK_CROSSING is non-zero; ignored otherwise.
        .afu_clk(plat_ifc.clocks.uClk_usrDiv2.clk),
        .afu_reset_n(plat_ifc.clocks.uClk_usrDiv2.reset_n)
        );
	
	//these are the child hostmem interface(s). They will not provide MMIO into afu.sv and will
	//not carry VTP-SVC traffic, only host memory accesses. They will, however, connect MMIO 
    //to a simple DFH CSR module so that any MMIO requests from the host will get a response.
	genvar h;
	generate for (h=1; h<NUM_HOSTMEM_CHAN; h=h+1) begin : child_hostmem_links
        //(From multi_link OFS example design)
        // New host channel wrappers -- the same interface as found in
        // plat_ifc.host_chan.ports. The PIM-provided wrapper around
        // the FIM's multi_link_afu_dfh module will connect the plat_ifc
        // ports to these new host_chan_with_dfh ports. All traffic other
        // than the MMIO associated with the AFU features will reach them.
        //We won't use this for the parent link (yet), only the children,
        //because of how the AFU_ID component is used/created in the ASP 
        //(within Platform Designer).
        ofs_plat_host_chan_axis_pcie_tlp_if child_host_chan_with_dfh[NUM_HOSTMEM_CHAN-1]();
        
        // Instantiate child features at MMIO offset 0 of the children.
        // The same module is used. When NUM_CHILDREN is not set (defaults
        // to 0), a child feature is constructed. Except for building
        // a different header, the behavior is similar to the parent.
        ofs_plat_host_chan_fim_multi_link_afu_dfh
        #(
            .GUID_H(64'b0),
            .GUID_L(64'b0)
        )
        child_link_dfh
        (
            //this should be some equation that takes 'h' into account. The 
            //number of interfaces equals the number of links times the number of
            //ports per link. Each link's ports are added in sequence to the full
            //array of interfaces. ex each link (L0 and L1) has 3 ports (P0, P1, P2). 
            //The total number of interfaces is 6 (0..5). We want to use P0 of each 
            //link. The array of interfaces will be [L0P0, L0P1, L0P2, L1P0,L1P1,L1P2].
            //.to_fiu(plat_ifc.host_chan.ports[h]),
            .to_fiu(plat_ifc.host_chan.ports[3]),
            .to_afu(child_host_chan_with_dfh[h-1])
        );
                
		ofs_plat_host_chan_as_avalon_mem_rdwr
		#(
			.ADD_CLOCK_CROSSING(USE_PIM_CDC_HOSTCHAN),
			.ADD_TIMING_REG_STAGES(1)
        )
		primary_avalon
		(
			.to_fiu(child_host_chan_with_dfh[h-1]),
			.host_mem_to_afu (host_mem_to_afu[h]),

			//these are only used if ADD_CLOCK_CROSSING is non-zero; ignored otherwise.
			.afu_clk(plat_ifc.clocks.uClk_usrDiv2.clk),
			.afu_reset_n(plat_ifc.clocks.uClk_usrDiv2.reset_n)
        );
        
	end : child_hostmem_links
	endgenerate

    // ====================================================================
    //
    //  Get local memory from the platform.
    //
    // ====================================================================

    ofs_plat_avalon_mem_if
      #(
        `LOCAL_MEM_AVALON_MEM_PARAMS_DEFAULT
        )
      local_mem_to_afu[ASP_LOCALMEM_NUM_CHANNELS]();

    // Map each bank individually
    genvar b;
    generate
        for (b = 0; b < ASP_LOCALMEM_NUM_CHANNELS; b = b + 1)
        begin : mb
            ofs_plat_local_mem_as_avalon_mem
              #(
                // EMIF closs crossings occur in the ASP Qsys-system
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
        .HOST_CHAN_IN_USE_MASK({NUM_HOSTMEM_CHAN{1'b1}}),
	    //.HOST_CHAN_IN_USE_MASK(6'b001001), //for 2xGen5x8 iseries-dk
        .LOCAL_MEM_IN_USE_MASK({ASP_LOCALMEM_NUM_CHANNELS{1'b1}})
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
    logic pclk_asp,pclk_asp_reset;
    assign pclk_asp = USE_PIM_CDC_HOSTCHAN ? plat_ifc.clocks.uClk_usrDiv2.clk :
                                                         plat_ifc.clocks.pClk.clk;
    assign pclk_asp_reset = USE_PIM_CDC_HOSTCHAN ? ~plat_ifc.clocks.uClk_usrDiv2.reset_n :
                                                               ~plat_ifc.clocks.pClk.reset_n;

    afu afu_inst
      (
        .host_mem_if(host_mem_to_afu),
        .mmio64_if(mmio64_to_afu),
        .local_mem(local_mem_to_afu),
        `ifdef INCLUDE_IO_PIPES
            .hssi_pipes(plat_ifc.hssi.channels[0:IO_PIPES_NUM_CHAN-1]),
        `endif
       
        .pClk(pclk_asp),
        .pClk_reset(pclk_asp_reset),

        .uClk_usr(plat_ifc.clocks.uClk_usr.clk),
        .uClk_usr_reset(~plat_ifc.clocks.uClk_usr.reset_n),
        .uClk_usrDiv2(plat_ifc.clocks.uClk_usrDiv2.clk),
        .uClk_usrDiv2_reset(~plat_ifc.clocks.uClk_usrDiv2.reset_n)
       );

endmodule // afu_top_ofs_plat

