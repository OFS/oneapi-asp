# Copyright 2022 Intel Corporation
# SPDX-License-Identifier: MIT
#


# Directory of script
set THIS_DIR [file dirname [info script]]

set_global_assignment -name SEARCH_PATH "${THIS_DIR}/.."

set_global_assignment -name SYSTEMVERILOG_FILE "${THIS_DIR}/../rtl/udp_oe_csr.sv"
set_global_assignment -name SYSTEMVERILOG_FILE "${THIS_DIR}/../rtl/udp_offload_engine.sv"
set_global_assignment -name SYSTEMVERILOG_FILE "${THIS_DIR}/../rtl/simple_tx.sv"
set_global_assignment -name SYSTEMVERILOG_FILE "${THIS_DIR}/../rtl/simple_rx.sv"
set_global_assignment -name SYSTEMVERILOG_FILE "${THIS_DIR}/../rtl/udp_oe_pkg.sv"
set_global_assignment -name SYSTEMVERILOG_FILE "${THIS_DIR}/../rtl/udp_oe_interfaces.sv"
set_global_assignment -name IP_FILE "${THIS_DIR}/../ip/asp_dcfifo.ip"

#qexec "qsys-generate /nfs/site/disks/swuser_work_dgroen/work/ofs-io-channels-0/071823/oneapi-asp/n6001/hardware/ofs_n6001/build/rtl/udp_offload_engine/ip/asp_dcfifo.ip --quartus-project=ofs_top --output-directory=/nfs/site/disks/swuser_work_dgroen/work/ofs-io-channels-0/071823/oneapi-asp/n6001/hardware/ofs_n6001/build/rtl/udp_offload_engine/ip/ --synthesis"

set_global_assignment -name SDC_FILE "${THIS_DIR}/shim_udp_offload_engine.sdc"
