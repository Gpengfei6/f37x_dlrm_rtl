#!/usr/bin/env bash
# User-executed Stage 2N-A15.5 exact-target XO-only runner.
# It does not invoke v++, link an xclbin, or access an FPGA device.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

VITIS_SETTINGS="${VITIS_SETTINGS:-/opt/Xilinx/Vitis/2020.2/settings64.sh}"
PLATFORM="${PLATFORM:-/opt/xilinx/platforms/inspur_f37x_xdma_201920_3/inspur_f37x_xdma_201920_3.xpfm}"
PART_NAME="xcvu37p-fsvh2892-2L-e"
EXPECTED_BRANCH="work/stage2n-a15-hbm-pipeline-integration"
AUTHORIZATION_BASELINE="0c705a360a036785e4c949185fcb5cc1dcc4f07f"
KERNEL_NAME="dlrm_f37x_rtl_kernel_stage2n_a15_v1"
ACCEPTED_WRAPPER_SHA256="c3da5be63d4cf195df124e572887b6aa96a464522883c6cdc95c4bd56ff4e8a1"

PACKAGE_TCL="${REPO_ROOT}/scripts/package_stage2n_a15_5_rtl_kernel_v1.tcl"
VALIDATOR="${REPO_ROOT}/scripts/validate_stage2n_a15_5_xo_v1.py"
WRAPPER_RTL="${REPO_ROOT}/rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a15_v1.sv"
XO_DIR="${REPO_ROOT}/build/stage2n_a15_5/xo_v1"
XO_PATH="${XO_DIR}/${KERNEL_NAME}.xo"
KERNEL_XML="${XO_DIR}/kernel.xml"
COMPONENT_XML="${XO_DIR}/dlrm_f37x_stage2n_a15_ip_v1/component.xml"

RESULT_ROOT="${REPO_ROOT}/results/stage2n_a15_5/target_xo_v1"
LOG_DIR="${RESULT_ROOT}/logs"
STATUS="${RESULT_ROOT}/a15_5_target_xo_v1_status.txt"
SOURCE_HASHES="${RESULT_ROOT}/a15_5_target_xo_v1_sources.sha256"
ARTIFACT_HASHES="${RESULT_ROOT}/a15_5_target_xo_v1_artifacts.sha256"
PACKAGE_LOG="${LOG_DIR}/vivado_package_xo.log"
VALIDATION_LOG="${LOG_DIR}/xo_metadata_validation.log"
TOOL_LOG="${LOG_DIR}/tool_versions.log"
GIT_STATUS_FILE="${RESULT_ROOT}/git_status_porcelain.txt"
INTERNAL_KERNEL_XML="${RESULT_ROOT}/kernel_xml_inside_xo.xml"
INTERNAL_COMPONENT_XML="${RESULT_ROOT}/component_xml_inside_xo.xml"

A15_5_TARGET_XO_BUILD="NOT_RUN"
A15_5_TARGET_XO_VALIDATION="NOT_RUN"
FAIL_REASON="NONE"
CURRENT_BRANCH="NOT_RECORDED"
CURRENT_HEAD="NOT_RECORDED"
XO_SHA256="NOT_AVAILABLE"

write_status()
{
    cat > "${STATUS}" <<EOF
A15_5_FLOW=TARGET_XO_V1
A15_5_TARGET_XO_BUILD=${A15_5_TARGET_XO_BUILD}
A15_5_TARGET_XO_VALIDATION=${A15_5_TARGET_XO_VALIDATION}
A15_5_TARGET_LINK=NOT_RUN
A15_5_XCLBIN=NOT_RUN
A15_5_PHYSICAL_HBM=NOT_VALIDATED
A15_5_FPGA_DEVICE_ACCESS=NONE
A15_5_READY_FOR_BOARD=NO
FAIL_REASON=${FAIL_REASON}
GIT_BRANCH=${CURRENT_BRANCH}
GIT_HEAD=${CURRENT_HEAD}
TARGET_PART=${PART_NAME}
PLATFORM=${PLATFORM}
KERNEL=${KERNEL_NAME}
CONTROL_INTERFACE=s_axi_control
MEMORY_INTERFACE=m_axi_gmem
M_AXI_MASTER_COUNT=1
M_AXI_DATA_WIDTH=128
M_AXI_ADDR_WIDTH=64
TABLE_BASE_OFFSET=0x304
KERNEL_ARGUMENT_COUNT=1
XO=${XO_PATH}
XO_SHA256=${XO_SHA256}
EOF
}

