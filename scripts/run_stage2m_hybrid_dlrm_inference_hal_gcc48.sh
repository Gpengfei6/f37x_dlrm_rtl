#!/usr/bin/env bash
#
# Stage 2M-A: hybrid DLRM functional inference on the locked F37X card.
#
# Partition:
#   FPGA: bottom MLP 8 -> 16 -> 8
#   CPU : 4 embedding lookups + pairwise dot interaction -> 18 values
#   FPGA: top MLP 18 -> 32 -> 16 -> 1
#
# This script does NOT program or reset any FPGA.
#

set -o pipefail

REPO_ROOT="${1:-/home/chaosuan/gpf/gpf_f37x_dlrm/f37x_dlrm_rtl_stage2m}"
PASSES="${2:-3}"

cd "${REPO_ROOT}" || {
    echo "ERROR: cannot enter repository: ${REPO_ROOT}" >&2
    exit 2
}

if [[ -f /opt/xilinx/xrt/setup.sh ]]; then
    source /opt/xilinx/xrt/setup.sh >/dev/null 2>&1 || {
        echo "ERROR: failed to initialize XRT environment." >&2
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
EXPECTED_UUID="49dbac1d-8053-4bd3-9d1a-54f05a5414d9"
EXPECTED_CU="dlrm_f37x_rtl_kernel:dlrm_f37x_rtl_kernel_1"
EXPECTED_XCLBIN_SHA256="c3dd3264d8906c25523e1f02c2026f86d8b0e7b99b63c884446e8fc442a1f7bb"
EXPECTED_STAGE2L_COMMIT="39aa325"

XCLBIN="build/stage2h/hw/dlrm_f37x_rtl_kernel.xclbin"
GENERATOR="python/generate_stage2m_hybrid_dlrm_package.py"
SOURCE="host/stage2m_hybrid_dlrm_inference_hal.cpp"
MODEL_ASSET_DIR="models/stage2m"
PREBUILT_PACKAGE="${MODEL_ASSET_DIR}/stage2m_trained_hybrid_dlrm.f37xhd"
PREBUILT_MANIFEST="${MODEL_ASSET_DIR}/stage2m_trained_hybrid_dlrm_manifest.json"

EXPECTED_GENERATOR_SHA256="1337524c76ba9ba3fa7e6d876f0174a49f82a1a973f74139dc6e7e86c3bd8cc2"
EXPECTED_HOST_SHA256="834e0fe266e7ec3b82c08b32871788e4ba044c0871c6e620b3abc627e305daa6"
EXPECTED_PACKAGE_SHA256="b953289de8910f8402c4eefb79c516ab7d2468dba34fcc44532b9469cdcb2b3b"
EXPECTED_MANIFEST_SHA256="301bd88086bc42a0943af7b9b1867570a3e049b19e980e51ecc4390d69d8855d"

BUILD_DIR="build/stage2m"
RESULT_DIR="results/stage2m"
SERVER_RESULT_DIR="server_results"
BINARY="${BUILD_DIR}/stage2m_hybrid_dlrm_inference_hal"
PACKAGE="${BUILD_DIR}/stage2m_trained_hybrid_dlrm.f37xhd"
MANIFEST="${RESULT_DIR}/stage2m_trained_hybrid_dlrm_manifest.json"

mkdir -p "${BUILD_DIR}" "${RESULT_DIR}" "${SERVER_RESULT_DIR}"

STAMP="$(date +%Y%m%d_%H%M%S)"
CSV="${RESULT_DIR}/stage2m_hybrid_dlrm_${STAMP}.csv"
LOG="${SERVER_RESULT_DIR}/stage2m_hybrid_dlrm_${STAMP}.log"
STATUS="${RESULT_DIR}/stage2m_hybrid_dlrm_status.txt"

exec > >(tee "${LOG}") 2>&1

write_failure() {
    local reason="$1"
    {
        echo "STAGE2M_HYBRID_DLRM_FAILED"
        echo "TIME=$(date -Is)"
        echo "TARGET_INDEX=${TARGET_INDEX}"
        echo "TARGET_BDF=${TARGET_BDF}"
        echo "TARGET_RENDER=${TARGET_RENDER}"
        echo "PASSES=${PASSES}"
        echo "REASON=${reason}"
        echo "PACKAGE=${PACKAGE}"
        echo "MANIFEST=${MANIFEST}"
        echo "CSV=${CSV}"
        echo "LOG=${LOG}"
    } > "${STATUS}"
}

fail() {
    local reason="$1"
    write_failure "${reason}"
    echo "ERROR: ${reason}" >&2
    exit 10
}

extract_uuid() {
    awk '
        /Xclbin UUID/ {
            getline
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0)
            print
            exit
        }
    '
}

