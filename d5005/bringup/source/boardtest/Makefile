
# This is a GNU Makefile.

# It can be used to compile an OpenCL program with
# the Intel(R) FPGA SDK for OpenCL(TM).
# See README.txt for more information.


# You must configure INTELFPGAOCLSDKROOT to point the root directory of the Intel(R) FPGA SDK for OpenCL(TM)
# software installation.
# See doc/getting_started.txt for more information on installing and
# configuring the Intel(R) FPGA SDK for OpenCL(TM).

HOST_DIR ?= host
TARGET = boardtest_host

LIB_DIRS = $(QUARTUS_HOME)/linux64

# Where is the Intel(R) FPGA SDK for OpenCL(TM) software?
ifeq ($(wildcard $(INTELFPGAOCLSDKROOT)),)
$(error Set INTELFPGAOCLSDKROOT to the root directory of the Intel(R) FPGA SDK for OpenCL(TM) software installation)
endif
ifeq ($(wildcard $(INTELFPGAOCLSDKROOT)/host/include/CL/opencl.h),)
$(error Set INTELFPGAOCLSDKROOT to the root directory of the Intel(R) FPGA SDK for OpenCL(TM) software installation.)
endif

SRCS = main.cpp memspeed.cpp reorder.cpp reorder_ocl.cpp hostspeed.cpp hostspeed_ocl.cpp aclutil.cpp timer.cpp rwtest.cpp kernel_launch.cpp kernel_rw.cpp
SRCS_FILES = $(foreach F, $(SRCS), $(HOST_DIR)/$(F))
SRCS_FILES += $(wildcard $(INTELFPGAOCLSDKROOT)/examples_aoc/common/src/AOCLUtils/*.cpp)

# Directories.
INC_DIRS := $(INTELFPGAOCLSDKROOT)/examples_aoc/common/inc

# OpenCL compile and link flags.
AOCL_COMPILE_CONFIG=$(shell aocl compile-config)
AOCL_LINK_CONFIG=$(shell aocl link-config)

# Make it all!
all :
	g++ -fPIC $(SRCS_FILES) $(foreach D,$(LIB_DIRS),-L$D) -o $(TARGET) -DLINUX $(AOCL_COMPILE_CONFIG) $(AOCL_LINK_CONFIG) -lrt $(foreach D,$(INC_DIRS),-I$D)

tsan:
	g++ -fPIC $(SRCS_FILES) $(foreach D,$(LIB_DIRS),-L$D) -o $(TARGET) -DLINUX $(AOCL_COMPILE_CONFIG) $(AOCL_LINK_CONFIG) -lrt -O1 -fsanitize=thread -pie $(foreach D,$(INC_DIRS),-I$D)

# Standard make targets
clean :
	@rm -f $(OBJS) $(TARGET)
