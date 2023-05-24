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
          std::string, std::string, int);

  /** deleting copy constructor, copy assignment operator, move constructor, move assignment operator */
  iopipes(const iopipes&) = delete;
  iopipes& operator=(const iopipes&) = delete;
  iopipes(const iopipes&&) = delete;
  iopipes& operator=(const iopipes&&) = delete;

  ~iopipes();

  void setup_iopipes_asp(fpga_handle);

  private:
    int m_mmd_handle;
    std::string m_local_ip_address;
    std::string m_local_mac_address;
    std::string m_local_netmask;
    int m_local_udp_port;
    std::string m_remote_ip_address;
    std::string m_remote_mac_address;
    int m_remote_udp_port;

}; 

}; // namespace intel_opae_mmd
#endif
