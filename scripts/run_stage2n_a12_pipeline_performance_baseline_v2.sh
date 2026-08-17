#!/usr/bin/env bash
#
# Stage 2N-A12 protected host-visible performance baseline v2.
#
# Uses the already-programmed Stage 2N-A10 xclbin and the accepted A11 asset.
# It never programs, resets, or rolls back the FPGA.
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

EXPECTED_BRANCH="work/stage2n-a12-performance-baseline"
REQUIRED_ANCESTOR="9f0aeb0edfebbb5327490a93f782797c78bdf9f7"

EXPECTED_UUID="f7a23117-5218-4fba-adb5-f093b596df03"
EXPECTED_KERNEL="dlrm_f37x_rtl_kernel_stage2n_a10_v2"
EXPECTED_INSTANCE="dlrm_a10_1"
EXPECTED_CU="${EXPECTED_KERNEL}:${EXPECTED_INSTANCE}"

WARMUP_PASSES="${STAGE2N_A12_WARMUP_PASSES:-1}"
MEASURED_PASSES="${STAGE2N_A12_MEASURED_PASSES:-20}"

SOURCE="host/stage2n_a12_pipeline_performance_baseline_v1.cpp"
A11_SOURCE="host/stage2n_a11_real_model_batch_board_v1.cpp"
ASSET="build/stage2n_a11/assets_v2/stage2n_a11_real_model_batch_v2.f37xpb"
ASSET_STATUS="results/stage2n_a11/assets_v2/stage2n_a11_real_model_batch_v2_status.txt"
A11_FINAL_STATUS="docs/evidence/stage2n_a11_final_v1/stage2n_a11_final_acceptance_v1_status.txt"

BUILD_DIR="build/stage2n_a12/performance_baseline_v2"
RESULT_DIR="results/stage2n_a12/performance_baseline_v2"
SERVER_RESULT_DIR="server_results/stage2n_a12_v2"

mkdir -p "${BUILD_DIR}" "${RESULT_DIR}" "${SERVER_RESULT_DIR}"

STAMP="$(date +%Y%m%d_%H%M%S)"
BINARY="${BUILD_DIR}/stage2n_a12_pipeline_performance_baseline_v2_${STAMP}"
LOG="${SERVER_RESULT_DIR}/stage2n_a12_pipeline_performance_baseline_v2_${STAMP}.log"
STATUS="${RESULT_DIR}/stage2n_a12_pipeline_performance_baseline_v2_status_${STAMP}.txt"
SAMPLE_CSV="${RESULT_DIR}/stage2n_a12_pipeline_performance_samples_v2_${STAMP}.csv"
PASS_CSV="${RESULT_DIR}/stage2n_a12_pipeline_performance_passes_v2_${STAMP}.csv"

exec > >(tee "${LOG}") 2>&1

