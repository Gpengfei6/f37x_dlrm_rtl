#!/usr/bin/env bash
# Stage 2N-A14.6 exact-target link-only runner.
#
# Consumes the accepted A14.5 v2 XO, links one F37X hardware xclbin with
# m_axi_gmem mapped to HBM[0], validates linked metadata, and reports routed
# timing. It never rebuilds the XO, opens a device, programs/resets an FPGA,
# runs a Host application, or performs a physical HBM transaction.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

VITIS_SETTINGS="${VITIS_SETTINGS:-/opt/Xilinx/Vitis/2020.2/settings64.sh}"
PLATFORM="${PLATFORM:-/opt/xilinx/platforms/inspur_f37x_xdma_201920_3/inspur_f37x_xdma_201920_3.xpfm}"
PLATFORM_VBNV="inspur_f37x_xdma_201920_3"
PART_NAME="xcvu37p-fsvh2892-2L-e"
EXPECTED_BRANCH="work/stage2n-a13-cycle-counter"
KERNEL_NAME="dlrm_f37x_rtl_kernel_stage2n_a14_v2"
CU_NAME="dlrm_a14_1"
KERNEL_FREQUENCY_MHZ="${KERNEL_FREQUENCY_MHZ:-100}"
JOBS="${JOBS:-8}"

ACCEPTED_XO_SHA256="7c05895b4ef7f3b3e1169d722f88a4ea5103ae9d5cb5283fd0372e7bc3e43dea"
ACCEPTED_KERNEL_XML_SHA256="c256715325344a6ee75dd1be5739cc6d5c2f5813452df7689f0272e1a67c9df3"
ACCEPTED_COMPONENT_XML_SHA256="4971079d0b71d6ed848a581770bd204ea339bcc9d4dd63c8de85f483ed8d4b79"

XO_DIR="${REPO_ROOT}/build/stage2n_a14/xo_v3"
XO_PATH="${XO_DIR}/${KERNEL_NAME}.xo"
KERNEL_XML="${XO_DIR}/kernel.xml"
COMPONENT_XML="${XO_DIR}/dlrm_f37x_stage2n_a14_ip_v3/component.xml"
WRAPPER_RTL="${REPO_ROOT}/rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a14_v2.sv"
CONFIG="${REPO_ROOT}/config/stage2n_a14_6_target_v1.cfg"
XO_VALIDATOR="${REPO_ROOT}/scripts/validate_stage2n_a14_5_xo_v2.py"
XCLBIN_VALIDATOR="${REPO_ROOT}/scripts/validate_stage2n_a14_6_xclbin_v1.py"
POST_ROUTE_TCL="${REPO_ROOT}/scripts/report_stage2n_a14_vitis_post_route_v1.tcl"

BUILD_ROOT="${REPO_ROOT}/build/stage2n_a14_6/link_v1"
TEMP_DIR="${BUILD_ROOT}/_x"
OUTPUT_DIR="${BUILD_ROOT}/hw"
XCLBIN_PATH="${OUTPUT_DIR}/${KERNEL_NAME}.xclbin"

RESULT_ROOT="${REPO_ROOT}/results/stage2n_a14_6/link_v1"
LOG_DIR="${RESULT_ROOT}/logs"
STATUS="${RESULT_ROOT}/a14_6_link_v1_status.txt"
SOURCE_HASHES="${RESULT_ROOT}/a14_6_link_v1_sources.sha256"
ARTIFACT_HASHES="${RESULT_ROOT}/a14_6_link_v1_artifacts.sha256"
GIT_STATUS_FILE="${RESULT_ROOT}/git_status_porcelain.txt"
TOOL_VERSION_LOG="${LOG_DIR}/tool_versions.log"
XO_VALIDATION_LOG="${LOG_DIR}/xo_metadata_validation.log"
VPP_LOG="${LOG_DIR}/vpp_link.log"
XCLBIN_INFO="${RESULT_ROOT}/${KERNEL_NAME}.xclbin.info"
CONNECTIVITY_JSON="${RESULT_ROOT}/xclbin_connectivity.json"
MEM_TOPOLOGY_JSON="${RESULT_ROOT}/xclbin_mem_topology.json"
IP_LAYOUT_JSON="${RESULT_ROOT}/xclbin_ip_layout.json"
XCLBIN_VALIDATION_LOG="${LOG_DIR}/xclbin_metadata_validation.log"
POST_ROUTE_LOG="${LOG_DIR}/vivado_post_route_report.log"
POST_ROUTE_DIR="${RESULT_ROOT}/post_route"
POST_ROUTE_METRICS="${POST_ROUTE_DIR}/post_route_metrics.txt"

