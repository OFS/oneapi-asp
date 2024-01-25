// Copyright 2022 Intel Corporation
// SPDX-License-Identifier: MIT

/********
 * The diagnostic program go through a few steps to test if the board is
 * working properly
 *
 * 1. Driver Installation Check
 *
 * 2. Board Installation Check
 *
 * 3. Basic Functionality Check
 *
 * 4. Large Size DMA transmission between host and the device
 *
 * 5. Measure PCIe bandwidth:
 *
 * Fastest: Max speed of any one Enqueue call
 * Slowest: Min speed of any one Enqueue call
 * Average: Sum of transfer times from Queued-End of each request divided
 * by total bytes
 * Total: Queue time of first Enqueue call to End time of last Enqueue call
 * divided by total bytes
 *
 * Final "Throughput" value is average of max read and max write speeds.
 ********/

#define _GNU_SOURCE 1
#include <malloc.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include <iomanip> // std::setw
#include <limits>
#include <sstream> // std::ostringstream

#include "acl_aligned.h"
#include "ocl.h"
#undef _GNU_SOURCE

#include "aocl_mmd.h"
#include "mmd.h"

#define ACL_BOARD_PKG_NAME "ofs"
#define ACL_VENDOR_NAME "Intel(R) Corporation"
#define ACL_BOARD_NAME "Intel OFS Platform"

// WARNING: host runs out of events if MAXNUMBYTES is much greater than
// MINNUMBYTES!!!
#define INT_KB (1024)
#define INT_MB (1024 * 1024)
#define INT_GB (1024 * 1024 * 1024)
#define DEFAULT_MAXNUMBYTES (256ULL * INT_MB)
#define DEFAULT_MINNUMBYTES (512ULL * INT_KB)

#define DIAGNOSE_FAILED -1

bool diagnose = 1;

bool mmd_dma_setup_check();
bool mmd_check_fme_driver_for_pr();
bool mmd_asp_loaded(const char *name);
extern int mmd_get_offline_board_names(size_t param_value_size,
                                            void *param_value,
                                            size_t *param_size_ret);

bool check_results(unsigned int *buf, unsigned int *output, unsigned n) {
  bool result = true;
  int prints = 0;
  for (unsigned j = 0; j < n; j++)
    if (buf[j] != output[j]) {
      if (prints++ < 512)
        printf("Error! Mismatch at element %d: %8x != %8x, xor = %08x\n", j,
               buf[j], output[j], buf[j] ^ output[j]);
      result = false;
    }
  return result;
}

#define MMD_STRING_RETURN_SIZE 1024

