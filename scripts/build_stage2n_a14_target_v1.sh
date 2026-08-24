#!/usr/bin/env bash
# Build-only Stage 2N-A14 target flow for Vivado/Vitis 2020.2 and F37X.
#
# This script packages the isolated single-bank embedding-lookup RTL kernel,
# links a hardware xclbin with m_axi_gmem mapped to HBM[0], validates metadata,
# and reports the routed design. It never opens an XRT device, programs or
# resets an FPGA, runs a Host application, or performs a physical HBM access.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

VITIS_SETTINGS="${VITIS_SETTINGS:-/opt/Xilinx/Vitis/2020.2/settings64.sh}"
PLATFORM="${PLATFORM:-/opt/xilinx/platforms/inspur_f37x_xdma_201920_3/inspur_f37x_xdma_201920_3.xpfm}"
PART_NAME="xcvu37p-fsvh2892-2L-e"
PLATFORM_VBNV="inspur_f37x_xdma_201920_3"
KERNEL_NAME="dlrm_f37x_rtl_kernel_stage2n_a14_v1"
CU_NAME="dlrm_a14_1"
KERNEL_FREQUENCY_MHZ="${KERNEL_FREQUENCY_MHZ:-100}"
JOBS="${JOBS:-8}"
A14_TARGET_BUILD_FLOW="${A14_TARGET_BUILD_FLOW:-STAGE2N_A14_TARGET_V1}"
A14_TARGET_RUNNER_VERSION="${A14_TARGET_RUNNER_VERSION:-V1}"

CONFIG="${REPO_ROOT}/config/stage2n_a14_target_v1.cfg"
PACKAGE_TCL="${A14_PACKAGE_TCL:-${REPO_ROOT}/scripts/package_stage2n_a14_rtl_kernel_v1.tcl}"
POST_ROUTE_TCL="${REPO_ROOT}/scripts/report_stage2n_a14_vitis_post_route_v1.tcl"
A14_LOOKUP_RTL="${REPO_ROOT}/rtl/hbm/dlrm_hbm_embedding_lookup_stage2n_a14_v1.sv"
A14_WRAPPER_RTL="${REPO_ROOT}/rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a14_v1.sv"

BUILD_ROOT="${REPO_ROOT}/build/stage2n_a14"
XO_DIR="${BUILD_ROOT}/xo_v1"
XO_PATH="${XO_DIR}/${KERNEL_NAME}.xo"
KERNEL_XML="${XO_DIR}/kernel.xml"
COMPONENT_XML="${XO_DIR}/dlrm_f37x_stage2n_a14_ip_v1/component.xml"
LINK_DIR="${BUILD_ROOT}/vitis_link_v1"
TEMP_DIR="${LINK_DIR}/_x"
OUTPUT_DIR="${LINK_DIR}/hw"
XCLBIN_PATH="${OUTPUT_DIR}/${KERNEL_NAME}.xclbin"

RESULT_ROOT="${REPO_ROOT}/results/stage2n_a14/target_build_v1"
LOG_DIR="${RESULT_ROOT}/logs"
STATUS="${RESULT_ROOT}/a14_target_build_status.txt"
HASH_OUTPUT="${RESULT_ROOT}/a14_target_artifacts.sha256"
SOURCE_HASH_OUTPUT="${RESULT_ROOT}/a14_target_sources.sha256"
XCLBIN_INFO="${RESULT_ROOT}/${KERNEL_NAME}.xclbin.info"
CONNECTIVITY_JSON="${RESULT_ROOT}/xclbin_connectivity.json"
MEM_TOPOLOGY_JSON="${RESULT_ROOT}/xclbin_mem_topology.json"
IP_LAYOUT_JSON="${RESULT_ROOT}/xclbin_ip_layout.json"
PACKAGE_LOG="${LOG_DIR}/vivado_package_xo.log"
VPP_LOG="${LOG_DIR}/vpp_link.log"
POST_ROUTE_LOG="${LOG_DIR}/vivado_post_route_report.log"
TOOL_VERSION_LOG="${LOG_DIR}/tool_versions.log"
POST_ROUTE_DIR="${RESULT_ROOT}/post_route"
POST_ROUTE_METRICS="${POST_ROUTE_DIR}/post_route_metrics.txt"
GIT_STATUS_FILE="${RESULT_ROOT}/git_status_porcelain.txt"

