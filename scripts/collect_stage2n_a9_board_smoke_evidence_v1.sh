#!/usr/bin/env bash
#
# Collect and validate the latest successful Stage 2N-A9 board-smoke evidence.
#
# Read-only with respect to the FPGA:
#   - no xbutil scan/query/program/reset;
#   - no render-node access;
#   - no FPGA programming or reset.
#
# The script only validates existing status/log files and copies canonical
# evidence into docs/evidence/stage2n_a9/.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

EXPECTED_BRANCH="work/stage2n-a9-board-smoke"
EXPECTED_TARGET_INDEX="2"
EXPECTED_TARGET_BDF="0000:9b:00.1"
EXPECTED_TARGET_RENDER="/dev/dri/renderD129"
EXPECTED_UUID="5d4ac982-14e3-40fb-afaa-f04ba82dce61"
EXPECTED_KERNEL="dlrm_f37x_rtl_kernel_stage2n_a7"
EXPECTED_CU="dlrm_a7_1"
EXPECTED_IP_NAME="${EXPECTED_KERNEL}:${EXPECTED_CU}"

RESULT_DIR="${REPO_ROOT}/results/stage2n_a9_board_v3"
LOG_DIR="${REPO_ROOT}/server_results/stage2n_a9"
EVIDENCE_DIR="${REPO_ROOT}/docs/evidence/stage2n_a9"

LATEST_STATUS="$(
    find "${RESULT_DIR}" \
        -maxdepth 1 \
        -type f \
        -name 'stage2n_a9_pipeline_board_smoke_v2_status_*.txt' \
        -printf '%T@ %p\n' |
    sort -nr |
    awk 'NR==1 {sub(/^[^ ]+ /, ""); print}'
)"

LATEST_LOG="$(
    find "${LOG_DIR}" \
        -maxdepth 1 \
        -type f \
        -name 'stage2n_a9_pipeline_board_smoke_v3_*.log' \
        -printf '%T@ %p\n' |
    sort -nr |
    awk 'NR==1 {sub(/^[^ ]+ /, ""); print}'
)"

fail()
{
    local reason="$*"
    echo "ERROR: ${reason}" >&2
    exit 10
}

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

[[ -n "${LATEST_STATUS}" && -s "${LATEST_STATUS}" ]] ||
    fail "latest A9 PASS status file was not found"

[[ -n "${LATEST_LOG}" && -s "${LATEST_LOG}" ]] ||
    fail "latest A9 board-smoke log was not found"

require_exact_line()
{
    local file="$1"
    local expected="$2"

    grep -Fxq "${expected}" "${file}" ||
        fail "missing exact line in ${file}: ${expected}"
}

require_key_value()
{
    local file="$1"
    local key="$2"
    local expected="$3"
    local actual

    actual="$(
        sed -n "s/^${key}=//p" "${file}" |
        head -n 1
    )"

    [[ "${actual}" == "${expected}" ]] ||
        fail "${key} is ${actual:-<missing>}, expected ${expected}"
}

require_exact_line \
    "${LATEST_STATUS}" \
    "STAGE2N_A9_PIPELINE_BOARD_SMOKE_V1_PASS"

require_key_value \
    "${LATEST_STATUS}" \
    "TARGET_INDEX" \
    "${EXPECTED_TARGET_INDEX}"

require_key_value \
    "${LATEST_STATUS}" \
    "TARGET_BDF" \
    "${EXPECTED_TARGET_BDF}"

require_key_value \
    "${LATEST_STATUS}" \
    "TARGET_RENDER" \
    "${EXPECTED_TARGET_RENDER}"

require_key_value \
    "${LATEST_STATUS}" \
    "XCLBIN_UUID" \
    "${EXPECTED_UUID}"

require_key_value \
    "${LATEST_STATUS}" \
    "KERNEL" \
    "${EXPECTED_KERNEL}"

require_key_value \
    "${LATEST_STATUS}" \
    "COMPUTE_UNIT" \
    "${EXPECTED_CU}"

require_key_value \
    "${LATEST_STATUS}" \
    "IP_NAME" \
    "${EXPECTED_IP_NAME}"

require_key_value \
    "${LATEST_STATUS}" \
    "PIPELINE_RUNS" \
    "2"

require_key_value \
    "${LATEST_STATUS}" \
    "PIPELINE_RESULT" \
    "-60"

require_key_value \
    "${LATEST_STATUS}" \
    "BOTTOM_OUTPUTS" \
    "8"

require_key_value \
    "${LATEST_STATUS}" \
    "INTERACTION_OUTPUTS" \
    "18"

require_key_value \
    "${LATEST_STATUS}" \
    "FINAL_BACKPRESSURE_READS" \
    "12"

require_key_value \
    "${LATEST_STATUS}" \
    "FIREWALL_GOOD_AFTER_TEST" \
    "1"

