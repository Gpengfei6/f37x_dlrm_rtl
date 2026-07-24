#!/usr/bin/env bash
# Stage 2H: link the packaged DLRM RTL kernel against the installed
# Inspur F37X Vitis platform and generate a hardware xclbin.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

VITIS_SETTINGS="${VITIS_SETTINGS:-/opt/Xilinx/Vitis/2020.2/settings64.sh}"
PLATFORM="${PLATFORM:-/opt/xilinx/platforms/inspur_f37x_xdma_201920_3/inspur_f37x_xdma_201920_3.xpfm}"
KERNEL_NAME="dlrm_f37x_rtl_kernel"
CU_NAME="dlrm_f37x_rtl_kernel_1"
KERNEL_FREQUENCY_MHZ="${KERNEL_FREQUENCY_MHZ:-100}"
JOBS="${JOBS:-8}"

XO_PATH="${REPO_ROOT}/build/stage2g/package/${KERNEL_NAME}.xo"
KERNEL_XML="${REPO_ROOT}/build/stage2g/package/kernel.xml"

BUILD_DIR="${REPO_ROOT}/build/stage2h"
OUTPUT_DIR="${BUILD_DIR}/hw"
TEMP_DIR="${BUILD_DIR}/_x"
XCLBIN_PATH="${OUTPUT_DIR}/${KERNEL_NAME}.xclbin"

LOG_DIR="${REPO_ROOT}/logs"
RESULT_DIR="${REPO_ROOT}/results/stage2h"
VPP_LOG="${LOG_DIR}/vpp_stage2h_f37x_link.log"
XCLBIN_INFO="${RESULT_DIR}/${KERNEL_NAME}.xclbin.info"
STATUS_FILE="${RESULT_DIR}/stage2h_f37x_link_status.txt"

mkdir -p "${OUTPUT_DIR}" "${LOG_DIR}" "${RESULT_DIR}"

write_failure_status() {
    local exit_code="$1"
    local reason="$2"

    cat > "${STATUS_FILE}" <<EOF
STAGE2H_F37X_LINK_FAILED
REASON=${reason}
EXIT_CODE=${exit_code}
KERNEL=${KERNEL_NAME}
COMPUTE_UNIT=${CU_NAME}
PLATFORM=${PLATFORM}
KERNEL_FREQUENCY_MHZ=${KERNEL_FREQUENCY_MHZ}
XO=${XO_PATH}
XCLBIN=${XCLBIN_PATH}
LOG=${VPP_LOG}
EOF
}

fail() {
    local exit_code="$1"
    shift
    local reason="$*"

    echo "ERROR: ${reason}" >&2
    write_failure_status "${exit_code}" "${reason}"
    exit "${exit_code}"
}

[[ -f "${VITIS_SETTINGS}" ]] ||
    fail 2 "Vitis settings not found: ${VITIS_SETTINGS}"

# shellcheck disable=SC1090
source "${VITIS_SETTINGS}"

command -v v++ >/dev/null 2>&1 ||
    fail 3 "v++ is not available after sourcing Vitis"
command -v xclbinutil >/dev/null 2>&1 ||
    fail 4 "xclbinutil is not available after sourcing Vitis"

[[ -f "${PLATFORM}" ]] ||
    fail 5 "F37X platform not found: ${PLATFORM}"
[[ -s "${XO_PATH}" ]] ||
    fail 6 "Stage 2G XO not found or empty: ${XO_PATH}"
[[ -s "${KERNEL_XML}" ]] ||
    fail 7 "Stage 2G kernel.xml not found or empty: ${KERNEL_XML}"

grep -q "${KERNEL_NAME}" "${KERNEL_XML}" ||
    fail 8 "kernel.xml does not contain kernel name ${KERNEL_NAME}"
grep -q "s_axi_control" "${KERNEL_XML}" ||
    fail 9 "kernel.xml does not contain s_axi_control"
# package_xo-generated kernel.xml does not necessarily enumerate the
# physical clock port by its RTL name. Clock/reset association is stored in
# the packaged IP metadata inside the XO, so do not reject a valid XO merely
# because the literal string 'ap_clk' is absent from kernel.xml.

rm -rf "${TEMP_DIR}"
rm -f "${XCLBIN_PATH}" "${VPP_LOG}" "${XCLBIN_INFO}"

START_EPOCH="$(date +%s)"
START_ISO="$(date -Is)"

echo "============================================================"
echo "Stage 2H F37X hardware link"
echo "Repository           : ${REPO_ROOT}"
echo "Platform             : ${PLATFORM}"
echo "Kernel               : ${KERNEL_NAME}"
echo "Compute unit         : ${CU_NAME}"
echo "Kernel frequency MHz : ${KERNEL_FREQUENCY_MHZ}"
echo "XO                   : ${XO_PATH}"
echo "XCLBIN               : ${XCLBIN_PATH}"
echo "============================================================"

