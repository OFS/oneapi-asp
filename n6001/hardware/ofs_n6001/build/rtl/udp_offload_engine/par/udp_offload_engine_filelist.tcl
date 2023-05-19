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

# Directory of script
set THIS_DIR [file dirname [info script]]

set_global_assignment -name SEARCH_PATH "${THIS_DIR}/.."

set_global_assignment -name SYSTEMVERILOG_FILE "${THIS_DIR}/../rtl/width_adapter_64_to_32.sv"
set_global_assignment -name SYSTEMVERILOG_FILE "${THIS_DIR}/../rtl/width_adapter_32_to_64.sv"
set_global_assignment -name SYSTEMVERILOG_FILE "${THIS_DIR}/../rtl/user_csr.sv"
set_global_assignment -name SYSTEMVERILOG_FILE "${THIS_DIR}/../rtl/udp_offload_engine.sv"
set_global_assignment -name SYSTEMVERILOG_FILE "${THIS_DIR}/../rtl/simple_tx.sv"
set_global_assignment -name SYSTEMVERILOG_FILE "${THIS_DIR}/../rtl/simple_rx.sv"
set_global_assignment -name SYSTEMVERILOG_FILE "${THIS_DIR}/../rtl/acl_dcfifo.sv"
set_global_assignment -name SYSTEMVERILOG_FILE "${THIS_DIR}/../rtl/udp_oe_pkg.sv"
set_global_assignment -name SYSTEMVERILOG_FILE "${THIS_DIR}/../rtl/udp_oe_interfaces.sv"

set_global_assignment -name SDC_FILE "${THIS_DIR}/shim_udp_offload_engine.sdc"
