set_false_path -from *|udp_offload_engine|*csr|udp_oe_ctrl.* -to *|udp_offload_engine|simple_*x|*
set_false_path -to *|udp_offload_engine|*csr|udp_oe_ctrl.* -from *|udp_offload_engine|simple_*x|*

set_false_path -from [get_keepers {*|hssi_tx_rst_n}] -to [get_keepers {*|udp_offload_engine|*|wraclr|*}]
set_false_path -from [get_keepers {*|hssi_rx_rst_n}] -to [get_keepers {*|udp_offload_engine|*|rdaclr|*}]
