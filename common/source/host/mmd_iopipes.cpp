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

#include <cassert>
#include <cstdlib>
#include <cstring>
#include <sys/mman.h>
#include <algorithm>
#include <sstream>

#include <chrono>
#include <iostream>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <netinet/ether.h>

#include "mmd_device.h"
#include "mmd_iopipes.h"

namespace intel_opae_mmd {
#define INVALID_MAC 0xffffffffffffffffULL
#define CSR_ADDRESS_MAP_JUMP_1 2
#define CSR_ADDRESS_MAP_JUMP_2 13

//base address is 0x20800
//dfh base offset is 0x0
//udp offload engine csrs offset is 0x10
#define CHECKSUM_IP     43369
uint64_t ParseMACAddress(std::string addr)
{
    uint64_t res = INVALID_MAC;
    struct ether_addr *eth = ether_aton(addr.c_str());
  
    if (eth) {
      res = 0ULL;
      memcpy(&res, eth->ether_addr_octet, sizeof(eth->ether_addr_octet));
    }

    return res;
}

//iopipes constructor with initializer list
iopipes::iopipes(int mmd_handle, std::string local_ip_address, std::string local_mac_address, std::string local_netmask, int local_udp_port,
                 std::string remote_ip_address, std::string remote_mac_address, int remote_udp_port, uint64_t iopipes_dfh_offset)
                : mmd_handle_(mmd_handle), local_ip_address_(local_ip_address), local_mac_address_(local_mac_address), local_netmask_(local_netmask),
                  local_udp_port_(local_udp_port), remote_ip_address_(remote_ip_address), remote_mac_address_(remote_mac_address),
                  remote_udp_port_(remote_udp_port), mmio_num_(0), iopipes_dfh_offset_(iopipes_dfh_offset){ }

//iopipes noop destructor
iopipes::~iopipes(){}
// setting IP/gateway/netmask to PAC
// void setup_pac(unsigned long mac, const char *fpga_ip,const char *gw_ip,const char *netmask)
// void setup_pac(fpga_handle afc_handle, unsigned long mac, const std::string& fpga_ip, const std::string&  gw_ip, const std::string& netmask)
// void setup_pac()

// function to setup io pipes CSR space
bool iopipes::setup_iopipes_asp(fpga_handle afc_handle)
{
  if(std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : IO-PIPES : Inside setup-iopipes_asp function");
  }
  printf("** Inside setup-iopipes_asp function **\n");
  const uint64_t REG_UDPOE_BASE_ADDR       = iopipes::iopipes_dfh_offset_;
  const uint64_t REG_UDPOE_CSR_BASE_ADDR   = REG_UDPOE_BASE_ADDR + (0x10*0x8);
  const uint64_t CSR_SCRATCHPAD_ADDR           = REG_UDPOE_CSR_BASE_ADDR+(0x00*0x8);
  const uint64_t CSR_UDPOE_NUM_IOPIPES_ADDR     = REG_UDPOE_CSR_BASE_ADDR+(0x01*0x8);

  const uint64_t CSR_FPGA_MAC_ADR_ADDR     = REG_UDPOE_CSR_BASE_ADDR+(0x02*0x8);
  const uint64_t CSR_FPGA_IP_ADR_ADDR      = REG_UDPOE_CSR_BASE_ADDR+(0x03*0x8);
  const uint64_t CSR_FPGA_UDP_PORT_ADDR    = REG_UDPOE_CSR_BASE_ADDR+(0x04*0x8);
  const uint64_t CSR_FPGA_NETMASK_ADDR     = REG_UDPOE_CSR_BASE_ADDR+(0x05*0x8);
  const uint64_t CSR_HOST_MAC_ADR_ADDR     = REG_UDPOE_CSR_BASE_ADDR+(0x06*0x8);
  const uint64_t CSR_HOST_IP_ADR_ADDR      = REG_UDPOE_CSR_BASE_ADDR+(0x07*0x8);
  const uint64_t CSR_HOST_UDP_PORT_ADDR    = REG_UDPOE_CSR_BASE_ADDR+(0x08*0x8);

  const uint64_t CSR_PAYLOAD_PER_PACKET_ADDR   = REG_UDPOE_CSR_BASE_ADDR+(0x09*0x8);
  const uint64_t CSR_CHECKSUM_IP_ADDR          = REG_UDPOE_CSR_BASE_ADDR+(0x0a*0x8);

  const uint64_t IOPIPES_CSR_START_ADDR          = REG_UDPOE_CSR_BASE_ADDR+(0x10*0x8);

  std::string local_ip_addr = local_ip_address_;

  if(std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("local ip address= %s\n", local_ip_addr.c_str());
  }
 
  uint64_t local_mac_addr = ParseMACAddress(local_mac_address_);
  if(local_mac_addr == 0xffffffffffffffffULL){
    printf("Invalid Local MAC address. Please provide MAC address in 'aa:bb:cc:dd:ee:ff' format\n");
    return false;
  } else{
    if(std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("local mac address= %ld\n", local_mac_addr);
    }
  }

  std::string local_netmask = local_netmask_;
  if(std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("local netmask = %s\n", local_netmask.c_str());
  }

  uint64_t local_udp_port = (unsigned long)local_udp_port_;
  if(std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("local udp port= %ld\n", local_udp_port);
  }

  std::string remote_ip_addr = remote_ip_address_;
  if(std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("remote ip address= %s\n", remote_ip_addr.c_str());
  }
 
  uint64_t remote_mac_addr = ParseMACAddress(remote_mac_address_); 
  if(remote_mac_addr == 0xffffffffffffffffULL){
    printf("Invalid Remote MAC address. Please provide MAC address in 'aa:bb:cc:dd:ee:ff' format\n");
    return false;
  } else{
    if(std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("remote mac address= %ld\n", remote_mac_addr);
    }
  }

  uint64_t remote_udp_port = (unsigned long)remote_udp_port_;
  if(std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("remote udp port= %ld\n", remote_udp_port);
  }

  if(std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : IO-PIPES : \n local ip address= %s\n local mac address= %ld\n" 
               "local netmask = %s\n local udp port= %ld\n remote ip address= %s\n" 
               "remote mac address= %ld\n remote udp port= %ld\n", local_ip_addr.c_str(), local_mac_addr,
               local_netmask.c_str(), local_udp_port, remote_ip_addr.c_str(), remote_mac_addr, remote_udp_port);
  }
 
