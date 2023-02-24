This directory contains scripts that are used to generate the OFS HLD Shim
for a specific OFS build.

The scripts are structured as follows:

- build-bsp.sh:
  This script is the entry point for generating the Shim/BSP. It compiles required
  software and clones required repositories (if needed) using other scripts
  in this directory.

- dedup-hardware.sh
  Users can use this script after building the Shim/BSP. It hardlinks identical files 
  consuming large disk space in $BSP_ROOT/hardware/<board_variant_name_for_non_usm>/build/output_files
  and $BSP_ROOT/hardware/<board_variant_name_for_usm>/build/output_files, thus saving disk space.

- build-bsp-sw.sh
  This script calls other scripts to build OPAE from source (if needed) and builds the
  MMD if it is not already compiled and installed in the Shim/BSP repo.

- build-opae.sh
  This script builds OPAE and installs it in the Shim/BSP source build directory.
  The version of OPAE that is built is not packaged when creating Shim/BSP
  tarball.

- build-mmd.sh
  This script builds the MMD and installs it in the linux64 directory in the
  Shim/BSP.  The MMD build is packaged when creating tarball for distribution.

- setup-bsp.py
  This script copies files from the OFS FIM pr-template-release source location to 
  the Shim/BSP hardware/<variant>/build/ folder and updates a variety of Quartus 
  setting files.

- build-default-aocx.sh
  This script requires build-bsp.sh to have completed successfully to generate
  Shim/BSP. It uses the Shim/BSP to compile the boardtest kernel that is used 
  as the default aocx file for the 'aocl initialize' command.

- create-tarball.sh
  This script packages the files needed for Shim/BSP, including the default aocx,
  and puts them in a single opencl-bsp.tar.gz file that can be used to
  redistribute the Shim/BSP.
