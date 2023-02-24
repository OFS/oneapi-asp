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

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <zlib.h>

#include <linux/mman.h>
#include <sys/mman.h>

// On some systems MAP_HUGE_2MB is not defined. It should be defined for all
// platforms that DCP supports, but we also want ability to compile MMD on
// CentOS 6 systems.
#ifndef MAP_HUGE_SHIFT
#define MAP_HUGE_SHIFT 26
#endif

#ifndef MAP_HUGE_2MB
#define MAP_HUGE_2MB (21 << MAP_HUGE_SHIFT)
#endif

#ifndef MAP_HUGE_1GB
#define MAP_HUGE_1GB (30 << MAP_HUGE_SHIFT)
#endif

#include <algorithm>
#include <cassert>
#include <iomanip>
#include <iostream>
#include <map>
#include <sstream>
#include <unordered_map>

#include "aocl_mmd.h"
#include "mmd_device.h"
#include "fpgaconf.h"
#include "zlib_inflate.h"

using namespace intel_opae_mmd;

#define ACL_DCP_ERROR_IF(COND, NEXT, ...)                                      \
  do {                                                                         \
    if (COND) {                                                                \
      printf("\nMMD ERROR: " __VA_ARGS__);                                     \
      fflush(stdout);                                                          \
      NEXT;                                                                    \
    }                                                                          \
  } while (0)

#define ACL_PKG_SECTION_DCP_GBS_GZ ".acl.gbs.gz"

// Keep a mapping between allocated memory and associated handle
// XXX: Note that this is not thread-safe.  Not recommened in long term
// likely should reevalute soon.
static std::unordered_map<void *,
                          std::pair<size_t, std::unique_ptr<std::vector<int>>>>
    mem_to_handles_map;

// If the MMD is loaded dynamically, destructors in the MMD will execute before
// the destructors in the runtime upon program termination. The DeviceMapManager
// guards accesses to the device/handle maps to make sure the runtime doesn't
// get to reference them after MMD destructors have been called. Destructor
// makes sure that all devices are closed at program termination regardless of
// what the runtime does. Implemented as a singleton.
class DeviceMapManager final {
public:
  typedef std::map<int, Device *> t_handle_to_dev_map;
  typedef std::map<uint64_t, int> t_id_to_handle_map;

  static const int SUCCESS = 0;
  static const int FAILURE = -1;

  // Returns handle and device pointer to the device with the specified name
  // Creates a new entry for this device if it doesn't already exist
  // Return 0 on success, -1 on failure
  int get_or_create_device(const char *board_name, int *handle,
                           Device **device);

  // Return obj id based on BSP name.
  uint64_t id_from_name(const char *board_name);

  // Return MMD handle based on obj id. Returned value is negative if board
  // doesn't exist
  inline int handle_from_id(uint64_t obj_id);

  // Return pointer to device based on MMD handle. Returned value is null
  // if board doesn't exist
  Device *device_from_handle(int handle);

  // Closes specified device if it exists
  void close_device_if_exists(int handle);

  // Returns a reference to the class singleton
  static DeviceMapManager &get_instance() {
    static DeviceMapManager instance;
    return instance;
  }

  DeviceMapManager(DeviceMapManager const &) = delete;
  void operator=(DeviceMapManager const &) = delete;
  ~DeviceMapManager() {
    // delete all allocated Device* entries
    while (handle_to_dev_map->size() > 0) {
      int handle = handle_to_dev_map->begin()->first;
      aocl_mmd_close(handle);
      #ifdef SIM
        std::cout << "# mmd.cpp: When destroying DeviceMapManager in ASE, assume it worked.\n";
        break;
      #endif
      if(std::getenv("MMD_ENABLE_DEBUG")){
        DEBUG_LOG("DEBUG LOG : In DeviceMapManager destructor, closing device with handle %d \n", handle);
      }
    }
    delete handle_to_dev_map;
    delete id_to_handle_map;
    handle_to_dev_map = nullptr;
    id_to_handle_map = nullptr;
  }

private:
  DeviceMapManager() {
    handle_to_dev_map = new t_handle_to_dev_map();
    id_to_handle_map = new t_id_to_handle_map();

    if(std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : Constructing DeviceMapManager object\n");
    }
  }
  t_handle_to_dev_map *handle_to_dev_map = nullptr;
  t_id_to_handle_map *id_to_handle_map = nullptr;
};
static DeviceMapManager &device_manager = DeviceMapManager::get_instance();

int DeviceMapManager::get_or_create_device(const char *board_name, int *handle,
                                           Device **device) {
  int _handle = MMD_INVALID_PARAM;
  Device *_device = nullptr;

  if (id_to_handle_map == nullptr || handle_to_dev_map == nullptr) {
    if(std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : Failure in DeviceMapManager::get_or_create_device,id_to_handle_map or handle_to_dev_map is NULL\n");
    }
    return DeviceMapManager::FAILURE;
  }

  uint64_t obj_id = id_from_name(board_name);
  if (!obj_id) {
    if(std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : Failure in DeviceMapManager::get_or_create_device. obj_id : %ld \n", obj_id);
    }
    return false;
  }
  if (id_to_handle_map->count(obj_id) == 0) {
    try {
      _device = new Device(obj_id);
      _handle = _device->get_mmd_handle();
      id_to_handle_map->insert({obj_id, _handle});
      handle_to_dev_map->insert({_handle, _device});
    } catch (std::runtime_error &e) {
      if(std::getenv("MMD_ENABLE_DEBUG")){
        DEBUG_LOG("DEBUG LOG : Failure in DeviceMapManager::get_or_create_device %s\n", e.what());
      }
      LOG_ERR("%s\n", e.what());
      delete _device;
      return DeviceMapManager::FAILURE;
    }
    if(std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : Success in creating new device object handle : %d \n", _handle);
    }
  } else {
    _handle = id_to_handle_map->at(obj_id);
    _device = handle_to_dev_map->at(_handle);
    if(std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : Success in retrieving device metadata(handle , object) , handle : %d\n", _handle);
    }
  }

  (*handle) = _handle;
  (*device) = _device;

  if(std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : Success in creating new device object , handle : %d\n", _handle);
  }
  return DeviceMapManager::SUCCESS;
}

uint64_t DeviceMapManager::id_from_name(const char *board_name) {
  uint64_t obj_id = 0;
  if (Device::parse_board_name(board_name, obj_id)) {
    if(std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : Success in retrieving object id from board name\n");
    }
    return obj_id;
  } else {
    if(std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : Failed to retrieve object id from board name\n");
    }
    // TODO: add error hanlding for DeviceMapManager (make sure 0 is marked as
    // invalid device)
    return 0;
  }
}

inline int DeviceMapManager::handle_from_id(uint64_t obj_id) {
  int handle = MMD_INVALID_PARAM;
  if (id_to_handle_map) {
    auto it = id_to_handle_map->find(obj_id);
    if (it != id_to_handle_map->end()) {
      handle = it->second;
    }
    if(std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : Success in retrieving handle from object id. handle : %d \n", handle);
    }
  } else {
    if(std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : Failed to retrieve handle from object id \n");
    }
  }
  return handle;
}

