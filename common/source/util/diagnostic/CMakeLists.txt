## Copyright 2022 Intel Corporation
## SPDX-License-Identifier: MIT

project(diagnostic)

set(DIAGNOSE_SRC
   acl_aligned.cpp
   main.cpp
   ocl.cpp
)

add_definitions(-DOPTION3=1 
                -DACL_USE_DMA=1
                -DACL_COMPILER_IS_MSVC=0 
                -D__USE_XOPEN2K8 
                -DACL_HAS_STDLIB_STDIO 
                -DACL_HOST_RUNTIME_IS_STATIC=0 
                -DACL_OPENCL_HOST_SYS=linux 
                -DACL_OPENCL_HOST_BIT=64 
                -DACL_TARGET_SYS=linux 
                -DACL_TARGET_BIT=64 
                -DLINUX)

add_executable(diagnose ${DIAGNOSE_SRC})

target_link_libraries(diagnose
   ${libintelfpga_LIBRARIES}
   intel_opae_mmd
   -lstdc++
)

install(TARGETS diagnose 
   RUNTIME DESTINATION ${CMAKE_INSTALL_PREFIX}/libexec
)
