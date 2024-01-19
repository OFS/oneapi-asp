// Copyright 2022 Intel Corporation
// SPDX-License-Identifier: MIT

#include <assert.h>
#include <numa.h>

#include <fstream>
#include <iomanip>
#include <iostream>
#include <limits>
#include <sstream>
#include <unistd.h>
#include <string.h>
#include "mmd_device.h"
#include "fpgaconf.h"
#include "mmd_iopipes.h"
#include "mmd.h"

// TODO: better encapsulation of afu_bbb_util functions
#include "afu_bbb_util.h"

#define MMD_COPY_BUFFER_SIZE (2 * 1024 * 1024)

using namespace intel_opae_mmd;

int Device::next_mmd_handle{1};

std::string Device::get_board_name(std::string prefix, uint64_t obj_id) {
  std::ostringstream stream;
  stream << prefix << std::setbase(16) << obj_id;
  return stream.str();
}

/**
 * The Device object is created for each device/board opened and
 * it has methods to interact with fpga device. 
 * The entry point for Device is in DeviceMapManager Class 
 * which maintains mapping between device names and handles.
 * Device Object is foundation for interacting with device. 
 */
Device::Device(uint64_t obj_id)
    : fpga_obj_id(obj_id), kernel_interrupt_thread(NULL), event_update(NULL),
      event_update_user_data(NULL), enable_set_numa(false),
      fme_sysfs_temp_initialized(false), bus(0), device(0), function(0),
      afu_initialized(false), asp_initialized(false), mmio_is_mapped(false),
      port_handle(NULL), filter(NULL), port_token(NULL),
      mmio_token(NULL), mmio_handle(NULL),
      filter_fme(NULL), fme_token(NULL), guid(), ddr_offset(0), mpf_mmio_offset(0),
      dma_ch0_dfh_offset(0), dma_ch1_dfh_offset(0), iopipes_dfh_offset(0),
      dma_host_to_fpga(NULL), dma_fpga_to_host(NULL), io_pipes(NULL), mmd_copy_buffer(NULL) {
  // Note that this constructor is not thread-safe because next_mmd_handle
  // is shared between all class instances
  if(std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : Constructing Device object\n");
  }
  mmd_handle = next_mmd_handle;
  if (next_mmd_handle == std::numeric_limits<int>::max())
    next_mmd_handle = 1;
  else
    next_mmd_handle++;

  int pma_res = posix_memalign((void **)&mmd_copy_buffer, 64, MMD_COPY_BUFFER_SIZE);
  if (pma_res) {
    throw std::runtime_error(std::string("posix_memalign failed for mmd_copy_buffer")
    + std::string(strerror(pma_res)));
  }

  /** Initializing filter list for DFL and VFIO
   *  filters are used in OPAE API fpgaPropertiesSetInterface()
   *  which helps in enumeration
   */
  fpga_interface filter_list[2] {FPGA_IFC_DFL, FPGA_IFC_SIM_DFL};
  fpga_interface filter_vfio_list[2] {FPGA_IFC_VFIO, FPGA_IFC_SIM_VFIO};
  fpga_result res = FPGA_OK;
  uint32_t num_matches;
  uint32_t i;
  fpga_token *tokens = nullptr;
  fpga_guid svm_guid;
  fpga_properties props = nullptr;

  board_type=BOARD_TYPE;
  if(std::getenv("MMD_ENABLE_DEBUG")){
    if(board_type == 1){
      DEBUG_LOG("DEBUG LOG : board_type = %d , n6001 board\n", board_type);
    }else{
      DEBUG_LOG("DEBUG LOG : board_type = %d , d5005 board\n", board_type);
    }
  }

  /** Below is fpga enumeration flow
   *  We first enumerate the Port, Physical Function (PF), FME (FPGA Management Engine)
   *  Using Bus, Device we retrieve from above we enumerate Virtual Function (VF) 
   *  using VFIO filter
   */
  for(int count = 0; count <= 1; count++) {
    fpgaGetProperties(NULL, &filter);
    fpgaPropertiesSetInterface(filter, filter_list[count]);
    //fpgaPropertiesSetInterface(filter, FPGA_IFC_SIM_DFL);

    num_matches = 0;
    res = fpgaEnumerate(&filter, 1, NULL, 0, &num_matches);

    if(num_matches >= 1) { 
      break;
    }

    fpgaDestroyProperties(&filter);
  }

  if (num_matches < 1) {
    fpgaDestroyProperties(&filter); 
    LOG_ERR("Error creating properties object: %s\n", fpgaErrStr(res));
    if(std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : Error creating properties object: %s\n", fpgaErrStr(res));
    }
    throw std::runtime_error("DFL device not found");
    //goto cleanup;
  }

  tokens = (fpga_token *)calloc(num_matches, sizeof(fpga_token));
  if(tokens==NULL){
    printf("Error! memory not allocated.");
    exit(1);
  }  

  res = fpgaEnumerate(&filter, 1, tokens, num_matches, &num_matches);
  if (res != FPGA_OK) {
    fpgaDestroyProperties(&filter);
    free(tokens);
    throw std::runtime_error(std::string("Error enumerating AFCs: ") +
                             std::string(fpgaErrStr(res)));
  }

  if (num_matches < 1) {
    fpgaDestroyProperties(&filter);
    free(tokens);
    throw std::runtime_error("AFC not found");
  }

  for (i = 0 ; i < num_matches ; ++i) {
    res = fpgaGetProperties(tokens[i], &props);
    if (res != FPGA_OK) {
        throw std::runtime_error(std::string("Error calling API fpgaGetProperties() : ") +
                                 std::string(fpgaErrStr(res)));
    }

    uint64_t oid = 0;
    res = fpgaPropertiesGetObjectID(props, &oid);
    if (res != FPGA_OK) {
        throw std::runtime_error(std::string("Error calling API fpgaPropertiesGetObjectID() : ") +
                                 std::string(fpgaErrStr(res)));
    }

    if (oid == obj_id) {
      // We've found our Port..
      port_token = tokens[i];

      res = fpgaOpen(port_token, &port_handle, 0);
      if (res != FPGA_OK) {
        throw std::runtime_error(std::string("Error opening Port: ") +
                                 std::string(fpgaErrStr(res)));
      }

      fpgaPropertiesGetBus(props, &bus);
      fpgaPropertiesGetDevice(props, &device);
      fpgaPropertiesGetFunction(props, &function);

      fpgaPropertiesGetParent(props, &fme_token);

      fpgaDestroyProperties(&props);
      break;
    }

    fpgaDestroyProperties(&props);
  }

  if (!port_token || !fme_token) {
      printf("port token : %p \n fme token : %p \n", port_token, fme_token);
      throw std::runtime_error(std::string("Couldn't find tokens\n "));
  }

  for(int count = 0; count <= 1; count++) {
    fpgaGetProperties(NULL, &props);
    if (res != FPGA_OK) {
        throw std::runtime_error(std::string("Error reading properties: ") +
            std::string(fpgaErrStr(res)));
    }

    fpgaPropertiesSetBus(props, bus);
    fpgaPropertiesSetDevice(props, device);
    fpgaPropertiesSetInterface(props, filter_vfio_list[count]);

    num_matches = 0;
    res = fpgaEnumerate(&props, 1, &mmio_token, 1, &num_matches);
    if (res != FPGA_OK) {
        throw std::runtime_error(std::string("fpgaEnumerate failed: ") +
                                   std::string(fpgaErrStr(res)));	  
    }

    if (num_matches >= 1) {
      break;	  
    }

    fpgaDestroyProperties(&props);
  }

  LOG_ERR("num_matches = %d\n", num_matches); 
  if(std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : num_matches = %d\n", num_matches);
  }
  if (num_matches < 1) {
    fpgaDestroyProperties(&filter); 
    LOG_ERR("Error creating properties object: %s\n", fpgaErrStr(res));
    if(std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : DFL device not found\n");
    }
    throw std::runtime_error("DFL device not found");
  }

  if (mmio_token) {
      res = fpgaOpen(mmio_token, &mmio_handle, 0);
      if (res != FPGA_OK) {
        throw std::runtime_error(std::string("Couldn't open mmio_token: ") +
                                 std::string(fpgaErrStr(res)));
      }
  }
  
  res = fpgaGetProperties(mmio_token, &props);
  if (res != FPGA_OK) {
    throw std::runtime_error(std::string("Error reading properties: ") +
                             std::string(fpgaErrStr(res)));
  }

  res = fpgaPropertiesGetGUID(props, &guid);
  if (res != FPGA_OK) {
      throw std::runtime_error(std::string("Error reading GUID: ") +
                               std::string(fpgaErrStr(res)));
  }

  fpgaDestroyProperties(&props);

  // TODO: Better encapsulation of how ASP variant is related to the DDR offset
  // value.
  if (uuid_parse(SVM_ASP_AFU_ID, svm_guid) < 0) {
    LOG_ERR("Error parsing guid '%s'\n", SVM_ASP_AFU_ID);
    if(std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : Error parsing guid '%s'\n", SVM_ASP_AFU_ID);
    }
  }

  if (uuid_compare(svm_guid, guid) == 0) {
    //fprintf(stderr,"svm_guid detected; setting mem_capability_support to 1 \n");
    mem_capability_support = 1;
  } else {
    //fprintf(stderr,"svm_guid not detected; setting mem_capability_support to 0 \n");
    mem_capability_support = 0;
  }

  if (uuid_compare(guid, svm_guid) == 0) {
    ddr_offset = SVM_DDR_OFFSET;
    mpf_mmio_offset = SVM_MMD_MPF;
  } else {
    ddr_offset = PCI_DDR_OFFSET;
    mpf_mmio_offset = SVM_MMD_MPF;
  }

  initialize_fme_sysfs();

  mpf_handle = nullptr;
  mmd_dev_name = get_board_name(ASP_NAME, obj_id);
  afu_initialized = true;
  if(std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : Done constructing Device object\n");
  }
}

