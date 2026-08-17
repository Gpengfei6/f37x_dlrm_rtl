#!/usr/bin/env bash
#
# Stage 2N-A8 final acceptance for the existing F37X link_v3 artifact.
#
# This script only reads the existing status, xclbin metadata, link log, and
# routed timing report. It does not rerun synthesis, placement, routing, v++,
# FPGA programming, render-node access, or reset.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

EXPECTED_BRANCH="work/stage2n-a8-xo-xclbin"
EXPECTED_KERNEL="dlrm_f37x_rtl_kernel_stage2n_a7"
EXPECTED_CU="dlrm_a7_1"
EXPECTED_PLATFORM="inspur_f37x_xdma_201920_3"
EXPECTED_FREQUENCY_MHZ="100"

RESULT_DIR="${REPO_ROOT}/results/stage2n_a8/link_v3"
LINK_STATUS="${RESULT_DIR}/stage2n_a8_f37x_link_v3_status.txt"
XCLBIN_INFO="${RESULT_DIR}/${EXPECTED_KERNEL}.xclbin.info"
LINK_LOG="${REPO_ROOT}/logs/vpp_stage2n_a8_f37x_link_v3.log"

ACCEPT_STATUS="${RESULT_DIR}/stage2n_a8_f37x_link_artifact_accept_v1_status.txt"
ACCEPT_DETAILS="${RESULT_DIR}/stage2n_a8_f37x_link_artifact_accept_v1_details.txt"

fail()
{
    local code="$1"
    shift
    local reason="$*"

    mkdir -p "${RESULT_DIR}"
    cat > "${ACCEPT_STATUS}" <<EOF
STAGE2N_A8_F37X_LINK_ARTIFACT_ACCEPT_V1_FAILED
REASON=${reason}
EXIT_CODE=${code}
NO_SYNTH_PLACE_ROUTE_RERUN=1
NO_XCLBIN_LINK_RERUN=1
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

[[ -s "${LINK_STATUS}" ]] ||
    fail 4 "link status is missing or empty: ${LINK_STATUS}"

[[ -s "${XCLBIN_INFO}" ]] ||
    fail 5 "xclbin info is missing or empty: ${XCLBIN_INFO}"

[[ -s "${LINK_LOG}" ]] ||
    fail 6 "link log is missing or empty: ${LINK_LOG}"

grep -q '^STAGE2N_A8_F37X_LINK_V3_PASS$' "${LINK_STATUS}" ||
    fail 7 "link status does not contain STAGE2N_A8_F37X_LINK_V3_PASS"

TIMING_REPORT="$(
    sed -n 's/^TIMING_REPORT=//p' "${LINK_STATUS}" |
    head -n 1
)"
XCLBIN_PATH="$(
    sed -n 's/^XCLBIN=//p' "${LINK_STATUS}" |
    head -n 1
)"

[[ -s "${TIMING_REPORT}" ]] ||
    fail 8 "timing report is missing or empty: ${TIMING_REPORT}"

[[ -s "${XCLBIN_PATH}" ]] ||
    fail 9 "xclbin is missing or empty: ${XCLBIN_PATH}"

ERROR_COUNT="$(grep -cE '^ERROR:' "${LINK_LOG}" || true)"
CRITICAL_WARNING_COUNT="$(
    grep -cE '^CRITICAL WARNING:' "${LINK_LOG}" || true
)"

[[ "${ERROR_COUNT}" == "0" ]] ||
    fail 10 "link log contains ${ERROR_COUNT} anchored ERROR lines"

[[ "${CRITICAL_WARNING_COUNT}" == "0" ]] ||
    fail 11 "link log contains ${CRITICAL_WARNING_COUNT} critical warnings"

export A8_LINK_STATUS="${LINK_STATUS}"
export A8_XCLBIN_INFO="${XCLBIN_INFO}"
export A8_TIMING_REPORT="${TIMING_REPORT}"
export A8_XCLBIN_PATH="${XCLBIN_PATH}"
export A8_ACCEPT_DETAILS="${ACCEPT_DETAILS}"
export A8_EXPECTED_KERNEL="${EXPECTED_KERNEL}"
export A8_EXPECTED_CU="${EXPECTED_CU}"
export A8_EXPECTED_PLATFORM="${EXPECTED_PLATFORM}"
export A8_EXPECTED_FREQUENCY="${EXPECTED_FREQUENCY_MHZ}"

python - <<'PY'
from __future__ import annotations

import hashlib
import os
import re
import sys
from pathlib import Path

status_path = Path(os.environ["A8_LINK_STATUS"])
info_path = Path(os.environ["A8_XCLBIN_INFO"])
timing_path = Path(os.environ["A8_TIMING_REPORT"])
xclbin_path = Path(os.environ["A8_XCLBIN_PATH"])
details_path = Path(os.environ["A8_ACCEPT_DETAILS"])

