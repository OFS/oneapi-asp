#!/bin/bash

if [ "$#" -eq 0 ]; then
  echo "Please provide the target device(s) as argument(s)."
  exit
fi

PACS=$@

RESOURCES=quartuskit/nfs/site/disks/swuser_work_vtzhang/builds/23.1acs/acds,aclsycltest/2023.1,sycl/rel/20230322,gcc/7.4.0,python/3.7.7,cmake/3.15.4,perl/5.8.8,dev/oneapi_sample_common,cygwin/2.9.0
d5005_FIM=/p/psg/pac/release/main/ofs/release/ofs/2023.1.x/20230413T2055/d5005/fim/pr_build_template/
n6001_FIM=/p/psg/swip/w/boelkrug/releases/ofs-2023.1.x/slimFIM/pr_build_template/

SCRIPT_ROOT=$PWD
ASP_ROOT=${SCRIPT_ROOT}/oneapi-asp
FPGA_TEST_DIR=${SCRIPT_ROOT}/oneAPI-samples/DirectProgramming/C++SYCL_FPGA
OUTPUT_LOG=${SCRIPT_ROOT}/output.txt

echo ""
echo "===== Running with the following settings ====="
echo ""
echo "RESOURCES   : $RESOURCES"
echo "D5005_FIM   : $d5005_FIM"
echo "N6001_FIM   : $n6001_FIM"
echo "ASP_ROOT    : $ASP_ROOT"
echo ""

echo "===== Setting Up for Compiles ====="
echo ""
# Clone oneapi-asp git repo 
echo "Cloning     : oneAPI ASP Repo (https://github.com/OFS/oneapi-asp)"
git clone https://github.com/OFS/oneapi-asp >> $OUTPUT_LOG 2>&1
cd oneapi-asp
echo ""

# Build the BSPs
for PAC in $PACS; do
  echo "Building    : ${PAC} BSP"
  AOCL_BOARD_PACKAGE_ROOT=${ASP_ROOT}/${PAC}
  OFS_OCL_SHIM_ROOT=${ASP_ROOT}/${PAC}
  PYTHONPATH=${ASP_ROOT}/${PAC}/build/opae/install/lib/python3.7/site-packages/
  FIM_VAR="${PAC}_FIM"
  arc shell $RESOURCES name="${PAC} bsp" -- AOCL_BOARD_PACKAGE_ROOT=$AOCL_BOARD_PACKAGE_ROOT OFS_OCL_SHIM_ROOT=$OFS_OCL_SHIM_ROOT PYTHONPATH=$PYTHONPATH OPAE_PLATFORM_ROOT=${!FIM_VAR} ./${PAC}/scripts/build-bsp.sh >> $OUTPUT_LOG 2>&1
  echo ""
done

# Downloading OneAPI Code Samples
echo "Cloning     : oneAPI Code Samples (https://github.com/oneapi-src/oneAPI-samples)"
echo ""
cd $SCRIPT_ROOT
git clone --no-checkout https://github.com/oneapi-src/oneAPI-samples >> $OUTPUT_LOG 2>&1
cd oneAPI-samples
echo "Checking Out: tags/2023.1.0"
echo ""
git checkout tags/2023.1.0 >> $OUTPUT_LOG 2>&1

for PAC in $PACS; do
  cd $SCRIPT_ROOT

  # Setting environment variables
  export AOCL_BOARD_PACKAGE_ROOT=${ASP_ROOT}/${PAC}
  export OFS_OCL_SHIM_ROOT=${ASP_ROOT}/${PAC}
  export PYTHONPATH=${ASP_ROOT}/${PAC}/build/opae/install/lib/python3.7/site-packages/

  # Run all the compiles
  echo "===== Compiling oneAPI Code Samples ====="
  echo ""
  arc shell $RESOURCES name="${PAC} compiles" -- AOCL_BOARD_PACKAGE_ROOT=$AOCL_BOARD_PACKAGE_ROOT OFS_OCL_SHIM_ROOT=$OFS_OCL_SHIM_ROOT PYTHONPATH=$PYTHONPATH ${SCRIPT_ROOT}/compile_oneapi_samples.sh ${PAC}
done

# Wait until all compiles have finished
echo ""

