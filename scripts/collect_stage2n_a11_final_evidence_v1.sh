#!/usr/bin/env bash
#
# Collect and validate final Stage 2N-A11 board-regression evidence v1.
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

EXPECTED_BRANCH="work/stage2n-a11-real-model-batch-regression"
EXPECTED_UUID="f7a23117-5218-4fba-adb5-f093b596df03"
EXPECTED_KERNEL="dlrm_f37x_rtl_kernel_stage2n_a10_v2"
EXPECTED_INSTANCE="dlrm_a10_1"
EXPECTED_IP_NAME="${EXPECTED_KERNEL}:${EXPECTED_INSTANCE}"

BOARD_RESULT_DIR="${REPO_ROOT}/results/stage2n_a11_board_v1"
BOARD_LOG_DIR="${REPO_ROOT}/server_results/stage2n_a11"
ASSET_EVIDENCE_DIR="${REPO_ROOT}/docs/evidence/stage2n_a11_assets_v2"
A10_EVIDENCE_DIR="${REPO_ROOT}/docs/evidence/stage2n_a10_final_v4"

HOST_SOURCE="${REPO_ROOT}/host/stage2n_a11_real_model_batch_board_v1.cpp"
BOARD_RUNNER="${REPO_ROOT}/scripts/run_stage2n_a11_real_model_batch_board_v1.sh"
BOARD_DOC="${REPO_ROOT}/docs/STAGE2N_A11_REAL_MODEL_BATCH_BOARD_V1.md"

EVIDENCE_DIR="${REPO_ROOT}/docs/evidence/stage2n_a11_final_v1"
FINAL_STATUS="${EVIDENCE_DIR}/stage2n_a11_final_acceptance_v1_status.txt"
MANIFEST="${EVIDENCE_DIR}/stage2n_a11_final_evidence_manifest_v1.sha256"

fail()
{
    local reason="$*"
    mkdir -p "${EVIDENCE_DIR}"
    cat > "${FINAL_STATUS}" <<EOF
STAGE2N_A11_FINAL_ACCEPTANCE_V1_FAILED
REASON=${reason}
NO_FPGA_ACCESS=1
NO_FPGA_PROGRAMMING_OR_RESET=1
EOF
    echo "ERROR: ${reason}" >&2
    exit 50
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
    "${BOARD_RUNNER}" \
    "${BOARD_DOC}" \
    "${ASSET_EVIDENCE_DIR}/stage2n_a11_pipeline_batch_asset_v2_manifest.sha256" \
    "${ASSET_EVIDENCE_DIR}/stage2n_a11_real_model_batch_v2_status.txt" \
    "${ASSET_EVIDENCE_DIR}/stage2n_a11_real_model_batch_v2_manifest.json" \
    "${ASSET_EVIDENCE_DIR}/stage2n_a11_real_model_batch_v2_samples.csv" \
    "${A10_EVIDENCE_DIR}/stage2n_a10_final_acceptance_v4_status.txt" \
    "${A10_EVIDENCE_DIR}/stage2n_a10_final_evidence_manifest_v4.sha256"
do
    require_file "${file}"
done

BOARD_STATUS="$(
    find "${BOARD_RESULT_DIR}" \
        -maxdepth 1 \
        -type f \
        -name 'stage2n_a11_real_model_batch_board_v1_status_*.txt' \
        -printf '%T@ %p\n' |
    sort -nr |
    head -n 1 |
    cut -d' ' -f2-
)"
[[ -n "${BOARD_STATUS}" ]] ||
    fail "no Stage 2N-A11 board status file found"
require_file "${BOARD_STATUS}"

require_exact "${BOARD_STATUS}" \
    "STAGE2N_A11_REAL_MODEL_BATCH_BOARD_V1_PASS"
