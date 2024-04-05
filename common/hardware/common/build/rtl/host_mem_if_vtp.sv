// Copyright 2022 Intel Corporation
// SPDX-License-Identifier: MIT
//

`include "ofs_plat_if.vh"
`include "ofs_asp.vh"

module host_mem_if_vtp
import ofs_asp_pkg::*;
(
    // Host memory sink (Avalon rdwr) - host-facing
    ofs_plat_avalon_mem_rdwr_if.to_sink host_mem_if [NUM_HOSTMEM_CHAN],
    // Host memory sources (Avalon rdwr) - shim-facing
    `ifdef INCLUDE_ASP_DMA
        ofs_plat_avalon_mem_rdwr_if.to_source host_mem_va_if_dma [NUM_DMA_CHAN-1:0],
    `endif
    `ifdef INCLUDE_USM_SUPPORT
        ofs_plat_avalon_mem_rdwr_if.to_source host_mem_va_if_kernel [NUM_USM_CHAN-1:0],
    `endif

    // FPGA MMIO master (Avalon) - host-facing
    ofs_plat_avalon_mem_if.to_source mmio64_if,
    // FPGA MMIO master (Avalon) - shim-facing
    ofs_plat_avalon_mem_if.to_sink mmio64_if_shim
);

// The width of the Avalon-MM user field is narrower on the AFU side
// of VTP, since VTP uses a bit to flag VTP page table traffic.
// Drop the high bit of the user field on the AFU side.
localparam AFU_AVMM_USER_WIDTH = host_mem_if[HOSTMEM_CHAN_VTP_SVC].USER_WIDTH_ - 1;

// ====================================================================
//
//  Instantiate the VTP service for use by the host channel.
//  The VTP service is an OFS Avalon shim that injects MMIO and page
//  table traffic into the interface. The VTP translation ports are
//  a separate interface that will be passed to the AFU memory engines.
//  A single vtp-svc block will be instantiated and shared by multiple
//  translation blocks (if required).
//
// ====================================================================

// One pair of ports (c0Tx and c1Tx) for each translation block.
mpf_vtp_port_if vtp_ports[NUM_VTP_PORTS]();

//we only need one of these - it is used for the VTP SVC module; the 
//rest of the channels will skip the SVC module.
ofs_plat_avalon_mem_rdwr_if
#(
    `OFS_PLAT_AVALON_MEM_RDWR_IF_REPLICATE_PARAMS_EXCEPT_TAGS(host_mem_if[HOSTMEM_CHAN_VTP_SVC]),
    .USER_WIDTH(AFU_AVMM_USER_WIDTH),
    .LOG_CLASS(ofs_plat_log_pkg::HOST_CHAN)
) host_mem_if_pa ();
assign host_mem_if_pa.clk = host_mem_if[0].clk;
assign host_mem_if_pa.reset_n = host_mem_if[0].reset_n;
assign host_mem_if_pa.instance_number = host_mem_if[0].instance_number;

// Physical address interface for use by the source paths - DMA and USM. 
// This instance will be the DMA/ASP side of the VTP service shim. (The 
// service shim injects page table requests. It does not translate
// addresses on the memory interfaces. The service shim's VTP
// ports must be used by the AFU for translation.)
ofs_plat_avalon_mem_rdwr_if
#(
    `OFS_PLAT_AVALON_MEM_RDWR_IF_REPLICATE_PARAMS_EXCEPT_TAGS(host_mem_if[HOSTMEM_CHAN_VTP_SVC]),
    .USER_WIDTH(AFU_AVMM_USER_WIDTH),
    .LOG_CLASS(ofs_plat_log_pkg::HOST_CHAN)
) host_mem_if_pa_asp [MAX_NUM_ASP_DMA_AND_USM_CHAN] ();

genvar h0;
generate for (h0=0; h0 < MAX_NUM_ASP_DMA_AND_USM_CHAN; h0=h0+1) begin : asp_chan_clk_assignments
    assign host_mem_if_pa_asp[h0].clk = host_mem_if[HOSTMEM_CHAN_VTP_SVC].clk;
end
endgenerate

mpf_vtp_svc_ofs_avalon_mem_rdwr
#(
    // VTP's CSR byte address. The AFU will add this address to
    // the feature list.
    .DFH_MMIO_BASE_ADDR(VTP_SVC_MMIO_BASE_ADDR),
    .DFH_MMIO_NEXT_ADDR(MPF_VTP_DFH_NEXT_ADDR),
    .N_VTP_PORTS(NUM_VTP_PORTS),
    // The tag must use value not used by the AFU so VTP can identify
    // it's own DMA traffic.
    .USER_TAG_IDX(AFU_AVMM_USER_WIDTH)
    //enable simulation messages
    //,.VTP_DEBUG_MESSAGES(1)
) vtp_svc (
    .mem_sink(host_mem_if[HOSTMEM_CHAN_VTP_SVC]),
    .mem_source(host_mem_if_pa),
    .mmio64_source(mmio64_if),
    .mmio64_sink(mmio64_if_shim),
    .vtp_ports
);

