#!/usr/bin/env bash
#
# Stage 2N-A8: accept the already generated package_v3 XO without rerunning
# Vivado packaging.
#
# This script explains and validates the Vivado 2020.2 user-managed-kernel
# behavior observed in package_v3:
#   component.xml contains 77 registers;
#   kernel.xml exposes 74 host arguments;
#   CONTROL_STATUS, VERSION, and RESULT_COUNT at 0x000/0x004/0x008 remain in
#   component.xml but are omitted from kernel.xml by package_xo.
#
# No synthesis, implementation, XO rebuild, xclbin link, FPGA programming,
# render-node access, or reset is performed.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

EXPECTED_BRANCH="work/stage2n-a8-xo-xclbin"
KERNEL_NAME="dlrm_f37x_rtl_kernel_stage2n_a7"

PACKAGE_DIR="${REPO_ROOT}/build/stage2n_a8/package_v3"
XO_PATH="${PACKAGE_DIR}/${KERNEL_NAME}.xo"
KERNEL_XML="${PACKAGE_DIR}/kernel.xml"
IP_DIR="${PACKAGE_DIR}/dlrm_f37x_stage2n_a7_ip_v3"
COMPONENT_XML="${IP_DIR}/component.xml"

RESULT_DIR="${REPO_ROOT}/results/stage2n_a8/package_v3"
STATUS_FILE="${RESULT_DIR}/stage2n_a8_xo_artifact_accept_v1_status.txt"
DETAIL_FILE="${RESULT_DIR}/stage2n_a8_xo_artifact_accept_v1_details.txt"

fail()
{
    local code="$1"
    shift
    local reason="$*"

    mkdir -p "${RESULT_DIR}"

    cat > "${STATUS_FILE}" <<EOF
STAGE2N_A8_XO_ARTIFACT_ACCEPT_V1_FAILED
REASON=${reason}
EXIT_CODE=${code}
KERNEL=${KERNEL_NAME}
XO=${XO_PATH}
KERNEL_XML=${KERNEL_XML}
COMPONENT_XML=${COMPONENT_XML}
NO_VIVADO_PACKAGING_RERUN=1
NO_XCLBIN_LINK=1
NO_FPGA_PROGRAMMING_OR_RESET=1
EOF

    echo "ERROR: ${reason}" >&2
    exit "${code}"
}

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
    fail 2 "wrong branch: ${CURRENT_BRANCH}; expected ${EXPECTED_BRANCH}"

command -v python >/dev/null 2>&1 ||
    fail 3 "python is unavailable"

command -v unzip >/dev/null 2>&1 ||
    fail 4 "unzip is unavailable"

[[ -s "${XO_PATH}" ]] ||
    fail 5 "XO is missing or empty: ${XO_PATH}"

[[ -s "${KERNEL_XML}" ]] ||
    fail 6 "kernel.xml is missing or empty: ${KERNEL_XML}"

[[ -s "${COMPONENT_XML}" ]] ||
    fail 7 "component.xml is missing or empty: ${COMPONENT_XML}"

mkdir -p "${RESULT_DIR}"
rm -f "${STATUS_FILE}" "${DETAIL_FILE}"

echo "============================================================"
echo "Stage 2N-A8 package_v3 XO artifact acceptance v1"
echo "REPO=${REPO_ROOT}"
echo "BRANCH=${CURRENT_BRANCH}"
echo "HEAD=${CURRENT_HEAD}"
echo "KERNEL=${KERNEL_NAME}"
echo "XO=${XO_PATH}"
echo "KERNEL_XML=${KERNEL_XML}"
echo "COMPONENT_XML=${COMPONENT_XML}"
echo "NO VIVADO PACKAGING RERUN"
echo "NO XCLBIN LINK"
echo "NO FPGA PROGRAMMING OR RESET"
echo "============================================================"

unzip -t "${XO_PATH}" >/dev/null ||
    fail 8 "XO ZIP integrity test failed"