/** Return true if board name parses correctly, false if it does not
 *  Return the parsed object_id in obj_id as an [out] parameter
 */
bool Device::parse_board_name(const char *board_name_str,
                                  uint64_t &obj_id) {
  if(std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : Parsing board name\n");
  }
  std::string prefix(ASP_NAME);
  std::string board_name(board_name_str);

  obj_id = 0;
  if (board_name.length() <= prefix.length() &&
      board_name.compare(0, prefix.length(), prefix)) {
    LOG_ERR("Error parsing device name '%s'\n", board_name_str);
    if(std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : Error parsing device name '%s'\n", board_name_str);
    }
    return false;
  }

  std::string device_num_str = board_name.substr(prefix.length());
  obj_id = std::stol(device_num_str, 0, 16);

  // Assume that OPAE does not use 0 as a valid object ID. This is true for now
  // but relies somewhat on an implementaion dependent feature.
  assert(obj_id > 0);
  return true;
}

/** Read information directly from sysfs.  This is non-portable and relies on
 *  paths set in driver (will not interoperate between DFH driver in up-stream
 *  kernel and Intel driver distributed with OFS cards).  In the future hopefully
 *  OPAE can provide SDK to read this information
 */
void Device::initialize_fme_sysfs() {
  const int MAX_LEN = 250;
  char numa_path[MAX_LEN];

  // HACK: currently ObjectID is constructed using its lower 20 bits
  // as the device minor number.  The device minor number also matches
  // the device ID in sysfs.  This is a simple way to construct a path
  // to the device FME using information that is already available (object_id).
  // Eventually this code should be replaced with a direct call to OPAE C API,
  // but API does not currently expose the NUMA nodes.
  int dev_num = 0xFFFFF & fpga_obj_id;

  // Path to NUMA node
  snprintf(numa_path, MAX_LEN,
           "/sys/class/fpga_region/region%d/device/numa_node", dev_num);

  char *numa_env_var = std::getenv("MMD_ENABLE_NUMA");
  int numa_env_val = 1;
  if (numa_env_var != nullptr) {
    numa_env_val = std::atoi(numa_env_var);
  }
  if (numa_env_val == 1) {
    // Read NUMA node and set value for future use. If not available set to -1
    // and disable use of NUMA setting
    std::ifstream sysfs_numa_node(numa_path, std::ifstream::in);
    if (sysfs_numa_node.is_open()) {
      sysfs_numa_node >> fpga_numa_node;
      sysfs_numa_node.close();
      if (std::stoi(fpga_numa_node) >= 0) {
        enable_set_numa = true;
      } else {
        enable_set_numa = false;
        fpga_numa_node = "-1";
      }
    } else {
      enable_set_numa = false;
      fpga_numa_node = "-1";
    }
  } else {
    enable_set_numa = false;
    fpga_numa_node = "-1";
  }
}