Device *DeviceMapManager::device_from_handle(int handle) {
  Device *dev = nullptr;
  if (handle_to_dev_map) {
    auto it = handle_to_dev_map->find(handle);
    if (it != handle_to_dev_map->end()) {
      return it->second;
    }
    if(std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : Success in retrieving device from handle. handle : %d \n", handle);
    }
  } else {
    if(std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : Failed to retrieve device from handle\n");
    }
  }
  return dev;
}

void DeviceMapManager::close_device_if_exists(int handle) {
  if (handle_to_dev_map) {
    if (handle_to_dev_map->count(handle) > 0) {
      Device *dev = handle_to_dev_map->at(handle);
      uint64_t obj_id = dev->get_fpga_obj_id();
      delete dev;

      handle_to_dev_map->erase(handle);
      id_to_handle_map->erase(obj_id);
      if(std::getenv("MMD_ENABLE_DEBUG")){
        DEBUG_LOG("DEBUG LOG : Closing device with handle : %d\n", handle);
      } 
    } else {
      if(std::getenv("MMD_ENABLE_DEBUG")){
        DEBUG_LOG("DEBUG LOG : Nothing to close. Device with handle : %d already closed\n", handle);
      }
    }
  } else {
    if(std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : Error, no handle to device map entry found for handle : %d \n", handle);
    }
  }
}

// Local function definition
static int program_aocx(int handle, void *data, size_t data_size);

// Interface for programing device that does not have a BSP loaded
int mmd_device_reprogram(const char *device_name, void *data,
                              size_t data_size) {
  if(std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : Entering mmd_device_reprogram() \n");
  }
  int handle;
  Device *dev = nullptr;
  if (device_manager.get_or_create_device(device_name, &handle, &dev) ==
      DeviceMapManager::SUCCESS) {
      return program_aocx(handle, data, data_size);
  } else {
    if(std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : Exiting mmd_device_reprogram() with error\n");
    }
    return MMD_AOCL_ERR;
  }
}

// Interface for checking if AFU has BSP loaded
bool mmd_bsp_loaded(const char *name) {
  uint64_t obj_id = device_manager.id_from_name(name);
  if (!obj_id) {
    if(std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : Error, no object id found for board : %s \n", name);
    }
    return false;
  }

  int handle = device_manager.handle_from_id(obj_id);
  if (handle > 0) {
    Device *dev = device_manager.device_from_handle(handle);
    if(dev) {
      if(std::getenv("MMD_ENABLE_DEBUG")){
        DEBUG_LOG("DEBUG LOG : BSP loaded for handle : %d \n", handle);
      }
      return dev->bsp_loaded();
    } else {
      if(std::getenv("MMD_ENABLE_DEBUG")){
        DEBUG_LOG("DEBUG LOG : BSP not loaded for handle : %d \n", handle);
      }
      return false;
    }
  } else {
    bool bsp_loaded = false;
    try {
      Device dev(obj_id);
      bsp_loaded = dev.bsp_loaded();
    } catch (std::runtime_error &e) {
      LOG_ERR("%s\n", e.what());
      if(std::getenv("MMD_ENABLE_DEBUG")){
        DEBUG_LOG("DEBUG LOG : BSP not loaded for handle : %d , %s\n", handle, e.what());
      }
      return false;
    }

    if(std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : BSP loaded : %d (0 - not loaded , 1 - loaded) for handle : %d \n", bsp_loaded, handle);
    }
    return bsp_loaded;
  }
}

static unsigned int get_offline_num_acl_boards(const char *bsp_uuid) {
  bool bsp_only = true; // TODO: looks like this is alway true now, verify then
                        // remove check.
  fpga_guid guid;
  fpga_result res = FPGA_OK;
  uint32_t num_matches = 0;
  bool ret_err = false;
  fpga_properties filter = NULL;

  if (uuid_parse(bsp_uuid, guid) < 0) {
    LOG_ERR("Error parsing guid '%s'\n", bsp_uuid);
    ret_err = true;
    goto out;
  }

  res = fpgaGetProperties(NULL, &filter);
  if (res != FPGA_OK) {
    LOG_ERR("Error creating properties object: %s\n", fpgaErrStr(res));
    ret_err = true;
    goto out;
  }

  if (bsp_only) {
    res = fpgaPropertiesSetGUID(filter, guid);
    if (res != FPGA_OK) {
      LOG_ERR("Error setting GUID: %s\n", fpgaErrStr(res));
      ret_err = true;
      goto out;
    }
  }

  res = fpgaPropertiesSetObjectType(filter, FPGA_ACCELERATOR);
  if (res != FPGA_OK) {
    LOG_ERR("Error setting object type: %s\n", fpgaErrStr(res));
    ret_err = true;
    goto out;
  }

  res = fpgaEnumerate(&filter, 1, NULL, 0, &num_matches);
  if (res != FPGA_OK) {
    LOG_ERR("Error enumerating AFCs: %s\n", fpgaErrStr(res));
    ret_err = true;
    goto out;
  }

out:
  if (filter)
    fpgaDestroyProperties(&filter);

  if (ret_err) {
    return MMD_AOCL_ERR;
  } else {
    return num_matches;
  }
}

fpga_result get_dfl_tokens(std::vector<fpga_token> &tokens)
{
  fpga_interface filter_list[2] {FPGA_IFC_DFL, FPGA_IFC_SIM_DFL}; 
  fpga_properties filter = nullptr;
  uint32_t num_matches = 0;
  fpga_result res = FPGA_EXCEPTION;

  for(int count = 0; count <= 1; count++) {
    res = fpgaGetProperties(NULL, &filter);
    if (res != FPGA_OK) {
      LOG_ERR("Error creating properties object: %s\n", fpgaErrStr(res));
      goto cleanup;
    }

    fpgaPropertiesSetInterface(filter, filter_list[count]);

    res = fpgaEnumerate(&filter, 1, NULL, 0, &num_matches);
    if (res != FPGA_OK) {
      LOG_ERR("Error enumerating: %s\n", fpgaErrStr(res));
      goto cleanup;
    }

    if(num_matches >= 1) { 
      break;
    }
    fpgaDestroyProperties(&filter);
    
  }

  if (num_matches < 1) {
    LOG_ERR("Error creating properties object: %s\n", fpgaErrStr(res));
    goto cleanup;
  }

  tokens.resize(num_matches);

  res = fpgaEnumerate(&filter, 1, tokens.data(), tokens.size(), &num_matches);
  if (res != FPGA_OK) {
    LOG_ERR("Error enumerating: %s\n", fpgaErrStr(res));
    goto cleanup;
  }

  res = FPGA_OK;

cleanup:
  fpgaDestroyProperties(&filter);
  return res;
}

