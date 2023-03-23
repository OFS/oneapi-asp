# Copyright 2022 Intel Corporation
# SPDX-License-Identifier: MIT

# - Try to find libopae-c-ase
# Once done, this will define
#
#  libopae-c-ase_FOUND - system has libopae-c-ase
#  libopae-c-ase_LIBRARIES - link these to use libopae-c-ase

find_package(PkgConfig)

# The library itself
find_library(libopae-c-ase_LIBRARIES
  NAMES opae-c-ase
  PATHS ${LIBOPAE-C_ROOT}/lib
  ${LIBOPAE-C_ROOT}/lib64
  ${LIBOPAE-C_ROOT}/../../opae-sim/install/lib64
  /usr/local/lib
  /usr/lib
  /lib
  /usr/lib/x86_64-linux-gnu
  ${CMAKE_EXTRA_LIBS})

if(libopae-c-ase_LIBRARIES)
  set(libopae-c-ase_FOUND true)
endif(libopae-c-ase_LIBRARIES)
