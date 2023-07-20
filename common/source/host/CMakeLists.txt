## Copyright 2022 Intel Corporation
## SPDX-License-Identifier: MIT

include(CMakePrintHelpers)
project(intel_opae_mmd)

enable_language(C ASM)

set(ASM_OPTIONS "-x assembler-with-cpp")
if(${CMAKE_C_COMPILER_ID} STREQUAL "Clang")
  set(ASM_OPTIONS "${ASM_OPTIONS} -no-integrated-as")
endif()

set(CMAKE_ASM_FLAGS "${CFLAGS} ${ASM_OPTIONS}")

set(MMD_SRC
   mmd.cpp
   mmd_device.cpp
   fpgaconf.c
   kernel_interrupt.cpp
   mmd_dma.cpp
   zlib_inflate.c
   mmd_iopipes.cpp
)

add_library(intel_opae_mmd SHARED ${MMD_SRC})

add_library(libmpf STATIC IMPORTED)
set_property(TARGET libmpf PROPERTY IMPORTED_LOCATION ${CMAKE_INSTALL_PREFIX}/lib/libMPF.so)

#cmake_print_variables(CMAKE_CURRENT_SOURCE_DIR)

#target_include_directories(intel_opae_mmd ${CMAKE_CURRENT_SOURCE_DIR})

target_link_libraries(intel_opae_mmd
   libmpf
   ${LIBOPAE_C_OR_ASE}
   pkg_editor.a
   ${libaocelf_LIBRARIES}
   ${libnuma_LIBRARIES}
   ${libMPF_LIBRARIES}
   -lpthread
   -lz
   -luuid
   -lstdc++
)

install(TARGETS intel_opae_mmd
   LIBRARY DESTINATION ${CMAKE_INSTALL_PREFIX}/lib
   COMPONENT intel_opae_mmd
)
