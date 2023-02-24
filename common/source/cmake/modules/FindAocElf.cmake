# Copyright 2020 Intel Corporation.
#
# THIS SOFTWARE MAY CONTAIN PREPRODUCTION CODE AND IS PROVIDED BY THE
# COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED
# WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR
# BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
# WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
# OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
# EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

################################################################################
# The Intel FPGA MMD links with a static library called libpkg_editor.a.
# This static library references symbols exposed in libelf.so.0. The
# symbol elfx_update_shstrndx is present in libelf.so.0, but not libelf.so.1.
# The Intel FPGA runtime ships with its own copy of libelf.so.0. It also
# adds its path to LD_LIBRARY_PATH so that required libraries including this
# one can be located. This Find*.cmake file locates the copy of libelf.so.0 
# that is included with Intel FPGA OpenCl and links with it when building the 
# MMD.  
################################################################################

#  libaocelf_FOUND - system has libaocelf
#  libaocelf_LIBRARIES - link these to use libaocelf

# The library itself
find_library(libaocelf_LIBRARIES
  NAMES libelf.so.0
  PATHS
  $ENV{INTELFPGAOCLSDKROOT}/host/linux64/lib
)

if(libaocelf_LIBRARIES)
  set(libaocelf_FOUND true)
endif(libaocelf_LIBRARIES)
