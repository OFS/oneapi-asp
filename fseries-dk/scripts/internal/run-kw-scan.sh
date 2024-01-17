#!/bin/bash

if [ -n "$OFS_OCL_ENV_DEBUG_SCRIPTS" ]; then
  echo "Running ${BASH_SOURCE[0]} with debug logging"
  set -x
fi

INTERNAL_SCRIPT_DIR_PATH="$(dirname "$(readlink -e "${BASH_SOURCE[0]}")")"
SCRIPT_DIR_PATH="$(dirname "$INTERNAL_SCRIPT_DIR_PATH")"
BSP_ROOT="$(readlink -e "$SCRIPT_DIR_PATH/..")"

# Check for klocwork commands
commands="kwauth kwcheck kwinject"
for cmd in $commands; do
  if ! command -v "$cmd" > /dev/null; then
    echo "Error missing Klocwork command '$cmd'"
    exit 1
  fi
done

# Authenticate if necessary
if [ ! -f "$HOME/.klocwork/ltoken" ]; then
  kwauth --url https://klocwork-jf3.devtools.intel.com:8085
fi

# Create Klocwork project if necessary
cd "$BSP_ROOT" || exit 1
if [ ! -d "$BSP_ROOT/.kwps" ]; then
  kwcheck create --url https://klocwork-jf3.devtools.intel.com:8085/opencl-bsp
fi

# shellcheck source=../build-bsp-sw.sh
source "$SCRIPT_DIR_PATH/build-bsp-sw.sh"
cd "$BSP_ROOT/build/release" || exit
make clean

# HUB workstations use /tmp/localdisk for user directory so builds need to
# include that location in scan
kwinject --white-dir /tmp/localdisk --output "$BSP_ROOT/.kwlp/buildspec.txt" make

cd "$BSP_ROOT" || exit
kwcheck run
kwcheck list