export STAGE2N_A8_KERNEL_NAME="${KERNEL_NAME}"
export STAGE2N_A8_KERNEL_XML="${KERNEL_XML}"
export STAGE2N_A8_COMPONENT_XML="${COMPONENT_XML}"
export STAGE2N_A8_XO="${XO_PATH}"
export STAGE2N_A8_DETAIL_FILE="${DETAIL_FILE}"

set +e
python - <<'PY'
from __future__ import annotations

import os
import sys
import zipfile
import xml.etree.ElementTree as ET
from pathlib import Path

kernel_name = os.environ["STAGE2N_A8_KERNEL_NAME"]
kernel_xml_path = Path(os.environ["STAGE2N_A8_KERNEL_XML"])
component_xml_path = Path(os.environ["STAGE2N_A8_COMPONENT_XML"])
xo_path = Path(os.environ["STAGE2N_A8_XO"])
detail_path = Path(os.environ["STAGE2N_A8_DETAIL_FILE"])

def fail(message: str) -> None:
    print(f"VALIDATION_ERROR={message}", file=sys.stderr)
    raise SystemExit(20)

def parse_int(text: str | None) -> int:
    if text is None:
        fail("missing numeric XML value")
    return int(text, 0)

# -------------------------------------------------------------------------
# Validate package_xo kernel.xml.
# -------------------------------------------------------------------------
kernel_tree = ET.parse(kernel_xml_path)
kernel_root = kernel_tree.getroot()
kernel = kernel_root.find("kernel")
if kernel is None:
    fail("kernel.xml has no kernel element")

if kernel.get("name") != kernel_name:
    fail(
        f"kernel.xml kernel name is {kernel.get('name')!r}, "
        f"expected {kernel_name!r}"
    )

if kernel.get("hwControlProtocol") != "user_managed":
    fail(
        "kernel.xml hwControlProtocol is not user_managed"
    )

ports = {
    port.get("name"): port
    for port in kernel.findall("./ports/port")
}
if "s_axi_control" not in ports:
    fail("kernel.xml is missing s_axi_control")

axi_port = ports["s_axi_control"]
expected_port_attributes = {
    "mode": "slave",
    "range": "0x1000",
    "dataWidth": "32",
    "portType": "addressable",
    "base": "0x0",
}
for key, expected in expected_port_attributes.items():
    actual = axi_port.get(key)
    if actual != expected:
        fail(
            f"s_axi_control {key} is {actual!r}, expected {expected!r}"
        )

kernel_args: dict[str, int] = {}
kernel_arg_ids: set[int] = set()
kernel_offsets: set[int] = set()

for arg in kernel.findall("./args/arg"):
    name = arg.get("name")
    if not name:
        fail("kernel.xml contains an unnamed argument")
    if name in kernel_args:
        fail(f"kernel.xml duplicates argument {name}")

    offset = parse_int(arg.get("offset"))
    arg_id = parse_int(arg.get("id"))

    if offset in kernel_offsets:
        fail(f"kernel.xml duplicates offset 0x{offset:x}")
    if arg_id in kernel_arg_ids:
        fail(f"kernel.xml duplicates argument id {arg_id}")

    kernel_args[name] = offset
    kernel_offsets.add(offset)
    kernel_arg_ids.add(arg_id)

expected_kernel_args = {
    "LAYER_COUNT": 0x010,
    "INITIAL_BUFFER": 0x014,
    "RESULT_META": 0x0A8,
    "INT_CONTROL_STATUS": 0x100,
    "INT_LOADED_MASK": 0x130,
    "PIPE_CONTROL_STATUS": 0x180,
    "PIPE_VERSION": 0x184,
    "PIPE_RESULT_DATA": 0x200,
    "PIPE_CONFIG_READY": 0x214,
}
for name, expected_offset in expected_kernel_args.items():
    actual_offset = kernel_args.get(name)
    if actual_offset != expected_offset:
        fail(
            f"kernel.xml {name} offset is "
            f"{None if actual_offset is None else hex(actual_offset)}, "
            f"expected {hex(expected_offset)}"
        )

if len(kernel_args) != 74:
    fail(
        f"kernel.xml argument count is {len(kernel_args)}, expected 74"
    )

