#!/usr/bin/env bash
#
# Stage 2N-A10 v2 XO packaging and metadata validation.
#
# Creates:
#   build/stage2n_a10/package_v2/
#     dlrm_f37x_rtl_kernel_stage2n_a10.xo
#     kernel.xml
#
# This script does not run synthesis/place/route, link an xclbin, access a
# render node, program an FPGA, or reset a board.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

VIVADO_SETTINGS="${VIVADO_SETTINGS:-/opt/Xilinx/Vivado/2020.2/settings64.sh}"
VIVADO_BIN="${VIVADO_BIN:-vivado}"

EXPECTED_BRANCH="work/stage2n-a10-model-batch-regression"
KERNEL_NAME="dlrm_f37x_rtl_kernel_stage2n_a10_v2"
PART_NAME="xcvu37p-fsvh2892-2L-e"

TCL_SCRIPT="${REPO_ROOT}/tcl/package_stage2n_a10_xo_v2.tcl"
BUILD_DIR="${REPO_ROOT}/build/stage2n_a10/package_v2"
IP_DIR="${BUILD_DIR}/dlrm_f37x_stage2n_a10_ip_v2"
XO_PATH="${BUILD_DIR}/${KERNEL_NAME}.xo"
KERNEL_XML="${BUILD_DIR}/kernel.xml"
COMPONENT_XML="${IP_DIR}/component.xml"

LOG_DIR="${REPO_ROOT}/logs"
RESULT_DIR="${REPO_ROOT}/results/stage2n_a10/package_v2"
VIVADO_LOG="${LOG_DIR}/vivado_stage2n_a10_xo_package_v2.log"
STATUS_FILE="${RESULT_DIR}/stage2n_a10_xo_package_v2_status.txt"
DETAIL_FILE="${RESULT_DIR}/stage2n_a10_xo_package_v2_details.txt"

fail()
{
    local code="$1"
    shift
    local reason="$*"

    mkdir -p "${RESULT_DIR}"
    cat > "${STATUS_FILE}" <<EOF
STAGE2N_A10_XO_PACKAGE_V2_FAILED
REASON=${reason}
EXIT_CODE=${code}
KERNEL=${KERNEL_NAME}
PART=${PART_NAME}
XO=${XO_PATH}
KERNEL_XML=${KERNEL_XML}
COMPONENT_XML=${COMPONENT_XML}
LOG=${VIVADO_LOG}
NO_SYNTH_PLACE_ROUTE=1
NO_XCLBIN_LINK=1
NO_FPGA_PROGRAMMING_OR_RESET=1
EOF

    echo "ERROR: ${reason}" >&2
    exit "${code}"
}

[[ -f "${VIVADO_SETTINGS}" ]] ||
    fail 2 "Vivado settings not found: ${VIVADO_SETTINGS}"

[[ -f "${TCL_SCRIPT}" ]] ||
    fail 3 "packaging Tcl not found: ${TCL_SCRIPT}"

# shellcheck disable=SC1090
source "${VIVADO_SETTINGS}" >/dev/null

command -v "${VIVADO_BIN}" >/dev/null 2>&1 ||
    fail 4 "Vivado executable is unavailable"

command -v unzip >/dev/null 2>&1 ||
    fail 5 "unzip is unavailable"

command -v python >/dev/null 2>&1 ||
    fail 6 "python is unavailable"

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
    fail 7 "wrong branch: ${CURRENT_BRANCH}; expected ${EXPECTED_BRANCH}"

for required_source in \
    rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a10_v2.sv \
    rtl/f37x/dlrm_internal_pipeline_axi_lite_adapter_stage2n_a10_v2.sv \
    rtl/pipeline/dlrm_internal_pipeline_controller.sv \
    rtl/control/mlp_sequence_controller_segmented.sv \
    rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a2.sv
do
    [[ -s "${REPO_ROOT}/${required_source}" ]] ||
        fail 8 "required source is missing or empty: ${required_source}"
done

grep -qF "module ${KERNEL_NAME}" \
    "${REPO_ROOT}/rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a10_v2.sv" ||
    fail 9 "A10 top module declaration is missing"

grep -qF "module dlrm_internal_pipeline_axi_lite_adapter_stage2n_a10_v2" \
    "${REPO_ROOT}/rtl/f37x/dlrm_internal_pipeline_axi_lite_adapter_stage2n_a10_v2.sv" ||
    fail 10 "A10 adapter module declaration is missing"

