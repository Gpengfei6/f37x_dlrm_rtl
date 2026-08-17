#!/usr/bin/env bash
#
# Collect and validate final Stage 2N-A12 performance-baseline evidence v1.
#
# Read-only with respect to FPGA hardware:
#   - no xbutil;
#   - no render-node access;
#   - no FPGA programming;
#   - no FPGA reset.
#

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

EXPECTED_BRANCH="work/stage2n-a12-performance-baseline"
EXPECTED_UUID="f7a23117-5218-4fba-adb5-f093b596df03"
EXPECTED_KERNEL="dlrm_f37x_rtl_kernel_stage2n_a10_v2"
EXPECTED_INSTANCE="dlrm_a10_1"
EXPECTED_IP_NAME="${EXPECTED_KERNEL}:${EXPECTED_INSTANCE}"

RESULT_DIR="${REPO_ROOT}/results/stage2n_a12/performance_baseline_v2"
LOG_DIR="${REPO_ROOT}/server_results/stage2n_a12_v2"

HOST_SOURCE="${REPO_ROOT}/host/stage2n_a12_pipeline_performance_baseline_v1.cpp"
RUNNER_V1="${REPO_ROOT}/scripts/run_stage2n_a12_pipeline_performance_baseline_v1.sh"
RUNNER_V2="${REPO_ROOT}/scripts/run_stage2n_a12_pipeline_performance_baseline_v2.sh"
DOC_V1="${REPO_ROOT}/docs/STAGE2N_A12_PIPELINE_PERFORMANCE_BASELINE_V1.md"
DOC_FIX_V2="${REPO_ROOT}/docs/STAGE2N_A12_PERFORMANCE_BASELINE_RUNNER_FIX_V2.md"
A11_FINAL_STATUS="${REPO_ROOT}/docs/evidence/stage2n_a11_final_v1/stage2n_a11_final_acceptance_v1_status.txt"

EVIDENCE_DIR="${REPO_ROOT}/docs/evidence/stage2n_a12_final_v1"
FINAL_STATUS="${EVIDENCE_DIR}/stage2n_a12_final_acceptance_v1_status.txt"
MANIFEST="${EVIDENCE_DIR}/stage2n_a12_final_evidence_manifest_v1.sha256"

fail()
{
    local reason="$*"
    mkdir -p "${EVIDENCE_DIR}"
    cat > "${FINAL_STATUS}" <<EOF
STAGE2N_A12_FINAL_ACCEPTANCE_V1_FAILED
REASON=${reason}
NO_FPGA_ACCESS=1
NO_FPGA_PROGRAMMING_OR_RESET=1
EOF
    echo "ERROR: ${reason}" >&2
    exit 60
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

require_regex()
{
    local file="$1"
    local pattern="$2"
    grep -Eq "${pattern}" "${file}" ||
        fail "missing required pattern in ${file}: ${pattern}"
}

metric()
{
    local file="$1"
    local name="$2"
    grep "^${name}=" "${file}" |
        tail -n 1 |
        cut -d= -f2-
}

copy_evidence()
{
    local source="$1"
    local destination_name="$2"
    cp -f "${source}" "${EVIDENCE_DIR}/${destination_name}"
}

cd "${REPO_ROOT}"

CURRENT_BRANCH="$(git symbolic-ref --short HEAD 2>/dev/null || echo DETACHED)"
CURRENT_HEAD="$(git rev-parse HEAD)"

[[ "${CURRENT_BRANCH}" == "${EXPECTED_BRANCH}" ]] ||
    fail "unexpected branch: ${CURRENT_BRANCH}"

for file in \
    "${HOST_SOURCE}" \
    "${RUNNER_V1}" \
    "${RUNNER_V2}" \
    "${DOC_V1}" \
    "${DOC_FIX_V2}" \
    "${A11_FINAL_STATUS}"
do
    require_file "${file}"
done

LATEST_STATUS="$(
    find "${RESULT_DIR}" \
        -maxdepth 1 \
        -type f \
        -name 'stage2n_a12_pipeline_performance_baseline_v2_status_*.txt' \
        -printf '%T@ %p\n' |
    sort -nr |
    head -n 1 |
    cut -d' ' -f2-
)"
[[ -n "${LATEST_STATUS}" ]] ||
    fail "no Stage 2N-A12 v2 PASS status found"
