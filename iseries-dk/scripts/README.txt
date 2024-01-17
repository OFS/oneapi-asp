This directory contains scripts that are used to generate the OFS HLD oneAPI-ASP
for a specific OFS build.

The scripts are structured as follows:

- build-bsp.sh:
  This script is the entry point for generating the oneAPI-ASP. It compiles required
  software and clones required repositories (if needed) using other scripts
  in this directory.

- dedup-hardware.sh
  Users can use this script after building the oneAPI-ASP. It hardlinks identical files 
  consuming large disk space in $BSP_ROOT/hardware/<board_variant_name_for_non_usm>/build/output_files
  and $BSP_ROOT/hardware/<board_variant_name_for_usm>/build/output_files, thus saving disk space.

- build-bsp-sw.sh
  This script calls other scripts to build OPAE from source (if needed) and builds the
  MMD if it is not already compiled and installed in the oneAPI-ASP repo.

- build-opae.sh
  This script builds OPAE and installs it in the oneAPI-ASP source build directory.
  The version of OPAE that is built is not packaged when creating oneAPI-ASP
  tarball.

- build-mmd.sh
  This script builds the MMD and installs it in the linux64 directory in the
  oneAPI-ASP.  The MMD build is packaged when creating tarball for distribution.

- setup-bsp.py
  This script copies files from the OFS FIM pr-template-release source location to 
  the oneAPI-ASP hardware/<variant>/build/ folder and updates a variety of Quartus 
  setting files.

- build-default-aocx.sh
  This script requires build-bsp.sh to have completed successfully to generate
  oneAPI-ASP. It uses the oneAPI-ASP to compile the boardtest kernel that is used 
  as the default aocx file for the 'aocl initialize' command.

- create-tarball.sh
  This script packages the files needed for oneAPI-ASP, including the default aocx,
  and puts them in a single opencl-bsp.tar.gz file that can be used to
  redistribute the oneAPI-ASP.
