#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

VIVADO_SETTINGS="${VIVADO_SETTINGS:-/opt/Xilinx/Vivado/2020.2/settings64.sh}"
VIVADO_BIN="${VIVADO_BIN:-vivado}"
STAGE2F_PART="${STAGE2F_PART:-xc7a200tfbg484-2}"
STAGE2F_RESULT_DIR="${STAGE2F_RESULT_DIR:-${REPOSITORY_ROOT}/results/stage2f}"
STAGE2F_WORK_DIR="${STAGE2F_WORK_DIR:-${REPOSITORY_ROOT}/work/stage2f}"

TCL_SCRIPT="${REPOSITORY_ROOT}/scripts/run_stage2f_post_route.tcl"
LOG_DIR="${REPOSITORY_ROOT}/logs"
CONSOLE_LOG="${LOG_DIR}/vivado_stage2f_post_route.log"
STATUS_FILE="${STAGE2F_RESULT_DIR}/stage2f_post_route_status.txt"

replace_status_key() {
    local status_path="$1"
    local key="$2"
    local value="$3"
    local temp_path

    temp_path="$(mktemp)"

    awk -v key="${key}" -v value="${value}" '
        BEGIN { found = 0 }
        index($0, key "=") == 1 {
            print key "=" value
            found = 1
            next
        }
        { print }
        END {
            if (!found) {
                print key "=" value
            }
        }
    ' "${status_path}" > "${temp_path}"

    mv "${temp_path}" "${status_path}"
}

require_status_value() {
    local key="$1"
    local expected="$2"
    local actual

    actual="$(
        awk -F= -v key="${key}" '
            $1 == key {
                print substr($0, index($0, "=") + 1)
                exit
            }
        ' "${STATUS_FILE}"
    )"

    if [[ -z "${actual}" ]]; then
        echo "ERROR: Stage 2F status is missing ${key}" >&2
        exit 20
    fi

    if [[ "${actual}" != "${expected}" ]]; then
        echo \
            "ERROR: Stage 2F acceptance failed: ${key}=${actual}, expected ${expected}" \
            >&2
        exit 21
    fi
}

if [[ ! -f "${TCL_SCRIPT}" ]]; then
    echo "ERROR: Stage 2F Tcl script was not found: ${TCL_SCRIPT}" >&2
    exit 2
fi

if [[ ! -f "${VIVADO_SETTINGS}" ]]; then
    echo "ERROR: Vivado settings script was not found: ${VIVADO_SETTINGS}" >&2
    exit 3
fi

# shellcheck disable=SC1090
source "${VIVADO_SETTINGS}"

if ! command -v "${VIVADO_BIN}" >/dev/null 2>&1; then
    echo "ERROR: Vivado executable was not found: ${VIVADO_BIN}" >&2
    exit 4
fi

mkdir -p "${LOG_DIR}"

export STAGE2F_PART
export STAGE2F_RESULT_DIR
export STAGE2F_WORK_DIR

echo "============================================================"
echo "Stage 2F Artix-7 OOC post-route implementation"
echo "Repository : ${REPOSITORY_ROOT}"
echo "Vivado     : $(command -v "${VIVADO_BIN}")"
echo "Part       : ${STAGE2F_PART}"
echo "Results    : ${STAGE2F_RESULT_DIR}"
echo "Work       : ${STAGE2F_WORK_DIR}"
echo "Log        : ${CONSOLE_LOG}"
echo "============================================================"

cd "${REPOSITORY_ROOT}"

set +e
"${VIVADO_BIN}" \
    -mode batch \
    -nolog \
    -nojournal \
    -source "${TCL_SCRIPT}" \
    2>&1 | tee "${CONSOLE_LOG}"
vivado_exit="${PIPESTATUS[0]}"
set -e

error_count="$(
    grep -c '^ERROR:' "${CONSOLE_LOG}" 2>/dev/null || true
)"
critical_warning_count="$(
    grep -c '^CRITICAL WARNING:' "${CONSOLE_LOG}" 2>/dev/null || true
)"

if [[ -f "${STATUS_FILE}" ]]; then
    replace_status_key "${STATUS_FILE}" "ERROR_COUNT" "${error_count}"
    replace_status_key \
        "${STATUS_FILE}" \
        "CRITICAL_WARNING_COUNT" \
        "${critical_warning_count}"
fi

if [[ "${vivado_exit}" -ne 0 ]]; then
    echo \
        "ERROR: Vivado Stage 2F flow failed with exit code ${vivado_exit}. See ${CONSOLE_LOG}" \
        >&2
    exit "${vivado_exit}"
fi

if [[ ! -f "${STATUS_FILE}" ]]; then
    echo "ERROR: Stage 2F status file was not created: ${STATUS_FILE}" >&2
    exit 10
fi

if ! grep -qx 'STAGE2F_RUN_COMPLETE' "${STATUS_FILE}"; then
    echo "ERROR: Status file does not contain STAGE2F_RUN_COMPLETE" >&2
    exit 11
fi

require_status_value "ROUTE_STATE" "ROUTE_COMPLETE"
require_status_value "UNROUTED_NETS" "0"
require_status_value "SETUP_FAILING_ENDPOINTS" "0"
require_status_value "HOLD_FAILING_ENDPOINTS" "0"
require_status_value "TIMING_STATE" "TIMING_MET"

if [[ "${error_count}" -ne 0 ]]; then
    echo "ERROR: Vivado log contains ${error_count} anchored ERROR line(s)" >&2
    exit 12
fi

echo
echo "========== Stage 2F status =========="
cat "${STATUS_FILE}"

if [[ "${critical_warning_count}" -ne 0 ]]; then
    echo \
        "WARNING: Vivado log contains ${critical_warning_count} anchored CRITICAL WARNING line(s); review before closing Stage 2F." \
        >&2
fi

echo
echo "STAGE2F_POST_ROUTE_FLOW_PASS"
echo "Status: ${STATUS_FILE}"
echo "Log:    ${CONSOLE_LOG}"
