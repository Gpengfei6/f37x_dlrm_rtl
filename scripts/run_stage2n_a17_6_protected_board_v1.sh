#!/usr/bin/env bash
# Protected A17.6 four-BO flow.
# Default action is prepare: source/golden/map checks and optional Host compile.
# This file never programs or runs the Host unless execute is explicitly unlocked.
# Codex does not execute this script.

set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

ACTION="${1:-prepare}"
EXPECTED_KERNEL="dlrm_f37x_rtl_kernel_stage2n_a17_v1"
EXPECTED_INSTANCE="dlrm_a17_1"
EXPECTED_CU="${EXPECTED_KERNEL}:${EXPECTED_INSTANCE}"
EXPECTED_PLATFORM="inspur_f37x_xdma_201920_3"
EXPECTED_XCLBIN_SHA256="b8d2034906451cc755b6c01a50c94a4b841998c3e2794c6e417dd1ab952e46ae"
EXPECTED_UUID="622c839f-55f4-47c1-92e9-95ee5595ffa4"
STALE_XO_SHA256="1bd10d1f2a8307380ca95922e13c1680fcc7c96aeb15189ced3dff1b58a2a047"
LIVE_XO_SHA256="15ded79ff75e7a12c464a8b1d65cc863cc6535ead673ba0ba445bb5e69a56be6"
EXPECTED_XRT_VERSION="2.9.210507"
XRT_SETUP="${XRT_SETUP:-/opt/xilinx/xrt/setup.sh}"

MANIFEST="${REPO_ROOT}/models/stage2n_a15_6/stage2n_a15_6_cases_v1.json"
MODEL="${REPO_ROOT}/models/stage2n_a15_6/stage2n_a15_6_model_v1.bin"
MODEL_DIR="${REPO_ROOT}/models/stage2n_a15_6"
HOST_SOURCE="${REPO_ROOT}/host/stage2n_a17_6_four_bo_host_v1.cpp"
HOST_BUILD_SCRIPT="${REPO_ROOT}/scripts/build_stage2n_a17_6_host_v1.sh"
HOST_BINARY="${REPO_ROOT}/build/stage2n_a17_6/host_v1/stage2n_a17_6_four_bo_host_v1"
HOST_BUILD_STATUS="${REPO_ROOT}/build/stage2n_a17_6/host_v1/host_build_status.txt"
MAP_PARSER="${REPO_ROOT}/scripts/parse_stage2n_a17_6_xclbin_map_v1.py"
SOURCE_CHECKER="${REPO_ROOT}/scripts/check/check_stage2n_a17_6_host_prep_v1.py"
ELF_IDENTITY_CHECKER="${REPO_ROOT}/scripts/check/check_stage2n_a17_6_host_elf_identity_v1.py"
# Historical Host identities, not execute defaults and not runtime-verified:
#   pre-fix ELF 520d78efe3a4ba81a8cd3a66ee48042d39a14a0a3e4fb390e567bd7afb3bf5cd
#     did not complete the four-bank function path
#   build-record ELF 9ba376589f56d99efca6e42328d347a6539ba1c40bba56d21ab690d87e7f20fc
#     compile record for the successful 20260910_102244 run; no pre-exec hash
# Execute requires A17_6_EXPECTED_HOST_ELF_SHA256 to be set explicitly.

TARGET_BDF="${A17_6_TARGET_BDF:-}"
TARGET_INDEX="${A17_6_TARGET_INDEX:-}"
TARGET_RENDER="${A17_6_TARGET_RENDER:-}"
XCLBIN="${A17_6_XCLBIN:-}"
EXPECTED_HOST_ELF_SHA256="${A17_6_EXPECTED_HOST_ELF_SHA256:-}"
EXPECTED_HOST_SOURCE_SHA256="${A17_6_EXPECTED_HOST_SOURCE_SHA256:-}"

STAMP="$(date +%Y%m%d_%H%M%S)"
RESULT_DIR="${REPO_ROOT}/results/stage2n_a17_6/protected_v1/${STAMP}"
mkdir -p "${RESULT_DIR}"
LOG="${RESULT_DIR}/runner.log"
PROGRAMMING_STATUS="NOT_RUN"
exec > >(tee "${LOG}") 2>&1

