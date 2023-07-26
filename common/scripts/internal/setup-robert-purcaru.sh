#!/bin/bash

if [ -z $1 ] ; then
    echo "specify fim"
    exit 1
fi

if [ "$1" = "d5005" ] ; then
    export OFS_OCL_SHIM_ROOT=/nfs/site/disks/swuser_work_robertpu/Github/ASPRedundancyReduction/robert-purcaru_oneapi-asp/d5005
    export AOCL_BOARD_PACKAGE_ROOT=/nfs/site/disks/swuser_work_robertpu/Github/ASPRedundancyReduction/robert-purcaru_oneapi-asp/d5005
    export PYTHONPATH=$AOCL_BOARD_PACKAGE_ROOT/build/opae/install/lib/python3.7/site-packages
    export OPAE_PLATFORM_ROOT=/p/psg/pac/release/main/ofs/release/ofs/2023.1/20230516T0519/d5005/fim/pr_build_template
elif [ "$1" = "n6001" ] ; then
    export OFS_OCL_SHIM_ROOT=/nfs/site/disks/swuser_work_robertpu/Github/ASPRedundancyReduction/robert-purcaru_oneapi-asp/n6001
    export AOCL_BOARD_PACKAGE_ROOT=/nfs/site/disks/swuser_work_robertpu/Github/ASPRedundancyReduction/robert-purcaru_oneapi-asp/n6001
    export PYTHONPATH=$AOCL_BOARD_PACKAGE_ROOT/build/opae/install/lib/python3.7/site-packages
    export OPAE_PLATFORM_ROOT=/p/psg/pac/release/main/ofs/release/ofs/2023.1/20230516T0519/n6001/slim_fim/seed_1/pr_build_template
else
    echo "specify fim (n6001 or d5005)"
fi

echo "paste this for arc resources:" 
echo "OFS_OCL_ENV_ENABLE_ASE=1 ./run-with-arc.sh /bin/bash"