require_file "${LATEST_STATUS}"

require_exact "${LATEST_STATUS}" \
    "STAGE2N_A12_PIPELINE_PERFORMANCE_BASELINE_V2_PASS"
require_exact "${LATEST_STATUS}" "GIT_BRANCH=${EXPECTED_BRANCH}"
require_exact "${LATEST_STATUS}" "TARGET_INDEX=2"
require_exact "${LATEST_STATUS}" "TARGET_BDF=0000:9b:00.1"
require_exact "${LATEST_STATUS}" "TARGET_RENDER=/dev/dri/renderD129"
require_exact "${LATEST_STATUS}" "AUTHORIZATION_CONFIRMED=1"
require_exact "${LATEST_STATUS}" "XCLBIN_UUID=${EXPECTED_UUID}"
require_exact "${LATEST_STATUS}" "KERNEL=${EXPECTED_KERNEL}"
require_exact "${LATEST_STATUS}" "COMPUTE_UNIT=${EXPECTED_INSTANCE}"
require_exact "${LATEST_STATUS}" "IP_NAME=${EXPECTED_IP_NAME}"
require_exact "${LATEST_STATUS}" \
    "TIMING_SCOPE=host-visible register-driven latency"
require_exact "${LATEST_STATUS}" "WARMUP_PASSES=1"
require_exact "${LATEST_STATUS}" "MEASURED_PASSES=20"
require_exact "${LATEST_STATUS}" "MEASURED_SAMPLES=5120"
require_exact "${LATEST_STATUS}" "MEASURED_LOGIT_EXACT=5120"
require_exact "${LATEST_STATUS}" "MEASURED_PREDICTION_EXACT=5120"
require_exact "${LATEST_STATUS}" "MEASURED_CLASSIFICATION_CORRECT=4560"
require_exact "${LATEST_STATUS}" "FIREWALL_GOOD_AFTER_TEST=1"
require_exact "${LATEST_STATUS}" "CU_IDLE_AFTER_TEST=1"
require_exact "${LATEST_STATUS}" "NO_FPGA_PROGRAMMING=1"
require_exact "${LATEST_STATUS}" "NO_FPGA_RESET=1"
require_exact "${LATEST_STATUS}" "NO_AUTOMATIC_ROLLBACK=1"
require_exact "${LATEST_STATUS}" "NO_OTHER_DEVICE_ACCESS=1"

for name in \
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
    require_regex "${LATEST_STATUS}" "^${name}=[0-9]+([.][0-9]+)?$"
done

SAMPLE_CSV_REL="$(metric "${LATEST_STATUS}" SAMPLE_CSV)"
PASS_CSV_REL="$(metric "${LATEST_STATUS}" PASS_CSV)"
LOG_REL="$(metric "${LATEST_STATUS}" LOG)"

[[ -n "${SAMPLE_CSV_REL}" ]] || fail "sample CSV path missing"
[[ -n "${PASS_CSV_REL}" ]] || fail "pass CSV path missing"
[[ -n "${LOG_REL}" ]] || fail "log path missing"

SAMPLE_CSV="${REPO_ROOT}/${SAMPLE_CSV_REL}"
PASS_CSV="${REPO_ROOT}/${PASS_CSV_REL}"
LOG="${REPO_ROOT}/${LOG_REL}"

for file in "${SAMPLE_CSV}" "${PASS_CSV}" "${LOG}"; do
    require_file "${file}"
done

