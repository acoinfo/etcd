#!/usr/bin/env bash

# This scripts build the etcd binaries
# To build the tools, run `build_tools.sh`

set -euo pipefail

source ./scripts/test_lib.sh

if [ "$GOOS" == "sylixos" ]; then
    source ./scripts/build_lib.sylixos.sh
else
    source ./scripts/build_lib.sh
fi

# only build when called directly, not sourced
if echo "$0" | grep -E "build(.sh)?$" >/dev/null; then
  run_build etcd_build
fi
