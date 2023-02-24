# Copyright (C) 2013-2014 Altera Corporation, San Jose, California, USA. All rights reserved. 
# Permission is hereby granted, free of charge, to any person obtaining a copy of this 
# software and associated documentation files (the "Software"), to deal in the Software 
# without restriction, including without limitation the rights to use, copy, modify, merge, 
# publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to 
# whom the Software is furnished to do so, subject to the following conditions: 
# The above copyright notice and this permission notice shall be included in all copies or 
# substantial portions of the Software. 
#  
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, 
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES 
# OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND 
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT 
# HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, 
# WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING 
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR 
# OTHER DEALINGS IN THE SOFTWARE. 
#  
# This agreement shall be governed in all respects by the laws of the State of California and 
# by the laws of the United States of America. 


# This is a GNU Makefile.

# It can be used to compile an OpenCL program with
# the Altera SDK for OpenCL.
# See README.txt for more information.


# You must configure INTELFPGAOCLSDKROOT to point the root directory of the Altera SDK for OpenCL
# software installation.
# See http://www.altera.com/literature/hb/opencl-sdk/aocl_getting_started.pdf 
# for more information on installing and configuring the Altera SDK for OpenCL.

ifeq ($(VERBOSE),1)
ECHO := 
else
ECHO := @
endif

TARGET := mem_bandwidth

# Where is the Altera SDK for OpenCL software?
ifeq ($(wildcard $(INTELFPGAOCLSDKROOT)),)
$(error Set INTELFPGAOCLSDKROOT to the root directory of the Altera SDK for OpenCL software installation)
endif
ifeq ($(wildcard $(INTELFPGAOCLSDKROOT)/host/include/CL/opencl.h),)
$(error Set INTELFPGAOCLSDKROOT to the root directory of the Altera SDK for OpenCL software installation.)
endif
ifeq ($(wildcard $(OFS_OCL_SHIM_ROOT)),)
$(error Set OFS_OCL_SHIM_ROOT env variable to ofs-hld-shim/<hld-shim-name> repository path)
endif

# Directories.
HOST_DIR := host
TARGET_DIR := bin
INC_DIRS := host/inc  ../extlibs/inc   $(INTELFPGAOCLSDKROOT)/host/include/
INC_DIRS += $(OFS_OCL_SHIM_ROOT)/source/include
INC_DIRS += $(OFS_OCL_SHIM_ROOT)/../common/source/include
INC_DIRS += $(INTELFPGAOCLSDKROOT)/examples_aoc/common/inc/

ifneq (,$(prefix))
$(Adding OPAE path since not installed at default location )
INC_DIRS += $(prefix)/include
#LIB_DIRS += $(prefix)/lib -Wl,-rpath-link -Wl,$(prefix)/lib -Wl,-rpath -Wl,$(prefix)/lib \
#				$(prefix)/lib64 -Wl,-rpath-link -Wl,$(prefix)/lib64 -Wl,-rpath -Wl,$(prefix)/lib64
endif


# All include files.
INC_FILES := $(foreach D,$(INC_DIRS),$(wildcard $D/*.h))

# Source files.
SRCS := $(wildcard $(INTELFPGAOCLSDKROOT)/examples_aoc/common/src/AOCLUtils/*.cpp) $(wildcard host/src/*.cpp)

# Libraries.
LIBS := intel_opae_mmd
LIB_DIRS = $(OFS_OCL_SHIM_ROOT)/linux64/lib

# Compiler.
CXX := g++ -std=c++11

# OpenCL compile and link flags.
AOCL_COMPILE_CONFIG := $(shell aocl compile-config)
AOCL_LINK_CONFIG := $(shell aocl link-config)

# Compilation flags
ifeq ($(DEBUG),1)
CXXFLAGS += -g -D__USE_XOPEN2K8
else
CXXFLAGS += -O2 -D__USE_XOPEN2K8
endif
CXXFLAGS+= -Wall -DHAVE_CONFIG_H -DTESTB -g

# Make it all!
all : $(TARGET_DIR)/$(TARGET)

# Host executable target.
$(TARGET_DIR)/$(TARGET) : Makefile $(SRCS) $(INC_FILES)
	@[ -d $(TARGET_DIR) ] || mkdir $(TARGET_DIR)
	$(ECHO)$(CXX) $(CPPFLAGS) $(CXXFLAGS) -fPIC $(foreach D,$(INC_DIRS),-I$D) \
			$(AOCL_COMPILE_CONFIG) $(SRCS) $(AOCL_LINK_CONFIG) \
			$(foreach D,$(LIB_DIRS),-L$D) \
			$(foreach L,$(LIBS),-l$L) \
			-o $(TARGET_DIR)/$(TARGET)

# Standard make targets
clean :
	$(ECHO)rm -f $(TARGET_DIR)/$(TARGET)

.PHONY : all clean

