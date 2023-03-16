#include <string.h> 
#include <cstring> 

#ifndef MMD_IOPIPES_H_
#define MMD_IOPIPES_H_
namespace intel_opae_mmd {
void setup_pac(fpga_handle, unsigned long , const std::string& , const std::string& , const std::string& );
//void setup_pac(unsigned long , char * , char * , char * );
//void setup_pac();
}; // namespace intel_opae_mmd
#endif
