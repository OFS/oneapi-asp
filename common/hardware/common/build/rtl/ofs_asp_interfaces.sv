// Copyright 2022 Intel Corporation
// SPDX-License-Identifier: MIT
//

//defining OFS ASP kernel/cra connections
interface kernel_control_intf #(
    parameter CRA_DATA_WIDTH    = ofs_asp_pkg::KERNEL_CRA_DATA_WIDTH,
    parameter CRA_ADDR_WIDTH    = ofs_asp_pkg::KERNEL_CRA_ADDR_WIDTH,
    parameter CRA_BYTE_EN_WIDTH = ofs_asp_pkg::KERNEL_CRA_BYTEENABLE_WIDTH
);

    logic kernel_reset_n;
    logic kernel_irq;

    logic                           kernel_cra_waitrequest;
    logic [CRA_DATA_WIDTH-1:0]      kernel_cra_readdata;
    logic                           kernel_cra_readdatavalid;
    logic                           kernel_cra_burstcount;
    logic [CRA_DATA_WIDTH-1:0]      kernel_cra_writedata;
    logic [CRA_ADDR_WIDTH-1:0]      kernel_cra_address;
    logic                           kernel_cra_write;
    logic                           kernel_cra_read;
    logic [CRA_BYTE_EN_WIDTH-1:0]   kernel_cra_byteenable;
    logic                           kernel_cra_debugaccess;


    //kernel_wrapper module
    modport kw (
        input   kernel_reset_n, kernel_cra_burstcount, kernel_cra_writedata, 
                kernel_cra_address, kernel_cra_write, kernel_cra_read, kernel_cra_debugaccess,
                kernel_cra_byteenable,
        output  kernel_irq, kernel_cra_waitrequest, kernel_cra_readdata,
                kernel_cra_readdatavalid
    );
    
    //asp_interface module
    modport asp (
        input   kernel_irq, kernel_cra_waitrequest, kernel_cra_readdata,
                kernel_cra_readdatavalid,
        output  kernel_reset_n, kernel_cra_burstcount, kernel_cra_writedata, 
                kernel_cra_address, kernel_cra_write, kernel_cra_read, kernel_cra_debugaccess,
                kernel_cra_byteenable
    );

endinterface : kernel_control_intf

interface kernel_mem_intf #(
    parameter ADDR_WIDTH        = ofs_asp_pkg::ASP_LOCALMEM_AVMM_ADDR_WIDTH,
    parameter DATA_WIDTH        = ofs_asp_pkg::ASP_LOCALMEM_AVMM_DATA_WIDTH,
    parameter BURSTCOUNT_WIDTH  = ofs_asp_pkg::ASP_LOCALMEM_QSYS_BURSTCNT_WIDTH,
    parameter BYTEENABLE_WIDTH  = ofs_asp_pkg::ASP_LOCALMEM_AVMM_BYTEENABLE_WIDTH
);
    logic                           waitrequest;
    logic [DATA_WIDTH-1:0]          readdata;
    logic                           readdatavalid;
    
    logic [BURSTCOUNT_WIDTH-1:0]    burstcount;
    logic [DATA_WIDTH-1:0]          writedata;
    logic [ADDR_WIDTH-1:0]          address;
    logic                           write;
    logic                           read;
    logic [BYTEENABLE_WIDTH-1:0]    byteenable;
    logic                           writeack;
    
    modport asp (
        input  read, write, writedata, address, burstcount,
               byteenable,
        output readdata, readdatavalid, waitrequest, writeack
    );
    modport ker (
        input  readdata, readdatavalid, waitrequest, writeack,
        output read, write, writedata, address, burstcount,
               byteenable
    );
endinterface : kernel_mem_intf

