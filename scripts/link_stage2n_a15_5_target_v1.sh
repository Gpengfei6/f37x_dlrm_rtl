#!/usr/bin/env bash
# User-executed Stage 2N-A15.5 F37X link-only runner.
# It consumes a separately validated A15.5 XO and never opens, programs, or
# resets a device and never runs a Host application.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

VITIS_SETTINGS="${VITIS_SETTINGS:-/opt/Xilinx/Vitis/2020.2/settings64.sh}"
PLATFORM="${PLATFORM:-/opt/xilinx/platforms/inspur_f37x_xdma_201920_3/inspur_f37x_xdma_201920_3.xpfm}"
PLATFORM_VBNV="inspur_f37x_xdma_201920_3"
PART_NAME="xcvu37p-fsvh2892-2L-e"
EXPECTED_BRANCH="work/stage2n-a15-hbm-pipeline-integration"
AUTHORIZATION_BASELINE="0c705a360a036785e4c949185fcb5cc1dcc4f07f"
KERNEL_NAME="dlrm_f37x_rtl_kernel_stage2n_a15_v1"
CU_NAME="dlrm_a15_1"
KERNEL_FREQUENCY_MHZ="${KERNEL_FREQUENCY_MHZ:-100}"
JOBS="${JOBS:-8}"

XO_DIR="${REPO_ROOT}/build/stage2n_a15_5/xo_v1"
XO_PATH="${XO_DIR}/${KERNEL_NAME}.xo"
KERNEL_XML="${XO_DIR}/kernel.xml"
COMPONENT_XML="${XO_DIR}/dlrm_f37x_stage2n_a15_ip_v1/component.xml"
XO_STATUS="${REPO_ROOT}/results/stage2n_a15_5/target_xo_v1/a15_5_target_xo_v1_status.txt"
WRAPPER_RTL="${REPO_ROOT}/rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a15_v1.sv"
PACKAGE_TCL="${REPO_ROOT}/scripts/package_stage2n_a15_5_rtl_kernel_v1.tcl"
CONFIG="${REPO_ROOT}/config/stage2n_a15_5_target_v1.cfg"
XO_VALIDATOR="${REPO_ROOT}/scripts/validate_stage2n_a15_5_xo_v1.py"
XCLBIN_VALIDATOR="${REPO_ROOT}/scripts/validate_stage2n_a15_5_xclbin_v1.py"
POST_ROUTE_TCL="${REPO_ROOT}/scripts/report_stage2n_a15_5_vitis_post_route_v1.tcl"

BUILD_ROOT="${REPO_ROOT}/build/stage2n_a15_5/link_v1"
TEMP_DIR="${BUILD_ROOT}/_x"
OUTPUT_DIR="${BUILD_ROOT}/hw"
XCLBIN_PATH="${OUTPUT_DIR}/${KERNEL_NAME}.xclbin"
RESULT_ROOT="${REPO_ROOT}/results/stage2n_a15_5/target_link_v1"
LOG_DIR="${RESULT_ROOT}/logs"
STATUS="${RESULT_ROOT}/a15_5_target_link_v1_status.txt"
GIT_STATUS_FILE="${RESULT_ROOT}/git_status_porcelain.txt"
TOOL_LOG="${LOG_DIR}/tool_versions.log"
XO_VALIDATION_LOG="${LOG_DIR}/xo_metadata_validation.log"
VPP_LOG="${LOG_DIR}/vpp_link.log"
XCLBIN_INFO="${RESULT_ROOT}/${KERNEL_NAME}.xclbin.info"
CONNECTIVITY_JSON="${RESULT_ROOT}/xclbin_connectivity.json"
MEM_TOPOLOGY_JSON="${RESULT_ROOT}/xclbin_mem_topology.json"
IP_LAYOUT_JSON="${RESULT_ROOT}/xclbin_ip_layout.json"
LINK_CONTRACT="${RESULT_ROOT}/link_contract.txt"
XCLBIN_VALIDATION_LOG="${LOG_DIR}/xclbin_metadata_validation.log"
POST_ROUTE_LOG="${LOG_DIR}/vivado_post_route_report.log"
POST_ROUTE_DIR="${RESULT_ROOT}/post_route"
POST_ROUTE_METRICS="${POST_ROUTE_DIR}/post_route_metrics.txt"
SOURCE_HASHES="${RESULT_ROOT}/a15_5_target_link_v1_sources.sha256"
ARTIFACT_HASHES="${RESULT_ROOT}/a15_5_target_link_v1_artifacts.sha256"