fail()
{
    echo "ERROR: $*" >&2
    echo "A17_6_BOARD=NOT_RUN" >&2
    echo "FPGA_PROGRAMMING=${PROGRAMMING_STATUS}" >&2
    echo "NO FPGA RESET OR GLOBAL HBM CLEANUP WAS ATTEMPTED" >&2
    if [[ -n "${LOG:-}" ]]; then
        {
            echo "ERROR: $*"
            echo "A17_6_BOARD=NOT_RUN"
            echo "FPGA_PROGRAMMING=${PROGRAMMING_STATUS}"
            echo "NO FPGA RESET OR GLOBAL HBM CLEANUP WAS ATTEMPTED"
        } >> "${LOG}"
    fi
    exit 10
}

require_goldens()
{
    python3 - "${MANIFEST}" "${MODEL_DIR}" "${HOST_SOURCE}" <<'PY' || fail "golden lock failed"
import hashlib, json, pathlib, sys
manifest = json.load(open(sys.argv[1], "r"))
root = pathlib.Path(sys.argv[2])
host = pathlib.Path(sys.argv[3]).read_text(encoding="utf-8")
expected = [-393, -392, -93, -689, -519]
names = ["baseline", "slot0_sensitivity", "slot1_sensitivity",
         "slot2_sensitivity", "slot3_sensitivity"]
cases = manifest["cases"]
assert len(cases) == 5
for index, case in enumerate(cases):
    assert case["name"] == names[index]
    assert case["expected_final_result"] == expected[index]
    table = root / case["file"]
    digest = hashlib.sha256(table.read_bytes()).hexdigest()
    assert digest == case["payload_sha256"]
    assert table.stat().st_size == 1024
assert "kLockedGoldens" in host
for value in expected:
    assert str(value) in host
assert "XSim result 36 is not a board golden" in host
print("A17_6_GOLDEN_LOCK=PASS")
PY
}

dump_xclbin_map()
{
    local xclbin="$1"
    local info="${RESULT_DIR}/${EXPECTED_KERNEL}.xclbin.info"
    local conn="${RESULT_DIR}/connectivity.json"
    local mem="${RESULT_DIR}/mem_topology.json"
    local ip="${RESULT_DIR}/ip_layout.json"
    local map="${RESULT_DIR}/a17_6_mem_map.txt"
    xclbinutil --info --input "${xclbin}" > "${info}" 2>&1 || fail "xclbinutil info failed"
    local uuid
    uuid="$(sed -n 's/^[[:space:]]*UUID (xclbin):[[:space:]]*//p' "${info}" | head -n1 | tr -d '\r')"
    [[ "${uuid}" == "${EXPECTED_UUID}" ]] || fail "xclbin UUID mismatch: ${uuid}"
    grep -Fq "${EXPECTED_KERNEL}" "${info}" || fail "A17 kernel missing from xclbin info"
    grep -Fq "${EXPECTED_INSTANCE}" "${info}" || fail "A17 CU missing from xclbin info"
    grep -F "${STALE_XO_SHA256}" "${info}" >/dev/null && fail "stale xo_001 fingerprint found"
    xclbinutil --dump-section CONNECTIVITY:JSON:"${conn}" --input "${xclbin}" >/dev/null
    xclbinutil --dump-section MEM_TOPOLOGY:JSON:"${mem}" --input "${xclbin}" >/dev/null
    xclbinutil --dump-section IP_LAYOUT:JSON:"${ip}" --input "${xclbin}" >/dev/null
    python3 "${MAP_PARSER}" \
        --connectivity "${conn}" \
        --mem-topology "${mem}" \
        --ip-layout "${ip}" \
        --uuid "${EXPECTED_UUID}" \
        --output "${map}" || fail "memory-map parse failed"
    echo "MEM_MAP=${map}"
}

echo "A17_6_PROTECTED_FLOW=START"
echo "ACTION=${ACTION}"
echo "EXPECTED_XCLBIN_SHA256=${EXPECTED_XCLBIN_SHA256}"
echo "EXPECTED_UUID=${EXPECTED_UUID}"
echo "EXPECTED_KERNEL=${EXPECTED_KERNEL}"
echo "EXPECTED_CU=${EXPECTED_INSTANCE}"
echo "LIVE_XO_SHA256=${LIVE_XO_SHA256}"
echo "STALE_XO_SHA256=${STALE_XO_SHA256}"
echo "STALE_XO_STATUS=SUPERSEDED_NOT_FOR_EXECUTION"
echo "HBM_BANKS=HBM[0],HBM[1],HBM[2],HBM[3]"
echo "FPGA_PROGRAMMING=NOT_RUN"
echo "BOARD=NOT_RUN"
echo "PERFORMANCE=NOT_CLAIMED"