/** find_dma_dfh_offsets() function is used in Device::initialize_asp() 
 *  We need to reinitialize DMA after we initialize asp 
 *  because we fpgaReset() as part of initializing ASP
 *  find_dma_dfh_offsets() helps us find the appropriate DFH offsets
 */ 
bool Device::find_dma_dfh_offsets() {
  uint64_t dfh_offset = 0;
  uint64_t next_dfh_offset = 0;
  if (find_dfh_by_guid(mmio_handle, DMA_BBB_GUID, &dfh_offset,
                       &next_dfh_offset)) {
    dma_ch0_dfh_offset = dfh_offset;
    if(std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : DMA CH1 offset: 0x%lX\t GUID: %s\n", dma_ch0_dfh_offset, DMA_BBB_GUID);
    }
    DEBUG_PRINT("DMA CH1 offset: 0x%lX\t GUID: %s\n", dma_ch0_dfh_offset,
                DMA_BBB_GUID);
  } else {
    fprintf(stderr,
            "Error initalizing DMA: Cannot find DMA channel 0 DFH offset\n");
    return false;
  }

  dfh_offset += 0;//next_dfh_offset;
  if (find_dfh_by_guid(mmio_handle, DMA_BBB_GUID, &dfh_offset,
                       &next_dfh_offset)) {
    dma_ch1_dfh_offset = dfh_offset;
    DEBUG_PRINT("DMA CH2 offset: 0x%lX\t GUID: %s\n", dma_ch1_dfh_offset,
                DMA_BBB_GUID);
    if(std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : DMA CH2 offset: 0x%lX\t GUID: %s\n", dma_ch1_dfh_offset, DMA_BBB_GUID);
    }
  } else {
    fprintf(stderr,
            "Error initalizing DMA. Cannot find DMA channel 2 DFH offset\n");
    return false;
  }

  assert(dma_ch0_dfh_offset != 0);
  assert(dma_ch1_dfh_offset != 0);

  return true;
}

bool Device::find_iopipes_dfh_offsets() {
  uint64_t dfh_offset = 0;
  uint64_t next_dfh_offset = 0;
  if (find_dfh_by_guid(mmio_handle, IOPIPES_GUID, &dfh_offset,
                       &next_dfh_offset)) {
    iopipes_dfh_offset = dfh_offset;
    if(std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : IOPIPES offset: 0x%lX\t GUID: %s\n", iopipes_dfh_offset, IOPIPES_GUID);
    }
  } else {
    if(std::getenv("MMD_ENABLE_DEBUG")){  
      DEBUG_LOG("DEBUG LOG : IO Pipes feature not enabled, IO Pipes not instantiated in ASP\n");
    }
    return false;
  }
  
  assert(iopipes_dfh_offset != 0);

  return true;
}

/** initialize_asp() function is used in aocl_mmd_open() API
 *  It resets AFC and reinitializes DMA, Kernel Interrupts if in use 
 */ 
