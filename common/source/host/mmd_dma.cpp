// Copyright 2022 Intel Corporation
// SPDX-License-Identifier: MIT

#include <cassert>
#include <cstdlib>
#include <cstring>
#include <sys/mman.h>
#include <chrono>
#include <iostream>
#include <unordered_map>

#include "mmd_device.h"
#include "mmd_dma.h"

namespace intel_opae_mmd {
const uint64_t KB = 2 << 9;
const uint64_t MB = 2 << 20;

std::mutex pinning_mutex;
std::unordered_map<uint64_t, int> address_mpfprepare_count ={};

// The ASE simulation often runs on systems that do not have permission
// for allocating 2M pages. This results in a lot of extra time spent pinning
// thousands of 4K pages if 2M is used for DMA buffer size. Solution is to
// reduce size to 4K in simuation.
#ifdef SIM
const uint64_t dma_buffer_sz = 4 * KB;
const uint64_t dma_copy_threshold = 4 * KB;
#else
const uint64_t dma_buffer_sz = 2 * MB;
//const uint64_t dma_copy_threshold = 1 * MB;
const uint64_t dma_copy_threshold = 0 * MB;
#endif
static_assert(dma_copy_threshold <= dma_buffer_sz,
              "DMA copy can overflow buffer");

static inline void check_result(fpga_result res, const char *err_str) {
  if (res == FPGA_OK) {
    return;
  }
  std::string opae_err_str = std::string("KernelInterrupt: ") +
                             std::string(err_str) + std::string(": ") +
                             std::string(fpgaErrStr(res));
}

/** mmd_dma class constructor
 *  it initializes various attributes like CSR offsets for DMA
 *  it determines if its s host to foga or fpga to host DMA object
 *  determines if interrupt is used or 'magic number' methodology
 *  create a dma work thread
 *  we use two work threads, one for HOST -> FPGA DMA , one for FPGA -> HOST DMA
 *  hence we create two mmd_dma objects
 */
mmd_dma::mmd_dma(fpga_handle fpga_handle_arg, int mmd_handle,
                 mpf_handle_t mpf_handle_in, uint64_t dfh_offset_arg,
                 int interrupt_num_arg, dma_mode mode)
    : m_initialized(false), m_mode(mode), m_status_handler_fn(nullptr),
      m_status_handler_user_data(nullptr), m_fpga_handle(fpga_handle_arg),
      m_mmd_handle(mmd_handle), mpf_handle(mpf_handle_in),
      dfh_offset(dfh_offset_arg), interrupt_num(interrupt_num_arg),
      m_thread(nullptr), m_work_queue(), m_work_thread_active(true),
      threshold(dma_copy_threshold), mmio_num(0), dma_buffer(nullptr), transaction_id(-1){

  const uint64_t dma_src_offset = 0x0;
  const uint64_t dma_dst_offset = 0x8;
  const uint64_t dma_len_offset = 0x10;
  const uint64_t h2f_offset = 0x80;
  const uint64_t f2h_offset = 0x100;

  switch (m_mode) {
  case dma_mode::f2h:
    dma_csr_base = dfh_offset + f2h_offset;
    wait_fpga_write = true;
    wait_interrupt = false;
    op_mode = "FPGA -> HOST";
    break;
  case dma_mode::h2f:
    dma_csr_base = dfh_offset + h2f_offset;
    wait_fpga_write = false;
    wait_interrupt = true;
    op_mode = "HOST -> FPGA";
  }

  dma_csr_src = dma_csr_base + dma_src_offset;
  dma_csr_dst = dma_csr_base + dma_dst_offset;
  dma_csr_len = dma_csr_base + dma_len_offset;
  fpga_result res;


  char *max_len_env_var = getenv("OFS_OCL_ENV_DMA_MAX_LEN");
  if(max_len_env_var != nullptr && m_mode == dma_mode::f2h) {
    max_dma_len = std::stoull(std::string(max_len_env_var));
    // Require 64 byte alignment
    if ((max_dma_len % 64) != 0) {
      max_dma_len = 0;
    }
  } else {
    max_dma_len = 0;
  }


  if (wait_interrupt) {
    res = fpgaCreateEventHandle(&event_handle);
    check_result(res, "error fpgaCreateEventHandle");
    res = fpgaRegisterEvent(m_fpga_handle, FPGA_EVENT_INTERRUPT, event_handle,
                            interrupt_num);
    check_result(res, "error fpgaRegisterEvent");
    res = fpgaGetOSObjectFromEventHandle(event_handle, &int_event_fd.fd);
    check_result(res, "error fpgaGetOSObjectFromEventHandle");
  } else {
    event_handle = nullptr;
  }

  const uint64_t wait_fpga_write_csr = 0x30;
  if (wait_fpga_write) {
    res = mpfVtpPrepareBuffer(
        mpf_handle, 4 * KB,
        reinterpret_cast<void **>(const_cast<uint64_t **>(&fpga_write_addr)),
        0);
    if(res != FPGA_OK) {
      printf("Error allocating write_fence buffer\n");
    }
    fpgaWriteMMIO64(
        m_fpga_handle, mmio_num, dfh_offset + wait_fpga_write_csr,
        reinterpret_cast<uint64_t>(const_cast<uint64_t *>(fpga_write_addr)));
  } else {
    fpga_write_addr = nullptr;
  }

  res = mpfVtpPrepareBuffer(mpf_handle, dma_buffer_sz, &dma_buffer, 0);
  if(res != FPGA_OK) {
    printf("Error allocating DMA buffer\n");
  }

  /** launch of new thread, creating new thread object
   *  using lambda and calling work_thread()
   */
  m_thread = new std::thread([this] { this->work_thread(); });
  m_initialized = true;

  if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_DMA_DEBUG")){
    DEBUG_LOG("DEBUG LOG : Constructing DMA %s \n",op_mode);
  }
}

