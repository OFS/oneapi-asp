#!/bin/bash

###############################################################################
# This script is used to acquire resources needed for building BSP in ARC.
# Or to check that the required programs are available on the user's path.
###############################################################################

if [ -n "$OFS_ASP_ENV_DEBUG_SCRIPTS" ]; then
  echo "Running ${BASH_SOURCE[0]} with debug logging"
  set -x
fi

# Set Intel proxy
export http_proxy=${http_proxy:-http://proxy-chain.intel.com:911}
export HTTP_PROXY=${HTTP_PROXY:-http://proxy-chain.intel.com:911}
export https_proxy=${https_proxy:-http://proxy-chain.intel.com:912}
export HTTPS_PROXY=${HTTPS_PROXY:-http://proxy-chain.intel.com:912}

# Definition of required resources
ACL_RESOURCE="aclsycltest/2024.0"
SYCL_RESOURCES="sycl/rel/20231017,cygwin/2.9.0,itf,regutils,testutils"
ACDS_RESOURCE="acds/23.3"

SW_BUILD_RESOURCES="gcc/7.4.0,python/3.8.10,cmake/3.15.4,git,git_lfs,perl/5.8.8"
MISC_RESOURCES="qedition/pro,p4,klocwork_kwclient,bundle/regtest/21.3,coverity/2022.03"
if [  -n "$OFS_ASP_ENV_ENABLE_ASE" ]; then
  SIM_ARC_RESOURCES="vcs,vcs-vcsmx-lic/vrtn-dev"
  echo "INFO: ASE enabled"
  # Final list of resources that are requested
  ARC_RESOURCES="$ACL_RESOURCE,$ACDS_RESOURCE,$SW_BUILD_RESOURCES,$MISC_RESOURCES,$SIM_ARC_RESOURCES,$SYCL_RESOURCES"
else
  unset SIM_ARC_RESOURCES
  OPAE_RESOURCE="intel_opae/2.5.0-2/1"
  echo "INFO: ASE not enabled (set OFS_ASP_ENV_ENABLE_ASE to enable)"
  # Final list of resources that are requested
  ARC_RESOURCES="$ACL_RESOURCE,$ACDS_RESOURCE,$SW_BUILD_RESOURCES,$MISC_RESOURCES,$SYCL_RESOURCES,$OPAE_RESOURCE"
fi

if [ -z "$OPAE_PLATFORM_ROOT" ]; then
    echo "Prior to running build-bsp.sh you'll need to set OPAE_PLATFORM_ROOT to the FIM release tree."
fi

# Final list of resources that are requested
echo "arc-resources is $ARC_RESOURCES"

# Print usage information
if [ -z "$1" ]; then
  echo "Usage: $0 <command to run> [command args]"
  exit 1
fi

# Check if this is an ARC system
if ! command -v arc > /dev/null; then
  echo "Error: arc command not found"
  exit 1
fi

CMD=$1
shift
arc shell "$ARC_RESOURCES" -- "$CMD" "$@"
