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

#ifndef KERNEL_INTERRUPT_H_
#define KERNEL_INTERRUPT_H_

#include <opae/fpga.h>

#include <atomic>
#include <chrono>
#include <mutex>
#include <thread>

#include "aocl_mmd.h"

namespace intel_opae_mmd {

class KernelInterrupt final {
public:
  KernelInterrupt(fpga_handle fpga_handle_arg, int mmd_handle);
  ~KernelInterrupt();

  static int yield_is_enabled();
  int yield();

  void enable_interrupts();
  void disable_interrupts();
  void set_kernel_interrupt(aocl_mmd_interrupt_handler_fn fn, void *user_data);

  KernelInterrupt(const KernelInterrupt &) = delete;
  KernelInterrupt &operator=(const KernelInterrupt &) = delete;
  KernelInterrupt(KernelInterrupt &&) = delete;
  KernelInterrupt &operator=(KernelInterrupt &&) = delete;

private:
  static void read_env_vars();

  void set_interrupt_mask(uint32_t intr_mask);
  void notify_work_thread();
  void wait_for_event();
  void work_thread();

  static int aocl_mmd_yield_val;
  static bool enable_thread;
  static bool use_usleep;
  static int sleep_us;

  std::mutex m_mutex;
  std::unique_ptr<std::thread> m_work_thread;
  std::atomic<bool> m_work_thread_active;
  int m_eventfd;
  aocl_mmd_interrupt_handler_fn m_kernel_interrupt_fn;
  void *m_kernel_interrupt_user_data;
  fpga_handle m_fpga_handle;
  int m_mmd_handle;
  fpga_event_handle m_event_handle;
};

}; // namespace intel_opae_mmd

#endif // KERNEL_INTERRUPT_H_