EXPECTED_SAMPLE_HEADER='measured_pass,sample_id,label,expected_logit,fpga_logit,expected_prediction,fpga_prediction,classification_correct,result_index,result_tag,bottom_count,interaction_count,prepare_idle_us,input_program_us,start_issue_us,wait_valid_us,result_read_us,retire_us,total_us'
ACTUAL_SAMPLE_HEADER="$(head -n 1 "${SAMPLE_CSV}" | tr -d '\r')"
[[ "${ACTUAL_SAMPLE_HEADER}" == "${EXPECTED_SAMPLE_HEADER}" ]] ||
    fail "sample CSV header mismatch"

EXPECTED_PASS_HEADER='measured_pass,samples,pass_total_us,throughput_samples_per_sec,logit_exact,prediction_exact,classification_correct'
ACTUAL_PASS_HEADER="$(head -n 1 "${PASS_CSV}" | tr -d '\r')"
[[ "${ACTUAL_PASS_HEADER}" == "${EXPECTED_PASS_HEADER}" ]] ||
    fail "pass CSV header mismatch"

SAMPLE_ROWS="$(awk 'END {print NR-1}' "${SAMPLE_CSV}")"
PASS_ROWS="$(awk 'END {print NR-1}' "${PASS_CSV}")"

[[ "${SAMPLE_ROWS}" == "5120" ]] ||
    fail "sample CSV row count mismatch: ${SAMPLE_ROWS}"
[[ "${PASS_ROWS}" == "20" ]] ||
    fail "pass CSV row count mismatch: ${PASS_ROWS}"

SAMPLE_LOGIT_EXACT="$(
    awk -F, 'NR > 1 && $4 == $5 {count++} END {print count+0}' \
        "${SAMPLE_CSV}"
)"
SAMPLE_PREDICTION_EXACT="$(
    awk -F, 'NR > 1 && $6 == $7 {count++} END {print count+0}' \
        "${SAMPLE_CSV}"
)"
SAMPLE_CLASSIFICATION_CORRECT="$(
    awk -F, 'NR > 1 && $8 == 1 {count++} END {print count+0}' \
        "${SAMPLE_CSV}"
)"
SAMPLE_RESULT_METADATA_EXACT="$(
    awk -F, '
        NR > 1 &&
        $9 == 0 &&
        $10 == 4 &&
        $11 == 8 &&
        $12 == 18 {count++}
        END {print count+0}
    ' "${SAMPLE_CSV}"
)"

[[ "${SAMPLE_LOGIT_EXACT}" == "5120" ]] ||
    fail "sample CSV exact-logit count mismatch"
[[ "${SAMPLE_PREDICTION_EXACT}" == "5120" ]] ||
    fail "sample CSV exact-prediction count mismatch"
[[ "${SAMPLE_CLASSIFICATION_CORRECT}" == "4560" ]] ||
    fail "sample CSV classification count mismatch"
[[ "${SAMPLE_RESULT_METADATA_EXACT}" == "5120" ]] ||
    fail "sample CSV result metadata mismatch"

PASS_SAMPLE_COUNT_EXACT="$(
    awk -F, 'NR > 1 && $2 == 256 {count++} END {print count+0}' \
        "${PASS_CSV}"
)"
PASS_LOGIT_EXACT="$(
    awk -F, 'NR > 1 && $5 == 256 {count++} END {print count+0}' \
        "${PASS_CSV}"
)"
PASS_PREDICTION_EXACT="$(
    awk -F, 'NR > 1 && $6 == 256 {count++} END {print count+0}' \
        "${PASS_CSV}"
)"
PASS_CLASSIFICATION_EXACT="$(
    awk -F, 'NR > 1 && $7 == 228 {count++} END {print count+0}' \
        "${PASS_CSV}"
)"

[[ "${PASS_SAMPLE_COUNT_EXACT}" == "20" ]] ||
    fail "per-pass sample count mismatch"
[[ "${PASS_LOGIT_EXACT}" == "20" ]] ||
    fail "per-pass exact-logit count mismatch"
[[ "${PASS_PREDICTION_EXACT}" == "20" ]] ||
    fail "per-pass exact-prediction count mismatch"
