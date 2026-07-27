#!/usr/bin/env bash
#
# Stage 2N-A4 host-only recovery verification v2.
#
# This script:
#   - locks index 2 / BDF 0000:9b:00.1 / renderD129;
#   - requires the Stage 2N-A4 xclbin UUID and CU already loaded;
#   - compiles and runs the v3 host smoke;
#   - performs no FPGA programming and no FPGA reset.
#

set -o pipefail

REPO_ROOT="${1:-/home/chaosuan/gpf/gpf_f37x_dlrm/f37x_dlrm_rtl_stage2n}"

cd "${REPO_ROOT}" || {
    echo "ERROR: cannot enter repository: ${REPO_ROOT}" >&2
    exit 2
}

# XRT's setup script is not safe under `set -u` on this server.
# Source it before enabling strict nounset/error handling.
if [[ -f /opt/xilinx/xrt/setup.sh ]]; then
    source /opt/xilinx/xrt/setup.sh >/dev/null 2>&1
    XRT_SETUP_RC=$?
    if [[ "${XRT_SETUP_RC}" -ne 0 ]]; then
        echo "ERROR: XRT setup returned ${XRT_SETUP_RC}" >&2
        exit 3
    fi
else
    echo "ERROR: /opt/xilinx/xrt/setup.sh not found" >&2
    exit 3
fi

set -Eeuo pipefail

TARGET_INDEX="2"
TARGET_BDF="0000:9b:00.1"
TARGET_RENDER="/dev/dri/renderD129"
EXPECTED_PLATFORM="inspur_f37x_xdma_201920_3"
EXPECTED_UUID="fb8f400f-7064-4583-9a18-6cf87a465fad"
EXPECTED_CU="dlrm_f37x_rtl_kernel_stage2n_a2:dlrm_a2_1"

SOURCE="host/stage2n_a4_integrated_smoke_v3.cpp"
BUILD_DIR="build/stage2n_a4_host_only_v2"
RESULT_DIR="results/stage2n_a4_host_only_v2"
SERVER_RESULT_DIR="server_results"

mkdir -p "${BUILD_DIR}" "${RESULT_DIR}" "${SERVER_RESULT_DIR}"

STAMP="$(date +%Y%m%d_%H%M%S)"
BINARY="${BUILD_DIR}/stage2n_a4_integrated_smoke_v3_${STAMP}"
LOG="${SERVER_RESULT_DIR}/stage2n_a4_host_only_v2_${STAMP}.log"
STATUS="${RESULT_DIR}/stage2n_a4_host_only_v2_status_${STAMP}.txt"

exec > >(tee "${LOG}") 2>&1

fail()
{
    local reason="$*"
    {
        echo "STAGE2N_A4_HOST_ONLY_V2_FAILED"
        echo "TIME=$(date -Is)"
        echo "REASON=${reason}"
        echo "TARGET_INDEX=${TARGET_INDEX}"
        echo "TARGET_BDF=${TARGET_BDF}"
        echo "TARGET_RENDER=${TARGET_RENDER}"
        echo "LOG=${LOG}"
        echo "NO_FPGA_PROGRAMMING=1"
        echo "NO_FPGA_RESET=1"
    } > "${STATUS}"

    echo "ERROR: ${reason}" >&2
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

query_target()
{
    xbutil query -d "${TARGET_BDF}" 2>&1
}

check_no_handle()
{
    local stage="$1"
    local fuser_output
    local lsof_output

    fuser_output="$(fuser -v "${TARGET_RENDER}" 2>&1 || true)"
    lsof_output="$(lsof "${TARGET_RENDER}" 2>&1 || true)"

    [[ -z "${fuser_output//[[:space:]]/}" ]] ||
        fail "${stage}: fuser detected a render handle"

    [[ -z "${lsof_output//[[:space:]]/}" ]] ||
        fail "${stage}: lsof detected a render handle"

    echo "${stage}: no open handle on ${TARGET_RENDER}"
}

echo "============================================================"
echo "Stage 2N-A4 host-only recovery verification v2"
echo "TIME=$(date -Is)"
echo "REPO=$(pwd)"
echo "TARGET_INDEX=${TARGET_INDEX}"
echo "TARGET_BDF=${TARGET_BDF}"
echo "TARGET_RENDER=${TARGET_RENDER}"
echo "EXPECTED_UUID=${EXPECTED_UUID}"
echo "EXPECTED_CU=${EXPECTED_CU}"
echo "NO FPGA PROGRAMMING"
echo "NO FPGA RESET"
echo "============================================================"

for tool in xbutil g++ fuser lsof grep awk; do
    command -v "${tool}" >/dev/null 2>&1 ||
        fail "required tool not found: ${tool}"
done

[[ -f "${SOURCE}" ]] ||
    fail "host source is missing: ${SOURCE}"

echo
echo "========== BUILD HOST V3 =========="

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

ls -lh "${BINARY}"

echo
echo "========== TARGET MAPPING =========="

SCAN="$(xbutil scan 2>&1)" ||
    fail "xbutil scan failed"
echo "${SCAN}"

echo "${SCAN}" |
    grep -Eq "^[[:space:]]*\[${TARGET_INDEX}\][[:space:]]+${TARGET_BDF}[[:space:]]+${EXPECTED_PLATFORM}" ||
    fail "locked index/BDF mapping mismatch"

RENDER_SYSFS="$(
    readlink -f "/sys/class/drm/$(basename "${TARGET_RENDER}")/device"
)"
[[ "${RENDER_SYSFS}" == *"/${TARGET_BDF}" ]] ||
    fail "render node mapping mismatch: ${RENDER_SYSFS}"