int scan_devices(const char *device_name) {
  static char vendor_name[MMD_STRING_RETURN_SIZE];
  aocl_mmd_get_offline_info(AOCL_MMD_VENDOR_NAME, sizeof(vendor_name),
                            vendor_name, NULL);
  printf("Vendor: %s\n", vendor_name);

  // create a output string stream for information of the list of devices
  // this information will be output to stdout at the end to form a nice looking
  // list
  std::ostringstream o_list_stream;

  // get all supported board names from MMD
  static char boards_name[MMD_STRING_RETURN_SIZE];
  mmd_get_offline_board_names(sizeof(boards_name), boards_name, NULL);

  // query through all possible device name
  static char board_name[MMD_STRING_RETURN_SIZE];
  static char pcie_info[MMD_STRING_RETURN_SIZE];
  char *dev_name;
  int handle;
  int first_row_printed = 0;
  int num_active_boards = 0;
  float temperature;
  char *boards;
  for (dev_name = strtok_r(boards_name, ";", &boards); dev_name != NULL;
       dev_name = strtok_r(NULL, ";", &boards)) {
    if (device_name != NULL && strcmp(dev_name, device_name) != 0)
      continue;

    handle = aocl_mmd_open(dev_name);

    // print out the first row of the table when needed
    if (handle != -1 && !first_row_printed) {
      o_list_stream << "\n";
      o_list_stream << std::left << std::setw(20) << "Physical Dev Name"
                    << std::left << std::setw(18) << "Status"
                    << "Information\n";
      first_row_printed = 1;
    }

    num_active_boards++;

    // when handle < -1 a DCP device exists but is not configured with OpenCL
    // ASP
    if (handle < -1) {
      o_list_stream << "\n";
      o_list_stream << std::left << std::setw(20) << dev_name << std::left
                    << std::setw(18) << "Uninitialized"
                    << "OneAPI ASP not loaded. Must load ASP using command: \n"
                    << std::left << std::setw(38) << " "
                    << "'aocl initialize <device_name> <board_variant>'\n"
                    << std::left << std::setw(38) << " "
                    << "before running OneAPI programs using this device\n";
    }

    if(handle == -1) {
      if(!first_row_printed) {
        o_list_stream << "\n";
        o_list_stream << std::left << std::setw(20) << "Physical Dev Name"
                    << std::left << std::setw(18) << "Status"
                    << "Information\n";
        first_row_printed = 1;
      } 

      o_list_stream << "\n";
      o_list_stream << std::left << std::setw(20) << dev_name << std::left
                    << std::setw(18) << "Uninitialized"
                    << "PR slot function not configured\n"
                    << std::left << std::setw(38) << " "
                    << "Need to follow instructions to bind vfio-pci driver to PR slot function\n";
    }

    // skip to next dev_name
    if (handle < 0) {
      continue;
    }

    // found a working supported device
    o_list_stream << "\n";
    try {
      aocl_mmd_get_info(handle, AOCL_MMD_BOARD_NAME, sizeof(board_name),
                      board_name, NULL);
    } catch(...) {
      return -1;
    }

    o_list_stream << std::left << std::setw(20) << dev_name << std::left
                  << std::setw(18) << "Passed   " << board_name << "\n";

    try {
      aocl_mmd_get_info(handle, AOCL_MMD_PCIE_INFO, sizeof(pcie_info), pcie_info,
                      NULL);
    } catch(...) {
      return -1;
    }

    o_list_stream << std::left << std::setw(38) << " "
                  << "PCIe " << pcie_info << "\n";

    try {
      aocl_mmd_get_info(handle, AOCL_MMD_TEMPERATURE, sizeof(float), &temperature,
                      NULL);
    } catch(...) {
      return -1;
    }

    // Temperature reported in celsius
    // anything below -273 is below absolute zero
    // we return -999 if no BMC found or some other error and so no temperature returned by OPAE API calls
    if (temperature > -273.15) {
      o_list_stream << std::left << std::setw(38) << " "
                    << "FPGA temperature = " << temperature << " degrees C.\n";
    } else {
      o_list_stream << std::left << std::setw(38) << " "
                    << "FPGA temperature = " << " NA \n";
    }
  }

  if (num_active_boards > 0) {
    if (device_name == NULL) {
      o_list_stream
          << "\nFound " << num_active_boards
          << " active device(s) installed on the host machine. To perform a "
             "full diagnostic on a specific device, please run\n";
      o_list_stream << "      aocl diagnose <device_name>\n";
    }
  } else {
    o_list_stream << "\nNo active device installed on the host machine.\n";
    o_list_stream
        << "      Please consult documentation for troubleshooting steps\n";
  }

  // output all characters in ostringstream
  std::string s = o_list_stream.str();
  printf("%s", s.c_str());

  return num_active_boards > 0 ? 0 : 1;
}

