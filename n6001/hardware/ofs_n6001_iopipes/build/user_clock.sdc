
#3.0ns for 333mhz
#2.86ns for 350mhz
#2.5ns for 400mhz
#2.3ns 434mhz
#2.222ns 450mhz
#2.0ns 500mhz
#1.5ns for 666mhz
#1.43ns for 700mhz
#1.25ns 800mhz

#remove existing constraints on the user clocks
remove_clock afu_top|pg_afu.port_gasket|user_clock|qph_user_clk|qph_user_clk_iopll|iopll_0_outclk0
remove_clock afu_top|pg_afu.port_gasket|user_clock|qph_user_clk|qph_user_clk_iopll|iopll_0|tennm_pll|outclk[1]
remove_clock afu_top|pg_afu.port_gasket|user_clock|qph_user_clk|qph_user_clk_iopll|iopll_0_outclk1
remove_clock afu_top|pg_afu.port_gasket|user_clock|qph_user_clk|qph_user_clk_iopll|iopll_0|tennm_pll|outclk[2]

#kernel clk 1x / uClk_usrDiv2
create_clock -name {afu_top|pg_afuport_gasket|user_clock|qph_user_clk|qph_user_clk_iopll|iopll_0_outclk0} -period 1.5 [get_pins {afu_top|port_gasket|user_clock|qph_user_clk|qph_user_clk_iopll|iopll_0|tennm_pll|outclk[1]}] 

#kernel clk 2x / uClk_usr
create_clock -name {afu_top|pg_afu.port_gasket|user_clock|qph_user_clk|qph_user_clk_iopll|iopll_0_outclk1} -period 1.5 [get_pins {afu_top|port_gasket|user_clock|qph_user_clk|qph_user_clk_iopll|iopll_0|tennm_pll|outclk[2]}] 