[[ "${PASSES}" =~ ^[0-9]+$ ]] ||
    fail "passes must be an integer"
(( PASSES >= 1 && PASSES <= 100 )) ||
    fail "passes must be in 1..100"

PYTHON_BIN=""
for CANDIDATE in python3 python; do
    if command -v "${CANDIDATE}" >/dev/null 2>&1; then
        if "${CANDIDATE}" -c 'import sys; assert sys.version_info[0] >= 3' \
            >/dev/null 2>&1
        then
            PYTHON_BIN="${CANDIDATE}"
            break
        fi
    fi
done
[[ -n "${PYTHON_BIN}" ]] ||
    fail "Python 3 was not found"
"${PYTHON_BIN}" -c 'import json' >/dev/null 2>&1 ||
    fail "Python JSON support is not available"

CURRENT_BRANCH="$(git symbolic-ref --short HEAD 2>/dev/null || true)"
CURRENT_HEAD="$(git rev-parse HEAD 2>/dev/null || true)"

[[ "${CURRENT_BRANCH}" == "work/stage2m-hybrid-dlrm" ]] ||
    fail "unexpected branch: ${CURRENT_BRANCH}"
git merge-base --is-ancestor "${EXPECTED_STAGE2L_COMMIT}" HEAD ||
    fail "Stage 2M branch does not descend from Stage 2L commit ${EXPECTED_STAGE2L_COMMIT}"

[[ -f "${GENERATOR}" ]] ||
    fail "hybrid package generator not found: ${GENERATOR}"
[[ -f "${SOURCE}" ]] ||
    fail "Stage 2M host source not found: ${SOURCE}"
[[ -s "${PREBUILT_PACKAGE}" ]] ||
    fail "prebuilt hybrid package not found: ${PREBUILT_PACKAGE}"
[[ -s "${PREBUILT_MANIFEST}" ]] ||
    fail "prebuilt hybrid manifest not found: ${PREBUILT_MANIFEST}"
[[ -s "${XCLBIN}" ]] ||
    fail "xclbin not found or empty: ${XCLBIN}"
[[ -n "${XILINX_XRT:-}" ]] ||
    fail "XILINX_XRT is not set"
[[ -f "${XILINX_XRT}/include/xrt.h" ]] ||
    fail "XRT xrt.h not found"
[[ -f "${XILINX_XRT}/include/experimental/xrt-next.h" ]] ||
    fail "XRT experimental/xrt-next.h not found"
[[ -e "${TARGET_RENDER}" ]] ||
    fail "render node not found: ${TARGET_RENDER}"

ACTUAL_XCLBIN_SHA256="$(sha256sum "${XCLBIN}" | awk '{print $1}')"
[[ "${ACTUAL_XCLBIN_SHA256}" == "${EXPECTED_XCLBIN_SHA256}" ]] ||
    fail "xclbin SHA256 mismatch: ${ACTUAL_XCLBIN_SHA256}"

echo "============================================================"
echo "Stage 2M-A F37X Hybrid DLRM Inference"
echo "TIME=$(date -Is)"
echo "REPO=$(pwd)"
echo "BRANCH=${CURRENT_BRANCH}"
echo "HEAD=${CURRENT_HEAD}"
echo "TARGET_INDEX=${TARGET_INDEX}"
echo "TARGET_BDF=${TARGET_BDF}"
echo "TARGET_RENDER=${TARGET_RENDER}"
echo "PASSES=${PASSES}"
echo "ACCESS=xclOpenContext+xclRegRead+xclRegWrite"
echo "PARTITION=FPGA_BOTTOM+CPU_EMBEDDING_INTERACTION+FPGA_TOP"
echo "NO XCLBIN PROGRAMMING OR DEVICE RESET IS PERFORMED"
echo "============================================================"

echo
echo "========== USE VERIFIED PREBUILT HYBRID PACKAGE =========="

