#!/usr/bin/env bash
# A18.3 extra-run on the already-loaded A18 xclbin.
# Never programs. Never resets. Codex does not execute this script.
# Requires the reviewed A18.3 Host ELF and UUID 32a9c911-...

set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

ACTION="${1:-prepare}"
EXPECTED_KERNEL="dlrm_f37x_rtl_kernel_stage2n_a18_v1"
EXPECTED_INSTANCE="dlrm_a18_1"
EXPECTED_PLATFORM="inspur_f37x_xdma_201920_3"
EXPECTED_XCLBIN_SHA256="bbb0fa1fcb5c39aea2a307eb8c8324eb406c51711b8ba2ae7830bc5fe3a36ec0"
EXPECTED_UUID="32a9c911-af15-47fc-90c8-0bfe3894a3ef"
A17_XCLBIN_SHA256="b8d2034906451cc755b6c01a50c94a4b841998c3e2794c6e417dd1ab952e46ae"
A17_UUID="622c839f-55f4-47c1-92e9-95ee5595ffa4"
A16_UUID="f18571de-4a43-46bd-8ab9-a89dd4b11f8e"
EXPECTED_XRT_VERSION="2.9.210507"
XRT_SETUP="${XRT_SETUP:-/opt/xilinx/xrt/setup.sh}"

MODEL="${REPO_ROOT}/models/stage2n_a15_6/stage2n_a15_6_model_v1.bin"
BASELINE="${REPO_ROOT}/models/stage2n_a15_6/stage2n_a15_6_case0_baseline_table_v1.bin"
HOST_SOURCE="${REPO_ROOT}/host/stage2n_a18_3_index_tuple_host_v1.cpp"
HOST_BINARY="${REPO_ROOT}/build/stage2n_a18_3/host_v1/stage2n_a18_3_index_tuple_host_v1"
HOST_BUILD_STATUS="${REPO_ROOT}/build/stage2n_a18_3/host_v1/host_build_status.txt"
MAP_PARSER="${REPO_ROOT}/scripts/parse_stage2n_a18_2_xclbin_map_v1.py"
SOURCE_CHECKER="${REPO_ROOT}/scripts/check/check_stage2n_a18_3_board_prepare_v1.py"
ELF_IDENTITY_CHECKER="${REPO_ROOT}/scripts/check/check_stage2n_a18_3_host_elf_identity_v1.py"

TARGET_BDF="${A18_3_TARGET_BDF:-}"
TARGET_INDEX="${A18_3_TARGET_INDEX:-}"
TARGET_RENDER="${A18_3_TARGET_RENDER:-}"
XCLBIN="${A18_3_XCLBIN:-}"
EXPECTED_HOST_ELF_SHA256="${A18_3_EXPECTED_HOST_ELF_SHA256:-}"
EXPECTED_HOST_SOURCE_SHA256="${A18_3_EXPECTED_HOST_SOURCE_SHA256:-}"

STAMP="$(date +%Y%m%d_%H%M%S)"
RESULT_DIR="${REPO_ROOT}/results/stage2n_a18_3/extra_run_v1/${STAMP}"
mkdir -p "${RESULT_DIR}"
LOG="${RESULT_DIR}/runner.log"
exec > >(tee "${LOG}") 2>&1

fail()
{
    echo "ERROR: $*" >&2
    echo "A18_3_EXTRA_RUN=NOT_RUN" >&2
    echo "FPGA_PROGRAMMING=NOT_RUN" >&2
    echo "FPGA_RESET=NOT_RUN" >&2
    echo "NO FPGA RESET OR PROGRAM WAS ATTEMPTED" >&2
    exit 10
}

echo "A18_3_EXTRA_RUN_FLOW=START"
echo "ACTION=${ACTION}"
echo "EXPECTED_UUID=${EXPECTED_UUID}"
echo "FPGA_PROGRAMMING=NOT_RUN"
echo "FPGA_RESET=NOT_RUN"
echo "PERFORMANCE=NOT_CLAIMED"

