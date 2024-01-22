// Copyright 2022 Intel Corporation
// SPDX-License-Identifier: MIT
//

`include "ofs_plat_if.vh"
`include "ofs_asp.vh"

module host_mem_if_vtp
  (
    // Host memory sink (Avalon rdwr) - host-facing
    ofs_plat_avalon_mem_rdwr_if.to_sink host_mem_if,
    // Host memory sources (Avalon rdwr) - shim-facing
    ofs_plat_avalon_mem_rdwr_if.to_source host_mem_va_if_dma,
    `ifdef INCLUDE_USM_SUPPORT
        ofs_plat_avalon_mem_rdwr_if.to_source host_mem_va_if_kernel,
    `endif

    // FPGA MMIO master (Avalon) - host-facing
    ofs_plat_avalon_mem_if.to_source mmio64_if,
    // FPGA MMIO master (Avalon) - shim-facing
    ofs_plat_avalon_mem_if.to_sink mmio64_if_shim
);

import ofs_asp_pkg::*;

// The width of the Avalon-MM user field is narrower on the AFU side
// of VTP, since VTP uses a bit to flag VTP page table traffic.
// Drop the high bit of the user field on the AFU side.
localparam AFU_AVMM_USER_WIDTH = host_mem_if.USER_WIDTH_ - 1;

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
mpf_vtp_port_if vtp_ports[NUM_VTP_PORTS-1:0]();

ofs_plat_avalon_mem_rdwr_if
#(
    `OFS_PLAT_AVALON_MEM_RDWR_IF_REPLICATE_PARAMS_EXCEPT_TAGS(host_mem_if),
    .USER_WIDTH(AFU_AVMM_USER_WIDTH),
    .LOG_CLASS(ofs_plat_log_pkg::HOST_CHAN)
) host_mem_if_pa();
  
assign host_mem_if_pa.clk = host_mem_if.clk;
assign host_mem_if_pa.reset_n = host_mem_if.reset_n;
assign host_mem_if_pa.instance_number = host_mem_if.instance_number;

// Physical address interface for use by the source paths - DMA and USM. 
// This instance will be the DMA/BSP side of the VTP service shim. (The 
// service shim injects page table requests. It does not translate
// addresses on the memory interfaces. The service shim's VTP
// ports must be used by the AFU for translation.)
ofs_plat_avalon_mem_rdwr_if
#(
    `OFS_PLAT_AVALON_MEM_RDWR_IF_REPLICATE_PARAMS_EXCEPT_TAGS(host_mem_if),
    .USER_WIDTH(AFU_AVMM_USER_WIDTH),
    .LOG_CLASS(ofs_plat_log_pkg::HOST_CHAN)
) host_mem_if_pa_bsp [1:0] ();

assign host_mem_if_pa_bsp[0].clk = host_mem_if.clk;
assign host_mem_if_pa_bsp[1].clk = host_mem_if.clk;

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
    .mem_sink(host_mem_if),
    .mem_source(host_mem_if_pa),
    .mmio64_source(mmio64_if),
    .mmio64_sink(mmio64_if_shim),
    .vtp_ports
);

//translation block - DMA
mpf_vtp_translate_ofs_avalon_mem_rdwr vtp_dma_inst
   (
    .host_mem_if(host_mem_if_pa_bsp[0]),
    .host_mem_va_if (host_mem_va_if_dma),
    .rd_error(),
    .wr_error(),
    .vtp_ports (vtp_ports[1:0])
    );

`ifdef INCLUDE_USM_SUPPORT
    //translation block - kernel
    mpf_vtp_translate_ofs_avalon_mem_rdwr vtp_kernel_inst
    (
        .host_mem_if(host_mem_if_pa_bsp[1]),
        .host_mem_va_if (host_mem_va_if_kernel),
        .rd_error(),
        .wr_error(),
        .vtp_ports (vtp_ports[3:2])
    );
`else
    assign host_mem_if_pa_bsp[1].rd_read  = 'b0;
    assign host_mem_if_pa_bsp[1].rd_user  = 'b0;
    assign host_mem_if_pa_bsp[1].wr_write = 'b0;
    assign host_mem_if_pa_bsp[1].wr_user  = 'b0;
`endif //INCLUDE_USM_SUPPORT

    //mux the two host_mem_source interfaces together
    ofs_plat_avalon_mem_rdwr_if_mux ofs_plat_avalon_mem_rdwr_if_mux_inst
    (
        .mem_sink   (host_mem_if_pa),
        .mem_source (host_mem_if_pa_bsp)
    );

endmodule : host_mem_if_vtp
