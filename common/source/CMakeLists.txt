# Copyright 2022 Intel Corporation
# SPDX-License-Identifier: MIT

cmake_minimum_required(VERSION 2.8.12)
project(a10_dcp)
include(ExternalProject)
include(CMakePrintHelpers)

if(${ASP_AFU_ID} STREQUAL "N6001")
  cmake_print_variables(CMAKE_BUILD_TYPE)
  add_definitions(-DPCI_ASP_AFU_ID="51ED2F4A-FEA2-4261-A595-918500575509") # PCI ID for N6001
  add_definitions(-DSVM_ASP_AFU_ID="5D9FEF7B-C491-4DCE-95FC-F979F6F061BE") # SVM/USM ID for N6001
  add_definitions(-DBOARD_TYPE=1)                                          # we use board type as 1 for N6001
else ()
  add_definitions(-DPCI_ASP_AFU_ID="3BF773B0-4D46-44D5-9067-C884DEEF8C33") # PCI ID for D5005	
  add_definitions(-DSVM_ASP_AFU_ID="BB664B90-4F03-46E6-BC04-DB601B45B75D") # SVM/USM ID for D5005
  add_definitions(-DBOARD_TYPE=0)                                          # we use board type as 0 for D5005 
endif()

if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE "Release" CACHE STRING "Choose the type of build, options are: Debug Release RelWithDebInfo MinSizeRel." FORCE)
endif(NOT CMAKE_BUILD_TYPE)

set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} "${CMAKE_SOURCE_DIR}/cmake/modules")
cmake_print_variables(CMAKE_MODULE_PATH)
cmake_print_variables(CMAKE_INSTALL_PREFIX)

find_package(OPAE 2.0 REQUIRED)
find_package(IntelFPGA REQUIRED)
find_package(AocElf REQUIRED)
find_package(NUMA REQUIRED)