[[ -s "${HOST_SOURCE}" ]] || fail "A18.3 Host source missing"
[[ -f "${MODEL}" && -s "${MODEL}" ]] || fail "A15.6 model.bin missing"
[[ -f "${BASELINE}" && -s "${BASELINE}" ]] || fail "baseline table missing"
python3 "${SOURCE_CHECKER}" --repo "${REPO_ROOT}" || fail "board-tree prepare check failed"

if [[ "${ACTION}" == "prepare" ]]; then
    echo "PREPARE_XBUTIL=NOT_INVOKED"
    echo "A18_3_EXTRA_RUN=NOT_AUTHORIZED"
    echo "FPGA_PROGRAMMING=NOT_RUN"
    echo "FPGA_RESET=NOT_RUN"
    echo "PERFORMANCE=NOT_CLAIMED"
    echo "FIRST_EXTRA_RUN_REQUIRES=A18_3_EXTRA_RUN_AUTHORIZED=yes A18_3_CONFIRM=yes plus extra-run"
    exit 0
fi

if [[ "${ACTION}" != "extra-run" ]]; then
    fail "usage: $0 prepare|extra-run"
fi

[[ "${A18_3_EXTRA_RUN_AUTHORIZED:-no}" == "yes" ]] ||
    fail "extra-run is not authorized; keep ACTION=prepare"
[[ "${EXPECTED_HOST_ELF_SHA256}" =~ ^[0-9a-f]{64}$ ]] ||
    fail "set A18_3_EXPECTED_HOST_ELF_SHA256"
[[ "${EXPECTED_HOST_SOURCE_SHA256}" =~ ^[0-9a-f]{64}$ ]] ||
    fail "set A18_3_EXPECTED_HOST_SOURCE_SHA256"
[[ -n "${TARGET_INDEX}" && "${TARGET_INDEX}" =~ ^[0-9]+$ ]] ||
    fail "set A18_3_TARGET_INDEX explicitly"
[[ -n "${TARGET_BDF}" ]] || fail "set A18_3_TARGET_BDF explicitly"
[[ -n "${TARGET_RENDER}" ]] || fail "set A18_3_TARGET_RENDER explicitly"
[[ -n "${XCLBIN}" && -s "${XCLBIN}" ]] || fail "set A18_3_XCLBIN to the reviewed a18_2_link_001 xclbin"
[[ -f "${XRT_SETUP}" ]] || fail "XRT setup is missing"

set +u
# shellcheck disable=SC1090
source "${XRT_SETUP}" >/dev/null || { set -u; fail "failed to initialize XRT"; }
set -u
for tool in xbutil xclbinutil sha256sum python3 awk grep readlink; do
    command -v "${tool}" >/dev/null 2>&1 || fail "required tool missing: ${tool}"
done

ACTUAL_XCLBIN_SHA256="$(sha256sum "${XCLBIN}" | awk '{print $1}')"
[[ "${ACTUAL_XCLBIN_SHA256}" == "${EXPECTED_XCLBIN_SHA256}" ]] ||
    fail "fixed xclbin SHA256 mismatch"
[[ "${ACTUAL_XCLBIN_SHA256}" != "${A17_XCLBIN_SHA256}" ]] ||
    fail "A17 xclbin presented as A18"

[[ -x "${HOST_BINARY}" ]] || fail "Host ELF missing; extra-run does not rebuild"
[[ -s "${HOST_BUILD_STATUS}" ]] || fail "A18.3 Host build status missing"
python3 "${ELF_IDENTITY_CHECKER}" \
    --expected-elf-sha256 "${EXPECTED_HOST_ELF_SHA256}" \
    --expected-source-sha256 "${EXPECTED_HOST_SOURCE_SHA256}" \
    --binary "${HOST_BINARY}" \
    --status "${HOST_BUILD_STATUS}" \
    --source "${HOST_SOURCE}" || fail "Host ELF identity failed"
