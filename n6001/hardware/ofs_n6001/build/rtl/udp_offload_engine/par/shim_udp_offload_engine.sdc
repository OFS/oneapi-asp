#false paths for the toggle clock crosser
set_false_path  -from *|udp_offload_engine|*|*_dcfifo|*_toggle[?] \
                -to   *|udp_offload_engine|*|*_dcfifo|*_toggle_inst|sync_stage_?[?]

set_false_path  -from *|udp_offload_engine|*|*_dcfifo|*_toggle_inst|sync_stage_*[?] \
                -to   *|udp_offload_engine|*|*_dcfifo|*_toggle_readback_inst|sync_stage*[?]

set_false_path -from *|udp_offload_engine|*csr|udp_oe_ctrl.* -to *|udp_offload_engine|simple_*x|*
set_false_path -to *|udp_offload_engine|*csr|udp_oe_ctrl.* -from *|udp_offload_engine|simple_*x|*

#set_false_path -from *alt_sld_fab_0*
#set_false_path -to *alt_sld_fab_0*

set_false_path -from [get_keepers {*|udp_offload_engine|*|rd_resetn_async_pipe[*]}] \
               -to   [get_keepers {*|udp_offload_engine|*|wr_resetn_async_pipe[*]}]
set_false_path -from [get_keepers {*|udp_offload_engine|*|rd_resetn_async_pipe[*]}] \
               -to   [get_keepers {*|udp_offload_engine|*|wr_resync_resetn_body[*]}]
set_false_path -from [get_keepers {*|udp_offload_engine|*|rd_resetn_async_pipe[*]}] \
               -to   [get_keepers {*|udp_offload_engine|*|wr_resync_resetn_head}]
               
set_false_path -from [get_keepers {*|udp_offload_engine|*|wr_resetn_body[1]}] \
               -to   [get_keepers {*|udp_offload_engine|*|rd_resetn_async_pipe[*]}]
set_false_path -from [get_keepers {*|udp_offload_engine|*|wr_resetn_body[1]}] \
               -to   [get_keepers {*|udp_offload_engine|*|rd_resetn_head}]
set_false_path -from [get_keepers {*|udp_offload_engine|*|wr_resetn_body[*]}] \
               -to   [get_keepers {*|udp_offload_engine|*|rd_resetn_body[*]}] \

set_false_path -from [get_keepers {*|hssi_tx_rst_n}] -to [get_keepers {*|udp_offload_engine|*|wr_resetn_head}]
set_false_path -from [get_keepers {*|hssi_tx_rst_n}] -to [get_keepers {*|udp_offload_engine|*|wr_resetn_body*}]