grep -qF "parameter integer MAX_LAYERS = 8" \
    "${REPO_ROOT}/rtl/f37x/dlrm_internal_pipeline_axi_lite_adapter_stage2n_a10_v2.sv" ||
    fail 11 "A10 MAX_LAYERS is not 8"

grep -qF "parameter integer MAX_WEIGHT_VALUES = 2048" \
    "${REPO_ROOT}/rtl/f37x/dlrm_internal_pipeline_axi_lite_adapter_stage2n_a10_v2.sv" ||
    fail 12 "A10 MAX_WEIGHT_VALUES is not 2048"

grep -qF "parameter integer MAX_BIAS_VALUES = 128" \
    "${REPO_ROOT}/rtl/f37x/dlrm_internal_pipeline_axi_lite_adapter_stage2n_a10_v2.sv" ||
    fail 13 "A10 MAX_BIAS_VALUES is not 128"

grep -qF "32'h0002_4E11" \
    "${REPO_ROOT}/rtl/f37x/dlrm_internal_pipeline_axi_lite_adapter_stage2n_a10_v2.sv" ||
    fail 14 "A10 pipeline version 0x00024E11 is missing"

mkdir -p "${LOG_DIR}" "${RESULT_DIR}"
rm -f \
    "${VIVADO_LOG}" \
    "${STATUS_FILE}" \
    "${DETAIL_FILE}"

START_TIME="$(date -Is)"
START_EPOCH="$(date +%s)"

echo "============================================================"
echo "Stage 2N-A10 v2 XO packaging"
echo "TIME=${START_TIME}"
echo "REPO=${REPO_ROOT}"
echo "BRANCH=${CURRENT_BRANCH}"
echo "HEAD=${CURRENT_HEAD}"
echo "PART=${PART_NAME}"
echo "KERNEL=${KERNEL_NAME}"
echo "PIPELINE_VERSION=0x00024E11"
echo "MAX_LAYERS=8"
echo "MAX_WEIGHT_VALUES=2048"
echo "MAX_BIAS_VALUES=128"
echo "XO=${XO_PATH}"
echo "NO SYNTH/PLACE/ROUTE"
echo "NO XCLBIN LINK"
echo "NO FPGA PROGRAMMING OR RESET"
echo "============================================================"

set +e
"${VIVADO_BIN}" \
    -mode batch \
    -nolog \
    -nojournal \
    -source "${TCL_SCRIPT}" \
    2>&1 | tee "${VIVADO_LOG}"
VIVADO_EXIT="${PIPESTATUS[0]}"
set -e

END_TIME="$(date -Is)"
END_EPOCH="$(date +%s)"
ELAPSED_SECONDS="$((END_EPOCH - START_EPOCH))"

[[ "${VIVADO_EXIT}" -eq 0 ]] ||
    fail "${VIVADO_EXIT}" "Vivado XO packaging failed; inspect ${VIVADO_LOG}"

[[ -s "${XO_PATH}" ]] ||
    fail 15 "XO was not generated or is empty: ${XO_PATH}"

[[ -s "${KERNEL_XML}" ]] ||
    fail 16 "kernel.xml was not generated or is empty: ${KERNEL_XML}"

[[ -s "${COMPONENT_XML}" ]] ||
    fail 17 "component.xml was not generated or is empty: ${COMPONENT_XML}"

ERROR_COUNT="$(grep -cE '^ERROR:' "${VIVADO_LOG}" || true)"
CRITICAL_WARNING_COUNT="$(
    grep -cE '^CRITICAL WARNING:' "${VIVADO_LOG}" || true
)"

[[ "${ERROR_COUNT}" == "0" ]] ||
    fail 18 "Vivado log contains ${ERROR_COUNT} anchored ERROR lines"

[[ "${CRITICAL_WARNING_COUNT}" == "0" ]] ||
    fail 19 "Vivado log contains ${CRITICAL_WARNING_COUNT} critical warnings"

unzip -t "${XO_PATH}" >/dev/null ||
    fail 20 "XO archive integrity test failed"

