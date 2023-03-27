# Copyright 2022 Intel Corporation
# SPDX-License-Identifier: MIT

# - Try to find libnuma
# Once done will define:
#
# libnuma_FOUND - system has libnuma
# libnuma_INCLUDE_DIRS - include directory with numa.h
# libnuma_LIBRARIES - link with this for libnuma

find_path(libnuma_INCLUDE_DIR
  NAMES numa.h
  PATHS
  ${LIBNUMA_ROOT}/include
  /usr/include

  # XXX: when compiling in arc libnuma may not be available
  /p/psg/swip/w/gsouther/shared/libs/libnuma/include
  /data/gsouther/shared/libs/libnuma/include
  )

find_library(libnuma_LIBRARIES
  NAMES numa
  PATHS
  ${LIBNUMA_ROOT}/lib
  ${LIBNUMA_ROOT}/lib64
  /usr/lib
  /usr/lib64

  # XXX: when compiling in arc libnuma may not be available
  /p/psg/swip/w/gsouther/shared/libs/libnuma/lib
  /data/gsouther/shared/libs/libnuma/lib
  )

if(libnuma_INCLUDE_DIR AND libnuma_LIBRARIES)
  set(libnuma_FOUND true)
endif(libnuma_INCLUDE_DIR AND libnuma_LIBRARIES)
