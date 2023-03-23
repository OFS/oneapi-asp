// Copyright 2022 Intel Corporation
// SPDX-License-Identifier: MIT

#include "kernel_interrupt.h"

#include <poll.h>
#include <sys/eventfd.h>

#include <cassert>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <thread>

#include "mmd_device.h"

using namespace intel_opae_mmd;

static const int mmd_kernel_interrupt_line_num = 1;
static const uint32_t enable_int_mask = 0x00000001;
static const uint32_t disable_int_mask = 0x00000000;
static const char *yield_env_var_name = "MMD_YIELD_DELAY";

int KernelInterrupt::aocl_mmd_yield_val = 1;
bool KernelInterrupt::enable_thread = false;
bool KernelInterrupt::use_usleep = true;
int KernelInterrupt::sleep_us = 0;

// TODO: read debug level setting from environment variable
static const int debug_log_level = 0;

// TODO: use consistent function throughout MMD for controlling debug
// messages.  For now defining in
static void debug_print(std::string &err_msg, int msglog) {
  if (debug_log_level >= msglog) {
    std::cerr << "KernelInterrupt: " << err_msg << std::endl;
  }
}

static inline void check_result(fpga_result res, const char *err_str) {
  if (res == FPGA_OK) {
    return;
  }
  std::string opae_err_str = std::string("KernelInterrupt: ") +
                             std::string(err_str) + std::string(": ") +
                             std::string(fpgaErrStr(res));
}

KernelInterrupt::KernelInterrupt(fpga_handle fpga_handle_arg, int mmd_handle)
    : m_work_thread_active(false), m_eventfd(0), m_kernel_interrupt_fn(nullptr),
      m_kernel_interrupt_user_data(nullptr), m_fpga_handle(fpga_handle_arg),
      m_mmd_handle(mmd_handle), m_event_handle(nullptr) {
  if(std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : KernelInterrupt Constructor\n");
  } 
  read_env_vars();
  enable_interrupts();
}

KernelInterrupt::~KernelInterrupt() {
  if(std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : KernelInterrupt Destructor\n");
  }
  try {
    disable_interrupts();
  } catch (...) {
    std::string err("destructor error");
    debug_print(err, 0);
  }
}

void KernelInterrupt::disable_interrupts() {
  if (!enable_thread) {
    if(std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : KernelInterrupt disabling interrupts\n");
    }
    assert(m_work_thread_active == false);
    set_interrupt_mask(disable_int_mask);
    return;
  }

  m_work_thread_active = false;
  notify_work_thread();
  m_work_thread->join();

  if (m_event_handle != nullptr) {
    fpga_result res;

    res = fpgaUnregisterEvent(m_fpga_handle, FPGA_EVENT_INTERRUPT,
                              m_event_handle);
    check_result(res, "error fpgaUnregisterEvent");

    res = fpgaDestroyEventHandle(&m_event_handle);
    check_result(res, "error fpgaDestroyEventHandle");
  }
  set_interrupt_mask(disable_int_mask);
  if(std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : KernelInterrupt disabling interrupts\n");
  }
}

void KernelInterrupt::notify_work_thread() {
  uint64_t val = 1;
  ssize_t res = write(m_eventfd, &val, sizeof(val));
  if (res < 0) {
    std::cerr << "Warning: KernelInterrupts::notify_work_thread()"
                 " write to eventfd failed: "
              << strerror(errno) << std::endl;
  }
}

void KernelInterrupt::enable_interrupts() {
  if (!enable_thread) {
    if(std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : KernelInterrupt enabling interrupts\n");
    }
    set_interrupt_mask(disable_int_mask);
    m_work_thread_active = false;
    return;
  }

  fpga_result res;

  res = fpgaCreateEventHandle(&m_event_handle);
  check_result(res, "error creating event handle");

  res = fpgaRegisterEvent(m_fpga_handle, FPGA_EVENT_INTERRUPT, m_event_handle,
                          mmd_kernel_interrupt_line_num);
  check_result(res, "error registering event");

  res = fpgaGetOSObjectFromEventHandle(m_event_handle, &m_eventfd);
  check_result(res, "error getting event file handle");

  set_interrupt_mask(enable_int_mask);

  m_work_thread_active = true;
  m_work_thread = std::unique_ptr<std::thread>(
      new std::thread([this] { this->work_thread(); }));
  if(std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : KernelInterrupt enabling interrupts\n");
  }
}

