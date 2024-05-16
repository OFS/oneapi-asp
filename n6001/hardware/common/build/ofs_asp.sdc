#separate the PCIe/host, user/kernel, and DDR4-user clocks
set_clock_groups -asynchronous  -group [get_clocks {sys_pll|iopll_0_clk_sys}] \
                                -group [get_clocks {afu_top|pg_afu.port_gasket|user_clock|qph_user_clk|qph_user_clk_iopll|iopll_0_outclk1 \
                                                    afu_top|pg_afu.port_gasket|user_clock|qph_user_clk|qph_user_clk_iopll|iopll_0_outclk0}] \
                                -group [get_clocks {mem_ss_top|mem_ss_inst|mem_ss|emif_0|emif_0_core_usr_clk \
                                                    mem_ss_top|mem_ss_inst|mem_ss|emif_1|emif_1_core_usr_clk \
                                                    mem_ss_top|mem_ss_inst|mem_ss|emif_2|emif_2_core_usr_clk \
                                                    mem_ss_top|mem_ss_inst|mem_ss|emif_3|emif_3_core_usr_clk}]