  fpga_result res = FPGA_OK;
  
  // MAC reset
  if(std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : IO-PIPES : MAC reset\n");
  }
  res = fpgaWriteMMIO64(afc_handle, mmio_num_, REG_UDPOE_BASE_ADDR, 0x7);
  if (res != FPGA_OK) {
    printf("error is %d, OK is %d, Exception is %d, Invalid param is %d \n",res, FPGA_OK, FPGA_EXCEPTION, FPGA_INVALID_PARAM);
    printf("Error:writing RST\n");
    printf("%s \n",fpgaErrStr(res));
    return false;;
  }
  
  if((res = fpgaWriteMMIO64(afc_handle, mmio_num_, CSR_SCRATCHPAD_ADDR, 0xf)) != FPGA_OK) {
    printf("Error:Reading number of channels CSR\n");
    printf("%s \n",fpgaErrStr(res));
    return false;
  }

// Read MMIO CSR NUM_CHANNELS to determine how many io channels to initialize
  uint64_t number_of_channels;
  if((res = fpgaReadMMIO64(afc_handle, mmio_num_, CSR_UDPOE_NUM_IOPIPES_ADDR, &number_of_channels)) != FPGA_OK) {
    printf("Error:Reading number of channels CSR\n");
    printf("%s \n",fpgaErrStr(res));
    return false;
  } 
  if(std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : IO-PIPES : Reading number of channels CSR : Number of Channels : %ld\n", number_of_channels);
  }

// Setting CSRs needed for UDP offload Engine
// Setting CSRs which will be common on all pipes, if we have instantiated multiple pipes
  if(std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : IO-PIPES : Setting common CSRs for all IO Pipes\n");
  }