void KernelInterrupt::set_interrupt_mask(uint32_t intr_mask) {
  if(std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : KernelInterrupt setting interrupt mask : %d\n",intr_mask );
  }
  fpga_result res;
  res = fpgaWriteMMIO32(m_fpga_handle, 0, AOCL_IRQ_MASKING_BASE, intr_mask);
  check_result(res, "Error fpgaWriteMMIO32");
}

void KernelInterrupt::work_thread() {
  while (m_work_thread_active) {
    wait_for_event();
    set_interrupt_mask(disable_int_mask);
    std::lock_guard<std::mutex> lock(m_mutex);
    if (m_kernel_interrupt_fn != nullptr) {
      m_kernel_interrupt_fn(m_mmd_handle, m_kernel_interrupt_user_data);
    }
    set_interrupt_mask(enable_int_mask);
  }
}

void KernelInterrupt::wait_for_event() {
  // Use timeout when polling eventfd because sometimes interrupts are missed.
  // This may be caused by knonw race condition with runtime, or there may
  // be occasional events lost from OPAE. Re-evaluate need for timeout
  // after fixing race condition with runtime.
  if(std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : KernelInterrupt waiting for event using poll()\n");
  }
  const int timeout_ms = 250;
  struct pollfd pfd = {.fd = m_eventfd, .events = POLLIN, .revents = 0};
  int num_events = poll(&pfd, 1, timeout_ms);
  if (num_events <= 0) {
    std::string err(num_events < 0 ? strerror(errno) : "timed out");
    std::string err_str("poll(): ");
    debug_print(err_str.append(err), 1);
  } else if (pfd.revents != POLLIN) {
    std::string err("poll error num: ", pfd.revents);
    debug_print(err, 0);
  } else {
    uint64_t val = 0;
    ssize_t bytes_read = read(pfd.fd, &val, sizeof(val));
    if (bytes_read < 0) {
      std::string err(strerror(errno));
      std::string err_str("read: ");
      debug_print(err_str.append(err), 1);
    }
  }
}

void KernelInterrupt::set_kernel_interrupt(aocl_mmd_interrupt_handler_fn fn,
                                           void *user_data) {
  if(std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : KernelInterrupt setting kernel interrupt\n");
  }
  std::lock_guard<std::mutex> lock(m_mutex);
  m_kernel_interrupt_fn = fn;
  m_kernel_interrupt_user_data = user_data;
}

int KernelInterrupt::yield_is_enabled() {
  if(std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : KernelInterrupt enabling yield\n");
  }
  read_env_vars();
  return aocl_mmd_yield_val;
}

int KernelInterrupt::yield() {
  if(std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : KernelInterrupt::yield()\n");
  }
  if (use_usleep) {
    if(std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : KernelInterrupt::yield() Sleeping for %d\n",sleep_us);
    }
    usleep(sleep_us);
  } else {
    std::this_thread::yield();
  }

  if (m_kernel_interrupt_fn != nullptr) {
    m_kernel_interrupt_fn(m_mmd_handle, m_kernel_interrupt_user_data);
  }
  return 0;
}

/** Configure interrupts or polling using environment variable
    if less than -1 then use interrupts
    if equal -1 then yield but no sleep
    if greater than or equal 0 then yield for that many us */
void KernelInterrupt::read_env_vars() {
  if(std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : Configure interrupts or polling using environment variable\n"
               "            if less than -1 then use interrupts\n"
               "            if equal -1 then yield but no sleep\n"
               "            if greater than or equal 0 then yield for that many usec\n");
  }
  static bool initialized = false;
  if (initialized) {
    return;
  }

  char *delay_env_var = std::getenv(yield_env_var_name);

  int delay_env_val = -1;
  if (delay_env_var != nullptr) {
    delay_env_val = std::atoi(delay_env_var);
  }

  // Use interrupts
  if (delay_env_val < -1) {
    if(std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : Using interrupts\n");
    }
    aocl_mmd_yield_val = 0;
    enable_thread = true;
    use_usleep = false;
    sleep_us = 0;
  }
  // Use yield without sleep
  else if (delay_env_val < 0) {
    if(std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : Using yield without sleep\n");
    }
    aocl_mmd_yield_val = 1;
    enable_thread = false;
    use_usleep = false;
    sleep_us = 0;
  }
  // Yield with sleep for delay us
  else {
    aocl_mmd_yield_val = 1;
    enable_thread = false;
    use_usleep = true;
    sleep_us = delay_env_val;

    if(std::getenv("MMD_ENABLE_DEBUG")){
      DEBUG_LOG("DEBUG LOG : Using yield with sleep : %d\n", sleep_us);
    }
  }

  initialized = true;
}