fail()
{
    local code="$1"
    shift
    FAIL_REASON="$*"
    if [[ -d "${RESULT_ROOT}" ]]; then
        write_status
    fi
    echo "ERROR: ${FAIL_REASON}" >&2
    exit "${code}"
}

unexpected_error()
{
    local code="$?"
    local line="${BASH_LINENO[0]:-UNKNOWN}"
    if [[ "${FAIL_REASON}" == "NONE" ]]; then
        A15_5_TARGET_XO_BUILD="FAIL"
        FAIL_REASON="unexpected command failure at line ${line}"
        [[ -d "${RESULT_ROOT}" ]] && write_status
    fi
    exit "${code}"
}

[[ ! -e "${XO_DIR}" ]] || {
    echo "ERROR: refusing to overwrite existing XO directory: ${XO_DIR}" >&2
    exit 2
}
[[ ! -e "${RESULT_ROOT}" ]] || {
    echo "ERROR: refusing to overwrite existing result root: ${RESULT_ROOT}" >&2
    exit 3
}
for required in "${VITIS_SETTINGS}" "${PLATFORM}" "${PACKAGE_TCL}" "${VALIDATOR}" "${WRAPPER_RTL}"; do
    [[ -f "${required}" ]] || {
        echo "ERROR: required input is missing: ${required}" >&2
        exit 4
    }
done

confirmation="${A15_5_XO_CONFIRM:-}"
if [[ -z "${confirmation}" ]]; then
    if [[ ! -t 0 ]]; then
        echo "ERROR: interactive confirmation unavailable; set A15_5_XO_CONFIRM=yes" >&2
        exit 5
    fi
    read -r -p "Proceed with the A15.5 XO-only build? [yes/no] " confirmation
fi
[[ "${confirmation}" == "yes" ]] || {
    echo "A15.5 XO-only build cancelled safely."
    exit 0
}

mkdir -p "${LOG_DIR}"
trap unexpected_error ERR
CURRENT_BRANCH="$(cd "${REPO_ROOT}" && git symbolic-ref --short HEAD 2>/dev/null || echo DETACHED)"
CURRENT_HEAD="$(cd "${REPO_ROOT}" && git rev-parse HEAD)"
[[ "${CURRENT_BRANCH}" == "${EXPECTED_BRANCH}" ]] || fail 6 "wrong branch: ${CURRENT_BRANCH}"
(cd "${REPO_ROOT}" && git merge-base --is-ancestor "${AUTHORIZATION_BASELINE}" HEAD) ||
    fail 6 "A15.5 authorization baseline is not an ancestor of HEAD"
(cd "${REPO_ROOT}" && git diff --quiet && git diff --cached --quiet) ||
    fail 6 "tracked worktree/index must be clean before target XO build"
(cd "${REPO_ROOT}" && git status --porcelain) > "${GIT_STATUS_FILE}"

actual_wrapper_sha256="$(sha256sum "${WRAPPER_RTL}" | awk '{print $1}')"
[[ "${actual_wrapper_sha256}" == "${ACCEPTED_WRAPPER_SHA256}" ]] ||
    fail 7 "accepted A15.4 wrapper SHA256 mismatch"

# shellcheck disable=SC1090
source "${VITIS_SETTINGS}" >/dev/null
for tool in git sha256sum vivado unzip python3 cmp grep awk tee; do
    command -v "${tool}" >/dev/null 2>&1 || fail 8 "required tool unavailable: ${tool}"
done

