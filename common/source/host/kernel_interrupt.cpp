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

/** KernelInterrupt constructor
 *  we call read_env_vars() and enable_interrupts() functions
 */
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

/** KernelInterrupt destructor
 *  calls disable_interrupts() 
 */
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

/** disable_interrupts() function is used in KernelInterrupt destructor
 *  if interupt not enabled , !enable_thread
 *  then disable interrupt mask
 *  else if interrupts are used,
 *  call noftify_work_thread(), join the thread
 *  we call OPAE API fpgaUnregisterEvent() to unregister FPGA event,
 *  it tells driver caller is no longer interested in notification for event associated with m_event_handle
 *  we call OPAE API fpgaDestroyEventHandle() to free resources
 */
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

/** notify_work_thread() function is called by disable_interrupts() function
 *  eventfd object created by OPAE API fpgaGetOSObjectFromEventHandle() , m_eventfd,
 *  can be used as an event wait/notify mechanism by user space applications and by kernel,
 *  to notify user space applications of events   
 *  every time write() is performed on eventfd, 
 *  the value of uint64_t being written is added to count and wakeup is performed.
 * We dont use read() below but read() will return count value to user space and reset count to 0
 */
void KernelInterrupt::notify_work_thread() {
  uint64_t val = 1;
  ssize_t res = write(m_eventfd, &val, sizeof(val));
  if (res < 0) {
    std::cerr << "Warning: KernelInterrupts::notify_work_thread()"
                 " write to eventfd failed: "
              << strerror(errno) << std::endl;
  }
}

/** enable_interrupts() function is called by Kernel Interrupt constructor
 *  if interrupt is not enabled it will disable interrupt mask , set thread active as false and return 
 *  if interrupt is enabled, it will use OPAE APIs to create event handle fpgaCreateEventHandle()
 *  OPAE event APIs provide functions for handling asynchronous events such as errors and interrupts
 *  Associated with every event a process has registered for is an fpga_event_handle, 
 *  which encapsulates OS specific data structure for event objects
 *  On Linux fpga_event_handle can be used as file descriptor 
 *  and passed to select(), poll() and similar functions to wait for asynchronous events
 *  OPAE API fpgaRegisterEvent() is used to tell driver that caller is interested in notification for event specified
 *  OPAE API fpgaGetOSObjectFromEventHandle() checks validity of event handle and
 *  gets OS object used to subscribe and unsubscribe to events
 *  we create a thread and call work_thread()
 */
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

/** work_thread() is called from enable_interrupts() function while creating new thread
 *  it calls wait_for_event(), disables interrupt mask
 *  creates lock_guard with m_mutex, calls kernel interrupt function and then enables interrupt mask
 */
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

/** wait_for_event() is called from work_thread() function
 *  it uses poll() function to wait for event on a file descriptor,
 *  the m_event_fd file descriptor which we got from fpgaOSObjectFromEventHandle()  
 *  poll() uses pollfd struct, which inncludes
 *  fd - file descriptor, events - requested events, revents - returned events
 *  timeout argument in poll() specifies number of milliseconds, 
 *  poll() will block waiting for file descriptor
 *  On success, poll() returns a nonnegative value which is the
 *  number of elements in the pollfds whose revents fields have been
 *  set to a nonzero value (indicating an event or an error).  A
 *  return value of zero indicates that the system call timed out
 *  before any file descriptors became read
 */
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

/** yield_is_enabled() is called in aocl_mmd_get_offline_info() API
 *  it uses return_env_vars() to return appropriate value
 */
int KernelInterrupt::yield_is_enabled() {
  if(std::getenv("MMD_ENABLE_DEBUG")){
    DEBUG_LOG("DEBUG LOG : KernelInterrupt enabling yield\n");
  }
  read_env_vars();
  return aocl_mmd_yield_val;
}

/** yield() is called through yield() method in Device object
 *  refer file mmd_device.cpp , mmd_device.h for Device Class
 *  this_thread::yield() provides hint to OS to reshcedule execution of threads,
 *  allowing other threads to run
 */
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
 *  if less than -1 then use interrupts
 *  if equal -1 then yield but no sleep
 *  if greater than or equal 0 then yield for that many us
 *  read_env_vars() called from KernelInterrupts constructor
 */
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