[[ "${PASS_CLASSIFICATION_EXACT}" == "20" ]] ||
    fail "per-pass classification count mismatch"

for line in \
    "WARMUP_LOGIT_EXACT=256" \
    "WARMUP_PREDICTION_EXACT=256" \
    "MEASURED_LOGIT_EXACT=5120" \
    "MEASURED_PREDICTION_EXACT=5120" \
    "MEASURED_CLASSIFICATION_CORRECT=4560" \
    "NO_FPGA_PROGRAMMING=1" \
    "NO_FPGA_RESET=1"
do
    require_exact "${LOG}" "${line}"
done

require_exact "${LOG}" \
    "STAGE2N_A12_PIPELINE_PERFORMANCE_BASELINE_V1_PASS warmup_passes=1 measured_passes=20 measured_samples=5120 logit_exact=5120 prediction_exact=5120"
require_exact "${LOG}" "TARGET_MAPPING_PASS=1"
require_exact "${LOG}" \
    "PRE_RUN: no open handle on /dev/dri/renderD129"
require_exact "${LOG}" \
    "POST_RUN: no open handle on /dev/dri/renderD129"

for pass_index in $(seq 1 20); do
    require_regex "${LOG}" \
        "^A12_MEASURED_PASS_COMPLETE=${pass_index}/20 "
done

require_exact "${A11_FINAL_STATUS}" \
    "STAGE2N_A11_FINAL_ACCEPTANCE_V1_PASS"
require_exact "${A11_FINAL_STATUS}" \
    "XCLBIN_UUID=${EXPECTED_UUID}"

STATIC_MODEL_CONFIG_US="$(metric "${LATEST_STATUS}" STATIC_MODEL_CONFIG_US)"
TOTAL_SAMPLE_LATENCY_MEAN_US="$(
    metric "${LATEST_STATUS}" TOTAL_SAMPLE_LATENCY_MEAN_US
)"
TOTAL_SAMPLE_LATENCY_P50_US="$(
    metric "${LATEST_STATUS}" TOTAL_SAMPLE_LATENCY_P50_US
)"
TOTAL_SAMPLE_LATENCY_P95_US="$(
    metric "${LATEST_STATUS}" TOTAL_SAMPLE_LATENCY_P95_US
)"
TOTAL_SAMPLE_LATENCY_P99_US="$(
    metric "${LATEST_STATUS}" TOTAL_SAMPLE_LATENCY_P99_US
)"
INPUT_PROGRAM_LATENCY_MEAN_US="$(
    metric "${LATEST_STATUS}" INPUT_PROGRAM_LATENCY_MEAN_US
)"
WAIT_VALID_LATENCY_MEAN_US="$(
    metric "${LATEST_STATUS}" WAIT_VALID_LATENCY_MEAN_US
)"
MEASURED_BATCH_TOTAL_US="$(
    metric "${LATEST_STATUS}" MEASURED_BATCH_TOTAL_US
)"
INSTRUMENTED_WALL_TOTAL_US="$(
    metric "${LATEST_STATUS}" INSTRUMENTED_WALL_TOTAL_US
)"
HOST_VISIBLE_THROUGHPUT="$(
    metric "${LATEST_STATUS}" HOST_VISIBLE_THROUGHPUT_SAMPLES_PER_SEC
)"
INSTRUMENTED_WALL_THROUGHPUT="$(
    metric "${LATEST_STATUS}" INSTRUMENTED_WALL_THROUGHPUT_SAMPLES_PER_SEC
)"
INPUT_PROGRAM_FRACTION="$(
    metric "${LATEST_STATUS}" INPUT_PROGRAM_FRACTION
)"
WAIT_VALID_FRACTION="$(
    metric "${LATEST_STATUS}" WAIT_VALID_FRACTION
)"
CONTROL_AND_RETIRE_FRACTION="$(
    metric "${LATEST_STATUS}" CONTROL_AND_RETIRE_FRACTION
)"