A14_TARGET_XO_BUILD="BLOCKED_NOT_RUN"
A14_VPP_LINK="BLOCKED_NOT_RUN"
A14_XCLBIN_BUILD="BLOCKED_NOT_RUN"
A14_HBM0_LINK_MAPPING="BLOCKED_NOT_RUN"
A14_TARGET_VU37P_TIMING="BLOCKED_NOT_RUN"
FAIL_REASON="NONE"
XCLBIN_UUID="NOT_AVAILABLE"
ROUTED_DCP="NOT_AVAILABLE"
CURRENT_BRANCH="NOT_RECORDED"
CURRENT_HEAD="NOT_RECORDED"

write_status()
{
    cat > "${STATUS}" <<EOF
A14_TARGET_BUILD_FLOW=${A14_TARGET_BUILD_FLOW}
A14_TARGET_RUNNER_VERSION=${A14_TARGET_RUNNER_VERSION}
A14_TARGET_XO_BUILD=${A14_TARGET_XO_BUILD}
A14_VPP_LINK=${A14_VPP_LINK}
A14_XCLBIN_BUILD=${A14_XCLBIN_BUILD}
A14_HBM0_LINK_MAPPING=${A14_HBM0_LINK_MAPPING}
A14_TARGET_VU37P_TIMING=${A14_TARGET_VU37P_TIMING}
A14_PHYSICAL_HBM_ACCESS=NOT_VALIDATED
A14_HOST_BUILD=NOT_RUN
A14_HOST_EXECUTION=NOT_RUN
A14_FPGA_PROGRAMMING=NOT_RUN
A14_FPGA_RESET=NOT_RUN
A14_FPGA_DEVICE_ACCESS=NONE
A14_READY_FOR_BOARD=NO
READY_REASON=PHYSICAL_HBM_HOST_AND_BOARD_VALIDATION_NOT_PERFORMED
FAIL_REASON=${FAIL_REASON}
GIT_BRANCH=${CURRENT_BRANCH}
GIT_HEAD=${CURRENT_HEAD}
TARGET_PART=${PART_NAME}
PLATFORM=${PLATFORM}
PLATFORM_VBNV=${PLATFORM_VBNV}
KERNEL=${KERNEL_NAME}
COMPUTE_UNIT=${CU_NAME}
CONTROL_INTERFACE=s_axi_control
MEMORY_INTERFACE=m_axi_gmem
REQUESTED_HBM_MAPPING=m_axi_gmem_TO_HBM_0
REQUESTED_CLOCK_MHZ=${KERNEL_FREQUENCY_MHZ}
XO=${XO_PATH}
XCLBIN=${XCLBIN_PATH}
XCLBIN_UUID=${XCLBIN_UUID}
ROUTED_DCP=${ROUTED_DCP}
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

fail_xclbin_metadata()
{
    local code="$1"
    shift
    A14_VPP_LINK="FAIL_METADATA_VALIDATION"
    A14_XCLBIN_BUILD="FAIL_METADATA_VALIDATION"
    A14_HBM0_LINK_MAPPING="FAIL_METADATA_VALIDATION"
    fail "${code}" "$@"
}

unexpected_error()
{
    local code="$?"
    local line="${BASH_LINENO[0]:-UNKNOWN}"
    if [[ "${FAIL_REASON}" == "NONE" ]]; then
        FAIL_REASON="unexpected command failure at line ${line}"
        write_status
    fi
    exit "${code}"
}

# Generated build and evidence roots are immutable for this runner. A previous
# result must be reviewed and moved aside explicitly; the script never deletes
# or overwrites it.
[[ ! -e "${BUILD_ROOT}" ]] || {
    echo "ERROR: refusing to overwrite existing build root: ${BUILD_ROOT}" >&2
    exit 2
}
[[ ! -e "${RESULT_ROOT}" ]] || {
    echo "ERROR: refusing to overwrite existing result root: ${RESULT_ROOT}" >&2
    exit 3
}
mkdir -p "${LOG_DIR}" "${OUTPUT_DIR}"
write_status
trap unexpected_error ERR

[[ "${KERNEL_FREQUENCY_MHZ}" == "100" ]] ||
    fail 4 "KERNEL_FREQUENCY_MHZ is frozen at 100 for this target runner"
[[ "${JOBS}" =~ ^[1-9][0-9]*$ ]] ||
    fail 4 "JOBS must be a positive integer"

for required in \
    "${VITIS_SETTINGS}" \
    "${PLATFORM}" \
    "${CONFIG}" \
    "${PACKAGE_TCL}" \
    "${POST_ROUTE_TCL}" \
    "${A14_LOOKUP_RTL}" \
    "${A14_WRAPPER_RTL}"
do
    [[ -f "${required}" ]] || fail 4 "required input is missing: ${required}"
done

EXPECTED_CONNECTIVITY="sp=${CU_NAME}.m_axi_gmem:HBM[0]"
EXPECTED_NK="nk=${KERNEL_NAME}:1:${CU_NAME}"
grep -Fxq "${EXPECTED_CONNECTIVITY}" "${CONFIG}" ||
    fail 5 "A14 connectivity configuration is not the reviewed HBM[0] mapping"
grep -Fxq "${EXPECTED_NK}" "${CONFIG}" ||
    fail 5 "A14 target configuration does not contain the reviewed shortened CU name"
connectivity_count="$(grep -cE '^[[:space:]]*sp=' "${CONFIG}" || true)"
[[ "${connectivity_count}" == "1" ]] ||
    fail 5 "A14 configuration must contain exactly one sp mapping"
nk_count="$(grep -cE '^[[:space:]]*nk=' "${CONFIG}" || true)"
[[ "${nk_count}" == "1" ]] ||
    fail 5 "A14 target configuration must contain exactly one nk declaration"

KERNEL_CU_SPEC="${KERNEL_NAME}:${CU_NAME}"
(( ${#KERNEL_CU_SPEC} <= 64 )) ||
    fail 5 "kernel/CU specification exceeds the Vitis 2020.2 64-character limit"

# shellcheck disable=SC1090
source "${VITIS_SETTINGS}" >/dev/null

for tool in git sha256sum vivado v++ xclbinutil unzip awk grep find python3; do
    command -v "${tool}" >/dev/null 2>&1 ||
        fail 6 "required tool unavailable after sourcing Vitis: ${tool}"
done

CURRENT_BRANCH="$(cd "${REPO_ROOT}" && git symbolic-ref --short HEAD 2>/dev/null || echo DETACHED)"
CURRENT_HEAD="$(cd "${REPO_ROOT}" && git rev-parse HEAD)"
(cd "${REPO_ROOT}" && git status --porcelain) > "${GIT_STATUS_FILE}"
write_status

{
    echo "VITIS_SETTINGS=${VITIS_SETTINGS}"
    echo "PLATFORM=${PLATFORM}"
    vivado -version
    v++ --version
    xclbinutil --version
} > "${TOOL_VERSION_LOG}" 2>&1

sha256sum \
    "${A14_LOOKUP_RTL}" \
    "${A14_WRAPPER_RTL}" \
    "${PACKAGE_TCL}" \
    "${POST_ROUTE_TCL}" \
    "${CONFIG}" > "${SOURCE_HASH_OUTPUT}"

set +e
vivado -mode batch -nolog -nojournal \
    -source "${PACKAGE_TCL}" 2>&1 | tee "${PACKAGE_LOG}"
package_exit="${PIPESTATUS[0]}"
set -e
if [[ "${package_exit}" -ne 0 ]]; then
    A14_TARGET_XO_BUILD="FAIL"
    fail 7 "A14 target-part XO packaging failed"
fi
if [[ ! -s "${XO_PATH}" || ! -s "${KERNEL_XML}" || ! -s "${COMPONENT_XML}" ]]; then
    A14_TARGET_XO_BUILD="FAIL"
    fail 8 "A14 XO or generated metadata is missing or empty"
fi
unzip -t "${XO_PATH}" >/dev/null || {
    A14_TARGET_XO_BUILD="FAIL"
    fail 9 "A14 XO archive integrity failed"
}
grep -Fxq "TARGET_PART_USED=1" "${PACKAGE_LOG}" || {
    A14_TARGET_XO_BUILD="FAIL"
    fail 10 "A14 XO was not packaged with the exact VU37P target part"
}

export A14_KERNEL_NAME="${KERNEL_NAME}"
export A14_KERNEL_XML="${KERNEL_XML}"
export A14_COMPONENT_XML="${COMPONENT_XML}"
python3 - <<'PY' || {
import os
import xml.etree.ElementTree as ET

kernel_name = os.environ["A14_KERNEL_NAME"]
root = ET.parse(os.environ["A14_KERNEL_XML"]).getroot()
kernel = root if root.tag == "kernel" else root.find("kernel")
if kernel is None:
    raise SystemExit("kernel.xml has no kernel element")
if kernel.get("name") != kernel_name:
    raise SystemExit("kernel.xml kernel name mismatch")
if kernel.get("hwControlProtocol") != "user_managed":
    raise SystemExit("kernel.xml control protocol is not user_managed")

ports = {node.get("name"): node for node in kernel.findall("./ports/port")}
if set(ports) != {"s_axi_control", "m_axi_gmem"}:
    raise SystemExit("kernel.xml port set mismatch: {}".format(sorted(ports)))

control = ports["s_axi_control"]
if control.get("mode") != "slave" or control.get("dataWidth") != "32":
    raise SystemExit("s_axi_control metadata mismatch")
memory = ports["m_axi_gmem"]
if memory.get("mode") != "master" or memory.get("dataWidth") != "128":
    raise SystemExit("m_axi_gmem metadata mismatch")
if int(memory.get("range", "0"), 0) != 0xFFFFFFFFFFFFFFFF:
    raise SystemExit("m_axi_gmem address range is not 64-bit")

args = {}
for arg in kernel.findall("./args/arg"):
    name = arg.get("name")
    if not name or name in args:
        raise SystemExit("unnamed or duplicate kernel argument")
    args[name] = int(arg.get("offset"), 0)
expected_args = {
    "LOOKUP_INDEX": 0x10,
    "RESULT0": 0x20,
    "RESULT1": 0x24,
    "RESULT2": 0x28,
    "RESULT3": 0x2C,
}
if args != expected_args:
    raise SystemExit("kernel.xml argument map mismatch: {}".format(args))

component_root = ET.parse(os.environ["A14_COMPONENT_XML"]).getroot()
namespace = component_root.tag[1:].split("}", 1)[0]
ns = {"spirit": namespace}
registers = {}
for register in component_root.findall(".//spirit:register", ns):
    name_node = register.find("spirit:name", ns)
    offset_node = register.find("spirit:addressOffset", ns)
    if name_node is None or offset_node is None:
        raise SystemExit("incomplete component register")
    name = (name_node.text or "").strip()
    if name in registers:
        raise SystemExit("duplicate component register {}".format(name))
    registers[name] = int((offset_node.text or "").strip(), 0)
expected_registers = {"CONTROL": 0x00, **expected_args}
if registers != expected_registers:
    raise SystemExit("component.xml register map mismatch: {}".format(registers))

print("A14_TARGET_XO_METADATA_VALIDATION=PASS")
print("KERNEL_XML_ARGUMENT_COUNT=5")
print("COMPONENT_XML_REGISTER_COUNT=6")
print("M_AXI_GMEM_DATA_WIDTH=128")
PY
    A14_TARGET_XO_BUILD="FAIL"
    fail 11 "A14 XO metadata validation failed"
}
A14_TARGET_XO_BUILD="PASS"
write_status

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
if [[ "${vpp_exit}" -ne 0 ]]; then
    A14_VPP_LINK="FAIL"
    A14_XCLBIN_BUILD="FAIL"
    fail 12 "A14 Vitis hardware link failed"
fi
if [[ ! -s "${XCLBIN_PATH}" ]]; then
    A14_VPP_LINK="FAIL"
    A14_XCLBIN_BUILD="FAIL"
    fail 13 "Vitis link returned success without an A14 xclbin"
fi
A14_VPP_LINK="PASS_PENDING_METADATA"
A14_XCLBIN_BUILD="BUILT_PENDING_METADATA"
write_status

vpp_errors="$(grep -cE '^ERROR:' "${VPP_LOG}" || true)"
vpp_critical="$(grep -cE '^CRITICAL WARNING:' "${VPP_LOG}" || true)"
if [[ "${vpp_errors}" != 0 ]]; then
    A14_VPP_LINK="FAIL_LOG_VALIDATION"
    A14_XCLBIN_BUILD="FAIL_LOG_VALIDATION"
    fail 14 "v++ log contains ${vpp_errors} anchored ERROR lines"
fi
if [[ "${vpp_critical}" != 0 ]]; then
    A14_VPP_LINK="FAIL_LOG_VALIDATION"
    A14_XCLBIN_BUILD="FAIL_LOG_VALIDATION"
    fail 15 "v++ log contains ${vpp_critical} CRITICAL WARNING lines"
fi

xclbinutil --quiet --force --info "${XCLBIN_INFO}" --input "${XCLBIN_PATH}" ||
    fail_xclbin_metadata 16 "failed to read xclbin metadata"
grep -qF "${KERNEL_NAME}" "${XCLBIN_INFO}" ||
    fail_xclbin_metadata 16 "xclbin metadata does not contain the A14 kernel"
grep -qF "${CU_NAME}" "${XCLBIN_INFO}" ||
    fail_xclbin_metadata 17 "xclbin metadata does not contain the expected compute unit"
grep -qF "${PLATFORM_VBNV}" "${XCLBIN_INFO}" ||
    fail_xclbin_metadata 18 "xclbin metadata does not contain the expected F37X platform"

xclbinutil --quiet --force \
    --dump-section "CONNECTIVITY:JSON:${CONNECTIVITY_JSON}" \
    --input "${XCLBIN_PATH}" ||
    fail_xclbin_metadata 19 "failed to extract xclbin CONNECTIVITY JSON"
xclbinutil --quiet --force \
    --dump-section "MEM_TOPOLOGY:JSON:${MEM_TOPOLOGY_JSON}" \
    --input "${XCLBIN_PATH}" ||
    fail_xclbin_metadata 19 "failed to extract xclbin MEM_TOPOLOGY JSON"
xclbinutil --quiet --force \
    --dump-section "IP_LAYOUT:JSON:${IP_LAYOUT_JSON}" \
    --input "${XCLBIN_PATH}" ||
    fail_xclbin_metadata 19 "failed to extract xclbin IP_LAYOUT JSON"

export A14_CONNECTIVITY_JSON="${CONNECTIVITY_JSON}"
export A14_MEM_TOPOLOGY_JSON="${MEM_TOPOLOGY_JSON}"
export A14_IP_LAYOUT_JSON="${IP_LAYOUT_JSON}"
export A14_CU_NAME="${CU_NAME}"
python3 - <<'PY' || fail_xclbin_metadata 19 "xclbin HBM[0] connectivity evidence validation failed"
import json
import os

with open(os.environ["A14_CONNECTIVITY_JSON"], "r", encoding="utf-8") as handle:
    connectivity = json.load(handle)
with open(os.environ["A14_MEM_TOPOLOGY_JSON"], "r", encoding="utf-8") as handle:
    topology = json.load(handle)
with open(os.environ["A14_IP_LAYOUT_JSON"], "r", encoding="utf-8") as handle:
    layout = json.load(handle)

def find_lists(value, key):
    found = []
    if isinstance(value, dict):
        for child_key, child in value.items():
            if child_key == key and isinstance(child, list):
                found.extend(child)
            found.extend(find_lists(child, key))
    elif isinstance(value, list):
        for child in value:
            found.extend(find_lists(child, key))
    return found

connections = find_lists(connectivity, "m_connection")
memories = find_lists(topology, "m_mem_data")
ips = find_lists(layout, "m_ip_data")
if not connections:
    raise SystemExit("CONNECTIVITY contains no connection records")

hbm0 = [entry for entry in memories if str(entry.get("m_tag", "")) == "HBM[0]"]
if len(hbm0) != 1:
    raise SystemExit("MEM_TOPOLOGY does not contain exactly one HBM[0]")
if str(hbm0[0].get("m_used", "1")).lower() in {"0", "false"}:
    raise SystemExit("HBM[0] is present but not marked used")

cu_name = os.environ["A14_CU_NAME"]
ip_names = [str(entry.get("m_name", "")) for entry in ips]
cu_indices = [index for index, name in enumerate(ip_names) if cu_name in name]
if len(cu_indices) != 1:
    raise SystemExit("IP_LAYOUT does not contain expected A14 compute unit")
hbm0_index = memories.index(hbm0[0])
cu_index = cu_indices[0]

def parse_index(entry, key):
    if key not in entry:
        raise SystemExit("CONNECTIVITY record lacks {}".format(key))
    value = entry[key]
    return value if isinstance(value, int) else int(str(value), 0)

cu_hbm0_connections = [
    entry for entry in connections
    if parse_index(entry, "m_ip_layout_index") == cu_index
    and parse_index(entry, "mem_data_index") == hbm0_index
]
if len(cu_hbm0_connections) != 1:
    raise SystemExit(
        "CONNECTIVITY does not contain exactly one A14 CU to HBM[0] record"
    )

print("A14_XCLBIN_CONNECTIVITY_RECORDS={}".format(len(connections)))
print("A14_XCLBIN_CU_INDEX={}".format(cu_index))
print("A14_XCLBIN_HBM0_INDEX={}".format(hbm0_index))
print("A14_XCLBIN_CU_TO_HBM0_CONNECTION=PASS")
print("A14_XCLBIN_HBM0_USED=PASS")
print("A14_XCLBIN_CU_LAYOUT=PASS")
PY

A14_VPP_LINK="PASS"
A14_XCLBIN_BUILD="PASS"
A14_HBM0_LINK_MAPPING="PASS"
XCLBIN_UUID="$(sed -n 's/^[[:space:]]*UUID (xclbin):[[:space:]]*//p' "${XCLBIN_INFO}" | head -n 1)"
[[ -n "${XCLBIN_UUID}" ]] || XCLBIN_UUID="NOT_PARSED"
write_status

ROUTED_DCP="$(find "${TEMP_DIR}" -type f \( -name '*_routed.dcp' -o -name '*route_design*.dcp' \) -print -quit 2>/dev/null || true)"
[[ -n "${ROUTED_DCP}" && -s "${ROUTED_DCP}" ]] || {
    A14_TARGET_VU37P_TIMING="FAIL_REPORT_EXTRACTION"
    fail 20 "routed Vitis checkpoint was not found"
}
export A14_ROUTED_DCP="${ROUTED_DCP}"
export A14_REPORT_DIR="${POST_ROUTE_DIR}"

set +e
vivado -mode batch -nolog -nojournal \
    -source "${POST_ROUTE_TCL}" 2>&1 | tee "${POST_ROUTE_LOG}"
report_exit="${PIPESTATUS[0]}"
set -e
[[ "${report_exit}" -eq 0 ]] || {
    A14_TARGET_VU37P_TIMING="FAIL_REPORT_EXTRACTION"
    fail 21 "A14 routed Vitis report extraction failed"
}
[[ -s "${POST_ROUTE_METRICS}" ]] || {
    A14_TARGET_VU37P_TIMING="FAIL_REPORT_EXTRACTION"
    fail 22 "A14 post-route metrics are missing"
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
    A14_TARGET_VU37P_TIMING="FAIL_TARGET_PART_MISMATCH"
    fail 23 "routed part mismatch: ${actual_part}"
}
[[ "${wns}" != "NOT_PARSED" && -n "${wns}" ]] || {
    A14_TARGET_VU37P_TIMING="FAIL_REPORT_EXTRACTION"
    fail 24 "A14 WNS was not parsed"
}

if awk -v wns="${wns}" -v tns="${tns}" -v endpoints="${failing_endpoints}" \
    'BEGIN {exit !((wns + 0.0) >= 0.0 && (tns + 0.0) == 0.0 && (endpoints + 0) == 0)}'
then
    A14_TARGET_VU37P_TIMING="PASS"
else
    A14_TARGET_VU37P_TIMING="FAIL"
    fail 25 "routed A14 F37X design did not meet timing: WNS=${wns}, TNS=${tns}, endpoints=${failing_endpoints}"
fi

sha256sum \
    "${XO_PATH}" \
    "${KERNEL_XML}" \
    "${COMPONENT_XML}" \
    "${XCLBIN_PATH}" \
    "${CONNECTIVITY_JSON}" \
    "${MEM_TOPOLOGY_JSON}" \
    "${IP_LAYOUT_JSON}" > "${HASH_OUTPUT}"

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
VPP_ERROR_COUNT=${vpp_errors}
VPP_CRITICAL_WARNING_COUNT=${vpp_critical}
SOURCE_SHA256=${SOURCE_HASH_OUTPUT}
ARTIFACT_SHA256=${HASH_OUTPUT}
XCLBIN_CONNECTIVITY_JSON=${CONNECTIVITY_JSON}
XCLBIN_MEM_TOPOLOGY_JSON=${MEM_TOPOLOGY_JSON}
XCLBIN_IP_LAYOUT_JSON=${IP_LAYOUT_JSON}
EOF

echo "A14_TARGET_XO_BUILD=${A14_TARGET_XO_BUILD}"
echo "A14_VPP_LINK=${A14_VPP_LINK}"
echo "A14_XCLBIN_BUILD=${A14_XCLBIN_BUILD}"
echo "A14_HBM0_LINK_MAPPING=${A14_HBM0_LINK_MAPPING}"
echo "A14_TARGET_VU37P_TIMING=${A14_TARGET_VU37P_TIMING}"
echo "A14_PHYSICAL_HBM_ACCESS=NOT_VALIDATED"
echo "A14_READY_FOR_BOARD=NO"
echo "XCLBIN_UUID=${XCLBIN_UUID}"
echo "STATUS=${STATUS}"
echo "NO FPGA ACCESS WAS PERFORMED"
