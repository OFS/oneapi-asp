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
#include <algorithm>
#include <sstream>

#include <chrono>
#include <iostream>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>

#include "mmd_device.h"
#include "mmd_iopipes.h"

using namespace intel_opae_mmd;

//base address is 0x20800
//dfh base offset is 0x0
//udp offload engine csrs offset is 0x10
//#define REG_UDPOE_BASE_ADDR           0x20800
/*#define REG_UDPOE_DFH_BASE_ADDR       (REG_UDPOE_BASE_ADDR + (0x0*0x8))
#define REG_UDPOE_CSR_BASE_ADDR       (REG_UDPOE_BASE_ADDR + (0x10*0x8))

#define CSR_NUM_CHANNELS_ADDR         (REG_UDPOE_CSR_BASE_ADDR+(0x00*0x8))

#define CSR_FPGA_MAC_ADR_ADDR         (REG_UDPOE_CSR_BASE_ADDR+(0x00*0x8))
#define CSR_FPGA_IP_ADR_ADDR          (REG_UDPOE_CSR_BASE_ADDR+(0x01*0x8))
#define CSR_FPGA_UDP_PORT_ADDR        (REG_UDPOE_CSR_BASE_ADDR+(0x02*0x8))
#define CSR_FPGA_NETMASK_ADDR         (REG_UDPOE_CSR_BASE_ADDR+(0x03*0x8))
#define CSR_HOST_MAC_ADR_ADDR         (REG_UDPOE_CSR_BASE_ADDR+(0x04*0x8))
#define CSR_HOST_IP_ADR_ADDR          (REG_UDPOE_CSR_BASE_ADDR+(0x05*0x8))
#define CSR_HOST_UDP_PORT_ADDR        (REG_UDPOE_CSR_BASE_ADDR+(0x06*0x8))

#define CSR_PAYLOAD_PER_PACKET_ADDR   (REG_UDPOE_CSR_BASE_ADDR+(0x07*0x8))
#define CSR_CHECKSUM_IP_ADDR          (REG_UDPOE_CSR_BASE_ADDR+(0x08*0x8))
#define CSR_RESET_REG_ADDR            (REG_UDPOE_CSR_BASE_ADDR+(0x09*0x8))

#define IOPIPES_CSR_START_ADDR          (REG_UDPOE_CSR_BASE_ADDR+(0x09*0x8))
 
//below CSRs per io pipe 
//#define CSR_STATUS_REG_ADDR           (REG_UDPOE_CSR_BASE_ADDR+(0x0A*0x8))
//#define CSR_MISC_CTRL_REG_ADDR        (REG_UDPOE_CSR_BASE_ADDR+(0x0B*0x8))
*/

#define CHECKSUM_IP     43369
#define UDP_MAX_BUFSIZE 16*1024
#define UDP_PORT_NUM    12345
#define CSR_MAC_VAL     0x001122334455

#define N               50 // data size

// Utility to parse a MAC address string
// It converts MAC address to unsigned long number
unsigned long ParseMACAddress(std::string mac_str){
  std::replace(mac_str.begin(), mac_str.end(), ':', ' ');
  std::array<int, 6> mac_nums;
  std::stringstream ss(mac_str);
  int i = 0;
  int tmp;

  while (ss >> std::hex >> tmp) {
    mac_nums[i++] = tmp;
  }

  if (i != 6) {
    std::cerr << "ERROR: invalid MAC address string\n";
    return 0;
  }

  unsigned long ret = 0;
  for (size_t j = 0; j < 6; j++) {
    ret += mac_nums[j] & 0xFF;
    if (j != 5) {
      ret <<= 8;
    }
  }

  return ret;
}

//iopipes constructor with initializer list
iopipes::iopipes(int mmd_handle, std::string local_ip_address, std::string local_mac_address, std::string local_netmask, int local_udp_port,
                 std::string remote_ip_address, std::string remote_mac_address, int remote_udp_port, uint64_t iopipes_dfh_offset)
                : m_mmd_handle(mmd_handle), m_local_ip_address(local_ip_address), m_local_mac_address(local_mac_address), m_local_netmask(local_netmask),
                  m_local_udp_port(local_udp_port), m_remote_ip_address(remote_ip_address), m_remote_mac_address(remote_mac_address),
                  m_remote_udp_port(remote_udp_port), mmio_num(0), m_iopipes_dfh_offset(iopipes_dfh_offset){ }