[[ -s "${HOST_SOURCE}" ]] || fail "A17.6 Host source missing"
[[ -f "${MANIFEST}" && -s "${MODEL}" ]] || fail "A15.6 model assets missing"
python3 "${SOURCE_CHECKER}" --repo "${REPO_ROOT}" || fail "local Host preparation check failed"
require_goldens

if [[ "${ACTION}" == "prepare" ]]; then
    echo "PREPARE_XCLBIN_DUMP=SKIPPED"
    echo "PREPARE_XBUTIL=NOT_INVOKED"
    echo "PREPARE_HOST_EXECUTION=NOT_RUN"
    echo "PREPARE_DEVICE_OPEN=NOT_RUN"
    if [[ "${A17_6_BUILD_HOST:-no}" == "yes" ]]; then
        bash "${HOST_BUILD_SCRIPT}" || fail "A17.6 Host build failed"
        grep -Fxq "A17_6_HOST_XRT_BUILD=PASS" "${HOST_BUILD_STATUS}" ||
            fail "Host build PASS missing"
        grep -Fxq "HOST_EXECUTION=NOT_RUN" "${HOST_BUILD_STATUS}" ||
            fail "Host build status must keep HOST_EXECUTION=NOT_RUN"
        grep -Fxq "COMPILER_EXIT_CODE=0" "${HOST_BUILD_STATUS}" ||
            fail "compiler exit code 0 missing from Host build status"
        grep -E '^BINARY_SHA256=[0-9a-f]{64}$' "${HOST_BUILD_STATUS}" >/dev/null ||
            fail "BINARY_SHA256 missing"
        grep -E '^SOURCE_SHA256=[0-9a-f]{64}$' "${HOST_BUILD_STATUS}" >/dev/null ||
            fail "SOURCE_SHA256 missing"
        [[ -s "${HOST_BINARY}" ]] || fail "Host ELF missing or empty after reported PASS"
        echo "HOST_BINARY=${HOST_BINARY}"
        echo "HOST_BUILD_STATUS=${HOST_BUILD_STATUS}"
        echo "HOST_BUILD_LOG=${REPO_ROOT}/build/stage2n_a17_6/host_v1/host_build.log"
    else
        echo "HOST_BUILD=NOT_RUN"
        echo "HINT=set A17_6_BUILD_HOST=yes to compile on the target after this prepare check"
    fi
    echo "A17_6_HOST_PREPARE=PASS"
    echo "A17_6_BOARD_EXECUTION=NOT_AUTHORIZED"
    echo "FPGA_PROGRAMMING=NOT_RUN"
    echo "HOST_EXECUTION=NOT_RUN"
    echo "BOARD=NOT_RUN"
    echo "PHYSICAL_HBM=NOT_RUN"
    echo "PERFORMANCE=NOT_CLAIMED"
    echo "FIRST_BOARD_RUN_REQUIRES=A17_6_BOARD_EXECUTION_AUTHORIZED=yes plus execute"
    exit 0
fi

if [[ "${ACTION}" != "execute" ]]; then
    fail "usage: $0 prepare|execute"
fi

[[ "${A17_6_BOARD_EXECUTION_AUTHORIZED:-no}" == "yes" ]] ||
    fail "first board execution is not authorized in this stage; keep ACTION=prepare"
[[ "${A17_6_ALLOW_PROGRAM:-no}" == "yes" ]] ||
    fail "execute refused: A17_6_ALLOW_PROGRAM is not yes"
[[ "${EXPECTED_HOST_ELF_SHA256}" =~ ^[0-9a-f]{64}$ ]] ||
    fail "set A17_6_EXPECTED_HOST_ELF_SHA256 to the locked 64-hex Host ELF; do not default to a historical fingerprint"
[[ "${EXPECTED_HOST_SOURCE_SHA256}" =~ ^[0-9a-f]{64}$ ]] ||
    fail "set A17_6_EXPECTED_HOST_SOURCE_SHA256 to the locked 64-hex Host source"
[[ -n "${TARGET_INDEX}" && "${TARGET_INDEX}" =~ ^[0-9]+$ ]] ||
    fail "set A17_6_TARGET_INDEX explicitly"
[[ -n "${TARGET_BDF}" ]] || fail "set A17_6_TARGET_BDF explicitly"
[[ -n "${TARGET_RENDER}" ]] || fail "set A17_6_TARGET_RENDER explicitly"
[[ -n "${XCLBIN}" && -s "${XCLBIN}" ]] || fail "set A17_6_XCLBIN to the link_004 xclbin"
[[ -f "${XRT_SETUP}" ]] || fail "XRT setup is missing"

