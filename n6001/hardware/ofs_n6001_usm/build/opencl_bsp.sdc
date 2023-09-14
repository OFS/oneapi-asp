#separate the PCIe/host, user/kernel, and DDR4-user clocks
set_clock_groups -asynchronous  -group [get_clocks {sys_pll|iopll_0_clk_sys}] \
                                -group [get_clocks {afu_top|pg_afu.port_gasket|user_clock|qph_user_clk|qph_user_clk_iopll|iopll_0_outclk1 \
                                                    afu_top|pg_afu.port_gasket|user_clock|qph_user_clk|qph_user_clk_iopll|iopll_0_outclk0}] \
                                -group [get_clocks {mem_ss_top|mem_ss*inst|mem_ss_fm*|intf_0_core_usr_clk \
                                                    mem_ss_top|mem_ss*inst|mem_ss_fm*|intf_1_core_usr_clk \
                                                    mem_ss_top|mem_ss*inst|mem_ss_fm*|intf_2_core_usr_clk \
                                                    mem_ss_top|mem_ss*inst|mem_ss_fm*|intf_3_core_usr_clk}]