bool Device::initialize_asp() {
  if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : Initializing ASP ... \n");
  }
  if (asp_initialized) {
    if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : ASP already initialized \n");
    }
    return true;
  }

  fpga_result res = fpgaMapMMIO(mmio_handle, 0, NULL);
  if (res != FPGA_OK) {
    LOG_ERR("Error mapping MMIO space: %s\n", fpgaErrStr(res));
    if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : Error mapping MMIO space: %s\n",fpgaErrStr(res));
    }
    return false;
  }
  mmio_is_mapped = true;

  /* Reset AFC */
  res = fpgaReset(port_handle);
  if (res != FPGA_OK) {
    LOG_ERR("Error resetting AFC: %s\n", fpgaErrStr(res));
    if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : Error resetting AFC: %s\n",fpgaErrStr(res));
    }
    return false;
  } else {
    if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : AFC reset \n");
    }
  }
  AFU_RESET_DELAY();

  // DMA performance is heavily dependent on the memcpy operation that transfers
  // data from user allocated buffer to the pinned buffer that is used for
  // DMA.  On some machines with multiple NUMA nodes it is critical for
  // performance that the pinned buffer is located on the NUMA node as the
  // threads that performs the DMA operation.
  //
  // The performance also improves slighlty if the DMA threads are on the same
  // NUMA node as the FPGA PCI device.
  //
  // This code pins memory allocation to occur from FPGA NUMA node prior to
  // initializing the DMA buffers.  It also pins all threads in the process
  // to run on this same node.
  struct bitmask *mask = NULL;
  if (enable_set_numa) {
    mask = numa_parse_nodestring(fpga_numa_node.c_str());
    numa_set_membind(mask);
    int ret = numa_run_on_node_mask_all(mask);
    if (ret < 0) {
      fprintf(stderr, " Error setting NUMA node mask\n");
    }
  }

  find_dma_dfh_offsets();

  if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : Connecting MPF \n");
  }
  mpfConnect(mmio_handle, 0, mpf_mmio_offset, &mpf_handle, 0);

  if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : Initializing HOST -> FPGA DMA channel \n");
  }
  const int dma_ch0_interrupt_num = 0; // DMA channel 0 hardcoded to interrupt 0
  dma_host_to_fpga =
      new mmd_dma(mmio_handle, mmd_handle, mpf_handle, dma_ch0_dfh_offset,
                  dma_ch0_interrupt_num, dma_mode::h2f);
  if (!dma_host_to_fpga->initialized()) {
    fprintf(stderr, "Error initializing MMD DMA\n");
    if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : Error initializing HOST -> FPGA DMA channel \n");
    }
    delete dma_host_to_fpga;
    return false;
  }

  if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : Initializing FPGA -> HOST DMA channel \n");
  }
  const int dma_ch1_interrupt_num = 2; // DMA channel 1 hardcoded to interrupt 2
  dma_fpga_to_host =
      new mmd_dma(mmio_handle, mmd_handle, mpf_handle, dma_ch1_dfh_offset,
                  dma_ch1_interrupt_num, dma_mode::f2h);
  if (!dma_fpga_to_host->initialized()) {
    fprintf(stderr, "Error initializing mmd dma\n");
    if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : Error initializing FPGA -> HOST DMA channel \n");
    }
    return false;
  }

  /** IO Pipes initialization
   ** Read from NUM_IOPIPES CSR and pass it to iopipes constructor call
   ** so setup_oneapi_asp() call can use it to initialize the config, status CSRs for all the pipes.
   */
  bool iopipes_enabled = find_iopipes_dfh_offsets();
  if(!diagnose && iopipes_enabled) {
    DEBUG_LOG("DEBUG LOG : IO Pipes are enabled\n");
    std::string local_ip_address;
    std::string local_mac_address;
    std::string local_netmask;
    int local_udp_port=0;
    std::string remote_ip_address;
    std::string remote_mac_address;
    int remote_udp_port=0;

    if(std::getenv("LOCAL_IP_ADDRESS")){
      local_ip_address = std::getenv("LOCAL_IP_ADDRESS");
    } else{
      fprintf(stderr, "Please set environment variable LOCAL_IP_ADDRESS to use IO PIPES\n");
      return false;   
    }

    if(std::getenv("LOCAL_MAC_ADDRESS")){
      local_mac_address = std::getenv("LOCAL_MAC_ADDRESS");
    } else{
      fprintf(stderr, "Please set environment variable LOCAL_MAC_ADDRESS to use IO PIPES\n");
      return false;  
    }

    if(std::getenv("LOCAL_NETMASK")){
      local_netmask = std::getenv("LOCAL_NETMASK");
    } else{
      fprintf(stderr, "Please set environment variable LOCAL_NETMASK to use IO PIPES\n");
      return false;   
    }

    if(std::getenv("LOCAL_UDP_PORT")){
      local_udp_port = atoi(std::getenv("LOCAL_UDP_PORT"));
    } else{
      fprintf(stderr, "Please set environment variable LOCAL_UDP_PORT to use IO PIPES\n");
      return false;   
    }

    if(std::getenv("REMOTE_IP_ADDRESS")){
      remote_ip_address = std::getenv("REMOTE_IP_ADDRESS");
    } else{
      fprintf(stderr, "Please set environment variable REMOTE_IP_ADDRESS to use IO PIPES\n");
      return false;   
    }

    if(std::getenv("REMOTE_MAC_ADDRESS")){
      remote_mac_address = std::getenv("REMOTE_MAC_ADDRESS");
    } else{
      fprintf(stderr, "Please set environment variable REMOTE_MAC_ADDRESS to use IO PIPES\n");
      return false;   
    }

    if(std::getenv("REMOTE_UDP_PORT")){
      remote_udp_port = atoi(std::getenv("REMOTE_UDP_PORT"));
    } else{
      fprintf(stderr, "Please set environment variable REMOTE_UDP_PORT to use IO PIPES\n");
      return false;   
    }

    DEBUG_LOG("DEBUG LOG : Creating iopipes object and setting up iopipes\n");
    io_pipes = new iopipes(mmd_handle, local_ip_address, local_mac_address, local_netmask, local_udp_port, remote_ip_address, remote_mac_address, remote_udp_port, iopipes_dfh_offset);
    if(!(io_pipes->setup_iopipes_asp(mmio_handle))){
      return false;
    }
  }
  
  //set the magic-number memory location on the host
  //dma_h->magic_iova
  //res = MMIOWrite64Blk(dma_h, dma_h->dma_desc_base, (uint64_t)desc,
  //                     sizeof(*desc));
  //ON_ERR_GOTO(res, out, "MMIOWrite64Blk");

  // Turn off membind restriction in order to allow future allocation to
  // occur on different NUMA nodes if needed.  Hypothesis is that only
  // the pinned buffers are performance critical for the memcpy. Other
  // allocations in the process can occur on other NUMA nodes if needed.
  if (enable_set_numa) {
    numa_set_membind(numa_nodes_ptr);
    numa_free_nodemask(mask);
  }

  try {
    kernel_interrupt_thread = new KernelInterrupt(mmio_handle, mmd_handle);
  } catch (const std::system_error &e) {
    std::cerr << "Error initializing kernel interrupt thread: " << e.what()
              << e.code() << std::endl;
    return false;
  } catch (const std::exception &e) {
    std::cerr << "Error initializing kernel interrupt thread: " << e.what()
              << std::endl;
    return false;
  }

  asp_initialized = true;
  if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : ASP Initialized ! \n");
  }
  return asp_initialized;
}