# -------------------------------------------------------------------------
# Validate IP-XACT component.xml.
# -------------------------------------------------------------------------
component_tree = ET.parse(component_xml_path)
component_root = component_tree.getroot()

ns_uri = ""
if component_root.tag.startswith("{"):
    ns_uri = component_root.tag[1:].split("}", 1)[0]
if not ns_uri:
    fail("component.xml has no XML namespace")

ns = {"spirit": ns_uri}
component_registers: dict[str, int] = {}

for register in component_root.findall(".//spirit:register", ns):
    name_node = register.find("spirit:name", ns)
    offset_node = register.find("spirit:addressOffset", ns)
    if name_node is None or offset_node is None:
        fail("component.xml contains an incomplete register")

    name = (name_node.text or "").strip()
    offset_text = (offset_node.text or "").strip()
    if not name or not offset_text:
        fail("component.xml contains an empty register name or offset")
    if name in component_registers:
        fail(f"component.xml duplicates register {name}")

    component_registers[name] = int(offset_text, 0)

expected_component_registers = {
    "CONTROL_STATUS": 0x000,
    "VERSION": 0x004,
    "RESULT_COUNT": 0x008,
    **expected_kernel_args,
}
for name, expected_offset in expected_component_registers.items():
    actual_offset = component_registers.get(name)
    if actual_offset != expected_offset:
        fail(
            f"component.xml {name} offset is "
            f"{None if actual_offset is None else hex(actual_offset)}, "
            f"expected {hex(expected_offset)}"
        )

if len(component_registers) != 77:
    fail(
        "component.xml register count is "
        f"{len(component_registers)}, expected 77"
    )

component_names = set(component_registers)
kernel_names = set(kernel_args)
component_only = component_names - kernel_names
kernel_only = kernel_names - component_names

expected_component_only = {
    "CONTROL_STATUS",
    "VERSION",
    "RESULT_COUNT",
}

if component_only != expected_component_only:
    fail(
        "component.xml minus kernel.xml is "
        f"{sorted(component_only)}, expected "
        f"{sorted(expected_component_only)}"
    )

if kernel_only:
    fail(
        "kernel.xml contains names absent from component.xml: "
        f"{sorted(kernel_only)}"
    )

# -------------------------------------------------------------------------
# Validate XO contents.
# -------------------------------------------------------------------------
with zipfile.ZipFile(xo_path, "r") as archive:
    members = archive.namelist()

required_member_suffixes = {
    "kernel.xml",
    "component.xml",
    "dlrm_f37x_rtl_kernel_stage2n_a7.sv",
    "dlrm_internal_pipeline_axi_lite_adapter_stage2n_a7.sv",
    "dlrm_internal_pipeline_controller.sv",
    "mlp_sequence_controller_segmented.sv",
    "dlrm_feature_interaction_engine.sv",
}
for suffix in required_member_suffixes:
    if not any(member.endswith(suffix) for member in members):
        fail(f"XO is missing archive member ending with {suffix}")

details = [
    "STAGE2N_A8_XO_ARTIFACT_ACCEPT_V1_DETAILS",
    f"KERNEL={kernel_name}",
    f"KERNEL_XML_ARG_COUNT={len(kernel_args)}",
    f"COMPONENT_XML_REGISTER_COUNT={len(component_registers)}",
    "COMPONENT_ONLY_REGISTERS="
    + ",".join(sorted(component_only)),
    "KERNEL_XML_LOW_CONTROL_REGISTERS_OMITTED_BY_PACKAGE_XO=1",
    "LEGACY_MLP_WINDOW_PRESENT=1",
    "STANDALONE_INTERACTION_WINDOW_PRESENT=1",
    "AUTOMATIC_PIPELINE_WINDOW_PRESENT=1",
    f"XO_ARCHIVE_MEMBER_COUNT={len(members)}",
]
detail_path.write_text("\n".join(details) + "\n", encoding="ascii")

