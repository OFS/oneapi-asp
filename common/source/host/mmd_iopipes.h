// Copyright 2020 Intel Corporation.
//
// THIS SOFTWARE MAY CONTAIN PREPRODUCTION CODE AND IS PROVIDED BY THE
// COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED
// WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
// MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
// DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR
// BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
// WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
// OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
// EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
// Copyright 2022 Intel Corporation
// SPDX-License-Identifier: MIT

#include <string.h> 
#include <cstring> 

#ifndef MMD_IOPIPES_H_
#define MMD_IOPIPES_H_

//#define MAC 1234
//#define FPGA_IP "abc"
//#define GW_IP   "abc"
//#define NETMASK "abc"

namespace intel_opae_mmd {
//void setup_pac(fpga_handle, unsigned long , const std::string& , const std::string& , const std::string& );
//void setup_pac(unsigned long , char * , char * , char * );
//void setup_pac();

// TO DO - do we need any code to monitor IO Pipes errors or performance in MMD?

class iopipes final {
public:
  /** IO Pipes constructor */
  iopipes(int, std::string, std::string, std::string, int,
          std::string, std::string, int, uint64_t);

  /** deleting copy constructor, copy assignment operator, move constructor, move assignment operator */
  iopipes(const iopipes&) = delete;
  iopipes& operator=(const iopipes&) = delete;
  iopipes(const iopipes&&) = delete;
  iopipes& operator=(const iopipes&&) = delete;

  ~iopipes();

  bool setup_iopipes_asp(fpga_handle);

  private:
    int mmd_handle_;
    std::string local_ip_address_;
    std::string local_mac_address_;
    std::string local_netmask_;
    int local_udp_port_;
    std::string remote_ip_address_;
    std::string remote_mac_address_;
    int remote_udp_port_;
    int mmio_num_;
    uint64_t iopipes_dfh_offset_;


}; 

}; // namespace intel_opae_mmd
#endif
