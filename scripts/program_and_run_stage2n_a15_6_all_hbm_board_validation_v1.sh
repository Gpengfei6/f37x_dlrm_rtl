#!/usr/bin/env bash
# Protected A15.6 physical-HBM/full-DLRM board runner.
# This file is prepared locally only. Codex does not execute it.

set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

EXPECTED_BRANCH="work/stage2n-a15-hbm-pipeline-integration"
EXPECTED_XCLBIN_SHA256="23ee48c91b3dfb5b68b3372ac49fc6607f203cf01d3b9fcfe04b4ea42be02356"
EXPECTED_UUID="1b555645-a9e2-4f5e-95af-6ce4adacbc3c"
EXPECTED_KERNEL="dlrm_f37x_rtl_kernel_stage2n_a15_v1"
EXPECTED_INSTANCE="dlrm_a15_1"
EXPECTED_CU="${EXPECTED_KERNEL}:${EXPECTED_INSTANCE}"
EXPECTED_PLATFORM="inspur_f37x_xdma_201920_3"
EXPECTED_HBM_BANK="HBM[0]"
EXPECTED_XRT_VERSION="2.9.210507"
TARGET_BDF="${A15_6_TARGET_BDF:-0000:9b:00.1}"
TARGET_INDEX="${A15_6_TARGET_INDEX:-}"
TARGET_RENDER="${A15_6_TARGET_RENDER:-}"
XRT_SETUP="${XRT_SETUP:-/opt/xilinx/xrt/setup.sh}"
XCLBIN="${A15_6_XCLBIN:-${1:-}}"

MANIFEST="${REPO_ROOT}/models/stage2n_a15_6/stage2n_a15_6_cases_v1.json"
MODEL="${REPO_ROOT}/models/stage2n_a15_6/stage2n_a15_6_model_v1.bin"
SOURCE_VALIDATOR="${REPO_ROOT}/scripts/validate_stage2n_a15_6_sources_v1.py"
EVIDENCE_ASSEMBLER="${REPO_ROOT}/scripts/assemble_stage2n_a15_6_evidence_v1.py"
EVIDENCE_VALIDATOR="${REPO_ROOT}/scripts/validate_stage2n_a15_6_evidence_v1.py"
HOST_BUILD_SCRIPT="${REPO_ROOT}/scripts/build_stage2n_a15_6_host_v1.sh"
HOST_BINARY="${REPO_ROOT}/build/stage2n_a15_6/host_v1/stage2n_a15_6_all_hbm_board_validation_v1"
HOST_BUILD_STATUS="${REPO_ROOT}/build/stage2n_a15_6/host_v1/host_build_status.txt"

STAMP="$(date +%Y%m%d_%H%M%S)"
RESULT_DIR="${REPO_ROOT}/results/stage2n_a15_6/board_validation_v1/${STAMP}"
LOG="${RESULT_DIR}/runner.log"
HOST_LOG="${RESULT_DIR}/host.log"
XCLBIN_INFO="${RESULT_DIR}/${EXPECTED_KERNEL}.xclbin.info"
PRE_QUERY_FILE="${RESULT_DIR}/pre_device_query.txt"
POST_QUERY_FILE="${RESULT_DIR}/post_host_query.txt"
EVIDENCE="${RESULT_DIR}/a15_6_board_evidence_v1.json"
VALIDATION_LOG="${RESULT_DIR}/evidence_validation.log"
FAILURE_STATUS="${RESULT_DIR}/failure_status.txt"
mkdir -p "${RESULT_DIR}"
exec > >(tee "${LOG}") 2>&1

write_failure()
{
    local reason="$1"
    {
        echo "A15_6_BOARD_FUNCTIONAL=FAIL"
        echo "TIME=$(date -Is)"
        echo "TARGET_INDEX=${TARGET_INDEX:-UNSET}"
        echo "TARGET_BDF=${TARGET_BDF}"
        echo "REASON=${reason}"
        echo "FPGA_RESET=NOT_RUN"
        echo "OTHER_DEVICE_ACCESS=NONE"
        echo "PERFORMANCE=NOT_CLAIMED"
    } > "${FAILURE_STATUS}"
}

