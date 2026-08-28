#!/usr/bin/env bash
# Revalidate one already-built, SHA256-frozen A15.5 xclbin without rebuilding
# XO/xclbin or accessing a device.  The user runs this in the controlled target
# environment; Codex does not execute it remotely.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

VITIS_SETTINGS="${VITIS_SETTINGS:-/opt/Xilinx/Vitis/2020.2/settings64.sh}"
EXPECTED_BRANCH="work/stage2n-a15-hbm-pipeline-integration"
SOURCE_BUILD_HEAD="30cbf64e44fa99aa025f1a7456d739c8b5d4be6b"
KERNEL_NAME="dlrm_f37x_rtl_kernel_stage2n_a15_v1"
CU_NAME="dlrm_a15_1"
PLATFORM_VBNV="inspur_f37x_xdma_201920_3"
PART_NAME="xcvu37p-fsvh2892-2L-e"
KERNEL_FREQUENCY_MHZ="100"
EXPECTED_XO_SHA256="a88fd4bba7a534f7068cff838448c5ba7f330e5bec27c8c2697525c9dedee019"
EXPECTED_XCLBIN_SHA256="23ee48c91b3dfb5b68b3372ac49fc6607f203cf01d3b9fcfe04b4ea42be02356"

XO_PATH="${A15_5_EXISTING_XO:-${REPO_ROOT}/build/stage2n_a15_5/xo_v1/${KERNEL_NAME}.xo}"
XCLBIN_PATH="${A15_5_EXISTING_XCLBIN:-${REPO_ROOT}/build/stage2n_a15_5/link_v1/hw/${KERNEL_NAME}.xclbin}"
KERNEL_XML="${A15_5_EXISTING_KERNEL_XML:-${REPO_ROOT}/build/stage2n_a15_5/xo_v1/kernel.xml}"
XO_STATUS="${A15_5_EXISTING_XO_STATUS:-${REPO_ROOT}/results/stage2n_a15_5/target_xo_v1/a15_5_target_xo_v1_status.txt}"
VPP_LOG="${A15_5_EXISTING_VPP_LOG:-${REPO_ROOT}/results/stage2n_a15_5/target_link_v1/logs/vpp_link.log}"
ROUTED_DCP_ROOT="${A15_5_EXISTING_DCP_ROOT:-${REPO_ROOT}/build/stage2n_a15_5/link_v1/_x}"

CONFIG="${REPO_ROOT}/config/stage2n_a15_5_target_v1.cfg"
LINK_V1="${REPO_ROOT}/scripts/link_stage2n_a15_5_target_v1.sh"
VALIDATOR_V2="${REPO_ROOT}/scripts/validate_stage2n_a15_5_xclbin_v2.py"
POST_ROUTE_TCL="${REPO_ROOT}/scripts/report_stage2n_a15_5_vitis_post_route_v1.tcl"
WRAPPER_RTL="${REPO_ROOT}/rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a15_v1.sv"

RESULT_ROOT="${REPO_ROOT}/results/stage2n_a15_5/target_xclbin_revalidation_v2"
LOG_DIR="${RESULT_ROOT}/logs"
STATUS="${RESULT_ROOT}/a15_5_target_xclbin_revalidation_v2_status.txt"
TOOL_LOG="${LOG_DIR}/tool_versions.log"
XCLBIN_INFO="${RESULT_ROOT}/${KERNEL_NAME}.xclbin.info"
CONNECTIVITY_JSON="${RESULT_ROOT}/xclbin_connectivity.json"
MEM_TOPOLOGY_JSON="${RESULT_ROOT}/xclbin_mem_topology.json"
IP_LAYOUT_JSON="${RESULT_ROOT}/xclbin_ip_layout.json"
LINK_CONTRACT="${RESULT_ROOT}/link_contract.txt"
VALIDATION_LOG="${LOG_DIR}/xclbin_metadata_validation_v2.log"
POST_ROUTE_LOG="${LOG_DIR}/vivado_post_route_report.log"
POST_ROUTE_DIR="${RESULT_ROOT}/post_route"
POST_ROUTE_METRICS="${POST_ROUTE_DIR}/post_route_metrics.txt"
SOURCE_HASHES="${RESULT_ROOT}/a15_5_revalidation_v2_sources.sha256"
ARTIFACT_HASHES="${RESULT_ROOT}/a15_5_revalidation_v2_artifacts.sha256"
GIT_STATUS_FILE="${RESULT_ROOT}/git_status_porcelain.txt"