int main(int argc, char *argv[]) {
  char *device_name = NULL;
  bool probe = false;

  for (int i = 1; i < argc; i++) {
    if (strcmp(argv[i], "-probe") == 0)
      probe = true;
    else
      device_name = argv[i];
  }

  // we scan all the device installed on the host machine and print
  // preliminary information about all or just the one specified
  if ((!probe && device_name == NULL) || (probe && device_name != NULL)) {
    if (scan_devices(device_name) == 0) {
      printf("\nASP DIAGNOSTIC_PASSED\n");
    } else {
      printf("\nASP DIAGNOSTIC_FAILED\n");
      return DIAGNOSE_FAILED;
    }
    return 0;
  }

  // get all supported board names from MMD
  //   if probing all device just print them and exit
  //   if diagnosing a particular device, check if it exists
  char boards_name[MMD_STRING_RETURN_SIZE];
  mmd_get_offline_board_names(sizeof(boards_name), boards_name, NULL);
  char *dev_name;
  bool device_exists = false;
  bool asp_loaded = false;
  char *boards = boards_name;
  for (dev_name = strtok_r(boards_name, ";", &boards); dev_name != NULL;
       dev_name = strtok_r(NULL, ";", &boards)) {
    if (probe)
      printf("%s\n", dev_name);
    else
      device_exists |= (strcmp(dev_name, argv[1]) == 0);
  }

  // If probing all devices we're done here
  if (probe)
    return 0;

  // Full diagnosis of a particular device begins here

  // get device number provided in the argument
  if (!device_exists) {
    printf("Unable to open the device %s.\n", argv[1]);
    printf("Please make sure you have provided a proper <device_name>.\n");
    printf("  Expected device names = %s\n", boards_name);
    return DIAGNOSE_FAILED;
  }

  asp_loaded = mmd_asp_loaded(argv[1]);
  if (!asp_loaded) {
    printf("\nASP not loaded for Programmable Accelerator Card %s\n", argv[1]);
    printf("  * Run 'aocl diagnose' to determine device name for %s\n",
           argv[1]);
    printf("  * Run 'aocl initialize <device_name> <board_variant>' to initialize "
           "ASP\n\n");
    return DIAGNOSE_FAILED;
  }

  srand(unsigned(time(NULL)));

  int maxbytes = DEFAULT_MAXNUMBYTES;
  if (argc >= 3) {
    maxbytes = atoi(argv[2]);
    if ((atol(argv[2]) < std::numeric_limits<int>::min()) || (atol(argv[2]) > std::numeric_limits<int>::max()))
      maxbytes = DEFAULT_MAXNUMBYTES;
  }

  unsigned maxints = unsigned(maxbytes / sizeof(int));

  unsigned iterations = 1;
  for (unsigned i = maxbytes / DEFAULT_MINNUMBYTES; i >> 1; i = i >> 1)
    iterations++;

  struct speed *readspeed = new struct speed[iterations];
  struct speed *writespeed = new struct speed[iterations];

  bool result = true;

  unsigned int *buf =
      (unsigned int *)acl_util_aligned_malloc(maxints * sizeof(unsigned int));
  unsigned int *output =
      (unsigned int *)acl_util_aligned_malloc(maxints * sizeof(unsigned int));

  // Create sequence: 0 rand1 ~2 rand2 4 ...
  for (unsigned j = 0; j < maxints; j++)
    if (j % 2 == 0)
      buf[j] = (j & 2) ? ~j : j;
    else
      buf[j] = unsigned(rand() * rand());

  ocl_device_init(maxbytes, device_name);

  int block_bytes = DEFAULT_MINNUMBYTES;

  // Warm up
  ocl_writespeed((char *)buf, block_bytes, maxbytes);
  ocl_readspeed((char *)output, block_bytes, maxbytes);

  for (unsigned i = 0; i < iterations; i++, block_bytes *= 2) {
    printf("Transferring %d KBs in %d %d KB blocks ...", maxbytes / 1024,
           maxbytes / block_bytes, block_bytes / 1024);
    writespeed[i] = ocl_writespeed((char *)buf, block_bytes, maxbytes);
    readspeed[i] = ocl_readspeed((char *)output, block_bytes, maxbytes);
    result &= check_results(buf, output, maxints);
    printf(" %.2f MB/s\n", (writespeed[i].fastest > readspeed[i].fastest)
                               ? writespeed[i].fastest
                               : readspeed[i].fastest);
  }

  printf("\nAs a reference:\n");
  printf("PCIe Gen1 peak speed: 250MB/s/lane\n");
  printf("PCIe Gen2 peak speed: 500MB/s/lane\n");
  printf("PCIe Gen3 peak speed: 1GB/s/lane\n");
  printf("PCIe Gen4 peak speed: 2GB/s/lane\n");

  printf("\n");
  printf("Writing %d KBs with block size (in bytes) below:\n", maxbytes / 1024);

  printf("\nBlock_Size Avg    Max    Min    End-End (MB/s)\n");

  float write_topspeed = 0;
  block_bytes = DEFAULT_MINNUMBYTES;
  for (unsigned i = 0; i < iterations; i++, block_bytes *= 2) {
    printf("%8d %.2f %.2f %.2f %.2f\n", block_bytes, writespeed[i].average,
           writespeed[i].fastest, writespeed[i].slowest, writespeed[i].total);

    if (writespeed[i].fastest > write_topspeed)
      write_topspeed = writespeed[i].fastest;
    if (writespeed[i].total > write_topspeed)
      write_topspeed = writespeed[i].total;
  }

  float read_topspeed = 0;
  block_bytes = DEFAULT_MINNUMBYTES;

  printf("\n");

  printf("Reading %d KBs with block size (in bytes) below:\n", maxbytes / 1024);
  printf("\nBlock_Size Avg    Max    Min    End-End (MB/s)\n");
  for (unsigned i = 0; i < iterations; i++, block_bytes *= 2) {
    printf("%8d %.2f %.2f %.2f %.2f\n", block_bytes, readspeed[i].average,
           readspeed[i].fastest, readspeed[i].slowest, readspeed[i].total);

    if (readspeed[i].fastest > read_topspeed)
      read_topspeed = readspeed[i].fastest;
    if (readspeed[i].total > read_topspeed)
      read_topspeed = readspeed[i].total;
  }

  printf("\nWrite top speed = %.2f MB/s\n", write_topspeed);
  printf("Read top speed = %.2f MB/s\n", read_topspeed);
  printf("Throughput = %.2f MB/s\n", (read_topspeed + write_topspeed) / 2);

  if (result)
    printf("\nASP DIAGNOSTIC_PASSED\n");
  else
    printf("\nASP DIAGNOSTIC_FAILED\n");

  acl_util_aligned_free(buf);
  acl_util_aligned_free(output);

  delete[] readspeed;
  delete[] writespeed;

  return (result) ? 0 : DIAGNOSE_FAILED;
}
