#!/bin/bash

# Copyright 2022 Intel Corporation
# SPDX-License-Identifier: MIT

echo "Start of sim_compile.sh"

rm -fr sim_files
mkdir sim_files

KERNEL_SYSTEM_QIP_FILE="./kernel_system.qip"
while IFS= read -r line
do
    ACL_FILE_TO_COPY=$(echo $line | awk '{ print $7 }' | sed 's/"//g' | sed "s|^.*INTELFPGAOCLSDKROOT)|$INTELFPGAOCLSDKROOT|g" | sed 's/]//g')
    cp $ACL_FILE_TO_COPY ./sim_files
done < "$KERNEL_SYSTEM_QIP_FILE"

for this_ip in board kernel_system ddr_board ddr_channel msgdma_bbb ase cci_interface
do
    echo "this-ip is $this_ip"
    find $this_ip -name synth | xargs -n1 -IAAA find AAA -name "*.v" -o -name "*.sv" -o -name "*.iv" | xargs cp -t ./sim_files
    find ip/$this_ip -name synth | xargs -n1 -IAAA find AAA -name "*.v" -o -name "*.sv" -o -name "*.iv" | xargs cp -t ./sim_files
done

find kernel_hdl -type f | xargs cp -t ./sim_files

find . -name "*.vhd" -type f | grep dspba | xargs cp -t ./sim_files
find . -name "*vh" -type f | xargs cp -t  ./sim_files
find ./rtl/ -name "*v" -type f | xargs cp -t  ./sim_files

cp -rf ./ip/*v ./sim_files
#cp -rf ./rtl/*v ./sim_files
cp -fr ./ip/BBB_* sim_files/

cp -rf mem_sim_model.sv ./sim_files/mem_sim_model.sv

find *.sv  | xargs cp -t ./sim_files

cp -Lrf ./*v ./sim_files/

rm simulation.tar.gz
tar -hzcvf simulation.tar.gz sim_files sys_description.hex *.hex 
cp -rf simulation.tar.gz fpga.bin

#copy fpga.bin to parent directory so aoc flow can find it
echo "Quartus compilation occurs deep in fim_platform; need to copy fpga.bin back up to where OneAPI compiler expects it."
cp fpga.bin ../../../../../..

echo "end of sim_compile.sh"
