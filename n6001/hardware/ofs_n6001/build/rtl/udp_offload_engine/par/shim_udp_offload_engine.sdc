#false paths for the toggle clock crosser
set_false_path  -from *|udp_offload_engine|*|tx_dcfifo|wr_toggle[2] \
                -to   *|udp_offload_engine|*|tx_dcfifo|wr_toggle_inst|sync_stage_1[2]

set_false_path  -from *|udp_offload_engine|*|tx_dcfifo|wr_toggle_inst|sync_stage_3[2] \
                -to   *|udp_offload_engine|*|tx_dcfifo|wr_toggle_readback_inst|sync_stage_1[2]

set_false_path  -from *|udp_offload_engine|*|tx_dcfifo|acl_dcfifo_reset_synchronizer_inst|wr_resetn_body[1] \
                -to   *|udp_offload_engine|*|tx_dcfifo|acl_dcfifo_reset_synchronizer_inst|*

