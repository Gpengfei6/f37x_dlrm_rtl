#!/usr/bin/env bash
#
# Stage 2N-A9 v3 protected F37X board smoke for the automatic pipeline.
#
# v3 changes:
#   - Keep the whitespace-tolerant xclbin metadata parsing from v2.
#   - Compile host v2, which allows initial idle cleanup before model
#     configuration and checks start-ready only after configuration.
#
# Authorized target only:
#   xbutil index : 2
#   BDF          : 0000:9b:00.1
#   render node  : /dev/dri/renderD129
#
# Safety contract:
#   - Never touches indices 0, 1, or 3.
#   - Never resets the FPGA.
#   - Never performs automatic rollback.
#   - Refuses to program an unrecognized or active source image.
#   - Requires exact interactive confirmations before programming.
#   - Uses only AXI4-Lite register access after programming.

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

EXPECTED_BRANCH="work/stage2n-a9-board-smoke"
REQUIRED_ANCESTOR="72df18bdd811d2031ab5446476370580c995ac50"

EXPECTED_NEW_UUID="5d4ac982-14e3-40fb-afaa-f04ba82dce61"
EXPECTED_NEW_KERNEL="dlrm_f37x_rtl_kernel_stage2n_a7"
EXPECTED_NEW_INSTANCE="dlrm_a7_1"
EXPECTED_NEW_CU="${EXPECTED_NEW_KERNEL}:${EXPECTED_NEW_INSTANCE}"
EXPECTED_NEW_SIZE="43550638"

ALLOWED_SOURCE_A4_UUID="fb8f400f-7064-4583-9a18-6cf87a465fad"
ALLOWED_SOURCE_A4_CU="dlrm_f37x_rtl_kernel_stage2n_a2:dlrm_a2_1"

ALLOWED_SOURCE_M_UUID="49dbac1d-8053-4bd3-9d1a-54f05a5414d9"
ALLOWED_SOURCE_M_CU="dlrm_f37x_rtl_kernel:dlrm_f37x_rtl_kernel_1"

ALLOWED_SOURCE_RSNB_UUID="676f4655-cab4-4ebe-a030-6412c5e1b392"
ALLOWED_SOURCE_RSNB_CU="rsnb_compact_mem_tile4_v15a:rsnb_compact_mem_tile4_v15a_1"

XCLBIN="build/stage2n_a8/link_v3/hw/dlrm_f37x_rtl_kernel_stage2n_a7.xclbin"
XCLBIN_INFO="results/stage2n_a8/link_v3/dlrm_f37x_rtl_kernel_stage2n_a7.xclbin.info"
A8_STATUS="results/stage2n_a8/link_v3/stage2n_a8_f37x_link_v3_status.txt"
A8_ACCEPT_STATUS="results/stage2n_a8/link_v3/stage2n_a8_f37x_link_artifact_accept_v1_status.txt"

SOURCE="host/stage2n_a9_pipeline_board_smoke_v2.cpp"
BUILD_DIR="build/stage2n_a9_board_v3"
RESULT_DIR="results/stage2n_a9_board_v3"
SERVER_RESULT_DIR="server_results/stage2n_a9"

mkdir -p "${BUILD_DIR}" "${RESULT_DIR}" "${SERVER_RESULT_DIR}"

STAMP="$(date +%Y%m%d_%H%M%S)"
BINARY="${BUILD_DIR}/stage2n_a9_pipeline_board_smoke_v3_${STAMP}"
LOG="${SERVER_RESULT_DIR}/stage2n_a9_pipeline_board_smoke_v3_${STAMP}.log"
STATUS="${RESULT_DIR}/stage2n_a9_pipeline_board_smoke_v2_status_${STAMP}.txt"

exec > >(tee "${LOG}") 2>&1