fail()
{
    write_failure "$*"
    echo "ERROR: $*" >&2
    echo "NO FPGA RESET OR GLOBAL HBM CLEANUP WAS ATTEMPTED" >&2
    exit 10
}

extract_uuid()
{
    awk '/Xclbin UUID/ {getline; gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0); print; exit}'
}

extract_cu_line()
{
    grep -E '^CU\[' | grep -F "${EXPECTED_CU}" | head -1
}

extract_hbm0_line()
{
    grep -E '^\[[[:space:]]*0\][[:space:]]+HBM\[0\]' | head -1
}

query_target()
{
    xbutil query -d "${TARGET_BDF}" 2>&1
}

require_empty_hbm0()
{
    local text="$1" stage="$2" line
    line="$(printf '%s\n' "${text}" | extract_hbm0_line)"
    [[ -n "${line}" ]] || fail "${stage}: HBM[0] line missing"
    printf '%s\n' "${line}" | grep -Eq 'HBM\[0\].*0 Byte[[:space:]]+0[[:space:]]*$' ||
        fail "${stage}: HBM[0] has active bytes or BOs"
}

require_empty_render()
{
    local stage="$1" fuser_output lsof_output
    fuser_output="$(fuser -v "${TARGET_RENDER}" 2>&1 || true)"
    lsof_output="$(lsof -w "${TARGET_RENDER}" 2>&1 || true)"
    [[ -z "${fuser_output//[[:space:]]/}" ]] || fail "${stage}: render node has an open fuser handle"
    [[ -z "${lsof_output//[[:space:]]/}" ]] || fail "${stage}: render node has an open lsof handle"
}

check_target_mapping()
{
    local scan_output render_sysfs
    scan_output="$(xbutil scan 2>&1)" || fail "xbutil scan failed"
    printf '%s\n' "${scan_output}" |
        grep -Eq "^[[:space:]]*\[${TARGET_INDEX}\][[:space:]]+${TARGET_BDF}[[:space:]]+${EXPECTED_PLATFORM}" ||
        fail "runtime index ${TARGET_INDEX} does not map to ${TARGET_BDF}/${EXPECTED_PLATFORM}"
    render_sysfs="$(readlink -f "/sys/class/drm/$(basename "${TARGET_RENDER}")/device" 2>/dev/null || true)"
    [[ "${render_sysfs}" == *"/${TARGET_BDF}" ]] ||
        fail "render node does not map to guarded BDF: ${render_sysfs}"
}

[[ -n "${TARGET_INDEX}" && "${TARGET_INDEX}" =~ ^[0-9]+$ ]] ||
    fail "set A15_6_TARGET_INDEX explicitly; historical index 2 is not selected silently"
[[ "${TARGET_BDF}" == "0000:9b:00.1" ]] || fail "wrong guarded BDF"
[[ -n "${XCLBIN}" && -s "${XCLBIN}" ]] || fail "pass the accepted A15.5 xclbin path"
[[ -f "${XRT_SETUP}" ]] || fail "XRT setup is missing"

set +u
# shellcheck disable=SC1090
source "${XRT_SETUP}" >/dev/null || { set -u; fail "failed to initialize XRT"; }
set -u
for tool in xbutil xclbinutil git sha256sum python3 awk grep fuser lsof readlink hostname; do
    command -v "${tool}" >/dev/null 2>&1 || fail "required tool missing: ${tool}"
done

CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
CURRENT_HEAD="$(git rev-parse HEAD 2>/dev/null || true)"
[[ "${CURRENT_BRANCH}" == "${EXPECTED_BRANCH}" ]] || fail "wrong branch: ${CURRENT_BRANCH}"

