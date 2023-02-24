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

echo "Start of run-ase.sh"

ASE_DIR_PATH="$(dirname "$(readlink -e "${BASH_SOURCE[0]}")")"

if [ -n "$OFS_OCL_ENV_DEBUG_SCRIPTS" ]; then
  set -x
fi

if [ "$#" -lt 2 ]; then
  echo "Usage: $0 <cl file> <board name>"
  exit 1
fi

cl_file="$1"
echo "cl_file is $cl_file"
#cl_file="$(readlink -f "$1")"
board_name="$2"

if [ ! -d "$cl_file" ]; then
  echo "Error: cannot find directory: $cl_file"
  exit 1
fi

# shellcheck source=setup.sh
source "$ASE_DIR_PATH/setup.sh" || exit

SIM_DIR="$(mktemp -d --tmpdir="$PWD" "ase_sim-${board_name}-XXXXXX")"

cd "$SIM_DIR" || exit

mkdir -p kernel
pushd kernel || exit
"$ASE_DIR_PATH/compile-kernel.sh" -b "$board_name" "$cl_file" || exit
aocx_file="$(readlink -f "$(ls -1 ./n6001/*.aocx)")"
popd || exit

mkdir -p sim
pushd sim || exit
"$ASE_DIR_PATH/simulate-aocx.sh" "$aocx_file" "$board_name" || exit
echo "Starting simulation in: $PWD"
make sim

echo "------------------------------------------------------------------------"
echo "Simulation complete"
echo "Simulation directory: $SIM_DIR/sim"
echo "Run 'make sim' from the simulation directory to restart simulation if desired"
echo "------------------------------------------------------------------------"
