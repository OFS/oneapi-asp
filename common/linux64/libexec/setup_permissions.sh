#!/bin/bash

## Copyright 2022 Intel Corporation
## SPDX-License-Identifier: MIT

################################################################################
# This script configure host OS to allow OpenCL workload to run successful on
# the host.  There are 3 settings that need to be changed from the default
# OFS configuration.
#
# 1) Enable users to lock pages in memory:
#
# 2) Change intel-fpga device permissions:
#
# 3) Change number of 2M huge pages:
################################################################################

################################################################################
# Utility function for checking if operation was successful
################################################################################
check_res()
{
  ret_code="$1"
  msg="$2"
  if [ "$ret_code" -ne 0 ]; then
    echo "Error: $msg"
    exit "$ret_code"
  fi
}

################################################################################
# Configure memlock settings to allow any user to lock pages in memory
#
# By default in Linux ordinary users can only lock 64 KB of virtual memory
# in the host to prevent OS from paging the memory to disk.  The OPAE
# software stack requires locking pages in memory that are shared between
# the host and FPGA.  The default configuration set in this script allows
# users to lock ulimited number of pages in memory (up-to amount of physical)
# memory in host.
################################################################################
set_memlock_limits()
{
  echo "Configuring locked memory setting"
  sudo sh -c "cat > /etc/security/limits.d/90-intel-fpga-opencl-limits.conf" << EOF
*	soft	memlock	unlimited
*	hard	memlock	unlimited
EOF

  check_res $? "Error: unable to enable memlock settings"

  lock_limit=$(ulimit -l)
  if [ $lock_limit != "unlimited" ]; then
    echo "** NOTE:changes to max locked memory setting only take effect with new login session"
  fi
}

################################################################################
# Set device permissions to allow all users to perform PR
#
# By default the intel-fpga driver restricts management functions to require
# root privilege.  However, OpenCL expects that ordinary users can perform
# partial reconfiguration (PR) to load a bitstream when the application starts
# executing.  This changes the device permissions to allow any user to access
# management features that are needed to perform PR.
################################################################################
set_dev_permission()
{
  echo "Configuring udev rules for DFL FPGA device permission"
  sudo sh -c "cat > /etc/udev/rules.d/90-intel-fpga-opencl.rules" << EOF
# Set device permission to allow regular user to perform PR, required for OpenCL

# S10 FME permisison
KERNEL=="dfl-fme.[0-9]*", ACTION=="add|change", GROUP="root", MODE="0666", RUN+="/bin/bash -c 'chmod 0666 %S%p/errors/* /dev/%k'"

# S10 port permission
KERNEL=="dfl-port.[0-9]*", ACTION=="add|change", GROUP="root", MODE="0666", RUN+="/bin/bash -c 'chmod 0666 %S%p/dfl*/userclk/frequency %S%p/errors/* /dev/%k'"

EOF

  check_res $? "Error: unable to configure intel-fpga device permission"

  sudo udevadm control --reload-rules
  sudo udevadm trigger --subsystem-match=platform --property-match=DRIVER="dfl-fme"
  sudo udevadm trigger --subsystem-match=platform --property-match=DRIVER="dfl-port" 

}

################################################################################
# Configure 2M huge pages
#
# Hugepages are used to improve performance of the DMA operations between host
# and FPGA.  The OFS oneAPI-ASP requires a minimum of 4 2M hugepages per FPGA.
# However, there is additional optimization that allows user to pre-pin memory
# using hugepages.  The default setting in this script configures 2048 2M
# hugepages.  This means 4G of host memory is allocated for hugepages.
# This can be changed by configuring OFS_ASP_ENV_NUM_HUGEPAGES before running
# this script.
################################################################################
set_hugepages()
{
  NUM_HUGE_PAGES=${OFS_ASP_ENV_NUM_HUGEPAGES:-1024}
  echo "Configuring system with $NUM_HUGE_PAGES 2M hugepages"
  sudo sh -c "cat > /etc/sysctl.d/intel-fpga-opencl-sysctl.conf" << EOF
vm.nr_hugepages = $NUM_HUGE_PAGES
EOF

  check_res $? "Error: unable to configure hugepages"
  sudo sh -c "echo $NUM_HUGE_PAGES > /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages"
}

################################################################################
# Set aocl initialize permissions
#
# To run aocl initialize, read and write permissions are needed for Others class
################################################################################
set_devuio_permissions()
{
  echo "Setting access permisions of /dev/uio to 666"
  sudo chmod 666 /dev/uio*
}

set_memlock_limits
set_dev_permission
set_hugepages
set_devuio_permissions


echo "Finished setup_permissions.sh script. All configuration settings are persistent."
