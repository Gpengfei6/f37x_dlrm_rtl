#!/usr/bin/env bash
#
# Stage 2N-A11 v1 protected 256-sample automatic-pipeline regression.
#
# Uses the already-programmed Stage 2N-A10 xclbin. This script:
#   - accesses only xbutil index 2 / BDF 0000:9b:00.1 / renderD129;
#   - never programs an xclbin;
#   - never resets the FPGA;
#   - never performs rollback;
#   - requires an exact interactive authorization before any FPGA access.
#

set -o pipefail

REPO_ROOT="${1:-/home/chaosuan/gpf/gpf_f37x_dlrm/f37x_dlrm_rtl_stage2n}"

cd "${REPO_ROOT}" || {
    echo "ERROR: cannot enter repository: ${REPO_ROOT}" >&2
    exit 2
}

if [[ -f /opt/xilinx/xrt/setup.sh ]]; then
    # shellcheck disable=SC1091
    source /opt/xilinx/xrt/setup.sh >/dev/null 2>&1 || {
        echo "ERROR: failed to initialize XRT." >&2
        exit 3
    }
else
    echo "ERROR: /opt/xilinx/xrt/setup.sh not found." >&2
    exit 3
fi

set -euo pipefail

TARGET_INDEX="2"
TARGET_BDF="0000:9b:00.1"
TARGET_RENDER="/dev/dri/renderD129"
EXPECTED_PLATFORM="inspur_f37x_xdma_201920_3"

EXPECTED_BRANCH="work/stage2n-a11-real-model-batch-regression"
REQUIRED_ANCESTOR="a0ba096a1a2054251ca98c28909c1d9527803365"

EXPECTED_UUID="f7a23117-5218-4fba-adb5-f093b596df03"
EXPECTED_KERNEL="dlrm_f37x_rtl_kernel_stage2n_a10_v2"
EXPECTED_INSTANCE="dlrm_a10_1"
EXPECTED_CU="${EXPECTED_KERNEL}:${EXPECTED_INSTANCE}"

SOURCE="host/stage2n_a11_real_model_batch_board_v1.cpp"
ASSET="build/stage2n_a11/assets_v2/stage2n_a11_real_model_batch_v2.f37xpb"
ASSET_STATUS="results/stage2n_a11/assets_v2/stage2n_a11_real_model_batch_v2_status.txt"
ASSET_EVIDENCE="docs/evidence/stage2n_a11_assets_v2"
A10_FINAL_STATUS="docs/evidence/stage2n_a10_final_v4/stage2n_a10_final_acceptance_v4_status.txt"

BUILD_DIR="build/stage2n_a11_board_v1"
RESULT_DIR="results/stage2n_a11_board_v1"
SERVER_RESULT_DIR="server_results/stage2n_a11"

mkdir -p "${BUILD_DIR}" "${RESULT_DIR}" "${SERVER_RESULT_DIR}"

STAMP="$(date +%Y%m%d_%H%M%S)"
BINARY="${BUILD_DIR}/stage2n_a11_real_model_batch_board_v1_${STAMP}"
LOG="${SERVER_RESULT_DIR}/stage2n_a11_real_model_batch_board_v1_${STAMP}.log"
STATUS="${RESULT_DIR}/stage2n_a11_real_model_batch_board_v1_status_${STAMP}.txt"
CSV="${RESULT_DIR}/stage2n_a11_real_model_batch_board_v1_samples_${STAMP}.csv"

exec > >(tee "${LOG}") 2>&1

write_failure()
{
    local reason="$1"
    {
        echo "STAGE2N_A11_REAL_MODEL_BATCH_BOARD_V1_FAILED"
        echo "TIME=$(date -Is)"
        echo "TARGET_INDEX=${TARGET_INDEX}"
        echo "TARGET_BDF=${TARGET_BDF}"
        echo "TARGET_RENDER=${TARGET_RENDER}"
        echo "REASON=${reason}"
        echo "LOG=${LOG}"
        echo "NO_FPGA_PROGRAMMING=1"
        echo "NO_FPGA_RESET=1"
        echo "NO_AUTOMATIC_ROLLBACK=1"
        echo "NO_OTHER_DEVICE_ACCESS=1"
    } > "${STATUS}"
}

