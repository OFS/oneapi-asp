#!/bin/bash

# Copyright 2022 Intel Corporation
# SPDX-License-Identifier: MIT

if [ -n "$OFS_OCL_ENV_DEBUG_SCRIPTS" ]; then
  set -x
fi

echo "This is the OFS HLD shim BSP run.sh script."

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
echo "OFS BSP build dir: $SCRIPT_DIR_PATH"

#if flow-type is 'flat_kclk' uncomment USE_KERNEL_CLK_EVERYWHERE_IN_PR_REGION in opencl_bsp.vh
if [ ${BSP_FLOW} = "afu_flat_kclk" ]; then
    echo "Enabling the USE_KERNEL_CLK_EVERYWHERE_IN_PR_REGION define in the Shim RTL..."
    SHIM_HEADER_FILE_NAME="${SCRIPT_DIR_PATH}/../rtl/opencl_bsp.vh"
    echo "Modifying the header file ${SHIM_HEADER_FILE_NAME} to uncomment the define and include it in the design."
    sed -i -e 's/\/\/`define USE_KERNEL_CLK_EVERYWHERE_IN_PR_REGION/`define USE_KERNEL_CLK_EVERYWHERE_IN_PR_REGION/' "$SHIM_HEADER_FILE_NAME"
    BSP_FLOW="afu_flat"
fi

cd "$SCRIPT_DIR_PATH/.." || exit

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
if [ ! -f "d5005.qdb" ]; then
    echo "ERROR: BSP is not setup"
fi

cp ../quartus.ini .

#import opencl kernel files
quartus_sh -t scripts/import_opencl_kernel.tcl

#check for bypass/alternative flows
if [ -n "$OFS_OCL_ENV_ENABLE_ASE" ]; then
    echo "Calling ASE simulation flow compile"
    sh ./scripts/ase-sim-compile.sh
    exit $?
fi

#add BBBs to quartus pr project
quartus_sh -t scripts/add_bbb_to_pr_project.tcl "$BSP_FLOW"

cp ../afu_opencl_kernel.qsf .

# use ip-deploy to create board.ip file from toplevel Platform Designer
# project board_hw.tcl
ip-deploy --component-name=board 

# use qsys-generate to create RTL from toplevel Platform Designer
# board.ip file
qsys-generate -syn --quartus-project=d5005 --rev=afu_flat board.ip

#append kernel_system qsys/ip assignments to all revisions
rm -f kernel_system_qsf_append.txt
{ echo
  grep -A10000 OPENCL_KERNEL_ASSIGNMENTS_START_HERE afu_opencl_kernel.qsf
  echo
} >> kernel_system_qsf_append.txt

cat kernel_system_qsf_append.txt >> afu_flat.qsf


# compile project
# =====================
quartus_sh -t scripts/compile_script.tcl "$BSP_FLOW"
FLOW_SUCCESS=$?

# Report Timing
# =============
if [ $FLOW_SUCCESS -eq 0 ]
then
    quartus_sh -t scripts/adjust_plls.tcl d5005 "${BSP_FLOW}"
else
    echo "ERROR: kernel compilation failed. Please see quartus_sh_compile.log for more information."
    exit 1
fi

#run packager tool to create GBS
BBS_ID_FILE="fme-ifc-id.txt"
if [ -f "$BBS_ID_FILE" ]; then
    FME_IFC_ID=$(cat $BBS_ID_FILE)
else
    echo "ERROR: fme id not found."
    exit 1
fi

PLL_METADATA_FILE="pll_metadata.txt"
if [ -f "$PLL_METADATA_FILE" ]; then
    IFS=" " read -r -a PLL_METADATA <<< "$(cat $PLL_METADATA_FILE)"
else
    echo "Error: cannot find $PLL_METADATA_FILE"
    exit 1
fi

#check for generated rbf and gbs files
if [ ! -f "./output_files/${BSP_FLOW}.persona1.rbf" ]; then
    echo "ERROR: ./output_files/${BSP_FLOW}.persona1.rbf is missing!"
    exit 1
fi

rm -f afu.gbs
$PACKAGER_BIN create-gbs \
    --rbf "./output_files/${BSP_FLOW}.persona1.rbf" \
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
cp fpga.bin ../
cp acl_quartus_report.txt ../

echo ""
echo "==========================================================================="
echo "OpenCL AFU compilation complete"
echo "==========================================================================="
echo ""