write_failure()
{
    local reason="$1"

    {
        echo "STAGE2N_A9_PIPELINE_BOARD_SMOKE_V3_FAILED"
        echo "TIME=$(date -Is)"
        echo "TARGET_INDEX=${TARGET_INDEX}"
        echo "TARGET_BDF=${TARGET_BDF}"
        echo "TARGET_RENDER=${TARGET_RENDER}"
        echo "REASON=${reason}"
        echo "XCLBIN=$(readlink -f "${XCLBIN}" 2>/dev/null || echo "${XCLBIN}")"
        echo "LOG=${LOG}"
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
    echo "No FPGA reset or automatic rollback was attempted." >&2
    exit 10
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

extract_cu_line()
{
    grep -E '^CU\[' | head -1
}

extract_dma_lines()
{
    grep -E '^Chan\[0\]\.(h2c|c2h):'
}

extract_hbm0_line()
{
    grep -E '^\[[[:space:]]*0\][[:space:]]+HBM\[0\]' | head -1
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

    echo "RENDER_SYSFS=${render_sysfs}"
}

query_target()
{
    xbutil query -d "${TARGET_BDF}" 2>&1
}

require_hbm0_empty()
{
    local query_text="$1"
    local stage="$2"
    local hbm_line

    hbm_line="$(printf '%s\n' "${query_text}" | extract_hbm0_line)"

    [[ -n "${hbm_line}" ]] ||
        fail "${stage}: HBM[0] status line is missing"

    echo "${hbm_line}" |
        grep -Eq 'HBM\[0\].*0 Byte[[:space:]]+0[[:space:]]*$' ||
        fail "${stage}: HBM[0] reports memory use or active BOs"

    echo "${stage}: HBM[0] usage is 0 Byte and BO count is 0"
}

activity_guard()
{
    local expected_uuid="$1"
    local expected_cu="$2"
    local wait_seconds="${3:-30}"

    local query1 query2
    local uuid1 uuid2
    local cu1 cu2
    local dma1 dma2

    echo
    echo "========== SOURCE ACTIVITY GUARD: SAMPLE 1 =========="
    date -Is

    query1="$(query_target)" ||
        fail "activity guard sample 1 query failed"

    uuid1="$(printf '%s\n' "${query1}" | extract_uuid)"
    cu1="$(printf '%s\n' "${query1}" | extract_cu_line)"
    dma1="$(printf '%s\n' "${query1}" | extract_dma_lines)"

    echo "SAMPLE1_UUID=${uuid1}"
    echo "${cu1}"
    echo "${dma1}"

    echo "${query1}" | grep -q "Level 0 : 0x0(GOOD)" ||
        fail "activity guard sample 1 firewall is not GOOD"

    [[ "${uuid1}" == "${expected_uuid}" ]] ||
        fail "activity guard sample 1 UUID changed"

    echo "${cu1}" | grep -Fq "${expected_cu}" ||
        fail "activity guard sample 1 CU mismatch"

    echo "${cu1}" | grep -Fq "(IDLE)" ||
        fail "activity guard sample 1 CU is not IDLE"

    require_empty_render "ACTIVITY_GUARD_SAMPLE1"
    require_hbm0_empty "${query1}" "ACTIVITY_GUARD_SAMPLE1"

    echo "Waiting ${wait_seconds} seconds; no programming occurs."
    sleep "${wait_seconds}"

    echo
    echo "========== SOURCE ACTIVITY GUARD: SAMPLE 2 =========="
    date -Is

    query2="$(query_target)" ||
        fail "activity guard sample 2 query failed"

    uuid2="$(printf '%s\n' "${query2}" | extract_uuid)"
    cu2="$(printf '%s\n' "${query2}" | extract_cu_line)"
    dma2="$(printf '%s\n' "${query2}" | extract_dma_lines)"

    echo "SAMPLE2_UUID=${uuid2}"
    echo "${cu2}"
    echo "${dma2}"

    echo "${query2}" | grep -q "Level 0 : 0x0(GOOD)" ||
        fail "activity guard sample 2 firewall is not GOOD"

    [[ "${uuid2}" == "${expected_uuid}" ]] ||
        fail "activity guard sample 2 UUID changed"

    echo "${cu2}" | grep -Fq "${expected_cu}" ||
        fail "activity guard sample 2 CU mismatch"

    echo "${cu2}" | grep -Fq "(IDLE)" ||
        fail "activity guard sample 2 CU is not IDLE"

    require_empty_render "ACTIVITY_GUARD_SAMPLE2"
    require_hbm0_empty "${query2}" "ACTIVITY_GUARD_SAMPLE2"

    [[ "${uuid1}" == "${uuid2}" ]] ||
        fail "source UUID changed during activity guard"

    [[ "${cu1}" == "${cu2}" ]] ||
        fail "CU status or usage changed during activity guard"

    [[ "${dma1}" == "${dma2}" ]] ||
        fail "DMA counters changed during activity guard"

    GUARD_CU_LINE="${cu2}"
    GUARD_DMA_LINES="${dma2}"

    echo "ACTIVITY_GUARD_UUID_UNCHANGED=1"
    echo "ACTIVITY_GUARD_CU_COUNTER_UNCHANGED=1"
    echo "ACTIVITY_GUARD_DMA_COUNTERS_UNCHANGED=1"
    echo "ACTIVITY_GUARD_PASS=1"
}

echo "============================================================"
echo "Stage 2N-A9 v3 Protected F37X Automatic Pipeline Board Smoke"
echo "TIME=$(date -Is)"
echo "REPO=$(pwd)"
echo "BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || echo UNKNOWN)"
echo "HEAD=$(git rev-parse HEAD 2>/dev/null || echo UNKNOWN)"
echo
echo "AUTHORIZED TARGET ONLY:"
echo "  xbutil index : ${TARGET_INDEX}"
echo "  BDF          : ${TARGET_BDF}"
echo "  render node  : ${TARGET_RENDER}"
echo
echo "NEW IMAGE:"
echo "  UUID         : ${EXPECTED_NEW_UUID}"
echo "  CU           : ${EXPECTED_NEW_CU}"
echo
echo "This script never resets the FPGA."
echo "It never accesses indices 0, 1, or 3."
echo "============================================================"

for tool in xbutil g++ nm sha256sum awk grep fuser lsof stat; do
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

[[ -f "${SOURCE}" ]] ||
    fail "host source not found: ${SOURCE}"

[[ -s "${XCLBIN}" ]] ||
    fail "A8 xclbin not found or empty: ${XCLBIN}"

[[ -s "${XCLBIN_INFO}" ]] ||
    fail "A8 xclbin info not found: ${XCLBIN_INFO}"

[[ -s "${A8_STATUS}" ]] ||
    fail "A8 link status not found: ${A8_STATUS}"

[[ -s "${A8_ACCEPT_STATUS}" ]] ||
    fail "A8 final acceptance status not found: ${A8_ACCEPT_STATUS}"

grep -q '^STAGE2N_A8_F37X_LINK_V3_PASS$' "${A8_STATUS}" ||
    fail "A8 link PASS marker is missing"

grep -q '^STAGE2N_A8_F37X_LINK_ARTIFACT_ACCEPT_V1_PASS$' \
    "${A8_ACCEPT_STATUS}" ||
    fail "A8 final acceptance PASS marker is missing"

CURRENT_BRANCH="$(git symbolic-ref --short HEAD 2>/dev/null || true)"
[[ "${CURRENT_BRANCH}" == "${EXPECTED_BRANCH}" ]] ||
    fail "unexpected branch: ${CURRENT_BRANCH}"

git merge-base --is-ancestor "${REQUIRED_ANCESTOR}" HEAD ||
    fail "current branch does not descend from ${REQUIRED_ANCESTOR}"

echo
echo "========== A8 XCLBIN IDENTITY =========="

ACTUAL_NEW_SIZE="$(stat -c '%s' "${XCLBIN}")"
[[ "${ACTUAL_NEW_SIZE}" == "${EXPECTED_NEW_SIZE}" ]] ||
    fail "xclbin size mismatch: ${ACTUAL_NEW_SIZE}"

ACTUAL_NEW_SHA256="$(
    sha256sum "${XCLBIN}" | awk '{print $1}'
)"

[[ "${ACTUAL_NEW_SHA256}" =~ ^[0-9a-f]{64}$ ]] ||
    fail "computed xclbin SHA256 has invalid format"

ACTUAL_METADATA_UUID="$(
    sed -n \
        's/^[[:space:]]*UUID (xclbin):[[:space:]]*//p' \
        "${XCLBIN_INFO}" |
    head -n 1 |
    tr -d '\r'
)"

