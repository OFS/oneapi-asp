# Copyright 2020 Intel Corporation.
#
# THIS SOFTWARE MAY CONTAIN PREPRODUCTION CODE AND IS PROVIDED BY THE
# COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED
# WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR
# BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
# WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
# OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
# EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#
#--------------------
# IPs
#--------------------
set_global_assignment -name QSYS_FILE "board.qsys"
set_global_assignment -name QSYS_FILE "ddr_channel.qsys"
set_global_assignment -name QSYS_FILE "ddr_board.qsys"

#--------------------
# DMA controller
#--------------------
set_global_assignment -name SOURCE_TCL_SCRIPT_FILE  "./rtl/dma/par/dma_controller_filelist.tcl"

#--------------------
# MPF VTP files
#--------------------
source "mpf_vtp.qsf"

#--------------------
# BSP RTL files
#--------------------
set_global_assignment -name SYSTEMVERILOG_FILE "rtl/ofs_plat_afu.sv"
set_global_assignment -name SYSTEMVERILOG_FILE "rtl/afu.sv"
set_global_assignment -name SYSTEMVERILOG_FILE "rtl/host_mem_if_vtp.sv"
set_global_assignment -name SYSTEMVERILOG_FILE "rtl/kernel_wrapper.v"
set_global_assignment -name SYSTEMVERILOG_FILE "rtl/bsp_logic.sv"
set_global_assignment -name SYSTEMVERILOG_FILE "rtl/dc_bsp_interfaces.sv"
set_global_assignment -name SYSTEMVERILOG_FILE "rtl/dc_bsp_pkg.sv"
set_global_assignment -name SYSTEMVERILOG_FILE "rtl/bsp_host_mem_if_mux.sv"
set_global_assignment -name SYSTEMVERILOG_FILE "rtl/avmm_wr_ack_gen.sv"
set_global_assignment -name SYSTEMVERILOG_FILE "rtl/avmm_wr_ack_burst_to_word.sv"
set_global_assignment -name SYSTEMVERILOG_FILE "rtl/avmm_wr_ack_tracker.sv"

#--------------------
# Search paths (for headers, etc)
#--------------------
set_global_assignment -name SEARCH_PATH rtl/

#--------------------
# SDC
#--------------------
set_global_assignment -name SDC_FILE "user_clock.sdc"
set_global_assignment -name SDC_FILE "reset.sdc"
set_global_assignment -name SDC_FILE "opencl_bsp.sdc"
