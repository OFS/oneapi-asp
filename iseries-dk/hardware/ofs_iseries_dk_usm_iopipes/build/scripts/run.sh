#!/bin/bash

# Copyright 2022 Intel Corporation
# SPDX-License-Identifier: MIT

if [ -n "$OFS_ASP_ENV_DEBUG_SCRIPTS" ]; then
  set -x
fi

echo "This is the OFS OneAPI ASP run.sh script."

KERNEL_BUILD_PWD=`pwd`
echo "run.sh KERNEL_BUILD_PWD is $KERNEL_BUILD_PWD"

BSP_BUILD_PWD="$KERNEL_BUILD_PWD/../"
echo "run.sh BSP_BUILD_PWD is $BSP_BUILD_PWD"

Q_REVISION="ofs_top"
echo "Q_REVISION is $Q_REVISION"
Q_PR_PARTITION_NAME="green_region"
echo "Q_PR_PARTITION_NAME is $Q_PR_PARTITION_NAME"

# set BSP flow
if [ $# -eq 0 ]
then
    BSP_FLOW="afu_flat"
else
    BSP_FLOW="$1"
fi
echo "Compiling '$BSP_FLOW' bsp-flow"

SCRIPT_PATH=$(readlink -f "${BASH_SOURCE[0]}")
echo "OFS BSP run.sh script path: $SCRIPT_PATH"
SCRIPT_DIR_PATH="$(dirname "$SCRIPT_PATH")"

#if flow-type is 'flat_kclk' uncomment USE_KERNEL_CLK_EVERYWHERE_IN_PR_REGION in opencl_bsp.vh
if [ ${BSP_FLOW} = "afu_flat_kclk" ]; then
    echo "Enabling the USE_KERNEL_CLK_EVERYWHERE_IN_PR_REGION define in the Shim RTL..."
    SHIM_HEADER_FILE_NAME="${SCRIPT_DIR_PATH}/../rtl/opencl_bsp.vh"
    echo "Modifying the header file ${SHIM_HEADER_FILE_NAME} to uncomment the define and include it in the design."
    sed -i -e 's/\/\/`define USE_KERNEL_CLK_EVERYWHERE_IN_PR_REGION/`define USE_KERNEL_CLK_EVERYWHERE_IN_PR_REGION/' "$SHIM_HEADER_FILE_NAME"
    BSP_FLOW="afu_flat"
fi

cd "$SCRIPT_DIR_PATH/.." || exit
AFU_BUILD_PWD=`pwd`
echo "run.sh AFU_BUILD_PWD is $AFU_BUILD_PWD"

if [ -n "$PACKAGER_BIN" ]; then
  echo "Selected explicitly configured PACKAGER_BIN=\"$PACKAGER_BIN\""
elif [ -z "$OFS_ASP_ENV_USE_BSP_PACKAGER" ] && PACKAGER_BIN="$(command -v packager)"; then
  echo "Detected PACKAGER_BIN=\"$PACKAGER_BIN\" from \$PATH search"
else
  echo "Attempting fallback to BSP copy of packager"
  if [ -f ./tools/packager ]; then
    chmod +x ./tools/packager
    PACKAGER_BIN=$(readlink -f ./tools/packager)
    PYTHONPATH=`find $OFS_ASP_ROOT -path *install*site-packages`
    echo "PYTHONPATH is $PYTHONPATH"
  else
    echo "Error cannot find BSP copy of packager"
    exit 1
  fi
fi

if ! PACKAGER_OUTPUT=$($PACKAGER_BIN); then
    echo "ERROR: packager ($PACKAGER_BIN) check failed with output '$PACKAGER_OUTPUT'"
    exit 1
fi

##make sure bbs files exist
if [[ ! $(find . -name ofs_top.qdb -print -quit) ]]
then
    echo "ERROR: BSP is not setup"
    exit 1
fi

RELATIVE_BSP_BUILD_PATH_TO_HERE=`realpath --relative-to=$AFU_BUILD_PWD $BSP_BUILD_PWD`
RELATIVE_KERNEL_BUILD_PATH_TO_HERE=`realpath --relative-to=$AFU_BUILD_PWD $KERNEL_BUILD_PWD`
#create new '$BSP_FLOW' revision based on the one used to compile the kernel
cp -f ${RELATIVE_KERNEL_BUILD_PATH_TO_HERE}/ofs_pr_afu.qsf ./$BSP_FLOW.qsf
#add ASP/$BSP_FLOW-specific stuff to the qsf file
echo "source afu_ip.qsf" >> ./$BSP_FLOW.qsf

#symlink the compiled kernel files to here from their origin (except the )
MYLIST=`ls --ignore=fim_platform --ignore=build $RELATIVE_KERNEL_BUILD_PATH_TO_HERE`
for f in ${MYLIST}
do
    #merge the ASP's 'ip' folder with the kernel-system's 'ip' folder
    if [ "$f" == "ip" ]; then
        cd ip
        ln -s ../${RELATIVE_KERNEL_BUILD_PATH_TO_HERE}/ip/* .
        cd  ..
    else
        ln -s ${RELATIVE_KERNEL_BUILD_PATH_TO_HERE}/${f} .
    fi
done

qsys-generate -syn --quartus-project=$Q_REVISION --rev=$BSP_FLOW board.qsys
## adding board.qsys and corresponding .ip parameterization files to opencl_bsp_ip.qsf
qsys-archive --quartus-project=$Q_REVISION --rev=$BSP_FLOW --add-to-project board.qsys

# compile project
# =====================
#check for bypass/alternative flows
if [ -n "$OFS_ASP_ENV_ENABLE_ASE" ]; then
    echo "Calling ASE simulation flow compile"
    sh ./scripts/ase-sim-compile.sh
    exit $?
fi

echo "Starting: quartus_sh --flow compile $Q_REVISION -c $BSP_FLOW"
quartus_sh --flow compile $Q_REVISION -c $BSP_FLOW

rm -rf fpga.bin

generated_gbs="${BSP_FLOW}"."${Q_PR_PARTITION_NAME}".gbs
if [ ! -f ./output_files/"${generated_gbs}" ]; then
    echo "run.sh ERROR: can't find ./output_files/${generated_gbs}"
    exit 1
fi

gzip -9c ./output_files/$generated_gbs > $generated_gbs.gz
aocl binedit fpga.bin create
aocl binedit fpga.bin add .acl.gbs.gz "./${generated_gbs}.gz"

echo "run.sh: done zipping up the gbs into gbs.gz, and creating fpga.bin"

if [ -f "${BSP_FLOW}.failing_clocks.rpt" ]; then
    aocl binedit fpga.bin add .failing_clocks.rpt "./${BSP_FLOW}.failing_clocks.rpt"
    cp "./${BSP_FLOW}.failing_clocks.rpt" ../
    echo "run.sh: done appending failing clocks report to fpga.bin"
fi

if [ -f "${BSP_FLOW}.failing_paths.rpt" ]; then
    aocl binedit fpga.bin add .failing_paths.rpt "./${BSP_FLOW}.failing_paths.rpt"
    cp "./${BSP_FLOW}.failing_paths.rpt" ../
    echo "run.sh: done appending failing paths report to fpga.bin"
fi

if [ ! -f fpga.bin ]; then
    echo "run.sh ERROR: no fpga.bin found.  FPGA compilation failed!"
    exit 1
fi

echo "run.sh: generate acl_quartus_report.txt"
quartus_sh -t scripts/gen-asp-quartus-report.tcl ofs_top "${BSP_FLOW}"

#copy fpga.bin to parent directory so oneAPI flow can find it
cp fpga.bin $RELATIVE_KERNEL_BUILD_PATH_TO_HERE/
cp acl_quartus_report.txt $RELATIVE_KERNEL_BUILD_PATH_TO_HERE/

echo ""
echo "==========================================================================="
echo "OneAPI ASP AFU compilation complete"
echo "==========================================================================="
echo ""