[[ -n "${ACTUAL_METADATA_UUID}" ]] ||
    fail "xclbin UUID is missing from metadata"

[[ "${ACTUAL_METADATA_UUID}" == "${EXPECTED_NEW_UUID}" ]] ||
    fail "xclbin UUID metadata mismatch: ${ACTUAL_METADATA_UUID}"

ACTUAL_METADATA_KERNEL="$(
    sed -n \
        -e 's/^[[:space:]]*Kernel:[[:space:]]*//p' \
        -e 's/^[[:space:]]*Kernels:[[:space:]]*//p' \
        "${XCLBIN_INFO}" |
    head -n 1 |
    tr -d '\r'
)"

[[ -n "${ACTUAL_METADATA_KERNEL}" ]] ||
    fail "kernel name is missing from xclbin metadata"

[[ "${ACTUAL_METADATA_KERNEL}" == "${EXPECTED_NEW_KERNEL}" ]] ||
    fail "kernel metadata mismatch: ${ACTUAL_METADATA_KERNEL}"

ACTUAL_METADATA_INSTANCE="$(
    sed -n \
        's/^[[:space:]]*Instance:[[:space:]]*//p' \
        "${XCLBIN_INFO}" |
    head -n 1 |
    awk '{print $1}' |
    tr -d '\r'
)"