print(f"KERNEL_XML_ARG_COUNT={len(kernel_args)}")
print(
    "COMPONENT_XML_REGISTER_COUNT="
    f"{len(component_registers)}"
)
print(
    "COMPONENT_ONLY_REGISTERS="
    + ",".join(sorted(component_only))
)
print("KERNEL_XML_LOW_CONTROL_REGISTERS_OMITTED_BY_PACKAGE_XO=1")
print("LEGACY_MLP_WINDOW_PRESENT=1")
print("STANDALONE_INTERACTION_WINDOW_PRESENT=1")
print("AUTOMATIC_PIPELINE_WINDOW_PRESENT=1")
print("XO_XML_AND_SOURCE_CONTENTS_VALID=1")
PY
PY_EXIT="$?"
set -e

[[ "${PY_EXIT}" -eq 0 ]] ||
    fail "${PY_EXIT}" "XML/XO semantic validation failed"

XO_SIZE_BYTES="$(stat -c '%s' "${XO_PATH}")"
KERNEL_XML_SIZE_BYTES="$(stat -c '%s' "${KERNEL_XML}")"
COMPONENT_XML_SIZE_BYTES="$(stat -c '%s' "${COMPONENT_XML}")"

XO_SHA256="$(sha256sum "${XO_PATH}" | awk '{print $1}')"
KERNEL_XML_SHA256="$(
    sha256sum "${KERNEL_XML}" |
    awk '{print $1}'
)"
COMPONENT_XML_SHA256="$(
    sha256sum "${COMPONENT_XML}" |
    awk '{print $1}'
)"

cat > "${STATUS_FILE}" <<EOF
STAGE2N_A8_XO_ARTIFACT_ACCEPT_V1_PASS
KERNEL=${KERNEL_NAME}
GIT_BRANCH=${CURRENT_BRANCH}
GIT_HEAD=${CURRENT_HEAD}
XO=${XO_PATH}
XO_SIZE_BYTES=${XO_SIZE_BYTES}
XO_SHA256=${XO_SHA256}
KERNEL_XML=${KERNEL_XML}
KERNEL_XML_SIZE_BYTES=${KERNEL_XML_SIZE_BYTES}
KERNEL_XML_SHA256=${KERNEL_XML_SHA256}
KERNEL_XML_ARG_COUNT=74
COMPONENT_XML=${COMPONENT_XML}
COMPONENT_XML_SIZE_BYTES=${COMPONENT_XML_SIZE_BYTES}
COMPONENT_XML_SHA256=${COMPONENT_XML_SHA256}
COMPONENT_XML_REGISTER_COUNT=77
COMPONENT_ONLY_REGISTERS=CONTROL_STATUS,RESULT_COUNT,VERSION
KERNEL_XML_LOW_CONTROL_REGISTERS_OMITTED_BY_PACKAGE_XO=1
LEGACY_MLP_WINDOW_PRESENT=1
STANDALONE_INTERACTION_WINDOW_PRESENT=1
AUTOMATIC_PIPELINE_WINDOW_PRESENT=1
XO_ARCHIVE_INTEGRITY_VALID=1
DETAILS=${DETAIL_FILE}
NO_VIVADO_PACKAGING_RERUN=1
NO_XCLBIN_LINK=1
NO_FPGA_PROGRAMMING_OR_RESET=1
EOF

echo "============================================================"
echo "STAGE2N_A8_XO_ARTIFACT_ACCEPT_V1_PASS"
echo "XO=${XO_PATH}"
echo "XO_SIZE_BYTES=${XO_SIZE_BYTES}"
echo "XO_SHA256=${XO_SHA256}"
echo "KERNEL_XML_ARG_COUNT=74"
echo "COMPONENT_XML_REGISTER_COUNT=77"
echo "COMPONENT_ONLY_REGISTERS=CONTROL_STATUS,RESULT_COUNT,VERSION"
echo "STATUS=${STATUS_FILE}"
echo "NO VIVADO PACKAGING RERUN"
echo "NO XCLBIN LINK"
echo "NO FPGA PROGRAMMING OR RESET"
echo "============================================================"