BOTTLENECK="$(
python3 - \
    "${INPUT_PROGRAM_FRACTION}" \
    "${WAIT_VALID_FRACTION}" \
    "${CONTROL_AND_RETIRE_FRACTION}" <<'PY'
import sys
values = {
    "INPUT_PROGRAM": float(sys.argv[1]),
    "WAIT_VALID": float(sys.argv[2]),
    "CONTROL_AND_RETIRE": float(sys.argv[3]),
}
print(max(values, key=values.get))
PY
)"

mkdir -p "${EVIDENCE_DIR}"

STATUS_BASENAME="$(basename "${LATEST_STATUS}")"
SAMPLE_CSV_BASENAME="$(basename "${SAMPLE_CSV}")"
PASS_CSV_BASENAME="$(basename "${PASS_CSV}")"
LOG_BASENAME="$(basename "${LOG}")"

copy_evidence "${LATEST_STATUS}" "${STATUS_BASENAME}"
copy_evidence "${SAMPLE_CSV}" "${SAMPLE_CSV_BASENAME}"
copy_evidence "${PASS_CSV}" "${PASS_CSV_BASENAME}"
copy_evidence "${LOG}" "${LOG_BASENAME}"
copy_evidence "${A11_FINAL_STATUS}" \
    "stage2n_a11_final_acceptance_v1_status.txt"

HOST_SHA256="$(sha256sum "${HOST_SOURCE}" | awk '{print $1}')"
RUNNER_V1_SHA256="$(sha256sum "${RUNNER_V1}" | awk '{print $1}')"
RUNNER_V2_SHA256="$(sha256sum "${RUNNER_V2}" | awk '{print $1}')"

cat > "${FINAL_STATUS}" <<EOF
STAGE2N_A12_FINAL_ACCEPTANCE_V1_PASS
GIT_BRANCH=${CURRENT_BRANCH}
GIT_HEAD=${CURRENT_HEAD}
CLAIM_BOUNDARY=host-visible AXI-Lite register-driven performance baseline; not pure RTL cycle latency
TARGET_INDEX=2
TARGET_BDF=0000:9b:00.1
TARGET_RENDER=/dev/dri/renderD129
XCLBIN_UUID=${EXPECTED_UUID}
KERNEL=${EXPECTED_KERNEL}
COMPUTE_UNIT=${EXPECTED_INSTANCE}
IP_NAME=${EXPECTED_IP_NAME}
WARMUP_PASSES=1
MEASURED_PASSES=20
MEASURED_SAMPLES=5120
STATIC_MODEL_CONFIG_US=${STATIC_MODEL_CONFIG_US}
TOTAL_SAMPLE_LATENCY_MEAN_US=${TOTAL_SAMPLE_LATENCY_MEAN_US}
TOTAL_SAMPLE_LATENCY_P50_US=${TOTAL_SAMPLE_LATENCY_P50_US}
TOTAL_SAMPLE_LATENCY_P95_US=${TOTAL_SAMPLE_LATENCY_P95_US}
TOTAL_SAMPLE_LATENCY_P99_US=${TOTAL_SAMPLE_LATENCY_P99_US}
INPUT_PROGRAM_LATENCY_MEAN_US=${INPUT_PROGRAM_LATENCY_MEAN_US}
WAIT_VALID_LATENCY_MEAN_US=${WAIT_VALID_LATENCY_MEAN_US}
MEASURED_BATCH_TOTAL_US=${MEASURED_BATCH_TOTAL_US}
INSTRUMENTED_WALL_TOTAL_US=${INSTRUMENTED_WALL_TOTAL_US}
HOST_VISIBLE_THROUGHPUT_SAMPLES_PER_SEC=${HOST_VISIBLE_THROUGHPUT}
INSTRUMENTED_WALL_THROUGHPUT_SAMPLES_PER_SEC=${INSTRUMENTED_WALL_THROUGHPUT}
INPUT_PROGRAM_FRACTION=${INPUT_PROGRAM_FRACTION}
WAIT_VALID_FRACTION=${WAIT_VALID_FRACTION}
CONTROL_AND_RETIRE_FRACTION=${CONTROL_AND_RETIRE_FRACTION}
DOMINANT_HOST_VISIBLE_COMPONENT=${BOTTLENECK}
MEASURED_LOGIT_EXACT=5120
MEASURED_PREDICTION_EXACT=5120
MEASURED_CLASSIFICATION_CORRECT=4560
BOARD_STATUS_FILE=${STATUS_BASENAME}
SAMPLE_CSV_FILE=${SAMPLE_CSV_BASENAME}
PASS_CSV_FILE=${PASS_CSV_BASENAME}
BOARD_LOG_FILE=${LOG_BASENAME}
HOST_SOURCE_SHA256=${HOST_SHA256}
RUNNER_V1_SHA256=${RUNNER_V1_SHA256}
RUNNER_V2_SHA256=${RUNNER_V2_SHA256}
FIREWALL_GOOD_AFTER_TEST=1
CU_IDLE_AFTER_TEST=1
NO_FPGA_ACCESS_DURING_COLLECTION=1
NO_FPGA_PROGRAMMING_OR_RESET_DURING_COLLECTION=1
EOF