[[ -n "${ACTUAL_METADATA_INSTANCE}" ]] ||
    fail "compute-unit instance is missing from xclbin metadata"

[[ "${ACTUAL_METADATA_INSTANCE}" == "${EXPECTED_NEW_INSTANCE}" ]] ||
    fail "compute-unit metadata mismatch: ${ACTUAL_METADATA_INSTANCE}"

echo "XCLBIN_SIZE_BYTES=${ACTUAL_NEW_SIZE}"
echo "XCLBIN_SHA256=${ACTUAL_NEW_SHA256}"
echo "XCLBIN_UUID=${ACTUAL_METADATA_UUID}"
echo "XCLBIN_KERNEL=${ACTUAL_METADATA_KERNEL}"
echo "XCLBIN_INSTANCE=${ACTUAL_METADATA_INSTANCE}"
echo "XCLBIN_CU=${EXPECTED_NEW_CU}"

echo
echo "========== LOW-LEVEL XRT SYMBOLS =========="

XRT_SYMBOL_LIBS=(
    "${XILINX_XRT}/lib/libxrt_core.so"
    "${XILINX_XRT}/lib/libxrt_coreutil.so"
)

for symbol in \
    xclOpen \
    xclClose \
    xclOpenContext \
    xclCloseContext \
    xclIPName2Index \
    xclRegRead \
    xclRegWrite
do
    found_library=""

    for library in "${XRT_SYMBOL_LIBS[@]}"; do
        [[ -e "${library}" ]] || continue

        if nm -D --defined-only "${library}" 2>/dev/null |
            awk '{print $NF}' |
            sed 's/@.*$//' |
            grep -Fx "${symbol}" >/dev/null
        then
            found_library="${library}"
            break
        fi
    done

    [[ -n "${found_library}" ]] ||
        fail "required XRT symbol is missing: ${symbol}"

    echo "FOUND_SYMBOL=${symbol} LIBRARY=${found_library}"
done

echo
echo "========== BUILD A9 HOST BEFORE PROGRAMMING =========="

g++ --version | head -1
echo "Using GCC 4.8-compatible mode: -std=gnu++11"

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
    fail "A9 host compilation returned ${BUILD_RESULT}"

