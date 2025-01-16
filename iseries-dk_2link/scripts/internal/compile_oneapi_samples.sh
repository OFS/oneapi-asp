#!/bin/bash

# Compile oneAPI Designs
declare -a DESIGNS=("Tutorials/Features/ac_fixed" "Tutorials/Features/ac_int" "ReferenceDesigns/board_test" "ReferenceDesigns/cholesky" "ReferenceDesigns/cholesky_inversion" "Tutorials/DesignPatterns/compute_units" "ReferenceDesigns/crr" "ReferenceDesigns/db" "ReferenceDesigns/decompress" "Tutorials/DesignPatterns/double_buffering" "Tutorials/Features/dsp_control" "Tutorials/Tools/dynamic_profiler" "Tutorials/GettingStarted/fpga_compile" "Tutorials/Features/fpga_reg" "ReferenceDesigns/gzip" "Tutorials/Features/kernel_args_restrict" "Tutorials/Features/experimental/latency_control" "Tutorials/DesignPatterns/loop_carried_dependency" "Tutorials/Features/loop_coalesce" "Tutorials/Features/loop_fusion" "Tutorials/Features/loop_initiation_interval" "Tutorials/Features/loop_ivdep" "Tutorials/Features/loop_unroll" "Tutorials/Features/lsu_control" "Tutorials/Features/max_interleaving" "Tutorials/Features/mem_channel" "Tutorials/Features/memory_attributes" "ReferenceDesigns/merge_sort" "Tutorials/DesignPatterns/n_way_buffering" "Tutorials/DesignPatterns/onchip_memory_cache" "Tutorials/DesignPatterns/optimize_inner_loop" "Tutorials/DesignPatterns/pipe_array" "Tutorials/Features/pipes" "Tutorials/Features/printf" "Tutorials/Features/private_copies" "ReferenceDesigns/qrd" "ReferenceDesigns/qri" "Tutorials/Features/read_only_cache" "Tutorials/Features/scheduler_target_fmax" "Tutorials/DesignPatterns/shannonization" "Tutorials/Features/speculated_iterations" "Tutorials/Features/stall_enable" "Tutorials/Tools/system_profiling" "Tutorials/DesignPatterns/triangular_loop" "Tutorials/DesignPatterns/buffered_host_streaming" "Tutorials/DesignPatterns/explicit_data_movement" "Tutorials/DesignPatterns/simple_host_streaming" "Tutorials/DesignPatterns/zero_copy_data_transfer" "ReferenceDesigns/anr" "ReferenceDesigns/mvdr_beamforming" "Tutorials/GettingStarted/fast_recompile")
declare -a USM_DESIGNS=("Tutorials/DesignPatterns/buffered_host_streaming" "Tutorials/DesignPatterns/explicit_data_movement" "Tutorials/DesignPatterns/simple_host_streaming" "Tutorials/DesignPatterns/zero_copy_data_transfer")
FAST_RECOMPILE="Tutorials/GettingStarted/fast_recompile"

if [ "$#" -ne 1 ]; then
  echo "Please provide the target device as argument."
  exit
else
  PAC=${1}
  DIR_NONUSM="ofs_${PAC}"
  DIR_USM="ofs_${PAC}_usm"

  FPGA_BOARD_NONUSM="pac_s10"
  FPGA_BOARD_USM="pac_s10_usm"
fi

if [[ -z "${AOCL_BOARD_PACKAGE_ROOT}" ]]; then
  echo "AOCL_BOARD_PACKAGE_ROOT not defined, aborting script"
  exit
elif [[ -z "${OFS_OCL_SHIM_ROOT}" ]]; then
  echo "OFS_OCL_SHIM_ROOT not defined, aborting script"
  exit
elif [[ -z "${PYTHONPATH}" ]]; then
  echo "PYTHONPATH not defined, aborting script"
  exit
fi

SCRIPT_ROOT=${PWD}
ARC_ID_LOG=${SCRIPT_ROOT}/${PAC}_arc_ids.txt
rm $ARC_ID_LOG
OUTPUT_LOG=${SCRIPT_ROOT}/output.txt

FPGA_TEST_DIR=${SCRIPT_ROOT}/oneAPI-samples/DirectProgramming/C++SYCL_FPGA/

for DESIGN in "${DESIGNS[@]}"
do
  echo ""

  cd ${FPGA_TEST_DIR}
  cd $DESIGN
  mkdir $DIR_NONUSM
  cd $DIR_NONUSM
  DIRECTORY="src/CMakeFiles/*.fpga.dir/link.txt"
  if [[ ${FAST_RECOMPILE} == ${DESIGN} ]]; then
    DIRECTORY="src/CMakeFiles/fpga.dir/build.make"
  fi
  if [[ " ${USM_DESIGNS[*]} " =~ " ${DESIGN} " ]]; then
    echo "Platform    : ${DIR_USM}"
    cmake ../ -DFPGA_DEVICE=${FPGA_BOARD_USM} >> $OUTPUT_LOG
    sed -i "s/${FPGA_BOARD_USM}/${DIR_USM} -Xstiming-failure-mode=ignore -Xstiming-failure-allowed-slack=50/g" $directory
  else
    echo "Platform    : ${DIR_NONUSM}"
    cmake ../ -DFPGA_DEVICE=${FPGA_BOARD_NONUSM} >> $OUTPUT_LOG
    sed -i "s/${FPGA_BOARD_NONUSM}/${DIR_NONUSM} -Xstiming-failure-mode=ignore -Xstiming-failure-allowed-slack=50/g" $DIRECTORY
  fi
  echo "Design      : ${DESIGN}"
  arc submit node/["memory>=128000"] name=$DESIGN priority=95 -- OFS_OCL_SHIM_ROOT=$OFS_OCL_SHIM_ROOT PYTHONPATH=$PYTHONPATH AOCL_BOARD_PACKAGE_ROOT=$AOCL_BOARD_PACKAGE_ROOT make fpga | tee -a $ARC_ID_LOG
done

echo ""
