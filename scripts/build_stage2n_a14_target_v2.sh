#!/usr/bin/env bash
# Stage 2N-A14 target-build compatibility entry for the older server Git.
#
# The target flow remains build-only. This launcher records that the corrected
# runner was used, then delegates to the reviewed V1 implementation. It never
# opens an XRT device, programs or resets an FPGA, runs a Host application, or
# performs a physical HBM transaction.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
V1_RUNNER="${SCRIPT_DIR}/build_stage2n_a14_target_v1.sh"

[[ -f "${V1_RUNNER}" ]] || {
    echo "ERROR: missing corrected V1 runner: ${V1_RUNNER}" >&2
    exit 2
}

export A14_TARGET_BUILD_FLOW="STAGE2N_A14_TARGET_V2_GIT_COMPAT"
export A14_TARGET_RUNNER_VERSION="V2_GIT_PORCELAIN_COMPAT"

exec bash "${V1_RUNNER}"
