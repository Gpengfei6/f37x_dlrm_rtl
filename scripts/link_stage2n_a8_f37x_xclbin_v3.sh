#!/usr/bin/env bash
#
# Stage 2N-A8 v3 F37X hardware link for the Stage 2N-A7 automatic pipeline.
#
# Consumes the verified A8 XO and generates an F37X hardware xclbin.
# It never programs or resets any FPGA and never opens a render node.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

VITIS_SETTINGS="${VITIS_SETTINGS:-/opt/Xilinx/Vitis/2020.2/settings64.sh}"
PLATFORM="${PLATFORM:-/opt/xilinx/platforms/inspur_f37x_xdma_201920_3/inspur_f37x_xdma_201920_3.xpfm}"

EXPECTED_BRANCH="work/stage2n-a8-xo-xclbin"
KERNEL_NAME="dlrm_f37x_rtl_kernel_stage2n_a7"
CU_NAME="dlrm_a7_1"
KERNEL_FREQUENCY_MHZ="${KERNEL_FREQUENCY_MHZ:-100}"
JOBS="${JOBS:-8}"

PACKAGE_DIR="${REPO_ROOT}/build/stage2n_a8/package_v3"
XO_PATH="${PACKAGE_DIR}/${KERNEL_NAME}.xo"
KERNEL_XML="${PACKAGE_DIR}/kernel.xml"

BUILD_DIR="${REPO_ROOT}/build/stage2n_a8/link_v3"
OUTPUT_DIR="${BUILD_DIR}/hw"
TEMP_DIR="${BUILD_DIR}/_x"
XCLBIN_PATH="${OUTPUT_DIR}/${KERNEL_NAME}.xclbin"

LOG_DIR="${REPO_ROOT}/logs"
RESULT_DIR="${REPO_ROOT}/results/stage2n_a8/link_v3"
VPP_LOG="${LOG_DIR}/vpp_stage2n_a8_f37x_link_v3.log"
XCLBIN_INFO="${RESULT_DIR}/${KERNEL_NAME}.xclbin.info"
STATUS_FILE="${RESULT_DIR}/stage2n_a8_f37x_link_v3_status.txt"
TIMING_COPY="${RESULT_DIR}/${KERNEL_NAME}_timing_summary_routed.rpt"

fail()
{
    local code="$1"
    shift
    local reason="$*"

    mkdir -p "${RESULT_DIR}"

    cat > "${STATUS_FILE}" <<EOF
STAGE2N_A8_F37X_LINK_V3_FAILED
REASON=${reason}
EXIT_CODE=${code}
KERNEL=${KERNEL_NAME}
COMPUTE_UNIT=${CU_NAME}
PLATFORM=${PLATFORM}
KERNEL_FREQUENCY_MHZ=${KERNEL_FREQUENCY_MHZ}
XO=${XO_PATH}
XCLBIN=${XCLBIN_PATH}
LOG=${VPP_LOG}
NO_FPGA_PROGRAMMING_OR_RESET=1
EOF

    echo "ERROR: ${reason}" >&2
    exit "${code}"
}

KERNEL_CU_SPEC="${KERNEL_NAME}:${CU_NAME}"
KERNEL_CU_SPEC_LENGTH="${#KERNEL_CU_SPEC}"

(( KERNEL_CU_SPEC_LENGTH <= 64 )) ||
    fail 1 "kernel/CU specification length ${KERNEL_CU_SPEC_LENGTH} exceeds the Vitis 2020.2 limit of 64"

[[ -f "${VITIS_SETTINGS}" ]] ||
    fail 2 "Vitis settings not found: ${VITIS_SETTINGS}"

# shellcheck disable=SC1090
source "${VITIS_SETTINGS}" >/dev/null

command -v v++ >/dev/null 2>&1 ||
    fail 3 "v++ is unavailable after sourcing Vitis"

command -v xclbinutil >/dev/null 2>&1 ||
    fail 4 "xclbinutil is unavailable after sourcing Vitis"

command -v unzip >/dev/null 2>&1 ||
    fail 5 "unzip is unavailable"

CURRENT_BRANCH="$(
    cd "${REPO_ROOT}" &&
    git symbolic-ref --short HEAD 2>/dev/null ||
        echo DETACHED
)"

CURRENT_HEAD="$(
    cd "${REPO_ROOT}" &&
    git rev-parse HEAD
)"

[[ "${CURRENT_BRANCH}" == "${EXPECTED_BRANCH}" ]] ||
    fail 6 "wrong branch: ${CURRENT_BRANCH}; expected ${EXPECTED_BRANCH}"

[[ -f "${PLATFORM}" ]] ||
    fail 7 "F37X platform not found: ${PLATFORM}"

[[ -s "${XO_PATH}" ]] ||
    fail 8 "A8 XO not found or empty: ${XO_PATH}"

[[ -s "${KERNEL_XML}" ]] ||
    fail 9 "A8 kernel.xml not found or empty: ${KERNEL_XML}"

grep -qF "name=\"${KERNEL_NAME}\"" "${KERNEL_XML}" ||
    fail 10 "kernel.xml does not contain kernel ${KERNEL_NAME}"

grep -qF 'name="s_axi_control"' "${KERNEL_XML}" ||
    fail 11 "kernel.xml does not contain s_axi_control"

grep -qF 'name="PIPE_CONTROL_STATUS"' "${KERNEL_XML}" ||
    fail 12 "kernel.xml does not contain PIPE_CONTROL_STATUS"

grep -qF 'offset="0x180"' "${KERNEL_XML}" ||
    fail 13 "kernel.xml does not contain pipeline base offset 0x180"