//iopipes noop destructor
iopipes::~iopipes(){}
// setting IP/gateway/netmask to PAC
// void setup_pac(unsigned long mac, const char *fpga_ip,const char *gw_ip,const char *netmask)
// void setup_pac(fpga_handle afc_handle, unsigned long mac, const std::string& fpga_ip, const std::string&  gw_ip, const std::string& netmask)
// void setup_pac()

// function to setup io pipes CSR space
void iopipes::setup_iopipes_asp(fpga_handle afc_handle)
{
  if(std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : IO-PIPES : Inside setup-iopipes_asp function");
  }
  printf("** Inside setup-iopipes_asp function **\n");
  uint64_t REG_UDPOE_BASE_ADDR       = iopipes::m_iopipes_dfh_offset;
  //uint64_t REG_UDPOE_DFH_BASE_ADDR   = REG_UDPOE_BASE_ADDR + (0x0*0x8);
  uint64_t REG_UDPOE_CSR_BASE_ADDR   = REG_UDPOE_BASE_ADDR + (0x10*0x8);
  //uint64_t CSR_SCRATCHPAD_ADDR      = REG_UDPOE_CSR_BASE_ADDR+(0x00*0x8);
  uint64_t CSR_SCRATCHPAD_ADDR           = REG_UDPOE_CSR_BASE_ADDR+(0x00*0x8);
  uint64_t CSR_UDPOE_NUM_IOPIPES_ADDR     = REG_UDPOE_CSR_BASE_ADDR+(0x01*0x8);

  uint64_t CSR_FPGA_MAC_ADR_ADDR     = REG_UDPOE_CSR_BASE_ADDR+(0x02*0x8);
  uint64_t CSR_FPGA_IP_ADR_ADDR      = REG_UDPOE_CSR_BASE_ADDR+(0x03*0x8);
  uint64_t CSR_FPGA_UDP_PORT_ADDR    = REG_UDPOE_CSR_BASE_ADDR+(0x04*0x8);
  uint64_t CSR_FPGA_NETMASK_ADDR     = REG_UDPOE_CSR_BASE_ADDR+(0x05*0x8);
  uint64_t CSR_HOST_MAC_ADR_ADDR     = REG_UDPOE_CSR_BASE_ADDR+(0x06*0x8);
  uint64_t CSR_HOST_IP_ADR_ADDR      = REG_UDPOE_CSR_BASE_ADDR+(0x07*0x8);
  uint64_t CSR_HOST_UDP_PORT_ADDR    = REG_UDPOE_CSR_BASE_ADDR+(0x08*0x8);

  uint64_t CSR_PAYLOAD_PER_PACKET_ADDR   = REG_UDPOE_CSR_BASE_ADDR+(0x09*0x8);
  uint64_t CSR_CHECKSUM_IP_ADDR          = REG_UDPOE_CSR_BASE_ADDR+(0x0a*0x8);
  //uint64_t CSR_RESET_REG_ADDR            = REG_UDPOE_CSR_BASE_ADDR+(0x09*0x8);

  uint64_t IOPIPES_CSR_START_ADDR          = REG_UDPOE_CSR_BASE_ADDR+(0x10*0x8);

  std::string local_ip_addr = m_local_ip_address;
  if(std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : IO-PIPES : local ip address= %s\n", local_ip_addr.c_str());
  }
  printf("local ip address= %s\n", local_ip_addr.c_str());
  
  uint64_t local_mac_addr = ParseMACAddress(m_local_mac_address);
  if(std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : IO-PIPES : local mac address= %ld\n", local_mac_addr);
  }
  printf("local mac address= %ld\n", local_mac_addr);

  std::string local_netmask = m_local_netmask;
  if(std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : IO-PIPES : local netmask = %s\n", local_netmask.c_str());
  }
  printf("local netmask = %s\n", local_netmask.c_str());

  uint64_t local_udp_port = (unsigned long)m_local_udp_port;
  if(std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : IO-PIPES : local udp port= %ld\n", local_udp_port);
  }
  printf("local udp port= %ld\n", local_udp_port);

  std::string remote_ip_addr = m_remote_ip_address;
  if(std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : IO-PIPES : remote ip address= %s\n", remote_ip_addr.c_str());
  }
  printf("remote ip address= %s\n", remote_ip_addr.c_str());
  
  uint64_t remote_mac_addr = ParseMACAddress(m_remote_mac_address);
  if(std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : IO-PIPES : remote mac address= %ld\n", remote_mac_addr);
  }
  printf("remote mac address= %ld\n", remote_mac_addr);

  uint64_t remote_udp_port = (unsigned long)m_remote_udp_port;
  if(std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : IO-PIPES : remote udp port= %ld\n", remote_udp_port);
  }
  printf("remote udp port= %ld\n", remote_udp_port);

  fpga_result res = FPGA_OK;
  
  // MAC reset
  if(std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : IO-PIPES : MAC reset\n");
  }
  res = fpgaWriteMMIO64(afc_handle, mmio_num, REG_UDPOE_BASE_ADDR, 0x7);
  if (res != FPGA_OK) {
    printf("error is %d, OK is %d, Exception is %d, Invalid param is %d \n",res, FPGA_OK, FPGA_EXCEPTION, FPGA_INVALID_PARAM);
    printf("Error:writing RST\n");
    exit(1);
  }
  
  /*usleep(10000);
  if ((res = fpgaWriteMMIO64(afc_handle, mmio_num, CSR_RESET_REG_ADDR, 0x3)) != FPGA_OK) {
    printf("Error:writing RST\n");
    exit(1);
  }
  
  usleep(10000);
  if ((res = fpgaWriteMMIO64(afc_handle, mmio_num, CSR_RESET_REG_ADDR, 0x0)) != FPGA_OK) {
    printf("Error:writing RST\n");
    exit(1);
  }
  usleep(5000000); // TODO: need to check if reset/wait is needed*/

  //
  // UOE register settings. These registers are not reset even after fpgaClose().
  //
  // Read MMIO CSR NUM_CHANNELS to determine how many io channels to initialize
  
  if((res = fpgaWriteMMIO64(afc_handle, mmio_num, CSR_SCRATCHPAD_ADDR, 0xf)) != FPGA_OK) {
    printf("Error:Reading number of channels CSR\n");
    exit(-1);
  }

  uint64_t number_of_channels;
  if((res = fpgaReadMMIO64(afc_handle, mmio_num, CSR_UDPOE_NUM_IOPIPES_ADDR, &number_of_channels)) != FPGA_OK) {
    printf("Error:Reading number of channels CSR\n");
    exit(-1);
  } 

  if(std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : IO-PIPES : Setting common CSRs for all IO Pipes\n");
  }

  if ((res = fpgaWriteMMIO64(afc_handle, mmio_num, CSR_FPGA_MAC_ADR_ADDR, local_mac_addr)) != FPGA_OK) {
    printf("Error:writing CSR_FPGA_MAC_ADR CSR");
    exit(1);
  }
  if ((res = fpgaWriteMMIO64(afc_handle, mmio_num, CSR_HOST_MAC_ADR_ADDR, remote_mac_addr)) != FPGA_OK) {
    printf("Error:writing CSR_HOST_MAC_ADR CSR");
    exit(1);
  }

  if ((res = fpgaWriteMMIO64(afc_handle, mmio_num, CSR_FPGA_UDP_PORT_ADDR, local_udp_port)) != FPGA_OK) {
    printf("Error:writing CSR_FPGA_UDP_PORT CSR");
    exit(1);
  }
  if ((res = fpgaWriteMMIO64(afc_handle, mmio_num, CSR_HOST_UDP_PORT_ADDR, remote_udp_port)) != FPGA_OK) {
    printf("Error:writing CSR_HOST_UDP_PORT CSR");
    exit(1);
  }
  
  //CSR_PAYLOAD_PER_PACKET_ADDR
  if ((res = fpgaWriteMMIO64(afc_handle, mmio_num, CSR_PAYLOAD_PER_PACKET_ADDR, (unsigned long) 32)) != FPGA_OK) {
    printf("Error:writing CSR_PAYLOAD_PER_PACKET CSR");
    exit(1);
  }

  //CSR CHECKSUM IP
  if ((res = fpgaWriteMMIO64(afc_handle, mmio_num, CSR_CHECKSUM_IP_ADDR, (unsigned long)CHECKSUM_IP)) != FPGA_OK) {
    printf("Error:writing CSR_CHECKSUM_IP CSR");
    exit(1);
  }
  
  /*//CSR_MISC_CTRL_REG_ADDR
  printf("Enable tx-rx loopback in UOE module.\n");
  if ((res = fpgaWriteMMIO64(afc_handle, mmio_num, CSR_MISC_CTRL_REG_ADDR, 0xFFFFFFFF)) != FPGA_OK) { 
    printf("Error:writing misc-ctrl CSR");
    exit(1);
  }*/
  
// TO do - need to clean code to write to CSRs, we dont need below calculations
// just write to CSRs what we got from environment variables or initialize to known values
  unsigned long ul_local_ip_addr = htonl(inet_addr(local_ip_addr.c_str()));
  unsigned long ul_local_netmask = htonl(inet_addr(local_netmask.c_str()));
  unsigned long ul_remote_ip_addr = htonl(inet_addr(remote_ip_addr.c_str()));
  //if ((res = fpgaWriteMMIO64(afc_handle, mmio_num, CSR_FPGA_IP_ADR_ADDR, tmp1 * 0x100000000 + (tmp2 & 0xffffffff))) != FPGA_OK) {
  if ((res = fpgaWriteMMIO64(afc_handle, mmio_num, CSR_FPGA_IP_ADR_ADDR, ul_local_ip_addr)) != FPGA_OK) { 
    printf("Error:writing CSR_FPGA_IP_ADR CSR");
    exit(1);
  }
  //if ((res = fpgaWriteMMIO64(afc_handle, mmio_num, CSR_HOST_IP_ADR_ADDR, tmp1 * 0x100000000 + (tmp2 & 0xffffffff))) != FPGA_OK) {
  if ((res = fpgaWriteMMIO64(afc_handle, mmio_num, CSR_HOST_IP_ADR_ADDR, ul_remote_ip_addr)) != FPGA_OK) { 
    printf("Error:writing CSR_HOST_IP_ADR CSR");
    exit(1);
  }
  //unsigned long tmp4 = htonl(inet_addr(local_netmask.c_str()));
  if ((res = fpgaWriteMMIO64(afc_handle, mmio_num, CSR_FPGA_NETMASK_ADDR, ul_local_netmask)) != FPGA_OK) {
    printf("Error:writing CSR_FPGA_NETMASK CSR");
    exit(1);
  }

///
  if(std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : IO-PIPES : Setting CSRs specific for each IO Pipe\n");
  }
  int i = 0x00;
  for(uint64_t loop=0; loop<number_of_channels; loop++) { 
    printf("Looping on channel %ld, Writing CSRs for channel %ld\n", loop, loop); 
    printf("Writing CSR_RESET_REG_ADDR for IO Pipe %ld\n", loop);
    if ((res = fpgaWriteMMIO64(afc_handle, mmio_num, (IOPIPES_CSR_START_ADDR + (++i*0x8)), 0x1)) != FPGA_OK) {
      printf("Error:writing CSR_RESET_REG CSR");
      exit(1);
    }
    i = i+2;
    printf("Writing CSR_MISC_CTRL_REG for IO Pipe %ld\n", loop);
    if ((res = fpgaWriteMMIO64(afc_handle, mmio_num, (IOPIPES_CSR_START_ADDR + (i*0x8)), 0xFFFFFFFF)) != FPGA_OK) {
      printf("Error:writing CSR_MISC_CTRL_REG CSR");
      exit(1);
    }
    i = i + 13;
  }

  // Read CSRs
  uint64_t mmio_read;
  if ((res = fpgaReadMMIO64(afc_handle, mmio_num, CSR_SCRATCHPAD_ADDR, &mmio_read)) != FPGA_OK) {
    printf("Error reading CSR_SCRATCHPAD_ADDR\n");
    exit(1);
  }
  if(std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : IO-PIPES : Read CSR: Scratchpad:%ld\n", mmio_read);
  }
  printf("Read CSR: Scratchpad:%ld\n", mmio_read);

  if ((res = fpgaReadMMIO64(afc_handle, mmio_num, CSR_UDPOE_NUM_IOPIPES_ADDR, &mmio_read)) != FPGA_OK) {
    printf("Error reading CSR_UDPOE_NUM_IOPIPES_ADDR\n");
    exit(1);
  }
  printf("Read CSR: Number of IO Channels/Pipes:%ld\n", mmio_read);

  if ((res = fpgaReadMMIO64(afc_handle, mmio_num, CSR_FPGA_MAC_ADR_ADDR, &mmio_read)) != FPGA_OK) {
    printf("Error reading CSR_FPGA_MAC_ADR_ADDR\n");
    exit(1);
  }
  printf("Read CSR: FPGA_MAC_ADDR:%ld\n", mmio_read);

  if ((res = fpgaReadMMIO64(afc_handle, mmio_num, CSR_FPGA_IP_ADR_ADDR, &mmio_read)) != FPGA_OK) {
    printf("Error reading CSR_FPGA_IP_ADR_ADDR\n");
    exit(1);
  }
  printf("Read CSR: FPGA_IP_ADDR:%ld\n", mmio_read);

  if ((res = fpgaReadMMIO64(afc_handle, mmio_num, CSR_FPGA_UDP_PORT_ADDR, &mmio_read)) != FPGA_OK) {
    printf("Error reading CSR_FPGA_UDP_PORT_ADDR\n");
    exit(1);
  }   
  printf("Read CSR: FPGA_UDP_PORT:%ld\n", mmio_read);

  if ((res = fpgaReadMMIO64(afc_handle, mmio_num, CSR_FPGA_NETMASK_ADDR, &mmio_read)) != FPGA_OK) {
    printf("Error reading CSR_FPGA_NETMASK_ADDR\n");
    exit(1); 
  }
  printf("Read CSR: FPGA_NETMASK:%ld\n", mmio_read);

  if ((res = fpgaReadMMIO64(afc_handle, mmio_num, CSR_HOST_MAC_ADR_ADDR, &mmio_read)) != FPGA_OK) {
    printf("Error reading CSR_HOST_MAC_ADR_ADDR\n");
    exit(1); 
  }
  printf("Read CSR: HOST_MAC_ADDR:%ld\n", mmio_read);

  if ((res = fpgaReadMMIO64(afc_handle, mmio_num, CSR_HOST_IP_ADR_ADDR, &mmio_read)) != FPGA_OK) {
    printf("Error reading CSR_HOST_IP_ADR_ADDR\n");
    exit(1); 
  }
  printf("Read CSR: HOST_IP_ADDR:%ld\n", mmio_read);

  if ((res = fpgaReadMMIO64(afc_handle, mmio_num, CSR_HOST_UDP_PORT_ADDR, &mmio_read)) != FPGA_OK) {
    printf("Error reading CSR_HOST_UDP_PORT_ADDR\n");
    exit(1); 
  }
  printf("Read CSR: HOST_UDP_PORT:%ld\n", mmio_read);

  if ((res = fpgaReadMMIO64(afc_handle, mmio_num, CSR_PAYLOAD_PER_PACKET_ADDR, &mmio_read)) != FPGA_OK) {
    printf("Error reading CSR_PAYLOAD_PER_PACKET_ADDR\n");
    exit(1); 
  }
  printf("Read CSR: HOST_UDP_PORT:%ld\n", mmio_read);

  if ((res = fpgaReadMMIO64(afc_handle, mmio_num, CSR_CHECKSUM_IP_ADDR , &mmio_read)) != FPGA_OK) {
    printf("Error reading CSR_CHECKSUM_IP_ADDR\n");
    exit(1);  
  }
  printf("Read CSR: HOST_UDP_PORT:%ld\n", mmio_read);

  i = 0x00;
  for(uint64_t loop=0; loop<number_of_channels; loop++) { 
    printf("Looping on channel %ld, Reading CSRs for channel %ld\n", loop, loop); 
    printf("Reading CSR_IOPIPE_INFO_REG_ADDR for IO pipe %ld\n", loop);
    if ((res = fpgaReadMMIO64(afc_handle, mmio_num, (IOPIPES_CSR_START_ADDR + (i++*0x8)), &mmio_read)) != FPGA_OK) {
      printf("Error:reading CSR_IOPIPE_INFO_REG_ADDR");
      exit(1);
    }
    printf("Read CSR_IOPIPE_INFO_REG_ADDR:%ld\n", mmio_read);

    printf("Reading CSR_RESET_REG_ADDR for IO pipe %ld\n", loop);
    if ((res = fpgaReadMMIO64(afc_handle, mmio_num, (IOPIPES_CSR_START_ADDR + (i++*0x8)), &mmio_read)) != FPGA_OK) {
      printf("Error:reading CSR_RESET_REG_ADDR");
      exit(1);
    }
    printf("Read CSR_RESET_REG_ADDR:%ld\n", mmio_read);

    printf("Reading CSR_STATUS_REG_ADDR for IO Pipe %ld\n", loop);
    if ((res = fpgaReadMMIO64(afc_handle, mmio_num, (IOPIPES_CSR_START_ADDR + (i++*0x8)), &mmio_read)) != FPGA_OK) {
      printf("Error:reading CSR_STATUS_REG_ADDR");
      exit(1);
    }
    printf("Read CSR_STATUS_REG_ADDR:%ld\n", mmio_read);

    printf("Reading CSR_MISC_CTRL_REG_ADDR for IO Pipe %ld\n", loop);
    if ((res = fpgaReadMMIO64(afc_handle, mmio_num, (IOPIPES_CSR_START_ADDR + (i++*0x8)), &mmio_read)) != FPGA_OK) {
      printf("Error:reading CSR_MISC_CTRL_REG_ADDR");
      exit(1);
    }
    printf("Read CSR_MISC_CTRL_REG_ADDR:%ld\n", mmio_read);

    printf("Reading CSR_TX_STATUS_REG_ADDR for IO Pipe %ld\n", loop);
    if ((res = fpgaReadMMIO64(afc_handle, mmio_num, (IOPIPES_CSR_START_ADDR + (i++*0x8)), &mmio_read)) != FPGA_OK) {
      printf("Error:reading CSR_TX_STATUS_REG_ADDR");
      exit(1);
    }
    printf("Read CSR_TX_STATUS_REG_ADDR:%ld\n", mmio_read);

    printf("Reading CSR_RX_STATUS_REG_ADDR for IO Pipe %ld\n", loop);
    if ((res = fpgaReadMMIO64(afc_handle, mmio_num, (IOPIPES_CSR_START_ADDR + (i++*0x8)), &mmio_read)) != FPGA_OK) {
      printf("Error:reading CSR_RX_STATUS_REG_ADDR");
      exit(1);
    }
    printf("Read CSR_RX_STATUS_REG_ADDR:%ld\n", mmio_read);
  }

// do we need to read or write to below IO Pipes specific CSRs 
/*#define CSR_PAYLOAD_PER_PACKET_ADDR   (REG_UDPOE_CSR_BASE_ADDR+(0x09*0x8))
#define CSR_CHECKSUM_IP_ADDR   (REG_UDPOE_CSR_BASE_ADDR+(0x0A*0x8))
#define CSR_STATUS_REG_ADDR     (REG_UDPOE_CSR_BASE_ADDR+(0x0B*0x8))
#define CSR_MISC_CTRL_REG_ADDR     (REG_UDPOE_CSR_BASE_ADDR+(0x0C*0x8))*/
  
/*int i = 0x00;
for(uint64_t loop=0; loop<=number_of_channels; loop++) { 
    if ((res = fpgaWriteMMIO64(afc_handle, mmio_num, (PIPES_CSR_START_ADDR+(++i*0x8)), 0x1)) != FPGA_OK) {
    printf("Error:writing CSR");
    exit(1);
  }
  if ((res = fpgaWriteMMIO64(afc_handle, mmio_num, (PIPES_CSR_START_ADDR+(++i*0x8)), 0xFFFFFFFF)) != FPGA_OK) {
    printf("Error:writing CSR");
    exit(1);
  }
}*/

}
