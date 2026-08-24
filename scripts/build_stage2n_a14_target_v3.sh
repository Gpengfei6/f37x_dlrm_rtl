#!/usr/bin/env bash
# Stage 2N-A14 target runner V3: explicit AXI master metadata for Vivado 2020.2.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
V1_RUNNER="${SCRIPT_DIR}/build_stage2n_a14_target_v1.sh"
PACKAGE_TCL_V2="${SCRIPT_DIR}/package_stage2n_a14_rtl_kernel_v2.tcl"

[[ -f "${V1_RUNNER}" ]] || {
    echo "ERROR: missing common target runner: ${V1_RUNNER}" >&2
    exit 2
}
[[ -f "${PACKAGE_TCL_V2}" ]] || {
    echo "ERROR: missing explicit-metadata packaging Tcl: ${PACKAGE_TCL_V2}" >&2
    exit 2
}

export A14_TARGET_BUILD_FLOW="STAGE2N_A14_TARGET_V3_XO_METADATA_FIX"
export A14_TARGET_RUNNER_VERSION="V3_EXPLICIT_AXI_METADATA"
export A14_PACKAGE_TCL="${PACKAGE_TCL_V2}"

exec bash "${V1_RUNNER}"