/** mmd_dma destructor 
 *  free-ing , releasing various resources created during object construction is a good idea
 *  it helps with system stability and reduces code bugs
 */
mmd_dma::~mmd_dma() {
  if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_DMA_DEBUG")){
    DEBUG_LOG("DEBUG LOG : Destructing DMA %s\n", op_mode);
  }
  m_work_thread_active = false;
  m_dma_notify.notify_one();
  m_thread->join();
  delete m_thread;
  mpfVtpReleaseBuffer(mpf_handle, dma_buffer);
  m_initialized = false;
}

/** work_thread() called while creating new threads in mmd_dma 
 *  We check m_work_queue to check if it has queued any DMA transactions 
 *  if not we use 'wait()' which comes with 'condition_variable' m_dma_notify
 *  basically if queue is empty we block current thread 
 *  and unlock other threads which share the mutex to proceed
 *  when this thread is notified and woekn up again it locks the mutex and does same check again
 *  once queue has work enqueued we pop an item of work and do_dma() on it.
 */
void mmd_dma::work_thread() {
  while (m_work_thread_active) {
    std::unique_lock<std::mutex> lock(m_work_queue_mutex);
    while (m_work_queue.empty()) {
      m_dma_notify.wait(lock);
      if (!m_work_thread_active) {
        return;
      }
    }
    dma_work_item item = m_work_queue.front();
    m_work_queue.pop();
    lock.unlock();
    int res = do_dma(item);
    if (item.op != nullptr) {
      event_update_fn(item.op, res);
    }
  }
}

/** We create an unique_lock using m_work_queue_mutex
 *  same mutex we used in work_thread()
 *  once we acquire lock we push DMA work item to m_work_queue, which is DMA work queue
 *  and release the lock
 *  we use condition_variable m_dma_notify to unblock thread waiting 
 *  eventually we call do_dma() function which performs dma
 *  work item has all data needed to perform DMA
 */  