{
    echo "VITIS_SETTINGS=${VITIS_SETTINGS}"
    echo "PLATFORM=${PLATFORM}"
    vivado -version
} > "${TOOL_LOG}" 2>&1
sha256sum "${PACKAGE_TCL}" "${VALIDATOR}" "${WRAPPER_RTL}" "${BASH_SOURCE[0]}" > "${SOURCE_HASHES}"
A15_5_TARGET_XO_BUILD="RUNNING"
write_status

trap - ERR
set +e
vivado -mode batch -nolog -nojournal -source "${PACKAGE_TCL}" -tclargs "${PART_NAME}" \
    2>&1 | tee "${PACKAGE_LOG}"
package_exit="${PIPESTATUS[0]}"
set -e
trap unexpected_error ERR
if [[ "${package_exit}" -ne 0 ]]; then
    A15_5_TARGET_XO_BUILD="FAIL"
    fail 9 "Vivado target XO packaging failed with exit ${package_exit}"
fi

for generated in "${XO_PATH}" "${KERNEL_XML}" "${COMPONENT_XML}"; do
    [[ -s "${generated}" ]] || {
        A15_5_TARGET_XO_BUILD="FAIL"
        fail 10 "generated artifact is missing or empty: ${generated}"
    }
done
unzip -t "${XO_PATH}" >/dev/null || fail 10 "XO archive integrity failed"
grep -Fxq "TARGET_PART_USED=1" "${PACKAGE_LOG}" || fail 10 "exact target part was not used"
grep -Fxq "A15_5_TARGET_XO_PACKAGE=PASS" "${PACKAGE_LOG}" || fail 10 "package PASS marker missing"

unzip -p "${XO_PATH}" '*/kernel.xml' > "${INTERNAL_KERNEL_XML}"
unzip -p "${XO_PATH}" 'ip_repo/*/component.xml' > "${INTERNAL_COMPONENT_XML}"
[[ -s "${INTERNAL_KERNEL_XML}" && -s "${INTERNAL_COMPONENT_XML}" ]] ||
    fail 11 "XO internal metadata is missing"
cmp -s "${KERNEL_XML}" "${INTERNAL_KERNEL_XML}" || fail 11 "kernel.xml copy mismatch"
cmp -s "${COMPONENT_XML}" "${INTERNAL_COMPONENT_XML}" || fail 11 "component.xml copy mismatch"

python3 "${VALIDATOR}" \
    --kernel-xml "${KERNEL_XML}" \
    --component-xml "${COMPONENT_XML}" \
    --wrapper-rtl "${WRAPPER_RTL}" \
    --package-tcl "${PACKAGE_TCL}" \
    --kernel-name "${KERNEL_NAME}" \
    --target-part "${PART_NAME}" > "${VALIDATION_LOG}" 2>&1 || {
        A15_5_TARGET_XO_VALIDATION="FAIL"
        fail 12 "XO metadata validation failed"
    }
grep -Fxq "A15_5_TARGET_XO_METADATA_VALIDATION=PASS" "${VALIDATION_LOG}" ||
    fail 12 "XO metadata PASS marker missing"

XO_SHA256="$(sha256sum "${XO_PATH}" | awk '{print $1}')"
sha256sum "${XO_PATH}" "${KERNEL_XML}" "${COMPONENT_XML}" \
    "${INTERNAL_KERNEL_XML}" "${INTERNAL_COMPONENT_XML}" > "${ARTIFACT_HASHES}"
A15_5_TARGET_XO_BUILD="PASS"
A15_5_TARGET_XO_VALIDATION="PASS"
write_status
cat >> "${STATUS}" <<EOF
SOURCE_SHA256=${SOURCE_HASHES}
ARTIFACT_SHA256=${ARTIFACT_HASHES}
PACKAGE_LOG=${PACKAGE_LOG}
VALIDATION_LOG=${VALIDATION_LOG}
NO_VPP_LINK=1
NO_XCLBIN=1
NO_FPGA_ACCESS=1
EOF

echo "A15_5_TARGET_XO_BUILD=PASS"
echo "A15_5_TARGET_XO_VALIDATION=PASS"
echo "XO=${XO_PATH}"
echo "XO_SHA256=${XO_SHA256}"
echo "STATUS=${STATUS}"
