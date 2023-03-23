// Copyright 2022 Intel Corporation
// SPDX-License-Identifier: MIT

struct speed {
  float fastest;
  float slowest;
  float average;
  float total;
};

void ocl_device_init(int maxbytes, char *device_name);
struct speed ocl_readspeed(char *buf, int block_bytes, int bytes);
struct speed ocl_writespeed(char *buf, int block_bytes, int bytes);
int ocl_test_all_global_memory();
