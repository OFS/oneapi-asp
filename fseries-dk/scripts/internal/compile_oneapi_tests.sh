
if [ -z $1 ]; then
    if pwd | grep -qw "n6001"; then
        PLATFORM_TARGET="ofs_n6001"
    else
        PLATFORM_TARGET="ofs_d5005"
    fi
else
    PLATFORM_TARGET="$1"
fi
echo "Using $PLATFORM_TARGET as the base variant"

# compile oneAPI designs
declare -a non_usm_designs=("anr" "board_test" "cholesky" "cholesky_inversion" "crr" "db" "decompress" "gzip" "merge_sort" "mvdr_beamforming" "qrd" "qri" "double_buffering")
declare -a usm_designs=("simple_host_streaming" "buffered_host_streaming" "zero_copy_data_transfer" "explicit_data_movement")
declare -a iopipes_designs=("io_streaming_multi_pipes" "io_streaming_one_pipe")

#group all of the designs into a single array
if [ "${PLATFORM_TARGET}" == "ofs_n6001" ]; then
    declare -a all_designs=("${non_usm_designs[@]}" "${usm_designs[@]}" "${iopipes_designs[@]}")
else
    declare -a all_designs=("${non_usm_designs[@]}" "${usm_designs[@]}")
fi

if [[ -z "${AOCL_BOARD_PACKAGE_ROOT}" ]]; then
  echo "AOCL_BOARD_PACKAGE_ROOT not defined, aborting script"
  exit
fi

echo "The designs I'm about to build are: "
for a in "${all_designs[@]}"; do
    echo "$a"
done

#send the build(s) to ARC to run in parallel; or don't send them to ARC to run then locally and serially
USE_ARC=1
#STARTING_SEED is the first seed to use
STARTING_SEED=1
#NUM_SEEDS is the number of seeds you want to compile
NUM_SEEDS=1

THIS_BUILD_ROOT=`pwd`

if [ ! -d oneAPI-samples ]; then
    echo "clone the oneAPI-samples repo; using the release/2024.0 branch to match the 2024.0 compiler"
    git clone https://github.com/oneapi-src/oneAPI-samples
    cd oneAPI-samples
    git checkout release/2024.0
    cd ..
else
    echo "oneAPI-samples folder already exists. Skipping the clone+checkout."
fi

if [ "${PLATFORM_TARGET}" == "ofs_n6001" ]; then
    if [ ! -d examples-afu ]; then
        echo "clone the examples-afu repo, using the master branch"
        git clone https://github.com/OFS/examples-afu
        #cd examples-afu
        #git checkout branch/tag
        #cd ..
    else
        echo "examples-afu folder already exists. Skipping the clone+checkout."
    fi
fi

#THIS_SEED tracks the current seed number through the while loop
THIS_SEED=$STARTING_SEED
#MAX_SEED_CNT is the upper limit of THIS_SEED
((MAX_SEED_CNT=STARTING_SEED+NUM_SEEDS))

while [ "$THIS_SEED" -lt "$MAX_SEED_CNT" ]
do
    for design in "${all_designs[@]}"
    do
        printf "**\n**\n**\nBuilding $design with seed $THIS_SEED\n"
        if [ "${design}" == "gzip" ]; then
            design_path="./oneAPI-samples/DirectProgramming/C++SYCL_FPGA/ReferenceDesigns/gzip"
        elif [ "${design}" == "board_test" ]; then
            design_path="./oneAPI-samples/DirectProgramming/C++SYCL_FPGA/ReferenceDesigns/board_test"
        else
            design_path=`find . -type d -name ${design}`
        fi
        if [ -z ${design_path} ]; then
            echo "Can't find design $design. Moving on to the next one."
            continue
        fi
        echo "design-path is $design_path"
        cd ${design_path}
        #if we need a special ARC resource or something
        MISC_ARC_STUFF=""
        if echo "${non_usm_designs[@]}" | grep -qw "$design"; then
            ASP_VARIANT="${PLATFORM_TARGET}"
        elif echo "${usm_designs[@]}" | grep -qw "$design"; then
            ASP_VARIANT="${PLATFORM_TARGET}_usm"
        else
            ASP_VARIANT="${PLATFORM_TARGET}_iopipes"
        fi
        
        #set up build folder
        echo "ASP_VARIANT is ${ASP_VARIANT}"
        THIS_BUILD_DIR=${ASP_VARIANT}_s${THIS_SEED}
        echo "THIS_BUILD_DIR is ${THIS_BUILD_DIR}"
        mkdir -p ${THIS_BUILD_DIR}
        cd ${THIS_BUILD_DIR}
        
        #the CMakeLists.txt files are not completely consistent across different designs. 
        #it's ugly, but we beed to mix-and-match some options here.
        if [ "${PLATFORM_TARGET}" == "ofs_n6001" ]; then
            THIS_DEVICE="Agilex7"
        else
            THIS_DEVICE="S10"
        fi
        
        if [ "${design}" == "zero_copy_data_transfer" ]; then
            THIS_DDEVICE_FLAG_ARG=""
        elif [ "${design}" == "simple_host_streaming" ]; then
            THIS_DDEVICE_FLAG_ARG=""
        else
            THIS_DDEVICE_FLAG_ARG="-DDEVICE_FLAG=${THIS_DEVICE}"
        fi
        if [ "${design}" == "db" ]; then
            THIS_DSEED_ARG=""
        else
            THIS_DSEED_ARG="-DSEED=${THIS_SEED}"
        fi
        
        #cmake ../ -DFPGA_DEVICE=${OFS_ASP_ROOT}:${ASP_VARIANT} -DDEVICE_FLAG=Agilex7 -DIS_BSP=1 -DIGNORE_DEFAULT_SEED=1 -DUSER_HARDWARE_FLAGS="-Xsseed=$THIS_SEED -Xsno-env-check -Xstiming-failure-mode=ignore -Xstiming-failure-allowed-slack=50"
        cmake ../ -DFPGA_DEVICE=${OFS_ASP_ROOT}:${ASP_VARIANT} ${THIS_DDEVICE_FLAG_ARG} -DIS_BSP=1 ${THIS_DSEED_ARG} -DUSER_HARDWARE_FLAGS="-Xsseed=$THIS_SEED -Xsno-env-check -Xstiming-failure-mode=ignore -Xstiming-failure-allowed-slack=50"
        
        build_cmd="OFS_ASP_ROOT=$OFS_ASP_ROOT  AOCL_BOARD_PACKAGE_ROOT=$AOCL_BOARD_PACKAGE_ROOT make fpga"
        echo "The build command will be: $build_cmd"
        if [ "${USE_ARC}" -eq "1" ]; then
            echo "Sending the build command to ARC."
            arc submit $MISC_ARC_STUFF node/["memory>=128000"] priority=95 -- $build_cmd
        else
            echo "Building locally."
            OFS_ASP_ROOT=$OFS_ASP_ROOT AOCL_BOARD_PACKAGE_ROOT=$AOCL_BOARD_PACKAGE_ROOT make fpga
        fi
        cd ${THIS_BUILD_ROOT}
    done
    ((THIS_SEED=THIS_SEED+1))
done 
