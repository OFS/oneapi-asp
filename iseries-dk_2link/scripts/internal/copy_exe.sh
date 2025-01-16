#!/bin/bash

# copy oneAPI designs over to OFS machine

if [ "$#" -ne 3 ]; then
  echo "Please provide the target device, and OFS machine (USER@ADDRESS) as argument."
  echo "Example command: ./copy_exe.sh n6001 hlduser 10.228.58.30"
  exit
elif [ ! -d "C++SYCL_FPGA" ]; then
  echo "Must have subdirectory C++SYCL_FPGA"
  echo "Retry script in the correct folder"
  exit
else
  PAC="${1}"
  USER="${2}"
  ADDRESS="${3}"
  DATE_TIME=$(date '+%m%d_%H_%M')
fi

echo "Copying C++SYCL_FPGA to ${USER}@${ADDRESS}:/home/${USER}/oneAPI_testing/${PAC}/${DATE_TIME}"

if [[ ! "$USER" == "sys_ofs" ]] ; then
  if [[ $PAC == "n6001" ]] ; then
    rsync -avh --exclude '*d5005*' C++SYCL_FPGA ${USER}@${ADDRESS}:/home/${USER}/oneAPI_testing/${PAC}/${DATE_TIME}
  else
    rsync -avh --exclude '*n6001*' C++SYCL_FPGA ${USER}@${ADDRESS}:/home/${USER}/oneAPI_testing/${PAC}/${DATE_TIME}
  fi
else
  if [[ $PAC == "n6001" ]] ; then
    rsync -avh --exclude '*d5005*' -i ~/.ssh/lab_sudo_n6001 C++SYCL_FPGA ${USER}@${ADDRESS}:/home/${USER}/oneAPI_testing/${PAC}/${DATE_TIME}
  else
    rsync -avh --exclude '*n6001*' -i ~/.ssh/lab_sudo_d5005 C++SYCL_FPGA ${USER}@${ADDRESS}:/home/${USER}/oneAPI_testing/${PAC}/${DATE_TIME}
  fi
fi