A14_6_INPUT_XO="NOT_VALIDATED"
A14_6_TABLE_BASE_ABI="NOT_VALIDATED"
A14_6_VPP_LINK="NOT_RUN"
A14_6_XCLBIN="NOT_GENERATED"
A14_6_HBM0_LINK_MAPPING="NOT_VALIDATED"
A14_6_TARGET_TIMING="NOT_RUN"
FAIL_REASON="NONE"
CURRENT_BRANCH="NOT_RECORDED"
CURRENT_HEAD="NOT_RECORDED"
XCLBIN_UUID="NOT_AVAILABLE"
ROUTED_DCP="NOT_AVAILABLE"
VPP_ERROR_COUNT="NOT_AVAILABLE"
VPP_CRITICAL_WARNING_COUNT="NOT_AVAILABLE"

write_status()
{
    cat > "${STATUS}" <<EOF
A14_6_FLOW=STAGE2N_A14_6_LINK_ONLY_V1
A14_6_INPUT_XO=${A14_6_INPUT_XO}
A14_6_TABLE_BASE_ABI=${A14_6_TABLE_BASE_ABI}
A14_6_VPP_LINK=${A14_6_VPP_LINK}
A14_6_XCLBIN=${A14_6_XCLBIN}
A14_6_HBM0_LINK_MAPPING=${A14_6_HBM0_LINK_MAPPING}
A14_6_TARGET_TIMING=${A14_6_TARGET_TIMING}
A14_6_PHYSICAL_HBM=NOT_VALIDATED
A14_6_HOST_BUILD=NOT_RUN
A14_6_HOST_EXECUTION=NOT_RUN
A14_6_FPGA_PROGRAMMING=NOT_RUN
A14_6_FPGA_RESET=NOT_RUN
A14_6_FPGA_DEVICE_ACCESS=NONE
A14_6_READY_FOR_BOARD=NO
FAIL_REASON=${FAIL_REASON}
GIT_BRANCH=${CURRENT_BRANCH}
GIT_HEAD=${CURRENT_HEAD}
TARGET_PART=${PART_NAME}
PLATFORM=${PLATFORM}
PLATFORM_VBNV=${PLATFORM_VBNV}
KERNEL=${KERNEL_NAME}
COMPUTE_UNIT=${CU_NAME}
REQUESTED_HBM_MAPPING=m_axi_gmem_TO_HBM_0
REQUESTED_CLOCK_MHZ=${KERNEL_FREQUENCY_MHZ}
XO=${XO_PATH}
ACCEPTED_XO_SHA256=${ACCEPTED_XO_SHA256}
XCLBIN=${XCLBIN_PATH}
XCLBIN_UUID=${XCLBIN_UUID}
ROUTED_DCP=${ROUTED_DCP}
VPP_ERROR_COUNT=${VPP_ERROR_COUNT}
VPP_CRITICAL_WARNING_COUNT=${VPP_CRITICAL_WARNING_COUNT}
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
    if [[ -d "${RESULT_ROOT}" ]]; then
        echo "STATUS=${STATUS}" >&2
    fi
    exit "${code}"
}

unexpected_error()
{
    local code="$?"
    local line="${BASH_LINENO[0]:-UNKNOWN}"
    if [[ "${FAIL_REASON}" == "NONE" ]]; then
        FAIL_REASON="unexpected command failure at line ${line}"
        if [[ -d "${RESULT_ROOT}" ]]; then
            write_status
        fi
    fi
    exit "${code}"
}