for PAC in $PACS; do

  echo "===== Monitoring and Cleaning Up Compiles for ${PAC} ====="

  ARC_ID_LOG=${SCRIPT_ROOT}/${PAC}_arc_ids.txt

  RESULTS_CSV="${FPGA_TEST_DIR}/${PAC}_compile_results.csv"
  echo "Test Path, Test Executable, Board Variant, Compile Status, Run to HW?, Run Status" > ${RESULTS_CSV}

  echo ""
  echo " STORAGE"
  echo "$(df . -h --output=size,used,avail)"
  echo ""

  while read ARC_ID; do
    cd ${FPGA_TEST_DIR}

    DESIGN=$(arc job-info $ARC_ID name)

    cd $DESIGN
    cd *${PAC}*
    
    echo "$(date)    ${ARC_ID}    ${DESIGN}"

    ARC_STATUS=$(arc job-info $ARC_ID status)

    # Wait until the job is done
    while [[ $ARC_STATUS != "done" ]] ; do
        ARC_STATUS=$(arc job-info $ARC_ID status)
        echo "Compiling"
        if [[ $ARC_STATUS == "error" ]] ; then
          break
        elif [[ $ARC_STATUS == "killed" ]] ; then
          break
        fi
        sleep 900
    done
    
    # If successful compile, remove the .prj directory to save space
    if [[ $ARC_STATUS == "done" ]] ; then
      FPGAFILES=(`find ./ -maxdepth 1 -name "*.fpga"`)
      if [ ${#FPGAFILES[@]} -gt 0 ]; then 
        echo "Succeeded"
        for FILE in "${FPGAFILES[@]}"; do
          [ -f "$FILE" ] || continue
          EXECUTABLE=$(basename $FILE)
          PARENT_DIR=$(basename $(dirname $FILE))
          echo "${DESIGN},${EXECUTABLE},${PARENT_DIR},Pass,Yes," >> ${RESULTS_CSV}
        done 
      else 
        echo "Failed"
        echo "${DESIGN},,,Fail,No,DNR" >> ${RESULTS_CSV}
      fi
      rm -rf *.fpga.prj 
    else
      echo "Failed"
    fi
  done <$ARC_ID_LOG
  
  echo ""
  echo " STORAGE"
  echo "$(df . -h --output=size,used,avail)"
  echo ""
  
done

echo "===== Preparing and Copying to Remote Board ====="
echo ""
cp ${SCRIPT_ROOT}/run_exe.sh ${FPGA_TEST_DIR}/run_exe.sh

# Deal with special db case
DB_FILES='/nfs/site/disks/swip_ofs/ofs_testing/sf1/'
cp -r $DB_FILES $FPGA_TEST_DIR/ReferenceDesigns/db/data/

for PAC in $PACS; do

  cd $FPGA_TEST_DIR

  # Extract .aocx files
  arc shell aclsycltest/2022.2 name="${PAC} aocx" -- aocl-extract-aocx -i Tutorials/DesignPatterns/double_buffering/ofs_${PAC}/double_buffering.fpga -o ofs_${PAC}.aocx >> $OUTPUT_LOG
  arc shell aclsycltest/2022.2 name="${PAC} usm aocx" -- aocl-extract-aocx -i Tutorials/DesignPatterns/buffered_host_streaming/ofs_${PAC}_usm/buffered_host_streaming.fpga -o ofs_${PAC}_usm.aocx >> $OUTPUT_LOG

  cd ..
  
  # Deal with special db case
  mv $FPGA_TEST_DIR/ReferenceDesigns/db/ofs_${PAC}/db.fpga $FPGA_TEST_DIR/ReferenceDesigns/db/db.fpga

  # Copy to remote machines through the passwordless SSH if the user is sys_ofs
  if [[ "$USER" == "sys_ofs" ]] ; then
    if [[ "$PAC" == "d5005" ]] ; then
      arc shell name="${PAC} copy" -- bash ${SCRIPT_ROOT}/copy_exe.sh ${PAC} hlduser 10.228.58.17
    else
      arc shell name="${PAC} copy" -- bash ${SCRIPT_ROOT}/copy_exe.sh ${PAC} hlduser 10.228.58.30
    fi
  fi
done