A15_5_TARGET_XO_BUILD="NOT_VALIDATED"
A15_5_TARGET_XO_VALIDATION="NOT_VALIDATED"
A15_5_TARGET_LINK="NOT_VALIDATED"
A15_5_XCLBIN="NOT_VALIDATED"
A15_5_XCLBIN_VALIDATION="NOT_RUN"
A15_5_TARGET_TIMING="NOT_RUN"
FAIL_REASON="NONE"
CURRENT_BRANCH="NOT_RECORDED"
CURRENT_HEAD="NOT_RECORDED"
XCLBIN_UUID="NOT_AVAILABLE"
ROUTED_DCP="NOT_AVAILABLE"

write_status()
{
    cat > "${STATUS}" <<EOF
A15_5_FLOW=TARGET_XCLBIN_REVALIDATION_V2
A15_5_SOURCE_BUILD_HEAD=${SOURCE_BUILD_HEAD}
A15_5_TARGET_XO_BUILD=${A15_5_TARGET_XO_BUILD}
A15_5_TARGET_XO_VALIDATION=${A15_5_TARGET_XO_VALIDATION}
A15_5_TARGET_LINK=${A15_5_TARGET_LINK}
A15_5_XCLBIN=${A15_5_XCLBIN}
A15_5_XCLBIN_VALIDATION=${A15_5_XCLBIN_VALIDATION}
A15_5_TARGET_TIMING=${A15_5_TARGET_TIMING}
A15_5_TARGET_REBUILD_REQUIRED=NO
A15_5_FPGA_PROGRAMMING=NOT_RUN
A15_5_HOST_EXECUTION=NOT_RUN
A15_5_PHYSICAL_HBM=NOT_VALIDATED
A15_5_BOARD=NOT_RUN
A15_5_PERFORMANCE=NOT_CLAIMED
FPGA_DEVICE_ACCESS=NONE
FAIL_REASON=${FAIL_REASON}
GIT_BRANCH=${CURRENT_BRANCH}
GIT_HEAD=${CURRENT_HEAD}
KERNEL=${KERNEL_NAME}
COMPUTE_UNIT=${CU_NAME}
PLATFORM_VBNV=${PLATFORM_VBNV}
TARGET_PART=${PART_NAME}
REQUESTED_CLOCK_MHZ=${KERNEL_FREQUENCY_MHZ}
CONNECTIVITY=${CU_NAME}.m_axi_gmem:HBM[0]
XO=${XO_PATH}
XO_SHA256=${EXPECTED_XO_SHA256}
XCLBIN=${XCLBIN_PATH}
XCLBIN_SHA256=${EXPECTED_XCLBIN_SHA256}
XCLBIN_UUID=${XCLBIN_UUID}
ROUTED_DCP=${ROUTED_DCP}
EOF
}

fail()
{
    local code="$1"
    shift
    FAIL_REASON="$*"
    [[ -d "${RESULT_ROOT}" ]] && write_status
    echo "ERROR: ${FAIL_REASON}" >&2
    exit "${code}"
}

unexpected_error()
{
    local code="$?"
    local line="${BASH_LINENO[0]:-UNKNOWN}"
    if [[ "${FAIL_REASON}" == "NONE" ]]; then
        FAIL_REASON="unexpected command failure at line ${line}"
        [[ -d "${RESULT_ROOT}" ]] && write_status
    fi
    exit "${code}"
}