fail()
{
    local reason="$*"
    write_failure "${reason}"
    echo "ERROR: ${reason}" >&2
    echo "No FPGA programming, reset, or rollback was attempted." >&2
    exit 10
}

require_file()
{
    local file="$1"
    [[ -s "${file}" ]] ||
        fail "required file missing or empty: ${file}"
}

require_exact()
{
    local file="$1"
    local line="$2"
    grep -Fxq "${line}" "${file}" ||
        fail "missing exact line in ${file}: ${line}"
}

extract_uuid()
{
    awk '
        /Xclbin UUID/ {
            getline
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0)
            print
            exit
        }
    '
}

require_empty_render()
{
    local stage="$1"
    local fuser_output
    local lsof_output

    fuser_output="$(fuser -v "${TARGET_RENDER}" 2>&1 || true)"
    lsof_output="$(lsof "${TARGET_RENDER}" 2>&1 || true)"

    if [[ -n "${fuser_output//[[:space:]]/}" ]]; then
        printf '%s\n' "${fuser_output}"
        fail "${stage}: fuser reports an open handle on ${TARGET_RENDER}"
    fi

    if [[ -n "${lsof_output//[[:space:]]/}" ]]; then
        printf '%s\n' "${lsof_output}"
        fail "${stage}: lsof reports an open handle on ${TARGET_RENDER}"
    fi

    echo "${stage}: no open handle on ${TARGET_RENDER}"
}

check_target_mapping()
{
    local scan_output
    local render_sysfs

    scan_output="$(xbutil scan 2>&1)" ||
        fail "xbutil scan failed"

    echo "${scan_output}"

    echo "${scan_output}" |
        grep -Eq \
            "^[[:space:]]*\[${TARGET_INDEX}\][[:space:]]+${TARGET_BDF}[[:space:]]+${EXPECTED_PLATFORM}" ||
        fail "index ${TARGET_INDEX} is not mapped to ${TARGET_BDF}"

    render_sysfs="$(
        readlink -f \
            "/sys/class/drm/$(basename "${TARGET_RENDER}")/device" \
            2>/dev/null || true
    )"

    [[ "${render_sysfs}" == *"/${TARGET_BDF}" ]] ||
        fail "render node does not map to locked BDF: ${render_sysfs}"

    echo "TARGET_MAPPING_PASS=1"
    echo "RENDER_SYSFS=${render_sysfs}"
}

query_target()
{
    xbutil query -d "${TARGET_BDF}" 2>&1
}

echo "============================================================"
echo "Stage 2N-A11 Protected 256-Sample Automatic-Pipeline Regression v1"
echo "TIME=$(date -Is)"
echo "REPO=$(pwd)"
echo "BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || echo UNKNOWN)"
echo "HEAD=$(git rev-parse HEAD 2>/dev/null || echo UNKNOWN)"
echo "TARGET_INDEX=${TARGET_INDEX}"
echo "TARGET_BDF=${TARGET_BDF}"
echo "TARGET_RENDER=${TARGET_RENDER}"
echo "EXPECTED_UUID=${EXPECTED_UUID}"
echo "EXPECTED_CU=${EXPECTED_CU}"
echo "NO FPGA PROGRAMMING"
echo "NO FPGA RESET"
echo "NO AUTOMATIC ROLLBACK"
echo "============================================================"

for tool in xbutil g++ nm sha256sum awk grep fuser lsof stat python3; do
    command -v "${tool}" >/dev/null 2>&1 ||
        fail "required tool not found: ${tool}"
done

[[ -n "${XILINX_XRT:-}" ]] ||
    fail "XILINX_XRT is not set"
[[ -f "${XILINX_XRT}/include/xrt.h" ]] ||
    fail "XRT xrt.h not found"
[[ -f "${XILINX_XRT}/include/experimental/xrt-next.h" ]] ||
    fail "XRT experimental/xrt-next.h not found"
