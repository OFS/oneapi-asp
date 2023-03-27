# Copyright 2022 Intel Corporation
# SPDX-License-Identifier: MIT

# - Try to find libintelfpga
# Once done, this will define
#
#  libintelfpga_FOUND - system has libintelfpga
#  libintelfpga_INCLUDE_DIRS - the libpae-c include directories
#  libintelfpga_LIBRARIES - link these to use libintelfpga

find_package(PkgConfig)

# Include dir
find_path(libintelfpga_INCLUDE_DIRS
  NAMES CL/cl_ext_intelfpga.h
  PATHS
  $ENV{INTELFPGAOCLSDKROOT}/host/include
)

# The library itself
find_library(libintelfpga_LIBRARIES
  NAMES alteracl
  PATHS
  $ENV{INTELFPGAOCLSDKROOT}/host/linux64/lib
)

if(libintelfpga_LIBRARIES AND libintelfpga_INCLUDE_DIRS)
  set(libintelfpga_FOUND true)
endif(libintelfpga_LIBRARIES AND libintelfpga_INCLUDE_DIRS)
