#!/usr/bin/env bash
# Build-only Stage 2N-A13 server flow for Vivado/Vitis 2020.2 and F37X.
#
# This script compiles the Host, packages the control-only RTL kernel, links a
# hardware xclbin, and reports the routed Vitis design. It never runs the Host,
# opens a render node, queries a device, programs an FPGA, or resets one.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

VITIS_SETTINGS="${VITIS_SETTINGS:-/opt/Xilinx/Vitis/2020.2/settings64.sh}"
PLATFORM="${PLATFORM:-/opt/xilinx/platforms/inspur_f37x_xdma_201920_3/inspur_f37x_xdma_201920_3.xpfm}"
PART_NAME="xcvu37p-fsvh2892-2L-e"
PLATFORM_VBNV="inspur_f37x_xdma_201920_3"
KERNEL_NAME="dlrm_f37x_rtl_kernel_stage2n_a13_v1"
CU_NAME="dlrm_a13_1"
KERNEL_FREQUENCY_MHZ="${KERNEL_FREQUENCY_MHZ:-100}"
JOBS="${JOBS:-8}"

HASH_MANIFEST="${REPO_ROOT}/A13_FILE_SHA256_VERIFIED.txt"
CONFIG="${REPO_ROOT}/config/stage2n_a13_v1.cfg"
PACKAGE_TCL="${REPO_ROOT}/scripts/package_stage2n_a13_rtl_kernel_v1.tcl"
POST_ROUTE_TCL="${REPO_ROOT}/scripts/report_stage2n_a13_vitis_post_route_v1.tcl"
HOST_BUILDER="${REPO_ROOT}/scripts/build_stage2n_a13_host_v1.sh"

BUILD_ROOT="${REPO_ROOT}/build/stage2n_a13"
XO_DIR="${BUILD_ROOT}/xo_v1"
XO_PATH="${XO_DIR}/${KERNEL_NAME}.xo"
KERNEL_XML="${XO_DIR}/kernel.xml"
COMPONENT_XML="${XO_DIR}/dlrm_f37x_stage2n_a13_ip_v1/component.xml"
LINK_DIR="${BUILD_ROOT}/vitis_link_v1"
TEMP_DIR="${LINK_DIR}/_x"
OUTPUT_DIR="${LINK_DIR}/hw"
XCLBIN_PATH="${OUTPUT_DIR}/${KERNEL_NAME}.xclbin"

RESULT_ROOT="${REPO_ROOT}/results/stage2n_a13/target_build_v1"
LOG_DIR="${RESULT_ROOT}/logs"
STATUS="${RESULT_ROOT}/a13_target_build_status.txt"
HASH_OUTPUT="${RESULT_ROOT}/a13_target_artifacts.sha256"
XCLBIN_INFO="${RESULT_ROOT}/${KERNEL_NAME}.xclbin.info"
PACKAGE_LOG="${LOG_DIR}/vivado_package_xo.log"
VPP_LOG="${LOG_DIR}/vpp_link.log"
POST_ROUTE_LOG="${LOG_DIR}/vivado_post_route_report.log"
POST_ROUTE_DIR="${RESULT_ROOT}/post_route"
POST_ROUTE_METRICS="${POST_ROUTE_DIR}/post_route_metrics.txt"

A13_TARGET_VU37P_TIMING="BLOCKED_NOT_RUN"
A13_HOST_XRT_BUILD="BLOCKED_NOT_RUN"
A13_XO_BUILD="BLOCKED_NOT_RUN"
A13_XCLBIN_BUILD="BLOCKED_NOT_RUN"
FAIL_REASON="NONE"
XCLBIN_UUID="NOT_AVAILABLE"
ROUTED_DCP="NOT_AVAILABLE"