GENERATOR_SHA256="$(sha256sum "${GENERATOR}" | awk '{print $1}')"
HOST_SHA256="$(sha256sum "${SOURCE}" | awk '{print $1}')"
PREBUILT_PACKAGE_SHA256="$(sha256sum "${PREBUILT_PACKAGE}" | awk '{print $1}')"
PREBUILT_MANIFEST_SHA256="$(sha256sum "${PREBUILT_MANIFEST}" | awk '{print $1}')"

[[ "${GENERATOR_SHA256}" == "${EXPECTED_GENERATOR_SHA256}" ]] ||
    fail "generator SHA256 mismatch: ${GENERATOR_SHA256}"
[[ "${HOST_SHA256}" == "${EXPECTED_HOST_SHA256}" ]] ||
    fail "host source SHA256 mismatch: ${HOST_SHA256}"
[[ "${PREBUILT_PACKAGE_SHA256}" == "${EXPECTED_PACKAGE_SHA256}" ]] ||
    fail "prebuilt package SHA256 mismatch: ${PREBUILT_PACKAGE_SHA256}"
[[ "${PREBUILT_MANIFEST_SHA256}" == "${EXPECTED_MANIFEST_SHA256}" ]] ||
    fail "prebuilt manifest SHA256 mismatch: ${PREBUILT_MANIFEST_SHA256}"

cp -f "${PREBUILT_PACKAGE}" "${PACKAGE}"
cp -f "${PREBUILT_MANIFEST}" "${MANIFEST}"

PACKAGE_SHA256="$(sha256sum "${PACKAGE}" | awk '{print $1}')"
MANIFEST_SHA256="$(sha256sum "${MANIFEST}" | awk '{print $1}')"

[[ "${PACKAGE_SHA256}" == "${EXPECTED_PACKAGE_SHA256}" ]] ||
    fail "copied package SHA256 mismatch: ${PACKAGE_SHA256}"
[[ "${MANIFEST_SHA256}" == "${EXPECTED_MANIFEST_SHA256}" ]] ||
    fail "copied manifest SHA256 mismatch: ${MANIFEST_SHA256}"

SAMPLE_COUNT="$("${PYTHON_BIN}" -c \
    'import json,sys; print(json.load(open(sys.argv[1]))["package"]["sample_count"])' \
    "${MANIFEST}")"
SOFTWARE_CORRECT_PER_PASS="$("${PYTHON_BIN}" -c \
    'import json,sys; print(json.load(open(sys.argv[1]))["quantization"]["quantized_test_correct"])' \
    "${MANIFEST}")"
QUANTIZED_TEST_ACCURACY="$("${PYTHON_BIN}" -c \
    'import json,sys; print("%.6f" % json.load(open(sys.argv[1]))["quantization"]["quantized_test_accuracy"])' \
    "${MANIFEST}")"
EMBEDDING_DIM="$("${PYTHON_BIN}" -c \
    'import json,sys; print(json.load(open(sys.argv[1]))["model"]["architecture"]["embedding_dim"])' \
    "${MANIFEST}")"

EXPECTED_ROWS=$((SAMPLE_COUNT * PASSES))
EXPECTED_FPGA_RUNS=$((EXPECTED_ROWS * 2))
EXPECTED_FPGA_OUTPUT_VALUES=$((EXPECTED_ROWS * (EMBEDDING_DIM + 1)))
EXPECTED_CPU_INTERACTIONS="${EXPECTED_ROWS}"
EXPECTED_CLASSIFICATION_CORRECT=$((SOFTWARE_CORRECT_PER_PASS * PASSES))

echo "MODEL_PACKAGE_SOURCE=verified_prebuilt_deterministic_asset"
echo "GENERATOR_SHA256=${GENERATOR_SHA256}"
echo "HOST_SHA256=${HOST_SHA256}"
echo "PACKAGE_SHA256=${PACKAGE_SHA256}"
echo "MANIFEST_SHA256=${MANIFEST_SHA256}"
echo "SAMPLE_COUNT=${SAMPLE_COUNT}"
echo "PASSES=${PASSES}"
echo "EXPECTED_ROWS=${EXPECTED_ROWS}"
echo "EXPECTED_FPGA_RUNS=${EXPECTED_FPGA_RUNS}"
echo "EXPECTED_FPGA_OUTPUT_VALUES=${EXPECTED_FPGA_OUTPUT_VALUES}"
echo "EXPECTED_CPU_INTERACTIONS=${EXPECTED_CPU_INTERACTIONS}"
echo "SOFTWARE_CORRECT_PER_PASS=${SOFTWARE_CORRECT_PER_PASS}"
echo "QUANTIZED_TEST_ACCURACY=${QUANTIZED_TEST_ACCURACY}"

