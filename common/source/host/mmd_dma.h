// Copyright 2022 Intel Corporation
// SPDX-License-Identifier: MIT

#ifndef MMD_DMA_H_
#define MMD_DMA_H_

#include <opae/fpga.h>
#include <opae/mpf/mpf.h>
#include <poll.h>

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <mutex>
#include <queue>
#include <thread>
#include <unordered_map>

#include "aocl_mmd.h"

namespace intel_opae_mmd {

enum class dma_mode { f2h, h2f };

struct dma_work_item {
  aocl_mmd_op_t op;
  void *host_addr;
  uint64_t dev_addr;
  size_t size;
};

class mmd_dma final {
public:
  mmd_dma(fpga_handle fpga_handle_arg, int mmd_handle, mpf_handle_t mpf_handle,
          uint64_t dfh_offset_arg, int interrupt_num_arg, dma_mode mode);
  ~mmd_dma();

  bool initialized() { return m_initialized; }

  int fpga_to_host(aocl_mmd_op_t op, void *host_addr, size_t dev_addr,
                           size_t size);
  int host_to_fpga(aocl_mmd_op_t op, const void *host_addr,
                           size_t dev_addr, size_t size);

  void set_status_handler(aocl_mmd_status_handler_fn fn, void *user_data);

  mmd_dma(mmd_dma &other) = delete;
  mmd_dma &operator=(const mmd_dma &other) = delete;

private:
  // Helper functions
  int enqueue_dma(dma_work_item &item);
  int do_dma(dma_work_item &item);
  void work_thread();
  void event_update_fn(aocl_mmd_op_t op, int status);
  int send_descriptors(uint64_t dma_src_addr, uint64_t dma_dst_addr, uint64_t dma_len);
  void read_status_registers();
  void read_register(uint64_t offset, const char* name);
  int pin_memory(void *addr, size_t len); 
  
  // Member variables
  bool m_initialized;
  dma_mode m_mode;
  std::mutex m_dma_op_mutex;
  aocl_mmd_status_handler_fn m_status_handler_fn;
  void *m_status_handler_user_data;
  fpga_handle m_fpga_handle;
  int m_mmd_handle;
  mpf_handle_t mpf_handle;
  uint64_t dfh_offset;
  int interrupt_num;
  uint64_t max_dma_len;
  std::condition_variable m_dma_notify;
  std::thread *m_thread;
  std::mutex m_work_queue_mutex;
  std::queue<dma_work_item> m_work_queue;
  std::atomic<bool> m_work_thread_active;
  uint64_t threshold;

  std::unordered_map<void *, uint64_t> pinned_mem;
  // CSR variables
  uint64_t dma_csr_src;
  uint64_t dma_csr_dst;
  uint64_t dma_csr_len;
  uint64_t dma_csr_base;
  uint32_t mmio_num;
  const char* op_mode;

  bool wait_fpga_write;
  volatile uint64_t *fpga_write_addr;

  bool wait_interrupt;
  pollfd int_event_fd{0};
  fpga_event_handle event_handle;

  // Buffer
  void *dma_buffer;
  uint64_t transaction_id;
};

}; // namespace intel_opae_mmd

#endif // MMD_DMA_H_
