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
    PYTHONPATH="$OFS_ASP_ROOT/build/opae/install/lib/python3.8/site-packages"
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
fi

RELATIVE_BSP_BUILD_PATH_TO_HERE=`realpath --relative-to=$AFU_BUILD_PWD $BSP_BUILD_PWD`
RELATIVE_KERNEL_BUILD_PATH_TO_HERE=`realpath --relative-to=$AFU_BUILD_PWD $KERNEL_BUILD_PWD`
#create new 'afu_flat' revision based on the one used to compile the kernel
cp -f ${RELATIVE_KERNEL_BUILD_PATH_TO_HERE}/ofs_pr_afu.qsf ./afu_flat.qsf
#add ASP/afu_flat-specific stuff to the qsf file
echo "source afu_ip.qsf" >> ./afu_flat.qsf

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

qsys-generate -syn --quartus-project=ofs_top --rev=afu_flat board.qsys
## adding board.qsys and corresponding .ip parameterization files to opencl_bsp_ip.qsf
qsys-archive --quartus-project=ofs_top --rev=afu_flat --add-to-project board.qsys

# compile project
# =====================
#check for bypass/alternative flows
if [ -n "$OFS_ASP_ENV_ENABLE_ASE" ]; then
    echo "Calling ASE simulation flow compile"
    sh ./scripts/ase-sim-compile.sh
    exit $?
fi

echo "Calling compile_script"
quartus_sh -t scripts/compile_script.tcl "$BSP_FLOW"
FLOW_SUCCESS=$?

# Report Timing
# =============
DO_ADJUST_PLLS=1
PLL_METADATA_FILE="pll_metadata.txt"
if [ $FLOW_SUCCESS -eq 0 ]
then
    if [ $DO_ADJUST_PLLS -eq 0 ]; then
        echo "Not running adjust_plls.tcl. We still need to create a pll_metadata.txt file. Doing that now with 1x clock @ 150MHz and 2x clock @ 300 MHz."
        echo "clock-frequency-low:150 clock-frequency-high:300" >> "$PLL_METADATA_FILE"
    else
        echo "Running adjust_plls.txt script to find the highest valid kernel_clock."
        quartus_sh -t scripts/adjust_plls.tcl ofs_top "${BSP_FLOW}"
    fi
else
    echo "ERROR: kernel compilation failed. Please see quartus_sh_compile.log for more information."
    exit 1
fi

#run packager tool to create GBS
BBS_ID_FILE="fme-ifc-id.txt"
if [ -f "$BBS_ID_FILE" ]; then
    FME_IFC_ID=$(cat $BBS_ID_FILE)
    echo "FME_IFC_ID is $FME_IFC_ID"
    cat $BBS_ID_FILE
else
    echo "ERROR: fme id not found."
    exit 1
fi

if [ -f "$PLL_METADATA_FILE" ]; then
    IFS=" " read -r -a PLL_METADATA <<< "$(cat $PLL_METADATA_FILE)"
else
    echo "Error: cannot find $PLL_METADATA_FILE"
    exit 1
fi

#check for generated rbf and gbs files
if [ ! -f "./output_files/${BSP_FLOW}.green_region.rbf" ]; then
    echo "ERROR: ./output_files/${BSP_FLOW}.green_region.rbf is missing!"
    exit 1
fi

rm -f ./output_files/"${BSP_FLOW}".gbs
$PACKAGER_BIN create-gbs \
    --rbf "./output_files/${BSP_FLOW}.green_region.rbf" \
    --gbs "./output_files/${BSP_FLOW}.gbs" \
    --afu-json opencl_afu.json \
    --set-value \
        interface-uuid:"$FME_IFC_ID" \
        "${PLL_METADATA[@]}"

FLOW_SUCCESS=$?
if [ $FLOW_SUCCESS != 0 ]; then
    echo "ERROR: packager tool failed to create .gbs file."
    exit 1
fi

rm -rf fpga.bin

gzip -9c ./output_files/"${BSP_FLOW}".gbs > "${BSP_FLOW}".gbs.gz
aocl binedit fpga.bin create
aocl binedit fpga.bin add .acl.gbs.gz "./${BSP_FLOW}.gbs.gz"

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
    echo "ERROR: no fpga.bin found.  FPGA compilation failed!"
    exit 1
fi

#copy fpga.bin to parent directory so aoc flow can find it
cp fpga.bin $RELATIVE_KERNEL_BUILD_PATH_TO_HERE/
cp acl_quartus_report.txt $RELATIVE_KERNEL_BUILD_PATH_TO_HERE/

echo ""
echo "==========================================================================="
echo "OneAPI ASP AFU compilation complete"
echo "==========================================================================="
echo ""
