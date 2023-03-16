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
//

#include <cassert>
#include <cstdlib>
#include <cstring>
#include <string.h>
#include <sys/mman.h>

#include <chrono>
#include <iostream>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>

#include "ccip_mmd_device.h"
#include "mmd_iopipes.h"

namespace intel_opae_mmd {

//using namespace intel_opae_mmd;


#define BSP_AFU_GUID "96ef4230-dafa-cb5f-18b7-9ffa2ee54aa0"
#define N6000_PCI_OCL_BSP_AFU_ID "51ED2F4A-FEA2-4261-A595-918500575509"
#define N6000_SVM_OCL_BSP_AFU_ID "5D9FEF7B-C491-4DCE-95FC-F979F6F061BE"

//base address is 0x20800
//dfh base offset is 0x0
//udp offload engine csrs offset is 0x10
#define REG_UDPOE_BASE_ADDR    0x20800
#define REG_UDPOE_DFH_BASE_ADDR   (REG_UDPOE_BASE_ADDR + (0x0*0x8))
#define REG_UDPOE_CSR_BASE_ADDR   (REG_UDPOE_BASE_ADDR + (0x10*0x8))

#define CSR_FPGA_MAC_ADR_ADDR   (REG_UDPOE_CSR_BASE_ADDR+(0x00*0x8))
#define CSR_FPGA_IP_ADR_ADDR   (REG_UDPOE_CSR_BASE_ADDR+(0x01*0x8))
#define CSR_FPGA_UDP_PORT_ADDR   (REG_UDPOE_CSR_BASE_ADDR+(0x02*0x8))
#define CSR_FPGA_NETMASK_ADDR (REG_UDPOE_CSR_BASE_ADDR+(0x03*0x8))
#define CSR_HOST_MAC_ADR_ADDR     (REG_UDPOE_CSR_BASE_ADDR+(0x04*0x8))
#define CSR_HOST_IP_ADR_ADDR   (REG_UDPOE_CSR_BASE_ADDR+(0x05*0x8))
#define CSR_HOST_UDP_PORT_ADDR   (REG_UDPOE_CSR_BASE_ADDR+(0x06*0x8))
#define CSR_PAYLOAD_PER_PACKET_ADDR   (REG_UDPOE_CSR_BASE_ADDR+(0x07*0x8))
#define CSR_CHECKSUM_IP_ADDR   (REG_UDPOE_CSR_BASE_ADDR+(0x08*0x8))
#define CSR_RESET_REG_ADDR     (REG_UDPOE_CSR_BASE_ADDR+(0x09*0x8))
#define CSR_STATUS_REG_ADDR     (REG_UDPOE_CSR_BASE_ADDR+(0x0A*0x8))
#define CSR_MISC_CTRL_REG_ADDR     (REG_UDPOE_CSR_BASE_ADDR+(0x0B*0x8))

#define UDP_MAX_BUFSIZE 16*1024
#define UDP_PORT_NUM    12345

#define CSR_MAC_VAL 0x001122334455

#define N 50 // data size

// setting IP/gateway/netmask to PAC
//void setup_pac(unsigned long mac, const char *fpga_ip,const char *gw_ip,const char *netmask)
void setup_pac(fpga_handle afc_handle, unsigned long mac, const std::string& fpga_ip, const std::string&  gw_ip, const std::string& netmask)
//void setup_pac()
{
  fpga_result res = FPGA_OK;
  
  printf("Doug - inside setup-pac function (a)\n");

  //const char* fpga_ip = c_fpga_ip.c_str();
  //const char *gw_ip = c_gw_ip.data();
  //const char *netmask = c_netmask.data();
  
  /*fpga_properties    filter = NULL;
  fpga_token         afc_token;
  fpga_handle        afc_handle;
  fpga_guid          guid;
  uint32_t           num_matches;

  fpga_result res = FPGA_OK;
  
  if (uuid_parse(N6000_SVM_OCL_BSP_AFU_ID, guid) < 0) {
    fprintf(stderr, "Error parsing guid '%s'\n", BSP_AFU_GUID);
    exit(1);
  }
  
  if ((res = fpgaGetProperties(NULL, &filter)) != FPGA_OK) {
    printf("Error:creating properties object");
    exit(1);
  }

  if ((res = fpgaPropertiesSetObjectType(filter, FPGA_ACCELERATOR)) != FPGA_OK) {
    printf("Error:setting object type");
    exit(1);
  }

  if ((res = fpgaPropertiesSetGUID(filter, guid)) != FPGA_OK) {
    printf("Error:setting GUID");
  }

  if ((res = fpgaEnumerate(&filter, 1, &afc_token, 1, &num_matches)) != FPGA_OK) {

    printf("Error:enumerating AFCs");
  }

  if (num_matches < 1) {
    fprintf(stderr, "AFC not found.\n");
    res = fpgaDestroyProperties(&filter);
    exit(1);
  }

  if ((res = fpgaOpen(afc_token, &afc_handle, FPGA_OPEN_SHARED)) != FPGA_OK) {
    printf("Error:opening AFC");
    exit(1);
  }

  if ((res = fpgaMapMMIO(afc_handle, 0, NULL)) != FPGA_OK) {
    printf("Error:mapping MMIO space");
    exit(1);
  }

  if ((res = fpgaReset(afc_handle)) != FPGA_OK) {
    printf("Error:resetting AFC");
    exit(1);
  }
*/
  uint64_t data = 0;
  
  fprintf(stderr, "iopipes.cpp - dump the DFH registers...\n");
  for (uint64_t this_addr = REG_UDPOE_BASE_ADDR; this_addr<=CSR_STATUS_REG_ADDR;this_addr+=8) {
      fprintf(stderr, "******* Read/write/read the UDP OE register 0x%lx\n",this_addr);
      res = fpgaReadMMIO64(afc_handle, 0, this_addr, &data);
      fprintf(stderr, "data: 0x%lx\n",data);
      fprintf(stderr, "writing 0x123456789abcdef to addr 0x%lx\n",this_addr);
      res = fpgaWriteMMIO64(afc_handle, 0, this_addr, 0x123456789abcdef);
      fprintf(stderr, "reading addr 0x%lx\n",this_addr);
      res = fpgaReadMMIO64(afc_handle, 0, this_addr, &data);
      fprintf(stderr, "data: 0x%lx\n\n\n",data);
  }

  fprintf(stderr, "iopipes.cpp - CSR_RESET_REG_ADDR is 0x%x\n",CSR_RESET_REG_ADDR);
  
  // MAC reset
  //res = fpgaWriteMMIO64(m_fpga_handle, mmio_num, dma_csr_src, dma_src_addr);
  res = fpgaWriteMMIO64(afc_handle, 0, REG_UDPOE_BASE_ADDR, 0x7);
  if (res != FPGA_OK) {
    printf("error is %d, OK is %d, Exception is %d, Invalid param is %d \n",res, FPGA_OK, FPGA_EXCEPTION, FPGA_INVALID_PARAM);
    printf("Error:writing RST\n");
    exit(1);
  }
  printf("Doug - inside setup-pac function (b)\n");
  usleep(10000);
  if ((res = fpgaWriteMMIO64(afc_handle, 0, CSR_RESET_REG_ADDR, 0x3)) != FPGA_OK) {
    printf("Error:writing RST\n");
    exit(1);
  }
  printf("Doug - inside setup-pac function (c)\n");
  usleep(10000);
  if ((res = fpgaWriteMMIO64(afc_handle, 0, CSR_RESET_REG_ADDR, 0x0)) != FPGA_OK) {
    printf("Error:writing RST\n");
    exit(1);
  }
  usleep(5000000); // TODO: need to check if reset/wait is needed
  printf("Doug - inside setup-pac function (d)\n");
  //
  // UOE register settings. These registers are not reset even after fpgaClose().
  //
  if ((res = fpgaWriteMMIO64(afc_handle, 0, CSR_FPGA_MAC_ADR_ADDR, mac)) != FPGA_OK) {
    printf("Error:writing CSR");
    exit(1);
  }
  if ((res = fpgaWriteMMIO64(afc_handle, 0, CSR_HOST_MAC_ADR_ADDR, mac)) != FPGA_OK) {
    printf("Error:writing CSR");
    exit(1);
  }
  
  //CSR_PAYLOAD_PER_PACKET_ADDR
  if ((res = fpgaWriteMMIO64(afc_handle, 0, CSR_PAYLOAD_PER_PACKET_ADDR, (unsigned long) 32)) != FPGA_OK) {
    printf("Error:writing CSR");
    exit(1);
  }
  //CSR_MISC_CTRL_REG_ADDR
  if ((res = fpgaWriteMMIO64(afc_handle, 0, CSR_MISC_CTRL_REG_ADDR, (unsigned long) 1)) != FPGA_OK) {
    printf("Error:writing CSR");
    exit(1);
  }
  

  unsigned long tmp1 = htonl(inet_addr(fpga_ip.c_str()));
  unsigned long tmp2 = htonl(inet_addr(gw_ip.c_str()));
  if ((res = fpgaWriteMMIO64(afc_handle, 0, CSR_FPGA_IP_ADR_ADDR, tmp1 * 0x100000000 + (tmp2 & 0xffffffff))) != FPGA_OK) {
    printf("Error:writing CSR");
    exit(1);
  }
  if ((res = fpgaWriteMMIO64(afc_handle, 0, CSR_HOST_IP_ADR_ADDR, tmp1 * 0x100000000 + (tmp2 & 0xffffffff))) != FPGA_OK) {
    printf("Error:writing CSR");
    exit(1);
  }
  unsigned long tmp3 = htonl(inet_addr(netmask.c_str()));
  if ((res = fpgaWriteMMIO64(afc_handle, 0, CSR_FPGA_NETMASK_ADDR, tmp3)) != FPGA_OK) {
    printf("Error:writing CSR");
    exit(1);
  }
  res = fpgaReadMMIO64(afc_handle, 0, CSR_FPGA_MAC_ADR_ADDR, &data);
  printf("Read CSR: MAC:%08lx\n", data);
/*
  if ((res = fpgaUnmapMMIO(afc_handle, 0)) != FPGA_OK) {
    printf("Error:unmapping MMIO space");
    exit(1);
  }
  if ((res = fpgaClose(afc_handle)) != FPGA_OK) {
    printf("Error:closing AFC");
    exit(1);
  }

  if ((res = fpgaDestroyToken(&afc_token)) != FPGA_OK) {
    printf("Error:destroying token");
    exit(1);
  }
  if ((res = fpgaDestroyProperties(&filter)) != FPGA_OK) {
    printf("Error:destroying properties object");
    exit(1);
  }
  */
}
}; 