  if ((res = fpgaWriteMMIO64(afc_handle, mmio_num_, CSR_FPGA_MAC_ADR_ADDR, local_mac_addr)) != FPGA_OK) {
    printf("Error:writing CSR_FPGA_MAC_ADR CSR");
    printf("%s \n",fpgaErrStr(res));
    return false;
  }
  if ((res = fpgaWriteMMIO64(afc_handle, mmio_num_, CSR_HOST_MAC_ADR_ADDR, remote_mac_addr)) != FPGA_OK) {
    printf("Error:writing CSR_HOST_MAC_ADR CSR");
    printf("%s \n",fpgaErrStr(res));
    return false;
  }

  if ((res = fpgaWriteMMIO64(afc_handle, mmio_num_, CSR_FPGA_UDP_PORT_ADDR, local_udp_port)) != FPGA_OK) {
    printf("Error:writing CSR_FPGA_UDP_PORT CSR");
    printf("%s \n",fpgaErrStr(res));
    return false;
  }
  if ((res = fpgaWriteMMIO64(afc_handle, mmio_num_, CSR_HOST_UDP_PORT_ADDR, remote_udp_port)) != FPGA_OK) {
    printf("Error:writing CSR_HOST_UDP_PORT CSR");
    printf("%s \n",fpgaErrStr(res));
    return false;
  }
  
  //CSR_PAYLOAD_PER_PACKET_ADDR
  if ((res = fpgaWriteMMIO64(afc_handle, mmio_num_, CSR_PAYLOAD_PER_PACKET_ADDR, (unsigned long) 32)) != FPGA_OK) {
    printf("Error:writing CSR_PAYLOAD_PER_PACKET CSR");
    printf("%s \n",fpgaErrStr(res));
    return false;
  }

  //CSR CHECKSUM IP
  if ((res = fpgaWriteMMIO64(afc_handle, mmio_num_, CSR_CHECKSUM_IP_ADDR, (unsigned long)CHECKSUM_IP)) != FPGA_OK) {
    printf("Error:writing CSR_CHECKSUM_IP CSR");
    printf("%s \n",fpgaErrStr(res));
    return false;
  }
  
  
// TO do - need to clean code to write to CSRs, we dont need below calculations
// just write to CSRs what we got from environment variables or initialize to known values
  unsigned long ul_local_ip_addr = htonl(inet_addr(local_ip_addr.c_str()));
  unsigned long ul_local_netmask = htonl(inet_addr(local_netmask.c_str()));
  unsigned long ul_remote_ip_addr = htonl(inet_addr(remote_ip_addr.c_str()));
  //if ((res = fpgaWriteMMIO64(afc_handle, mmio_num, CSR_FPGA_IP_ADR_ADDR, tmp1 * 0x100000000 + (tmp2 & 0xffffffff))) != FPGA_OK) {
  if ((res = fpgaWriteMMIO64(afc_handle, mmio_num_, CSR_FPGA_IP_ADR_ADDR, ul_local_ip_addr)) != FPGA_OK) { 
    printf("Error:writing CSR_FPGA_IP_ADR CSR");
    printf("%s \n",fpgaErrStr(res));
    return false;
  }
  //if ((res = fpgaWriteMMIO64(afc_handle, mmio_num, CSR_HOST_IP_ADR_ADDR, tmp1 * 0x100000000 + (tmp2 & 0xffffffff))) != FPGA_OK) {
  if ((res = fpgaWriteMMIO64(afc_handle, mmio_num_, CSR_HOST_IP_ADR_ADDR, ul_remote_ip_addr)) != FPGA_OK) { 
    printf("Error:writing CSR_HOST_IP_ADR CSR");
    printf("%s \n",fpgaErrStr(res));
    return false;
  }
  //unsigned long tmp4 = htonl(inet_addr(local_netmask.c_str()));
  if ((res = fpgaWriteMMIO64(afc_handle, mmio_num_, CSR_FPGA_NETMASK_ADDR, ul_local_netmask)) != FPGA_OK) {
    printf("Error:writing CSR_FPGA_NETMASK CSR");
    printf("%s \n",fpgaErrStr(res));
    return false;
  }

// Setting CSRs for each IO Pipe instantiated 
  if(std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : IO-PIPES : Setting CSRs specific for each IO Pipe\n");
  }
  int i = 0x00;
  for(uint64_t loop=0; loop<number_of_channels; loop++) { 
    printf("Looping on channel %ld, Writing CSRs for channel %ld\n", loop, loop); 
    printf("Writing CSR_RESET_REG_ADDR for IO Pipe %ld\n", loop);
    if ((res = fpgaWriteMMIO64(afc_handle, mmio_num_, (IOPIPES_CSR_START_ADDR + (++i*0x8)), 0x1)) != FPGA_OK) {
      printf("Error:writing CSR_RESET_REG CSR");
      printf("%s \n",fpgaErrStr(res));
      return false;
    }
    i = i+CSR_ADDRESS_MAP_JUMP_1;
    printf("Writing CSR_MISC_CTRL_REG for IO Pipe %ld\n", loop);
    if ((res = fpgaWriteMMIO64(afc_handle, mmio_num_, (IOPIPES_CSR_START_ADDR + (i*0x8)), 0xFFFFFFFF)) != FPGA_OK) {
      printf("Error:writing CSR_MISC_CTRL_REG CSR");
      printf("%s \n",fpgaErrStr(res));
      return false;
    }
    i = i + CSR_ADDRESS_MAP_JUMP_2;
  }