[[ ! -e "${RESULT_ROOT}" ]] || {
    echo "ERROR: refusing to overwrite revalidation result root: ${RESULT_ROOT}" >&2
    exit 2
}
for required in "${VITIS_SETTINGS}" "${XO_PATH}" "${XCLBIN_PATH}" "${KERNEL_XML}" \
    "${XO_STATUS}" "${VPP_LOG}" "${ROUTED_DCP_ROOT}" "${CONFIG}" "${LINK_V1}" \
    "${VALIDATOR_V2}" "${POST_ROUTE_TCL}" "${WRAPPER_RTL}"; do
    [[ -e "${required}" ]] || {
        echo "ERROR: required retained input is missing: ${required}" >&2
        exit 3
    }
done

confirmation="${A15_5_REVALIDATE_CONFIRM:-}"
if [[ -z "${confirmation}" ]]; then
    if [[ ! -t 0 ]]; then
        echo "ERROR: interactive confirmation unavailable; set A15_5_REVALIDATE_CONFIRM=yes" >&2
        exit 4
    fi
    read -r -p "Revalidate the existing fixed-SHA A15.5 xclbin without link/device access? [yes/no] " confirmation
fi
[[ "${confirmation}" == "yes" ]] || {
    echo "A15.5 xclbin revalidation cancelled safely."
    exit 0
}

mkdir -p "${LOG_DIR}"
trap unexpected_error ERR
CURRENT_BRANCH="$(cd "${REPO_ROOT}" && git symbolic-ref --short HEAD 2>/dev/null || echo DETACHED)"
CURRENT_HEAD="$(cd "${REPO_ROOT}" && git rev-parse HEAD)"
[[ "${CURRENT_BRANCH}" == "${EXPECTED_BRANCH}" ]] || fail 5 "wrong branch: ${CURRENT_BRANCH}"
(cd "${REPO_ROOT}" && git merge-base --is-ancestor "${SOURCE_BUILD_HEAD}" HEAD) ||
    fail 5 "source-build HEAD is not an ancestor of current HEAD"
(cd "${REPO_ROOT}" && git diff --quiet "${SOURCE_BUILD_HEAD}" -- \
    rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a15_v1.sv \
    scripts/package_stage2n_a15_5_rtl_kernel_v1.tcl \
    scripts/build_stage2n_a15_5_target_xo_v1.sh \
    scripts/link_stage2n_a15_5_target_v1.sh \
    config/stage2n_a15_5_target_v1.cfg) ||
    fail 5 "frozen build inputs differ from source-build HEAD"
(cd "${REPO_ROOT}" && git diff --quiet && git diff --cached --quiet) ||
    fail 5 "tracked worktree/index must be clean before revalidation"
(cd "${REPO_ROOT}" && git status --porcelain) > "${GIT_STATUS_FILE}"

actual_xo_sha256="$(sha256sum "${XO_PATH}" | awk '{print $1}')"
actual_xclbin_sha256="$(sha256sum "${XCLBIN_PATH}" | awk '{print $1}')"
[[ "${actual_xo_sha256}" == "${EXPECTED_XO_SHA256}" ]] || fail 6 "XO SHA256 mismatch"
[[ "${actual_xclbin_sha256}" == "${EXPECTED_XCLBIN_SHA256}" ]] || fail 6 "xclbin SHA256 mismatch"
grep -Fxq "A15_5_TARGET_XO_BUILD=PASS" "${XO_STATUS}" || fail 6 "XO PASS status missing"
grep -Fxq "A15_5_TARGET_XO_VALIDATION=PASS" "${XO_STATUS}" || fail 6 "XO validation PASS status missing"
grep -Eiq '(run|link|vitis build).*completed|total elapsed time' "${VPP_LOG}" ||
    fail 6 "v++ completion marker missing"