[[ -e "${TARGET_RENDER}" ]] ||
    fail "render node not found: ${TARGET_RENDER}"

for file in \
    "${SOURCE}" \
    "${ASSET}" \
    "${ASSET_STATUS}" \
    "${A10_FINAL_STATUS}"
do
    require_file "${file}"
done

CURRENT_BRANCH="$(git symbolic-ref --short HEAD 2>/dev/null || true)"
[[ "${CURRENT_BRANCH}" == "${EXPECTED_BRANCH}" ]] ||
    fail "unexpected branch: ${CURRENT_BRANCH}"

git merge-base --is-ancestor "${REQUIRED_ANCESTOR}" HEAD ||
    fail "current branch does not descend from ${REQUIRED_ANCESTOR}"

require_exact \
    "${ASSET_STATUS}" \
    "STAGE2N_A11_PIPELINE_BATCH_ASSET_V2_PASS"
require_exact "${ASSET_STATUS}" "SAMPLE_COUNT=256"
require_exact "${ASSET_STATUS}" "DESCRIPTOR_COUNT=5"
require_exact "${ASSET_STATUS}" "WEIGHT_COUNT=1360"
require_exact "${ASSET_STATUS}" "BIAS_COUNT=73"
require_exact "${ASSET_STATUS}" "INTERACTION_SHIFT=11"
require_exact "${ASSET_STATUS}" "SOFTWARE_TOP_EXACT=256"
require_exact "${ASSET_STATUS}" "SOFTWARE_CLASSIFICATION_CORRECT=228"

require_exact \
    "${A10_FINAL_STATUS}" \
    "STAGE2N_A10_FINAL_ACCEPTANCE_V4_PASS"
require_exact \
    "${A10_FINAL_STATUS}" \
    "XCLBIN_UUID=${EXPECTED_UUID}"

(
    cd "${ASSET_EVIDENCE}"
    sha256sum -c \
        stage2n_a11_pipeline_batch_asset_v2_manifest.sha256
)

python3 - "${ASSET}" "${ASSET_STATUS}" <<'PY'
from __future__ import print_function
import hashlib
import re
import sys

asset = sys.argv[1]
status = sys.argv[2]

with open(asset, "rb") as f:
    actual = hashlib.sha256(f.read()).hexdigest()
with open(status, "r") as f:
    text = f.read()

match = re.search(r"^OUTPUT_ASSET_SHA256=([0-9a-f]{64})$", text, re.M)
if match is None:
    raise SystemExit("ASSET_STATUS_SHA256_FORMAT_VALID=0")

stored = match.group(1)
print("ASSET_SHA256_LENGTH={}".format(len(stored)))
print("ASSET_SHA256_MATCHES_STATUS={}".format(int(actual == stored)))
if actual != stored:
    raise SystemExit("asset SHA256 does not match status")
PY

echo
echo "========== BUILD A11 HOST BEFORE FPGA ACCESS =========="

set +e
g++ \
    -std=gnu++11 \
    -O2 \
    -Wall \
    -Wextra \
    -Wpedantic \
    -I"${XILINX_XRT}/include" \
    "${SOURCE}" \
    -L"${XILINX_XRT}/lib" \
    -Wl,-rpath,"${XILINX_XRT}/lib" \
    -lxrt_core \
    -pthread \
    -ldl \
    -o "${BINARY}"
BUILD_RESULT="$?"
set -e

[[ "${BUILD_RESULT}" -eq 0 ]] ||
    fail "A11 host compilation returned ${BUILD_RESULT}"

ls -lh "${BINARY}"

echo
echo "This run will access ONLY:"
echo "  index ${TARGET_INDEX}"
echo "  BDF ${TARGET_BDF}"
echo "  render node ${TARGET_RENDER}"
echo
echo "It will execute 256 register-driven inference samples."
echo "It will not program or reset the FPGA."
echo

AUTHORIZATION_TEXT="授权仅对 index 2、BDF 0000:9b:00.1、renderD129 进行 Stage 2N-A11 256样本自动流水线回归，不允许操作其他设备，不允许复位。"