  // Read CSRs to help in debug
  // Reading CSRs common to all pipes
  uint64_t debug_scratchpad_csr, debug_num_iopipes_csr, debug_fpga_mac_addr_csr, debug_fpga_ip_addr_csr,
           debug_fpga_udp_port_csr, debug_fpga_netmask_csr, debug_host_mac_addr_csr, debug_host_ip_addr_csr, 
           debug_host_udp_port_csr, debug_payload_per_packet_csr, debug_checksum_ip_csr;

  if ((res = fpgaReadMMIO64(afc_handle, mmio_num_, CSR_SCRATCHPAD_ADDR, &debug_scratchpad_csr)) != FPGA_OK) {
    printf("Error reading CSR_SCRATCHPAD_ADDR\n");
    printf("%s \n",fpgaErrStr(res));
    return false;
  }
  if(std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("Read CSR: Scratchpad:%ld\n", debug_scratchpad_csr);
  }

  if ((res = fpgaReadMMIO64(afc_handle, mmio_num_, CSR_UDPOE_NUM_IOPIPES_ADDR, &debug_num_iopipes_csr)) != FPGA_OK) {
    printf("Error reading CSR_UDPOE_NUM_IOPIPES_ADDR\n");
    printf("%s \n",fpgaErrStr(res));
    return false;
  }
  if(std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("Read CSR: Number of IO Channels/Pipes:%ld\n", debug_num_iopipes_csr);
  }

  if ((res = fpgaReadMMIO64(afc_handle, mmio_num_, CSR_FPGA_MAC_ADR_ADDR, &debug_fpga_mac_addr_csr)) != FPGA_OK) {
    printf("Error reading CSR_FPGA_MAC_ADR_ADDR\n");
    printf("%s \n",fpgaErrStr(res));
    return false;
  }
  if(std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("Read CSR: FPGA_MAC_ADDR:%ld\n", debug_fpga_mac_addr_csr);
  }

  if ((res = fpgaReadMMIO64(afc_handle, mmio_num_, CSR_FPGA_IP_ADR_ADDR, &debug_fpga_ip_addr_csr)) != FPGA_OK) {
    printf("Error reading CSR_FPGA_IP_ADR_ADDR\n");
    printf("%s \n",fpgaErrStr(res));
    return false;
  }
  if(std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("Read CSR: FPGA_IP_ADDR:%ld\n", debug_fpga_ip_addr_csr);
  }

  if ((res = fpgaReadMMIO64(afc_handle, mmio_num_, CSR_FPGA_UDP_PORT_ADDR, &debug_fpga_udp_port_csr)) != FPGA_OK) {
    printf("Error reading CSR_FPGA_UDP_PORT_ADDR\n");
    printf("%s \n",fpgaErrStr(res));
    return false;
  }   
  if(std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("Read CSR: FPGA_UDP_PORT:%ld\n", debug_fpga_udp_port_csr);
  }

  if ((res = fpgaReadMMIO64(afc_handle, mmio_num_, CSR_FPGA_NETMASK_ADDR, &debug_fpga_netmask_csr)) != FPGA_OK) {
    printf("Error reading CSR_FPGA_NETMASK_ADDR\n");
    printf("%s \n",fpgaErrStr(res));
    return false;
  }
  if(std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("Read CSR: FPGA_NETMASK:%ld\n", debug_fpga_netmask_csr);
  }

