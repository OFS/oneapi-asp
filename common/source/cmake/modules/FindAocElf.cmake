# Copyright 2022 Intel Corporation
# SPDX-License-Identifier: MIT

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