/** Device Class Destructor implementation
 *  Properly releasing and free-ing memory
 *  part of best coding practices and help
 *  with stable system performance and 
 *  helps reduce bugs
 */
Device::~Device() {
  if(std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : Destructing Device object \n");
  }
  int num_errors = 0;
  if (mmd_copy_buffer) {
    free(mmd_copy_buffer);
    mmd_copy_buffer = NULL;
  }

  if (kernel_interrupt_thread) {
    delete kernel_interrupt_thread;
    kernel_interrupt_thread = NULL;
  }

  if (dma_host_to_fpga) {
    delete dma_host_to_fpga;
    dma_host_to_fpga = NULL;
  }

  if (dma_fpga_to_host) {
    delete dma_fpga_to_host;
    dma_fpga_to_host = NULL;
  }

  if (mpf_handle) {
    mpfDisconnect(mpf_handle);
  }

  if (mmio_is_mapped) {
    if (fpgaUnmapMMIO(mmio_handle, 0))
      num_errors++;
  }

  if (port_handle) {
    if (fpgaClose(port_handle) != FPGA_OK)
      num_errors++;
  }

  if (port_token) {
    if (fpgaDestroyToken(&port_token) != FPGA_OK)
      num_errors++;
  }

  if (mmio_handle) {
    if (fpgaClose(mmio_handle) != FPGA_OK)
      num_errors++;
  }

  if (mmio_token) {
    if (fpgaDestroyToken(&mmio_token) != FPGA_OK)
      num_errors++;
  }

  if (filter) {
    if (fpgaDestroyProperties(&filter) != FPGA_OK)
      num_errors++;
  }

  if (num_errors > 0) {
    DEBUG_PRINT("Error freeing resources in Device destructor\n");
    if(std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : Error freeing resources in Device destructor\n");
    }
  }
}

/** progam_bitstream() is used in program_aocx() function
 *  it calls program_gbs_bitstream() function which is implemented in fpgaconf.c
 *  it reconnects MPF and re-initializes DMA after programming bitstream
 */ 
int Device::program_bitstream(uint8_t *data, size_t data_size) {
  if (!afu_initialized) {
   if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : FPGA NOT FOUND \n");
    }
    return FPGA_NOT_FOUND;
  }

  assert(data);

  if (kernel_interrupt_thread) {
    kernel_interrupt_thread->disable_interrupts();
  }

  if (mpf_handle) {
    if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : Disconnecting MPF before program bitstream, this will also disconnect DMA. \n");
    }
    mpfDisconnect(mpf_handle);
  }

  find_fpga_target target = {bus, device, function, -1};
  fpga_token fpga_dev;
  int num_found = find_fpga(target, &fpga_dev);
  if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : Trying to find FPGA using bus, device, function. \n");
  }

  int result;
  if (num_found == 1) {
    if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : FPGA found , programming bitstream using program_gbs_bitstream() \n");
    }
    result = program_gbs_bitstream(fpga_dev, data, data_size);
  } else {
    LOG_ERR("Error programming FPGA\n");
    if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : FPGA not found , Error programming FPGA \n");
    }
    result = -1;
  }

  fpgaDestroyToken(&fpga_dev);

  fpga_result res = FPGA_OK;
  fpga_properties prop = nullptr;

  fpga_guid svm_guid, pci_guid;

  if (uuid_parse(PCI_ASP_AFU_ID, pci_guid) < 0) {
    LOG_ERR("Error parsing guid '%s'\n", PCI_ASP_AFU_ID);
    if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG :  Error parsing guid '%s' \n", PCI_ASP_AFU_ID);
    }
  }

  if (uuid_parse(SVM_ASP_AFU_ID, svm_guid) < 0) {
    LOG_ERR("Error parsing guid '%s'\n", SVM_ASP_AFU_ID);
    if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : Error parsing guid '%s' \n",SVM_ASP_AFU_ID );
    }
  }

  uint32_t num_matches = 0;
  if(!mmio_token){
    fpgaGetProperties(NULL, &prop);
    fpgaPropertiesSetBus(prop, bus);
    fpgaPropertiesSetDevice(prop, device);
    fpgaPropertiesSetInterface(prop, FPGA_IFC_VFIO);
    //fpgaPropertiesSetInterface(prop, FPGA_IFC_SIM_VFIO);

    res = fpgaEnumerate(&prop, 1, &mmio_token, 1, &num_matches);
    if (res != FPGA_OK) {
      throw std::runtime_error(std::string("fpgaEnumerate failed: ") +
                                 std::string(fpgaErrStr(res)));
    }

    res = fpgaOpen(mmio_token, &mmio_handle, 0);
    if (res != FPGA_OK) {
      throw std::runtime_error(std::string("Couldn't open mmio_token: ") +
                               std::string(fpgaErrStr(res)));
    }

  }

  res = fpgaGetProperties(mmio_token, &prop);
  if (res != FPGA_OK) {
    throw std::runtime_error(std::string("Error reading properties: ") +
                             std::string(fpgaErrStr(res)));
  }

  if (prop) {
    res = fpgaPropertiesGetGUID(prop, &guid);
    if (res != FPGA_OK) {
      throw std::runtime_error(std::string("Error reading GUID: ") +
                               std::string(fpgaErrStr(res)));
    }

    if (uuid_compare(svm_guid, guid) == 0) {
      mem_capability_support = 1;
    } else {
      mem_capability_support = 0;
    }

  }
  fpgaDestroyProperties(&prop);

  if (uuid_compare(guid, svm_guid) == 0) {
    ddr_offset = SVM_DDR_OFFSET;
    mpf_mmio_offset = SVM_MMD_MPF;
  } else {
    ddr_offset = PCI_DDR_OFFSET;
    mpf_mmio_offset = SVM_MMD_MPF;
  }

  if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : Connecting MPF after program bitstream \n");
  }

  mpf_handle = nullptr;
  mpfConnect(mmio_handle, 0, mpf_mmio_offset, &mpf_handle, 0);

  if (kernel_interrupt_thread) {
    kernel_interrupt_thread->enable_interrupts();
  }

  if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : Initializing HOST -> FPGA DMA after program bitstream \n");
  }
  if (dma_host_to_fpga) {
    const int dma_ch0_interrupt_num = 0; // DMA channel 0 hardcoded to interrupt 0
    dma_host_to_fpga =
        new mmd_dma(mmio_handle, mmd_handle, mpf_handle, dma_ch0_dfh_offset,
                    dma_ch0_interrupt_num, dma_mode::h2f);
    if (!dma_host_to_fpga->initialized()) {
      LOG_ERR("Error initializing mmd H2F DMA\n");
      if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
        DEBUG_LOG("DEBUG LOG : Error Initializing HOST -> FPGA DMA after program bitstream \n");
      }
      delete dma_host_to_fpga;
      return false;
    }
  }

  if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : Initializing FPGA -> HOST DMA after program bitstream \n");
  }
  if (dma_fpga_to_host) {
    const int dma_ch1_interrupt_num = 2; // DMA channel 1 hardcoded to interrupt 2
    dma_fpga_to_host =
        new mmd_dma(mmio_handle, mmd_handle, mpf_handle, dma_ch1_dfh_offset,
                    dma_ch1_interrupt_num, dma_mode::f2h);
    if (!dma_fpga_to_host->initialized()) {
      fprintf(stderr, "Error initializing MMD F2H DMA\n");
      return false;
    }
  }

  return result;
}