expected_kernel = os.environ["A8_EXPECTED_KERNEL"]
expected_cu = os.environ["A8_EXPECTED_CU"]
expected_platform = os.environ["A8_EXPECTED_PLATFORM"]
expected_frequency = os.environ["A8_EXPECTED_FREQUENCY"]

status_text = status_path.read_text(errors="replace")
info_text = info_path.read_text(errors="replace")
timing_text = timing_path.read_text(errors="replace")

def fail(message: str) -> None:
    print(f"VALIDATION_ERROR={message}", file=sys.stderr)
    raise SystemExit(20)

def status_value(key: str) -> str:
    match = re.search(
        rf"(?m)^{re.escape(key)}=(.*)$",
        status_text,
    )
    if not match:
        fail(f"status is missing {key}")
    return match.group(1).strip()

kernel = status_value("KERNEL")
compute_unit = status_value("COMPUTE_UNIT")
frequency = status_value("KERNEL_FREQUENCY_MHZ")
uuid = status_value("XCLBIN_UUID")
reported_size = int(status_value("XCLBIN_SIZE_BYTES"))

if kernel != expected_kernel:
    fail(f"kernel is {kernel}, expected {expected_kernel}")
if compute_unit != expected_cu:
    fail(f"compute unit is {compute_unit}, expected {expected_cu}")
if frequency != expected_frequency:
    fail(f"frequency is {frequency}, expected {expected_frequency}")

if expected_kernel not in info_text:
    fail("xclbin info is missing the kernel")
if expected_cu not in info_text:
    fail("xclbin info is missing the compute unit")
if expected_platform not in info_text:
    fail("xclbin info is missing the F37X platform")

summary_pattern = re.compile(
    r"WNS\(ns\)\s+TNS\(ns\).*?WHS\(ns\)\s+THS\(ns\).*?\n"
    r"\s*-+.*?\n"
    r"\s*([-+]?\d+(?:\.\d+)?)\s+"
    r"([-+]?\d+(?:\.\d+)?)\s+"
    r"(\d+)\s+\d+\s+"
    r"([-+]?\d+(?:\.\d+)?)\s+"
    r"([-+]?\d+(?:\.\d+)?)\s+"
    r"(\d+)",
    re.S,
)
summary_match = summary_pattern.search(timing_text)
if not summary_match:
    fail("cannot parse Design Timing Summary")

setup_wns = float(summary_match.group(1))
setup_tns = float(summary_match.group(2))
setup_failing = int(summary_match.group(3))
hold_whs = float(summary_match.group(4))
hold_ths = float(summary_match.group(5))
hold_failing = int(summary_match.group(6))

if setup_wns < 0.0 or setup_tns < 0.0 or setup_failing != 0:
    fail(
        "setup timing failed: "
        f"WNS={setup_wns}, TNS={setup_tns}, "
        f"failing={setup_failing}"
    )

if hold_whs < 0.0 or hold_ths < 0.0 or hold_failing != 0:
    fail(
        "hold timing failed: "
        f"WHS={hold_whs}, THS={hold_ths}, "
        f"failing={hold_failing}"
    )

if "All user specified timing constraints are met." not in timing_text:
    fail("timing report does not contain the timing-met statement")

actual_size = xclbin_path.stat().st_size
if actual_size != reported_size:
    fail(
        f"xclbin size is {actual_size}, "
        f"status reports {reported_size}"
    )

sha256 = hashlib.sha256(xclbin_path.read_bytes()).hexdigest()
if len(sha256) != 64 or not re.fullmatch(r"[0-9a-f]{64}", sha256):
    fail("computed SHA256 is malformed")

if not re.fullmatch(
    r"[0-9a-fA-F]{8}-"
    r"[0-9a-fA-F]{4}-"
    r"[0-9a-fA-F]{4}-"
    r"[0-9a-fA-F]{4}-"
    r"[0-9a-fA-F]{12}",
    uuid,
):
    fail(f"xclbin UUID is malformed: {uuid}")

details = [
    "STAGE2N_A8_F37X_LINK_ARTIFACT_ACCEPT_V1_DETAILS",
    f"KERNEL={kernel}",
    f"COMPUTE_UNIT={compute_unit}",
    f"PLATFORM={expected_platform}",
    f"KERNEL_FREQUENCY_MHZ={frequency}",
    f"XCLBIN_SIZE_BYTES={actual_size}",
    f"XCLBIN_SHA256={sha256}",
    f"XCLBIN_UUID={uuid}",
    f"SETUP_WNS_NS={setup_wns:.3f}",
    f"SETUP_TNS_NS={setup_tns:.3f}",
    f"SETUP_FAILING_ENDPOINTS={setup_failing}",
    f"HOLD_WHS_NS={hold_whs:.3f}",
    f"HOLD_THS_NS={hold_ths:.3f}",
    f"HOLD_FAILING_ENDPOINTS={hold_failing}",
    "TIMING_CONSTRAINTS_MET=1",
    "EMPTY_CONNECTIVITY_EXPECTED_FOR_CONTROL_ONLY_KERNEL=1",
]
details_path.write_text("\n".join(details) + "\n", encoding="ascii")

