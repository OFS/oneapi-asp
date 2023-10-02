// Copyright 2022 Intel Corporation
// SPDX-License-Identifier: MIT
//

interface shim_avst_if #(
    parameter DATA_WIDTH        = ofs_asp_pkg::SHIM_AVST_DATA_WIDTH
);
    logic                           valid;
    logic                           ready;
    logic [DATA_WIDTH-1:0]          data;
    
    modport source (
        input  ready,
        output valid, data
    );
    modport sink (
        input  valid, data,
        output ready
    );
endinterface : shim_avst_if