int mmd_dma::enqueue_dma(dma_work_item &item) {

  // When item.op is not null DMA is non-blocking and queued to worked thread
  if (item.op != nullptr) {
    std::unique_lock<std::mutex> lv(m_work_queue_mutex);
    m_work_queue.push(item);
    lv.unlock();
    m_dma_notify.notify_one();
    if(std::getenv("MMD_DMA_DEBUG")){
      DEBUG_LOG("DEBUG LOG : TID : %ld DMA ---- Pushing DMA transaction to queue:\nDEBUG LOG : TID : %ld DMA ----          Operation        - %s \nDEBUG LOG : TID : %ld DMA ----          host addr        - %p  \nDEBUG LOG : TID : %ld DMA ----         device addr      - %ld \nDEBUG LOG : TID : %ld DMA ----         Transaction size - 0x%zx \n", transaction_id, transaction_id, op_mode, transaction_id, item.host_addr, transaction_id, item.dev_addr,transaction_id,item.size);
    }
    return 0;
  }

  if (item.op == nullptr) {
    if(std::getenv("MMD_DMA_DEBUG")) {
      DEBUG_LOG("DEBUG LOG : TID : %ld DMA ---- item op is null ptr, which means you are most probably programming bitstream\n",transaction_id);
    }
  }

  // No item.op when operation is blocking, run do_dma() with main thread
  return do_dma(item);
}

void mmd_dma::set_status_handler(aocl_mmd_status_handler_fn fn,
                                 void *user_data) {
  m_status_handler_fn = fn;
  m_status_handler_user_data = user_data;
}

void mmd_dma::event_update_fn(aocl_mmd_op_t op, int status) {
  m_status_handler_fn(m_mmd_handle, m_status_handler_user_data, op, status);
}

void mmd_dma::read_status_registers() {

  read_register(0x3 * 0x8, "cmdq");
  read_register(0x4 * 0x8, "data");
  read_register(0x5 * 0x8, "config");
  read_register(0x6 * 0x8, "status");
  read_register(0x7 * 0x8, "burst_cnt");
  read_register(0x8 * 0x8, "read_valid_cnt");
  read_register(0x9 * 0x8, "magic_num_cnt");
  read_register(0xA * 0x8, "wrdata_cnt");
  read_register(0xB * 0x8, "status2");

}


void mmd_dma::read_register(uint64_t offset, const char* name)
{
  fpga_result res = FPGA_OK;
  uint64_t regval = 0;
  res = fpgaReadMMIO64(m_fpga_handle, mmio_num, dma_csr_base + offset, &regval);
  if(res != FPGA_OK) {
    printf("TID : %ld DMA ---- %s Error reading %s\n", transaction_id, op_mode, name);
  } else {
    printf("TID : %ld DMA ---- %s DMA status: %s\t 0x%lx\n",transaction_id, op_mode, name, regval);
  }
}

/** send_descriptors() function is called by do_dma() function
 *  we use OPAE API fpgaWriteMMIO64() to write dma source, destination addresses to CSRs
 *  and also to write dma transaction length to CSR
 *  for host->fpga DMA we wait for interrupt and 
 *  for fpga->host DMA we use 'magic number' methodology which is known as polling method, instead of using interrupt
 *  in future we plan to enable interrupts for fpga->host direction as well
 *  we can do without lock_guard it seems, there is no shared variable , but not tested yet, will remove in future release
 *  it won't affect performance or functionality
 */  