fpga_result build_board_names(std::vector<fpga_token> &toks, std::string &boards)
{
  if(std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : Querying board name \n");
  }
  fpga_properties props = nullptr;

  for (auto &t : toks) {
    fpgaGetProperties(t, &props);
    fpga_objtype type;

    fpgaPropertiesGetObjectType(props, &type);

    if (type == FPGA_ACCELERATOR) {
      uint64_t obj_id = 0;
      fpgaPropertiesGetObjectID(props, &obj_id);

      boards.append(Device::get_board_name(BSP_NAME, obj_id));
      boards.append(";");
    }

    fpgaDestroyProperties(&props);
  }

  if ((boards.length() > 1) && (boards[boards.length()-1] == ';')) {
    boards = boards.substr(0, boards.length() - 1);
  }

  if(std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : Found board name :  %s\n",boards.c_str());
  }

  return FPGA_OK;
}

static bool get_offline_board_names(std::string &boards, bool bsp_only = true) {
  fpga_guid pci_guid;
  fpga_guid svm_guid;
  fpga_result res = FPGA_OK;
  std::vector<fpga_token> dfl_tokens;

  if (get_dfl_tokens(dfl_tokens)) {
    LOG_ERR("get_dfl_tokens\n");
    if(std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : Failed querying DFL Tokens \n");
    }
    return false;
  } else {
    if(std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : Success querying DFL Tokens \n");
    }  
  }

  if (bsp_only) {

    uuid_parse(PCI_OCL_BSP_AFU_ID, pci_guid);
    uuid_parse(SVM_OCL_BSP_AFU_ID, svm_guid);

    std::vector<fpga_token> bsp_tokens;

    for (auto &t : dfl_tokens) {
      fpga_properties dfl_props = nullptr;
      fpgaGetProperties(t, &dfl_props);

      uint16_t segment = 0;
      uint8_t bus = 0;
      uint8_t device = 0;

      fpgaPropertiesGetSegment(dfl_props, &segment);
      fpgaPropertiesGetBus(dfl_props, &bus);
      fpgaPropertiesGetDevice(dfl_props, &device);

      fpga_token fme_tok = nullptr;
      res = fpgaPropertiesGetParent(dfl_props, &fme_tok);
      if (res != FPGA_OK) {
        fpgaDestroyProperties(&dfl_props);
        continue;      
      }

      const size_t filters = 4;
      fpga_properties filter[filters] = { nullptr, nullptr, nullptr, nullptr };

      //const size_t filters = 2; 
      //fpga_properties filter[filters] = { nullptr, nullptr};
      fpgaGetProperties(nullptr, &filter[0]);
      fpgaPropertiesSetObjectType(filter[0], FPGA_ACCELERATOR);
      fpgaPropertiesSetSegment(filter[0], segment);
      fpgaPropertiesSetBus(filter[0], bus);
      fpgaPropertiesSetDevice(filter[0], device);
      fpgaPropertiesSetGUID(filter[0], pci_guid);
      fpgaPropertiesSetInterface(filter[0], FPGA_IFC_VFIO);
      //fpgaPropertiesSetInterface(filter[0], FPGA_IFC_SIM_VFIO);

      fpgaGetProperties(nullptr, &filter[1]);
      fpgaPropertiesSetObjectType(filter[1], FPGA_ACCELERATOR);
      fpgaPropertiesSetSegment(filter[1], segment);
      fpgaPropertiesSetBus(filter[1], bus);
      fpgaPropertiesSetDevice(filter[1], device);
      fpgaPropertiesSetGUID(filter[1], pci_guid);
      fpgaPropertiesSetInterface(filter[1], FPGA_IFC_SIM_VFIO);


      fpgaGetProperties(nullptr, &filter[2]);
      fpgaPropertiesSetObjectType(filter[2], FPGA_ACCELERATOR);
      fpgaPropertiesSetSegment(filter[2], segment);
      fpgaPropertiesSetBus(filter[2], bus);
      fpgaPropertiesSetDevice(filter[2], device);
      fpgaPropertiesSetGUID(filter[2], svm_guid);
      fpgaPropertiesSetInterface(filter[2], FPGA_IFC_VFIO);
      //fpgaPropertiesSetInterface(filter[2], FPGA_IFC_SIM_VFIO);

      fpgaGetProperties(nullptr, &filter[3]);
      fpgaPropertiesSetObjectType(filter[3], FPGA_ACCELERATOR);
      fpgaPropertiesSetSegment(filter[3], segment);
      fpgaPropertiesSetBus(filter[3], bus);
      fpgaPropertiesSetDevice(filter[3], device);
      fpgaPropertiesSetGUID(filter[3], svm_guid);
      fpgaPropertiesSetInterface(filter[3], FPGA_IFC_SIM_VFIO);

      uint32_t num_tokens = 0;

      res = fpgaEnumerate(filter, filters, nullptr, 0, &num_tokens);
      if ((res == FPGA_OK) && (num_tokens > 0)) {
        bsp_tokens.push_back(t);
      }

      fpgaDestroyProperties(&dfl_props);
      fpgaDestroyProperties(&filter[0]);
      fpgaDestroyProperties(&filter[1]);
      fpgaDestroyProperties(&filter[2]);
      fpgaDestroyProperties(&filter[3]);
    }

    build_board_names(bsp_tokens, boards);

  } else {

    build_board_names(dfl_tokens, boards);

  }

  return true;
}

AOCL_MMD_CALL void aocl_mmd_dump_mpf_stats(const char *name) {
  DEBUG_PRINT("\n- aocl_mmd_dump_mpf_stats:: Dumping MPF statistics\n");
  if(std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : aocl_mmd_dump_mpf_stats:: Dumping MPF statistics\n");
  }
  int handle = aocl_mmd_open(name);
  Device *dev = device_manager.device_from_handle(handle);
  if (dev)
    return dev->dump_mpf_stats();
  else
    fprintf(stderr, "aocl_mmd_dump_mpf_stats:: FAILED getting device\n");
}

AOCL_MMD_CALL void aocl_mmd_shared_mem_prepare_buffer(const char *name,
                                                      size_t size,
                                                      void *host_ptr) {
  DCP_DEBUG_MEM("\n- aocl_mmd_shared_mem_prepare_buffer: %s\t %lu\t %p\t \n",
                name, size, host_ptr);
  if(std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : aocl_mmd_shared_mem_prepare_buffer: %s\t %lu\t %p\t \n", name, size, host_ptr);
  }
  int handle = aocl_mmd_open(name);
  Device *dev = device_manager.device_from_handle(handle);
  if (dev) {
    return dev->shared_mem_prepare_buffer(size, host_ptr);
  } else {
    fprintf(stderr, "aocl_mmd_shared_mem_alloc FAILED getting device\n");
  }
}

