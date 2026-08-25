#!/usr/bin/env bash
# Stage 2N-A14.5 exact-target XO-only runner, Vivado 2020.2-compatible gate.
#
# This version accepts the observed Vivado 2020.2 kernel.xml port range only
# after independently proving 64-bit addressing from RTL, IP-XACT bus/model
# parameters and address space, physical address ports, and the TABLE_BASE
# global-memory argument.  It does not invoke v++, link or generate an xclbin,
# bind physical HBM, open XRT, touch a device, program/reset an FPGA, or
# overwrite an earlier A14/A14.5 build or result.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

VITIS_SETTINGS="${VITIS_SETTINGS:-/opt/Xilinx/Vitis/2020.2/settings64.sh}"
PART_NAME="xcvu37p-fsvh2892-2L-e"
KERNEL_NAME="dlrm_f37x_rtl_kernel_stage2n_a14_v2"

PACKAGE_TCL="${REPO_ROOT}/scripts/package_stage2n_a14_rtl_kernel_v4.tcl"
VALIDATOR="${REPO_ROOT}/scripts/validate_stage2n_a14_5_xo_v2.py"
RUNNER_SCRIPT="${REPO_ROOT}/scripts/build_stage2n_a14_5_target_xo_v2.sh"
LOOKUP_RTL="${REPO_ROOT}/rtl/hbm/dlrm_hbm_embedding_lookup_stage2n_a14_v2.sv"
WRAPPER_RTL="${REPO_ROOT}/rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a14_v2.sv"

XO_DIR="${REPO_ROOT}/build/stage2n_a14/xo_v3"
XO_PATH="${XO_DIR}/${KERNEL_NAME}.xo"
KERNEL_XML="${XO_DIR}/kernel.xml"
COMPONENT_XML="${XO_DIR}/dlrm_f37x_stage2n_a14_ip_v3/component.xml"

RESULT_ROOT="${REPO_ROOT}/results/stage2n_a14_5/target_xo_v2"
LOG_DIR="${RESULT_ROOT}/logs"
STATUS="${RESULT_ROOT}/a14_5_target_xo_v2_status.txt"
SOURCE_HASH_OUTPUT="${RESULT_ROOT}/a14_5_target_xo_v2_sources.sha256"
ARTIFACT_HASH_OUTPUT="${RESULT_ROOT}/a14_5_target_xo_v2_artifacts.sha256"
PACKAGE_LOG="${LOG_DIR}/vivado_package_xo_v2.log"
VALIDATION_LOG="${LOG_DIR}/xo_metadata_validation_v2.log"
TOOL_VERSION_LOG="${LOG_DIR}/tool_versions.log"
GIT_STATUS_FILE="${RESULT_ROOT}/git_status_porcelain.txt"
INTERNAL_KERNEL_XML="${RESULT_ROOT}/kernel_xml_inside_xo.xml"
INTERNAL_COMPONENT_XML="${RESULT_ROOT}/component_xml_inside_xo.xml"

A14_5_TARGET_XO_BUILD="BLOCKED_NOT_RUN"
A14_5_TABLE_BASE_ABI="NOT_VALIDATED"
A14_5_AXI_ADDR_WIDTH_EVIDENCE="NOT_VALIDATED"
KERNEL_XML_PORT_RANGE="NOT_AVAILABLE"
FAIL_REASON="NONE"
CURRENT_BRANCH="NOT_RECORDED"
CURRENT_HEAD="NOT_RECORDED"

write_status()
{
    cat > "${STATUS}" <<EOF
A14_5_FLOW=STAGE2N_A14_5_TARGET_XO_V2_RANGE_COMPAT
A14_5_TARGET_RUNNER_VERSION=V2_VIVADO_2020_2_RANGE_COMPAT
A14_5_TARGET_XO_BUILD=${A14_5_TARGET_XO_BUILD}
A14_5_TABLE_BASE_ABI=${A14_5_TABLE_BASE_ABI}
A14_5_AXI_ADDR_WIDTH_EVIDENCE=${A14_5_AXI_ADDR_WIDTH_EVIDENCE}
KERNEL_XML_PORT_RANGE=${KERNEL_XML_PORT_RANGE}
A14_5_VPP_LINK=NOT_RUN
A14_5_XCLBIN=NOT_GENERATED
A14_5_PHYSICAL_HBM=NOT_VALIDATED
A14_5_HOST_BUILD=NOT_RUN
A14_5_HOST_EXECUTION=NOT_RUN
A14_5_FPGA_PROGRAMMING=NOT_RUN
A14_5_FPGA_RESET=NOT_RUN
A14_5_FPGA_DEVICE_ACCESS=NONE
A14_5_READY_FOR_BOARD=NO
FAIL_REASON=${FAIL_REASON}
GIT_BRANCH=${CURRENT_BRANCH}
GIT_HEAD=${CURRENT_HEAD}
TARGET_PART=${PART_NAME}
KERNEL=${KERNEL_NAME}
CONTROL_INTERFACE=s_axi_control
MEMORY_INTERFACE=m_axi_gmem
M_AXI_DATA_WIDTH=128
M_AXI_ADDR_WIDTH=64
TABLE_BASE_OFFSET=0x18
TABLE_BASE_WIDTH=64
XO=${XO_PATH}
EOF
}