write_failure()
{
    local reason="$1"
    {
        echo "STAGE2N_A12_PIPELINE_PERFORMANCE_BASELINE_V2_FAILED"
        echo "TIME=$(date -Is)"
        echo "TARGET_INDEX=${TARGET_INDEX}"
        echo "TARGET_BDF=${TARGET_BDF}"
        echo "TARGET_RENDER=${TARGET_RENDER}"
        echo "WARMUP_PASSES=${WARMUP_PASSES}"
        echo "MEASURED_PASSES=${MEASURED_PASSES}"
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

require_positive_integer()
{
    local name="$1"
    local value="$2"
    [[ "${value}" =~ ^[1-9][0-9]*$ ]] ||
        fail "${name} must be a positive integer: ${value}"
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
echo "Stage 2N-A12 Protected Performance Baseline v2"
echo "TIME=$(date -Is)"
echo "REPO=$(pwd)"
echo "BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || echo UNKNOWN)"
echo "HEAD=$(git rev-parse HEAD 2>/dev/null || echo UNKNOWN)"
echo "TARGET_INDEX=${TARGET_INDEX}"
echo "TARGET_BDF=${TARGET_BDF}"
echo "TARGET_RENDER=${TARGET_RENDER}"
echo "EXPECTED_UUID=${EXPECTED_UUID}"
echo "EXPECTED_CU=${EXPECTED_CU}"
echo "WARMUP_PASSES=${WARMUP_PASSES}"
echo "MEASURED_PASSES=${MEASURED_PASSES}"
echo "TIMING_SCOPE=host-visible register-driven latency"
echo "NO FPGA PROGRAMMING"
echo "NO FPGA RESET"
echo "NO AUTOMATIC ROLLBACK"
echo "============================================================"

for tool in xbutil g++ awk grep fuser lsof python3; do
    command -v "${tool}" >/dev/null 2>&1 ||
        fail "required tool not found: ${tool}"
done

require_positive_integer "WARMUP_PASSES" "${WARMUP_PASSES}"
require_positive_integer "MEASURED_PASSES" "${MEASURED_PASSES}"
[[ "${WARMUP_PASSES}" -le 100 ]] ||
    fail "WARMUP_PASSES exceeds 100"
[[ "${MEASURED_PASSES}" -le 1000 ]] ||
    fail "MEASURED_PASSES exceeds 1000"

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
    "${A11_SOURCE}" \
    "${ASSET}" \
    "${ASSET_STATUS}" \
    "${A11_FINAL_STATUS}"
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

require_exact \
    "${A11_FINAL_STATUS}" \
    "STAGE2N_A11_FINAL_ACCEPTANCE_V1_PASS"
require_exact \
    "${A11_FINAL_STATUS}" \
    "XCLBIN_UUID=${EXPECTED_UUID}"
require_exact "${A11_FINAL_STATUS}" "FPGA_LOGIT_EXACT=256"

echo
echo "========== BUILD A12 HOST BEFORE FPGA ACCESS =========="

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
    fail "A12 host compilation returned ${BUILD_RESULT}"

ls -lh "${BINARY}"

echo
echo "This benchmark will access ONLY:"
echo "  index ${TARGET_INDEX}"
echo "  BDF ${TARGET_BDF}"
echo "  render node ${TARGET_RENDER}"
echo
echo "It will run ${WARMUP_PASSES} warm-up pass(es) and"
echo "${MEASURED_PASSES} measured pass(es) over 256 samples."
echo "It will not program or reset the FPGA."
echo

AUTHORIZATION_TEXT="授权仅对 index 2、BDF 0000:9b:00.1、renderD129 进行 Stage 2N-A12 性能基线测量 v2，不允许操作其他设备，不允许复位。"

read -r -p \
    "请输入完整授权语句后继续： " \
    AUTHORIZATION_INPUT

[[ "${AUTHORIZATION_INPUT}" == "${AUTHORIZATION_TEXT}" ]] ||
    fail "A12 FPGA-access authorization did not match exactly"

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
    fail "target firewall is not GOOD before A12"

PRE_UUID="$(printf '%s\n' "${PRE_QUERY}" | extract_uuid)"
[[ "${PRE_UUID}" == "${EXPECTED_UUID}" ]] ||
    fail "current target UUID is not the accepted A10 image: ${PRE_UUID}"

echo "${PRE_QUERY}" | grep -Fq "${EXPECTED_CU}" ||
    fail "accepted A10 CU is missing"
echo "${PRE_QUERY}" | grep -Fq "(IDLE)" ||
    fail "accepted A10 CU is not IDLE"

require_empty_render "PRE_RUN"

echo
echo "========== RUN A12 PERFORMANCE BASELINE =========="

set +e
"${BINARY}" \
    "${ASSET}" \
    "${SAMPLE_CSV}" \
    "${PASS_CSV}" \
    "${WARMUP_PASSES}" \
    "${MEASURED_PASSES}"
HOST_RESULT="$?"
set -e

[[ "${HOST_RESULT}" -eq 0 ]] ||
    fail "A12 Host returned ${HOST_RESULT}"

MEASURED_SAMPLES="$(
    python3 - "${MEASURED_PASSES}" <<'PY'
import sys
print(int(sys.argv[1]) * 256)
PY
)"
EXPECTED_CORRECT="$(
    python3 - "${MEASURED_PASSES}" <<'PY'
import sys
print(int(sys.argv[1]) * 228)
PY
)"

grep -Fq \
    "STAGE2N_A12_PIPELINE_PERFORMANCE_BASELINE_V1_PASS warmup_passes=${WARMUP_PASSES} measured_passes=${MEASURED_PASSES} measured_samples=${MEASURED_SAMPLES} logit_exact=${MEASURED_SAMPLES} prediction_exact=${MEASURED_SAMPLES}" \
    "${LOG}" ||
    fail "A12 Host PASS marker is missing"

for exact_line in \
    "WARMUP_PASSES=${WARMUP_PASSES}" \
    "MEASURED_PASSES=${MEASURED_PASSES}" \
    "MEASURED_SAMPLES=${MEASURED_SAMPLES}" \
    "MEASURED_LOGIT_EXACT=${MEASURED_SAMPLES}" \
    "MEASURED_PREDICTION_EXACT=${MEASURED_SAMPLES}" \
    "MEASURED_CLASSIFICATION_CORRECT=${EXPECTED_CORRECT}" \
    "NO_FPGA_PROGRAMMING=1" \
    "NO_FPGA_RESET=1"
do
    grep -Fxq "${exact_line}" "${LOG}" ||
        fail "missing A12 Host result line: ${exact_line}"
done

for metric in \
    STATIC_MODEL_CONFIG_US \
    TOTAL_SAMPLE_LATENCY_MEAN_US \
    TOTAL_SAMPLE_LATENCY_P50_US \
    TOTAL_SAMPLE_LATENCY_P95_US \
    TOTAL_SAMPLE_LATENCY_P99_US \
    INPUT_PROGRAM_LATENCY_MEAN_US \
    WAIT_VALID_LATENCY_MEAN_US \
    MEASURED_BATCH_TOTAL_US \
    INSTRUMENTED_WALL_TOTAL_US \
    HOST_VISIBLE_THROUGHPUT_SAMPLES_PER_SEC \
    INSTRUMENTED_WALL_THROUGHPUT_SAMPLES_PER_SEC \
    INPUT_PROGRAM_FRACTION \
    WAIT_VALID_FRACTION \
    CONTROL_AND_RETIRE_FRACTION
do
    grep -Eq "^${metric}=[0-9]+([.][0-9]+)?$" "${LOG}" ||
        fail "missing or invalid positive metric: ${metric}"
done

[[ -s "${SAMPLE_CSV}" ]] ||
    fail "A12 sample timing CSV is missing"
[[ -s "${PASS_CSV}" ]] ||
    fail "A12 pass summary CSV is missing"

SAMPLE_ROWS="$(
    awk 'END {print NR-1}' "${SAMPLE_CSV}"
)"
PASS_ROWS="$(
    awk 'END {print NR-1}' "${PASS_CSV}"
)"
[[ "${SAMPLE_ROWS}" == "${MEASURED_SAMPLES}" ]] ||
    fail "A12 sample CSV row count mismatch: ${SAMPLE_ROWS}"