print(f"XCLBIN_SHA256={sha256}")
print(f"SETUP_WNS_NS={setup_wns:.3f}")
print(f"SETUP_TNS_NS={setup_tns:.3f}")
print(f"SETUP_FAILING_ENDPOINTS={setup_failing}")
print(f"HOLD_WHS_NS={hold_whs:.3f}")
print(f"HOLD_THS_NS={hold_ths:.3f}")
print(f"HOLD_FAILING_ENDPOINTS={hold_failing}")
print("TIMING_CONSTRAINTS_MET=1")
print("XCLBIN_METADATA_VALID=1")
PY

XCLBIN_SIZE_BYTES="$(stat -c '%s' "${XCLBIN_PATH}")"
XCLBIN_SHA256="$(
    sed -n 's/^XCLBIN_SHA256=//p' "${ACCEPT_DETAILS}"
)"
XCLBIN_UUID="$(
    sed -n 's/^XCLBIN_UUID=//p' "${ACCEPT_DETAILS}"
)"
SETUP_WNS_NS="$(
    sed -n 's/^SETUP_WNS_NS=//p' "${ACCEPT_DETAILS}"
)"
SETUP_TNS_NS="$(
    sed -n 's/^SETUP_TNS_NS=//p' "${ACCEPT_DETAILS}"
)"
SETUP_FAILING_ENDPOINTS="$(
    sed -n 's/^SETUP_FAILING_ENDPOINTS=//p' "${ACCEPT_DETAILS}"
)"
HOLD_WHS_NS="$(
    sed -n 's/^HOLD_WHS_NS=//p' "${ACCEPT_DETAILS}"
)"
HOLD_THS_NS="$(
    sed -n 's/^HOLD_THS_NS=//p' "${ACCEPT_DETAILS}"
)"
HOLD_FAILING_ENDPOINTS="$(
    sed -n 's/^HOLD_FAILING_ENDPOINTS=//p' "${ACCEPT_DETAILS}"
)"

cat > "${ACCEPT_STATUS}" <<EOF
STAGE2N_A8_F37X_LINK_ARTIFACT_ACCEPT_V1_PASS
KERNEL=${EXPECTED_KERNEL}
COMPUTE_UNIT=${EXPECTED_CU}
PLATFORM=${EXPECTED_PLATFORM}
KERNEL_FREQUENCY_MHZ=${EXPECTED_FREQUENCY_MHZ}
GIT_BRANCH=${CURRENT_BRANCH}
GIT_HEAD=${CURRENT_HEAD}
XCLBIN=${XCLBIN_PATH}
XCLBIN_SIZE_BYTES=${XCLBIN_SIZE_BYTES}
XCLBIN_SHA256=${XCLBIN_SHA256}
XCLBIN_UUID=${XCLBIN_UUID}
XCLBIN_INFO=${XCLBIN_INFO}
TIMING_REPORT=${TIMING_REPORT}
SETUP_WNS_NS=${SETUP_WNS_NS}
SETUP_TNS_NS=${SETUP_TNS_NS}
SETUP_FAILING_ENDPOINTS=${SETUP_FAILING_ENDPOINTS}
HOLD_WHS_NS=${HOLD_WHS_NS}
HOLD_THS_NS=${HOLD_THS_NS}
HOLD_FAILING_ENDPOINTS=${HOLD_FAILING_ENDPOINTS}
ERROR_COUNT=${ERROR_COUNT}
CRITICAL_WARNING_COUNT=${CRITICAL_WARNING_COUNT}
EMPTY_CONNECTIVITY_EXPECTED_FOR_CONTROL_ONLY_KERNEL=1
DETAILS=${ACCEPT_DETAILS}
NO_SYNTH_PLACE_ROUTE_RERUN=1
NO_XCLBIN_LINK_RERUN=1
NO_FPGA_PROGRAMMING_OR_RESET=1
EOF

echo "============================================================"
echo "STAGE2N_A8_F37X_LINK_ARTIFACT_ACCEPT_V1_PASS"
echo "XCLBIN=${XCLBIN_PATH}"
echo "XCLBIN_SIZE_BYTES=${XCLBIN_SIZE_BYTES}"
echo "XCLBIN_SHA256=${XCLBIN_SHA256}"
echo "XCLBIN_UUID=${XCLBIN_UUID}"
echo "SETUP_WNS_NS=${SETUP_WNS_NS}"
echo "HOLD_WHS_NS=${HOLD_WHS_NS}"
echo "COMPUTE_UNIT=${EXPECTED_CU}"
echo "STATUS=${ACCEPT_STATUS}"
echo "NO SYNTH/PLACE/ROUTE RERUN"
echo "NO XCLBIN LINK RERUN"
echo "NO FPGA PROGRAMMING OR RESET"
echo "============================================================"
