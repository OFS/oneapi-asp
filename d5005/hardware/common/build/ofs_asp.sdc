# Copyright 2022 Intel Corporation
# SPDX-License-Identifier: MIT

#separate the CCIP/host, user/kernel, and DDR4-user clocks
set_clock_groups -asynchronous -group [get_clocks {sys_pll|iopll_0_clk2x}] -group [get_clocks {afu_top|port_gasket|user_clock|qph_user_clk|qph_user_clk_iopll|iopll_0_outclk0 afu_top|port_gasket|user_clock|qph_user_clk|qph_user_clk_iopll|iopll_0_outclk1}] -group [get_clocks {emif_top_inst|mem_bank[0].emif_ddr4_inst|emif_s10_0_core_usr_clk emif_top_inst|mem_bank[1].emif_ddr4_inst|emif_s10_0_core_usr_clk emif_top_inst|mem_bank[2].emif_ddr4_inst|emif_s10_0_core_usr_clk emif_top_inst|mem_bank[3].emif_ddr4_inst|emif_s10_0_core_usr_clk}]

set_clock_groups -asynchronous -group [get_clocks {sys_pll|iopll_0_clk_250M}] -group [get_clocks {afu_top|port_gasket|user_clock|qph_user_clk|qph_user_clk_iopll|iopll_0_outclk0 afu_top|port_gasket|user_clock|qph_user_clk|qph_user_clk_iopll|iopll_0_outclk1}] -group [get_clocks {emif_top_inst|mem_bank[0].emif_ddr4_inst|emif_s10_0_core_usr_clk emif_top_inst|mem_bank[1].emif_ddr4_inst|emif_s10_0_core_usr_clk emif_top_inst|mem_bank[2].emif_ddr4_inst|emif_s10_0_core_usr_clk emif_top_inst|mem_bank[3].emif_ddr4_inst|emif_s10_0_core_usr_clk}]