[[ "${PASS_ROWS}" == "${MEASURED_PASSES}" ]] ||
    fail "A12 pass CSV row count mismatch: ${PASS_ROWS}"

EXPECTED_SAMPLE_CSV_HEADER='measured_pass,sample_id,label,expected_logit,fpga_logit,expected_prediction,fpga_prediction,classification_correct,result_index,result_tag,bottom_count,interaction_count,prepare_idle_us,input_program_us,start_issue_us,wait_valid_us,result_read_us,retire_us,total_us'
ACTUAL_SAMPLE_CSV_HEADER="$(head -n 1 "${SAMPLE_CSV}" | tr -d '\r')"
[[ "${ACTUAL_SAMPLE_CSV_HEADER}" == "${EXPECTED_SAMPLE_CSV_HEADER}" ]] ||
    fail "A12 sample CSV header mismatch"

SAMPLE_TAG_EXACT="$(
    awk -F, 'NR > 1 && $9 == 0 && $10 == 4 {count++}
             END {print count+0}' "${SAMPLE_CSV}"
)"
SAMPLE_PHASE_COUNT_EXACT="$(
    awk -F, 'NR > 1 && $11 == 8 && $12 == 18 {count++}
             END {print count+0}' "${SAMPLE_CSV}"
)"
[[ "${SAMPLE_TAG_EXACT}" == "${MEASURED_SAMPLES}" ]] ||
    fail "A12 sample CSV result metadata mismatch"