fail()
{
    local code="$1"
    shift
    FAIL_REASON="$*"
    write_status
    echo "ERROR: ${FAIL_REASON}" >&2
    echo "STATUS=${STATUS}" >&2
    exit "${code}"
}

unexpected_error()
{
    local code="$?"
    local line="${BASH_LINENO[0]:-UNKNOWN}"
    if [[ "${FAIL_REASON}" == "NONE" ]]; then
        if [[ "${A14_5_TARGET_XO_BUILD}" == "RUNNING" ]]; then
            A14_5_TARGET_XO_BUILD="FAIL"
        fi
        FAIL_REASON="unexpected command failure at line ${line}"
        write_status
    fi
    exit "${code}"
}

[[ ! -e "${XO_DIR}" ]] || {
    echo "ERROR: refusing to overwrite existing A14.5 XO directory: ${XO_DIR}" >&2
    exit 2
}
[[ ! -e "${RESULT_ROOT}" ]] || {
    echo "ERROR: refusing to overwrite existing A14.5 result root: ${RESULT_ROOT}" >&2
    exit 3
}

mkdir -p "${LOG_DIR}"
write_status
trap unexpected_error ERR

for required in \
    "${VITIS_SETTINGS}" \
    "${PACKAGE_TCL}" \
    "${VALIDATOR}" \
    "${RUNNER_SCRIPT}" \
    "${LOOKUP_RTL}" \
    "${WRAPPER_RTL}"
do
    [[ -f "${required}" ]] || fail 4 "required input is missing: ${required}"
done

# shellcheck disable=SC1090
source "${VITIS_SETTINGS}" >/dev/null

for tool in git sha256sum vivado unzip python3 cmp grep sed wc tee; do
    command -v "${tool}" >/dev/null 2>&1 ||
        fail 5 "required tool unavailable after sourcing Vitis: ${tool}"
done

CURRENT_BRANCH="$(cd "${REPO_ROOT}" && git symbolic-ref --short HEAD 2>/dev/null || echo DETACHED)"
CURRENT_HEAD="$(cd "${REPO_ROOT}" && git rev-parse HEAD)"
(cd "${REPO_ROOT}" && git status --porcelain) > "${GIT_STATUS_FILE}"
A14_5_TARGET_XO_BUILD="RUNNING"
write_status

vivado -version > "${TOOL_VERSION_LOG}" 2>&1
sha256sum \
    "${LOOKUP_RTL}" \
    "${WRAPPER_RTL}" \
    "${PACKAGE_TCL}" \
    "${VALIDATOR}" \
    "${RUNNER_SCRIPT}" > "${SOURCE_HASH_OUTPUT}"

# ERR must be disabled around the expected return-code capture.  With
# `set +e` alone, an ERR trap still fires for a failed pipe under pipefail.
trap - ERR
set +e
vivado -mode batch -nolog -nojournal \
    -source "${PACKAGE_TCL}" 2>&1 | tee "${PACKAGE_LOG}"
package_exit="${PIPESTATUS[0]}"
set -e
trap unexpected_error ERR
if [[ "${package_exit}" -ne 0 ]]; then
    A14_5_TARGET_XO_BUILD="FAIL"
    fail 6 "A14.5 target-part XO v2 packaging failed"
fi

if [[ ! -s "${XO_PATH}" || ! -s "${KERNEL_XML}" ||
      ! -s "${COMPONENT_XML}" ]]; then
    A14_5_TARGET_XO_BUILD="FAIL"
    fail 7 "A14.5 XO v2 or generated metadata is missing or empty"
fi
unzip -t "${XO_PATH}" >/dev/null || {
    A14_5_TARGET_XO_BUILD="FAIL"
    fail 8 "A14.5 XO v2 archive integrity failed"
}
grep -Fxq "TARGET_PART_USED=1" "${PACKAGE_LOG}" || {
    A14_5_TARGET_XO_BUILD="FAIL"
    fail 9 "A14.5 XO v2 was not packaged with the exact VU37P target part"
}
grep -Fxq "STAGE2N_A14_5_TABLE_BASE_XO_PACKAGE_V2=PASS" "${PACKAGE_LOG}" || {
    A14_5_TARGET_XO_BUILD="FAIL"
    fail 9 "A14.5 XO v2 package PASS marker is missing"
}

