// Copyright 2022 Intel Corporation
// SPDX-License-Identifier: MIT

#ifndef __FPGACONF_H__
#define __FPGACONF_H__

#include "opae/fpga.h"
#define DEBUG_LOG(...) fprintf(stderr, __VA_ARGS__)

#ifdef __cplusplus
extern "C" {
#endif

struct find_fpga_target {
  int bus;
  int device;
  int function;
  int socket;
};

int find_fpga(struct find_fpga_target target, fpga_token *fpga);

int program_gbs_bitstream(fpga_token fpga, uint8_t *gbs_data, size_t gbs_len);

#ifdef __cplusplus
}
#endif

#endif // __FPGACONF_H__