require_exact "${BOARD_STATUS}" "GIT_BRANCH=${EXPECTED_BRANCH}"
require_exact "${BOARD_STATUS}" "TARGET_INDEX=2"
require_exact "${BOARD_STATUS}" "TARGET_BDF=0000:9b:00.1"
require_exact "${BOARD_STATUS}" "TARGET_RENDER=/dev/dri/renderD129"
require_exact "${BOARD_STATUS}" "AUTHORIZATION_CONFIRMED=1"
require_exact "${BOARD_STATUS}" "XCLBIN_UUID=${EXPECTED_UUID}"
require_exact "${BOARD_STATUS}" "KERNEL=${EXPECTED_KERNEL}"
require_exact "${BOARD_STATUS}" "COMPUTE_UNIT=${EXPECTED_INSTANCE}"
require_exact "${BOARD_STATUS}" "IP_NAME=${EXPECTED_IP_NAME}"
require_exact "${BOARD_STATUS}" \
    "ASSET=build/stage2n_a11/assets_v2/stage2n_a11_real_model_batch_v2.f37xpb"
require_exact "${BOARD_STATUS}" "SAMPLE_COUNT=256"
require_exact "${BOARD_STATUS}" "PIPELINE_START_COMMANDS=256"
require_exact "${BOARD_STATUS}" "FPGA_LOGIT_EXACT=256"
require_exact "${BOARD_STATUS}" "FPGA_PREDICTION_EXACT=256"
require_exact "${BOARD_STATUS}" "FPGA_RESULT_INDEX_EXACT=256"
require_exact "${BOARD_STATUS}" "FPGA_RESULT_TAG_EXACT=256"
require_exact "${BOARD_STATUS}" "FPGA_BOTTOM_COUNT_EXACT=256"
require_exact "${BOARD_STATUS}" "FPGA_INTERACTION_COUNT_EXACT=256"
require_exact "${BOARD_STATUS}" "FPGA_CLASSIFICATION_CORRECT=228"
require_exact "${BOARD_STATUS}" \
    "FPGA_CLASSIFICATION_ACCURACY=0.890625"
require_exact "${BOARD_STATUS}" "FINAL_DESCRIPTOR_TAG=4"
require_exact "${BOARD_STATUS}" "FIREWALL_GOOD_AFTER_TEST=1"
require_exact "${BOARD_STATUS}" "CU_IDLE_AFTER_TEST=1"
require_exact "${BOARD_STATUS}" "NO_FPGA_PROGRAMMING=1"
require_exact "${BOARD_STATUS}" "NO_FPGA_RESET=1"
require_exact "${BOARD_STATUS}" "NO_AUTOMATIC_ROLLBACK=1"
require_exact "${BOARD_STATUS}" "NO_OTHER_DEVICE_ACCESS=1"
require_regex "${BOARD_STATUS}" '^BATCH_ELAPSED_US=[1-9][0-9]*$'
require_regex "${BOARD_STATUS}" '^GIT_HEAD=[0-9a-f]{40}$'

BOARD_GIT_HEAD="$(
    grep '^GIT_HEAD=' "${BOARD_STATUS}" |
    head -n 1 |
    cut -d= -f2
)"
git cat-file -e "${BOARD_GIT_HEAD}^{commit}" 2>/dev/null ||
    fail "board-run GIT_HEAD is not present in repository history"

CSV_REL="$(
    grep '^CSV=' "${BOARD_STATUS}" |
    head -n 1 |
    cut -d= -f2-
)"
LOG_REL="$(
    grep '^LOG=' "${BOARD_STATUS}" |
    head -n 1 |
    cut -d= -f2-
)"
[[ -n "${CSV_REL}" ]] || fail "CSV path missing from board status"
[[ -n "${LOG_REL}" ]] || fail "LOG path missing from board status"

BOARD_CSV="${REPO_ROOT}/${CSV_REL}"
BOARD_LOG="${REPO_ROOT}/${LOG_REL}"
require_file "${BOARD_CSV}"
require_file "${BOARD_LOG}"

EXPECTED_CSV_HEADER='sample_id,label,expected_logit,fpga_logit,expected_prediction,fpga_prediction,logit_exact,prediction_exact,classification_correct,result_index,result_tag,bottom_count,interaction_count'
ACTUAL_CSV_HEADER="$(head -n 1 "${BOARD_CSV}" | tr -d '\r')"
[[ "${ACTUAL_CSV_HEADER}" == "${EXPECTED_CSV_HEADER}" ]] ||
    fail "board CSV header mismatch"