require_key_value \
    "${LATEST_STATUS}" \
    "CU_IDLE_AFTER_TEST" \
    "1"

require_key_value \
    "${LATEST_STATUS}" \
    "NO_FPGA_RESET" \
    "1"

require_key_value \
    "${LATEST_STATUS}" \
    "NO_AUTOMATIC_ROLLBACK" \
    "1"

require_key_value \
    "${LATEST_STATUS}" \
    "NO_OTHER_DEVICE_ACCESS" \
    "1"

grep -Fq \
    "STAGE2N_A9_PIPELINE_BOARD_SMOKE_V2_PASS runs=2 final=-60 bottom=8 interaction=18" \
    "${LATEST_LOG}" ||
    fail "Host v2 PASS marker is missing from latest log"

grep -Fq \
    "STAGE2N_A9_PIPELINE_BOARD_SMOKE_V3_PASS" \
    "${LATEST_LOG}" ||
    fail "protected runner v3 PASS marker is missing from latest log"

grep -Fq \
    "NO FPGA RESET WAS PERFORMED" \
    "${LATEST_LOG}" ||
    fail "no-reset marker is missing from latest log"

grep -Fq \
    "NO OTHER DEVICE WAS ACCESSED" \
    "${LATEST_LOG}" ||
    fail "no-other-device marker is missing from latest log"

mkdir -p "${EVIDENCE_DIR}"

STATUS_BASENAME="$(basename "${LATEST_STATUS}")"
LOG_BASENAME="$(basename "${LATEST_LOG}")"

cp -f \
    "${LATEST_STATUS}" \
    "${EVIDENCE_DIR}/${STATUS_BASENAME}"

cp -f \
    "${LATEST_LOG}" \
    "${EVIDENCE_DIR}/${LOG_BASENAME}"

STATUS_SHA256="$(
    sha256sum "${LATEST_STATUS}" |
    awk '{print $1}'
)"
LOG_SHA256="$(
    sha256sum "${LATEST_LOG}" |
    awk '{print $1}'
)"

SUMMARY_FILE="${EVIDENCE_DIR}/stage2n_a9_board_smoke_accept_v1.txt"

cat > "${SUMMARY_FILE}" <<EOF
STAGE2N_A9_BOARD_SMOKE_ACCEPT_V1_PASS
GIT_BRANCH=${CURRENT_BRANCH}
GIT_HEAD=${CURRENT_HEAD}
TARGET_INDEX=${EXPECTED_TARGET_INDEX}
TARGET_BDF=${EXPECTED_TARGET_BDF}
TARGET_RENDER=${EXPECTED_TARGET_RENDER}
XCLBIN_UUID=${EXPECTED_UUID}
KERNEL=${EXPECTED_KERNEL}
COMPUTE_UNIT=${EXPECTED_CU}
IP_NAME=${EXPECTED_IP_NAME}
PIPELINE_RUNS=2
PIPELINE_RESULT=-60
BOTTOM_OUTPUTS=8
INTERACTION_OUTPUTS=18
FINAL_BACKPRESSURE_READS=12
FIREWALL_GOOD_AFTER_TEST=1
CU_IDLE_AFTER_TEST=1
NO_FPGA_RESET=1
NO_AUTOMATIC_ROLLBACK=1
NO_OTHER_DEVICE_ACCESS=1
SOURCE_STATUS=${LATEST_STATUS}
SOURCE_STATUS_SHA256=${STATUS_SHA256}
SOURCE_LOG=${LATEST_LOG}
SOURCE_LOG_SHA256=${LOG_SHA256}
COPIED_STATUS=${EVIDENCE_DIR}/${STATUS_BASENAME}
COPIED_LOG=${EVIDENCE_DIR}/${LOG_BASENAME}
EOF

echo "============================================================"
echo "STAGE2N_A9_BOARD_SMOKE_ACCEPT_V1_PASS"
echo "TARGET_INDEX=${EXPECTED_TARGET_INDEX}"
echo "TARGET_BDF=${EXPECTED_TARGET_BDF}"
echo "TARGET_RENDER=${EXPECTED_TARGET_RENDER}"
echo "XCLBIN_UUID=${EXPECTED_UUID}"
echo "PIPELINE_RUNS=2"
echo "PIPELINE_RESULT=-60"
echo "BOTTOM_OUTPUTS=8"
echo "INTERACTION_OUTPUTS=18"
echo "FINAL_BACKPRESSURE_READS=12"
echo "FIREWALL_GOOD_AFTER_TEST=1"
echo "CU_IDLE_AFTER_TEST=1"
echo "NO FPGA ACCESS PERFORMED BY THIS COLLECTION SCRIPT"
echo "EVIDENCE_DIR=${EVIDENCE_DIR}"
echo "SUMMARY=${SUMMARY_FILE}"
echo "============================================================"