set +e
v++ \
    --target hw \
    --link \
    --platform "${PLATFORM}" \
    --connectivity.nk "${KERNEL_NAME}:1:${CU_NAME}" \
    --kernel_frequency "${KERNEL_FREQUENCY_MHZ}" \
    --jobs "${JOBS}" \
    --save-temps \
    --temp_dir "${TEMP_DIR}" \
    --output "${XCLBIN_PATH}" \
    --vivado.prop run.impl_1.strategy=Performance_Explore \
    --vivado.prop run.impl_1.steps.phys_opt_design.is_enabled=1 \
    --vivado.prop run.impl_1.steps.post_route_phys_opt_design.is_enabled=1 \
    "${XO_PATH}" \
    2>&1 | tee "${VPP_LOG}"
VPP_EXIT_CODE="${PIPESTATUS[0]}"
set -e

END_EPOCH="$(date +%s)"
END_ISO="$(date -Is)"
ELAPSED_SECONDS="$((END_EPOCH - START_EPOCH))"

if [[ "${VPP_EXIT_CODE}" != "0" ]]; then
    fail "${VPP_EXIT_CODE}" \
        "v++ hardware link failed; inspect ${VPP_LOG}"
fi

[[ -s "${XCLBIN_PATH}" ]] ||
    fail 10 "v++ returned success but xclbin is missing or empty"

ERROR_COUNT="$(
    grep -cE '^ERROR:' "${VPP_LOG}" || true
)"
CRITICAL_WARNING_COUNT="$(
    grep -cE '^CRITICAL WARNING:' "${VPP_LOG}" || true
)"

if [[ "${ERROR_COUNT}" != "0" ]]; then
    fail 11 "v++ log contains ${ERROR_COUNT} anchored errors"
fi

if [[ "${CRITICAL_WARNING_COUNT}" != "0" ]]; then
    fail 12 \
        "v++ log contains ${CRITICAL_WARNING_COUNT} critical warnings"
fi

xclbinutil \
    --quiet \
    --force \
    --info "${XCLBIN_INFO}" \
    --input "${XCLBIN_PATH}"

grep -q "${KERNEL_NAME}" "${XCLBIN_INFO}" ||
    fail 13 "xclbin metadata does not contain kernel ${KERNEL_NAME}"

TIMING_REPORT="$(
    find "${TEMP_DIR}" -type f \
        -name '*timing_summary_routed.rpt' \
        -print 2>/dev/null |
    head -1
)"

if [[ -z "${TIMING_REPORT}" ]]; then
    TIMING_REPORT="NOT_FOUND"
fi

GIT_BRANCH="$(
    cd "${REPO_ROOT}" &&
    git symbolic-ref --short HEAD 2>/dev/null ||
    echo UNKNOWN
)"
GIT_HEAD="$(
    cd "${REPO_ROOT}" &&
    git rev-parse HEAD 2>/dev/null ||
    echo UNKNOWN
)"
XCLBIN_SIZE_BYTES="$(stat -c '%s' "${XCLBIN_PATH}")"

cat > "${STATUS_FILE}" <<EOF
STAGE2H_F37X_LINK_PASS
KERNEL=${KERNEL_NAME}
COMPUTE_UNIT=${CU_NAME}
PLATFORM=${PLATFORM}
TARGET=hw
KERNEL_FREQUENCY_MHZ=${KERNEL_FREQUENCY_MHZ}
GIT_BRANCH=${GIT_BRANCH}
GIT_HEAD=${GIT_HEAD}
START_TIME=${START_ISO}
END_TIME=${END_ISO}
ELAPSED_SECONDS=${ELAPSED_SECONDS}
XO=${XO_PATH}
XCLBIN=${XCLBIN_PATH}
XCLBIN_SIZE_BYTES=${XCLBIN_SIZE_BYTES}
XCLBIN_INFO=${XCLBIN_INFO}
TIMING_REPORT=${TIMING_REPORT}
ERROR_COUNT=${ERROR_COUNT}
CRITICAL_WARNING_COUNT=${CRITICAL_WARNING_COUNT}
EOF

echo "============================================================"
echo "STAGE2H_F37X_LINK_PASS"
echo "XCLBIN=${XCLBIN_PATH}"
echo "XCLBIN_SIZE_BYTES=${XCLBIN_SIZE_BYTES}"
echo "ELAPSED_SECONDS=${ELAPSED_SECONDS}"
echo "TIMING_REPORT=${TIMING_REPORT}"
echo "============================================================"
