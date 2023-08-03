# compile oneAPI designs
declare -a non_usm_designs=("anr" "board_test" "cholesky" "cholesky_inversion" "crr" "db" "decompress" "gzip" "merge_sort" "mvdr_beamforming" "qrd" "qri")
declare -a usm_designs=("simple_host_streaming" "buffered_host_streaming" "zero_copy_data_transfer" "explicit_data_movement")
declare -a dbl_buf_design=("double_buffering")

if [[ -z "${AOCL_BOARD_PACKAGE_ROOT}" ]]; then
  echo "AOCL_BOARD_PACKAGE_ROOT not defined, aborting script"
  exit
fi
git clone https://github.com/oneapi-src/oneAPI-samples
cd oneAPI-samples
git checkout tags/2023.1.0

# non-USM designs
cd DirectProgramming/C++SYCL_FPGA/ReferenceDesigns/

for design in "${non_usm_designs[@]}"
do
  echo "building $design"
  cd $design
  mkdir ofs_n6001
  cd ofs_n6001
  directory="src/CMakeFiles/${design}.fpga.dir/link.txt"
  if [[ "$design" == "gzip" ]]
  then  
    cmake ../ -DFPGA_DEVICE=pac_a10
    sed -i 's/pac_a10/ofs_n6001 -Xsno-env-check -Xstiming-failure-mode=ignore -Xstiming-failure-allowed-slack=50/g' $directory
  else
    cmake ../ -DFPGA_DEVICE=pac_s10
    sed -i 's/pac_s10/ofs_n6001 -Xsno-env-check -Xstiming-failure-mode=ignore -Xstiming-failure-allowed-slack=50/g' $directory
  fi
  arc submit node/["memory>=128000"] priority=95 -- PACKAGER_BIN=$OFS_ASP_ROOT/build/opae/install/bin/packager OFS_ASP_ROOT=$OFS_ASP_ROOT PYTHONPATH=$AOCL_BOARD_PACKAGE_ROOT/build/opae/install/lib/python3.8/site-packages AOCL_BOARD_PACKAGE_ROOT=$AOCL_BOARD_PACKAGE_ROOT make fpga
  cd ..
  cd .. 
done

cd ../../../

# USM designs
cd DirectProgramming/C++SYCL_FPGA/Tutorials/DesignPatterns/

for design in "${dbl_buf_design[@]}"
do
  echo "building $design"
  cd $design
  mkdir ofs_n6001
  cd ofs_n6001
  cmake ../ -DFPGA_DEVICE=pac_s10
  directory="src/CMakeFiles/${design}.fpga.dir/link.txt"
  sed -i 's/pac_s10/ofs_n6001 -Xsno-env-check -Xstiming-failure-mode=ignore -Xstiming-failure-allowed-slack=50/g' $directory
  arc submit node/["memory>=128000"] priority=95 -- PACKAGER_BIN=$OFS_ASP_ROOT/build/opae/install/bin/packager OFS_ASP_ROOT=$OFS_ASP_ROOT PYTHONPATH=$AOCL_BOARD_PACKAGE_ROOT/build/opae/install/lib/python3.8/site-packages AOCL_BOARD_PACKAGE_ROOT=$AOCL_BOARD_PACKAGE_ROOT make fpga
  cd ..
  cd .. 
done

for design in "${usm_designs[@]}"
do
  echo "building $design"
  cd $design
  mkdir ofs_n6001_usm
  cd ofs_n6001_usm
  cmake ../ -DFPGA_DEVICE=pac_s10_usm
  directory="src/CMakeFiles/${design}.fpga.dir/link.txt"
  sed -i 's/pac_s10_usm/ofs_n6001_usm -Xsno-env-check -Xstiming-failure-mode=ignore -Xstiming-failure-allowed-slack=50/g' $directory
  arc submit node/["memory>=128000"] priority=95 -- PACKAGER_BIN=$OFS_ASP_ROOT/build/opae/install/bin/packager OFS_ASP_ROOT=$OFS_ASP_ROOT PYTHONPATH=$AOCL_BOARD_PACKAGE_ROOT/build/opae/install/lib/python3.8/site-packages AOCL_BOARD_PACKAGE_ROOT=$AOCL_BOARD_PACKAGE_ROOT make fpga
  cd ..
  cd .. 
done

cd ../../../../