  if ((res = fpgaReadMMIO64(afc_handle, mmio_num_, CSR_HOST_MAC_ADR_ADDR, &debug_host_mac_addr_csr)) != FPGA_OK) {
    printf("Error reading CSR_HOST_MAC_ADR_ADDR\n");
    printf("%s \n",fpgaErrStr(res));
    return false;
  }
  if(std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("Read CSR: HOST_MAC_ADDR:%ld\n", debug_host_mac_addr_csr);
  }

  if ((res = fpgaReadMMIO64(afc_handle, mmio_num_, CSR_HOST_IP_ADR_ADDR, &debug_host_ip_addr_csr)) != FPGA_OK) {
    printf("Error reading CSR_HOST_IP_ADR_ADDR\n");
    printf("%s \n",fpgaErrStr(res));
    return false;
  }
  if(std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("Read CSR: HOST_IP_ADDR:%ld\n", debug_host_ip_addr_csr);
  }

  if ((res = fpgaReadMMIO64(afc_handle, mmio_num_, CSR_HOST_UDP_PORT_ADDR, &debug_host_udp_port_csr)) != FPGA_OK) {
    printf("Error reading CSR_HOST_UDP_PORT_ADDR\n");
    printf("%s \n",fpgaErrStr(res));
    return false;
  }
  if(std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("Read CSR: HOST_UDP_PORT:%ld\n", debug_host_udp_port_csr);
  }

  if ((res = fpgaReadMMIO64(afc_handle, mmio_num_, CSR_PAYLOAD_PER_PACKET_ADDR, &debug_payload_per_packet_csr)) != FPGA_OK) {
    printf("Error reading CSR_PAYLOAD_PER_PACKET_ADDR\n");
    printf("%s \n",fpgaErrStr(res));
    return false;
  }
  if(std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("Read CSR: PAYLOAD_PER_PACKET:%ld\n", debug_payload_per_packet_csr);
  }

  if ((res = fpgaReadMMIO64(afc_handle, mmio_num_, CSR_CHECKSUM_IP_ADDR , &debug_checksum_ip_csr)) != FPGA_OK) {
    printf("Error reading CSR_CHECKSUM_IP_ADDR\n");
    printf("%s \n",fpgaErrStr(res));
    return false; 
  }
  if(std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("Read CSR: CHECKSUM_IP:%ld\n", debug_checksum_ip_csr);
  }

  if(std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : IO-PIPES : \n CSR: Scratchpad:%ld\n CSR: Number of IO Channels/Pipes:%ld\n"
              "CSR: FPGA_MAC_ADDR:%ld\n CSR: FPGA_IP_ADDR:%ld\n CSR: FPGA_UDP_PORT:%ld\n"
              "CSR: FPGA_NETMASK:%ld\n CSR: HOST_MAC_ADDR:%ld\n CSR: HOST_IP_ADDR:%ld\n"
              "CSR: HOST_UDP_PORT:%ld\n CSR: PAYLOAD_PER_PACKET:%ld\n CSR: CHECKSUM_IP:%ld\n", debug_scratchpad_csr, 
              debug_num_iopipes_csr, debug_fpga_mac_addr_csr, debug_fpga_ip_addr_csr, debug_fpga_udp_port_csr,
              debug_fpga_netmask_csr, debug_host_mac_addr_csr, debug_host_ip_addr_csr, debug_host_udp_port_csr,
              debug_payload_per_packet_csr, debug_checksum_ip_csr);
  }