echo
echo "========== LOW-LEVEL API SYMBOLS =========="

XRT_SYMBOL_LIBS=(
    "${XILINX_XRT}/lib/libxrt_core.so"
    "${XILINX_XRT}/lib/libxrt_coreutil.so"
)

for SYMBOL in \
    xclOpen \
    xclClose \
    xclOpenContext \
    xclCloseContext \
    xclIPName2Index \
    xclRegRead \
    xclRegWrite
do
    FOUND_LIB=""
    for LIB in "${XRT_SYMBOL_LIBS[@]}"; do
        [[ -e "${LIB}" ]] || continue
        if nm -D --defined-only "${LIB}" 2>/dev/null |
            awk '{print $NF}' |
            sed 's/@.*$//' |
            grep -Fx "${SYMBOL}" >/dev/null
        then
            FOUND_LIB="${LIB}"
            break
        fi
    done
    [[ -n "${FOUND_LIB}" ]] ||
        fail "required XRT symbol is missing: ${SYMBOL}"
    echo "FOUND_SYMBOL=${SYMBOL} LIBRARY=${FOUND_LIB}"
done

echo
echo "========== TARGET MAPPING =========="

SCAN_OUTPUT="$(xbutil scan 2>&1)" ||
    fail "xbutil scan failed"
echo "${SCAN_OUTPUT}"

echo "${SCAN_OUTPUT}" |
    grep -Eq "^[[:space:]]*\[${TARGET_INDEX}\][[:space:]]+${TARGET_BDF}[[:space:]]+${EXPECTED_PLATFORM}" ||
    fail "index ${TARGET_INDEX} is not mapped to ${TARGET_BDF}"

RENDER_SYSFS="$(
    readlink -f "/sys/class/drm/$(basename "${TARGET_RENDER}")/device" \
        2>/dev/null || true
)"
[[ "${RENDER_SYSFS}" == *"/${TARGET_BDF}" ]] ||
    fail "render node does not map to locked BDF: ${RENDER_SYSFS}"
echo "RENDER_SYSFS=${RENDER_SYSFS}"

echo
echo "========== PRE-RUN DEVICE STATE =========="

PRE_QUERY="$(xbutil query -d "${TARGET_BDF}" 2>&1)" ||
    fail "pre-run xbutil query failed"
echo "${PRE_QUERY}"

PRE_UUID="$(printf '%s\n' "${PRE_QUERY}" | extract_uuid)"
[[ "${PRE_UUID}" == "${EXPECTED_UUID}" ]] ||
    fail "loaded xclbin UUID mismatch: ${PRE_UUID}"
echo "${PRE_QUERY}" | grep -q "Level 0 : 0x0(GOOD)" ||
    fail "target firewall is not GOOD before Stage 2M"
echo "${PRE_QUERY}" | grep -q "${EXPECTED_CU}" ||
    fail "expected DLRM compute unit is not visible"
echo "${PRE_QUERY}" | grep -q "(IDLE)" ||
    fail "DLRM compute unit is not IDLE before Stage 2M"

FUSER_OUTPUT="$(fuser -v "${TARGET_RENDER}" 2>&1 || true)"
LSOF_OUTPUT="$(lsof "${TARGET_RENDER}" 2>&1 || true)"
[[ -z "${FUSER_OUTPUT//[[:space:]]/}" ]] ||
    fail "fuser reports an existing handle on ${TARGET_RENDER}"
[[ -z "${LSOF_OUTPUT//[[:space:]]/}" ]] ||
    fail "lsof reports an existing handle on ${TARGET_RENDER}"

echo "Target identity, UUID, firewall, CU, occupancy, and xclbin SHA256 checks passed."
echo "XCLBIN_SHA256=${ACTUAL_XCLBIN_SHA256}"

echo
echo "========== BUILD STAGE 2M HOST =========="

g++ --version | head -1
echo "Using GCC 4.8-compatible C++ mode: -std=gnu++11"

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
    -lxrt_coreutil \
    -pthread \
    -ldl \
    -o "${BINARY}" ||
    fail "Stage 2M host compilation failed"

ls -lh "${BINARY}"

echo
echo "========== VERIFY HYBRID PACKAGE IN HOST =========="