AOCL_MMD_CALL void aocl_mmd_shared_mem_release_buffer(const char *name,
                                                      void *host_ptr) {
  DCP_DEBUG_MEM("\n- aocl_mmd_shared_mem_release_buffer: %s\t %p\t \n", name,
                host_ptr);
  if(std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : aocl_mmd_shared_mem_release_buffer: %s\t %p\t \n", name, host_ptr);
  }
  int handle = aocl_mmd_open(name);
  Device *dev = device_manager.device_from_handle(handle);
  if (dev) {
    return dev->shared_mem_release_buffer(host_ptr);
  } else {
    fprintf(stderr, "aocl_mmd_shared_mem_alloc FAILED getting device\n");
  }
}

static void unpin_all_mem_for_handle(int handle) {
  if(std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : Trying to unpin all memory allocations for handle : %d \n", handle);
  }
  Device *dev = device_manager.device_from_handle(handle);

  if (dev == NULL) {
    if(std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : No device found for handle : %d \n", handle);
    }  
    return;
  }

  for (auto mem_it = mem_to_handles_map.begin();
       mem_it != mem_to_handles_map.end(); ++mem_it) {
    if (find(mem_it->second.second.get()->begin(),
             mem_it->second.second.get()->end(),
             handle) != mem_it->second.second.get()->end()) {
      void *addr = mem_it->first;
      dev->free_prepinned_mem(addr);
      if(std::getenv("MMD_ENABLE_DEBUG")){
        DEBUG_LOG("DEBUG LOG : Unpinned addr : %p for handle : %d \n", addr,handle);
      }
    }
  }
  if(std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : Done unpinning all memory allocations for handle : %d \n", handle);
  }
}

static int repin_all_mem_for_handle(int handle) {
  if(std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : Trying to repin all memory allocations for handle : %d \n", handle);
  }
  Device *dev = device_manager.device_from_handle(handle);

  if (dev == NULL) {
    if(std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : No device found for handle : %d \n", handle);
    }
    return MMD_AOCL_ERR;
  }

  for (auto mem_it = mem_to_handles_map.begin();
       mem_it != mem_to_handles_map.end(); ++mem_it) {
    if (find(mem_it->second.second.get()->begin(),
             mem_it->second.second.get()->end(),
             handle) != mem_it->second.second.get()->end()) {
      void *addr = mem_it->first;
      if (dev->pin_alloc(&addr, mem_it->second.first) == nullptr) {
        if(std::getenv("MMD_ENABLE_DEBUG")){
          DEBUG_LOG("DEBUG LOG : ERROR Re-pinning addr : %p for handle : %d \n", addr, handle);
        }  
        return MMD_AOCL_ERR;
      } else {
        if(std::getenv("MMD_ENABLE_DEBUG")){
          DEBUG_LOG("DEBUG LOG : Re-pinned addr : %p for handle : %d \n", addr,handle);
        }  
      }
    }
  }

  if(std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : Done Re-pinning all memory allocations for handle : %d \n", handle);
  }

  return 0;
}

static int program_aocx(int handle, void *data, size_t data_size) {
  Device *afu = device_manager.device_from_handle(handle);
  if (afu == NULL) {
    if(std::getenv("MMD_PROGRAM_DEBUG")){
      DEBUG_LOG("DEBUG LOG : aocl_mmd_program: invalid handle: %d\n", handle);
    } 
    LOG_ERR("aocl_mmd_program: invalid handle: %d\n", handle);
    return MMD_AOCL_ERR;
  }

  if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_DMA_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : Opening file from memory using pkg editor acl_pkg_open_file_from_memory()\n");
  }
  struct acl_pkg_file *pkg = acl_pkg_open_file_from_memory(
      (char *)data, data_size, ACL_PKG_SHOW_ERROR);
  struct acl_pkg_file *fpga_bin_pkg = NULL;
  struct acl_pkg_file *search_pkg = pkg;
  if(pkg == NULL){
    if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_DMA_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : Cannot open file from memory using pkg editor.\n");
    }
  }
  ACL_DCP_ERROR_IF(pkg == NULL, return MMD_AOCL_ERR,
                   "cannot open file from memory using pkg editor.\n");

  // extract bin file from aocx
  size_t fpga_bin_len = 0;
  char *fpga_bin_contents = NULL;
  if (acl_pkg_section_exists(pkg, ACL_PKG_SECTION_FPGA_BIN, &fpga_bin_len) &&
      acl_pkg_read_section_transient(pkg, ACL_PKG_SECTION_FPGA_BIN,
                                     &fpga_bin_contents)) {
    fpga_bin_pkg = acl_pkg_open_file_from_memory(
        (char *)fpga_bin_contents, fpga_bin_len, ACL_PKG_SHOW_ERROR);
    search_pkg = fpga_bin_pkg;
    if(search_pkg != NULL){
      if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_DMA_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
        DEBUG_LOG("DEBUG LOG : Extracted bin from aocx.\n");
      }
    } else {
      if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_DMA_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
        DEBUG_LOG("DEBUG LOG : Failed to extract bin from aocx.\n");
      }
      ACL_DCP_ERROR_IF(search_pkg == NULL, return MMD_AOCL_ERR,
                   "Failed to extract bin from aocx.\n");
    }
  } else {
    if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_DMA_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
        DEBUG_LOG("DEBUG LOG : aocx file does not contain .bin section.\n");
    }
    ACL_DCP_ERROR_IF(search_pkg == NULL, return MMD_AOCL_ERR,
                   "aocx file does not contain .bin section.\n");
  }

  // load compressed gbs
  size_t acl_gbs_gz_len = 0;
  char *acl_gbs_gz_contents = NULL;
  if (acl_pkg_section_exists(search_pkg, ACL_PKG_SECTION_DCP_GBS_GZ,
                             &acl_gbs_gz_len) &&
      acl_pkg_read_section_transient(search_pkg, ACL_PKG_SECTION_DCP_GBS_GZ,
                                     &acl_gbs_gz_contents)) {
    void *gbs_data = NULL;
    size_t gbs_data_size = 0;
    int ret =
        inf(acl_gbs_gz_contents, acl_gbs_gz_len, &gbs_data, &gbs_data_size);

    if (ret != Z_OK) {
      LOG_ERR("aocl_mmd_program error: GBS decompression FAILED!\n");
      if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_DMA_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
        DEBUG_LOG("DEBUG LOG : aocl_mmd_program error: GBS decompression FAILED!\n"); 
      }
      free(gbs_data);
      return MMD_AOCL_ERR;
    } else {
      if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_DMA_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
        DEBUG_LOG("DEBUG LOG : aocl_mmd_program : GBS decompression PASSED!\n"); 
      }  
    }

    int res = 0;
    try {
      res = afu->program_bitstream(static_cast<uint8_t *>(gbs_data),
                                   gbs_data_size);
    } catch (const std::exception &e) {
      std::cerr << "Error programming bitstream: " << e.what();
    }

    free(gbs_data);

    if (pkg) {
      acl_pkg_close_file(pkg);
    }
    if (fpga_bin_pkg) {
      acl_pkg_close_file(fpga_bin_pkg);
    }

    if (res == 0) {
      return handle;
    }
  } else {
    if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_DMA_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : aocl_mmd_program : .bin file does not contain gbs section !\n"); 
    } 
  }

  return MMD_AOCL_ERR;
}