[[ "$(grep -cE '^ERROR:' "${VPP_LOG}" || true)" == "0" ]] || fail 6 "v++ log contains anchored ERROR lines"
A15_5_TARGET_XO_BUILD="PASS"
A15_5_TARGET_XO_VALIDATION="PASS"
write_status

# shellcheck disable=SC1090
source "${VITIS_SETTINGS}" >/dev/null
for tool in git sha256sum vivado xclbinutil python3 awk grep find hostname date; do
    command -v "${tool}" >/dev/null 2>&1 || fail 7 "required tool unavailable: ${tool}"
done
{
    echo "VITIS_SETTINGS=${VITIS_SETTINGS}"
    echo "HOSTNAME=$(hostname)"
    echo "DATE=$(date -Iseconds)"
    vivado -version
    xclbinutil --version
} > "${TOOL_LOG}" 2>&1

cat > "${LINK_CONTRACT}" <<EOF
KERNEL=${KERNEL_NAME}
COMPUTE_UNIT=${CU_NAME}
PLATFORM_VBNV=${PLATFORM_VBNV}
TARGET_PART=${PART_NAME}
KERNEL_FREQUENCY_MHZ=${KERNEL_FREQUENCY_MHZ}
CONNECTIVITY=${CU_NAME}.m_axi_gmem:HBM[0]
M_AXI_MASTER_COUNT=1
EOF

xclbinutil --quiet --force --info "${XCLBIN_INFO}" --input "${XCLBIN_PATH}" || fail 8 "xclbin info extraction failed"
xclbinutil --quiet --force --dump-section "CONNECTIVITY:JSON:${CONNECTIVITY_JSON}" --input "${XCLBIN_PATH}" || fail 8 "CONNECTIVITY extraction failed"
xclbinutil --quiet --force --dump-section "MEM_TOPOLOGY:JSON:${MEM_TOPOLOGY_JSON}" --input "${XCLBIN_PATH}" || fail 8 "MEM_TOPOLOGY extraction failed"
xclbinutil --quiet --force --dump-section "IP_LAYOUT:JSON:${IP_LAYOUT_JSON}" --input "${XCLBIN_PATH}" || fail 8 "IP_LAYOUT extraction failed"

python3 "${VALIDATOR_V2}" \
    --connectivity "${CONNECTIVITY_JSON}" \
    --mem-topology "${MEM_TOPOLOGY_JSON}" \
    --ip-layout "${IP_LAYOUT_JSON}" \
    --xclbin-info "${XCLBIN_INFO}" \
    --config "${CONFIG}" \
    --link-script "${LINK_V1}" \
    --link-contract "${LINK_CONTRACT}" \
    --kernel-xml "${KERNEL_XML}" \
    --kernel "${KERNEL_NAME}" \
    --compute-unit "${CU_NAME}" \
    --platform "${PLATFORM_VBNV}" \
    --part "${PART_NAME}" \
    --clock-mhz "${KERNEL_FREQUENCY_MHZ}" > "${VALIDATION_LOG}" 2>&1 ||
    fail 9 "xclbin v2 metadata validation failed"
grep -Fxq "A15_5_XCLBIN_METADATA_VALIDATION_V2=PASS" "${VALIDATION_LOG}" ||
    fail 9 "xclbin v2 metadata PASS marker missing"
XCLBIN_UUID="$(awk -F= '$1 == "XCLBIN_UUID" {print $2; exit}' "${VALIDATION_LOG}")"
A15_5_XCLBIN_VALIDATION="PASS"
write_status

ROUTED_DCP="$(find "${ROUTED_DCP_ROOT}" -type f \( -name '*_routed.dcp' -o -name '*route_design*.dcp' \) -print -quit 2>/dev/null || true)"
[[ -n "${ROUTED_DCP}" && -s "${ROUTED_DCP}" ]] || fail 10 "routed DCP not found"
export A15_5_ROUTED_DCP="${ROUTED_DCP}"
export A15_5_REPORT_DIR="${POST_ROUTE_DIR}"
vivado -mode batch -nolog -nojournal -source "${POST_ROUTE_TCL}" > "${POST_ROUTE_LOG}" 2>&1 ||
    fail 10 "read-only routed report extraction failed"