int mmd_dma::send_descriptors(uint64_t dma_src_addr, uint64_t dma_dst_addr, uint64_t dma_len) {

  std::lock_guard<std::mutex> lock(m_dma_op_mutex);

#if 0
  printf("send_descriptors: dma_src_addr 0x%lx\t dma_dst_addr 0x%lx\t dma_len "
         "0x%lx\n",
         dma_src_addr, dma_dst_addr, dma_len);
#endif
  fpga_result res = FPGA_OK;

  // This check is only needed during development when unaligned accesses
  // were not supported.  Comment out for now, but eventually remove this
  // code altogether.
#if 0
  if ((dma_src_addr % 64) != 0) {
    fprintf(stderr,"Error dma_src_addr unaligned: %lx\n", dma_src_addr);
    return -1;
  }
  if ((dma_dst_addr % 64) != 0) {
    fprintf(stderr,"Error dma_dst_addr unaligned: %lx\n", dma_dst_addr);
    return -1;
  }
  if ((dma_len % 64) != 0 && dma_len != 32) {
    fprintf(stderr,"Error invalided dma_len: %lx\n", dma_len);
    return -1;
  }
#endif

  res = fpgaWriteMMIO64(m_fpga_handle, mmio_num, dma_csr_src, dma_src_addr);
  res = fpgaWriteMMIO64(m_fpga_handle, mmio_num, dma_csr_dst, dma_dst_addr);
  res = fpgaWriteMMIO64(m_fpga_handle, mmio_num, dma_csr_len, dma_len);

  if(res != FPGA_OK) {
    return -1;
  }

  // Simulation is much slower than real hardware so never timeout. On hardware
  // even largest transfer should complete within 10 seconds
#ifdef SIM
  const int TIMEOUT = -1;
#else
  const int TIMEOUT = 10000;
#endif
  if (wait_interrupt) {
    if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_DMA_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : TID : %ld DMA ---- %s Waiting for Interrupt\n",transaction_id, op_mode);
    }
    int_event_fd.events = POLLIN;
    int poll_res = poll(&int_event_fd, 1, TIMEOUT);
    if (poll_res < 0) {
      fprintf(stderr, "TID : %ld DMA ---- %s Poll error\n",transaction_id, op_mode);
    } else if (poll_res == 0) {
      fprintf(stderr, "TID : %ld DMA ---- %s Poll timeout\n",transaction_id, op_mode);
      read_status_registers();
      {
          fprintf(stderr, "TID : %ld DMA ---- %s Print some mpf stats\n",transaction_id, op_mode);
          
          mpf_vtp_stats vtp_stats;
          mpfVtpGetStats(mpf_handle, &vtp_stats);
        
          printf("TID : %ld DMA ---- %s #   VTP failed:            %ld\n", transaction_id, op_mode, vtp_stats.numFailedTranslations);
          if (vtp_stats.numFailedTranslations)
          {
              printf("TID : %ld DMA ---- %s #   VTP failed addr:       0x%lx\n", transaction_id, op_mode, (uint64_t)vtp_stats.ptWalkLastVAddr);
          }
          printf("TID : %ld DMA ---- %s #   VTP PT walk cycles:    %ld\n", transaction_id, op_mode, vtp_stats.numPTWalkBusyCycles);
          printf("TID : %ld DMA ---- %s #   VTP L2 4KB hit / miss: %ld / %ld\n",
              transaction_id, op_mode, vtp_stats.numTLBHits4KB, vtp_stats.numTLBMisses4KB);
          printf("TID : %ld DMA ---- %s #   VTP L2 2MB hit / miss: %ld / %ld\n",
              transaction_id, op_mode, vtp_stats.numTLBHits2MB, vtp_stats.numTLBMisses2MB);
        
          //double cycles_per_pt = (double)vtp_stats.numPTWalkBusyCycles /
          //                    (double)(vtp_stats.numTLBMisses4KB + vtp_stats.numTLBMisses2MB);
          //
          //double usec_per_cycle = 0;
          //if (s_afu_mhz) usec_per_cycle = 1.0 / (double)s_afu_mhz;
          //printf("#   VTP usec / PT walk:    %f\n\n", cycles_per_pt * usec_per_cycle);
      }
      printf("\n");
      return -1;
    } else {
      uint64_t count;
      ssize_t bytes_read = read(int_event_fd.fd, &count, sizeof(count));
      if (bytes_read < 0) {
        fprintf(stderr, "TID : %ld DMA ---- %s Error: poll failed %s\n", transaction_id, op_mode, strerror(errno));
        return -1;
      }
      if (bytes_read == 0) {
        fprintf(stderr, "TID : %ld DMA ---- %s Error: poll failed zero bytes read\n",transaction_id, op_mode);
        return -1;
      }
      if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_DMA_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
        DEBUG_LOG("DEBUG LOG : TID : %ld DMA ---- %s Interrupt received\n",transaction_id, op_mode);
      }
    }
  }

  const uint64_t FPGA_DMA_WF_MAGIC_NO = 0x5772745F53796E63ULL;
  if (wait_fpga_write) {
    if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_DMA_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : TID : %ld DMA ---- %s Waiting for Magic Number to be written to host memory , which confirms completion of %s\n",transaction_id, op_mode, op_mode);
    }
    while (*fpga_write_addr != FPGA_DMA_WF_MAGIC_NO) {
#if 0
      printf("\n");
      read_status_registers();
      sleep(1);
#endif
      std::this_thread::yield();
    }
    if(std::getenv("MMD_PROGRAM_DEBUG") || std::getenv("MMD_DMA_DEBUG") || std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : TID : %ld DMA ---- %s Magic Number written to host memory , which confirms completion of %s\n",transaction_id, op_mode, op_mode);
    }
    *fpga_write_addr = 0;
  }
  return 0;
}