AOCL_MMD_CALL int aocl_mmd_program(int handle, void *user_data, size_t size,
                                   aocl_mmd_program_mode_t program_mode) {
  if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_DMA_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : Entering MMD API aocl_mmd_program()\n");
  }
  if ((program_mode & AOCL_MMD_PROGRAM_PRESERVE_GLOBAL_MEM) ==
      AOCL_MMD_PROGRAM_PRESERVE_GLOBAL_MEM) {
    unpin_all_mem_for_handle(handle);
    if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_DMA_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : Unpinned memory allocated through MMD memory allocation APIs (if any) before programming bitstream\n");
      DEBUG_LOG("DEBUG LOG : We store MMD memory allocations in a data structure , which we used to determine the Unpin list\n");
    }
    int status = program_aocx(handle, user_data, size);
    if (status != MMD_AOCL_ERR) {
      if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_DMA_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
        DEBUG_LOG("DEBUG LOG : Programmed aocx successfully \n"); 
      } 
      if (repin_all_mem_for_handle(handle) == MMD_AOCL_ERR) {
        if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_DMA_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
          DEBUG_LOG("DEBUG LOG : Error: FAILED to re-pin all memory after program\n");
        }
      } else {
        if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_DMA_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
          DEBUG_LOG("DEBUG LOG : Re-pinned memory(if any was unpinned) which we had unpinned before programming bitstream\n");
          DEBUG_LOG("DEBUG LOG : We store MMD memory allocations in a data structure , which we used to determine the Re-pin list\n");
        }
      }
    } else {
      if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_DMA_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
        DEBUG_LOG("DEBUG LOG : Programming aocx FAILED \n"); 
      }
    }
    return status;
  } else {
    if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_DMA_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : Error: memory unpreserved programming not supported\n");
    }
    return MMD_AOCL_ERR;
  }
}

int AOCL_MMD_CALL aocl_mmd_yield(int handle) {
  DEBUG_PRINT("* Called: aocl_mmd_yield\n");
  if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_DMA_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : * Called: aocl_mmd_yield\n");
  }
  Device *dev = device_manager.device_from_handle(handle);
  if (dev) {
    return dev->yield();
  }
  return 0;
}

// Macros used for acol_mmd_get_offline_info and aocl_mmd_get_info
#define RESULT_INT(X)                                                          \
  {                                                                            \
    *((int *)param_value) = X;                                                 \
    if (param_size_ret)                                                        \
      *param_size_ret = sizeof(int);                                           \
  }
#define RESULT_SIZE_T(X)                                                       \
  {                                                                            \
    *((size_t *)param_value) = X;                                              \
    if (param_size_ret)                                                        \
      *param_size_ret = sizeof(size_t);                                        \
  }

#define RESULT_STR(X)                                                          \
  do {                                                                         \
    unsigned Xlen = strnlen(X, 4096) + 1;                                      \
    unsigned Xcpylen = (param_value_size <= Xlen) ? param_value_size : Xlen;   \
    memcpy((void *)param_value, X, Xcpylen);          \
    if (param_size_ret)                                                        \
      *param_size_ret = Xcpylen;                                               \
  } while (0)

int aocl_mmd_get_offline_info(aocl_mmd_offline_info_t requested_info_id,
                              size_t param_value_size, void *param_value,
                              size_t *param_size_ret) {
  // aocl_mmd_get_offline_info can be called many times by the runtime
  // and it is expensive to query the system.  Only compute values first
  // time aocl_mmd_get_offline_info called future iterations use saved results
  static bool initialized = false;
  static int mem_type_info;
  static unsigned int num_acl_boards;
  static std::string boards;
  static bool success;

  if (!initialized) {
    mem_type_info = (int)AOCL_MMD_PHYSICAL_MEMORY;
    if (get_offline_num_acl_boards(SVM_OCL_BSP_AFU_ID) > 0) {
      mem_type_info |= (int)AOCL_MMD_SVM_COARSE_GRAIN_BUFFER;
    }
    num_acl_boards = get_offline_num_acl_boards(SVM_OCL_BSP_AFU_ID) +
                     get_offline_num_acl_boards(PCI_OCL_BSP_AFU_ID);
    success = get_offline_board_names(boards, true);
    initialized = true;
  }

  switch (requested_info_id) {
  case AOCL_MMD_VERSION:
    RESULT_STR(AOCL_MMD_VERSION_STRING);
    break;
  case AOCL_MMD_NUM_BOARDS: {
    if (num_acl_boards >= 0) {
      RESULT_INT(num_acl_boards);
    } else {
      return MMD_AOCL_ERR;
    }
    break;
  }
  case AOCL_MMD_VENDOR_NAME:
    RESULT_STR("Intel Corp");
    break;
  case AOCL_MMD_BOARD_NAMES: {
    if (success) {
      RESULT_STR(boards.c_str());
    } else {
      return MMD_AOCL_ERR;
    }
    break;
  }
  case AOCL_MMD_VENDOR_ID:
    RESULT_INT(0);
    break;
  case AOCL_MMD_USES_YIELD:
    RESULT_INT(KernelInterrupt::yield_is_enabled());
    break;
  case AOCL_MMD_MEM_TYPES_SUPPORTED:
    RESULT_INT(mem_type_info);
    break;
  }

  return 0;
}

int mmd_get_offline_board_names(size_t param_value_size, void *param_value,
                                     size_t *param_size_ret) {
  std::string boards;
  bool success = get_offline_board_names(boards, false);
  if (success) {
    RESULT_STR(boards.c_str());
  } else {
    RESULT_INT(-1);
  }

  return 0;
}