"${BINARY}" --verify-only "${PACKAGE}" ||
    fail "Stage 2M host package verification failed"

echo
echo "========== RUN STAGE 2M HYBRID DLRM =========="

set +e
"${BINARY}" "${PACKAGE}" "${CSV}" "${PASSES}"
HOST_RC=$?
set -e
[[ "${HOST_RC}" -eq 0 ]] ||
    fail "Stage 2M host executable returned ${HOST_RC}"

[[ -s "${CSV}" ]] ||
    fail "Stage 2M CSV was not created"

ACTUAL_ROWS="$(
    awk 'NR > 1 {count++} END {print count+0}' "${CSV}"
)"
PASS_ROWS="$(
    awk -F, 'NR > 1 && $NF == "PASS" {count++} END {print count+0}' "${CSV}"
)"
EXACT_ROWS="$(
    awk -F, 'NR > 1 && $5 == 1 && $6 == 1 && $7 == 1 {count++} END {print count+0}' "${CSV}"
)"
MISMATCH_ROWS="$(
    awk -F, 'NR > 1 && ($5 != 1 || $6 != 1 || $7 != 1 || $9 != $10 || $11 != $12 || $13 != $14) {count++} END {print count+0}' "${CSV}"
)"
CLASSIFICATION_CORRECT="$(
    awk -F, 'NR > 1 && $8 == 1 {count++} END {print count+0}' "${CSV}"
)"

[[ "${ACTUAL_ROWS}" -eq "${EXPECTED_ROWS}" ]] ||
    fail "CSV row mismatch: expected ${EXPECTED_ROWS}, got ${ACTUAL_ROWS}"
[[ "${PASS_ROWS}" -eq "${EXPECTED_ROWS}" ]] ||
    fail "CSV PASS mismatch: expected ${EXPECTED_ROWS}, got ${PASS_ROWS}"
[[ "${EXACT_ROWS}" -eq "${EXPECTED_ROWS}" ]] ||
    fail "CSV exact mismatch: expected ${EXPECTED_ROWS}, got ${EXACT_ROWS}"
[[ "${MISMATCH_ROWS}" -eq 0 ]] ||
    fail "CSV contains ${MISMATCH_ROWS} numerical mismatches"
[[ "${CLASSIFICATION_CORRECT}" -eq "${EXPECTED_CLASSIFICATION_CORRECT}" ]] ||
    fail "classification count mismatch: expected ${EXPECTED_CLASSIFICATION_CORRECT}, got ${CLASSIFICATION_CORRECT}"

grep -q "TOTAL_FPGA_NETWORK_RUNS=${EXPECTED_FPGA_RUNS}" "${LOG}" ||
    fail "FPGA network-run count marker missing"
grep -q "TOTAL_FPGA_OUTPUT_VALUES=${EXPECTED_FPGA_OUTPUT_VALUES}" "${LOG}" ||
    fail "FPGA output-value count marker missing"
grep -q "TOTAL_CPU_INTERACTIONS=${EXPECTED_CPU_INTERACTIONS}" "${LOG}" ||
    fail "CPU interaction count marker missing"

echo
echo "========== POST-RUN DEVICE STATE =========="

POST_QUERY="$(xbutil query -d "${TARGET_BDF}" 2>&1)" ||
    fail "post-run xbutil query failed"
echo "${POST_QUERY}"

POST_UUID="$(printf '%s\n' "${POST_QUERY}" | extract_uuid)"
[[ "${POST_UUID}" == "${EXPECTED_UUID}" ]] ||
    fail "xclbin UUID changed after Stage 2M: ${POST_UUID}"
echo "${POST_QUERY}" | grep -q "Level 0 : 0x0(GOOD)" ||
    fail "target firewall is not GOOD after Stage 2M"
echo "${POST_QUERY}" | grep -q "${EXPECTED_CU}" ||
    fail "DLRM compute unit disappeared after Stage 2M"
echo "${POST_QUERY}" | grep -q "(IDLE)" ||
    fail "DLRM compute unit is not IDLE after Stage 2M"

grep -q "STAGE2M_HYBRID_DLRM_PASS" "${LOG}" ||
    fail "Stage 2M PASS marker is missing from log"

