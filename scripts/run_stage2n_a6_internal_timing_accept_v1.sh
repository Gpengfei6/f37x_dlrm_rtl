#!/usr/bin/env bash
#
# Stage 2N-A6 internal timing acceptance runner v1.
#
# Reuses the existing post-route DCP and accepts only the timing intrinsic to
# the RTL block: register-to-register setup and hold paths.
#
# No synthesis/place/route rerun, no XO/xclbin build, and no FPGA access/reset.
#

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

VIVADO_SETTINGS="${VIVADO_SETTINGS:-/opt/Xilinx/Vivado/2020.2/settings64.sh}"
VIVADO_BIN="${VIVADO_BIN:-vivado}"

EXPECTED_BRANCH="work/stage2n-a6-ooc-timing"
EXPECTED_HEAD="915a49b698c35f5b1dfbfd5eaf02db17ab35c8ce"

STAGE2N_A6_EXISTING_DCP="${STAGE2N_A6_EXISTING_DCP:-${REPO_ROOT}/results/stage2n_a6_ooc_v2/post_route.dcp}"
STAGE2N_A6_ACCEPT_RESULT_DIR="${STAGE2N_A6_ACCEPT_RESULT_DIR:-${REPO_ROOT}/results/stage2n_a6_internal_accept_v1}"

TCL_SCRIPT="${REPO_ROOT}/scripts/inspect_stage2n_a6_internal_timing_v1.tcl"
LOG_DIR="${REPO_ROOT}/logs"
CONSOLE_LOG="${LOG_DIR}/vivado_stage2n_a6_internal_timing_accept_v1.log"
STATUS_FILE="${STAGE2N_A6_ACCEPT_RESULT_DIR}/stage2n_a6_internal_timing_accept_v1_status.txt"

fail()
{
    echo "ERROR: $*" >&2
    exit 10
}

require_status_line()
{
    local expected_line="$1"

    grep -qxF "${expected_line}" "${STATUS_FILE}" ||
        fail "required status line missing: ${expected_line}"
}

require_nonnegative_status_value()
{
    local key="$1"
    local value

    value="$(
        awk -F= -v key="${key}" '
            $1 == key {
                print substr($0, index($0, "=") + 1)
                exit
            }
        ' "${STATUS_FILE}"
    )"

    [[ -n "${value}" && "${value}" != "NA" ]] ||
        fail "status is missing numeric ${key}"

    awk -v value="${value}" 'BEGIN { exit !(value + 0.0 >= 0.0) }' ||
        fail "${key} is negative: ${value}"
}

[[ -f "${VIVADO_SETTINGS}" ]] ||
    fail "Vivado settings script not found: ${VIVADO_SETTINGS}"

[[ -f "${TCL_SCRIPT}" ]] ||
    fail "internal timing Tcl not found: ${TCL_SCRIPT}"

[[ -f "${STAGE2N_A6_EXISTING_DCP}" ]] ||
    fail "existing post-route DCP not found: ${STAGE2N_A6_EXISTING_DCP}"

# shellcheck disable=SC1090
source "${VIVADO_SETTINGS}" >/dev/null

command -v "${VIVADO_BIN}" >/dev/null 2>&1 ||
    fail "Vivado executable not found: ${VIVADO_BIN}"

CURRENT_BRANCH="$(
    cd "${REPO_ROOT}" &&
    git symbolic-ref --short HEAD 2>/dev/null ||
        echo DETACHED
)"

CURRENT_HEAD="$(
    cd "${REPO_ROOT}" &&
    git rev-parse HEAD
)"

[[ "${CURRENT_BRANCH}" == "${EXPECTED_BRANCH}" ]] ||
    fail "wrong branch: ${CURRENT_BRANCH}; expected ${EXPECTED_BRANCH}"

[[ "${CURRENT_HEAD}" == "${EXPECTED_HEAD}" ]] ||
    fail "wrong HEAD: ${CURRENT_HEAD}; expected ${EXPECTED_HEAD}"

mkdir -p "${LOG_DIR}"
rm -f "${CONSOLE_LOG}"

export STAGE2N_A6_EXISTING_DCP
export STAGE2N_A6_ACCEPT_RESULT_DIR

echo "============================================================"
echo "Stage 2N-A6 internal timing acceptance v1"
echo "TIME=$(date -Is)"
echo "REPO=${REPO_ROOT}"
echo "BRANCH=${CURRENT_BRANCH}"
echo "HEAD=${CURRENT_HEAD}"
echo "DCP=${STAGE2N_A6_EXISTING_DCP}"
echo "RESULTS=${STAGE2N_A6_ACCEPT_RESULT_DIR}"
echo "ACCEPTANCE=INTERNAL REGISTER-TO-REGISTER TIMING"
echo "OUTPUT HOLD=PENDING FINAL AXI/XRT/F37X SHELL"
echo "NO SYNTHESIS/PLACE/ROUTE RERUN"
echo "NO XO/XCLBIN BUILD"
echo "NO FPGA PROGRAMMING OR RESET"
echo "============================================================"

cd "${REPO_ROOT}"

set +e
"${VIVADO_BIN}" \
    -mode batch \
    -nolog \
    -nojournal \
    -source "${TCL_SCRIPT}" \
    2>&1 | tee "${CONSOLE_LOG}"
VIVADO_EXIT="${PIPESTATUS[0]}"
set -e

[[ "${VIVADO_EXIT}" -eq 0 ]] ||
    fail "Vivado acceptance returned ${VIVADO_EXIT}; see ${CONSOLE_LOG}"

[[ -f "${STATUS_FILE}" ]] ||
    fail "acceptance status file is missing: ${STATUS_FILE}"

grep -qx 'STAGE2N_A6_INTERNAL_TIMING_ACCEPT_V1_PASS' "${STATUS_FILE}" ||
    fail "internal timing PASS marker is missing"

for required_line in \
    "TOP=dlrm_internal_pipeline_controller" \
    "PART=xcvu37p-fsvh2892-2L-e" \
    "CLOCK_PERIOD_NS=10.000" \
    "INTERNAL_SETUP_FAILING_PATHS=0" \
    "INTERNAL_HOLD_FAILING_PATHS=0" \
    "UNROUTED_NETS=0" \
    "LATCH_COUNT=0" \
    "DRC_ERROR_COUNT=0" \
    "INTERNAL_SETUP_MET=1" \
    "INTERNAL_HOLD_MET=1" \
    "ROUTE_MET=1" \
    "LATCH_MET=1" \
    "DRC_ERROR_FREE=1" \
    "OUTPUT_HOLD_EXCLUDED_PENDING_FINAL_SHELL=1" \
    "NO_SYNTH_PLACE_ROUTE_RERUN=1" \
    "NO_XO_OR_XCLBIN_BUILD=1" \
    "NO_FPGA_PROGRAMMING_OR_RESET=1"
do
    require_status_line "${required_line}"
done

require_nonnegative_status_value "INTERNAL_SETUP_WNS_NS"
require_nonnegative_status_value "INTERNAL_HOLD_WHS_NS"

echo
echo "========== Stage 2N-A6 accepted internal timing =========="
cat "${STATUS_FILE}"

echo
echo "============================================================"
echo "STAGE2N_A6_INTERNAL_TIMING_ACCEPT_V1_PASS"
echo "STATUS=${STATUS_FILE}"
echo "LOG=${CONSOLE_LOG}"
echo "NO SYNTHESIS/PLACE/ROUTE RERUN"
echo "NO XO/XCLBIN BUILD"
echo "NO FPGA PROGRAMMING OR RESET"
echo "============================================================"