read -r -p \
    "请输入完整授权语句后继续： " \
    AUTHORIZATION_INPUT

[[ "${AUTHORIZATION_INPUT}" == "${AUTHORIZATION_TEXT}" ]] ||
    fail "A11 FPGA-access authorization did not match exactly"

AUTHORIZATION_CONFIRMED=1

echo
echo "========== AUTHORIZED TARGET MAPPING =========="
check_target_mapping

echo
echo "========== PRE-RUN DEVICE STATE =========="
PRE_QUERY="$(query_target)" ||
    fail "pre-run xbutil query failed"
echo "${PRE_QUERY}"

echo "${PRE_QUERY}" | grep -q "Level 0 : 0x0(GOOD)" ||
    fail "target firewall is not GOOD before A11"

PRE_UUID="$(printf '%s\n' "${PRE_QUERY}" | extract_uuid)"
[[ "${PRE_UUID}" == "${EXPECTED_UUID}" ]] ||
    fail "current target UUID is not the accepted A10 image: ${PRE_UUID}"

echo "${PRE_QUERY}" | grep -Fq "${EXPECTED_CU}" ||
    fail "accepted A10 CU is missing"
echo "${PRE_QUERY}" | grep -Fq "(IDLE)" ||
    fail "accepted A10 CU is not IDLE"

require_empty_render "PRE_RUN"

echo
echo "========== RUN A11 256-SAMPLE HOST =========="

set +e
"${BINARY}" "${ASSET}" "${CSV}"
HOST_RESULT="$?"
set -e

[[ "${HOST_RESULT}" -eq 0 ]] ||
    fail "A11 Host returned ${HOST_RESULT}"

grep -Fq \
    "STAGE2N_A11_REAL_MODEL_BATCH_BOARD_V1_PASS samples=256 logits=256 predictions=256 correct=228 accuracy=0.890625 tag=4" \
    "${LOG}" ||
    fail "A11 Host PASS marker is missing"

for exact_line in \
    "PIPELINE_START_COMMANDS=256" \
    "FPGA_LOGIT_EXACT=256" \
    "FPGA_PREDICTION_EXACT=256" \
    "FPGA_RESULT_INDEX_EXACT=256" \
    "FPGA_RESULT_TAG_EXACT=256" \
    "FPGA_BOTTOM_COUNT_EXACT=256" \
    "FPGA_INTERACTION_COUNT_EXACT=256" \
    "FPGA_CLASSIFICATION_CORRECT=228" \
    "FPGA_CLASSIFICATION_ACCURACY=0.890625"
do
    grep -Fxq "${exact_line}" "${LOG}" ||
        fail "missing Host result line: ${exact_line}"
done

[[ -s "${CSV}" ]] ||
    fail "A11 sample result CSV is missing or empty"

CSV_ROWS="$(
    awk 'END {print NR-1}' "${CSV}"
)"
[[ "${CSV_ROWS}" == "256" ]] ||
    fail "A11 CSV sample count mismatch: ${CSV_ROWS}"

CSV_LOGIT_EXACT="$(
    awk -F, 'NR > 1 && $7 == 1 {count++} END {print count+0}' "${CSV}"
)"
CSV_PREDICTION_EXACT="$(
    awk -F, 'NR > 1 && $8 == 1 {count++} END {print count+0}' "${CSV}"
)"
CSV_CLASSIFICATION_CORRECT="$(
    awk -F, 'NR > 1 && $9 == 1 {count++} END {print count+0}' "${CSV}"
)"

[[ "${CSV_LOGIT_EXACT}" == "256" ]] ||
    fail "CSV exact-logit count mismatch"
[[ "${CSV_PREDICTION_EXACT}" == "256" ]] ||
    fail "CSV exact-prediction count mismatch"
[[ "${CSV_CLASSIFICATION_CORRECT}" == "228" ]] ||
    fail "CSV classification count mismatch"

echo
echo "========== POST-RUN DEVICE STATE =========="

POST_QUERY="$(query_target)" ||
    fail "post-run xbutil query failed"
echo "${POST_QUERY}"

