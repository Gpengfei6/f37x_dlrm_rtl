#!/usr/bin/env bash
#
# Stage 2N-A1 v2: standalone DLRM feature-interaction XSim regression.
#
# This script deliberately uses new v2 file, top, work, log, and status names.
# It does not package an XO, link an xclbin, program/reset an FPGA, or access
# any render node.
#

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

VIVADO_SETTINGS="${VIVADO_SETTINGS:-/opt/Xilinx/Vivado/2020.2/settings64.sh}"
WORK_DIR="${REPO_ROOT}/work/stage2n_interaction_xsim_v2"
LOG_DIR="${REPO_ROOT}/logs"
RESULT_DIR="${REPO_ROOT}/results/stage2n"
STATUS_FILE="${RESULT_DIR}/stage2n_interaction_xsim_v2_status.txt"

SOURCE_RTL="${REPO_ROOT}/rtl/interaction/dlrm_feature_interaction_engine.sv"
SOURCE_TB="${REPO_ROOT}/tb/tb_dlrm_feature_interaction_engine_v2.sv"
TOP_MODULE="tb_dlrm_feature_interaction_engine_v2"
SNAPSHOT="tb_dlrm_feature_interaction_engine_v2_sim"

XVLOG_LOG="${LOG_DIR}/xvlog_stage2n_interaction_v2.log"
XELAB_LOG="${LOG_DIR}/xelab_stage2n_interaction_v2.log"
XSIM_LOG="${LOG_DIR}/xsim_stage2n_interaction_v2.log"

fail()
{
    echo "ERROR: $*" >&2
    exit 10
}

git_value()
{
    local command_name="$1"
    (
        cd "${REPO_ROOT}"
        case "${command_name}" in
            branch)
                git symbolic-ref --short HEAD 2>/dev/null || echo UNKNOWN
                ;;
            head)
                git rev-parse HEAD 2>/dev/null || echo UNKNOWN
                ;;
            *)
                echo UNKNOWN
                ;;
        esac
    )
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
    fail "v2 interaction testbench not found: ${SOURCE_TB}"

GIT_BRANCH="$(git_value branch)"
GIT_HEAD="$(git_value head)"

rm -rf "${WORK_DIR}"
mkdir -p "${WORK_DIR}" "${LOG_DIR}" "${RESULT_DIR}"
rm -f "${STATUS_FILE}" "${XVLOG_LOG}" "${XELAB_LOG}" "${XSIM_LOG}"

cd "${WORK_DIR}"

echo "============================================================"
echo "Stage 2N-A1 v2 DLRM Feature Interaction XSim"
echo "TIME=$(date -Is)"
echo "REPO=${REPO_ROOT}"
echo "BRANCH=${GIT_BRANCH}"
echo "HEAD=${GIT_HEAD}"
echo "RTL=${SOURCE_RTL}"
echo "TB_V2=${SOURCE_TB}"
echo "TOP=${TOP_MODULE}"
echo "WORK=${WORK_DIR}"
echo "NO XO/XCLBIN BUILD"
echo "NO FPGA PROGRAMMING OR RESET"
echo "============================================================"

xvlog \
    --sv \
    "${SOURCE_RTL}" \
    "${SOURCE_TB}" \
    2>&1 | tee "${XVLOG_LOG}"

xelab \
    "${TOP_MODULE}" \
    -s "${SNAPSHOT}" \
    --timescale 1ns/1ps \
    2>&1 | tee "${XELAB_LOG}"

xsim \
    "${SNAPSHOT}" \
    -runall \
    2>&1 | tee "${XSIM_LOG}"

PASS_MARKER="tb_dlrm_feature_interaction_engine_v2: PASS cases=3 outputs=54 errors=3"

grep -qF "${PASS_MARKER}" "${XSIM_LOG}" ||
    fail "Stage 2N interaction v2 PASS marker is missing"

if grep -E '^(ERROR:|FATAL:)' \
    "${XVLOG_LOG}" \
    "${XELAB_LOG}" \
    "${XSIM_LOG}"
then
    fail "Stage 2N interaction v2 logs contain anchored errors"
fi

{
    echo "STAGE2N_INTERACTION_XSIM_V2_PASS"
    echo "TIME=$(date -Is)"
    echo "BRANCH=${GIT_BRANCH}"
    echo "HEAD=${GIT_HEAD}"
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
    echo "TB_V2_SHA256=$(sha256sum "${SOURCE_TB}" | awk '{print $1}')"
    echo "LOG=${XSIM_LOG}"
} > "${STATUS_FILE}"

echo
echo "============================================================"
echo "STAGE2N_INTERACTION_XSIM_V2_PASS"
echo "STATUS=${STATUS_FILE}"
echo "LOG=${XSIM_LOG}"
echo "============================================================"
