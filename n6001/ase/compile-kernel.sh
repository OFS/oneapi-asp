#!/bin/bash

# Copyright 2020 Intel Corporation.
#
# THIS SOFTWARE MAY CONTAIN PREPRODUCTION CODE AND IS PROVIDED BY THE
# COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED
# WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR
# BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
# WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
# OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
# EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

ASE_DIR_PATH="$(dirname "$(readlink -e "${BASH_SOURCE[0]}")")"
BSP_ROOT="$(readlink -e "$ASE_DIR_PATH/..")"

if [ -n "$OFS_OCL_ENV_DEBUG_SCRIPTS" ]; then
  set -x
fi

if [ -z "$OFS_OCL_ENV_ENABLE_ASE" ]; then
  echo "Error: must setup ASE environment before compiling kernel"
  exit 1
fi 

function usage() {
  echo "Usage: $0 [-b board-type] <cl_file/path-to-OneAPI-Makefile>"
  exit 1
}

while getopts ":b:h" arg; do
  case $arg in
    b) BOARD="$OPTARG"
    ;;
    *) usage
  esac
done

shift $((OPTIND - 1))

if (($# == 0)); then
  usage
fi

DESIGN_SRC="$1"

# Check that board variant is valid
BOARD=${BOARD:-ofs_n6001}
if [ ! -f "$BSP_ROOT/hardware/$BOARD/build/ofs_top.qdb" ]; then
  echo "Error: cannot find required OFS FIM QDB file for board '$BOARD'"
  echo "Error: $BSP_ROOT/hardware/$BOARD/build/ofs_top.qdb does not exist. You must build the BSP first."
  exit 1
fi
echo "Running ASE for board variant: $BOARD"

if [ -f "$DESIGN_SRC" ]; then
    echo "Running ASE with design: $DESIGN_SRC"
    echo "aoc command is next"
    aoc -v -board-package="$BSP_ROOT" -board="$BOARD" "$DESIGN_SRC"
elif [ -d "$DESIGN_SRC" ]; then
    echo "Running ASE with oneAPI design: $DESIGN_SRC"
    echo "pwd is  $PWD"
    mkdir -p n6001
    echo "pwd is $PWD"
    cd n6001
    echo "pwd is $PWD, cmake is next"
    export USM_TAIL=""
    if [ ${BOARD} == "ofs_n6001_usm" ]; then
        export USM_TAIL="_usm"
    fi
    export BOARD_TYPE=de10_agilex${USM_TAIL}
    cmake "$DESIGN_SRC" -DFPGA_BOARD=${BOARD_TYPE}
    echo "after cmake"
    sed -i "s/$BOARD_TYPE/$BOARD/g" src/CMakeFiles/*/link.txt
    make fpga
    echo "make fpga is done; break out the aocx file"
    FPGAFILE=`ls *.fpga`
    AOCXFILE=`echo $FPGAFILE | sed 's/fpga/aocx/g'`
    echo "FPGAFILE is $FPGAFILE"
    echo "AOCXFILE is $AOCXFILE"
    ${INTELFPGAOCLSDKROOT}/host/linux64/bin/aocl-extract-aocx -i $FPGAFILE -o $AOCXFILE
else
    echo "Error: cannot find: '$DESIGN_SRC'"
    exit 1
fi

echo "Done with compile-kernel.sh."
