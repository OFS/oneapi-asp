#!/bin/bash

if [ -n "$OFS_OCL_ENV_DEBUG_SCRIPTS" ]; then
  set -x
fi

INTERNAL_SCRIPT_DIR_PATH="$(dirname "$(readlink -e "${BASH_SOURCE[0]}")")"
BSP_ROOT="$(readlink -e "$INTERNAL_SCRIPT_DIR_PATH/../..")"

# XXX: *** Workaround to support Intel internal build environment ***
# Intel lab environment does not have access to public github.  Detect if script
# is running in lab by checking substring of home directory.  If so change the
# URL for intel-fpag-bbb to use internal mirror then restore file to avoid
# committing changes
if [[ "$HOME" =~ "/storage/shared/home_directories" ]]; then
  (cd "$BSP_ROOT/.." && git submodule deinit n6001/source/extra/intel-fpga-bbb)
  sed -i 's,https://github.com/OPAE/intel-fpga-bbb.git,ssh://git@gitlab.devtools.intel.com:29418/OPAE/intel-fpga-bbb-x.git,g' "$BSP_ROOT/../.gitmodules"
  (cd "$BSP_ROOT/.." && git submodule update --init n6001/source/extra/intel-fpga-bbb && git checkout "$BSP_ROOT/../.gitmodules")
else
  echo "Warning did not detect minicloud home directory structure"
  (cd "$BSP_ROOT/.." && git submodule update --init n6001/source/extra/intel-fpga-bbb)
fi

"$INTERNAL_SCRIPT_DIR_PATH/../build-mmd.sh"
