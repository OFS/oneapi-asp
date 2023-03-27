# Copyright 2022 Intel Corporation
# SPDX-License-Identifier: MIT

# - Try to find libintelfpga
# Once done, this will define
#
#  libsafestr_FOUND - system has libsafestr
#  libsafestr_INCLUDE_DIRS - the libsafestr include directories
#  libsafestr_LIBRARIES - link these to use libsafestr

find_package(PkgConfig)
pkg_check_modules(PC_OPAE QUIET opae-c)

# Use pkg-config to get hints about paths
execute_process(COMMAND pkg-config --cflags opae-c --silence-errors
  COMMAND cut -d I -f 2
  OUTPUT_VARIABLE OPAE-C_PKG_CONFIG_INCLUDE_DIRS)
set(OPAE-C_PKG_CONFIG_INCLUDE_DIRS "${OPAE-C_PKG_CONFIG_INCLUDE_DIRS}" CACHE STRING "Compiler flags for OPAE-C library")

# Include dir
find_path(libsafestr_INCLUDE_DIRS
  NAMES safe_string/safe_string.h
  PATHS ${LIBOPAE-C_ROOT}/include
  ${OPAE-C_PKG_CONFIG_INCLUDE_DIRS}
  /usr/local/include
  /usr/include
  ${CMAKE_EXTRA_INCLUDES})

# The library itself
find_library(libsafestr_LIBRARIES
  NAMES libsafestr.a
  PATHS ${LIBOPAE-C_ROOT}/lib
  ${LIBOPAE-C_ROOT}/lib64
  /usr/local/lib
  /usr/lib
  /lib
  /usr/lib/x86_64-linux-gnu
  ${CMAKE_EXTRA_LIBS})

if(libsafestr_LIBRARIES AND libsafestr_INCLUDE_DIRS)
  set(libsafestr_FOUND true)
endif(libsafestr_LIBRARIES AND libsafestr_INCLUDE_DIRS)
