#!/usr/bin/env bash
#
# Stage 2N-A3 v2:
# Link the Stage 2N-A2 integrated DLRM RTL kernel against the verified
# Inspur F37X Vitis platform and generate a hardware xclbin.
#
# This script uses a new build/output tree and never overwrites the verified
# Stage 2H xclbin. It does not program/reset an FPGA and does not access any
# render node.
#

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

VITIS_SETTINGS="${VITIS_SETTINGS:-/opt/Xilinx/Vitis/2020.2/settings64.sh}"
PLATFORM="${PLATFORM:-/opt/xilinx/platforms/inspur_f37x_xdma_201920_3/inspur_f37x_xdma_201920_3.xpfm}"

KERNEL_NAME="dlrm_f37x_rtl_kernel_stage2n_a2"
CU_NAME="dlrm_f37x_rtl_kernel_stage2n_a2_1"
KERNEL_FREQUENCY_MHZ="${KERNEL_FREQUENCY_MHZ:-100}"
JOBS="${JOBS:-8}"

XO_PATH="${REPO_ROOT}/build/stage2n_a2/package_v2/${KERNEL_NAME}.xo"
KERNEL_XML="${REPO_ROOT}/build/stage2n_a2/package_v2/kernel.xml"

BUILD_DIR="${REPO_ROOT}/build/stage2n_a3_v2"
OUTPUT_DIR="${BUILD_DIR}/hw"
TEMP_DIR="${BUILD_DIR}/_x"
XCLBIN_PATH="${OUTPUT_DIR}/${KERNEL_NAME}.xclbin"

LOG_DIR="${REPO_ROOT}/logs"
RESULT_DIR="${REPO_ROOT}/results/stage2n_a3_v2"

VPP_LOG="${LOG_DIR}/vpp_stage2n_a3_f37x_link_v2.log"
XCLBIN_INFO="${RESULT_DIR}/${KERNEL_NAME}.xclbin.info"
STATUS_FILE="${RESULT_DIR}/stage2n_a3_f37x_link_v2_status.txt"
TIMING_COPY="${RESULT_DIR}/${KERNEL_NAME}_timing_summary_routed.rpt"

mkdir -p "${OUTPUT_DIR}" "${LOG_DIR}" "${RESULT_DIR}"

write_failure_status()
{
    local exit_code="$1"
    local reason="$2"

    cat > "${STATUS_FILE}" <<EOF
STAGE2N_A3_F37X_LINK_V2_FAILED
REASON=${reason}
EXIT_CODE=${exit_code}
KERNEL=${KERNEL_NAME}
COMPUTE_UNIT=${CU_NAME}
PLATFORM=${PLATFORM}
KERNEL_FREQUENCY_MHZ=${KERNEL_FREQUENCY_MHZ}
XO=${XO_PATH}
XCLBIN=${XCLBIN_PATH}
LOG=${VPP_LOG}
NO_FPGA_PROGRAMMING=1
EOF
}

fail()
{
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
source "${VITIS_SETTINGS}" >/dev/null

command -v v++ >/dev/null 2>&1 ||
    fail 3 "v++ is not available after sourcing Vitis"

command -v xclbinutil >/dev/null 2>&1 ||
    fail 4 "xclbinutil is not available after sourcing Vitis"

command -v unzip >/dev/null 2>&1 ||
    fail 5 "unzip is not available"

[[ -f "${PLATFORM}" ]] ||
    fail 6 "F37X platform not found: ${PLATFORM}"

[[ -s "${XO_PATH}" ]] ||
    fail 7 "Stage 2N-A2 XO not found or empty: ${XO_PATH}"

[[ -s "${KERNEL_XML}" ]] ||
    fail 8 "Stage 2N-A2 kernel.xml not found or empty: ${KERNEL_XML}"

grep -qF "name=\"${KERNEL_NAME}\"" "${KERNEL_XML}" ||
    fail 9 "kernel.xml does not contain kernel ${KERNEL_NAME}"

grep -qF 'name="s_axi_control"' "${KERNEL_XML}" ||
    fail 10 "kernel.xml does not contain s_axi_control"

grep -qF 'name="INT_CONTROL_STATUS"' "${KERNEL_XML}" ||
    fail 11 "kernel.xml does not contain INT_CONTROL_STATUS"

grep -qF 'offset="0x100"' "${KERNEL_XML}" ||
    fail 12 "kernel.xml does not contain interaction offset 0x100"

grep -qF 'name="INT_LOADED_MASK"' "${KERNEL_XML}" ||
    fail 13 "kernel.xml does not contain INT_LOADED_MASK"

unzip -t "${XO_PATH}" >/dev/null ||
    fail 14 "XO archive integrity test failed"

XO_CONTENTS="$(unzip -Z1 "${XO_PATH}")"

grep -qF 'dlrm_feature_interaction_engine.sv' <<< "${XO_CONTENTS}" ||
    fail 15 "XO does not contain dlrm_feature_interaction_engine.sv"

grep -qF 'dlrm_f37x_rtl_kernel_stage2n_a2.sv' <<< "${XO_CONTENTS}" ||
    fail 16 "XO does not contain the Stage 2N-A2 top"

rm -rf "${TEMP_DIR}"
rm -f \
    "${XCLBIN_PATH}" \
    "${VPP_LOG}" \
    "${XCLBIN_INFO}" \
    "${STATUS_FILE}" \
    "${TIMING_COPY}"

START_EPOCH="$(date +%s)"
START_ISO="$(date -Is)"

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

XO_SHA256="$(sha256sum "${XO_PATH}" | awk '{print $1}')"
KERNEL_XML_SHA256="$(sha256sum "${KERNEL_XML}" | awk '{print $1}')"

echo "============================================================"
echo "Stage 2N-A3 v2 F37X hardware link"
echo "Repository           : ${REPO_ROOT}"
echo "Branch               : ${GIT_BRANCH}"
echo "HEAD                 : ${GIT_HEAD}"
echo "Platform             : ${PLATFORM}"
echo "Kernel               : ${KERNEL_NAME}"
echo "Compute unit         : ${CU_NAME}"
echo "Kernel frequency MHz : ${KERNEL_FREQUENCY_MHZ}"
echo "Jobs                 : ${JOBS}"
echo "XO                   : ${XO_PATH}"
echo "XO SHA256            : ${XO_SHA256}"
echo "Kernel XML SHA256    : ${KERNEL_XML_SHA256}"
echo "XCLBIN               : ${XCLBIN_PATH}"
echo "NO FPGA PROGRAMMING OR RESET"
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
    fail 17 "v++ returned success but xclbin is missing or empty"

ERROR_COUNT="$(grep -cE '^ERROR:' "${VPP_LOG}" || true)"
CRITICAL_WARNING_COUNT="$(
    grep -cE '^CRITICAL WARNING:' "${VPP_LOG}" || true
)"

