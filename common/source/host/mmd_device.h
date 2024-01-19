// Copyright 2022 Intel Corporation
// SPDX-License-Identifier: MIT

#ifndef MMD_DEVICE_H
#define MMD_DEVICE_H

#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <string>

#include <opae/fpga.h>
#include <opae/mpf/mpf.h>
#include <uuid/uuid.h>

#include "aocl_mmd.h"
#include "kernel_interrupt.h"
#include "mmd_dma.h"
#include "pkg_editor.h"
#include "mmd_iopipes.h"

// Tune delay for simulation or HW. Eventually delay
// should be removed for HW, may still be needed for ASE simulation
#ifdef SIM
#define DELAY_MULTIPLIER 100
#else
#define DELAY_MULTIPLIER 1
#endif

// Most AOCL_MMD_CALL functions return negative number in case of error,
// MMD_AOCL_ERR is used to indicate an error from the MMD that is being
// returned to the runtime.  Simply set to -2 for now since neither interface
// defines a meaning to return codes for errors.
#define MMD_AOCL_ERR -1

// NOTE: some of the code relies on invalid handle returning -1
// future TODO eliminate dependency on specific error values
#define MMD_INVALID_PARAM -1

// Our diagnostic script relies on handle values < -1 to determine when
// a valid device is present but a functioning ASP is not loaded.
#define MMD_ASP_NOT_LOADED -2
#define MMD_ASP_INIT_FAILED -3

// Delay settings
// TODO: Figure out why these delays are needed and
// have requirement removed (at least for HW)
#define MMIO_DELAY()
#define YIELD_DELAY() usleep(1 * DELAY_MULTIPLIER)
#define OPENCL_SW_RESET_DELAY() usleep(5000 * DELAY_MULTIPLIER)
#define AFU_RESET_DELAY() usleep(20000 * DELAY_MULTIPLIER)

#define KERNEL_SW_RESET_BASE (AOCL_MMD_KERNEL + 0x30)

#define MMD_COPY_BUFFER_SIZE (2 * 1024 * 1024)

// Below is GUID for DMA
#define DMA_BBB_GUID   "BC24AD4F-8738-F840-575F-BAB5B61A8DAE"
#define IOPIPES_GUID "9c8560c5-729f-f873-966d-1f07871d4396"

#define NULL_DFH_BBB_GUID "da1182b1-b344-4e23-90fe-6aab12a0132f"

#define ASP_NAME "ofs_"

#define SVM_MMD_MPF 0x24000

// LOG ERRORS
//#define MMD_ERR_LOGGING
#ifdef MMD_ERR_LOGGING
#define LOG_ERR(...) fprintf(stderr, __VA_ARGS__)
#else
#define LOG_ERR(...)
#endif

// debugging
//#define DEBUG
#ifdef DEBUG
#define DEBUG_PRINT(...) fprintf(stderr, __VA_ARGS__)
#else
#define DEBUG_PRINT(...)
#endif

#ifdef DEBUG_MEM
#define DCP_DEBUG_MEM(...) fprintf(stderr, __VA_ARGS__)
#else
#define DCP_DEBUG_MEM(...)
#endif

#define DEBUG_LOG(...) fprintf(stderr, __VA_ARGS__)

#define SVM_DDR_OFFSET 0x1000000000000
#define PCI_DDR_OFFSET 0

enum {
  AOCL_IRQ_POLLING_BASE = 0x0100, // CSR to polling interrupt status
  AOCL_IRQ_MASKING_BASE = 0x0108, // CSR to set/unset interrupt mask
  AOCL_MMD_KERNEL = 0x4000,       /* Control interface into kernel interface */
  AOCL_MMD_MEMORY = 0x100000      /* Data interface to device memory */
};

enum AfuStatu { MMD_INVALID_ID = 0, MMD_ASP, MMD_AFU };

class Device final {
public:
  Device(uint64_t);
  Device(const Device &) = delete;
  Device &operator=(const Device &) = delete;
  ~Device();

  static std::string get_board_name(std::string prefix, uint64_t obj_id);
  static bool parse_board_name(const char *board_name, uint64_t &obj_id);

  int get_mmd_handle() { return mmd_handle; }
  int get_mem_capability_support() { return mem_capability_support; }
  uint64_t get_fpga_obj_id() { return fpga_obj_id; }
  std::string get_dev_name() { return mmd_dev_name; }
  std::string get_bdf();
  float get_temperature();

  int program_bitstream(uint8_t *data, size_t data_size);
  bool initialize_asp();
  void set_kernel_interrupt(aocl_mmd_interrupt_handler_fn fn, void *user_data);
  void set_status_handler(aocl_mmd_status_handler_fn fn, void *user_data);
  int yield();
  void event_update_fn(aocl_mmd_op_t op, int status);
  bool asp_loaded();

  int read_block(aocl_mmd_op_t op, int mmd_interface, void *host_addr,
                 size_t dev_addr, size_t size);

  int write_block(aocl_mmd_op_t op, int mmd_interface, const void *host_addr,
                  size_t dev_addr, size_t size);

  int copy_block(aocl_mmd_op_t op, int mmd_interface, size_t src_offset,
                 size_t dst_offset, size_t size);

  void *pin_alloc(void **addr, size_t size);
  int free_prepinned_mem(void *mem);

  void shared_mem_prepare_buffer(size_t size, void *host_ptr);

  void shared_mem_release_buffer(void *host_ptr);

  void dump_mpf_stats();

private:
  static int next_mmd_handle;

  int mem_capability_support;
  int board_type;
  int mmd_handle;
  uint64_t fpga_obj_id;
  std::string mmd_dev_name;
  intel_opae_mmd::KernelInterrupt *kernel_interrupt_thread;
  aocl_mmd_status_handler_fn event_update;
  void *event_update_user_data;

  // HACK: use the sysfs path to read NUMA node
  // this should be replaced with OPAE call once that is
  // available
  std::string fpga_numa_node;
  bool enable_set_numa;
  bool fme_sysfs_temp_initialized;
  void initialize_fme_sysfs();

  void initialize_local_cpus_sysfs();

  bool find_dma_dfh_offsets();
  bool find_iopipes_dfh_offsets();

  uint8_t bus;
  uint8_t device;
  uint8_t function;

  bool afu_initialized;
  bool asp_initialized;
  bool mmio_is_mapped;

  mpf_handle_t mpf_handle;

  fpga_handle port_handle;
  fpga_properties filter;
  fpga_token port_token;

  fpga_token mmio_token;
  fpga_handle mmio_handle;

  fpga_properties filter_fme;
  fpga_token fme_token;

  fpga_guid guid;
  size_t ddr_offset;
  uint64_t mpf_mmio_offset;
  uint64_t dma_ch0_dfh_offset;
  uint64_t dma_ch1_dfh_offset;
  uint64_t iopipes_dfh_offset;
  intel_opae_mmd::mmd_dma *dma_host_to_fpga;
  intel_opae_mmd::mmd_dma *dma_fpga_to_host;
  intel_opae_mmd::iopipes *io_pipes;

  char *mmd_copy_buffer;

  // Helper functions
  int read_mmio(void *host_addr, size_t dev_addr, size_t size);
  int write_mmio(const void *host_addr, size_t dev_addr, size_t size);
};

#endif // MMD_DEVICE_H