CSV_ROWS="$(
    awk 'END {print NR-1}' "${BOARD_CSV}"
)"
CSV_SAMPLE_ID_EXACT="$(
    awk -F, '
        NR > 1 {
            expected = NR - 2
            if ($1 == expected) count++
        }
        END {print count+0}
    ' "${BOARD_CSV}"
)"
CSV_LOGIT_EXACT="$(
    awk -F, 'NR > 1 && $7 == 1 {count++} END {print count+0}' \
        "${BOARD_CSV}"
)"
CSV_PREDICTION_EXACT="$(
    awk -F, 'NR > 1 && $8 == 1 {count++} END {print count+0}' \
        "${BOARD_CSV}"
)"
CSV_CLASSIFICATION_CORRECT="$(
    awk -F, 'NR > 1 && $9 == 1 {count++} END {print count+0}' \
        "${BOARD_CSV}"
)"
CSV_RESULT_INDEX_EXACT="$(
    awk -F, 'NR > 1 && $10 == 0 {count++} END {print count+0}' \
        "${BOARD_CSV}"
)"
CSV_RESULT_TAG_EXACT="$(
    awk -F, 'NR > 1 && $11 == 4 {count++} END {print count+0}' \
        "${BOARD_CSV}"
)"
CSV_BOTTOM_COUNT_EXACT="$(
    awk -F, 'NR > 1 && $12 == 8 {count++} END {print count+0}' \
        "${BOARD_CSV}"
)"
CSV_INTERACTION_COUNT_EXACT="$(
    awk -F, 'NR > 1 && $13 == 18 {count++} END {print count+0}' \
        "${BOARD_CSV}"
)"

[[ "${CSV_ROWS}" == "256" ]] ||
    fail "board CSV row count mismatch: ${CSV_ROWS}"
[[ "${CSV_SAMPLE_ID_EXACT}" == "256" ]] ||
    fail "board CSV sample-ID sequence mismatch"
[[ "${CSV_LOGIT_EXACT}" == "256" ]] ||
    fail "board CSV exact-logit count mismatch"
[[ "${CSV_PREDICTION_EXACT}" == "256" ]] ||
    fail "board CSV exact-prediction count mismatch"
[[ "${CSV_CLASSIFICATION_CORRECT}" == "228" ]] ||
    fail "board CSV classification count mismatch"
[[ "${CSV_RESULT_INDEX_EXACT}" == "256" ]] ||
    fail "board CSV result-index count mismatch"
[[ "${CSV_RESULT_TAG_EXACT}" == "256" ]] ||
    fail "board CSV result-tag count mismatch"
[[ "${CSV_BOTTOM_COUNT_EXACT}" == "256" ]] ||
    fail "board CSV bottom-count check mismatch"
[[ "${CSV_INTERACTION_COUNT_EXACT}" == "256" ]] ||
    fail "board CSV interaction-count check mismatch"

for line in \
    "A11_ASSET_PARSE_PASS=1" \
    "A11_ASSET_SAMPLE_COUNT=256" \
    "A11_ASSET_DESCRIPTOR_COUNT=5" \
    "A11_ASSET_WEIGHT_COUNT=1360" \
    "A11_ASSET_BIAS_COUNT=73" \
    "A11_ASSET_REFERENCE_CORRECT=228" \
    "HAL_DEVICE_INDEX=2" \
    "HAL_TARGET_BDF=0000:9b:00.1" \
    "HAL_XCLBIN_UUID=${EXPECTED_UUID}" \
    "HAL_IP_NAME=${EXPECTED_IP_NAME}" \
    "HAL_IP_INDEX=0" \
    "HAL_EXCLUSIVE_CONTEXT_OPEN=1" \
    "MLP_WINDOW_VERSION=0x00024701" \
    "INTERACTION_WINDOW_VERSION=0x00024e02" \
    "PIPELINE_WINDOW_VERSION=0x00024e11" \
    "A11_STATIC_MODEL_CONFIGURATION_PASS=1" \
    "PIPELINE_START_COMMANDS=256" \
    "FPGA_LOGIT_EXACT=256" \
    "FPGA_PREDICTION_EXACT=256" \
    "FPGA_RESULT_INDEX_EXACT=256" \
    "FPGA_RESULT_TAG_EXACT=256" \
    "FPGA_BOTTOM_COUNT_EXACT=256" \
    "FPGA_INTERACTION_COUNT_EXACT=256" \
    "FPGA_CLASSIFICATION_CORRECT=228" \
    "FPGA_CLASSIFICATION_ACCURACY=0.890625" \
    "NO_FPGA_PROGRAMMING=1" \
    "NO_FPGA_RESET=1"