//DMA-specific translations
//DMA CH0 will be connected to the VTP-SVC module.
`ifdef INCLUDE_ASP_DMA
    mpf_vtp_translate_ofs_avalon_mem_rdwr vtp_dma_inst
    (
        .host_mem_if(host_mem_if_pa_asp[HOSTMEM_VTP_SVC_CHAN_DMA]),
        .host_mem_va_if (host_mem_va_if_dma[DMA_VTP_SVC_CHAN]),
        .rd_error(),
        .wr_error(),
        .vtp_ports (vtp_ports[HOSTMEM_VTP_SVC_CHAN_DMA +: NUM_VTP_PORTS_PER_CHAN])
    );
`else
    assign host_mem_if_pa_asp[HOSTMEM_VTP_SVC_CHAN_DMA].rd_read  = 'b0;
    assign host_mem_if_pa_asp[HOSTMEM_VTP_SVC_CHAN_DMA].rd_user  = 'b0;
    assign host_mem_if_pa_asp[HOSTMEM_VTP_SVC_CHAN_DMA].wr_write = 'b0;
    assign host_mem_if_pa_asp[HOSTMEM_VTP_SVC_CHAN_DMA].wr_user  = 'b0;
`endif //INCLUDE_ASP_DMA
genvar d;
generate for (d=1; d<NUM_HOSTMEM_CHAN; d=d+1) begin : dma_channels
    //translation block - kernel
    //DMA CH0 will be connected to the VTP-SVC module; then we alternate DMA/USM.
    `ifdef INCLUDE_ASP_DMA
        mpf_vtp_translate_ofs_avalon_mem_rdwr vtp_dma_inst_gen
        (
            .host_mem_if(host_mem_if_pa_asp[d*2]),
            .host_mem_va_if (host_mem_va_if_dma[d]),
            .rd_error(),
            .wr_error(),
            .vtp_ports (vtp_ports[d*2 +: NUM_VTP_PORTS_PER_CHAN])
        );
    `else
        assign host_mem_if_pa_asp[d*2].rd_read  = 'b0;
        assign host_mem_if_pa_asp[d*2].rd_user  = 'b0;
        assign host_mem_if_pa_asp[d*2].wr_write = 'b0;
        assign host_mem_if_pa_asp[d*2].wr_user  = 'b0;
    `endif //INCLUDE_ASP_DMA
end
endgenerate

//USM-specific translations
//USM CH0 will be connected to the VTP-SVC module.
`ifdef INCLUDE_USM_SUPPORT
    mpf_vtp_translate_ofs_avalon_mem_rdwr vtp_kernel_inst
    (
        .host_mem_if(host_mem_if_pa_asp[HOSTMEM_VTP_SVC_CHAN_USM]),
        .host_mem_va_if (host_mem_va_if_kernel[USM_VTP_SVC_CHAN]),
        .rd_error(),
        .wr_error(),
        .vtp_ports (vtp_ports[NUM_HOSTMEM_CHAN*2 +: NUM_VTP_PORTS_PER_CHAN])
    );
`else
    assign host_mem_if_pa_asp[HOSTMEM_VTP_SVC_CHAN_USM].rd_read  = 'b0;
    assign host_mem_if_pa_asp[HOSTMEM_VTP_SVC_CHAN_USM].rd_user  = 'b0;
    assign host_mem_if_pa_asp[HOSTMEM_VTP_SVC_CHAN_USM].wr_write = 'b0;
    assign host_mem_if_pa_asp[HOSTMEM_VTP_SVC_CHAN_USM].wr_user  = 'b0;
`endif //INCLUDE_USM_SUPPORT
genvar u;
generate for (u=1; u<NUM_HOSTMEM_CHAN; u=u+1) begin : usm_channels
    //translation block - kernel
    //USM CH0 will be connected to the VTP-SVC module.
    `ifdef INCLUDE_USM_SUPPORT
        mpf_vtp_translate_ofs_avalon_mem_rdwr vtp_kernel_inst_gen
        (
            .host_mem_if(host_mem_if_pa_asp[u*2+1]),
            .host_mem_va_if (host_mem_va_if_kernel[u]),
            .rd_error(),
            .wr_error(),
            .vtp_ports (vtp_ports[(NUM_HOSTMEM_CHAN+u)*2 +: NUM_VTP_PORTS_PER_CHAN])
        );
    `else
        assign host_mem_if_pa_asp[u*2+1].rd_read  = 'b0;
        assign host_mem_if_pa_asp[u*2+1].rd_user  = 'b0;
        assign host_mem_if_pa_asp[u*2+1].wr_write = 'b0;
        assign host_mem_if_pa_asp[u*2+1].wr_user  = 'b0;
    `endif //INCLUDE_USM_SUPPORT
end
endgenerate

//CH0 for both DMA and USM will be mux'd together (if they exist) and used for
//the VTP-SVC interface; the rest of the hostmem/dma/usm channels will directly
//be assigned to the non-0 host_mem_if channels.
//mux the host_mem_source/pa interfaces together
ofs_plat_avalon_mem_rdwr_if_mux ofs_plat_avalon_mem_rdwr_if_mux_inst
(
    .mem_sink   (host_mem_if_pa),
    .mem_source (host_mem_if_pa_asp[0:1])
);

//hostmem CH0 is used for VTP-SVC, the rest are just translated. Still
//grouped as pairs of DMA/USM channels.
genvar c;
generate
    for (c=2; c <= NUM_HOSTMEM_CHAN; c=c+1) begin: pa_mux_hostmem_channels
        //mux the host_mem_source/pa interfaces together
        ofs_plat_avalon_mem_rdwr_if_mux ofs_plat_avalon_mem_rdwr_if_mux_inst
        (
            .mem_sink   (host_mem_if[c-1]),
            .mem_source (host_mem_if_pa_asp[2:3])
        );
    end : pa_mux_hostmem_channels
endgenerate

endmodule : host_mem_if_vtp
