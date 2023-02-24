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

if [ -n "$OFS_OCL_ENV_DEBUG_SCRIPTS" ]; then
  echo "Running ${BASH_SOURCE[0]} with debug logging"
  set -x
fi

SCRIPT_DIR_PATH="$(dirname "$(readlink -e "${BASH_SOURCE[0]}")")"
BSP_ROOT="$(readlink -e "$SCRIPT_DIR_PATH/..")"

# If hardlink is installed use it to deduplicate files in the hardware
# directory that are identical by hardlinking between the files
if command -v /usr/sbin/hardlink; then
  echo "Running hardlink to deduplicate files in hardware directory"
  /usr/sbin/hardlink "$BSP_ROOT/hardware"

# If hardlink not installed then check files that are known to consume large
# amount of disk space and see if they are the same in the ofs_d5005
# and ofs_d5005_usm directories. If so replace the ofs_d5005_usm copy with
# a hard link to version of the file in ofs_d5005 directory
else
  echo "Deduplicating large files in hardware ofs_d5005 and ofs_d5005_usm direcotry"
  dups=("build/output_files/ofs_fim.green_region.pmsf"
        "build/output_files/ofs_fim.static.msf"
        "build/output_files/ofs_fim.sof"
        "build/ofs_fim.qdb")

  for f in "${dups[@]}"; do
    if [[ -e "$BSP_ROOT/hardware/ofs_d5005/$f" && 
          -e "$BSP_ROOT/hardware/ofs_d5005_usm/$f" ]];
    then
      ln -f "$BSP_ROOT/hardware/ofs_d5005/$f" "$BSP_ROOT/hardware/ofs_d5005_usm/$f"
    fi
  done
fi