A15_5_INPUT_XO="NOT_VALIDATED"
A15_5_TARGET_LINK="NOT_RUN"
A15_5_XCLBIN="NOT_RUN"
A15_5_HBM0_LINK_MAPPING="NOT_VALIDATED"
A15_5_TARGET_TIMING="NOT_RUN"
FAIL_REASON="NONE"
CURRENT_BRANCH="NOT_RECORDED"
CURRENT_HEAD="NOT_RECORDED"
XO_SHA256="NOT_AVAILABLE"
XCLBIN_SHA256="NOT_AVAILABLE"
XCLBIN_UUID="NOT_AVAILABLE"
ROUTED_DCP="NOT_AVAILABLE"

write_status()
{
    cat > "${STATUS}" <<EOF
A15_5_FLOW=TARGET_LINK_V1
A15_5_INPUT_XO=${A15_5_INPUT_XO}
A15_5_TARGET_LINK=${A15_5_TARGET_LINK}
A15_5_XCLBIN=${A15_5_XCLBIN}
A15_5_HBM0_LINK_MAPPING=${A15_5_HBM0_LINK_MAPPING}
A15_5_TARGET_TIMING=${A15_5_TARGET_TIMING}
A15_5_PHYSICAL_HBM=NOT_VALIDATED
A15_5_HOST_BUILD=NOT_RUN
A15_5_HOST_EXECUTION=NOT_RUN
A15_5_FPGA_PROGRAMMING=NOT_RUN
A15_5_FPGA_RESET=NOT_RUN
A15_5_FPGA_DEVICE_ACCESS=NONE
A15_5_READY_FOR_BOARD=NO
FAIL_REASON=${FAIL_REASON}
GIT_BRANCH=${CURRENT_BRANCH}
GIT_HEAD=${CURRENT_HEAD}
TARGET_PART=${PART_NAME}
PLATFORM=${PLATFORM}
PLATFORM_VBNV=${PLATFORM_VBNV}
KERNEL=${KERNEL_NAME}
COMPUTE_UNIT=${CU_NAME}
REQUESTED_HBM_MAPPING=${CU_NAME}.m_axi_gmem:HBM[0]
REQUESTED_CLOCK_MHZ=${KERNEL_FREQUENCY_MHZ}
M_AXI_MASTER_COUNT=1
XO=${XO_PATH}
XO_SHA256=${XO_SHA256}
XCLBIN=${XCLBIN_PATH}
XCLBIN_SHA256=${XCLBIN_SHA256}
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

[[ ! -e "${BUILD_ROOT}" ]] || {
    echo "ERROR: refusing to overwrite build root: ${BUILD_ROOT}" >&2
    exit 2
}
[[ ! -e "${RESULT_ROOT}" ]] || {
    echo "ERROR: refusing to overwrite result root: ${RESULT_ROOT}" >&2
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
for required in "${VITIS_SETTINGS}" "${PLATFORM}" "${XO_PATH}" "${KERNEL_XML}" \
    "${COMPONENT_XML}" "${XO_STATUS}" "${WRAPPER_RTL}" "${PACKAGE_TCL}" \
    "${CONFIG}" "${XO_VALIDATOR}" "${XCLBIN_VALIDATOR}" "${POST_ROUTE_TCL}"; do
    [[ -f "${required}" ]] || {
        echo "ERROR: required input is missing: ${required}" >&2
        exit 5
    }
done

grep -Fxq "A15_5_TARGET_XO_BUILD=PASS" "${XO_STATUS}" || {
    echo "ERROR: input XO has no accepted build PASS status" >&2
    exit 6
}
grep -Fxq "A15_5_TARGET_XO_VALIDATION=PASS" "${XO_STATUS}" || {
    echo "ERROR: input XO has no accepted metadata PASS status" >&2
    exit 6
}
recorded_xo_sha256="$(awk -F= '$1 == "XO_SHA256" {print $2; exit}' "${XO_STATUS}")"
[[ "${recorded_xo_sha256}" =~ ^[0-9a-f]{64}$ ]] || {
    echo "ERROR: input XO status has no valid SHA256" >&2
    exit 6
}
XO_SHA256="$(sha256sum "${XO_PATH}" | awk '{print $1}')"
[[ "${XO_SHA256}" == "${recorded_xo_sha256}" ]] || {
    echo "ERROR: input XO SHA256 differs from accepted status" >&2
    exit 6
}
unzip -t "${XO_PATH}" >/dev/null || {
    echo "ERROR: input XO archive integrity failed" >&2
    exit 6
}

expected_nk="nk=${KERNEL_NAME}:1:${CU_NAME}"
expected_sp="sp=${CU_NAME}.m_axi_gmem:HBM[0]"
grep -Fxq "${expected_nk}" "${CONFIG}" || { echo "ERROR: reviewed nk entry missing" >&2; exit 7; }
grep -Fxq "${expected_sp}" "${CONFIG}" || { echo "ERROR: reviewed HBM[0] entry missing" >&2; exit 7; }
[[ "$(grep -cE '^[[:space:]]*nk=' "${CONFIG}" || true)" == "1" ]] || { echo "ERROR: nk count is not one" >&2; exit 7; }
[[ "$(grep -cE '^[[:space:]]*sp=' "${CONFIG}" || true)" == "1" ]] || { echo "ERROR: sp count is not one" >&2; exit 7; }

confirmation="${A15_5_LINK_CONFIRM:-}"
if [[ -z "${confirmation}" ]]; then
    if [[ ! -t 0 ]]; then
        echo "ERROR: interactive confirmation unavailable; set A15_5_LINK_CONFIRM=yes" >&2
        exit 8
    fi
    read -r -p "Proceed with the A15.5 link-only build? [yes/no] " confirmation
fi
[[ "${confirmation}" == "yes" ]] || {
    echo "A15.5 link-only build cancelled safely."
    exit 0
}

mkdir -p "${OUTPUT_DIR}" "${LOG_DIR}"
trap unexpected_error ERR
CURRENT_BRANCH="$(cd "${REPO_ROOT}" && git symbolic-ref --short HEAD 2>/dev/null || echo DETACHED)"
CURRENT_HEAD="$(cd "${REPO_ROOT}" && git rev-parse HEAD)"
[[ "${CURRENT_BRANCH}" == "${EXPECTED_BRANCH}" ]] || fail 9 "wrong branch: ${CURRENT_BRANCH}"
(cd "${REPO_ROOT}" && git merge-base --is-ancestor "${AUTHORIZATION_BASELINE}" HEAD) ||
    fail 9 "A15.5 authorization baseline is not an ancestor of HEAD"
(cd "${REPO_ROOT}" && git diff --quiet && git diff --cached --quiet) ||
    fail 9 "tracked worktree/index must be clean before target link"
(cd "${REPO_ROOT}" && git status --porcelain) > "${GIT_STATUS_FILE}"

cat > "${LINK_CONTRACT}" <<EOF
KERNEL=${KERNEL_NAME}
COMPUTE_UNIT=${CU_NAME}
PLATFORM_VBNV=${PLATFORM_VBNV}
TARGET_PART=${PART_NAME}
KERNEL_FREQUENCY_MHZ=${KERNEL_FREQUENCY_MHZ}
CONNECTIVITY=${CU_NAME}.m_axi_gmem:HBM[0]
M_AXI_MASTER_COUNT=1
EOF
write_status

python3 "${XO_VALIDATOR}" \
    --kernel-xml "${KERNEL_XML}" \
    --component-xml "${COMPONENT_XML}" \
    --wrapper-rtl "${WRAPPER_RTL}" \
    --package-tcl "${PACKAGE_TCL}" \
    --kernel-name "${KERNEL_NAME}" \
    --target-part "${PART_NAME}" > "${XO_VALIDATION_LOG}" 2>&1 ||
    fail 10 "input XO metadata revalidation failed"
grep -Fxq "A15_5_TARGET_XO_METADATA_VALIDATION=PASS" "${XO_VALIDATION_LOG}" ||
    fail 10 "input XO validation PASS marker missing"
A15_5_INPUT_XO="PASS"
write_status

# shellcheck disable=SC1090
source "${VITIS_SETTINGS}" >/dev/null
for tool in git sha256sum vivado 'v++' xclbinutil unzip awk grep find python3 tee; do
    command -v "${tool}" >/dev/null 2>&1 || fail 11 "required tool unavailable: ${tool}"
done
{
    echo "VITIS_SETTINGS=${VITIS_SETTINGS}"
    echo "PLATFORM=${PLATFORM}"
    vivado -version
    xclbinutil --version
} > "${TOOL_LOG}" 2>&1
sha256sum "${XO_PATH}" "${CONFIG}" "${XO_VALIDATOR}" "${XCLBIN_VALIDATOR}" \
    "${POST_ROUTE_TCL}" "${BASH_SOURCE[0]}" > "${SOURCE_HASHES}"

A15_5_TARGET_LINK="RUNNING"
write_status
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
    "${XO_PATH}" 2>&1 | tee "${VPP_LOG}"
vpp_exit="${PIPESTATUS[0]}"
set -e
trap unexpected_error ERR
if [[ "${vpp_exit}" -ne 0 ]]; then
    A15_5_TARGET_LINK="FAIL"
    fail 12 "Vitis hardware link failed with exit ${vpp_exit}"
fi
[[ -s "${XCLBIN_PATH}" ]] || fail 13 "v++ returned success without a non-empty xclbin"
[[ "$(grep -cE '^ERROR:' "${VPP_LOG}" || true)" == "0" ]] || fail 13 "v++ log contains ERROR lines"

xclbinutil --quiet --force --info "${XCLBIN_INFO}" --input "${XCLBIN_PATH}" || fail 14 "xclbin info extraction failed"
xclbinutil --quiet --force --dump-section "CONNECTIVITY:JSON:${CONNECTIVITY_JSON}" --input "${XCLBIN_PATH}" || fail 14 "CONNECTIVITY extraction failed"
xclbinutil --quiet --force --dump-section "MEM_TOPOLOGY:JSON:${MEM_TOPOLOGY_JSON}" --input "${XCLBIN_PATH}" || fail 14 "MEM_TOPOLOGY extraction failed"
xclbinutil --quiet --force --dump-section "IP_LAYOUT:JSON:${IP_LAYOUT_JSON}" --input "${XCLBIN_PATH}" || fail 14 "IP_LAYOUT extraction failed"

python3 "${XCLBIN_VALIDATOR}" \
    --connectivity "${CONNECTIVITY_JSON}" \
    --mem-topology "${MEM_TOPOLOGY_JSON}" \
    --ip-layout "${IP_LAYOUT_JSON}" \
    --xclbin-info "${XCLBIN_INFO}" \
    --config "${CONFIG}" \
    --link-script "${BASH_SOURCE[0]}" \
    --link-contract "${LINK_CONTRACT}" \
    --kernel "${KERNEL_NAME}" \
    --compute-unit "${CU_NAME}" \
    --platform "${PLATFORM_VBNV}" \
    --part "${PART_NAME}" \
    --clock-mhz "${KERNEL_FREQUENCY_MHZ}" > "${XCLBIN_VALIDATION_LOG}" 2>&1 ||
    fail 15 "xclbin metadata validation failed"
grep -Fxq "A15_5_XCLBIN_METADATA_VALIDATION=PASS" "${XCLBIN_VALIDATION_LOG}" ||
    fail 15 "xclbin metadata PASS marker missing"
XCLBIN_UUID="$(awk -F= '$1 == "XCLBIN_UUID" {print $2; exit}' "${XCLBIN_VALIDATION_LOG}")"
XCLBIN_SHA256="$(sha256sum "${XCLBIN_PATH}" | awk '{print $1}')"
A15_5_XCLBIN="PASS"
A15_5_HBM0_LINK_MAPPING="PASS"
write_status

ROUTED_DCP="$(find "${TEMP_DIR}" -type f \( -name '*_routed.dcp' -o -name '*route_design*.dcp' \) -print -quit 2>/dev/null || true)"
[[ -n "${ROUTED_DCP}" && -s "${ROUTED_DCP}" ]] || fail 16 "routed checkpoint not found"
export A15_5_ROUTED_DCP="${ROUTED_DCP}"
export A15_5_REPORT_DIR="${POST_ROUTE_DIR}"
trap - ERR
set +e
vivado -mode batch -nolog -nojournal -source "${POST_ROUTE_TCL}" 2>&1 | tee "${POST_ROUTE_LOG}"
report_exit="${PIPESTATUS[0]}"
set -e
trap unexpected_error ERR
[[ "${report_exit}" -eq 0 && -s "${POST_ROUTE_METRICS}" ]] || fail 17 "post-route report extraction failed"

metric()
{
    local key="$1"
    awk -F= -v key="${key}" '$1 == key {sub(/^[^=]*=/, ""); print; exit}' "${POST_ROUTE_METRICS}"
}
actual_part="$(metric TARGET_PART)"
wns="$(metric WNS_NS)"
tns="$(metric TNS_NS)"
failing_endpoints="$(metric FAILING_ENDPOINTS)"
[[ "${actual_part}" == "${PART_NAME}" ]] || fail 18 "routed target part mismatch: ${actual_part}"
[[ -n "${wns}" && "${wns}" != "NOT_PARSED" ]] || fail 18 "setup WNS was not parsed"
if awk -v wns="${wns}" -v tns="${tns}" -v endpoints="${failing_endpoints}" \
    'BEGIN {exit !((wns + 0.0) >= 0.0 && (tns + 0.0) == 0.0 && (endpoints + 0) == 0)}'; then
    A15_5_TARGET_TIMING="PASS"
else
    A15_5_TARGET_TIMING="FAIL"
    fail 19 "100 MHz timing failed: WNS=${wns}, TNS=${tns}, endpoints=${failing_endpoints}"
fi

A15_5_TARGET_LINK="PASS"
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
XO_VALIDATION_LOG=${XO_VALIDATION_LOG}
XCLBIN_VALIDATION_LOG=${XCLBIN_VALIDATION_LOG}
POST_ROUTE_METRICS=${POST_ROUTE_METRICS}
EOF

echo "A15_5_INPUT_XO=PASS"
echo "A15_5_TARGET_LINK=PASS"
echo "A15_5_XCLBIN=PASS"
echo "A15_5_HBM0_LINK_MAPPING=PASS"
echo "A15_5_TARGET_TIMING=PASS"
echo "A15_5_PHYSICAL_HBM=NOT_VALIDATED"
echo "A15_5_FPGA_DEVICE_ACCESS=NONE"
echo "STATUS=${STATUS}"
