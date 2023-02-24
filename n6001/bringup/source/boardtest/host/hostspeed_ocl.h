#include "CL/opencl.h"

struct speed {
  float fastest;
  float slowest;
  float average;
  float total;
};
void freeDeviceMemory();
void hostspeed_ocl_device_init( cl_platform_id platform,
                                cl_device_id device,
                                cl_context context,
                                cl_command_queue queue,
                                size_t maxbytes);
struct speed ocl_readspeed(char * buf, size_t block_bytes, size_t bytes);
struct speed ocl_writespeed(char * buf, size_t block_bytes, size_t bytes);
size_t ocl_test_all_global_memory( );