do
    require_exact "${BOARD_LOG}" "${line}"
done

require_exact "${BOARD_LOG}" \
    "STAGE2N_A11_REAL_MODEL_BATCH_BOARD_V1_PASS samples=256 logits=256 predictions=256 correct=228 accuracy=0.890625 tag=4"
require_exact "${BOARD_LOG}" "TARGET_MAPPING_PASS=1"
require_exact "${BOARD_LOG}" \
    "PRE_RUN: no open handle on /dev/dri/renderD129"
require_exact "${BOARD_LOG}" \
    "POST_RUN: no open handle on /dev/dri/renderD129"
require_regex "${BOARD_LOG}" '^BATCH_ELAPSED_US=[1-9][0-9]*$'

for progress in 32 64 96 128 160 192 224 256; do
    require_regex "${BOARD_LOG}" \
        "^A11_BATCH_PROGRESS=${progress}/256 "
done

(
    cd "${ASSET_EVIDENCE_DIR}"
    sha256sum -c \
        stage2n_a11_pipeline_batch_asset_v2_manifest.sha256
) || fail "Stage 2N-A11 asset evidence manifest verification failed"

(
    cd "${A10_EVIDENCE_DIR}"
    sha256sum -c \
        stage2n_a10_final_evidence_manifest_v4.sha256
) || fail "Stage 2N-A10 evidence manifest verification failed"

require_exact \
    "${ASSET_EVIDENCE_DIR}/stage2n_a11_real_model_batch_v2_status.txt" \
    "STAGE2N_A11_PIPELINE_BATCH_ASSET_V2_PASS"
require_exact \
    "${A10_EVIDENCE_DIR}/stage2n_a10_final_acceptance_v4_status.txt" \
    "STAGE2N_A10_FINAL_ACCEPTANCE_V4_PASS"

mkdir -p "${EVIDENCE_DIR}"

BOARD_STATUS_BASENAME="$(basename "${BOARD_STATUS}")"
BOARD_CSV_BASENAME="$(basename "${BOARD_CSV}")"
BOARD_LOG_BASENAME="$(basename "${BOARD_LOG}")"

copy_evidence "${BOARD_STATUS}" "${BOARD_STATUS_BASENAME}"
copy_evidence "${BOARD_CSV}" "${BOARD_CSV_BASENAME}"
copy_evidence "${BOARD_LOG}" "${BOARD_LOG_BASENAME}"

copy_evidence \
    "${ASSET_EVIDENCE_DIR}/stage2n_a11_real_model_batch_v2_status.txt" \
    "stage2n_a11_real_model_batch_v2_status.txt"
copy_evidence \
    "${ASSET_EVIDENCE_DIR}/stage2n_a11_real_model_batch_v2_manifest.json" \
    "stage2n_a11_real_model_batch_v2_manifest.json"
copy_evidence \
    "${ASSET_EVIDENCE_DIR}/stage2n_a11_pipeline_batch_asset_v2_manifest.sha256" \
    "stage2n_a11_pipeline_batch_asset_v2_manifest.sha256"
copy_evidence \
    "${A10_EVIDENCE_DIR}/stage2n_a10_final_acceptance_v4_status.txt" \
    "stage2n_a10_final_acceptance_v4_status.txt"

BATCH_ELAPSED_US="$(
    grep '^BATCH_ELAPSED_US=' "${BOARD_STATUS}" |
    head -n 1 |
    cut -d= -f2
)"