echo "HOST_EXECUTE_PATH=${HOST_BINARY}"

info="${RESULT_DIR}/${EXPECTED_KERNEL}.xclbin.info"
conn="${RESULT_DIR}/connectivity.json"
mem="${RESULT_DIR}/mem_topology.json"
ip="${RESULT_DIR}/ip_layout.json"
map="${RESULT_DIR}/a18_2_mem_map.txt"
xclbinutil --info --input "${XCLBIN}" > "${info}" 2>&1 || fail "xclbinutil info failed"
uuid="$(sed -n 's/^[[:space:]]*UUID (xclbin):[[:space:]]*//p' "${info}" | head -n1 | tr -d '\r')"
[[ "${uuid}" == "${EXPECTED_UUID}" ]] || fail "xclbin UUID mismatch: ${uuid}"
xclbinutil --dump-section CONNECTIVITY:JSON:"${conn}" --input "${XCLBIN}" >/dev/null
xclbinutil --dump-section MEM_TOPOLOGY:JSON:"${mem}" --input "${XCLBIN}" >/dev/null
xclbinutil --dump-section IP_LAYOUT:JSON:"${ip}" --input "${XCLBIN}" >/dev/null
python3 "${MAP_PARSER}" \
    --connectivity "${conn}" \
    --mem-topology "${mem}" \
    --ip-layout "${ip}" \
    --uuid "${EXPECTED_UUID}" \
    --output "${map}" || fail "memory-map parse failed"
MEM_MAP="${map}"

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

scan_output="$(xbutil scan 2>&1)" || fail "xbutil scan failed"
printf '%s\n' "${scan_output}" |
    grep -Eq "^[[:space:]]*\[${TARGET_INDEX}\][[:space:]]+${TARGET_BDF}[[:space:]]+${EXPECTED_PLATFORM}" ||
    fail "runtime index ${TARGET_INDEX} does not map to ${TARGET_BDF}/${EXPECTED_PLATFORM}"
[[ -e "${TARGET_RENDER}" ]] || fail "guarded render node not found"
render_sysfs="$(readlink -f "/sys/class/drm/$(basename "${TARGET_RENDER}")/device" 2>/dev/null || true)"
[[ "${render_sysfs}" == *"/${TARGET_BDF}" ]] ||
    fail "render node does not map to guarded BDF: ${render_sysfs}"

PRE_QUERY="$(query_target)" || fail "pre-authorization query failed"
printf '%s\n' "${PRE_QUERY}" > "${RESULT_DIR}/pre_device_query.txt"
printf '%s\n' "${PRE_QUERY}" | grep -q 'Level 0 : 0x0(GOOD)' || fail "target firewall is not GOOD"
for bank in 0 1 2 3; do
    require_empty_hbm_tag "${PRE_QUERY}" "HBM[${bank}]" "PRE_AUTHORIZATION"
done
CURRENT_UUID="$(printf '%s\n' "${PRE_QUERY}" | extract_uuid)"
[[ "${CURRENT_UUID}" == "${EXPECTED_UUID}" ]] ||
    fail "CURRENT_UUID=${CURRENT_UUID} is not ${EXPECTED_UUID}; extra-run refuses to program"

echo "============================================================"
echo "Stage 2N-A18.3 extra-run (no program, no reset)"
echo "TARGET_INDEX=${TARGET_INDEX}"
echo "TARGET_BDF=${TARGET_BDF}"
echo "CURRENT_UUID=${CURRENT_UUID}"
echo "ACTION_PROGRAM_FPGA=NO"
echo "FPGA_RESET=NOT_RUN"
echo "NOTE_REJECT_A16_UUID=${A16_UUID}"
echo "NOTE_REJECT_A17_UUID=${A17_UUID}"
echo "PERFORMANCE=NOT_CLAIMED"
echo "============================================================"
confirmation="${A18_3_CONFIRM:-}"
if [[ -z "${confirmation}" ]]; then
    [[ -t 0 ]] || fail "interactive confirmation unavailable; set A18_3_CONFIRM=yes after review"
    read -r -p "Proceed with this extra-run (no program, no reset)? [yes/no] " confirmation