[[ "${SAMPLE_PHASE_COUNT_EXACT}" == "${MEASURED_SAMPLES}" ]] ||
    fail "A12 sample CSV phase-count mismatch"

echo
echo "========== POST-RUN DEVICE STATE =========="

POST_QUERY="$(query_target)" ||
    fail "post-run xbutil query failed"
echo "${POST_QUERY}"

echo "${POST_QUERY}" | grep -q "Level 0 : 0x0(GOOD)" ||
    fail "target firewall is not GOOD after A12"

POST_UUID="$(printf '%s\n' "${POST_QUERY}" | extract_uuid)"
[[ "${POST_UUID}" == "${EXPECTED_UUID}" ]] ||
    fail "target UUID changed during A12"

echo "${POST_QUERY}" | grep -Fq "${EXPECTED_CU}" ||
    fail "A10 CU disappeared after A12"
echo "${POST_QUERY}" | grep -Fq "(IDLE)" ||
    fail "A10 CU is not IDLE after A12"

require_empty_render "POST_RUN"

metric_value()
{
    local name="$1"
    grep "^${name}=" "${LOG}" |
        tail -n 1 |
        cut -d= -f2-
}

STATIC_MODEL_CONFIG_US="$(metric_value STATIC_MODEL_CONFIG_US)"
TOTAL_SAMPLE_LATENCY_MEAN_US="$(
    metric_value TOTAL_SAMPLE_LATENCY_MEAN_US
)"
TOTAL_SAMPLE_LATENCY_P50_US="$(
    metric_value TOTAL_SAMPLE_LATENCY_P50_US
)"
TOTAL_SAMPLE_LATENCY_P95_US="$(
    metric_value TOTAL_SAMPLE_LATENCY_P95_US
)"
TOTAL_SAMPLE_LATENCY_P99_US="$(
    metric_value TOTAL_SAMPLE_LATENCY_P99_US
)"
INPUT_PROGRAM_LATENCY_MEAN_US="$(
    metric_value INPUT_PROGRAM_LATENCY_MEAN_US
)"
WAIT_VALID_LATENCY_MEAN_US="$(
    metric_value WAIT_VALID_LATENCY_MEAN_US
)"
MEASURED_BATCH_TOTAL_US="$(
    metric_value MEASURED_BATCH_TOTAL_US
)"
INSTRUMENTED_WALL_TOTAL_US="$(
    metric_value INSTRUMENTED_WALL_TOTAL_US
)"
HOST_VISIBLE_THROUGHPUT="$(
    metric_value HOST_VISIBLE_THROUGHPUT_SAMPLES_PER_SEC
)"
INSTRUMENTED_WALL_THROUGHPUT="$(
    metric_value INSTRUMENTED_WALL_THROUGHPUT_SAMPLES_PER_SEC
)"
INPUT_PROGRAM_FRACTION="$(
    metric_value INPUT_PROGRAM_FRACTION
)"
WAIT_VALID_FRACTION="$(
    metric_value WAIT_VALID_FRACTION
)"
CONTROL_AND_RETIRE_FRACTION="$(
    metric_value CONTROL_AND_RETIRE_FRACTION
)"