set +u
# shellcheck disable=SC1090
source "${XRT_SETUP}" >/dev/null || { set -u; fail "failed to initialize XRT"; }
set -u
for tool in xbutil xclbinutil git sha256sum python3 awk grep fuser lsof readlink hostname; do
    command -v "${tool}" >/dev/null 2>&1 || fail "required tool missing: ${tool}"
done

ACTUAL_XCLBIN_SHA256="$(sha256sum "${XCLBIN}" | awk '{print $1}')"
[[ "${ACTUAL_XCLBIN_SHA256}" == "${EXPECTED_XCLBIN_SHA256}" ]] ||
    fail "fixed xclbin SHA256 mismatch"
[[ "${ACTUAL_XCLBIN_SHA256}" != "${STALE_XO_SHA256}" ]] ||
    fail "stale xo_001 bytes presented as an xclbin"

# Host identity is checked before xclbinutil dump, xbutil, or program.
[[ -x "${HOST_BINARY}" ]] ||
    fail "execute refused: Host ELF missing; execute does not rebuild"
[[ -s "${HOST_BUILD_STATUS}" ]] || fail "A17.6 Host build status missing"
python3 "${ELF_IDENTITY_CHECKER}" \
    --expected-elf-sha256 "${EXPECTED_HOST_ELF_SHA256}" \
    --expected-source-sha256 "${EXPECTED_HOST_SOURCE_SHA256}" \
    --binary "${HOST_BINARY}" \
    --status "${HOST_BUILD_STATUS}" \
    --source "${HOST_SOURCE}" || fail "Host ELF identity trio failed before program"
echo "HOST_IDENTITY_CHECKED_BEFORE_PROGRAM=YES"
echo "HOST_EXECUTE_PATH=${HOST_BINARY}"

dump_xclbin_map "${XCLBIN}"
MEM_MAP="${RESULT_DIR}/a17_6_mem_map.txt"
[[ -s "${MEM_MAP}" ]] || fail "memory map missing"

extract_uuid()
{
    awk '/Xclbin UUID/ {getline; gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0); print; exit}'
}

query_target()
{
    xbutil query -d "${TARGET_BDF}" 2>&1
}