HOST_SHA256="$(sha256sum "${HOST_SOURCE}" | awk '{print $1}')"
RUNNER_SHA256="$(sha256sum "${BOARD_RUNNER}" | awk '{print $1}')"
DOC_SHA256="$(sha256sum "${BOARD_DOC}" | awk '{print $1}')"

cat > "${FINAL_STATUS}" <<EOF
STAGE2N_A11_FINAL_ACCEPTANCE_V1_PASS
GIT_BRANCH=${CURRENT_BRANCH}
GIT_HEAD=${CURRENT_HEAD}
BOARD_RUN_GIT_HEAD=${BOARD_GIT_HEAD}
CLAIM_BOUNDARY=deterministic synthetic Stage 2M trained-model regression; not real Criteo evidence
TARGET_INDEX=2
TARGET_BDF=0000:9b:00.1
TARGET_RENDER=/dev/dri/renderD129
XCLBIN_UUID=${EXPECTED_UUID}
KERNEL=${EXPECTED_KERNEL}
COMPUTE_UNIT=${EXPECTED_INSTANCE}
IP_NAME=${EXPECTED_IP_NAME}
ASSET_FORMAT=F37XPB1
ASSET_VERSION=2
MODEL_SHAPE=8x16x8_interact18_32x16x1
SAMPLE_COUNT=256
DESCRIPTOR_COUNT=5
WEIGHT_COUNT=1360
BIAS_COUNT=73
INTERACTION_SHIFT=11
PIPELINE_START_COMMANDS=256
FPGA_LOGIT_EXACT=256
FPGA_PREDICTION_EXACT=256
FPGA_RESULT_INDEX_EXACT=256
FPGA_RESULT_TAG_EXACT=256
FPGA_BOTTOM_COUNT_EXACT=256
FPGA_INTERACTION_COUNT_EXACT=256
FPGA_CLASSIFICATION_CORRECT=228
FPGA_CLASSIFICATION_ACCURACY=0.890625
FINAL_DESCRIPTOR_TAG=4
BATCH_ELAPSED_US=${BATCH_ELAPSED_US}
BOARD_STATUS_FILE=${BOARD_STATUS_BASENAME}
BOARD_CSV_FILE=${BOARD_CSV_BASENAME}
BOARD_LOG_FILE=${BOARD_LOG_BASENAME}
HOST_SOURCE_SHA256=${HOST_SHA256}
BOARD_RUNNER_SHA256=${RUNNER_SHA256}
BOARD_DOC_SHA256=${DOC_SHA256}
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
    "STAGE2N_A11_FINAL_ACCEPTANCE_V1_PASS"

(
    cd "${EVIDENCE_DIR}"
    sha256sum -c "$(basename "${MANIFEST}")"
) || fail "final A11 evidence manifest self-check failed"

echo "============================================================"
echo "STAGE2N_A11_FINAL_ACCEPTANCE_V1_PASS"
echo "GIT_BRANCH=${CURRENT_BRANCH}"
echo "GIT_HEAD=${CURRENT_HEAD}"
echo "BOARD_RUN_GIT_HEAD=${BOARD_GIT_HEAD}"
echo "TARGET_INDEX=2"
echo "TARGET_BDF=0000:9b:00.1"
echo "TARGET_RENDER=/dev/dri/renderD129"
echo "XCLBIN_UUID=${EXPECTED_UUID}"
echo "MODEL_SHAPE=8x16x8_interact18_32x16x1"
echo "SAMPLE_COUNT=256"
echo "FPGA_LOGIT_EXACT=256"
echo "FPGA_PREDICTION_EXACT=256"
echo "FPGA_CLASSIFICATION_CORRECT=228"
echo "FPGA_CLASSIFICATION_ACCURACY=0.890625"
echo "FINAL_DESCRIPTOR_TAG=4"
echo "BATCH_ELAPSED_US=${BATCH_ELAPSED_US}"
echo "EVIDENCE_DIR=${EVIDENCE_DIR}"
echo "FINAL_STATUS=${FINAL_STATUS}"
echo "MANIFEST=${MANIFEST}"
echo "NO FPGA ACCESS WAS PERFORMED"
echo "============================================================"