echo "RENDER_SYSFS=${RENDER_SYSFS}"

check_no_handle "PRE_RUN"

echo
echo "========== PRE-RUN DEVICE STATE =========="

PRE_QUERY="$(query_target)" ||
    fail "pre-run query failed"
echo "${PRE_QUERY}"

echo "${PRE_QUERY}" | grep -q "Level 0 : 0x0(GOOD)" ||
    fail "firewall is not GOOD before host run"

PRE_UUID="$(printf '%s\n' "${PRE_QUERY}" | extract_uuid)"
[[ "${PRE_UUID}" == "${EXPECTED_UUID}" ]] ||
    fail "unexpected loaded UUID: ${PRE_UUID}"

echo "${PRE_QUERY}" | grep -Fq "${EXPECTED_CU}" ||
    fail "expected Stage 2N-A4 CU is not visible"

echo "${PRE_QUERY}" | grep -Fq "(IDLE)" ||
    fail "Stage 2N-A4 CU is not IDLE before host run"

echo
echo "========== RUN HOST V3 =========="

set +e
"${BINARY}"
HOST_RC=$?
set -e

[[ "${HOST_RC}" -eq 0 ]] ||
    fail "host v3 returned ${HOST_RC}"

grep -qF \
    "STAGE2N_A4_INTEGRATED_SMOKE_V3_PASS mlp_result=19 interaction_outputs=18" \
    "${LOG}" ||
    fail "host v3 PASS marker is missing"

echo
echo "========== POST-RUN DEVICE STATE =========="

POST_QUERY="$(query_target)" ||
    fail "post-run query failed"
echo "${POST_QUERY}"

echo "${POST_QUERY}" | grep -q "Level 0 : 0x0(GOOD)" ||
    fail "firewall is not GOOD after host run"

POST_UUID="$(printf '%s\n' "${POST_QUERY}" | extract_uuid)"
[[ "${POST_UUID}" == "${EXPECTED_UUID}" ]] ||
    fail "UUID changed after host run: ${POST_UUID}"

echo "${POST_QUERY}" | grep -Fq "${EXPECTED_CU}" ||
    fail "Stage 2N-A4 CU disappeared after host run"

echo "${POST_QUERY}" | grep -Fq "(IDLE)" ||
    fail "Stage 2N-A4 CU is not IDLE after host run"

check_no_handle "POST_RUN"

{
    echo "STAGE2N_A4_HOST_ONLY_V2_PASS"
    echo "TIME=$(date -Is)"
    echo "TARGET_INDEX=${TARGET_INDEX}"
    echo "TARGET_BDF=${TARGET_BDF}"
    echo "TARGET_RENDER=${TARGET_RENDER}"
    echo "XCLBIN_UUID=${POST_UUID}"
    echo "COMPUTE_UNIT=${EXPECTED_CU}"
    echo "LEGACY_MLP_RESULT=19"
    echo "INTERACTION_OUTPUTS=18"
    echo "INTERACTION_OUTPUTS_EXACT=1"
    echo "STALE_DONE_RECOVERY_VERIFIED=1"
    echo "TERMINAL_DONE_ACCEPTED=1"
    echo "FIREWALL_GOOD_AFTER_TEST=1"
    echo "CU_IDLE_AFTER_TEST=1"
    echo "NO_FPGA_PROGRAMMING=1"
    echo "NO_FPGA_RESET=1"
    echo "HOST_SOURCE=$(readlink -f "${SOURCE}")"
    echo "HOST_BINARY=$(readlink -f "${BINARY}")"
    echo "LOG=${LOG}"
} > "${STATUS}"

echo
echo "============================================================"
echo "STAGE2N_A4_HOST_ONLY_V2_PASS"
echo "LEGACY_MLP_RESULT=19"
echo "INTERACTION_OUTPUTS=18"
echo "STALE_DONE_RECOVERY_VERIFIED=1"
echo "STATUS=${STATUS}"
echo "LOG=${LOG}"
echo "NO FPGA PROGRAMMING OR RESET WAS PERFORMED"
echo "============================================================"
