# Copyright 2022 Intel Corporation
# SPDX-License-Identifier: MIT

# Make the kernel reset multicycle
set_multicycle_path -to * -setup 5 -from {green_bs|pim_green_bs|ofs_plat_afu|afu|bsp_logic_inst|board_inst|*|reset_controller_*|alt_rst_sync_uq?|altera_reset_synchronizer_int_chain_out}
set_multicycle_path -to * -hold  4  -from {green_bs|pim_green_bs|ofs_plat_afu|afu|bsp_logic_inst|board_inst|*|reset_controller_*|alt_rst_sync_uq?|altera_reset_synchronizer_int_chain_out}

set_multicycle_path -from {green_bs|*|acl_hyper_optimized_ccb_0|master_rst_d} -to {green_bs|*|acl_hyper_optimized_ccb_0|slave_rst_r[0]} -setup -end 4
set_multicycle_path -from {green_bs|*|acl_hyper_optimized_ccb_0|master_rst_d} -to {green_bs|*|acl_hyper_optimized_ccb_0|slave_rst_r[0]} -hold -end 5
set_multicycle_path -from {green_bs|*|acl_hyper_optimized_ccb_0|slave_rst_d2} -to {green_bs|*|acl_hyper_optimized_ccb_0|rsp_master_reset_0} -setup -end 5
set_multicycle_path -from {green_bs|*|acl_hyper_optimized_ccb_0|slave_rst_d2} -to {green_bs|*|acl_hyper_optimized_ccb_0|rsp_master_reset_0} -hold -end 4

set_multicycle_path -from {green_bs|*|clock_crosser|slave_rst_d2} -to {green_bs|*|clock_crosser|rsp_master_reset_0} -setup -end 5
set_multicycle_path -from {green_bs|*|clock_crosser|slave_rst_d2} -to {green_bs|*|clock_crosser|rsp_master_reset_0} -hold -end 4
set_multicycle_path -from {green_bs|*|clock_crosser|master_rst_d} -to {green_bs|*|clock_crosser|slave_rst_r[0]} -setup -end 5
set_multicycle_path -from {green_bs|*|clock_crosser|master_rst_d} -to {green_bs|*|clock_crosser|slave_rst_r[0]} -hold -end 4

set_false_path -to [get_pins -compatibility_mode -nocase *|alt_rst_sync_uq1|altera_reset_synchronizer_int_chain*|d]

set_false_path -to {green_bs|uclk_usr_q?}