//Reading CSRs for each pipe instantiated
  uint64_t debug_iopipe_info_csr, debug_reset_csr, 
           debug_status_csr, debug_misc_ctrl_csr,
           debug_tx_status_csr, debug_rx_status_csr;
  i = 0x00;
  for(uint64_t loop=0; loop<number_of_channels; loop++) { 
    if(std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("Looping on channel %ld, Reading CSRs for channel %ld\n", loop, loop);
      DEBUG_LOG("Reading CSR_IOPIPE_INFO_REG_ADDR for IO pipe %ld\n", loop);
    }

    if ((res = fpgaReadMMIO64(afc_handle, mmio_num_, (IOPIPES_CSR_START_ADDR + (i++*0x8)), &debug_iopipe_info_csr)) != FPGA_OK) {
      printf("Error:reading CSR_IOPIPE_INFO_REG_ADDR");
      printf("%s \n",fpgaErrStr(res));
      return false;
    }
    if(std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("Read CSR_IOPIPE_INFO_REG_ADDR:%ld\n", debug_iopipe_info_csr);
    }

    if(std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("Reading CSR_RESET_REG_ADDR for IO pipe %ld\n", loop);
    }
    if ((res = fpgaReadMMIO64(afc_handle, mmio_num_, (IOPIPES_CSR_START_ADDR + (i++*0x8)), &debug_reset_csr)) != FPGA_OK) {
      printf("Error:reading CSR_RESET_REG_ADDR");
      printf("%s \n",fpgaErrStr(res));
      return false;
    }

    if(std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("Read CSR_RESET_REG_ADDR:%ld\n", debug_reset_csr);
    }

    if(std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("Reading CSR_STATUS_REG_ADDR for IO Pipe %ld\n", loop);
    }
    if ((res = fpgaReadMMIO64(afc_handle, mmio_num_, (IOPIPES_CSR_START_ADDR + (i++*0x8)), &debug_status_csr)) != FPGA_OK) {
      printf("Error:reading CSR_STATUS_REG_ADDR");
      printf("%s \n",fpgaErrStr(res));
      return false;
    }

    if(std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("Read CSR_STATUS_REG_ADDR:%ld\n", debug_status_csr);
    }

    if(std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("Reading CSR_MISC_CTRL_REG_ADDR for IO Pipe %ld\n", loop);
    }
    if ((res = fpgaReadMMIO64(afc_handle, mmio_num_, (IOPIPES_CSR_START_ADDR + (i++*0x8)), &debug_misc_ctrl_csr)) != FPGA_OK) {
      printf("Error:reading CSR_MISC_CTRL_REG_ADDR");
      printf("%s \n",fpgaErrStr(res));
      return false;
    }

    if(std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("Read CSR_MISC_CTRL_REG_ADDR:%ld\n", debug_misc_ctrl_csr);
    }

    if(std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("Reading CSR_TX_STATUS_REG_ADDR for IO Pipe %ld\n", loop);
    }

    if ((res = fpgaReadMMIO64(afc_handle, mmio_num_, (IOPIPES_CSR_START_ADDR + (i++*0x8)), &debug_tx_status_csr)) != FPGA_OK) {
      printf("Error:reading CSR_TX_STATUS_REG_ADDR");
      printf("%s \n",fpgaErrStr(res));
      return false;
    }
    if(std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("Read CSR_TX_STATUS_REG_ADDR:%ld\n", debug_tx_status_csr);
    }

    if(std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("Reading CSR_RX_STATUS_REG_ADDR for IO Pipe %ld\n", loop);
    }
    if ((res = fpgaReadMMIO64(afc_handle, mmio_num_, (IOPIPES_CSR_START_ADDR + (i++*0x8)), &debug_rx_status_csr)) != FPGA_OK) {
      printf("Error:reading CSR_RX_STATUS_REG_ADDR");
      printf("%s \n",fpgaErrStr(res));
      return false;
    }
    if(std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("Read CSR_RX_STATUS_REG_ADDR:%ld\n", debug_rx_status_csr);
    }

    if(std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : IO-PIPES : \n CSR_IOPIPE_INFO_REG_ADDR:%ld\n CSR_RESET_REG_ADDR:%ld\n"
              "CSR_STATUS_REG_ADDR:%ld\n CSR_MISC_CTRL_REG_ADDR:%ld\n CSR_TX_STATUS_REG_ADDR:%ld\n"
              "CSR_RX_STATUS_REG_ADDR:%ld\n", debug_iopipe_info_csr, debug_reset_csr, debug_status_csr,
              debug_misc_ctrl_csr, debug_tx_status_csr, debug_rx_status_csr);
    }
  }
  return true;
}
}// namespace intel_opae_mmd
