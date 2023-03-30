#include <string.h> 
#include <cstring> 

#ifndef MMD_IOPIPES_H_
#define MMD_IOPIPES_H_

#define MAC 1234
#define FPGA_IP "abc"
#define GW_IP   "abc"
#define NETMASK "abc"

namespace intel_opae_mmd {
//void setup_pac(fpga_handle, unsigned long , const std::string& , const std::string& , const std::string& );
//void setup_pac(unsigned long , char * , char * , char * );
//void setup_pac();

class iopipes final {
public:
  /** IO Pipes constructor */
  iopipes(int);

  /** deleting copy constructor, copy assignment operator, move constructor, move assignment operator */
  iopipes(const iopipes&) = delete;
  iopipes& operator=(const iopipes&) = delete;
  iopipes(const iopipes&&) = delete;
  iopipes& operator=(const iopipes&&) = delete;

  ~iopipes();

  void setup_iopipes_asp(fpga_handle);

  private:
    int m_mmd_handle;

}; 

}; // namespace intel_opae_mmd
#endif