int aocl_mmd_get_info(int handle, aocl_mmd_info_t requested_info_id,
                      size_t param_value_size, void *param_value,
                      size_t *param_size_ret) {
  DEBUG_PRINT("called aocl_mmd_get_info\n");
  if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_DMA_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : called aocl_mmd_get_info\n");
  }
  Device *dev = device_manager.device_from_handle(handle);
  if (dev == NULL)
    return 0;

  assert(param_value);
  switch (requested_info_id) {
  case AOCL_MMD_BOARD_NAME: {
    std::ostringstream board_name;
    board_name << "Intel OFS Platform"
               << " (" << dev->get_dev_name() << ")";
    RESULT_STR(board_name.str().c_str());
    break;
  }
  case AOCL_MMD_NUM_KERNEL_INTERFACES:
    RESULT_INT(1);
    break;
  case AOCL_MMD_KERNEL_INTERFACES:
    RESULT_INT(AOCL_MMD_KERNEL);
    break;
#ifdef SIM
  case AOCL_MMD_PLL_INTERFACES:
    RESULT_INT(-1);
    break;
#else
  case AOCL_MMD_PLL_INTERFACES:
    RESULT_INT(-1);
    break;
#endif
  case AOCL_MMD_MEMORY_INTERFACE:
    RESULT_INT(AOCL_MMD_MEMORY);
    break;
  case AOCL_MMD_PCIE_INFO: {
    RESULT_STR(dev->get_bdf().c_str());
    break;
  }
  case AOCL_MMD_BOARD_UNIQUE_ID:
    RESULT_INT(0);
    break;
  case AOCL_MMD_TEMPERATURE: {
    if (param_value_size == sizeof(float)) {
      float *ptr = static_cast<float *>(param_value);
      *ptr = dev->get_temperature();
      if (param_size_ret)
        *param_size_ret = sizeof(float);
    }
    break;
  }
  case AOCL_MMD_CONCURRENT_READS:
    RESULT_INT(1);
    break;
  case AOCL_MMD_CONCURRENT_WRITES:
    RESULT_INT(1);
    break;
  case AOCL_MMD_CONCURRENT_READS_OR_WRITES:
    RESULT_INT(2);
    break;

  case AOCL_MMD_MIN_HOST_MEMORY_ALIGNMENT:
    RESULT_SIZE_T(64);
    break;

  case AOCL_MMD_HOST_MEM_CAPABILITIES: {
    if (dev->get_mem_capability_support()) {
      RESULT_INT(AOCL_MMD_MEM_CAPABILITY_SUPPORTED);
    } else {
      RESULT_INT(0);
    }
    break;
  }

  case AOCL_MMD_SHARED_MEM_CAPABILITIES: {
    if (dev->get_mem_capability_support()) {
      RESULT_INT(AOCL_MMD_MEM_CAPABILITY_SUPPORTED);
    } else {
      RESULT_INT(0);
    }
    break;
  }

  case AOCL_MMD_DEVICE_MEM_CAPABILITIES:
    RESULT_INT(0);
    break;
  case AOCL_MMD_HOST_MEM_CONCURRENT_GRANULARITY:
    RESULT_SIZE_T(0);
    break;
  case AOCL_MMD_SHARED_MEM_CONCURRENT_GRANULARITY:
    RESULT_SIZE_T(0);
    break;
  case AOCL_MMD_DEVICE_MEM_CONCURRENT_GRANULARITY:
    RESULT_SIZE_T(0);
    break;
  }
  return 0;
}

#undef RESULT_INT
#undef RESULT_STR

int AOCL_MMD_CALL aocl_mmd_set_interrupt_handler(
    int handle, aocl_mmd_interrupt_handler_fn fn, void *user_data) {
  Device *dev = device_manager.device_from_handle(handle);
  if (dev) {
    dev->set_kernel_interrupt(fn, user_data);
    if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_DMA_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : Set kernel interrupt handler for device handle : %d\n", handle);
    }
  } else {
    if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_DMA_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : Error setting kernel interrupt handler for device handle : %d\n", handle);
    }
    return MMD_AOCL_ERR;
  }
  return 0;
}

int AOCL_MMD_CALL aocl_mmd_set_status_handler(int handle,
                                              aocl_mmd_status_handler_fn fn,
                                              void *user_data) {
  Device *dev = device_manager.device_from_handle(handle);
  if (dev) {
    dev->set_status_handler(fn, user_data);
    if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_DMA_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : Set status handler for device handle : %d\n", handle);
    }
  }
  // TODO: handle error condition if dev null
  return 0;
}

// Host to device-global-memory write
int AOCL_MMD_CALL aocl_mmd_write(int handle, aocl_mmd_op_t op, size_t len,
                                 const void *src, int mmd_interface,
                                 size_t offset) {
  DCP_DEBUG_MEM("\n- aocl_mmd_write: %d\t %p\t %lu\t %p\t %d\t %lu\n", handle,
                op, len, src, mmd_interface, offset);
  if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_DMA_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : aocl_mmd_write: handle : %d\t operation : %p\t len : 0x%zx\t src : %p\t mmd_interface : %d\t offset : 0x%zx\n", handle,op, len, src, mmd_interface, offset );
  }
  Device *dev = device_manager.device_from_handle(handle);
  if (dev)
    return dev->write_block(op, mmd_interface, src, offset, len);
  else {
    if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_DMA_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : Error in aocl_mmd_write , device not found for handle : %d\n", handle);
    }
    return -1;
  }
}

int AOCL_MMD_CALL aocl_mmd_read(int handle, aocl_mmd_op_t op, size_t len,
                                void *dst, int mmd_interface, size_t offset) {
  DCP_DEBUG_MEM("\n+ aocl_mmd_read: %d\t %p\t %lu\t %p\t %d\t %lu\n", handle,
                op, len, dst, mmd_interface, offset);
  if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_DMA_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : aocl_mmd_read: handle : %d\t operation : %p\t len : 0x%zx\t dst : %p\t mmd_interface : %d\t offset : 0x%zx\n", handle,op, len, dst, mmd_interface, offset );
  }
  Device *dev = device_manager.device_from_handle(handle);
  if (dev)
    return dev->read_block(op, mmd_interface, dst, offset, len);
  else {
    if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_DMA_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : Error in aocl_mmd_read , device not found for handle : %d\n", handle);
    }
    return -1;
  }
}

int AOCL_MMD_CALL aocl_mmd_copy(int handle, aocl_mmd_op_t op, size_t len,
                                int mmd_interface, size_t src_offset,
                                size_t dst_offset) {
  DCP_DEBUG_MEM("\n+ aocl_mmd_copy: %d\t %p\t %lu\t %d\t %lu %lu\n", handle, op,
                len, mmd_interface, src_offset, dst_offset);
  if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_DMA_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : aocl_mmd_copy: handle : %d\t operation : %p\t len : 0x%zx\t mmd_interface : %d\t src_offset : 0x%zx dst_offset : 0x%zx\n", handle,op, len, mmd_interface, src_offset, dst_offset );
  }
  Device *dev = device_manager.device_from_handle(handle);
  if (dev)
    return dev->copy_block(op, mmd_interface, src_offset, dst_offset, len);
  else {
    if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_DMA_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : Error in aocl_mmd_copy , device not found for handle : %d\n", handle);
    }
  }
    return MMD_AOCL_ERR;
}

int AOCL_MMD_CALL aocl_mmd_open(const char *name) {
  DEBUG_PRINT("Opening device: %s\n", name);
  if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_DMA_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : aocl_mmd_open, Opening device: %s\n", name );
  }

  uint64_t obj_id = device_manager.id_from_name(name);
  if (!obj_id) {
    if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_DMA_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : Error while aocl_mmd_open, object id not found for board : %s\n", name );
    }
    return MMD_INVALID_PARAM;
  }

  int handle;
  Device *dev = nullptr;
  if (device_manager.get_or_create_device(name, &handle, &dev) !=
      DeviceMapManager::SUCCESS) {
    if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_DMA_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : Error while aocl_mmd_open, device not found for board : %s\n", name );
    }
    return MMD_AOCL_ERR;
  }

  assert(dev);
  if (dev->bsp_loaded()) {
    if (!dev->initialize_bsp()) {
      LOG_ERR("Error initializing bsp\n");
      if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_DMA_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
        DEBUG_LOG("DEBUG LOG : Error while aocl_mmd_open, Error initializing bsp for board : %s\n", name );
      }
      return MMD_BSP_INIT_FAILED;
    }
  } else {
    if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_DMA_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : Error while aocl_mmd_open, bsp not loaded for board : %s\n", name );
    }
    return MMD_BSP_NOT_LOADED;
  }
  DEBUG_PRINT("end of aocl_mmd_open \n");
  if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_DMA_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : Success aocl_mmd_open for board : %s, handle : %d \n", name, handle );
  }
  return handle;
}