ls -lh "${BINARY}"

echo
echo "========== TARGET MAPPING =========="
check_target_mapping

echo
echo "========== PRE-PROGRAM DEVICE STATE =========="

PRE_QUERY="$(query_target)" ||
    fail "pre-program xbutil query failed"
echo "${PRE_QUERY}"

echo "${PRE_QUERY}" | grep -q "Level 0 : 0x0(GOOD)" ||
    fail "target firewall is not GOOD before programming"

CURRENT_UUID="$(printf '%s\n' "${PRE_QUERY}" | extract_uuid)"
[[ -n "${CURRENT_UUID}" ]] ||
    fail "could not extract current target UUID"

echo "CURRENT_UUID=${CURRENT_UUID}"

require_empty_render "PRE_PROGRAM"

PROGRAMMED_NOW=0
PROGRAM_START="NOT_RUN"
PROGRAM_END="NOT_RUN"

if [[ "${CURRENT_UUID}" == "${EXPECTED_NEW_UUID}" ]]; then
    echo "The Stage 2N-A9 image is already loaded; programming is skipped."

    echo "${PRE_QUERY}" | grep -Fq "${EXPECTED_NEW_CU}" ||
        fail "new UUID is loaded but the expected CU is missing"

    echo "${PRE_QUERY}" | grep -Fq "(IDLE)" ||
        fail "new A7 CU is not IDLE before smoke"
else
    SOURCE_KIND=""
    SOURCE_CU=""

    if [[ "${CURRENT_UUID}" == "${ALLOWED_SOURCE_A4_UUID}" ]]; then
        SOURCE_KIND="verified Stage 2N-A4 A2 image"
        SOURCE_CU="${ALLOWED_SOURCE_A4_CU}"
    elif [[ "${CURRENT_UUID}" == "${ALLOWED_SOURCE_M_UUID}" ]]; then
        SOURCE_KIND="verified Stage 2M image"
        SOURCE_CU="${ALLOWED_SOURCE_M_CU}"
    elif [[ "${CURRENT_UUID}" == "${ALLOWED_SOURCE_RSNB_UUID}" ]]; then
        SOURCE_KIND="authorized idle RSNB image"
        SOURCE_CU="${ALLOWED_SOURCE_RSNB_CU}"
    else
        fail "unrecognized current UUID ${CURRENT_UUID}; refusing to program"
    fi

    echo "${PRE_QUERY}" | grep -Fq "${SOURCE_CU}" ||
        fail "recognized source UUID has an unexpected CU"

    echo "${PRE_QUERY}" | grep -Fq "(IDLE)" ||
        fail "recognized source CU is not IDLE"

    require_hbm0_empty "${PRE_QUERY}" "PRE_PROGRAM"

    echo
    echo "SOURCE_KIND=${SOURCE_KIND}"
    echo "SOURCE_UUID=${CURRENT_UUID}"
    echo "SOURCE_CU=${SOURCE_CU}"
    echo
    echo "Running a fresh 30-second read-only activity guard."

    activity_guard "${CURRENT_UUID}" "${SOURCE_CU}" 30

    echo
    echo "Programming will replace ONLY the verified image on:"
    echo "  index ${TARGET_INDEX}"
    echo "  BDF ${TARGET_BDF}"
    echo "No reset or automatic rollback will be performed."
    echo

    read -r -p \
        "Type exactly PROGRAM_STAGE2N_A9_INDEX2_9B to continue: " \
        CONFIRM_1

    [[ "${CONFIRM_1}" == "PROGRAM_STAGE2N_A9_INDEX2_9B" ]] ||
        fail "programming confirmation did not match"

    read -r -p \
        "Type the target BDF exactly (${TARGET_BDF}): " \
        CONFIRM_2

    [[ "${CONFIRM_2}" == "${TARGET_BDF}" ]] ||
        fail "target BDF confirmation did not match"

    read -r -p \
        "Type the current source UUID exactly (${CURRENT_UUID}): " \
        CONFIRM_3

    [[ "${CONFIRM_3}" == "${CURRENT_UUID}" ]] ||
        fail "source UUID confirmation did not match"

    echo
    echo "========== FINAL PRE-PROGRAM RECHECK =========="

    check_target_mapping
    require_empty_render "FINAL_PRE_PROGRAM"

    FINAL_QUERY="$(query_target)" ||
        fail "final pre-program query failed"

    echo "${FINAL_QUERY}" | grep -q "Level 0 : 0x0(GOOD)" ||
        fail "final pre-program firewall is not GOOD"

    FINAL_UUID="$(printf '%s\n' "${FINAL_QUERY}" | extract_uuid)"
    FINAL_CU_LINE="$(printf '%s\n' "${FINAL_QUERY}" | extract_cu_line)"
    FINAL_DMA_LINES="$(printf '%s\n' "${FINAL_QUERY}" | extract_dma_lines)"

    [[ "${FINAL_UUID}" == "${CURRENT_UUID}" ]] ||
        fail "target UUID changed before programming"

    echo "${FINAL_CU_LINE}" | grep -Fq "${SOURCE_CU}" ||
        fail "source CU changed before programming"

    echo "${FINAL_CU_LINE}" | grep -Fq "(IDLE)" ||
        fail "source CU is not IDLE immediately before programming"

    [[ "${FINAL_CU_LINE}" == "${GUARD_CU_LINE}" ]] ||
        fail "CU usage or state changed after activity guard"

    [[ "${FINAL_DMA_LINES}" == "${GUARD_DMA_LINES}" ]] ||
        fail "DMA counters changed after activity guard"

    require_hbm0_empty "${FINAL_QUERY}" "FINAL_PRE_PROGRAM"

    echo "Final checks passed."
    echo "Programming ONLY ${TARGET_BDF}."

    echo
    echo "========== PROGRAM INDEX 2 / BDF 0000:9b:00.1 =========="

    PROGRAM_START="$(date -Is)"

    set +e
    xbutil program -d "${TARGET_BDF}" -p "${XCLBIN}"
    PROGRAM_RESULT="$?"
    set -e

    PROGRAM_END="$(date -Is)"

    [[ "${PROGRAM_RESULT}" -eq 0 ]] ||
        fail "xbutil program returned ${PROGRAM_RESULT}"

    PROGRAMMED_NOW=1
    sleep 3