/** Calls kernel_interrupt_thread->yield() */
int Device::yield() {
  if(std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : Device::yield() \n");
  }
  if (kernel_interrupt_thread) {
    return kernel_interrupt_thread->yield();
  } else {
    return 0;
  }
}

/** asp_loaded() function which checks if asp is loaded on board
 *  it is used in aocl_mmd_open() API
 */
bool Device::asp_loaded() {

  fpga_guid pci_guid;
  fpga_guid svm_guid;
  fpga_guid afu_guid;
  fpga_properties prop;
  fpga_result res;

  if (uuid_parse(PCI_ASP_AFU_ID, pci_guid) < 0) {
    LOG_ERR("Error parsing guid '%s'\n", PCI_ASP_AFU_ID);
    if(std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : Error parsing guid '%s' \n", PCI_ASP_AFU_ID);
    }
    return false;
  }
  if (uuid_parse(SVM_ASP_AFU_ID, svm_guid) < 0) {
    LOG_ERR("Error parsing guid '%s'\n", SVM_ASP_AFU_ID);
    if(std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : Error parsing guid '%s' \n", SVM_ASP_AFU_ID);
    }
    return false;
  }

  res = fpgaGetProperties(mmio_token, &prop);
  if (res != FPGA_OK) {
    LOG_ERR("Error reading properties: %s\n", fpgaErrStr(res));
    if(std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : Error reading properties: %s \n", fpgaErrStr(res));
    }
    fpgaDestroyProperties(&prop);
    return false;
  }

  if(!mmio_token) {
    fpgaDestroyProperties(&prop);
    return false;
  }

  res = fpgaPropertiesGetGUID(prop, &afu_guid);
  if (res != FPGA_OK) {
    LOG_ERR("Error reading GUID\n");
    if(std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : Error reading GUID \n");
    }
    fpgaDestroyProperties(&prop);
    return false;
  }

  fpgaDestroyProperties(&prop);
  if (uuid_compare(pci_guid, afu_guid) == 0 ||
      uuid_compare(svm_guid, afu_guid) == 0) {
    if(std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : asp loaded : true \n");
    } 
    return true;
  } else {
    if(std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : asp loaded : false \n");
    }
    return false;
  }
}

std::string Device::get_bdf() {
  std::ostringstream bdf;
  bdf << std::setfill('0') << std::setw(2) << std::hex << unsigned(bus) << ":"
      << std::setfill('0') << std::setw(2) << std::hex << unsigned(device) << "."
      << std::hex << unsigned(function);

  return bdf.str();
}

/** get_temperature() function is called 
 *  in aocl_mmd_get_info() API
 *  We currently use hardcoded paths to retrieve temperature information
 *  We will replace with OPAE APIs in future
 */
float Device::get_temperature() {
  if(std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : Reading temperature ... \n");
  }
  float temp = 0;
  fpga_object obj;
  const char *name;
  if(board_type == 1){
    name = "dfl_dev.*/*-hwmon.*.auto/hwmon/hwmon*/temp15_input";
  }else{
    name = "dfl_dev.*/spi_master/spi*/spi*.*/*-hwmon.*.auto/hwmon/hwmon*/temp1_input";
  }

  fpga_result res;
  res = fpgaTokenGetObject(fme_token, name, &obj, FPGA_OBJECT_GLOB);
  if (res != FPGA_OK) {
    if(std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : Error reading temperature monitor from BMC :");
      DEBUG_LOG(" %s \n",fpgaErrStr(res));
    }
    temp = -999;
    return temp;
  }

  uint64_t value = 0;
  fpgaObjectRead64(obj, &value, FPGA_OBJECT_SYNC);
  fpgaDestroyObject(&obj);
  temp = value / 1000;
  return temp;
}

/** set_kernel_interrupt() function is used in aocl_mmd_set_interrupt_handler() API
 */
void Device::set_kernel_interrupt(aocl_mmd_interrupt_handler_fn fn,
                                      void *user_data) {
  if(std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : Device::set_kernel_interrupt() \n");
  }
  if (kernel_interrupt_thread) {
    kernel_interrupt_thread->set_kernel_interrupt(fn, user_data);
  }
}

