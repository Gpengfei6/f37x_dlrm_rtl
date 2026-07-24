#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

VIVADO_SETTINGS="${VIVADO_SETTINGS:-/opt/Xilinx/Vivado/2020.2/settings64.sh}"
TCL_SCRIPT="${REPO_ROOT}/scripts/package_stage2g_xo.tcl"
LOG_DIR="${REPO_ROOT}/logs"
RESULT_DIR="${REPO_ROOT}/results/stage2g"
XO_PATH="${REPO_ROOT}/build/stage2g/package/dlrm_f37x_rtl_kernel.xo"
XML_PATH="${REPO_ROOT}/build/stage2g/package/kernel.xml"
VIVADO_LOG="${LOG_DIR}/vivado_stage2g_package_xo.log"

if [[ ! -f "${VIVADO_SETTINGS}" ]]; then
    echo "ERROR: Vivado settings not found: ${VIVADO_SETTINGS}" >&2
    exit 2
fi

if [[ ! -f "${TCL_SCRIPT}" ]]; then
    echo "ERROR: packaging Tcl not found: ${TCL_SCRIPT}" >&2
    exit 3
fi

# shellcheck disable=SC1090
source "${VIVADO_SETTINGS}"

mkdir -p "${LOG_DIR}" "${RESULT_DIR}"

vivado \
    -mode batch \
    -nojournal \
    -log "${VIVADO_LOG}" \
    -source "${TCL_SCRIPT}"

if [[ ! -s "${XO_PATH}" ]]; then
    echo "ERROR: XO was not generated: ${XO_PATH}" >&2
    exit 4
fi

if [[ ! -s "${XML_PATH}" ]]; then
    echo "ERROR: kernel.xml was not generated: ${XML_PATH}" >&2
    exit 5
fi

ERROR_COUNT="$(
    grep -cE '^ERROR:' "${VIVADO_LOG}" || true
)"
CRITICAL_COUNT="$(
    grep -cE '^CRITICAL WARNING:' "${VIVADO_LOG}" || true
)"

if [[ "${ERROR_COUNT}" != "0" ]]; then
    echo "ERROR: Vivado log contains ${ERROR_COUNT} anchored errors" >&2
    grep -E '^ERROR:' "${VIVADO_LOG}" >&2 || true
    exit 6
fi

if [[ "${CRITICAL_COUNT}" != "0" ]]; then
    echo \
        "ERROR: Vivado log contains ${CRITICAL_COUNT} critical warnings" \
        >&2
    grep -E '^CRITICAL WARNING:' "${VIVADO_LOG}" >&2 || true
    exit 7
fi

XO_SIZE_BYTES="$(stat -c '%s' "${XO_PATH}")"
XML_SIZE_BYTES="$(stat -c '%s' "${XML_PATH}")"
GIT_BRANCH="$(git -C "${REPO_ROOT}" symbolic-ref --short HEAD 2>/dev/null || echo UNKNOWN)"
GIT_HEAD="$(git -C "${REPO_ROOT}" rev-parse HEAD 2>/dev/null || echo UNKNOWN)"

cat > "${RESULT_DIR}/stage2g_xo_status.txt" <<EOF
STAGE2G_XO_PACKAGE_PASS
KERNEL=dlrm_f37x_rtl_kernel
PART=xcvu37p-fsvh2892-2L-e
PLATFORM=inspur_f37x_xdma_201920_3
GIT_BRANCH=${GIT_BRANCH}
GIT_HEAD=${GIT_HEAD}
XO=${XO_PATH}
XO_SIZE_BYTES=${XO_SIZE_BYTES}
KERNEL_XML=${XML_PATH}
KERNEL_XML_SIZE_BYTES=${XML_SIZE_BYTES}
ERROR_COUNT=${ERROR_COUNT}
CRITICAL_WARNING_COUNT=${CRITICAL_COUNT}
EOF

echo "STAGE2G_XO_PACKAGE_PASS"
echo "XO=${XO_PATH}"
echo "KERNEL_XML=${XML_PATH}"