/** do_dma() function is called by enqueue_dma() function
 *  it determines the dma host, src addresses from work item
 *  it pins host memory to improve performance
 *  if transfer size is less than 'threshold' which can be tuned,
 *  it uses intermediate buffer to perforam DMA,
 *  because performance won't be affected a lot at small transfer size
 *  if transfer size > 'threshold' it pins the host memory and unpins when done with DMA
 *  it determines appropriate dma src, dst, len and calles send_descriptors() function  
 */
int mmd_dma::do_dma(dma_work_item &item) {
// adding the following mutex will disable double buffering  
// const std::lock_guard<std::mutex> lock(pinning_mutex);
#if 0 
  printf("do_dma\t");
  if (m_mode == dma_mode::f2h) {
    printf("f2h\t");
  } else {
    printf("h2f\t");
  }
  printf("host: %p\t dev: 0x%lx\t len: 0x%lx\n", item.host_addr, item.dev_addr,
         item.size);
#endif

  static_assert(sizeof(void *) == 8, "Error pointer size not equal to 8 bytes");
  uint64_t host_addr = 0;

  // If host address is already managed by VTP then use it directly, otherwise
  // pin the host memory so that it is managed by VTP if it is larger than
  // threshold (2MB as of when comment was first written, could be tuned). If
  // transfer is smaller than threshold use prepinned DMA buffer and memcpy
  // to/from host to DMA buffer
  bool use_dma_buffer;
  if(item.size > threshold) {
    use_dma_buffer = false;
    fpga_result res;
    res = mpfVtpPrepareBuffer(mpf_handle, item.size, &item.host_addr, FPGA_BUF_PREALLOCATED);
    if(res != FPGA_OK) { 
      fprintf(stderr,"TID : %ld DMA ---- %s Error mpfVtpPrepareBuffer %s\n", transaction_id, op_mode, fpgaErrStr(res));
      return -1;
    }
    if(std::getenv("MMD_DMA_DEBUG")){	    
      DEBUG_LOG("DEBUG LOG : TID : %ld DMA ---- Pinned host memory for %s DMA , host_addr : %p , transaction size : 0x%zx \n",transaction_id, op_mode, item.host_addr, item.size);
    }
    host_addr = reinterpret_cast<uint64_t>(item.host_addr);
  } else {
    use_dma_buffer = true;
    host_addr = reinterpret_cast<uint64_t>(dma_buffer);
    if(m_mode == dma_mode::h2f) {
      memcpy(dma_buffer, item.host_addr, item.size);
    }
    if(std::getenv("MMD_DMA_DEBUG")){	    
      DEBUG_LOG("DEBUG LOG : TID : %ld DMA ---- Using intermediate DMA buffer (no pin mode) for %s DMA , host_addr : %p , transaction size : 0x%zx \n", transaction_id, op_mode, item.host_addr, item.size);
      DEBUG_LOG("DEBUG LOG : TID : %ld DMA ---- Using intermediate DMA buffer (no pin mode) is slow , so expect performance impact \n", transaction_id);
    }
  }
  assert(host_addr != 0);
  
  uint64_t dma_src_addr = 0;
  uint64_t dma_dst_addr = 0;
  uint64_t dma_len = item.size;

  switch (m_mode) {
  case dma_mode::h2f:
    dma_src_addr = host_addr;
    dma_dst_addr = item.dev_addr;
    break;
  case dma_mode::f2h:
    dma_src_addr = item.dev_addr;
    dma_dst_addr = host_addr;
    break;
  default:
    fprintf(stderr, "TID : %ld DMA ---- %s , Error: invalid mode\n",transaction_id, op_mode);
  }

  int dma_res = 0;

  // Note: If max_dma_len is greater than 63*1024 for FPGA to host then the DMA
  // block hangs running on FPGA hardware. Error does not occur in simulation.
  while(max_dma_len > 0 && dma_len > max_dma_len) {
    if(std::getenv("MMD_DMA_DEBUG")){
      DEBUG_LOG("DEBUG LOG : TID : %ld DMA ---- %s , Sending descriptors to DMA hardware controller, dma_src_addr : %ld , dma_dst_addr : %ld, max_dma_len : %ld \n", transaction_id, op_mode, dma_src_addr, dma_dst_addr, max_dma_len);
    }
    dma_res = send_descriptors(dma_src_addr, dma_dst_addr, max_dma_len);
    if (dma_res != 0) {
      return dma_res;
    }
    dma_src_addr += max_dma_len;
    dma_dst_addr += max_dma_len;
    dma_len -= max_dma_len;
  }
  if(dma_len > 0) {
      if(std::getenv("MMD_DMA_DEBUG")){
        DEBUG_LOG("DEBUG LOG : TID : %ld DMA ---- %s , Sent descriptors to DMA hardware controller, dma_src_addr : %ld , dma_dst_addr : %ld, max_dma_len : %ld \n", transaction_id, op_mode, dma_src_addr, dma_dst_addr, max_dma_len);
      }
      dma_res = send_descriptors(dma_src_addr, dma_dst_addr, dma_len);
  }

  // Copy data from DMA buffer to host buffer if necessary
  if (use_dma_buffer && m_mode == dma_mode::f2h) {
    memcpy(item.host_addr, dma_buffer, item.size);
    if(std::getenv("MMD_DMA_DEBUG")){
      DEBUG_LOG("DEBUG LOG : TID : %ld DMA ---- %s , Copying from intermediate dma buffer(no pin mode) to host addr, host_addr : %p , transaction size : 0x%zx \n\n", transaction_id, op_mode, item.host_addr, item.size );
    }
  }

  if(!use_dma_buffer){
    fpga_result res = mpfVtpReleaseBuffer(mpf_handle, item.host_addr);
    if(std::getenv("MMD_DMA_DEBUG")){
      DEBUG_LOG("DEBUG LOG : TID : %ld DMA ---- %s , Releasing pinned host memory after DMA transaction, host_addr : %p \n\n", transaction_id, op_mode, item.host_addr);
    }
    if(res != FPGA_OK) {
      fprintf(stderr,"e TID : %ld DMA ---- %s ,Error mpfVtpReleaseBuffer %s \n", transaction_id, op_mode, fpgaErrStr(res));
    }  
  }

  return dma_res;
}