(
    cd "${EVIDENCE_DIR}"

    find . \
        -maxdepth 1 \
        -type f \
        ! -name "$(basename "${MANIFEST}")" \
        -printf '%P\n' |
    sort |
    while IFS= read -r file; do
        sha256sum "${file}"
    done > "$(basename "${MANIFEST}")"
)

require_file "${FINAL_STATUS}"
require_file "${MANIFEST}"
require_exact "${FINAL_STATUS}" \
    "STAGE2N_A12_FINAL_ACCEPTANCE_V1_PASS"

(
    cd "${EVIDENCE_DIR}"
    sha256sum -c "$(basename "${MANIFEST}")"
) || fail "final A12 evidence manifest self-check failed"

echo "============================================================"
echo "STAGE2N_A12_FINAL_ACCEPTANCE_V1_PASS"
echo "GIT_BRANCH=${CURRENT_BRANCH}"
echo "GIT_HEAD=${CURRENT_HEAD}"
echo "TARGET_INDEX=2"
echo "TARGET_BDF=0000:9b:00.1"
echo "TARGET_RENDER=/dev/dri/renderD129"
echo "XCLBIN_UUID=${EXPECTED_UUID}"
echo "MEASURED_SAMPLES=5120"
echo "TOTAL_SAMPLE_LATENCY_MEAN_US=${TOTAL_SAMPLE_LATENCY_MEAN_US}"
echo "TOTAL_SAMPLE_LATENCY_P50_US=${TOTAL_SAMPLE_LATENCY_P50_US}"
echo "TOTAL_SAMPLE_LATENCY_P95_US=${TOTAL_SAMPLE_LATENCY_P95_US}"
echo "TOTAL_SAMPLE_LATENCY_P99_US=${TOTAL_SAMPLE_LATENCY_P99_US}"
echo "HOST_VISIBLE_THROUGHPUT_SAMPLES_PER_SEC=${HOST_VISIBLE_THROUGHPUT}"
echo "INSTRUMENTED_WALL_THROUGHPUT_SAMPLES_PER_SEC=${INSTRUMENTED_WALL_THROUGHPUT}"
echo "INPUT_PROGRAM_FRACTION=${INPUT_PROGRAM_FRACTION}"
echo "WAIT_VALID_FRACTION=${WAIT_VALID_FRACTION}"
echo "CONTROL_AND_RETIRE_FRACTION=${CONTROL_AND_RETIRE_FRACTION}"
echo "DOMINANT_HOST_VISIBLE_COMPONENT=${BOTTLENECK}"
echo "EVIDENCE_DIR=${EVIDENCE_DIR}"
echo "FINAL_STATUS=${FINAL_STATUS}"
echo "MANIFEST=${MANIFEST}"
echo "NO FPGA ACCESS WAS PERFORMED"
echo "============================================================"