int AOCL_MMD_CALL aocl_mmd_close(int handle) {
  #ifndef SIM
    device_manager.close_device_if_exists(handle);
  #else
    std::cout << "# mmd.cpp: During simulation (ASE) we are not closing the device.\n";
  #endif
  return 0;
}

AOCL_MMD_CALL void *aocl_mmd_host_alloc(int *handles, size_t num_devices,
                                        size_t size, size_t alignment,
                                        aocl_mmd_mem_properties_t *properties,
                                        int *error) {
  if (num_devices == 0 || handles == nullptr) {
    if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_DMA_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : aocl_mmd_host_alloc - number of device =0 or handles = nullptr \n");
    }
    if (error) {
      if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_DMA_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
        DEBUG_LOG("DEBUG LOG : aocl_mmd_host_alloc - error invalid handle \n" );
      }
      *error = AOCL_MMD_ERROR_INVALID_HANDLE;
    } else {
      if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_DMA_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
        DEBUG_LOG("DEBUG LOG : aocl_mmd_host_alloc - returning nullptr \n" );
      }
    }
    return nullptr;
  }

  /* checking that alignment is power of 2
     for now if user specifies alignment more than 2M it will be flagged as
     error, since max page size used is 2M currently if user specifies
     allocation_size <= 4K and alignment of 2M , address returned might not be
     aligned to 2M but will definetely be aligned to 4K it might be possible to
     support higher alignments in future
  */
  const int page_2M = 1 << 21;
  if ((alignment > page_2M) || ((alignment & (alignment - 1)) != 0)) {
    if (error) {
      if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_DMA_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
        DEBUG_LOG("DEBUG LOG : aocl_mmd_host_alloc - UNSUPPORTED_ALIGNMENT \n" );
      }
      *error = AOCL_MMD_ERROR_UNSUPPORTED_ALIGNMENT;
    } else {
      if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_DMA_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
        DEBUG_LOG("DEBUG LOG : aocl_mmd_host_alloc -  returning nullptr\n" );
      }
    }
    return nullptr;
  }

  if ((properties != nullptr) &&
      (*(properties) != AOCL_MMD_MEM_PROPERTIES_GLOBAL_MEMORY) &&
      (*(properties) != AOCL_MMD_MEM_PROPERTIES_MEMORY_BANK)) {
    if (error) {
      if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_DMA_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
        DEBUG_LOG("DEBUG LOG : aocl_mmd_host_alloc - UNSUPPORTED_PROPERTY \n" );
      }
      *error = AOCL_MMD_ERROR_UNSUPPORTED_PROPERTY;
    } else {
      if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_DMA_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
        DEBUG_LOG("DEBUG LOG : aocl_mmd_host_alloc - returning nullptr \n" );
      }
    }
    return nullptr;
  }

  // error if size specified is <= 0
  if (size == 0) {
    if (error) {
      if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_DMA_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
        DEBUG_LOG("DEBUG LOG : aocl_mmd_host_alloc - ERROR_OUT_OF_MEMORY \n" );
      }
      *error = AOCL_MMD_ERROR_OUT_OF_MEMORY;
    } else {
      if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_DMA_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
        DEBUG_LOG("DEBUG LOG : aocl_mmd_host_alloc - returning nullptr \n" );
      }
    } 
    return nullptr;
  }

  auto mmd_dev_handles =
      std::unique_ptr<std::vector<int>>(new std::vector<int>());
  for (unsigned int i = 0; i < num_devices; i++) {
    Device *dev = device_manager.device_from_handle(handles[i]);
    if (dev) {
      mmd_dev_handles->push_back(handles[i]);
    } else {
      if (error) {
        if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_DMA_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
          DEBUG_LOG("DEBUG LOG : aocl_mmd_host_alloc - ERROR_INVALID_HANDLE \n" );
        }
        *error = AOCL_MMD_ERROR_INVALID_HANDLE;
      } else {
        if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_DMA_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
          DEBUG_LOG("DEBUG LOG : aocl_mmd_host_alloc - returning nullptr \n" );
        }
      }
      return nullptr;
    }
  }

  const int prot = PROT_READ | PROT_WRITE;

#ifdef SIM
  int flags = MAP_ANON | MAP_PRIVATE;
#else
  int flags = MAP_ANONYMOUS | MAP_PRIVATE | MAP_LOCKED;
#endif

  const int page_4K = 1 << 12;
  if (size > page_4K) { // if allocation size > 4K use hugepages
    flags |= MAP_HUGETLB | MAP_HUGE_2MB;
    if (size % page_2M) {
      size += (page_2M - (size % page_2M));
    }
  } else {
    if (size % page_4K) {
      size += (page_4K - (size % page_4K));
    }
  }

  if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_DMA_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : aocl_mmd_host_alloc - allocating memory using mmap() \n" );
  }
  void *addr = mmap(nullptr, size, prot, flags, -1, 0);
  if (addr == MAP_FAILED && errno == ENOMEM) {

#ifdef SIM
    flags = MAP_ANONYMOUS | MAP_PRIVATE;
#else
    flags = MAP_ANONYMOUS | MAP_PRIVATE | MAP_LOCKED;
#endif
    addr = mmap(nullptr, size, prot, flags, -1, 0);
    if (addr != MAP_FAILED) {
      fprintf(
          stderr,
          "Warning allocation with 2M pages failed, using 4K pages instead\n");
    }
  }

  DEBUG_PRINT("aocl mmd alloc: mmap: %p, %zu\n", addr, size);
  if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_DMA_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : aocl_mmd_host_alloc - mmap() : %p, %zu \n", addr, size );
  }

  if (addr == MAP_FAILED) {
    LOG_ERR("aocl mmd alloc failed: %s\n", strerror(errno));
    if (error) {
      if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_DMA_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
        DEBUG_LOG("DEBUG LOG : aocl_mmd_host_alloc -  ERROR_OUT_OF_MEMORY\n" );
      }
      *error = AOCL_MMD_ERROR_OUT_OF_MEMORY;
    } else {
      if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_DMA_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
        DEBUG_LOG("DEBUG LOG : aocl_mmd_host_alloc -  returning nullptr\n" );
      }
    }
    return nullptr;
  }

  for (auto handle : *mmd_dev_handles) {
    // TODO: need to add a cleanup step in case this operation fails
    Device *dev = device_manager.device_from_handle(handle);
    if (dev != nullptr && dev->pin_alloc(&addr, size) == nullptr) {
      if (error) {
        if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_DMA_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
          DEBUG_LOG("DEBUG LOG : aocl_mmd_host_alloc -  ERROR_OUT_OF_MEMORY\n" );
        }
        *error = AOCL_MMD_ERROR_OUT_OF_MEMORY;
      } else {
        if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_DMA_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
          DEBUG_LOG("DEBUG LOG : aocl_mmd_host_alloc -  returning nullptr\n" );
        }
      }
      return nullptr;
    }
  }

  mem_to_handles_map[addr] = std::make_pair(size, std::move(mmd_dev_handles));
  if (error) {
    *error = AOCL_MMD_ERROR_SUCCESS;
  }
  if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_DMA_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : aocl_mmd_host_alloc - Exiting with SUCCESS  \n" );
  }
  return addr;
}