fi

echo
echo "========== POST-PROGRAM VERIFICATION =========="

POST_PROGRAM_QUERY="$(query_target)" ||
    fail "post-program xbutil query failed"
echo "${POST_PROGRAM_QUERY}"

echo "${POST_PROGRAM_QUERY}" | grep -q "Level 0 : 0x0(GOOD)" ||
    fail "target firewall is not GOOD after programming"

POST_PROGRAM_UUID="$(
    printf '%s\n' "${POST_PROGRAM_QUERY}" | extract_uuid
)"

[[ "${POST_PROGRAM_UUID}" == "${EXPECTED_NEW_UUID}" ]] ||
    fail "post-program UUID mismatch: ${POST_PROGRAM_UUID}"

echo "${POST_PROGRAM_QUERY}" | grep -Fq "${EXPECTED_NEW_CU}" ||
    fail "new A7 CU is not visible after programming"

echo "${POST_PROGRAM_QUERY}" | grep -Fq "(IDLE)" ||
    fail "new A7 CU is not IDLE after programming"

require_empty_render "POST_PROGRAM"

echo
echo "========== RUN A7 AUTOMATIC PIPELINE BOARD SMOKE =========="

set +e
"${BINARY}"
HOST_RESULT="$?"
set -e

[[ "${HOST_RESULT}" -eq 0 ]] ||
    fail "A9 host returned ${HOST_RESULT}"

grep -qF \
    "STAGE2N_A9_PIPELINE_BOARD_SMOKE_V2_PASS runs=2 final=-60 bottom=8 interaction=18" \
    "${LOG}" ||
    fail "A9 host PASS marker is missing"