require_empty_hbm_tag()
{
    local text="$1" tag="$2" stage="$3" line
    line="$(printf '%s\n' "${text}" | grep -F " ${tag} " | head -1)"
    [[ -n "${line}" ]] || fail "${stage}: ${tag} line missing"
    printf '%s\n' "${line}" | grep -Eq '0 Byte[[:space:]]+0[[:space:]]*$' ||
        fail "${stage}: ${tag} has active bytes or BOs"
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

[[ -e "${TARGET_RENDER}" ]] || fail "guarded render node not found"
check_target_mapping
PRE_QUERY="$(query_target)" || fail "pre-authorization query failed"
printf '%s\n' "${PRE_QUERY}" > "${RESULT_DIR}/pre_device_query.txt"
printf '%s\n' "${PRE_QUERY}" | grep -q 'Level 0 : 0x0(GOOD)' || fail "target firewall is not GOOD"
for bank in 0 1 2 3; do
    require_empty_hbm_tag "${PRE_QUERY}" "HBM[${bank}]" "PRE_AUTHORIZATION"
done
CURRENT_UUID="$(printf '%s\n' "${PRE_QUERY}" | extract_uuid)"

echo "============================================================"
echo "Stage 2N-A17.6 protected board authorization"
echo "TARGET_INDEX=${TARGET_INDEX}"
echo "TARGET_BDF=${TARGET_BDF}"
echo "TARGET_RENDER=${TARGET_RENDER}"
echo "XCLBIN_SHA256=${ACTUAL_XCLBIN_SHA256}"
echo "XCLBIN_UUID=${EXPECTED_UUID}"
echo "HOST_EXECUTE_PATH=${HOST_BINARY}"
echo "HOST_EXPECTED_ELF_SHA256=${EXPECTED_HOST_ELF_SHA256}"
echo "HOST_EXPECTED_SOURCE_SHA256=${EXPECTED_HOST_SOURCE_SHA256}"
echo "KERNEL=${EXPECTED_KERNEL}"
echo "CU=${EXPECTED_INSTANCE}"
echo "HBM_BANKS=HBM[0],HBM[1],HBM[2],HBM[3]"
echo "HBM[0]=REQUIRED"
echo "HBM[3]=REQUIRED"
echo "CURRENT_UUID=${CURRENT_UUID}"
echo "A17_6_FORCE_NO_PROGRAM=${A17_6_FORCE_NO_PROGRAM:-no}"
if [[ "${CURRENT_UUID}" == "${EXPECTED_UUID}" ]]; then
    echo "ACTION_PROGRAM_FPGA_IF_NEEDED=NO_ALREADY_LOADED"
else
    if [[ "${A17_6_FORCE_NO_PROGRAM:-}" == "yes" ]]; then
        echo "ACTION_PROGRAM_FPGA_IF_NEEDED=REFUSED_FORCE_NO_PROGRAM"
    else
        echo "ACTION_PROGRAM_FPGA_IF_NEEDED=YES"
    fi
fi
echo "ACTION_ALLOCATE_FOUR_HBM_BOS=YES"
echo "ACTION_RUN_COMPLETE_DLRM_INFERENCE=YES"
echo "FPGA_RESET=NOT_RUN"
echo "GLOBAL_HBM_CLEANUP=NOT_RUN"
echo "OTHER_DEVICE_ACCESS=NONE"
echo "============================================================"
confirmation="${A17_6_CONFIRM:-}"
if [[ -z "${confirmation}" ]]; then
    [[ -t 0 ]] || fail "interactive confirmation unavailable; set A17_6_CONFIRM=yes after review"
    read -r -p "Proceed with this protected A17.6 four-BO run? [yes/no] " confirmation
fi
if [[ "${confirmation}" != "yes" ]]; then
    echo "A17.6 protected run cancelled safely."
    echo "FPGA_PROGRAMMING=NOT_RUN"
    echo "BOARD=NOT_RUN"
    exit 0
fi

if [[ "${CURRENT_UUID}" != "${EXPECTED_UUID}" ]]; then
    if [[ "${A17_6_FORCE_NO_PROGRAM:-}" == "yes" ]]; then
        fail "UUID is ${CURRENT_UUID}, expected ${EXPECTED_UUID}; A17_6_FORCE_NO_PROGRAM=yes refuses xbutil program"
    fi
    xbutil program -d "${TARGET_BDF}" -p "${XCLBIN}" || fail "xbutil program failed"
    PROGRAMMING_STATUS="PASS"
    sleep 3
else
    PROGRAMMING_STATUS="SKIPPED_ALREADY_LOADED"
    echo "A17_6_PROGRAM=SKIPPED_ALREADY_LOADED"
fi

mapfile -t CASE_ARGUMENTS < <(python3 - "${MANIFEST}" "${MODEL_DIR}" <<'PY'
import json, pathlib, sys
manifest = json.load(open(sys.argv[1], "r"))
root = pathlib.Path(sys.argv[2])
for case in manifest["cases"]:
    print(str(root / case["file"]))
    print(case["expected_final_result"])
PY
)
[[ "${#CASE_ARGUMENTS[@]}" -eq 10 ]] || fail "case argument construction failed"

HOST_LOG="${RESULT_DIR}/host.log"
set +e
"${HOST_BINARY}" "${TARGET_INDEX}" "${TARGET_BDF}" "${EXPECTED_UUID}" "${MODEL}" \
    "${MEM_MAP}" "${CASE_ARGUMENTS[@]}" > "${HOST_LOG}" 2>&1
host_exit="$?"
set -e
echo "HOST_EXIT_CODE=${host_exit}"
echo "HOST_EXECUTE_PATH=${HOST_BINARY}"
cat "${HOST_LOG}"
[[ "${host_exit}" -eq 0 ]] || fail "A17.6 Host returned ${host_exit}"
grep -Fxq "STAGE2N_A17_6_FOUR_BO_HOST_V1=PASS" "${HOST_LOG}" || fail "Host PASS missing"
grep -Fxq "A17_6_BO_CLEANUP=PASS" "${HOST_LOG}" || fail "BO cleanup PASS missing"
grep -Fq "XSIM_RESULT_36_NOT_USED=1" "${HOST_LOG}" || fail "XSim-36 guard missing"

echo "A17_6_FPGA_PROGRAMMING=${PROGRAMMING_STATUS}"
echo "A17_6_BOARD_FUNCTIONAL=HOST_RETURNED_PASS"
echo "A17_6_PERFORMANCE=NOT_CLAIMED"
echo "FPGA_RESET=NOT_RUN"
echo "OTHER_DEVICE_ACCESS=NONE"
echo "NOTE=physical four-bank PASS still requires a separate evidence review"