if [[ "${ERROR_COUNT}" != "0" ]]; then
    fail 18 "v++ log contains ${ERROR_COUNT} anchored errors"
fi

if [[ "${CRITICAL_WARNING_COUNT}" != "0" ]]; then
    fail 19 \
        "v++ log contains ${CRITICAL_WARNING_COUNT} critical warnings"
fi

xclbinutil \
    --quiet \
    --force \
    --info "${XCLBIN_INFO}" \
    --input "${XCLBIN_PATH}"

grep -qF "Kernels:                ${KERNEL_NAME}" "${XCLBIN_INFO}" ||
    grep -qF "Kernel: ${KERNEL_NAME}" "${XCLBIN_INFO}" ||
    fail 20 "xclbin metadata does not contain kernel ${KERNEL_NAME}"

grep -qF 'Platform VBNV:          inspur_f37x_xdma_201920_3' \
    "${XCLBIN_INFO}" ||
    fail 21 "xclbin metadata does not contain the expected F37X platform"

TIMING_REPORT="$(
    find "${TEMP_DIR}" \
        -type f \
        -name '*timing_summary_routed.rpt' \
        -print \
        -quit 2>/dev/null
)"

if [[ -n "${TIMING_REPORT}" && -f "${TIMING_REPORT}" ]]; then
    cp -f "${TIMING_REPORT}" "${TIMING_COPY}"
else
    TIMING_REPORT="NOT_FOUND"
    TIMING_COPY="NOT_CREATED"
fi

XCLBIN_SIZE_BYTES="$(stat -c '%s' "${XCLBIN_PATH}")"
XCLBIN_SHA256="$(sha256sum "${XCLBIN_PATH}" | awk '{print $1}')"

XCLBIN_UUID="$(
    sed -n \
        's/^[[:space:]]*UUID (xclbin):[[:space:]]*//p' \
        "${XCLBIN_INFO}" |
    head -n 1
)"

if [[ -z "${XCLBIN_UUID}" ]]; then
    XCLBIN_UUID="NOT_PARSED"
fi

cat > "${STATUS_FILE}" <<EOF
STAGE2N_A3_F37X_LINK_V2_PASS
KERNEL=${KERNEL_NAME}
COMPUTE_UNIT=${CU_NAME}
PLATFORM=${PLATFORM}
TARGET=hw
KERNEL_FREQUENCY_MHZ=${KERNEL_FREQUENCY_MHZ}
JOBS=${JOBS}
GIT_BRANCH=${GIT_BRANCH}
GIT_HEAD=${GIT_HEAD}
START_TIME=${START_ISO}
END_TIME=${END_ISO}
ELAPSED_SECONDS=${ELAPSED_SECONDS}
XO=${XO_PATH}
XO_SHA256=${XO_SHA256}
KERNEL_XML=${KERNEL_XML}
KERNEL_XML_SHA256=${KERNEL_XML_SHA256}
XCLBIN=${XCLBIN_PATH}
XCLBIN_SIZE_BYTES=${XCLBIN_SIZE_BYTES}
XCLBIN_SHA256=${XCLBIN_SHA256}
XCLBIN_UUID=${XCLBIN_UUID}
XCLBIN_INFO=${XCLBIN_INFO}
TIMING_REPORT=${TIMING_REPORT}
TIMING_COPY=${TIMING_COPY}
ERROR_COUNT=${ERROR_COUNT}
CRITICAL_WARNING_COUNT=${CRITICAL_WARNING_COUNT}
LOG=${VPP_LOG}
NO_FPGA_PROGRAMMING=1
EOF

echo "============================================================"
echo "STAGE2N_A3_F37X_LINK_V2_PASS"
echo "XCLBIN=${XCLBIN_PATH}"
echo "XCLBIN_SIZE_BYTES=${XCLBIN_SIZE_BYTES}"
echo "XCLBIN_SHA256=${XCLBIN_SHA256}"
echo "XCLBIN_UUID=${XCLBIN_UUID}"
echo "ELAPSED_SECONDS=${ELAPSED_SECONDS}"
echo "TIMING_REPORT=${TIMING_REPORT}"
echo "STATUS=${STATUS_FILE}"
echo "NO FPGA PROGRAMMING OR RESET"
echo "============================================================"
