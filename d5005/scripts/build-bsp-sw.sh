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

###############################################################################
# Script to build MMD needed for the BSP. The script first looks for the
# LIBOPAE_C_ROOT environment variable. If that is not found then it builds
# OPAE from source.
#
# The reason for this is that we are not currently installing
# OPAE on systems that also have Quartus installed. So default behavior of
# buildling required resources from source is most common. In the future
# we may want to detect the version of OPAE that is installed and only
# build from source if compatible OPAE not found. For now using an installed
# OPAE requires setting the LIBOPAE_C_ROOT environment variable to the
# install location, even if that is standard system location.
###############################################################################

if [ -n "$OFS_OCL_ENV_DEBUG_SCRIPTS" ]; then
  set -x
fi

SCRIPT_DIR_PATH="$(dirname "$(readlink -e "${BASH_SOURCE[0]}")")"
BSP_ROOT="$(readlink -e "$SCRIPT_DIR_PATH/..")"

if [ -z "$LIBOPAE_C_ROOT" ]; then
    "$SCRIPT_DIR_PATH/build-opae.sh"
    export LIBOPAE_C_ROOT="$BSP_ROOT/build/opae/install"
    export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$BSP_ROOT/build/json-c/install/lib64
fi

export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$BSP_ROOT/build/json-c/install/lib64
"$SCRIPT_DIR_PATH/build-mmd.sh" || exit
