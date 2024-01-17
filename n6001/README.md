# OneAPI-ASP 

## Overview
This repository contains files necessary to generate ASP for the OFS N6001
reference platform. The hardware currently relies on platforms that implement 
the OFS PCIe TLP format using AXI-S interfaces, and the software uses OPAE SDK 
interfaces.

## Repo Structure

The repository is structured as follows:

* bringup: contains files used by 'aocl install' command to install prerequisite
software on a target system and to load a ASP.  The files are stored in two
separate git submodules that each use git-lfs to store their contents.

* hardware: contains files used by the OneAPI compiler to integrate the 
generated kernel code with platform specific code.  Contains distinct shim 
targets with distinct functionalities (ex. USM and non-USM variants targeting
the same board platform).

* linux64: contains the libraries and utilities that are used by the OneAPI
software stack. The repository itself contains a few scripts that are checked-in
to linux64/libexec. The linux64 directory is also the target for files compiled
from the source directory.

* scripts: a variety of helper scripts used for configuring ASP and for 
running tests

## ASP variants

The `hardware` folder contains subdirectories with the 2 different oneAPI-ASP variants:

* `ofs_n6001_usm`: ASP that supports shared virtual memory between host and device. This 
variant is the same as the non-USM variant with the addition of the USM path between 
the kernel-system and the host.

* `ofs_n6001`:  DMA-based ASP that supports local memory and host memory interfaces for the 
kernel system.

* `ofs_n6001_iopipes`:  DMA-based ASP that supports local memory, host memory, and HSSI/IO Pipes interfaces for the 
kernel system.

* `ofs_n6001_usm_iopipes`:  ASP that supports shared virtual memory between host and device. This 
variant is the same as the non-USM iopipes variant with with the addition of the USM path between 
the kernel-system and the host.

## Generating ASP

Generating a ASP requires 2 primary steps: generating hardware and compiling
the software.

The hardware folder contains code that implements the ASP modules, but it needs
copies of the OFS FIM pr-release-template files to work with a specific platform. 
The setup_bsp.py script copies the required files from the FIM pr-release-template
and updates the project qsf files appropriately.

Need to set **OPAE_PLATFORM_ROOT** to point to pr_build_template in FIM build area.

Need to set **OFS_ASP_ROOT** to point to oneapi-asp/n6001.

To generate ASP hardware and software, acquire the appropriate resources (mentioned above) and run: `scripts/build-bsp.sh`.

To generate MMD software only run: `scripts/build_mmd.sh`

To package generated ASP into tarball run: `scripts/create-tarball.sh`

## Kernel Compilation Options

* Default Kernels - hello_world.cl (for non-USM) , hello_world.cl (for USM).
  Use script - scripts/build-default-aocx.sh.
  Generated aocx will be in $OFS_ASP_ROOT/build/bringup folder.
  Host code will be in $OFS_ASP_ROOT/bringup/source folder

* Flat: This flow compiles both the ASP and the kernel - the entire
  partial reconfiguration (PR) region - without any additional floorplan
  constraints (beyond the existing static region (SR) / PR region constraints).
  This will execute a new place-and-route of the entire PR region - the
  ASP's synthesis/placement/routing is not locked-down when using this flow.
  Timing violations in the fixed-clock domains (DDR, ASP/PCIe) are possible
  when using this flow.
  
Example compilation command: <br>
  `$OFS_ASP_ROOT/$ aoc -v -board=ofs_n6001
  <path to example designs>/example_designs/hello_world/device/hello_world.cl`
  
  If timing violations in static clock domains (not the kernel clock) are persistent
  across multiple seeds, users can try enabling the 
  USE_KERNEL_CLK_EVERYWHERE_IN_PR_REGION define in opencl_bsp.vh - it will move all clock 
  crossings in the PR region closer to the SR-PR boundary (the PIM will manage 
  clock crossings). This may help resolve timing violations; however, the maximum achievable
  kernel clock Fmax may be reduced.