export A10_KERNEL_NAME="${KERNEL_NAME}"
export A10_KERNEL_XML="${KERNEL_XML}"
export A10_COMPONENT_XML="${COMPONENT_XML}"
export A10_XO_PATH="${XO_PATH}"
export A10_DETAIL_FILE="${DETAIL_FILE}"

set +e
python - <<'PY'
from __future__ import annotations

import os
import sys
import zipfile
import xml.etree.ElementTree as ET
from pathlib import Path

kernel_name = os.environ["A10_KERNEL_NAME"]
kernel_xml_path = Path(os.environ["A10_KERNEL_XML"])
component_xml_path = Path(os.environ["A10_COMPONENT_XML"])
xo_path = Path(os.environ["A10_XO_PATH"])
detail_path = Path(os.environ["A10_DETAIL_FILE"])

def fail(message: str) -> None:
    print(f"VALIDATION_ERROR={message}", file=sys.stderr)
    raise SystemExit(30)

def parse_int(text: str | None) -> int:
    if text is None:
        fail("missing numeric XML value")
    return int(text, 0)

kernel_root = ET.parse(kernel_xml_path).getroot()
kernel = kernel_root.find("kernel")
if kernel is None:
    fail("kernel.xml has no kernel element")

if kernel.get("name") != kernel_name:
    fail(
        f"kernel.xml name is {kernel.get('name')!r}, "
        f"expected {kernel_name!r}"
    )

if kernel.get("hwControlProtocol") != "user_managed":
    fail("kernel.xml control protocol is not user_managed")

port = kernel.find("./ports/port[@name='s_axi_control']")
if port is None:
    fail("kernel.xml is missing s_axi_control")

expected_port = {
    "mode": "slave",
    "range": "0x1000",
    "dataWidth": "32",
    "portType": "addressable",
    "base": "0x0",
}
for key, expected in expected_port.items():
    if port.get(key) != expected:
        fail(
            f"s_axi_control {key} is {port.get(key)!r}, "
            f"expected {expected!r}"
        )

kernel_args: dict[str, int] = {}
for arg in kernel.findall("./args/arg"):
    name = arg.get("name")
    if not name:
        fail("kernel.xml contains an unnamed argument")
    if name in kernel_args:
        fail(f"kernel.xml duplicates {name}")
    kernel_args[name] = parse_int(arg.get("offset"))

expected_args = {
    "LAYER_COUNT": 0x010,
    "INT_CONTROL_STATUS": 0x100,
    "INT_LOADED_MASK": 0x130,
    "PIPE_CONTROL_STATUS": 0x180,
    "PIPE_VERSION": 0x184,
    "PIPE_RESULT_DATA": 0x200,
    "PIPE_ERROR_CODE": 0x210,
    "PIPE_CONFIG_READY": 0x214,
}
for name, expected_offset in expected_args.items():
    if kernel_args.get(name) != expected_offset:
        fail(
            f"kernel.xml {name} is "
            f"{kernel_args.get(name)!r}, expected {expected_offset:#x}"
        )

if len(kernel_args) != 74:
    fail(
        f"kernel.xml argument count is {len(kernel_args)}, expected 74"
    )

component_root = ET.parse(component_xml_path).getroot()
if not component_root.tag.startswith("{"):
    fail("component.xml has no namespace")

namespace_uri = component_root.tag[1:].split("}", 1)[0]
ns = {"spirit": namespace_uri}

component_regs: dict[str, int] = {}
for register in component_root.findall(".//spirit:register", ns):
    name_node = register.find("spirit:name", ns)
    offset_node = register.find("spirit:addressOffset", ns)
    if name_node is None or offset_node is None:
        fail("component.xml contains an incomplete register")
    name = (name_node.text or "").strip()
    offset = int((offset_node.text or "").strip(), 0)
    if name in component_regs:
        fail(f"component.xml duplicates {name}")
    component_regs[name] = offset

expected_component = {
    "CONTROL_STATUS": 0x000,
    "VERSION": 0x004,
    "RESULT_COUNT": 0x008,
    **expected_args,
}
for name, expected_offset in expected_component.items():
    if component_regs.get(name) != expected_offset:
        fail(
            f"component.xml {name} is "
            f"{component_regs.get(name)!r}, expected {expected_offset:#x}"
        )

if len(component_regs) != 77:
    fail(
        "component.xml register count is "
        f"{len(component_regs)}, expected 77"
    )

