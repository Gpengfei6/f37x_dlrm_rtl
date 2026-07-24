#!/usr/bin/env bash
#
# Stage 2J HAL path: compile and run the low-level register smoke test.
#
# Locked target:
#   xbutil index : 2
#   BDF          : 0000:9b:00.1
#   render node  : /dev/dri/renderD129
#
# This script does NOT program or reset any FPGA.
#

set -o pipefail

REPO_ROOT="${1:-/home/chaosuan/gpf/gpf_f37x_dlrm/f37x_dlrm_rtl_stage2e}"
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

XCLBIN="build/stage2h/hw/dlrm_f37x_rtl_kernel.xclbin"
SOURCE="host/stage2j_dlrm_f37x_smoke_hal.cpp"
BUILD_DIR="build/stage2j"
BINARY="${BUILD_DIR}/stage2j_dlrm_f37x_smoke_hal"
RESULT_DIR="results/stage2j"
SERVER_RESULT_DIR="server_results"

mkdir -p "${BUILD_DIR}" "${RESULT_DIR}" "${SERVER_RESULT_DIR}"

STAMP="$(date +%Y%m%d_%H%M%S)"
LOG="${SERVER_RESULT_DIR}/stage2j_hal_board_smoke_${STAMP}.log"
STATUS="${RESULT_DIR}/stage2j_hal_board_smoke_status.txt"

exec > >(tee "${LOG}") 2>&1

write_failure() {
    local reason="$1"
    {
        echo "STAGE2J_HAL_BOARD_SMOKE_FAILED"
        echo "TIME=$(date -Is)"
        echo "TARGET_INDEX=${TARGET_INDEX}"
        echo "TARGET_BDF=${TARGET_BDF}"
        echo "TARGET_RENDER=${TARGET_RENDER}"
        echo "REASON=${reason}"
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

echo "============================================================"
echo "Stage 2J F37X DLRM Low-Level HAL Board Smoke"
echo "TIME=$(date -Is)"
echo "REPO=$(pwd)"
echo "BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || echo UNKNOWN)"
echo "HEAD=$(git rev-parse HEAD 2>/dev/null || echo UNKNOWN)"
echo "TARGET_INDEX=${TARGET_INDEX}"
echo "TARGET_BDF=${TARGET_BDF}"
echo "TARGET_RENDER=${TARGET_RENDER}"
echo "ACCESS=xclOpenContext+xclRegRead+xclRegWrite"
echo "NO XCLBIN PROGRAMMING OR DEVICE RESET IS PERFORMED"
echo "============================================================"

command -v xbutil >/dev/null 2>&1 || fail "xbutil not found"
command -v g++ >/dev/null 2>&1 || fail "g++ not found"
[[ -n "${XILINX_XRT:-}" ]] || fail "XILINX_XRT is not set"
[[ -f "${SOURCE}" ]] || fail "HAL host source not found: ${SOURCE}"
[[ -s "${XCLBIN}" ]] || fail "xclbin not found or empty: ${XCLBIN}"
[[ -f "${XILINX_XRT}/include/xrt.h" ]] ||
    fail "XRT xrt.h not found"
[[ -f "${XILINX_XRT}/include/experimental/xrt-next.h" ]] ||
    fail "XRT experimental/xrt-next.h not found"
[[ -e "${TARGET_RENDER}" ]] ||
    fail "render node not found: ${TARGET_RENDER}"

ACTUAL_XCLBIN_SHA256="$(sha256sum "${XCLBIN}" | awk '{print $1}')"
[[ "${ACTUAL_XCLBIN_SHA256}" == "${EXPECTED_XCLBIN_SHA256}" ]] ||
    fail "xclbin SHA256 mismatch: ${ACTUAL_XCLBIN_SHA256}"

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

RENDER_SYSFS="$(readlink -f "/sys/class/drm/$(basename "${TARGET_RENDER}")/device" 2>/dev/null || true)"
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
    fail "target firewall is not GOOD before HAL test"
echo "${PRE_QUERY}" | grep -q "${EXPECTED_CU}" ||
    fail "expected DLRM compute unit is not visible"

FUSER_OUTPUT="$(fuser -v "${TARGET_RENDER}" 2>&1 || true)"
LSOF_OUTPUT="$(lsof "${TARGET_RENDER}" 2>&1 || true)"
[[ -z "${FUSER_OUTPUT//[[:space:]]/}" ]] ||
    fail "fuser reports an existing handle on ${TARGET_RENDER}"
[[ -z "${LSOF_OUTPUT//[[:space:]]/}" ]] ||
    fail "lsof reports an existing handle on ${TARGET_RENDER}"

echo "Target identity, UUID, firewall, CU, occupancy, and xclbin SHA256 checks passed."
echo "XCLBIN_SHA256=${ACTUAL_XCLBIN_SHA256}"

echo
echo "========== BUILD HAL HOST =========="
g++ --version | head -1
echo "Using GCC 4.8-compatible C++ mode: -std=gnu++11"

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
  -lxrt_coreutil \
  -pthread \
  -ldl \
  -o "${BINARY}"
BUILD_RC=$?
set -e

[[ "${BUILD_RC}" -eq 0 ]] ||
    fail "HAL host compilation returned ${BUILD_RC}"

ls -lh "${BINARY}"

echo
echo "========== RUN HAL HOST =========="
set +e
"${BINARY}"
HOST_RC=$?
set -e

[[ "${HOST_RC}" -eq 0 ]] ||
    fail "HAL host executable returned ${HOST_RC}"

echo
echo "========== POST-RUN DEVICE STATE =========="
POST_QUERY="$(xbutil query -d "${TARGET_BDF}" 2>&1)" ||
    fail "post-run xbutil query failed"
echo "${POST_QUERY}"

POST_UUID="$(printf '%s\n' "${POST_QUERY}" | extract_uuid)"
[[ "${POST_UUID}" == "${EXPECTED_UUID}" ]] ||
    fail "xclbin UUID changed after HAL test: ${POST_UUID}"
echo "${POST_QUERY}" | grep -q "Level 0 : 0x0(GOOD)" ||
    fail "target firewall is not GOOD after HAL test"
echo "${POST_QUERY}" | grep -q "${EXPECTED_CU}" ||
    fail "DLRM compute unit disappeared after HAL test"
echo "${POST_QUERY}" | grep -q "(IDLE)" ||
    fail "DLRM compute unit is not IDLE after HAL test"

grep -q "STAGE2J_HAL_BOARD_SMOKE_PASS result=19" "${LOG}" ||
    fail "HAL PASS marker missing from log"

{
    echo "STAGE2J_HAL_BOARD_SMOKE_PASS"
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
    echo "EXPECTED_RESULT=19"
    echo "HOST_SOURCE=$(readlink -f "${SOURCE}")"
    echo "HOST_BINARY=$(readlink -f "${BINARY}")"
    echo "LOG=${LOG}"
} > "${STATUS}"

echo
echo "============================================================"
echo "STAGE2J_HAL_BOARD_SMOKE_PASS"
echo "TARGET=${TARGET_BDF} (xbutil index ${TARGET_INDEX})"
echo "IP_INDEX=0"
echo "EXPECTED_RESULT=19"
echo "STATUS=${STATUS}"
echo "LOG=${LOG}"
echo "============================================================"