# All fixed-artifact checks occur before target query, programming, BO access,
# or Host execution.
ACTUAL_XCLBIN_SHA256="$(sha256sum "${XCLBIN}" | awk '{print $1}')"
[[ "${ACTUAL_XCLBIN_SHA256}" == "${EXPECTED_XCLBIN_SHA256}" ]] ||
    fail "fixed xclbin SHA256 mismatch"
xclbinutil --info --input "${XCLBIN}" > "${XCLBIN_INFO}" 2>&1 || fail "xclbinutil info failed"
METADATA_UUID="$(sed -n 's/^[[:space:]]*UUID (xclbin):[[:space:]]*//p' "${XCLBIN_INFO}" | head -n1 | tr -d '\r')"
[[ "${METADATA_UUID}" == "${EXPECTED_UUID}" ]] || fail "fixed xclbin UUID mismatch"
grep -Fq "${EXPECTED_KERNEL}" "${XCLBIN_INFO}" || fail "fixed kernel missing"
grep -Fq "${EXPECTED_INSTANCE}" "${XCLBIN_INFO}" || fail "fixed CU missing"

python3 "${SOURCE_VALIDATOR}" --repo "${REPO_ROOT}" || fail "local source/asset validation failed"
python3 "${EVIDENCE_VALIDATOR}" --manifest "${MANIFEST}" --self-test ||
    fail "offline evidence validator self-test failed"

if [[ ! -x "${HOST_BINARY}" ]]; then
    bash "${HOST_BUILD_SCRIPT}" || fail "A15.6 Host build failed"
fi
[[ -s "${HOST_BUILD_STATUS}" ]] || fail "A15.6 Host build status missing"
grep -Fxq "A15_6_HOST_XRT_BUILD=PASS" "${HOST_BUILD_STATUS}" || fail "Host build PASS missing"
[[ -x "${HOST_BINARY}" ]] || fail "Host binary missing"

if [[ -z "${TARGET_RENDER}" ]]; then
    for candidate in /sys/class/drm/renderD*/device; do
        [[ -e "${candidate}" ]] || continue
        mapped="$(readlink -f "${candidate}" 2>/dev/null || true)"
        if [[ "${mapped}" == *"/${TARGET_BDF}" ]]; then
            TARGET_RENDER="/dev/dri/$(basename "$(dirname "${candidate}")")"
            break
        fi
    done
fi
[[ -n "${TARGET_RENDER}" && -e "${TARGET_RENDER}" ]] || fail "guarded render node not found"

check_target_mapping
require_empty_render "PRE_AUTHORIZATION"
PRE_QUERY="$(query_target)" || fail "pre-authorization query failed"
printf '%s\n' "${PRE_QUERY}" > "${PRE_QUERY_FILE}"
printf '%s\n' "${PRE_QUERY}" | grep -q 'Level 0 : 0x0(GOOD)' || fail "target firewall is not GOOD"
require_empty_hbm0 "${PRE_QUERY}" "PRE_AUTHORIZATION"
CURRENT_UUID="$(printf '%s\n' "${PRE_QUERY}" | extract_uuid)"
CURRENT_CU_LINE="$(printf '%s\n' "${PRE_QUERY}" | extract_cu_line || true)"

PROGRAMMING_STATUS="SKIPPED_ALREADY_LOADED"
if [[ "${CURRENT_UUID}" != "${EXPECTED_UUID}" ]]; then
    [[ -n "${A15_6_ALLOWED_SOURCE_UUID:-}" && -n "${A15_6_ALLOWED_SOURCE_CU:-}" ]] ||
        fail "current UUID differs; explicitly set reviewed A15_6_ALLOWED_SOURCE_UUID/CU"
    [[ "${CURRENT_UUID}" == "${A15_6_ALLOWED_SOURCE_UUID}" ]] || fail "source UUID not allowlisted"
    printf '%s\n' "${PRE_QUERY}" | grep -Fq "${A15_6_ALLOWED_SOURCE_CU}" || fail "source CU not allowlisted"
    printf '%s\n' "${PRE_QUERY}" | grep -Fq '(IDLE)' || fail "source CU is not IDLE"
