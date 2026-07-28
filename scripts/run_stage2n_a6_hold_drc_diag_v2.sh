#!/usr/bin/env bash
#
# Stage 2N-A6 hold-path and DRC diagnostic runner v2.
#
# Reuses the existing post-route checkpoint. It does not rerun synthesis,
# placement, physical optimization, or routing. It performs no XO/xclbin
# build and no FPGA access/reset.
#

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

VIVADO_SETTINGS="${VIVADO_SETTINGS:-/opt/Xilinx/Vivado/2020.2/settings64.sh}"
VIVADO_BIN="${VIVADO_BIN:-vivado}"

EXPECTED_BRANCH="work/stage2n-a6-ooc-timing"
EXPECTED_HEAD="915a49b698c35f5b1dfbfd5eaf02db17ab35c8ce"

STAGE2N_A6_EXISTING_DCP="${STAGE2N_A6_EXISTING_DCP:-${REPO_ROOT}/results/stage2n_a6_ooc_v2/post_route.dcp}"
STAGE2N_A6_DIAG_RESULT_DIR="${STAGE2N_A6_DIAG_RESULT_DIR:-${REPO_ROOT}/results/stage2n_a6_hold_drc_diag_v2}"

TCL_SCRIPT="${REPO_ROOT}/scripts/inspect_stage2n_a6_hold_drc_v2.tcl"
LOG_DIR="${REPO_ROOT}/logs"
CONSOLE_LOG="${LOG_DIR}/vivado_stage2n_a6_hold_drc_diag_v2.log"
STATUS_FILE="${STAGE2N_A6_DIAG_RESULT_DIR}/stage2n_a6_hold_drc_diag_v2_status.txt"

fail()
{
    echo "ERROR: $*" >&2
    exit 10
}

[[ -f "${VIVADO_SETTINGS}" ]] ||
    fail "Vivado settings script not found: ${VIVADO_SETTINGS}"

[[ -f "${TCL_SCRIPT}" ]] ||
    fail "diagnostic Tcl not found: ${TCL_SCRIPT}"

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
export STAGE2N_A6_DIAG_RESULT_DIR

echo "============================================================"
echo "Stage 2N-A6 hold-path and DRC diagnostic v2"
echo "TIME=$(date -Is)"
echo "REPO=${REPO_ROOT}"
echo "BRANCH=${CURRENT_BRANCH}"
echo "HEAD=${CURRENT_HEAD}"
echo "DCP=${STAGE2N_A6_EXISTING_DCP}"
echo "RESULTS=${STAGE2N_A6_DIAG_RESULT_DIR}"
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
    fail "Vivado diagnostic returned ${VIVADO_EXIT}; see ${CONSOLE_LOG}"

[[ -f "${STATUS_FILE}" ]] ||
    fail "diagnostic status file is missing: ${STATUS_FILE}"

grep -qx 'STAGE2N_A6_HOLD_DRC_DIAG_V2_COMPLETE' "${STATUS_FILE}" ||
    fail "diagnostic completion marker is missing"

echo
echo "========== Stage 2N-A6 hold/DRC status =========="
cat "${STATUS_FILE}"

echo
echo "========== Hold path class summary =========="
cat "${STAGE2N_A6_DIAG_RESULT_DIR}/hold_class_summary.txt"

echo
echo "========== DRC summary =========="
cat "${STAGE2N_A6_DIAG_RESULT_DIR}/drc_summary.txt"

echo
echo "============================================================"
echo "STAGE2N_A6_HOLD_DRC_DIAG_V2_COMPLETE"
echo "STATUS=${STATUS_FILE}"
echo "HOLD_TSV=${STAGE2N_A6_DIAG_RESULT_DIR}/hold_negative_paths.tsv"
echo "DRC_TSV=${STAGE2N_A6_DIAG_RESULT_DIR}/drc_violations.tsv"
echo "LOG=${CONSOLE_LOG}"
echo "NO SYNTHESIS/PLACE/ROUTE RERUN"
echo "NO XO/XCLBIN BUILD"
echo "NO FPGA PROGRAMMING OR RESET"
echo "============================================================"