####################################################################
## SDL required compiler flags
####################################################################
# Needed for all builds
set (CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Wformat -Wformat-security")
set (CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -fPIC")

set (CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Wformat -Wformat-security")
set (CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fPIC")

set (CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -fpie")
set (CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -fpie")

# Release build only
set (CMAKE_C_FLAGS_RELEASE "${CMAKE_C_FLAGS_RELEASE} -D_FORTIFY_SOURCE=2")
if (GCC_VERSION VERSION_GREATER 4.9 OR GCC_VERSION VERSION_EQUAL 4.9)
   set (CMAKE_C_FLAGS_RELEASE "${CMAKE_C_FLAGS_RELEASE} -fstack-protector-strong")
   set (CMAKE_C_FLAGS_RELEASE "${CMAKE_C_FLAGS_RELEASE} -z noexecstack -z relro -z now")
else()
   set (CMAKE_C_FLAGS_RELEASE "${CMAKE_C_FLAGS_RELEASE} -fstack-protector-all")
endif()

set (CMAKE_CXX_FLAGS_RELEASE "${CMAKE_CXX_FLAGS_RELEASE} -fPIC -D_FORTIFY_SOURCE=2")
if (GCC_VERSION VERSION_GREATER 4.9 OR GCC_VERSION VERSION_EQUAL 4.9)
   set (CMAKE_CXX_FLAGS_RELEASE "${CMAKE_CXX_FLAGS_RELEASE} -fstack-protector-strong")
   set (CMAKE_CXX_FLAGS_RELEASE "${CMAKE_CXX_FLAGS_RELEASE} -z noexecstack -z relro -z now")
else()
   set (CMAKE_CXX_FLAGS_RELEASE "${CMAKE_CXX_FLAGS_RELEASE} -fstack-protector-all")
endif()
####################################################################

set(CMAKE_C_FLAGS_RELEASE "${CMAKE_C_FLAGS_RELEASE} -O3")
set(CMAKE_CXX_FLAGS_RELEASE "${CMAKE_CXX_FLAGS_RELEASE} -O3")

set(CMAKE_C_FLAGS_DEBUG "${CMAKE_C_FLAGS_DEBUG} -O0 -ggdb3")
set(CMAKE_CXX_FLAGS_DEBUG "${CMAKE_CXX_FLAGS_DEBUG} -O0 -ggdb3")

#### Sanitizer settings ####
# Address
set(CMAKE_C_FLAGS_ASAN "-O1 -g -fsanitize=address -fno-omit-frame-pointer -fno-optimize-sibling-calls")
set(CMAKE_CXX_FLAGS_ASAN "-O1 -g -fsanitize=address -fno-omit-frame-pointer -fno-optimize-sibling-calls")

# Memory
set(CMAKE_C_FLAGS_MSAN "-O1 -g -fsanitize=memory -fno-omit-frame-pointer -fno-optimize-sibling-calls")
set(CMAKE_CXX_FLAGS_MSAN "-O1 -g -fsanitize=memory -fno-omit-frame-pointer -fno-optimize-sibling-calls")

# Thread
set(CMAKE_C_FLAGS_TSAN "-O1 -g -fsanitize=thread -fno-omit-frame-pointer -fno-optimize-sibling-calls")
set(CMAKE_CXX_FLAGS_TSAN "-O1 -g -fsanitize=thread -fno-omit-frame-pointer -fno-optimize-sibling-calls")
set(CMAKE_EXE_LINKER_FLAGS_TSAN "-fsanitize=thread -pie")


set (CMAKE_CXX_STANDARD 11)
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -std=c++11")

# Enable all warnings except unknown-pragmas.  Wunknown-pragmas must be excluded because
# it is triggered by header file included from OpenCL runtime
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Wall -Wno-unknown-pragmas")
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Wall -Wno-unknown-pragmas")

# Make warnings errors to avoid having them in SDL report
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Werror")
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Werror")

option(OPENCL_ASE_SIM "Build for ASE simulation" OFF)
if(OPENCL_ASE_SIM)
   set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -DSIM=1")
   set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -DSIM=1")
   find_package(ASE REQUIRED)
   set(LIBOPAE_C_OR_ASE ${libopae-c-ase_LIBRARIES})
else()
   set(LIBOPAE_C_OR_ASE ${libopae-c_LIBRARIES})
endif()

link_directories("${CMAKE_SOURCE_DIR}/host/lib")
link_directories("$ENV{QUARTUS_ROOTDIR}/linux64")

cmake_print_variables(CMAKE_CURRENT_SOURCE_DIR)
# Build MPF as external project
ExternalProject_Add(mpf_project
    PREFIX mpf
    SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/extra/intel-fpga-bbb"
    CMAKE_CACHE_ARGS
        -DCMAKE_INSTALL_PREFIX:PATH=${CMAKE_INSTALL_PREFIX}
        -DOPAELIB_INC_PATH:PATH=${libopae-c_INCLUDE_DIRS}
        -DCMAKE_CXX_COMPILER:FILEPATH=${CMAKE_CXX_COMPILER}
        -DCMAKE_C_COMPILER:FILEPATH=${CMAKE_C_COMPILER}
	#-DCMAKE_INSTALL_LIBDIR:PATH=${CMAKE_INSTALL_PREFIX}/linux64/lib
	-DCMAKE_INSTALL_LIBDIR:PATH=${CMAKE_INSTALL_PREFIX}/lib
)

include_directories(
   ${CMAKE_INSTALL_PREFIX}/include
   ${CMAKE_CURRENT_SOURCE_DIR}
   ${CMAKE_SOURCE_DIR}/include
   ${libopae-c_INCLUDE_DIRS}
   ${libintelfpga_INCLUDE_DIRS}
   ${libnuma_INCLUDE_DIR}
)

add_subdirectory(host)
if(NOT OPENCL_ASE_SIM)
   add_subdirectory(util)
endif()