echo "${POST_QUERY}" | grep -q "Level 0 : 0x0(GOOD)" ||
    fail "target firewall is not GOOD after A11"

POST_UUID="$(printf '%s\n' "${POST_QUERY}" | extract_uuid)"
[[ "${POST_UUID}" == "${EXPECTED_UUID}" ]] ||
    fail "target UUID changed during A11"

echo "${POST_QUERY}" | grep -Fq "${EXPECTED_CU}" ||
    fail "A10 CU disappeared after A11"
echo "${POST_QUERY}" | grep -Fq "(IDLE)" ||
    fail "A10 CU is not IDLE after A11"

require_empty_render "POST_RUN"

BATCH_ELAPSED_US="$(
    grep '^BATCH_ELAPSED_US=' "${LOG}" |
    tail -n 1 |
    cut -d= -f2
)"

{
    echo "STAGE2N_A11_REAL_MODEL_BATCH_BOARD_V1_PASS"
    echo "TIME=$(date -Is)"
    echo "GIT_BRANCH=${CURRENT_BRANCH}"
    echo "GIT_HEAD=$(git rev-parse HEAD)"
    echo "TARGET_INDEX=${TARGET_INDEX}"
    echo "TARGET_BDF=${TARGET_BDF}"
    echo "TARGET_RENDER=${TARGET_RENDER}"
    echo "AUTHORIZATION_CONFIRMED=${AUTHORIZATION_CONFIRMED}"
    echo "XCLBIN_UUID=${POST_UUID}"
    echo "KERNEL=${EXPECTED_KERNEL}"
    echo "COMPUTE_UNIT=${EXPECTED_INSTANCE}"
    echo "IP_NAME=${EXPECTED_CU}"
    echo "ASSET=${ASSET}"
    echo "SAMPLE_COUNT=256"
    echo "PIPELINE_START_COMMANDS=256"
    echo "FPGA_LOGIT_EXACT=256"
    echo "FPGA_PREDICTION_EXACT=256"
    echo "FPGA_RESULT_INDEX_EXACT=256"
    echo "FPGA_RESULT_TAG_EXACT=256"
    echo "FPGA_BOTTOM_COUNT_EXACT=256"
    echo "FPGA_INTERACTION_COUNT_EXACT=256"
    echo "FPGA_CLASSIFICATION_CORRECT=228"
    echo "FPGA_CLASSIFICATION_ACCURACY=0.890625"
    echo "FINAL_DESCRIPTOR_TAG=4"
    echo "BATCH_ELAPSED_US=${BATCH_ELAPSED_US}"
    echo "CSV=${CSV}"
    echo "LOG=${LOG}"
    echo "FIREWALL_GOOD_AFTER_TEST=1"
    echo "CU_IDLE_AFTER_TEST=1"
    echo "NO_FPGA_PROGRAMMING=1"
    echo "NO_FPGA_RESET=1"
    echo "NO_AUTOMATIC_ROLLBACK=1"
    echo "NO_OTHER_DEVICE_ACCESS=1"
} > "${STATUS}"

echo
echo "============================================================"
echo "STAGE2N_A11_REAL_MODEL_BATCH_BOARD_V1_PASS"
echo "TARGET=${TARGET_BDF} (xbutil index ${TARGET_INDEX})"
echo "UUID=${POST_UUID}"
echo "CU=${EXPECTED_CU}"
echo "SAMPLES=256"
echo "FPGA_LOGIT_EXACT=256"
echo "FPGA_PREDICTION_EXACT=256"
echo "FPGA_CLASSIFICATION_CORRECT=228"
echo "FPGA_CLASSIFICATION_ACCURACY=0.890625"
echo "FINAL_DESCRIPTOR_TAG=4"
echo "BATCH_ELAPSED_US=${BATCH_ELAPSED_US}"
echo "STATUS=${STATUS}"
echo "CSV=${CSV}"
echo "LOG=${LOG}"
echo "NO FPGA PROGRAMMING WAS PERFORMED"
echo "NO FPGA RESET WAS PERFORMED"
echo "NO OTHER DEVICE WAS ACCESSED"
echo "============================================================"