/** fpga_to_host() function as name suggests for fpga -> host DMA
 *  it constructs a dma work item and adds it to a queue
 *  DMA uses two queues, one for host to fpga and one for fpga to host DMA
 */
int mmd_dma::fpga_to_host(aocl_mmd_op_t op, void *host_addr,
                                  size_t dev_addr, size_t size) {
  transaction_id++;
  assert(host_addr);
  assert(m_mode == dma_mode::f2h);

  dma_work_item item = {
      .op = op, .host_addr = host_addr, .dev_addr = dev_addr, .size = size};

  if(std::getenv("MMD_DMA_DEBUG")){
    DEBUG_LOG("\nDEBUG LOG : TID : %ld DMA ---- %s TRANSACTION , host_addr = %p, device_addr = %ld, transaction size = 0x%zx\n", transaction_id, op_mode,host_addr, dev_addr, size);
  }
  return enqueue_dma(item);
}

/** host_to_fpga() function as name suggests for host -> fpga DMA
 *  it constructs a dma work item and adds it to a queue
 *  DMA uses two queues, one for host to fpga and one for fpga to host DMA
 */
int mmd_dma::host_to_fpga(aocl_mmd_op_t op, const void *host_addr,
                                  size_t dev_addr, size_t size) {
  transaction_id++;
  assert(host_addr);
  assert(m_mode == dma_mode::h2f);

  dma_work_item item = {.op = op,
                        .host_addr = const_cast<void *>(host_addr),
                        .dev_addr = dev_addr,
                        .size = size};
  if(std::getenv("MMD_DMA_DEBUG")){
    DEBUG_LOG("\nDEBUG LOG : TID : %ld DMA ---- %s TRANSACTION , host_addr = %p, device_addr = %ld, transaction size = 0x%zx\n", transaction_id, op_mode, host_addr, dev_addr, size);
  }
  return enqueue_dma(item);
}
}// namespace intel_opae_mmd
