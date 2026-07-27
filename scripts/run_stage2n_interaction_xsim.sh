#!/usr/bin/env bash
#
# Stage 2N-A1: standalone DLRM feature-interaction XSim regression.
#
# This script performs simulation only. It does not package an XO, link an
# xclbin, program/reset an FPGA, or access any render node.
#

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

VIVADO_SETTINGS="${VIVADO_SETTINGS:-/opt/Xilinx/Vivado/2020.2/settings64.sh}"
WORK_DIR="${REPO_ROOT}/work/stage2n_interaction_xsim"
LOG_DIR="${REPO_ROOT}/logs"
RESULT_DIR="${REPO_ROOT}/results/stage2n"
STATUS_FILE="${RESULT_DIR}/stage2n_interaction_xsim_status.txt"

SOURCE_RTL="${REPO_ROOT}/rtl/interaction/dlrm_feature_interaction_engine.sv"
SOURCE_TB="${REPO_ROOT}/tb/tb_dlrm_feature_interaction_engine.sv"

fail()
{
    echo "ERROR: $*" >&2
    exit 10
}

[[ -f "${VIVADO_SETTINGS}" ]] ||
    fail "Vivado settings not found: ${VIVADO_SETTINGS}"

# shellcheck disable=SC1090
source "${VIVADO_SETTINGS}" >/dev/null

for tool in xvlog xelab xsim; do
    command -v "${tool}" >/dev/null 2>&1 ||
        fail "${tool} is not available"
done

[[ -f "${SOURCE_RTL}" ]] ||
    fail "interaction RTL not found: ${SOURCE_RTL}"
[[ -f "${SOURCE_TB}" ]] ||
    fail "interaction testbench not found: ${SOURCE_TB}"

rm -rf "${WORK_DIR}"
mkdir -p "${WORK_DIR}" "${LOG_DIR}" "${RESULT_DIR}"
rm -f "${STATUS_FILE}"

cd "${WORK_DIR}"

echo "============================================================"
echo "Stage 2N-A1 DLRM Feature Interaction XSim"
echo "TIME=$(date -Is)"
echo "REPO=${REPO_ROOT}"
echo "BRANCH=$(git -C "${REPO_ROOT}" symbolic-ref --short HEAD 2>/dev/null || echo UNKNOWN)"
echo "HEAD=$(git -C "${REPO_ROOT}" rev-parse HEAD 2>/dev/null || echo UNKNOWN)"
echo "RTL=${SOURCE_RTL}"
echo "TB=${SOURCE_TB}"
echo "NO XO/XCLBIN BUILD"
echo "NO FPGA PROGRAMMING OR RESET"
echo "============================================================"

xvlog \
    --sv \
    "${SOURCE_RTL}" \
    "${SOURCE_TB}" \
    2>&1 | tee "${LOG_DIR}/xvlog_stage2n_interaction.log"

xelab \
    tb_dlrm_feature_interaction_engine \
    -s tb_dlrm_feature_interaction_engine_sim \
    --timescale 1ns/1ps \
    2>&1 | tee "${LOG_DIR}/xelab_stage2n_interaction.log"

xsim \
    tb_dlrm_feature_interaction_engine_sim \
    -runall \
    2>&1 | tee "${LOG_DIR}/xsim_stage2n_interaction.log"

grep -q \
    "tb_dlrm_feature_interaction_engine: PASS cases=3 outputs=54 errors=3" \
    "${LOG_DIR}/xsim_stage2n_interaction.log" ||
    fail "Stage 2N interaction PASS marker is missing"

if grep -E '^(ERROR:|FATAL:)' \
    "${LOG_DIR}/xvlog_stage2n_interaction.log" \
    "${LOG_DIR}/xelab_stage2n_interaction.log" \
    "${LOG_DIR}/xsim_stage2n_interaction.log"
then
    fail "Stage 2N interaction logs contain anchored errors"
fi

{
    echo "STAGE2N_INTERACTION_XSIM_PASS"
    echo "TIME=$(date -Is)"
    echo "BRANCH=$(git -C "${REPO_ROOT}" symbolic-ref --short HEAD 2>/dev/null || echo UNKNOWN)"
    echo "HEAD=$(git -C "${REPO_ROOT}" rev-parse HEAD 2>/dev/null || echo UNKNOWN)"
    echo "VECTOR_COUNT=5"
    echo "VECTOR_DIM=8"
    echo "OUTPUT_DIM=18"
    echo "INPUT_FORMAT=SIGNED_INT16"
    echo "ACCUMULATOR_FORMAT=SIGNED_INT48"
    echo "ROUNDING=NEAREST_TIES_AWAY_FROM_ZERO"
    echo "SATURATION=SIGNED_INT16"
    echo "PAIR_ORDER=(1,0),(2,0),(2,1),(3,0),(3,1),(3,2),(4,0),(4,1),(4,2),(4,3)"
    echo "DIRECTED_CASES=3"
    echo "CHECKED_OUTPUTS=54"
    echo "CHECKED_ERRORS=3"
    echo "RTL_SHA256=$(sha256sum "${SOURCE_RTL}" | awk '{print $1}')"
    echo "TB_SHA256=$(sha256sum "${SOURCE_TB}" | awk '{print $1}')"
    echo "LOG=${LOG_DIR}/xsim_stage2n_interaction.log"
} > "${STATUS_FILE}"

echo
echo "============================================================"
echo "STAGE2N_INTERACTION_XSIM_PASS"
echo "STATUS=${STATUS_FILE}"
echo "LOG=${LOG_DIR}/xsim_stage2n_interaction.log"
echo "============================================================"
