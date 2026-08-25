#!/usr/bin/env bash
# Stage 2N-A14.5 exact-target XO-only runner.
#
# Packages and validates the runtime TABLE_BASE ABI on Vivado 2020.2.  It does
# not invoke v++, link or generate an xclbin, bind physical HBM, open XRT, touch
# a device, program/reset an FPGA, or overwrite an earlier A14 build/result.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

VITIS_SETTINGS="${VITIS_SETTINGS:-/opt/Xilinx/Vitis/2020.2/settings64.sh}"
PART_NAME="xcvu37p-fsvh2892-2L-e"
KERNEL_NAME="dlrm_f37x_rtl_kernel_stage2n_a14_v2"

PACKAGE_TCL="${REPO_ROOT}/scripts/package_stage2n_a14_rtl_kernel_v3.tcl"
LOOKUP_RTL="${REPO_ROOT}/rtl/hbm/dlrm_hbm_embedding_lookup_stage2n_a14_v2.sv"
WRAPPER_RTL="${REPO_ROOT}/rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a14_v2.sv"

XO_DIR="${REPO_ROOT}/build/stage2n_a14/xo_v2"
XO_PATH="${XO_DIR}/${KERNEL_NAME}.xo"
KERNEL_XML="${XO_DIR}/kernel.xml"
COMPONENT_XML="${XO_DIR}/dlrm_f37x_stage2n_a14_ip_v2/component.xml"

RESULT_ROOT="${REPO_ROOT}/results/stage2n_a14_5/target_xo_v1"
LOG_DIR="${RESULT_ROOT}/logs"
STATUS="${RESULT_ROOT}/a14_5_target_xo_status.txt"
SOURCE_HASH_OUTPUT="${RESULT_ROOT}/a14_5_target_sources.sha256"
ARTIFACT_HASH_OUTPUT="${RESULT_ROOT}/a14_5_target_artifacts.sha256"
PACKAGE_LOG="${LOG_DIR}/vivado_package_xo.log"
TOOL_VERSION_LOG="${LOG_DIR}/tool_versions.log"
GIT_STATUS_FILE="${RESULT_ROOT}/git_status_porcelain.txt"
INTERNAL_KERNEL_XML="${RESULT_ROOT}/kernel_xml_inside_xo.xml"

A14_5_TARGET_XO_BUILD="BLOCKED_NOT_RUN"
A14_5_TABLE_BASE_ABI="NOT_VALIDATED"
FAIL_REASON="NONE"
CURRENT_BRANCH="NOT_RECORDED"
CURRENT_HEAD="NOT_RECORDED"