/** set_kernel_interrupt() function is used in aocl_mmd_set_status_handler() API
 */
void Device::set_status_handler(aocl_mmd_status_handler_fn fn,
                                    void *user_data) {
  if(std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : Device::set_status_handler() \n");
  }
  event_update = fn;
  event_update_user_data = user_data;
  dma_host_to_fpga->set_status_handler(fn, user_data);
  dma_fpga_to_host->set_status_handler(fn, user_data);
}

/** event_update_fn() is used in read_block(), write_block(), copy_block() functions
 *  OPAE provides event API for handling asynchronous events sucj as errors and interrupts
 *  under the hood those are used
 */
void Device::event_update_fn(aocl_mmd_op_t op, int status) {
  if(std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : Device::event_update_fn() \n");
  }
  event_update(mmd_handle, event_update_user_data, op, status);
}

/** read_block() is used in aocl_mmd_read() API
 *  as name suggests its used for fpga->host DMA and MMIO transfers
 */
int Device::read_block(aocl_mmd_op_t op, int mmd_interface, void *host_addr,
                           size_t offset, size_t size) {
  if(std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : Device::read_block()\n");
  }
  int res;

  // The mmd_interface is defined as the base address of the MMIO write.  Access
  // to memory requires special functionality.  Otherwise do direct MMIO read of
  // base address + offset
  if (mmd_interface == AOCL_MMD_MEMORY) {
    if(std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : Using DMA to read block\n");
    }
    assert(offset >= ddr_offset);
    res = dma_fpga_to_host->fpga_to_host(op, host_addr, offset - ddr_offset,
                                         size);
  } else {
    if(std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : Using MMIO to read block\n");
    }
    res = read_mmio(host_addr, mmd_interface + offset, size);

    if (op) {
      this->event_update_fn(op, res);
    }
  }
  return res;
}

/** write_block() is used in aocl_mmd_write() API
 *  as name suggests its used for host->fpga DMA and MMIO transfers
 */
int Device::write_block(aocl_mmd_op_t op, int mmd_interface,
                            const void *host_addr, size_t offset, size_t size) {
  if(std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : Device::write_block()\n");
  }
  int res;

  // The mmd_interface is defined as the base address of the MMIO write.  Access
  // to memory requires special functionality.  Otherwise do direct MMIO write
  if (mmd_interface == AOCL_MMD_MEMORY) {
    if(std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : Using DMA to write block\n");
    }
    assert(offset >= ddr_offset);
    res = dma_host_to_fpga->host_to_fpga(op, host_addr, offset - ddr_offset,
                                         size);
  } else {
    if(std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : Using MMIO to write block\n");
    }
    res = write_mmio(host_addr, mmd_interface + offset, size);
    if (op) {
      this->event_update_fn(op, res);
    }
  }

  return res;
}

/** copy_block() is used in aocl_mmd_copy() API
 *  as name suggests its used for copies from source to destination 
 *  currently we use intermediate buffer for copies
 *  implementation can be optimized to use direct copy in future
 */
int Device::copy_block(aocl_mmd_op_t op, int mmd_interface,
                           size_t src_offset, size_t dst_offset, size_t size) {
  if(std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : Device::copy_block()\n");
  }
  int status = -1;

  if (mmd_interface == AOCL_MMD_MEMORY) {
    size_t bytes_left = size;
    size_t read_offset = src_offset;
    size_t write_offset = dst_offset;
    while (bytes_left != 0) {
      size_t chunk =
          bytes_left > MMD_COPY_BUFFER_SIZE ? MMD_COPY_BUFFER_SIZE : bytes_left;

      // for now, just to reads and writes to/from host to implement this
      // DMA hw can support direct copy but we don't have time to verify
      // that so close to the release.
      // also this API is rarely used.
      status = read_block(NULL, AOCL_MMD_MEMORY, mmd_copy_buffer, read_offset,
                          chunk);
      if (status != 0)
        break;
      status = write_block(NULL, AOCL_MMD_MEMORY, mmd_copy_buffer, write_offset,
                           chunk);
      if (status != 0)
        break;
      read_offset += chunk;
      write_offset += chunk;
      bytes_left -= chunk;
    }
    status = 0;
  } else {
    if(std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : Error copy_block unsupported mmd_interface: %d\n", mmd_interface);
    }
    LOG_ERR("copy_block unsupported mmd_interface: %d\n", mmd_interface);
    status = -1;
  }

  if (op) {
    // TODO: check what 'status' value should really be.  Right now just
    // using 0 as was done in previous MMD.  Also handle case if op is NULL
    this->event_update_fn(op, 0);
  }

  return status;
}

/** read_mmio() is used in read_block() function
 *  it uses OPAE APIs fpgaReadMMIO64() fpgaReadMMIO32
 */