{
    echo "STAGE2N_A12_PIPELINE_PERFORMANCE_BASELINE_V2_PASS"
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
    echo "TIMING_SCOPE=host-visible register-driven latency"
    echo "WARMUP_PASSES=${WARMUP_PASSES}"
    echo "MEASURED_PASSES=${MEASURED_PASSES}"
    echo "MEASURED_SAMPLES=${MEASURED_SAMPLES}"
    echo "STATIC_MODEL_CONFIG_US=${STATIC_MODEL_CONFIG_US}"
    echo "TOTAL_SAMPLE_LATENCY_MEAN_US=${TOTAL_SAMPLE_LATENCY_MEAN_US}"
    echo "TOTAL_SAMPLE_LATENCY_P50_US=${TOTAL_SAMPLE_LATENCY_P50_US}"
    echo "TOTAL_SAMPLE_LATENCY_P95_US=${TOTAL_SAMPLE_LATENCY_P95_US}"
    echo "TOTAL_SAMPLE_LATENCY_P99_US=${TOTAL_SAMPLE_LATENCY_P99_US}"
    echo "INPUT_PROGRAM_LATENCY_MEAN_US=${INPUT_PROGRAM_LATENCY_MEAN_US}"
    echo "WAIT_VALID_LATENCY_MEAN_US=${WAIT_VALID_LATENCY_MEAN_US}"
    echo "MEASURED_BATCH_TOTAL_US=${MEASURED_BATCH_TOTAL_US}"
    echo "INSTRUMENTED_WALL_TOTAL_US=${INSTRUMENTED_WALL_TOTAL_US}"
    echo "HOST_VISIBLE_THROUGHPUT_SAMPLES_PER_SEC=${HOST_VISIBLE_THROUGHPUT}"
    echo "INSTRUMENTED_WALL_THROUGHPUT_SAMPLES_PER_SEC=${INSTRUMENTED_WALL_THROUGHPUT}"
    echo "INPUT_PROGRAM_FRACTION=${INPUT_PROGRAM_FRACTION}"
    echo "WAIT_VALID_FRACTION=${WAIT_VALID_FRACTION}"
    echo "CONTROL_AND_RETIRE_FRACTION=${CONTROL_AND_RETIRE_FRACTION}"
    echo "MEASURED_LOGIT_EXACT=${MEASURED_SAMPLES}"
    echo "MEASURED_PREDICTION_EXACT=${MEASURED_SAMPLES}"
    echo "MEASURED_CLASSIFICATION_CORRECT=${EXPECTED_CORRECT}"
    echo "SAMPLE_CSV=${SAMPLE_CSV}"
    echo "PASS_CSV=${PASS_CSV}"
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
echo "STAGE2N_A12_PIPELINE_PERFORMANCE_BASELINE_V2_PASS"
echo "TARGET=${TARGET_BDF} (xbutil index ${TARGET_INDEX})"
echo "UUID=${POST_UUID}"
echo "WARMUP_PASSES=${WARMUP_PASSES}"
echo "MEASURED_PASSES=${MEASURED_PASSES}"
echo "MEASURED_SAMPLES=${MEASURED_SAMPLES}"
echo "STATIC_MODEL_CONFIG_US=${STATIC_MODEL_CONFIG_US}"
echo "TOTAL_SAMPLE_LATENCY_MEAN_US=${TOTAL_SAMPLE_LATENCY_MEAN_US}"
echo "TOTAL_SAMPLE_LATENCY_P50_US=${TOTAL_SAMPLE_LATENCY_P50_US}"
echo "TOTAL_SAMPLE_LATENCY_P95_US=${TOTAL_SAMPLE_LATENCY_P95_US}"
echo "TOTAL_SAMPLE_LATENCY_P99_US=${TOTAL_SAMPLE_LATENCY_P99_US}"
echo "HOST_VISIBLE_THROUGHPUT_SAMPLES_PER_SEC=${HOST_VISIBLE_THROUGHPUT}"
echo "INSTRUMENTED_WALL_TOTAL_US=${INSTRUMENTED_WALL_TOTAL_US}"
echo "INSTRUMENTED_WALL_THROUGHPUT_SAMPLES_PER_SEC=${INSTRUMENTED_WALL_THROUGHPUT}"
echo "INPUT_PROGRAM_FRACTION=${INPUT_PROGRAM_FRACTION}"
echo "WAIT_VALID_FRACTION=${WAIT_VALID_FRACTION}"
echo "CONTROL_AND_RETIRE_FRACTION=${CONTROL_AND_RETIRE_FRACTION}"
echo "STATUS=${STATUS}"
echo "SAMPLE_CSV=${SAMPLE_CSV}"
echo "PASS_CSV=${PASS_CSV}"
echo "LOG=${LOG}"
echo "NO FPGA PROGRAMMING WAS PERFORMED"
echo "NO FPGA RESET WAS PERFORMED"
echo "NO OTHER DEVICE WAS ACCESSED"
echo "============================================================"