fi
if [[ "${confirmation}" != "yes" ]]; then
    echo "A18.3 extra-run cancelled safely."
    echo "FPGA_PROGRAMMING=NOT_RUN"
    echo "A18_3_EXTRA_RUN=NOT_RUN"
    exit 0
fi

HOST_LOG="${RESULT_DIR}/host.log"
set +e
unset A18_2_LOOKUP_INDEXES
unset A18_2_ALLOW_NONDEFAULT_INDEXES
"${HOST_BINARY}" "${TARGET_INDEX}" "${TARGET_BDF}" "${EXPECTED_UUID}" "${MODEL}" \
    "${MEM_MAP}" "${BASELINE}" > "${HOST_LOG}" 2>&1
host_exit="$?"
set -e
echo "HOST_EXIT_CODE=${host_exit}"
cat "${HOST_LOG}"
[[ "${host_exit}" -eq 0 ]] || fail "A18.3 Host returned ${host_exit}"
grep -Fxq "STAGE2N_A18_3_INDEX_TUPLE_HOST_V1=PASS" "${HOST_LOG}" || fail "Host PASS missing"
grep -Fxq "A18_3_ALL_FIVE_TUPLES=PASS" "${HOST_LOG}" || fail "five-tuple PASS missing"
grep -Fxq "TUPLE0_EXPECTED_RESULT=-393" "${HOST_LOG}" || fail "TUPLE0 golden missing"
grep -Fxq "TUPLE1_EXPECTED_RESULT=-61" "${HOST_LOG}" || fail "TUPLE1 golden missing"
grep -Fxq "TUPLE2_EXPECTED_RESULT=-60" "${HOST_LOG}" || fail "TUPLE2 golden missing"
grep -Fxq "TUPLE3_EXPECTED_RESULT=-162" "${HOST_LOG}" || fail "TUPLE3 golden missing"
grep -Fxq "TUPLE4_EXPECTED_RESULT=-185" "${HOST_LOG}" || fail "TUPLE4 golden missing"
for n in 0 1 2 3 4; do
    grep -Fxq "TUPLE${n}_COMPLETE_DLRM_RESULT=PASS" "${HOST_LOG}" || fail "TUPLE${n} complete-DLRM PASS missing"
    grep -Fxq "TUPLE${n}_BOTTOM_CYCLES_ACTUAL=322" "${HOST_LOG}" || fail "TUPLE${n} bottom cycles missing"
    grep -Fxq "TUPLE${n}_INTERACTION_CYCLES_ACTUAL=100" "${HOST_LOG}" || fail "TUPLE${n} interaction cycles missing"
    grep -Fxq "TUPLE${n}_TOP_CYCLES_ACTUAL=744" "${HOST_LOG}" || fail "TUPLE${n} top cycles missing"
    grep -Fxq "TUPLE${n}_COMPUTE_TOTAL_CYCLES_ACTUAL=1174" "${HOST_LOG}" || fail "TUPLE${n} total cycles missing"
done

POST_QUERY="$(query_target)" || fail "post-host query failed"
printf '%s\n' "${POST_QUERY}" > "${RESULT_DIR}/post_host_query.txt"
for bank in 0 1 2 3; do
    require_empty_hbm_tag "${POST_QUERY}" "HBM[${bank}]" "POST_HOST"
done

echo "A18_3_EXTRA_RUN=HOST_RETURNED_PASS"
echo "FPGA_PROGRAMMING=NOT_RUN"
echo "FPGA_RESET=NOT_RUN"
echo "A18_3_PERFORMANCE=NOT_CLAIMED"
echo "NOTE=extra-run is not T>4 and is not a speedup; copy originals for review"