int Device::read_mmio(void *host_addr, size_t mmio_addr, size_t size) {
  fpga_result res = FPGA_OK;

  DCP_DEBUG_MEM("read_mmio start: %p\t 0x%zx\t 0x%zx\n", host_addr, mmio_addr,
                size);
  if(std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : Device::read_mmio start: host_addr : %p\t mmio_addr : 0x%zx\t size : 0x%zx\n",host_addr, mmio_addr, size );
  }

  // HACK: need extra delay for oneapi sw reset
  if (mmio_addr == KERNEL_SW_RESET_BASE)
    OPENCL_SW_RESET_DELAY();

  uint64_t *host_addr64 = static_cast<uint64_t *>(host_addr);
  while (size >= 8) {
    if(std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : Using fpgaReadMMIO64()       host_addr : %p\t mmio_addr : 0x%zx\t size : 0x8\n",host_addr,mmio_addr);
    }
    res = fpgaReadMMIO64(mmio_handle, 0, mmio_addr, host_addr64);
    if (res != FPGA_OK){
      if(std::getenv("MMD_ENABLE_DEBUG")){
        DEBUG_LOG("DEBUG LOG : Error in read_mmio() host_addr : %p\t mmio_addr : 0x%zx\t size : 0x8\n",host_addr,mmio_addr);
      }
      return -1;
    }
    host_addr64 += 1;
    mmio_addr += 8;
    size -= 8;
  }

  uint32_t *host_addr32 = reinterpret_cast<uint32_t *>(host_addr64);
  while (size >= 4) {
    if(std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : Using fpgaReadMMIO32()       host_addr : %p\t mmio_addr : 0x%zx\t size : 0x4\n",host_addr,mmio_addr);
    }
    res = fpgaReadMMIO32(mmio_handle, 0, mmio_addr, host_addr32);
    if (res != FPGA_OK){
      if(std::getenv("MMD_ENABLE_DEBUG")){
        DEBUG_LOG("DEBUG LOG : Error in read_mmio() host_addr : %p\t mmio_addr : 0x%zx\t size : 0x4\n",host_addr,mmio_addr);
      }
      return -1;
    }
    host_addr32 += 1;
    mmio_addr += 4;
    size -= 4;
  }

  if (size > 0) {
    uint32_t read_data;
    if(std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : Using fpgaReadMMIO32()       host_addr : %p\t mmio_addr : 0x%zx\t size : 0x%zx\n",host_addr,mmio_addr,size);
    }
    res = fpgaReadMMIO32(mmio_handle, 0, mmio_addr, &read_data);
    if (res != FPGA_OK){
      if(std::getenv("MMD_ENABLE_DEBUG")){
        DEBUG_LOG("DEBUG LOG : Error in read_mmio() host_addr : %p\t mmio_addr : 0x%zx\t size : 0x%zx\n",host_addr,mmio_addr,size);
      }
      return -1;
    }
    memcpy(host_addr32, &read_data, size);
  }

  return res;
}

/** write_mmio() is used in write_block() function
 *  it uses OPAE APIs fpgaWriteMMIO64() fpgaWriteMMIO32
 */
int Device::write_mmio(const void *host_addr, size_t mmio_addr,
                           size_t size) {
  fpga_result res = FPGA_OK;

  DEBUG_PRINT("write_mmio\n");
  if(std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : Device::write_mmio start: host_addr : %p\t mmio_addr : 0x%zx\t size : 0x%zx\n",host_addr, mmio_addr, size );
  }

  // HACK: need extra delay for oneapi sw reset
  if (mmio_addr == KERNEL_SW_RESET_BASE)
    OPENCL_SW_RESET_DELAY();

  const uint64_t *host_addr64 = static_cast<const uint64_t *>(host_addr);
  while (size >= 8) {
    if(std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : Using fpgaWriteMMIO64()       host_addr : %p\t mmio_addr : 0x%zx\t size : 0x8\n",host_addr,mmio_addr);
    }
    res = fpgaWriteMMIO64(mmio_handle, 0, mmio_addr, *host_addr64);
    if (res != FPGA_OK){
      if(std::getenv("MMD_ENABLE_DEBUG")){
        DEBUG_LOG("DEBUG LOG : Error in write_mmio() host_addr : %p\t mmio_addr : 0x%zx\t size : 0x8\n",host_addr,mmio_addr);
      }
      return -1;
    }
    host_addr64 += 1;
    mmio_addr += 8;
    size -= 8;
  }

  const uint32_t *host_addr32 = reinterpret_cast<const uint32_t *>(host_addr64);
  while (size > 0) {
    if(std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : Using fpgaWriteMMIO32()       host_addr : %p\t mmio_addr : 0x%zx\t size : 0x%zx\n",host_addr,mmio_addr,size);
    }
    uint32_t tmp_data32 = 0;
    size_t chunk_size = (size >= 4) ? 4 : size;
    memcpy(&tmp_data32, host_addr32, chunk_size);
    res = fpgaWriteMMIO32(mmio_handle, 0, mmio_addr, tmp_data32);
    if (res != FPGA_OK){
      if(std::getenv("MMD_ENABLE_DEBUG")){
        DEBUG_LOG("DEBUG LOG : Error in write_mmio() host_addr : %p\t mmio_addr : 0x%zx\t size : 0x%zx\n",host_addr,mmio_addr,size);
      }
      return -1;
    }
    host_addr32 += 1;
    mmio_addr += chunk_size;
    size -= chunk_size;
  }

  return 0;
}

/** pin_alloc() function is used in aocl_mmd_host_alloc() aocl_mmd_shared_alloc() APIs 
 *  it is also used in repin_all_mem_for_handle() function
 *  it uses mpfVtpPrepareBuffer() API provied by MPF VTP
 */
void *Device::pin_alloc(void **addr, size_t size) {
  if(std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : Device::pin_alloc() : addr : %p, size : %ld\n",addr, size );
  }
  assert(mpf_handle);
  const int flags = FPGA_BUF_PREALLOCATED;
  if(std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : Device::pin_allo()c Using mpfVtpPrepareBuffer()");
  }
  int rc = mpfVtpPrepareBuffer(mpf_handle, size, addr, flags);
  if (rc == FPGA_OK) {
    return *addr;
  } else {
    if(std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : Device::pin_alloc() Error");
    }
    return nullptr;
  }
}

/** free_prepinned_mem() function is used in aocl_mmd_free() API and unpin_all_mem_for_handle() function
 *  it uses mpfVtpReleaseBuffer() API provided by MPF VTP
 */
int Device::free_prepinned_mem(void *mem) {
  if(std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : Device::free_prepinned_mem() : addr : %p\n",mem );
  }
  assert(mpf_handle);
  int rc = mpfVtpReleaseBuffer(mpf_handle, mem);
  if (rc != FPGA_OK) {
    if(std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : Device::free_prepinned_mem() Error");
    }
  }
  return rc;
}