grep -qF 'name="PIPE_CONFIG_READY"' "${KERNEL_XML}" ||
    fail 14 "kernel.xml does not contain PIPE_CONFIG_READY"

unzip -t "${XO_PATH}" >/dev/null ||
    fail 15 "XO archive integrity test failed"

XO_CONTENTS="$(unzip -Z1 "${XO_PATH}")"

grep -qF 'dlrm_f37x_rtl_kernel_stage2n_a7.sv' <<< "${XO_CONTENTS}" ||
    fail 16 "XO does not contain the A7 kernel top"

grep -qF 'dlrm_internal_pipeline_controller.sv' <<< "${XO_CONTENTS}" ||
    fail 17 "XO does not contain the internal pipeline controller"

mkdir -p "${OUTPUT_DIR}" "${LOG_DIR}" "${RESULT_DIR}"

rm -rf "${TEMP_DIR}"
rm -f \
    "${XCLBIN_PATH}" \
    "${VPP_LOG}" \
    "${XCLBIN_INFO}" \
    "${STATUS_FILE}" \
    "${TIMING_COPY}"

START_TIME="$(date -Is)"
START_EPOCH="$(date +%s)"

XO_SHA256="$(sha256sum "${XO_PATH}" | awk '{print $1}')"
KERNEL_XML_SHA256="$(sha256sum "${KERNEL_XML}" | awk '{print $1}')"

echo "============================================================"
echo "Stage 2N-A8 v3 F37X hardware link"
echo "TIME=${START_TIME}"
echo "REPO=${REPO_ROOT}"
echo "BRANCH=${CURRENT_BRANCH}"
echo "HEAD=${CURRENT_HEAD}"
echo "PLATFORM=${PLATFORM}"
echo "KERNEL=${KERNEL_NAME}"
echo "COMPUTE_UNIT=${CU_NAME}"
echo "KERNEL_CU_SPEC_LENGTH=${KERNEL_CU_SPEC_LENGTH}/64"
echo "KERNEL_FREQUENCY_MHZ=${KERNEL_FREQUENCY_MHZ}"
echo "JOBS=${JOBS}"
echo "XO=${XO_PATH}"
echo "XO_SHA256=${XO_SHA256}"
echo "XCLBIN=${XCLBIN_PATH}"
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
VPP_EXIT="${PIPESTATUS[0]}"
set -e

END_TIME="$(date -Is)"
END_EPOCH="$(date +%s)"
ELAPSED_SECONDS="$((END_EPOCH - START_EPOCH))"

[[ "${VPP_EXIT}" -eq 0 ]] ||
    fail "${VPP_EXIT}" "v++ hardware link failed; inspect ${VPP_LOG}"

[[ -s "${XCLBIN_PATH}" ]] ||
    fail 18 "v++ returned success but xclbin is missing or empty"

ERROR_COUNT="$(grep -cE '^ERROR:' "${VPP_LOG}" || true)"
CRITICAL_WARNING_COUNT="$(
    grep -cE '^CRITICAL WARNING:' "${VPP_LOG}" || true
)"

[[ "${ERROR_COUNT}" == "0" ]] ||
    fail 19 "v++ log contains ${ERROR_COUNT} anchored ERROR lines"

[[ "${CRITICAL_WARNING_COUNT}" == "0" ]] ||
    fail 20 "v++ log contains ${CRITICAL_WARNING_COUNT} critical warnings"

xclbinutil \
    --quiet \
    --force \
    --info "${XCLBIN_INFO}" \
    --input "${XCLBIN_PATH}"

grep -qF "Kernels:                ${KERNEL_NAME}" "${XCLBIN_INFO}" ||
    grep -qF "Kernel: ${KERNEL_NAME}" "${XCLBIN_INFO}" ||
    fail 21 "xclbin metadata does not contain kernel ${KERNEL_NAME}"

grep -qF "Instance:        ${CU_NAME}" "${XCLBIN_INFO}" ||
    fail 22 "xclbin metadata does not contain compute unit ${CU_NAME}"

grep -qF 'Platform VBNV:          inspur_f37x_xdma_201920_3' "${XCLBIN_INFO}" ||
    fail 23 "xclbin metadata does not contain the expected F37X platform"

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
STAGE2N_A8_F37X_LINK_V3_PASS
KERNEL=${KERNEL_NAME}
COMPUTE_UNIT=${CU_NAME}
KERNEL_CU_SPEC=${KERNEL_CU_SPEC}
KERNEL_CU_SPEC_LENGTH=${KERNEL_CU_SPEC_LENGTH}
PLATFORM=${PLATFORM}
TARGET=hw
KERNEL_FREQUENCY_MHZ=${KERNEL_FREQUENCY_MHZ}
JOBS=${JOBS}
GIT_BRANCH=${CURRENT_BRANCH}
GIT_HEAD=${CURRENT_HEAD}
START_TIME=${START_TIME}
END_TIME=${END_TIME}
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
NO_FPGA_PROGRAMMING_OR_RESET=1
EOF

echo "============================================================"
echo "STAGE2N_A8_F37X_LINK_V3_PASS"
echo "XCLBIN=${XCLBIN_PATH}"
echo "XCLBIN_SIZE_BYTES=${XCLBIN_SIZE_BYTES}"
echo "XCLBIN_SHA256=${XCLBIN_SHA256}"
echo "XCLBIN_UUID=${XCLBIN_UUID}"
echo "COMPUTE_UNIT=${CU_NAME}"
echo "ELAPSED_SECONDS=${ELAPSED_SECONDS}"
echo "TIMING_REPORT=${TIMING_REPORT}"
echo "STATUS=${STATUS_FILE}"
echo "NO FPGA PROGRAMMING OR RESET"
echo "============================================================"