echo
echo "========== POST-RUN DEVICE STATE =========="

POST_RUN_QUERY="$(query_target)" ||
    fail "post-run xbutil query failed"
echo "${POST_RUN_QUERY}"

echo "${POST_RUN_QUERY}" | grep -q "Level 0 : 0x0(GOOD)" ||
    fail "target firewall is not GOOD after board smoke"

POST_RUN_UUID="$(printf '%s\n' "${POST_RUN_QUERY}" | extract_uuid)"

[[ "${POST_RUN_UUID}" == "${EXPECTED_NEW_UUID}" ]] ||
    fail "xclbin UUID changed after board smoke"

echo "${POST_RUN_QUERY}" | grep -Fq "${EXPECTED_NEW_CU}" ||
    fail "A7 CU disappeared after board smoke"

echo "${POST_RUN_QUERY}" | grep -Fq "(IDLE)" ||
    fail "A7 CU is not IDLE after board smoke"

{
    echo "STAGE2N_A9_PIPELINE_BOARD_SMOKE_V3_PASS"
    echo "TIME=$(date -Is)"
    echo "TARGET_INDEX=${TARGET_INDEX}"
    echo "TARGET_BDF=${TARGET_BDF}"
    echo "TARGET_RENDER=${TARGET_RENDER}"
    echo "PROGRAMMED_NOW=${PROGRAMMED_NOW}"
    echo "PROGRAM_START=${PROGRAM_START}"
    echo "PROGRAM_END=${PROGRAM_END}"
    echo "PREVIOUS_UUID=${CURRENT_UUID}"
    echo "XCLBIN_UUID=${POST_RUN_UUID}"
    echo "KERNEL=${EXPECTED_NEW_KERNEL}"
    echo "COMPUTE_UNIT=${EXPECTED_NEW_INSTANCE}"
    echo "IP_NAME=${EXPECTED_NEW_CU}"
    echo "IP_INDEX=0"
    echo "KERNEL_FREQUENCY_MHZ=100"
    echo "XCLBIN=$(readlink -f "${XCLBIN}")"
    echo "XCLBIN_SIZE_BYTES=${ACTUAL_NEW_SIZE}"
    echo "XCLBIN_SHA256=${ACTUAL_NEW_SHA256}"
    echo "ACCESS=xclOpenContext+xclRegRead+xclRegWrite"
    echo "PIPELINE_RUNS=2"
    echo "PIPELINE_RESULT=-60"
    echo "BOTTOM_OUTPUTS=8"
    echo "INTERACTION_OUTPUTS=18"
    echo "FINAL_BACKPRESSURE_READS=12"
    echo "FIREWALL_GOOD_AFTER_TEST=1"
    echo "CU_IDLE_AFTER_TEST=1"
    echo "NO_FPGA_RESET=1"
    echo "NO_AUTOMATIC_ROLLBACK=1"
    echo "NO_OTHER_DEVICE_ACCESS=1"
    echo "HOST_SOURCE=$(readlink -f "${SOURCE}")"
    echo "HOST_BINARY=$(readlink -f "${BINARY}")"
    echo "LOG=${LOG}"
} > "${STATUS}"

echo
echo "============================================================"
echo "STAGE2N_A9_PIPELINE_BOARD_SMOKE_V3_PASS"
echo "TARGET=${TARGET_BDF} (xbutil index ${TARGET_INDEX})"
echo "UUID=${POST_RUN_UUID}"
echo "CU=${EXPECTED_NEW_CU}"
echo "PIPELINE_RUNS=2"
echo "PIPELINE_RESULT=-60"
echo "BOTTOM_OUTPUTS=8"
echo "INTERACTION_OUTPUTS=18"
echo "STATUS=${STATUS}"
echo "LOG=${LOG}"
echo "NO FPGA RESET WAS PERFORMED"
echo "NO OTHER DEVICE WAS ACCESSED"
echo "============================================================"