unzip -p "${XO_PATH}" '*/kernel.xml' > "${INTERNAL_KERNEL_XML}"
unzip -p "${XO_PATH}" 'ip_repo/*/component.xml' > "${INTERNAL_COMPONENT_XML}"
[[ -s "${INTERNAL_KERNEL_XML}" ]] || {
    A14_5_TARGET_XO_BUILD="FAIL"
    fail 10 "kernel.xml is missing inside the XO v2"
}
[[ -s "${INTERNAL_COMPONENT_XML}" ]] || {
    A14_5_TARGET_XO_BUILD="FAIL"
    fail 10 "component.xml is missing inside the XO v2"
}
cmp -s "${KERNEL_XML}" "${INTERNAL_KERNEL_XML}" || {
    A14_5_TARGET_XO_BUILD="FAIL"
    fail 10 "standalone and in-XO kernel.xml differ"
}
cmp -s "${COMPONENT_XML}" "${INTERNAL_COMPONENT_XML}" || {
    A14_5_TARGET_XO_BUILD="FAIL"
    fail 10 "standalone and in-XO component.xml differ"
}

python3 "${VALIDATOR}" \
    --kernel-xml "${KERNEL_XML}" \
    --component-xml "${COMPONENT_XML}" \
    --wrapper-rtl "${WRAPPER_RTL}" \
    --kernel-name "${KERNEL_NAME}" > "${VALIDATION_LOG}" 2>&1 || {
        A14_5_TARGET_XO_BUILD="FAIL"
        fail 11 "A14.5 XO v2 metadata validation failed"
    }

grep -Fxq "A14_5_TARGET_XO_METADATA_VALIDATION_V2=PASS" \
    "${VALIDATION_LOG}" || {
        A14_5_TARGET_XO_BUILD="FAIL"
        fail 12 "A14.5 XO v2 metadata PASS marker is missing"
    }

KERNEL_XML_PORT_RANGE="$(sed -n 's/^KERNEL_XML_PORT_RANGE=//p' "${VALIDATION_LOG}")"
range_record_count="$(grep -c '^KERNEL_XML_PORT_RANGE=' "${VALIDATION_LOG}" || true)"
if [[ -z "${KERNEL_XML_PORT_RANGE}" ||
      "${range_record_count}" -ne 1 ]]; then
    A14_5_TARGET_XO_BUILD="FAIL"
    fail 13 "A14.5 kernel.xml port range record is missing or duplicated"
fi
grep -Fxq \
    "AXI_ADDRESS_WIDTH_EVIDENCE=RTL_COMPONENT_IPXACT_POINTER_CONSISTENT" \
    "${VALIDATION_LOG}" || {
        A14_5_TARGET_XO_BUILD="FAIL"
        fail 13 "A14.5 64-bit AXI address evidence is incomplete"
    }

sha256sum \
    "${XO_PATH}" \
    "${KERNEL_XML}" \
    "${COMPONENT_XML}" \
    "${INTERNAL_KERNEL_XML}" \
    "${INTERNAL_COMPONENT_XML}" > "${ARTIFACT_HASH_OUTPUT}"

A14_5_TARGET_XO_BUILD="PASS"
A14_5_TABLE_BASE_ABI="PASS"
A14_5_AXI_ADDR_WIDTH_EVIDENCE="PASS"
write_status

cat >> "${STATUS}" <<EOF
SOURCE_SHA256=${SOURCE_HASH_OUTPUT}
ARTIFACT_SHA256=${ARTIFACT_HASH_OUTPUT}
PACKAGE_LOG=${PACKAGE_LOG}
VALIDATION_LOG=${VALIDATION_LOG}
XO_SIZE_BYTES=$(wc -c < "${XO_PATH}")
KERNEL_XML_ARGUMENT_COUNT=6
COMPONENT_XML_REGISTER_COUNT=7
TABLE_BASE_ADDRESS_QUALIFIER=1
TABLE_BASE_PORT=m_axi_gmem
IPXACT_ADDRESS_SPACE_BYTES=18446744073709551616
KERNEL_XML_PORT_RANGE_ROLE=DESCRIPTIVE_NOT_SOLE_WIDTH_PROOF
NO_VPP_LINK=1
NO_XCLBIN=1
NO_PHYSICAL_HBM_BINDING=1
NO_FPGA_ACCESS=1
EOF

echo "A14_5_TARGET_XO_BUILD=PASS"
echo "A14_5_TABLE_BASE_ABI=PASS"
echo "A14_5_AXI_ADDR_WIDTH_EVIDENCE=PASS"
echo "KERNEL_XML_PORT_RANGE=${KERNEL_XML_PORT_RANGE}"
echo "A14_5_VPP_LINK=NOT_RUN"
echo "A14_5_XCLBIN=NOT_GENERATED"
echo "A14_5_PHYSICAL_HBM=NOT_VALIDATED"
echo "A14_5_FPGA_DEVICE_ACCESS=NONE"
echo "STATUS=${STATUS}"