write_status()
{
    cat > "${STATUS}" <<EOF
A13_TARGET_BUILD_FLOW=STAGE2N_A13_V1
A13_TARGET_VU37P_TIMING=${A13_TARGET_VU37P_TIMING}
A13_HOST_XRT_BUILD=${A13_HOST_XRT_BUILD}
A13_XO_BUILD=${A13_XO_BUILD}
A13_XCLBIN_BUILD=${A13_XCLBIN_BUILD}
A13_READY_FOR_BOARD=NO
READY_REASON=BOARD_AUTHORIZATION_AND_BOARD_VALIDATION_NOT_PERFORMED
FAIL_REASON=${FAIL_REASON}
TARGET_PART=${PART_NAME}
PLATFORM=${PLATFORM}
PLATFORM_VBNV=${PLATFORM_VBNV}
KERNEL=${KERNEL_NAME}
COMPUTE_UNIT=${CU_NAME}
REQUESTED_CLOCK_MHZ=${KERNEL_FREQUENCY_MHZ}
XO=${XO_PATH}
XCLBIN=${XCLBIN_PATH}
XCLBIN_UUID=${XCLBIN_UUID}
ROUTED_DCP=${ROUTED_DCP}
HOST_EXECUTION=NOT_RUN
FPGA_PROGRAMMING=NOT_RUN
FPGA_RESET=NOT_RUN
FPGA_DEVICE_ACCESS=NONE
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

for required in \
    "${VITIS_SETTINGS}" \
    "${PLATFORM}" \
    "${HASH_MANIFEST}" \
    "${CONFIG}" \
    "${PACKAGE_TCL}" \
    "${POST_ROUTE_TCL}" \
    "${HOST_BUILDER}"
do
    [[ -f "${required}" ]] || fail 4 "required input is missing: ${required}"
done

# shellcheck disable=SC1090
source "${VITIS_SETTINGS}" >/dev/null

for tool in git sha256sum vivado v++ xclbinutil unzip awk grep find python3; do
    command -v "${tool}" >/dev/null 2>&1 || fail 5 "required tool unavailable: ${tool}"
done

CURRENT_BRANCH="$(cd "${REPO_ROOT}" && git symbolic-ref --short HEAD 2>/dev/null || echo DETACHED)"
CURRENT_HEAD="$(cd "${REPO_ROOT}" && git rev-parse HEAD)"

set +e
(
    cd "${REPO_ROOT}"
    sha256sum -c "${HASH_MANIFEST}"
) > "${RESULT_ROOT}/a13_source_hash_check.txt" 2>&1
hash_exit="$?"
set -e
[[ "${hash_exit}" -eq 0 ]] || fail 6 "A13 source SHA256 verification failed"

set +e
bash "${HOST_BUILDER}" > "${LOG_DIR}/host_build.log" 2>&1
host_exit="$?"
set -e
if [[ "${host_exit}" -ne 0 ]]; then
    A13_HOST_XRT_BUILD="FAIL"
    fail 7 "A13 XRT Host build failed"
fi
if ! grep -Fxq 'A13_HOST_XRT_BUILD=PASS' \
    "${BUILD_ROOT}/host_v1/host_build_status.txt"
then
    A13_HOST_XRT_BUILD="FAIL"
    fail 8 "A13 Host build did not emit its PASS status"
fi
A13_HOST_XRT_BUILD="PASS"
write_status

set +e
vivado -mode batch -nolog -nojournal \
    -source "${PACKAGE_TCL}" 2>&1 | tee "${PACKAGE_LOG}"
package_exit="${PIPESTATUS[0]}"
set -e
if [[ "${package_exit}" -ne 0 ]]; then
    A13_XO_BUILD="FAIL"
    fail 9 "A13 XO packaging failed"
fi
if [[ ! -s "${XO_PATH}" || ! -s "${KERNEL_XML}" || ! -s "${COMPONENT_XML}" ]]; then
    A13_XO_BUILD="FAIL"
    fail 10 "A13 XO or generated metadata is missing or empty"
fi
if ! unzip -t "${XO_PATH}" >/dev/null; then
    A13_XO_BUILD="FAIL"
    fail 12 "A13 XO archive integrity failed"
fi
grep -qF "name=\"${KERNEL_NAME}\"" "${KERNEL_XML}" ||
    fail 13 "kernel.xml has the wrong kernel name"
for register_name in PIPE_BOTTOM_CYCLES PIPE_INTERACTION_CYCLES PIPE_TOP_CYCLES PIPE_TOTAL_CYCLES; do
    grep -qF "name=\"${register_name}\"" "${KERNEL_XML}" ||
        fail 14 "kernel.xml is missing ${register_name}"
done

export A13_KERNEL_NAME="${KERNEL_NAME}"
export A13_KERNEL_XML="${KERNEL_XML}"
export A13_COMPONENT_XML="${COMPONENT_XML}"
python3 - <<'PY' || fail 15 "A13 XO metadata validation failed"
import os
import xml.etree.ElementTree as ET

kernel_name = os.environ["A13_KERNEL_NAME"]
kernel = ET.parse(os.environ["A13_KERNEL_XML"]).getroot().find("kernel")
if kernel is None:
    raise SystemExit("kernel.xml has no kernel")
if kernel.get("name") != kernel_name:
    raise SystemExit("kernel.xml kernel name mismatch")
if kernel.get("hwControlProtocol") != "user_managed":
    raise SystemExit("kernel.xml control protocol is not user_managed")

port = kernel.find("./ports/port[@name='s_axi_control']")
if port is None:
    raise SystemExit("kernel.xml lacks s_axi_control")
expected_port = {
    "mode": "slave",
    "range": "0x1000",
    "dataWidth": "32",
    "portType": "addressable",
    "base": "0x0",
}
for key, expected in expected_port.items():
    if port.get(key) != expected:
        raise SystemExit("s_axi_control {} mismatch".format(key))
if any((node.get("name") or "").lower().startswith("m_axi")
       for node in kernel.findall("./ports/port")):
    raise SystemExit("unexpected m_axi port in kernel.xml")

args = {}
for arg in kernel.findall("./args/arg"):
    name = arg.get("name")
    if not name or name in args:
        raise SystemExit("unnamed or duplicate kernel argument")
    args[name] = int(arg.get("offset"), 0)

expected_counters = {
    "PIPE_BOTTOM_CYCLES": 0x218,
    "PIPE_INTERACTION_CYCLES": 0x21C,
    "PIPE_TOP_CYCLES": 0x220,
    "PIPE_TOTAL_CYCLES": 0x224,
}
if len(args) != 78:
    raise SystemExit("kernel.xml argument count is {}, expected 78".format(len(args)))
for name, offset in expected_counters.items():
    if args.get(name) != offset:
        raise SystemExit("{} offset mismatch".format(name))

component_root = ET.parse(os.environ["A13_COMPONENT_XML"]).getroot()
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
if len(registers) != 81:
    raise SystemExit("component register count is {}, expected 81".format(len(registers)))
for name, offset in expected_counters.items():
    if registers.get(name) != offset:
        raise SystemExit("component {} offset mismatch".format(name))
component_only = set(registers) - set(args)
if component_only != {"CONTROL_STATUS", "VERSION", "RESULT_COUNT"}:
    raise SystemExit("unexpected component-only register set")
print("A13_XO_METADATA_VALIDATION=PASS")
print("KERNEL_XML_ARGUMENT_COUNT=78")
print("COMPONENT_XML_REGISTER_COUNT=81")
print("M_AXI_PORT_COUNT=0")
PY
A13_XO_BUILD="PASS"
write_status

KERNEL_CU_SPEC="${KERNEL_NAME}:${CU_NAME}"
(( ${#KERNEL_CU_SPEC} <= 64 )) ||
    fail 15 "kernel/CU specification exceeds the Vitis 2020.2 64-character limit"

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
    A13_XCLBIN_BUILD="FAIL"
    fail 16 "Vitis hardware link failed"
fi
if [[ ! -s "${XCLBIN_PATH}" ]]; then
    A13_XCLBIN_BUILD="FAIL"
    fail 17 "Vitis link returned success without an xclbin"
fi
A13_XCLBIN_BUILD="BUILT_PENDING_VALIDATION"
write_status

vpp_errors="$(grep -cE '^ERROR:' "${VPP_LOG}" || true)"
vpp_critical="$(grep -cE '^CRITICAL WARNING:' "${VPP_LOG}" || true)"
if [[ "${vpp_errors}" != 0 ]]; then
    A13_XCLBIN_BUILD="FAIL_LOG_VALIDATION"
    fail 18 "v++ log contains ${vpp_errors} ERROR lines"
fi
if [[ "${vpp_critical}" != 0 ]]; then
    A13_XCLBIN_BUILD="FAIL_LOG_VALIDATION"
    fail 18 "v++ log contains ${vpp_critical} CRITICAL WARNING lines"
fi

xclbinutil --quiet --force --info "${XCLBIN_INFO}" --input "${XCLBIN_PATH}"
grep -qF "${KERNEL_NAME}" "${XCLBIN_INFO}" || fail 19 "xclbin kernel metadata mismatch"
grep -qF "${CU_NAME}" "${XCLBIN_INFO}" || fail 20 "xclbin CU metadata mismatch"
grep -qF "${PLATFORM_VBNV}" "${XCLBIN_INFO}" || fail 21 "xclbin platform metadata mismatch"
A13_XCLBIN_BUILD="PASS"
write_status

XCLBIN_UUID="$(sed -n 's/^[[:space:]]*UUID (xclbin):[[:space:]]*//p' "${XCLBIN_INFO}" | head -n 1)"
[[ -n "${XCLBIN_UUID}" ]] || XCLBIN_UUID="NOT_PARSED"

ROUTED_DCP="$(find "${TEMP_DIR}" -type f \( -name '*_routed.dcp' -o -name '*route_design*.dcp' \) -print -quit 2>/dev/null || true)"
[[ -n "${ROUTED_DCP}" && -s "${ROUTED_DCP}" ]] ||
    fail 22 "routed Vitis checkpoint was not found"
export A13_ROUTED_DCP="${ROUTED_DCP}"
export A13_REPORT_DIR="${POST_ROUTE_DIR}"

set +e
vivado -mode batch -nolog -nojournal \
    -source "${POST_ROUTE_TCL}" 2>&1 | tee "${POST_ROUTE_LOG}"
report_exit="${PIPESTATUS[0]}"
set -e
[[ "${report_exit}" -eq 0 ]] || fail 23 "routed Vitis report extraction failed"
[[ -s "${POST_ROUTE_METRICS}" ]] || fail 24 "post-route metrics are missing"

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
worst_startpoint="$(metric WORST_STARTPOINT)"
worst_endpoint="$(metric WORST_ENDPOINT)"
counter_path_hits="$(grep -cE 'bottom_cycle_count|interaction_cycle_count|top_cycle_count|total_cycle_count' \
    "${POST_ROUTE_DIR}/post_route_worst_setup_paths.rpt" || true)"
[[ "${actual_part}" == "${PART_NAME}" ]] ||
    fail 25 "routed part mismatch: ${actual_part}"
[[ "${wns}" != "NOT_PARSED" ]] || fail 26 "WNS was not parsed"

if awk -v wns="${wns}" -v tns="${tns}" -v endpoints="${failing_endpoints}" \
    'BEGIN {exit !((wns + 0.0) >= 0.0 && (tns + 0.0) == 0.0 && (endpoints + 0) == 0)}'
then
    A13_TARGET_VU37P_TIMING="PASS"
else
    A13_TARGET_VU37P_TIMING="FAIL"
    fail 27 "routed F37X design did not meet 100 MHz: WNS=${wns}, TNS=${tns}, endpoints=${failing_endpoints}"
fi

{
    sha256sum "${XO_PATH}"
    sha256sum "${KERNEL_XML}"
    sha256sum "${XCLBIN_PATH}"
    sha256sum "${BUILD_ROOT}/host_v1/stage2n_a13_cycle_counter_board_v1"
} > "${HASH_OUTPUT}"

write_status
cat >> "${STATUS}" <<EOF
GIT_BRANCH=${CURRENT_BRANCH}
GIT_HEAD=${CURRENT_HEAD}
WNS_NS=${wns}
TNS_NS=${tns}
FAILING_ENDPOINTS=${failing_endpoints}
WORST_STARTPOINT=${worst_startpoint}
WORST_ENDPOINT=${worst_endpoint}
A13_COUNTER_TOP100_PATH_TEXT_HITS=${counter_path_hits}
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
ARTIFACT_SHA256=${HASH_OUTPUT}
EOF

echo "A13_TARGET_VU37P_TIMING=${A13_TARGET_VU37P_TIMING}"
echo "A13_HOST_XRT_BUILD=${A13_HOST_XRT_BUILD}"
echo "A13_XO_BUILD=${A13_XO_BUILD}"
echo "A13_XCLBIN_BUILD=${A13_XCLBIN_BUILD}"
echo "A13_READY_FOR_BOARD=NO"
echo "XCLBIN_UUID=${XCLBIN_UUID}"
echo "STATUS=${STATUS}"
echo "NO FPGA ACCESS WAS PERFORMED"