[[ ! -e "${BUILD_ROOT}" ]] || {
    echo "ERROR: refusing to overwrite existing build root: ${BUILD_ROOT}" >&2
    exit 2
}
[[ ! -e "${RESULT_ROOT}" ]] || {
    echo "ERROR: refusing to overwrite existing result root: ${RESULT_ROOT}" >&2
    exit 3
}

[[ "${KERNEL_FREQUENCY_MHZ}" == "100" ]] || {
    echo "ERROR: KERNEL_FREQUENCY_MHZ is frozen at 100" >&2
    exit 4
}
[[ "${JOBS}" =~ ^[1-9][0-9]*$ ]] || {
    echo "ERROR: JOBS must be a positive integer" >&2
    exit 4
}

for required in \
    "${VITIS_SETTINGS}" \
    "${PLATFORM}" \
    "${XO_PATH}" \
    "${KERNEL_XML}" \
    "${COMPONENT_XML}" \
    "${WRAPPER_RTL}" \
    "${CONFIG}" \
    "${XO_VALIDATOR}" \
    "${XCLBIN_VALIDATOR}" \
    "${POST_ROUTE_TCL}"
do
    [[ -f "${required}" ]] || {
        echo "ERROR: required input is missing: ${required}" >&2
        exit 5
    }
done

EXPECTED_NK="nk=${KERNEL_NAME}:1:${CU_NAME}"
EXPECTED_SP="sp=${CU_NAME}.m_axi_gmem:HBM[0]"
grep -Fxq "${EXPECTED_NK}" "${CONFIG}" || {
    echo "ERROR: reviewed nk entry is missing" >&2
    exit 6
}
grep -Fxq "${EXPECTED_SP}" "${CONFIG}" || {
    echo "ERROR: reviewed HBM[0] sp entry is missing" >&2
    exit 6
}
[[ "$(grep -cE '^[[:space:]]*nk=' "${CONFIG}" || true)" == "1" ]] || {
    echo "ERROR: configuration must contain exactly one nk entry" >&2
    exit 6
}
[[ "$(grep -cE '^[[:space:]]*sp=' "${CONFIG}" || true)" == "1" ]] || {
    echo "ERROR: configuration must contain exactly one sp entry" >&2
    exit 6
}