AOCL_MMD_CALL int aocl_mmd_free(void *mem) {

  // TODO: check on return code in case of freeing null
  if (mem == nullptr) {
    if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_DMA_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : ERROR aocl_mmd_free - trying to free nullptr\n" );
    }
    return 0;
  }

  auto handle_iter = mem_to_handles_map.find(mem);
  if (handle_iter == mem_to_handles_map.end()) {
    // TODO: more rigorous error handling
    if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_DMA_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : ERROR aocl_mmd_free - address to free not found in datastructure mem_to_handles_map \n" );
    }
    return -1;
  }

  auto mmd_dev_handles = std::move(handle_iter->second.second);

  int rc = 0;
  for (auto handle : *mmd_dev_handles) {
    Device *dev = device_manager.device_from_handle(handle);
    if (dev) {
      dev->free_prepinned_mem(mem);
      if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_DMA_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
        DEBUG_LOG("DEBUG LOG : aocl_mmd_free - freeing pinned mem at address %p \n", mem );
      }
    } else {
      if(std::getenv("MMD_PROGRAM_DEBUG")){
        DEBUG_LOG("DEBUG LOG : ERROR aocl_mmd_free - device not found for handle : %d \n", handle );
      }
      rc = -1;
    }
  }
  DEBUG_PRINT("aocl_mmd_free: munmap: %p %zu\n", mem,
              handle_iter->second.first);
  if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_DMA_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : aocl_mmd_free: munmap: %p %zu\n" ,mem, handle_iter->second.first );
  }
  rc = munmap(mem, handle_iter->second.first);
  if (rc < 0) {
    if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_DMA_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : aocl_mmd_free: munmap FAILED\n");
    }
    perror("munmap failed");
  }
  mem_to_handles_map.erase(handle_iter);
  if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_DMA_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : aocl_mmd_free: munmap SUCCESS, freed memory allocated at address : %p\n", mem);
  }
  return rc;
}

int mmd_get_handle(const char *name) {

  int handle;
  Device *dev = nullptr;
  if (device_manager.get_or_create_device(name, &handle, &dev) !=
      DeviceMapManager::SUCCESS) {
    if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_DMA_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG :mmd_get_handle FAILED for board name : %s\n", name);
    }
    return MMD_AOCL_ERR;
  } else {
    if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_DMA_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG :mmd_get_handle PASSED for board name : %s\n", name);
    }
    return handle;
  }
}

AOCL_MMD_CALL void *aocl_mmd_shared_alloc(int handle, size_t size,
                                          size_t alignment,
                                          aocl_mmd_mem_properties_t *properties,
                                          int *error) {

  // num_devices is limited to 1;
  // parameter checking is being done within aocl_mmd_host_alloc() call

  /* Shared allocation commited for oneAPI beta09 USM only needs to be able to
     allocate on host, not on device. So we can use aocl_mmd_host_alloc()_API
     under the hood.
  */
  if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_DMA_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : In aocl_mmd_shared_alloc which uses aocl_mmd_host_alloc underthehood\n");
  }
  void *return_value =
      aocl_mmd_host_alloc(&handle, 1, size, alignment, properties, error);
  if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_DMA_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : Exiting aocl_mmd_shared_alloc\n");
  }
  return return_value;
}

AOCL_MMD_CALL int aocl_mmd_shared_migrate(int handle, void *shared_ptr,
                                          size_t size,
                                          aocl_mmd_migrate_t destination) {

  /*aocl_mmd_shared_migrate API is being used for completeness but not doing any
    work other than validating API params. Since shared allocation is always
    allocated on host no migration needs to be done between device and host. In
    the future a fully functioning aocl_mmd_shared_alloc() API may be
    implemented with memory being allocated on the device and migrated between
    host and device.
  */
  DEBUG_PRINT(
      "aocl_mmd_shared_migrate API is being used for completeness but not "
      "doing any work other than validating API params.\nSince shared "
      "allocation is always allocated on host no migration needs to be done "
      "between device and host.\nIn the future a fully functioning "
      "aocl_mmd_shared_alloc() API may be implemented with memory being "
      "allocated on the device and migrated between host and device");

  if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_DMA_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : aocl_mmd_shared_migrate API is being used for completeness but not "
      "doing any work other than validating API params.\nSince shared "
      "allocation is always allocated on host no migration needs to be done "
      "between device and host.\nIn the future a fully functioning "
      "aocl_mmd_shared_alloc() API may be implemented with memory being "
      "allocated on the device and migrated between host and device"); 
  }

  // validating 'handle' param
  if (!device_manager.device_from_handle(handle)) {
    if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_DMA_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : aocl_mmd_shared_migrate ERROR_INVALID_HANDLE\n");
    }
    return AOCL_MMD_ERROR_INVALID_HANDLE;
  }

  // validating 'size' param
  const int page_4K = 1 << 12;
  const int page_2M = 1 << 21;

  // error if size specified is <= 0
  if (size == 0) {
    if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_DMA_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : aocl_mmd_shared_migrate ERROR_INVALID_MIGRATION_SIZE for handle : %d\n", handle);
    }
    return AOCL_MMD_ERROR_INVALID_MIGRATION_SIZE;
  }

  if ((size % page_4K != 0) && (size % page_2M != 0)) {
    if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_DMA_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : aocl_mmd_shared_migrate ERROR_INVALID_MIGRATION_SIZE for handle : %d\n", handle);
    }
    return AOCL_MMD_ERROR_INVALID_MIGRATION_SIZE;
  }

  // validating 'shared_ptr' param
  auto handle_iter = mem_to_handles_map.find(shared_ptr);
  if (handle_iter == mem_to_handles_map.end()) {
    if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_DMA_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : aocl_mmd_shared_migrate ERROR_INVALID_POINTER for handle : %d\n", handle);
    }
    return AOCL_MMD_ERROR_INVALID_POINTER;
  }

  if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_DMA_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : Exiting aocl_mmd_shared_migrate for handle : %d \n", handle);
  }
  return 0;
}