component_only = set(component_regs) - set(kernel_args)
expected_component_only = {
    "CONTROL_STATUS",
    "VERSION",
    "RESULT_COUNT",
}
if component_only != expected_component_only:
    fail(
        f"component-only registers are {sorted(component_only)}, "
        f"expected {sorted(expected_component_only)}"
    )

kernel_only = set(kernel_args) - set(component_regs)
if kernel_only:
    fail(
        f"kernel.xml has names absent from component.xml: "
        f"{sorted(kernel_only)}"
    )

with zipfile.ZipFile(xo_path, "r") as archive:
    members = archive.namelist()

required_suffixes = {
    "kernel.xml",
    "component.xml",
    "dlrm_f37x_rtl_kernel_stage2n_a10_v2.sv",
    "dlrm_internal_pipeline_axi_lite_adapter_stage2n_a10_v2.sv",
    "dlrm_internal_pipeline_controller.sv",
    "mlp_sequence_controller_segmented.sv",
    "dlrm_feature_interaction_engine.sv",
}
for suffix in required_suffixes:
    if not any(member.endswith(suffix) for member in members):
        fail(f"XO is missing member ending with {suffix}")

details = [
    "STAGE2N_A10_XO_PACKAGE_V2_DETAILS",
    f"KERNEL={kernel_name}",
    f"KERNEL_XML_ARG_COUNT={len(kernel_args)}",
    f"COMPONENT_XML_REGISTER_COUNT={len(component_regs)}",
    "COMPONENT_ONLY_REGISTERS="
    + ",".join(sorted(component_only)),
    "PIPELINE_VERSION=0x00024E11",
    "MAX_LAYERS=8",
    "MAX_WEIGHT_VALUES=2048",
    "MAX_BIAS_VALUES=128",
    f"XO_ARCHIVE_MEMBER_COUNT={len(members)}",
    "XO_XML_AND_SOURCE_CONTENTS_VALID=1",
]
detail_path.write_text("\n".join(details) + "\n", encoding="ascii")

print(f"KERNEL_XML_ARG_COUNT={len(kernel_args)}")
print(
    "COMPONENT_XML_REGISTER_COUNT="
    f"{len(component_regs)}"
)
print(
    "COMPONENT_ONLY_REGISTERS="
    + ",".join(sorted(component_only))
)
print("PIPELINE_VERSION=0x00024E11")
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
KERNEL_XML_SHA256="$(sha256sum "${KERNEL_XML}" | awk '{print $1}')"
COMPONENT_XML_SHA256="$(sha256sum "${COMPONENT_XML}" | awk '{print $1}')"

cat > "${STATUS_FILE}" <<EOF
STAGE2N_A10_XO_PACKAGE_V2_PASS
KERNEL=${KERNEL_NAME}
PART=${PART_NAME}
GIT_BRANCH=${CURRENT_BRANCH}
GIT_HEAD=${CURRENT_HEAD}
START_TIME=${START_TIME}
END_TIME=${END_TIME}
ELAPSED_SECONDS=${ELAPSED_SECONDS}
PIPELINE_VERSION=0x00024E11
MAX_LAYERS=8
MAX_WEIGHT_VALUES=2048
MAX_BIAS_VALUES=128
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
ERROR_COUNT=${ERROR_COUNT}
CRITICAL_WARNING_COUNT=${CRITICAL_WARNING_COUNT}
DETAILS=${DETAIL_FILE}
LOG=${VIVADO_LOG}
NO_SYNTH_PLACE_ROUTE=1
NO_XCLBIN_LINK=1
NO_FPGA_PROGRAMMING_OR_RESET=1
EOF

echo "============================================================"
echo "STAGE2N_A10_XO_PACKAGE_V2_PASS"
echo "XO=${XO_PATH}"
echo "XO_SIZE_BYTES=${XO_SIZE_BYTES}"
echo "KERNEL_XML_ARG_COUNT=74"
echo "COMPONENT_XML_REGISTER_COUNT=77"
echo "PIPELINE_VERSION=0x00024E11"
echo "STATUS=${STATUS_FILE}"
echo "NO SYNTH/PLACE/ROUTE"
echo "NO XCLBIN LINK"
echo "NO FPGA PROGRAMMING OR RESET"
echo "============================================================"