[[ -s "${POST_ROUTE_METRICS}" ]] || fail 10 "post-route metrics missing"

metric()
{
    local key="$1"
    awk -F= -v key="${key}" '$1 == key {sub(/^[^=]*=/, ""); print; exit}' "${POST_ROUTE_METRICS}"
}
actual_part="$(metric TARGET_PART)"
wns="$(metric WNS_NS)"
tns="$(metric TNS_NS)"
failing_endpoints="$(metric FAILING_ENDPOINTS)"
[[ "${actual_part}" == "${PART_NAME}" ]] || fail 11 "routed target part mismatch"
[[ -n "${wns}" && "${wns}" != "NOT_PARSED" ]] || fail 11 "setup WNS not parsed"
if awk -v wns="${wns}" -v tns="${tns}" -v endpoints="${failing_endpoints}" \
    'BEGIN {exit !((wns + 0.0) >= 0.0 && (tns + 0.0) == 0.0 && (endpoints + 0) == 0)}'; then
    A15_5_TARGET_TIMING="PASS"
else
    A15_5_TARGET_TIMING="FAIL"
    fail 11 "100 MHz setup timing failed"
fi

A15_5_TARGET_LINK="PASS"
A15_5_XCLBIN="PASS"
sha256sum "${VALIDATOR_V2}" "${CONFIG}" "${LINK_V1}" "${POST_ROUTE_TCL}" \
    "${BASH_SOURCE[0]}" > "${SOURCE_HASHES}"
sha256sum "${XO_PATH}" "${XCLBIN_PATH}" "${CONNECTIVITY_JSON}" \
    "${MEM_TOPOLOGY_JSON}" "${IP_LAYOUT_JSON}" "${POST_ROUTE_METRICS}" > "${ARTIFACT_HASHES}"
write_status
cat >> "${STATUS}" <<EOF
WNS_NS=${wns}
TNS_NS=${tns}
FAILING_ENDPOINTS=${failing_endpoints}
WORST_STARTPOINT=$(metric WORST_STARTPOINT)
WORST_ENDPOINT=$(metric WORST_ENDPOINT)
LUT=$(metric LUT)
FF=$(metric FF)
RAMB36=$(metric RAMB36)
RAMB18=$(metric RAMB18)
URAM=$(metric URAM)
DSP=$(metric DSP)
LATCH=$(metric LATCH)
DRC_ERROR_COUNT=$(metric DRC_ERROR_COUNT)
DRC_CRITICAL_WARNING_COUNT=$(metric DRC_CRITICAL_WARNING_COUNT)
METHODOLOGY_ERROR_COUNT=$(metric METHODOLOGY_ERROR_COUNT)
METHODOLOGY_CRITICAL_WARNING_COUNT=$(metric METHODOLOGY_CRITICAL_WARNING_COUNT)
SOURCE_SHA256=${SOURCE_HASHES}
ARTIFACT_SHA256=${ARTIFACT_HASHES}
VALIDATION_LOG=${VALIDATION_LOG}
POST_ROUTE_METRICS=${POST_ROUTE_METRICS}
EOF

echo "A15_5_TARGET_XO_BUILD=PASS"
echo "A15_5_TARGET_XO_VALIDATION=PASS"
echo "A15_5_TARGET_LINK=PASS"
echo "A15_5_XCLBIN=PASS"
echo "A15_5_XCLBIN_VALIDATION=PASS"
echo "A15_5_TARGET_TIMING=PASS"
echo "A15_5_TARGET_REBUILD_REQUIRED=NO"
echo "A15_5_PHYSICAL_HBM=NOT_VALIDATED"
echo "FPGA_DEVICE_ACCESS=NONE"
echo "STATUS=${STATUS}"