write_status()
{
    cat > "${STATUS}" <<EOF
A14_5_FLOW=STAGE2N_A14_5_TARGET_XO_V1
A14_5_TARGET_XO_BUILD=${A14_5_TARGET_XO_BUILD}
A14_5_TABLE_BASE_ABI=${A14_5_TABLE_BASE_ABI}
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
    "${LOOKUP_RTL}" \
    "${WRAPPER_RTL}"
do
    [[ -f "${required}" ]] || fail 4 "required input is missing: ${required}"
done

# shellcheck disable=SC1090
source "${VITIS_SETTINGS}" >/dev/null

for tool in git sha256sum vivado unzip grep python3 cmp; do
    command -v "${tool}" >/dev/null 2>&1 ||
        fail 5 "required tool unavailable after sourcing Vitis: ${tool}"
done

CURRENT_BRANCH="$(cd "${REPO_ROOT}" && git symbolic-ref --short HEAD 2>/dev/null || echo DETACHED)"
CURRENT_HEAD="$(cd "${REPO_ROOT}" && git rev-parse HEAD)"
(cd "${REPO_ROOT}" && git status --porcelain) > "${GIT_STATUS_FILE}"
write_status

vivado -version > "${TOOL_VERSION_LOG}" 2>&1
sha256sum \
    "${LOOKUP_RTL}" \
    "${WRAPPER_RTL}" \
    "${PACKAGE_TCL}" > "${SOURCE_HASH_OUTPUT}"

set +e
vivado -mode batch -nolog -nojournal \
    -source "${PACKAGE_TCL}" 2>&1 | tee "${PACKAGE_LOG}"
package_exit="${PIPESTATUS[0]}"
set -e
if [[ "${package_exit}" -ne 0 ]]; then
    A14_5_TARGET_XO_BUILD="FAIL"
    fail 6 "A14.5 target-part XO packaging failed"
fi

if [[ ! -s "${XO_PATH}" || ! -s "${KERNEL_XML}" ||
      ! -s "${COMPONENT_XML}" ]]; then
    A14_5_TARGET_XO_BUILD="FAIL"
    fail 7 "A14.5 XO or generated metadata is missing or empty"
fi
unzip -t "${XO_PATH}" >/dev/null || {
    A14_5_TARGET_XO_BUILD="FAIL"
    fail 8 "A14.5 XO archive integrity failed"
}
grep -Fxq "TARGET_PART_USED=1" "${PACKAGE_LOG}" || {
    A14_5_TARGET_XO_BUILD="FAIL"
    fail 9 "A14.5 XO was not packaged with the exact VU37P target part"
}

unzip -p "${XO_PATH}" '*/kernel.xml' > "${INTERNAL_KERNEL_XML}"
[[ -s "${INTERNAL_KERNEL_XML}" ]] || {
    A14_5_TARGET_XO_BUILD="FAIL"
    fail 10 "kernel.xml is missing inside the XO"
}
cmp -s "${KERNEL_XML}" "${INTERNAL_KERNEL_XML}" || {
    A14_5_TARGET_XO_BUILD="FAIL"
    fail 10 "standalone and in-XO kernel.xml differ"
}

export A14_5_KERNEL_NAME="${KERNEL_NAME}"
export A14_5_KERNEL_XML="${KERNEL_XML}"
export A14_5_COMPONENT_XML="${COMPONENT_XML}"
python3 - <<'PY' || {
import os
import xml.etree.ElementTree as ET

kernel_name = os.environ["A14_5_KERNEL_NAME"]
root = ET.parse(os.environ["A14_5_KERNEL_XML"]).getroot()
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
    raise SystemExit("m_axi_gmem data metadata mismatch")
if int(memory.get("range", "0"), 0) != 0xFFFFFFFFFFFFFFFF:
    raise SystemExit("m_axi_gmem address range is not 64-bit")

args = {}
for arg in kernel.findall("./args/arg"):
    name = arg.get("name")
    if not name or name in args:
        raise SystemExit("unnamed or duplicate kernel argument")
    args[name] = arg

expected_offsets = {
    "LOOKUP_INDEX": 0x10,
    "TABLE_BASE": 0x18,
    "RESULT0": 0x20,
    "RESULT1": 0x24,
    "RESULT2": 0x28,
    "RESULT3": 0x2C,
}
actual_offsets = {name: int(arg.get("offset"), 0) for name, arg in args.items()}
if actual_offsets != expected_offsets:
    raise SystemExit("kernel.xml argument map mismatch: {}".format(actual_offsets))

table_base = args["TABLE_BASE"]
if table_base.get("addressQualifier") != "1":
    raise SystemExit("TABLE_BASE is not a global-memory argument")
if table_base.get("port") != "m_axi_gmem":
    raise SystemExit("TABLE_BASE is not bound to m_axi_gmem")
if int(table_base.get("size", "0"), 0) != 8:
    raise SystemExit("TABLE_BASE size is not 64-bit")
if int(table_base.get("hostSize", "0"), 0) != 8:
    raise SystemExit("TABLE_BASE host size is not 64-bit")

for name, arg in args.items():
    if name == "TABLE_BASE":
        continue
    if arg.get("addressQualifier") != "0" or arg.get("port") != "s_axi_control":
        raise SystemExit("scalar argument metadata mismatch for {}".format(name))

component_root = ET.parse(os.environ["A14_5_COMPONENT_XML"]).getroot()
namespace = component_root.tag[1:].split("}", 1)[0]
ns = {"spirit": namespace}
registers = {}
for register in component_root.findall(".//spirit:register", ns):
    name_node = register.find("spirit:name", ns)
    offset_node = register.find("spirit:addressOffset", ns)
    size_node = register.find("spirit:size", ns)
    if name_node is None or offset_node is None or size_node is None:
        raise SystemExit("incomplete component register")
    name = (name_node.text or "").strip()
    if name in registers:
        raise SystemExit("duplicate component register {}".format(name))
    registers[name] = (
        int((offset_node.text or "").strip(), 0),
        int((size_node.text or "").strip(), 0),
    )

expected_registers = {
    "CONTROL": (0x00, 32),
    "LOOKUP_INDEX": (0x10, 32),
    "TABLE_BASE": (0x18, 64),
    "RESULT0": (0x20, 32),
    "RESULT1": (0x24, 32),
    "RESULT2": (0x28, 32),
    "RESULT3": (0x2C, 32),
}
if registers != expected_registers:
    raise SystemExit("component.xml register map mismatch: {}".format(registers))

print("A14_5_TARGET_XO_METADATA_VALIDATION=PASS")
print("KERNEL_XML_ARGUMENT_COUNT=6")
print("COMPONENT_XML_REGISTER_COUNT=7")
print("TABLE_BASE_ADDRESS_QUALIFIER=1")
print("TABLE_BASE_PORT=m_axi_gmem")
print("TABLE_BASE_OFFSET=0x18")
print("TABLE_BASE_SIZE_BYTES=8")
print("M_AXI_GMEM_DATA_WIDTH=128")
print("M_AXI_GMEM_ADDRESS_RANGE=0xFFFFFFFFFFFFFFFF")
PY
    A14_5_TARGET_XO_BUILD="FAIL"
    fail 11 "A14.5 XO metadata validation failed"
}

A14_5_TARGET_XO_BUILD="PASS"
A14_5_TABLE_BASE_ABI="PASS"
write_status

sha256sum \
    "${XO_PATH}" \
    "${KERNEL_XML}" \
    "${COMPONENT_XML}" \
    "${INTERNAL_KERNEL_XML}" > "${ARTIFACT_HASH_OUTPUT}"

cat >> "${STATUS}" <<EOF
SOURCE_SHA256=${SOURCE_HASH_OUTPUT}
ARTIFACT_SHA256=${ARTIFACT_HASH_OUTPUT}
PACKAGE_LOG=${PACKAGE_LOG}
XO_SIZE_BYTES=$(wc -c < "${XO_PATH}")
NO_VPP_LINK=1
NO_XCLBIN=1
NO_PHYSICAL_HBM_BINDING=1
NO_FPGA_ACCESS=1
EOF

echo "A14_5_TARGET_XO_BUILD=PASS"
echo "A14_5_TABLE_BASE_ABI=PASS"
echo "A14_5_VPP_LINK=NOT_RUN"
echo "A14_5_XCLBIN=NOT_GENERATED"
echo "A14_5_PHYSICAL_HBM=NOT_VALIDATED"
echo "A14_5_FPGA_DEVICE_ACCESS=NONE"
echo "STATUS=${STATUS}"