else
    printf '%s\n' "${CURRENT_CU_LINE}" | grep -Fq "${EXPECTED_CU}" || fail "accepted CU missing"
    printf '%s\n' "${CURRENT_CU_LINE}" | grep -Fq '(IDLE)' || fail "accepted CU is not IDLE"
fi

echo "============================================================"
echo "Stage 2N-A15.6 protected board authorization"
echo "TARGET_INDEX=${TARGET_INDEX}"
echo "TARGET_BDF=${TARGET_BDF}"
echo "TARGET_RENDER=${TARGET_RENDER}"
echo "XCLBIN_SHA256=${ACTUAL_XCLBIN_SHA256}"
echo "XCLBIN_UUID=${EXPECTED_UUID}"
echo "KERNEL=${EXPECTED_KERNEL}"
echo "CU=${EXPECTED_INSTANCE}"
echo "HBM_BANK=${EXPECTED_HBM_BANK}"
echo "ACTION_PROGRAM_FPGA_IF_NEEDED=YES"
echo "ACTION_ALLOCATE_HBM0_BO=YES"
echo "ACTION_RUN_COMPLETE_DLRM_INFERENCE=YES"
echo "FPGA_RESET=NOT_RUN"
echo "GLOBAL_HBM_CLEANUP=NOT_RUN"
echo "OTHER_DEVICE_ACCESS=NONE"
echo "============================================================"
confirmation="${A15_6_CONFIRM:-}"
if [[ -z "${confirmation}" ]]; then
    [[ -t 0 ]] || fail "interactive confirmation unavailable; set A15_6_CONFIRM=yes after review"
    read -r -p "Proceed with this protected A15.6 run? [yes/no] " confirmation
fi
if [[ "${confirmation}" != "yes" ]]; then
    echo "A15.6 protected run cancelled safely."
    exit 0
fi

# Recheck exact device immediately after authorization and before changes.
check_target_mapping
require_empty_render "FINAL_PRE_DEVICE_CHANGE"
FINAL_PRE="$(query_target)" || fail "final pre-device query failed"
require_empty_hbm0 "${FINAL_PRE}" "FINAL_PRE_DEVICE_CHANGE"
[[ "$(printf '%s\n' "${FINAL_PRE}" | extract_uuid)" == "${CURRENT_UUID}" ]] ||
    fail "target UUID changed after authorization"

if [[ "${CURRENT_UUID}" != "${EXPECTED_UUID}" ]]; then
    xbutil program -d "${TARGET_BDF}" -p "${XCLBIN}" || fail "xbutil program failed"
    PROGRAMMING_STATUS="PASS"
    sleep 3
fi

PRE_HOST="$(query_target)" || fail "pre-Host query failed"
[[ "$(printf '%s\n' "${PRE_HOST}" | extract_uuid)" == "${EXPECTED_UUID}" ]] || fail "accepted UUID not active"
printf '%s\n' "${PRE_HOST}" | grep -Fq "${EXPECTED_CU}" || fail "accepted CU not active"
printf '%s\n' "${PRE_HOST}" | grep -Fq '(IDLE)' || fail "accepted CU is not IDLE"
require_empty_render "PRE_HOST"
require_empty_hbm0 "${PRE_HOST}" "PRE_HOST"

mapfile -t CASE_ARGUMENTS < <(python3 - "${MANIFEST}" "${REPO_ROOT}/models/stage2n_a15_6" <<'PY'
import json, pathlib, sys
manifest = json.load(open(sys.argv[1], "r"))
root = pathlib.Path(sys.argv[2])
for case in manifest["cases"]:
    print(str(root / case["file"]))
    print(case["expected_final_result"])
PY
)
[[ "${#CASE_ARGUMENTS[@]}" -eq 10 ]] || fail "case argument construction failed"