{
    echo "STAGE2M_HYBRID_DLRM_PASS"
    echo "TIME=$(date -Is)"
    echo "TARGET_INDEX=${TARGET_INDEX}"
    echo "TARGET_BDF=${TARGET_BDF}"
    echo "TARGET_RENDER=${TARGET_RENDER}"
    echo "XCLBIN_UUID=${POST_UUID}"
    echo "XCLBIN=$(readlink -f "${XCLBIN}")"
    echo "XCLBIN_SHA256=${ACTUAL_XCLBIN_SHA256}"
    echo "IP_NAME=${EXPECTED_CU}"
    echo "IP_INDEX=0"
    echo "ACCESS=xclOpenContext+xclRegRead+xclRegWrite"
    echo "EXECUTION_PARTITION=FPGA_BOTTOM+CPU_EMBEDDING_INTERACTION+FPGA_TOP"
    echo "MODEL_PACKAGE=$(readlink -f "${PACKAGE}")"
    echo "MODEL_PACKAGE_SOURCE=verified_prebuilt_deterministic_asset"
    echo "MODEL_GENERATOR_SHA256=${GENERATOR_SHA256}"
    echo "MODEL_PACKAGE_SHA256=${PACKAGE_SHA256}"
    echo "MODEL_MANIFEST=$(readlink -f "${MANIFEST}")"
    echo "MODEL_MANIFEST_SHA256=${MANIFEST_SHA256}"
    echo "BOTTOM_ARCHITECTURE=8,16,8"
    echo "EMBEDDING_TABLES=64,80,96,128"
    echo "EMBEDDING_DIM=8"
    echo "INTERACTION_DIM=18"
    echo "TOP_ARCHITECTURE=18,32,16,1"
    echo "MODEL_SAMPLES=${SAMPLE_COUNT}"
    echo "PASSES=${PASSES}"
    echo "TOTAL_HYBRID_INFERENCES=${EXPECTED_ROWS}"
    echo "TOTAL_FPGA_NETWORK_RUNS=${EXPECTED_FPGA_RUNS}"
    echo "TOTAL_FPGA_OUTPUT_VALUES=${EXPECTED_FPGA_OUTPUT_VALUES}"
    echo "TOTAL_CPU_INTERACTIONS=${EXPECTED_CPU_INTERACTIONS}"
    echo "CSV_ROWS=${ACTUAL_ROWS}"
    echo "CSV_PASS_ROWS=${PASS_ROWS}"
    echo "CSV_EXACT_ROWS=${EXACT_ROWS}"
    echo "CSV_MISMATCH_ROWS=${MISMATCH_ROWS}"
    echo "CLASSIFICATION_CORRECT=${CLASSIFICATION_CORRECT}"
    echo "QUANTIZED_TEST_ACCURACY=${QUANTIZED_TEST_ACCURACY}"
    echo "HOST_SOURCE=$(readlink -f "${SOURCE}")"
    echo "HOST_SOURCE_SHA256=${HOST_SHA256}"
    echo "HOST_BINARY=$(readlink -f "${BINARY}")"
    echo "CSV=${CSV}"
    echo "LOG=${LOG}"
} > "${STATUS}"

echo
echo "============================================================"
echo "STAGE2M_HYBRID_DLRM_PASS"
echo "TARGET=${TARGET_BDF} (xbutil index ${TARGET_INDEX})"
echo "PARTITION=FPGA_BOTTOM+CPU_EMBEDDING_INTERACTION+FPGA_TOP"
echo "BOTTOM_ARCHITECTURE=8,16,8"
echo "INTERACTION_DIM=18"
echo "TOP_ARCHITECTURE=18,32,16,1"
echo "MODEL_SAMPLES=${SAMPLE_COUNT}"
echo "PASSES=${PASSES}"
echo "TOTAL_HYBRID_INFERENCES=${EXPECTED_ROWS}"
echo "TOTAL_FPGA_NETWORK_RUNS=${EXPECTED_FPGA_RUNS}"
echo "TOTAL_FPGA_OUTPUT_VALUES=${EXPECTED_FPGA_OUTPUT_VALUES}"
echo "TOTAL_CPU_INTERACTIONS=${EXPECTED_CPU_INTERACTIONS}"
echo "EXACT_MATCHES=${EXACT_ROWS}"
echo "CLASSIFICATION_CORRECT=${CLASSIFICATION_CORRECT}"
echo "QUANTIZED_TEST_ACCURACY=${QUANTIZED_TEST_ACCURACY}"
echo "CSV=${CSV}"
echo "STATUS=${STATUS}"
echo "LOG=${LOG}"
echo "============================================================"