KERNEL_CU_SPEC="${KERNEL_NAME}:${CU_NAME}"
(( ${#KERNEL_CU_SPEC} <= 64 )) || {
    echo "ERROR: kernel/CU specification exceeds 64 characters" >&2
    exit 6
}

ACTUAL_XO_SHA256="$(sha256sum "${XO_PATH}" | awk '{print $1}')"
ACTUAL_KERNEL_XML_SHA256="$(sha256sum "${KERNEL_XML}" | awk '{print $1}')"
ACTUAL_COMPONENT_XML_SHA256="$(sha256sum "${COMPONENT_XML}" | awk '{print $1}')"
[[ "${ACTUAL_XO_SHA256}" == "${ACCEPTED_XO_SHA256}" ]] || {
    echo "ERROR: accepted XO SHA256 mismatch" >&2
    exit 7
}
[[ "${ACTUAL_KERNEL_XML_SHA256}" == "${ACCEPTED_KERNEL_XML_SHA256}" ]] || {
    echo "ERROR: accepted kernel.xml SHA256 mismatch" >&2
    exit 7
}
[[ "${ACTUAL_COMPONENT_XML_SHA256}" == "${ACCEPTED_COMPONENT_XML_SHA256}" ]] || {
    echo "ERROR: accepted component.xml SHA256 mismatch" >&2
    exit 7
}
unzip -t "${XO_PATH}" >/dev/null || {
    echo "ERROR: accepted XO archive integrity failed" >&2
    exit 7
}

echo "============================================================"
echo "Stage 2N-A14.6 exact-target link-only run"
echo "PLATFORM=${PLATFORM}"
echo "KERNEL=${KERNEL_NAME}"
echo "COMPUTE_UNIT=${CU_NAME}"
echo "CONNECTIVITY=${EXPECTED_SP}"
echo "CLOCK_MHZ=${KERNEL_FREQUENCY_MHZ}"
echo "XO_SHA256=${ACTUAL_XO_SHA256}"
echo "This run builds an xclbin and routed reports only."
echo "It does NOT open/program/reset an FPGA or access physical HBM."
echo "============================================================"

confirmation="${A14_6_CONFIRM:-}"
if [[ -z "${confirmation}" ]]; then
    if [[ ! -t 0 ]]; then
        echo "ERROR: interactive confirmation unavailable; set A14_6_CONFIRM=yes" >&2
        exit 8
    fi
    read -r -p "Proceed with the A14.6 link-only build? [yes/no] " confirmation
fi
[[ "${confirmation}" == "yes" ]] || {
    echo "A14.6 link-only build cancelled safely."
    exit 0
}

mkdir -p "${OUTPUT_DIR}" "${LOG_DIR}"
trap unexpected_error ERR

CURRENT_BRANCH="$(cd "${REPO_ROOT}" && git symbolic-ref --short HEAD 2>/dev/null || echo DETACHED)"
CURRENT_HEAD="$(cd "${REPO_ROOT}" && git rev-parse HEAD)"
[[ "${CURRENT_BRANCH}" == "${EXPECTED_BRANCH}" ]] ||
    fail 9 "wrong branch: ${CURRENT_BRANCH}; expected ${EXPECTED_BRANCH}"
(cd "${REPO_ROOT}" && git status --porcelain) > "${GIT_STATUS_FILE}"
write_status

python3 "${XO_VALIDATOR}" \
    --kernel-xml "${KERNEL_XML}" \
    --component-xml "${COMPONENT_XML}" \
    --wrapper-rtl "${WRAPPER_RTL}" \
    --kernel-name "${KERNEL_NAME}" \
    > "${XO_VALIDATION_LOG}" 2>&1 ||
    fail 10 "accepted XO cross-layer metadata validation failed"
grep -Fxq "A14_5_TARGET_XO_METADATA_VALIDATION_V2=PASS" \
    "${XO_VALIDATION_LOG}" ||
    fail 10 "accepted XO validation PASS marker is missing"
A14_6_INPUT_XO="PASS"
A14_6_TABLE_BASE_ABI="PASS"
write_status

# shellcheck disable=SC1090
source "${VITIS_SETTINGS}" >/dev/null
for tool in git sha256sum vivado v++ xclbinutil unzip awk grep find python3; do
    command -v "${tool}" >/dev/null 2>&1 ||
        fail 11 "required tool unavailable after sourcing Vitis: ${tool}"
done

{
    echo "VITIS_SETTINGS=${VITIS_SETTINGS}"
    echo "PLATFORM=${PLATFORM}"
    vivado -version
    v++ --version
    xclbinutil --version
} > "${TOOL_VERSION_LOG}" 2>&1

sha256sum \
    "${CONFIG}" \
    "${XO_VALIDATOR}" \
    "${XCLBIN_VALIDATOR}" \
    "${POST_ROUTE_TCL}" \
    "${WRAPPER_RTL}" \
    "${BASH_SOURCE[0]}" > "${SOURCE_HASHES}"

trap - ERR
set +e
v++ \
    --target hw \
    --link \
    --platform "${PLATFORM}" \
    --config "${CONFIG}" \
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
vpp_exit="${PIPESTATUS[0]}"
set -e
trap unexpected_error ERR

if [[ "${vpp_exit}" -ne 0 ]]; then
    A14_6_VPP_LINK="FAIL"
    fail 12 "A14.6 Vitis hardware link failed with exit ${vpp_exit}"
fi
[[ -s "${XCLBIN_PATH}" ]] || {
    A14_6_VPP_LINK="FAIL"
    fail 13 "v++ returned success without a non-empty xclbin"
}
A14_6_VPP_LINK="PASS_PENDING_METADATA"
A14_6_XCLBIN="BUILT_PENDING_METADATA"
write_status

VPP_ERROR_COUNT="$(grep -cE '^ERROR:' "${VPP_LOG}" || true)"
VPP_CRITICAL_WARNING_COUNT="$(grep -cE '^CRITICAL WARNING:' "${VPP_LOG}" || true)"
[[ "${VPP_ERROR_COUNT}" == "0" ]] ||
    fail 14 "v++ log contains ${VPP_ERROR_COUNT} anchored ERROR lines"
[[ "${VPP_CRITICAL_WARNING_COUNT}" == "0" ]] ||
    fail 15 "v++ log contains ${VPP_CRITICAL_WARNING_COUNT} critical warnings"

xclbinutil --quiet --force --info "${XCLBIN_INFO}" --input "${XCLBIN_PATH}" ||
    fail 16 "failed to read xclbin metadata"
xclbinutil --quiet --force \
    --dump-section "CONNECTIVITY:JSON:${CONNECTIVITY_JSON}" \
    --input "${XCLBIN_PATH}" || fail 17 "failed to extract CONNECTIVITY JSON"
xclbinutil --quiet --force \
    --dump-section "MEM_TOPOLOGY:JSON:${MEM_TOPOLOGY_JSON}" \
    --input "${XCLBIN_PATH}" || fail 17 "failed to extract MEM_TOPOLOGY JSON"
xclbinutil --quiet --force \
    --dump-section "IP_LAYOUT:JSON:${IP_LAYOUT_JSON}" \
    --input "${XCLBIN_PATH}" || fail 17 "failed to extract IP_LAYOUT JSON"

python3 "${XCLBIN_VALIDATOR}" \
    --connectivity "${CONNECTIVITY_JSON}" \
    --mem-topology "${MEM_TOPOLOGY_JSON}" \
    --ip-layout "${IP_LAYOUT_JSON}" \
    --xclbin-info "${XCLBIN_INFO}" \
    --kernel "${KERNEL_NAME}" \
    --compute-unit "${CU_NAME}" \
    --platform "${PLATFORM_VBNV}" \
    > "${XCLBIN_VALIDATION_LOG}" 2>&1 ||
    fail 18 "xclbin identity or HBM[0] connectivity validation failed"
grep -Fxq "A14_6_XCLBIN_METADATA_VALIDATION=PASS" \
    "${XCLBIN_VALIDATION_LOG}" ||
    fail 18 "xclbin validation PASS marker is missing"

XCLBIN_UUID="$(awk -F= '$1 == "XCLBIN_UUID" {print $2; exit}' "${XCLBIN_VALIDATION_LOG}")"
[[ -n "${XCLBIN_UUID}" ]] || fail 18 "xclbin UUID was not parsed"
A14_6_VPP_LINK="PASS"
A14_6_XCLBIN="PASS"
A14_6_HBM0_LINK_MAPPING="PASS"
write_status

ROUTED_DCP="$(find "${TEMP_DIR}" -type f \( -name '*_routed.dcp' -o -name '*route_design*.dcp' \) -print -quit 2>/dev/null || true)"
[[ -n "${ROUTED_DCP}" && -s "${ROUTED_DCP}" ]] || {
    A14_6_TARGET_TIMING="FAIL_REPORT_EXTRACTION"
    fail 19 "routed Vitis checkpoint was not found"
}
export A14_ROUTED_DCP="${ROUTED_DCP}"
export A14_REPORT_DIR="${POST_ROUTE_DIR}"

trap - ERR
set +e
vivado -mode batch -nolog -nojournal \
    -source "${POST_ROUTE_TCL}" 2>&1 | tee "${POST_ROUTE_LOG}"
report_exit="${PIPESTATUS[0]}"
set -e
trap unexpected_error ERR
[[ "${report_exit}" -eq 0 ]] || {
    A14_6_TARGET_TIMING="FAIL_REPORT_EXTRACTION"
    fail 20 "routed report extraction failed"
}
[[ -s "${POST_ROUTE_METRICS}" ]] || {
    A14_6_TARGET_TIMING="FAIL_REPORT_EXTRACTION"
    fail 20 "post-route metrics are missing"
}

metric()
{
    local key="$1"
    awk -F= -v key="${key}" '$1 == key {sub(/^[^=]*=/, ""); print; exit}' \
        "${POST_ROUTE_METRICS}"
}

actual_part="$(metric TARGET_PART)"
wns="$(metric WNS_NS)"
tns="$(metric TNS_NS)"
failing_endpoints="$(metric FAILING_ENDPOINTS)"
[[ "${actual_part}" == "${PART_NAME}" ]] || {
    A14_6_TARGET_TIMING="FAIL_TARGET_PART_MISMATCH"
    fail 21 "routed part mismatch: ${actual_part}"
}
[[ -n "${wns}" && "${wns}" != "NOT_PARSED" ]] || {
    A14_6_TARGET_TIMING="FAIL_REPORT_EXTRACTION"
    fail 21 "setup WNS was not parsed"
}
if awk -v wns="${wns}" -v tns="${tns}" -v endpoints="${failing_endpoints}" \
    'BEGIN {exit !((wns + 0.0) >= 0.0 && (tns + 0.0) == 0.0 && (endpoints + 0) == 0)}'
then
    A14_6_TARGET_TIMING="PASS"
else
    A14_6_TARGET_TIMING="FAIL"
    fail 22 "target timing failed: WNS=${wns}, TNS=${tns}, endpoints=${failing_endpoints}"
fi

sha256sum \
    "${XO_PATH}" \
    "${KERNEL_XML}" \
    "${COMPONENT_XML}" \
    "${XCLBIN_PATH}" \
    "${CONNECTIVITY_JSON}" \
    "${MEM_TOPOLOGY_JSON}" \
    "${IP_LAYOUT_JSON}" > "${ARTIFACT_HASHES}"

write_status
cat >> "${STATUS}" <<EOF
WNS_NS=${wns}
TNS_NS=${tns}
FAILING_ENDPOINTS=${failing_endpoints}
WORST_STARTPOINT=$(metric WORST_STARTPOINT)
WORST_ENDPOINT=$(metric WORST_ENDPOINT)
CLOCK_COUNT=$(metric CLOCK_COUNT)
CLOCKS=$(metric CLOCKS)
LUT=$(metric LUT)
FF=$(metric FF)
RAMB36=$(metric RAMB36)
RAMB18=$(metric RAMB18)
BRAM_TILE_EQUIVALENT=$(metric BRAM_TILE_EQUIVALENT)
URAM=$(metric URAM)
DSP=$(metric DSP)
LATCH=$(metric LATCH)
DRC_ERROR_COUNT=$(metric DRC_ERROR_COUNT)
DRC_CRITICAL_WARNING_COUNT=$(metric DRC_CRITICAL_WARNING_COUNT)
METHODOLOGY_ERROR_COUNT=$(metric METHODOLOGY_ERROR_COUNT)
METHODOLOGY_CRITICAL_WARNING_COUNT=$(metric METHODOLOGY_CRITICAL_WARNING_COUNT)
SOURCE_SHA256=${SOURCE_HASHES}
ARTIFACT_SHA256=${ARTIFACT_HASHES}
XO_VALIDATION_LOG=${XO_VALIDATION_LOG}
XCLBIN_VALIDATION_LOG=${XCLBIN_VALIDATION_LOG}
XCLBIN_CONNECTIVITY_JSON=${CONNECTIVITY_JSON}
XCLBIN_MEM_TOPOLOGY_JSON=${MEM_TOPOLOGY_JSON}
XCLBIN_IP_LAYOUT_JSON=${IP_LAYOUT_JSON}
POST_ROUTE_METRICS=${POST_ROUTE_METRICS}
EOF

echo "A14_6_INPUT_XO=${A14_6_INPUT_XO}"
echo "A14_6_TABLE_BASE_ABI=${A14_6_TABLE_BASE_ABI}"
echo "A14_6_VPP_LINK=${A14_6_VPP_LINK}"
echo "A14_6_XCLBIN=${A14_6_XCLBIN}"
echo "A14_6_HBM0_LINK_MAPPING=${A14_6_HBM0_LINK_MAPPING}"
echo "A14_6_TARGET_TIMING=${A14_6_TARGET_TIMING}"
echo "A14_6_PHYSICAL_HBM=NOT_VALIDATED"
echo "A14_6_FPGA_DEVICE_ACCESS=NONE"
echo "A14_6_READY_FOR_BOARD=NO"
echo "STATUS=${STATUS}"