set +e
"${HOST_BINARY}" "${TARGET_INDEX}" "${TARGET_BDF}" "${EXPECTED_UUID}" "${MODEL}" \
    "${CASE_ARGUMENTS[@]}" > "${HOST_LOG}" 2>&1
host_exit="$?"
set -e
cat "${HOST_LOG}"
[[ "${host_exit}" -eq 0 ]] || fail "A15.6 Host returned ${host_exit}"
grep -Fxq "STAGE2N_A15_6_ALL_HBM_BOARD_VALIDATION_V1=PASS" "${HOST_LOG}" || fail "Host PASS missing"
grep -Fxq "A15_6_BO_CLEANUP=PASS" "${HOST_LOG}" || fail "BO cleanup PASS missing"

POST_QUERY="$(query_target)" || fail "post-Host query failed"
printf '%s\n' "${POST_QUERY}" > "${POST_QUERY_FILE}"
[[ "$(printf '%s\n' "${POST_QUERY}" | extract_uuid)" == "${EXPECTED_UUID}" ]] || fail "UUID changed after Host"
printf '%s\n' "${POST_QUERY}" | grep -Fq "${EXPECTED_CU}" || fail "CU missing after Host"
printf '%s\n' "${POST_QUERY}" | grep -Fq '(IDLE)' || fail "CU not IDLE after Host"
require_empty_render "POST_HOST"
require_empty_hbm0 "${POST_QUERY}" "POST_HOST"

python3 "${EVIDENCE_ASSEMBLER}" \
    --host-log "${HOST_LOG}" --manifest "${MANIFEST}" --output "${EVIDENCE}" \
    --timestamp-utc "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --hostname "$(hostname)" \
    --branch "${CURRENT_BRANCH}" --head "${CURRENT_HEAD}" \
    --device-index "${TARGET_INDEX}" --bdf "${TARGET_BDF}" \
    --xclbin-path "$(readlink -f "${XCLBIN}")" \
    --xclbin-sha256 "${ACTUAL_XCLBIN_SHA256}" --uuid "${EXPECTED_UUID}" \
    --programming-status "${PROGRAMMING_STATUS}" --device-close-status PASS ||
    fail "evidence assembly failed"
python3 "${EVIDENCE_VALIDATOR}" --manifest "${MANIFEST}" --evidence "${EVIDENCE}" \
    > "${VALIDATION_LOG}" 2>&1 || { cat "${VALIDATION_LOG}"; fail "evidence validation failed"; }
cat "${VALIDATION_LOG}"

echo "A15_6_FIXED_XCLBIN_IDENTITY=PASS"
echo "A15_6_DEVICE_IDENTITY=PASS"
echo "A15_6_FPGA_PROGRAMMING=${PROGRAMMING_STATUS}"
echo "A15_6_HBM0_BO_ALLOCATION=PASS"
echo "A15_6_PAYLOAD_TRANSFER=PASS"
echo "A15_6_TABLE_BASE_PROGRAMMING=PASS"
echo "A15_6_BASELINE_CASE=PASS"
echo "A15_6_SLOT0_SENSITIVITY=PASS"
echo "A15_6_SLOT1_SENSITIVITY=PASS"
echo "A15_6_SLOT2_SENSITIVITY=PASS"
echo "A15_6_SLOT3_SENSITIVITY=PASS"
echo "A15_6_COMPLETE_DLRM_RESULT=PASS"
echo "A15_6_BO_CLEANUP=PASS"
echo "A15_6_PHYSICAL_HBM=PASS"
echo "A15_6_BOARD_FUNCTIONAL=PASS"
echo "A15_6_PERFORMANCE=NOT_CLAIMED"
echo "FPGA_RESET=NOT_RUN"
echo "OTHER_DEVICE_ACCESS=NONE"
echo "EVIDENCE=${EVIDENCE}"
