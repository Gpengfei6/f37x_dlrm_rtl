#!/usr/bin/env bash
# Stage 2N-A14.7 protected physical-HBM single-table smoke.
#
# Authorized target only:
#   xbutil index : 2
#   BDF          : 0000:9b:00.1
#   render node  : /dev/dri/renderD129
#
# Safety contract:
#   - Never resets the FPGA and never performs automatic rollback.
#   - Never programs unless the current source UUID/CU is explicitly allowlisted.
#   - If the accepted A14.6 image is already loaded, programming is skipped.
#   - Requires a stable read-only activity guard and HBM[0]=0 Byte/0 BO before use.
#   - Uses the accepted A14.6 xclbin identity exactly.
#   - Requires yes/no authorization before any programming action.
#   - Host allocates exactly one 1024-byte BO in HBM[0], performs one lookup,
#     releases the BO, and the runner requires HBM[0] to return to zero usage.

set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

XRT_SETUP="${XRT_SETUP:-/opt/xilinx/xrt/setup.sh}"
EXPECTED_XRT_VERSION="2.9.210507"
TARGET_INDEX="2"
TARGET_BDF="0000:9b:00.1"
TARGET_RENDER="/dev/dri/renderD129"
EXPECTED_PLATFORM="inspur_f37x_xdma_201920_3"
EXPECTED_BRANCH="work/stage2n-a13-cycle-counter"
REQUIRED_ANCESTOR="b44855ed4bc8b469257cb3de80cf530e9d5039b9"
EXPECTED_UUID="6f29087c-9598-4e68-877a-cc4840d078b8"
EXPECTED_XCLBIN_SHA256="9a7ce2518691e1d9a9ef55a0037d5d5345e3781f1e11eb7c2c7d19697144f573"
EXPECTED_KERNEL="dlrm_f37x_rtl_kernel_stage2n_a14_v2"
EXPECTED_INSTANCE="dlrm_a14_1"
EXPECTED_CU="${EXPECTED_KERNEL}:${EXPECTED_INSTANCE}"
EXPECTED_IP_INDEX="0"
EXPECTED_HBM_MEMORY_INDEX="0"
LOOKUP_INDEX="${A14_7_LOOKUP_INDEX:-37}"
GUARD_SECONDS=30

XCLBIN="${REPO_ROOT}/build/stage2n_a14_6/link_v1/hw/${EXPECTED_KERNEL}.xclbin"
XCLBIN_INFO="${REPO_ROOT}/results/stage2n_a14_6/link_v1/${EXPECTED_KERNEL}.xclbin.info"
A14_6_STATUS="${REPO_ROOT}/results/stage2n_a14_6/link_v1/a14_6_link_v1_status.txt"
HOST_BUILD_SCRIPT="${REPO_ROOT}/scripts/build_stage2n_a14_7_host_v1.sh"
HOST_BUILD_DIR="${REPO_ROOT}/build/stage2n_a14_7/host_v1"
HOST_BUILD_STATUS="${HOST_BUILD_DIR}/host_build_status.txt"
HOST_BINARY="${HOST_BUILD_DIR}/stage2n_a14_7_hbm_single_table_board_smoke_v1"
PAYLOAD="${HOST_BUILD_DIR}/stage2n_a14_7_hbm_table.bin"
VALIDATOR="${REPO_ROOT}/python/verify_stage2n_a14_7_evidence_v1.py"

STAMP="$(date +%Y%m%d_%H%M%S)"
RESULT_DIR="${REPO_ROOT}/results/stage2n_a14_7/board_smoke_v1/${STAMP}"
LOG_DIR="${REPO_ROOT}/server_results/stage2n_a14_7"
LOG="${LOG_DIR}/stage2n_a14_7_hbm_smoke_v1_${STAMP}.log"
HOST_LOG="${RESULT_DIR}/host.log"
EVIDENCE="${RESULT_DIR}/a14_7_evidence_64.txt"
VALIDATION_LOG="${RESULT_DIR}/evidence_validation.log"
FAILURE_STATUS="${RESULT_DIR}/failure_status.txt"
PRE_QUERY_FILE="${RESULT_DIR}/pre_host_query.txt"
POST_QUERY_FILE="${RESULT_DIR}/post_host_query.txt"

mkdir -p "${RESULT_DIR}" "${LOG_DIR}"
exec > >(tee "${LOG}") 2>&1

write_failure()
{
    local reason="$1"
    {
        echo "A14_7_BOARD_SMOKE=FAILED"
        echo "TIME=$(date -Is)"
        echo "TARGET_INDEX=${TARGET_INDEX}"
        echo "TARGET_BDF=${TARGET_BDF}"
        echo "TARGET_RENDER=${TARGET_RENDER}"
        echo "REASON=${reason}"
        echo "NO_FPGA_RESET=1"
        echo "NO_AUTOMATIC_ROLLBACK=1"
        echo "NO_OTHER_DEVICE_WRITE=1"
        echo "LOG=${LOG}"
    } > "${FAILURE_STATUS}"
}

fail()
{
    local reason="$*"
    write_failure "${reason}"
    echo "ERROR: ${reason}" >&2
    echo "No FPGA reset or automatic rollback was attempted." >&2
    echo "FAILURE_STATUS=${FAILURE_STATUS}" >&2
    exit 10
}

extract_uuid()
{
    awk '
        /Xclbin UUID/ {
            getline
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0)
            print
            exit
        }
    '
}

extract_cu_line()
{
    grep -E '^CU\[' | head -1
}

extract_dma_lines()
{
    grep -E '^Chan\[0\]\.(h2c|c2h):'
}

extract_hbm0_line()
{
    grep -E '^\[[[:space:]]*0\][[:space:]]+HBM\[0\]' | head -1
}

query_target()
{
    xbutil query -d "${TARGET_BDF}" 2>&1
}

require_firewall_good()
{
    local text="$1"
    local stage="$2"
    printf '%s\n' "${text}" | grep -q "Level 0 : 0x0(GOOD)" ||
        fail "${stage}: target firewall is not GOOD"
}

require_empty_render()
{
    local stage="$1"
    local fuser_output lsof_output
    fuser_output="$(fuser -v "${TARGET_RENDER}" 2>&1 || true)"
    lsof_output="$(lsof "${TARGET_RENDER}" 2>&1 || true)"
    if [[ -n "${fuser_output//[[:space:]]/}" ]]; then
        printf '%s\n' "${fuser_output}"
        fail "${stage}: fuser reports an open handle on ${TARGET_RENDER}"
    fi
    if [[ -n "${lsof_output//[[:space:]]/}" ]]; then
        printf '%s\n' "${lsof_output}"
        fail "${stage}: lsof reports an open handle on ${TARGET_RENDER}"
    fi
    echo "${stage}: render node has no open handle"
}

require_hbm0_empty()
{
    local query_text="$1"
    local stage="$2"
    local hbm_line
    hbm_line="$(printf '%s\n' "${query_text}" | extract_hbm0_line)"
    [[ -n "${hbm_line}" ]] || fail "${stage}: HBM[0] status line is missing"
    printf '%s\n' "${hbm_line}" |
        grep -Eq 'HBM\[0\].*0 Byte[[:space:]]+0[[:space:]]*$' ||
        fail "${stage}: HBM[0] reports memory use or active BOs"
    echo "${stage}: HBM[0] usage is 0 Byte and BO count is 0"
}

check_target_mapping()
{
    local scan_output render_sysfs
    scan_output="$(xbutil scan 2>&1)" || fail "xbutil scan failed"
    echo "${scan_output}"
    printf '%s\n' "${scan_output}" |
        grep -Eq "^[[:space:]]*\[${TARGET_INDEX}\][[:space:]]+${TARGET_BDF}[[:space:]]+${EXPECTED_PLATFORM}" ||
        fail "index ${TARGET_INDEX} is not mapped to ${TARGET_BDF}/${EXPECTED_PLATFORM}"
    render_sysfs="$(readlink -f "/sys/class/drm/$(basename "${TARGET_RENDER}")/device" 2>/dev/null || true)"
    [[ "${render_sysfs}" == *"/${TARGET_BDF}" ]] ||
        fail "render node does not map to locked BDF: ${render_sysfs}"
    echo "RENDER_SYSFS=${render_sysfs}"
}

GUARD_CU_LINE=""
GUARD_DMA_LINES=""
activity_guard()
{
    local expected_uuid="$1"
    local expected_cu="$2"
    local query1 query2 uuid1 uuid2 cu1 cu2 dma1 dma2

    echo "========== A14.7 READ-ONLY ACTIVITY GUARD / SAMPLE 1 =========="
    query1="$(query_target)" || fail "activity guard sample 1 query failed"
    require_firewall_good "${query1}" "ACTIVITY_GUARD_SAMPLE1"
    uuid1="$(printf '%s\n' "${query1}" | extract_uuid)"
    cu1="$(printf '%s\n' "${query1}" | extract_cu_line)"
    dma1="$(printf '%s\n' "${query1}" | extract_dma_lines)"
    [[ "${uuid1}" == "${expected_uuid}" ]] || fail "activity guard sample 1 UUID changed"
    printf '%s\n' "${cu1}" | grep -Fq "${expected_cu}" || fail "activity guard sample 1 CU mismatch"
    printf '%s\n' "${cu1}" | grep -Fq "(IDLE)" || fail "activity guard sample 1 CU is not IDLE"
    [[ -n "${dma1}" ]] || fail "activity guard sample 1 DMA lines are missing"
    require_empty_render "ACTIVITY_GUARD_SAMPLE1"
    require_hbm0_empty "${query1}" "ACTIVITY_GUARD_SAMPLE1"

    echo "Waiting ${GUARD_SECONDS} seconds; no programming or Host access occurs."
    sleep "${GUARD_SECONDS}"

    echo "========== A14.7 READ-ONLY ACTIVITY GUARD / SAMPLE 2 =========="
    query2="$(query_target)" || fail "activity guard sample 2 query failed"
    require_firewall_good "${query2}" "ACTIVITY_GUARD_SAMPLE2"
    uuid2="$(printf '%s\n' "${query2}" | extract_uuid)"
    cu2="$(printf '%s\n' "${query2}" | extract_cu_line)"
    dma2="$(printf '%s\n' "${query2}" | extract_dma_lines)"
    [[ "${uuid2}" == "${expected_uuid}" ]] || fail "activity guard sample 2 UUID changed"
    printf '%s\n' "${cu2}" | grep -Fq "${expected_cu}" || fail "activity guard sample 2 CU mismatch"
    printf '%s\n' "${cu2}" | grep -Fq "(IDLE)" || fail "activity guard sample 2 CU is not IDLE"
    [[ -n "${dma2}" ]] || fail "activity guard sample 2 DMA lines are missing"
    require_empty_render "ACTIVITY_GUARD_SAMPLE2"
    require_hbm0_empty "${query2}" "ACTIVITY_GUARD_SAMPLE2"
    [[ "${uuid1}" == "${uuid2}" ]] || fail "UUID changed during activity guard"
    [[ "${cu1}" == "${cu2}" ]] || fail "CU state changed during activity guard"
    [[ "${dma1}" == "${dma2}" ]] || fail "DMA counters changed during read-only activity guard"
    GUARD_CU_LINE="${cu2}"
    GUARD_DMA_LINES="${dma2}"
    echo "A14_7_ACTIVITY_GUARD=PASS"
}

host_value()
{
    local key="$1"
    awk -F= -v key="${key}" '$1 == key {sub(/^[^=]*=/, ""); print; exit}' "${HOST_LOG}"
}

[[ "${LOOKUP_INDEX}" =~ ^[0-9]+$ ]] || fail "A14_7_LOOKUP_INDEX must be decimal 0..63"
(( LOOKUP_INDEX >= 0 && LOOKUP_INDEX < 64 )) || fail "A14_7_LOOKUP_INDEX must be in 0..63"
[[ -f "${XRT_SETUP}" ]] || fail "XRT setup is missing: ${XRT_SETUP}"
# shellcheck disable=SC1090
source "${XRT_SETUP}" >/dev/null 2>&1 || fail "failed to initialize XRT"
for tool in xbutil git sha256sum awk grep fuser lsof readlink stat python3; do
    command -v "${tool}" >/dev/null 2>&1 || fail "required tool not found: ${tool}"
done
[[ -e "${TARGET_RENDER}" ]] || fail "render node not found: ${TARGET_RENDER}"
[[ -s "${XCLBIN}" ]] || fail "accepted A14.6 xclbin is missing: ${XCLBIN}"
[[ -s "${XCLBIN_INFO}" ]] || fail "accepted A14.6 xclbin info is missing: ${XCLBIN_INFO}"
[[ -s "${A14_6_STATUS}" ]] || fail "accepted A14.6 status is missing: ${A14_6_STATUS}"
[[ -s "${HOST_BUILD_SCRIPT}" ]] || fail "A14.7 Host build script is missing"
[[ -s "${VALIDATOR}" ]] || fail "A14.7 evidence validator is missing"

CURRENT_BRANCH="$(git symbolic-ref --short HEAD 2>/dev/null || true)"
CURRENT_HEAD="$(git rev-parse HEAD 2>/dev/null || true)"
[[ "${CURRENT_BRANCH}" == "${EXPECTED_BRANCH}" ]] ||
    fail "unexpected branch ${CURRENT_BRANCH}; expected ${EXPECTED_BRANCH}"
git merge-base --is-ancestor "${REQUIRED_ANCESTOR}" HEAD ||
    fail "current HEAD does not descend from accepted A14.6 source ${REQUIRED_ANCESTOR}"

xbutil --version > "${RESULT_DIR}/xrt_version.txt" 2>&1 || true
xbutil version >> "${RESULT_DIR}/xrt_version.txt" 2>&1 || true
grep -Fq "${EXPECTED_XRT_VERSION}" "${RESULT_DIR}/xrt_version.txt" ||
    fail "XRT version does not contain frozen ${EXPECTED_XRT_VERSION}"

grep -Fxq "A14_6_VPP_LINK=PASS" "${A14_6_STATUS}" || fail "A14.6 link PASS marker is missing"
grep -Fxq "A14_6_XCLBIN=PASS" "${A14_6_STATUS}" || fail "A14.6 xclbin PASS marker is missing"
grep -Fxq "A14_6_HBM0_LINK_MAPPING=PASS" "${A14_6_STATUS}" || fail "A14.6 HBM[0] mapping PASS marker is missing"
grep -Fxq "A14_6_TARGET_TIMING=PASS" "${A14_6_STATUS}" || fail "A14.6 timing PASS marker is missing"

ACTUAL_XCLBIN_SHA256="$(sha256sum "${XCLBIN}" | awk '{print $1}')"
[[ "${ACTUAL_XCLBIN_SHA256}" == "${EXPECTED_XCLBIN_SHA256}" ]] ||
    fail "accepted A14.6 xclbin SHA256 mismatch: ${ACTUAL_XCLBIN_SHA256}"
METADATA_UUID="$(sed -n 's/^[[:space:]]*UUID (xclbin):[[:space:]]*//p' "${XCLBIN_INFO}" | head -n1 | tr -d '\r')"
[[ "${METADATA_UUID}" == "${EXPECTED_UUID}" ]] || fail "xclbin metadata UUID mismatch: ${METADATA_UUID}"
grep -Fq "${EXPECTED_KERNEL}" "${XCLBIN_INFO}" || fail "expected A14 kernel missing from xclbin info"
grep -Fq "${EXPECTED_INSTANCE}" "${XCLBIN_INFO}" || fail "expected A14 CU missing from xclbin info"

# Build-only gate occurs before any target-device query.
if [[ ! -e "${HOST_BUILD_DIR}" ]]; then
    bash "${HOST_BUILD_SCRIPT}" || fail "A14.7 Host build-only gate failed"
fi
[[ -s "${HOST_BUILD_STATUS}" ]] || fail "A14.7 Host build status missing"
grep -Fxq "A14_7_HOST_XRT_BUILD=PASS" "${HOST_BUILD_STATUS}" || fail "A14.7 Host build PASS missing"
grep -Fxq "A14_7_XRT2020_2_API_PROBE=PASS" "${HOST_BUILD_STATUS}" || fail "A14.7 XRT API probe PASS missing"
grep -Fxq "A14_7_CANONICAL_PAYLOAD=PASS" "${HOST_BUILD_STATUS}" || fail "A14.7 canonical payload PASS missing"
[[ -x "${HOST_BINARY}" ]] || fail "A14.7 Host binary missing/not executable"
[[ -s "${PAYLOAD}" ]] || fail "A14.7 canonical payload missing"
[[ "$(stat -c '%s' "${PAYLOAD}")" == "1024" ]] || fail "A14.7 payload size mismatch"
[[ "$(sha256sum "${PAYLOAD}" | awk '{print $1}')" == "023ad250824def6b538ac40a7f0a9bd457e571136100ab1c1e574769f9061b03" ]] ||
    fail "A14.7 payload SHA256 mismatch"

python3 "${VALIDATOR}" --self-test > "${RESULT_DIR}/validator_self_test.log" 2>&1 ||
    fail "A14.7 offline evidence validator self-test failed"
grep -Fxq "A14_7_TAMPER_REJECTION=PASS" "${RESULT_DIR}/validator_self_test.log" ||
    fail "A14.7 tamper-rejection marker missing"

echo "============================================================"
echo "Stage 2N-A14.7 Protected Physical HBM Single-Table Smoke"
echo "TARGET_INDEX=${TARGET_INDEX}"
echo "TARGET_BDF=${TARGET_BDF}"
echo "TARGET_RENDER=${TARGET_RENDER}"
echo "EXPECTED_UUID=${EXPECTED_UUID}"
echo "EXPECTED_CU=${EXPECTED_CU}"
echo "LOOKUP_INDEX=${LOOKUP_INDEX}"
echo "NO FPGA RESET OR AUTOMATIC ROLLBACK IS PERMITTED"
echo "============================================================"

check_target_mapping
require_empty_render "PRE_DEVICE_STATE"
PRE_QUERY="$(query_target)" || fail "pre-device xbutil query failed"
require_firewall_good "${PRE_QUERY}" "PRE_DEVICE_STATE"
CURRENT_UUID="$(printf '%s\n' "${PRE_QUERY}" | extract_uuid)"
[[ -n "${CURRENT_UUID}" ]] || fail "could not extract current target UUID"
PROGRAMMING_STATUS="SKIPPED_ALREADY_LOADED"
AUTHORIZATION_GIVEN="0"

if [[ "${CURRENT_UUID}" == "${EXPECTED_UUID}" ]]; then
    printf '%s\n' "${PRE_QUERY}" | grep -Fq "${EXPECTED_CU}" || fail "accepted A14.6 UUID loaded but expected CU missing"
    printf '%s\n' "${PRE_QUERY}" | extract_cu_line | grep -Fq "(IDLE)" || fail "accepted A14.6 CU not IDLE"
    require_hbm0_empty "${PRE_QUERY}" "PRE_DEVICE_STATE"
else
    ALLOWED_SOURCE_UUID="${A14_7_ALLOWED_SOURCE_UUID:-}"
    ALLOWED_SOURCE_CU="${A14_7_ALLOWED_SOURCE_CU:-}"
    [[ -n "${ALLOWED_SOURCE_UUID}" && -n "${ALLOWED_SOURCE_CU}" ]] ||
        fail "current UUID ${CURRENT_UUID} is not A14.6; set explicit A14_7_ALLOWED_SOURCE_UUID and A14_7_ALLOWED_SOURCE_CU only after source review"
    [[ "${CURRENT_UUID}" == "${ALLOWED_SOURCE_UUID}" ]] ||
        fail "current UUID ${CURRENT_UUID} does not match explicit source allowlist ${ALLOWED_SOURCE_UUID}"
    printf '%s\n' "${PRE_QUERY}" | grep -Fq "${ALLOWED_SOURCE_CU}" || fail "allowlisted source CU is not visible"
    printf '%s\n' "${PRE_QUERY}" | extract_cu_line | grep -Fq "(IDLE)" || fail "allowlisted source CU is not IDLE"
    require_hbm0_empty "${PRE_QUERY}" "PRE_PROGRAM"
    activity_guard "${ALLOWED_SOURCE_UUID}" "${ALLOWED_SOURCE_CU}"

    confirmation="${A14_7_CONFIRM:-}"
    if [[ -z "${confirmation}" ]]; then
        if [[ ! -t 0 ]]; then
            fail "interactive confirmation unavailable; set A14_7_CONFIRM=yes only after reviewing the locked target/source above"
        fi
        echo "The authorized run is limited to ${TARGET_BDF}: program the accepted A14.6 xclbin, then execute exactly one physical-HBM lookup; no reset/rollback."
        read -r -p "Proceed with the protected A14.7 run? [yes/no] " confirmation
    fi
    if [[ "${confirmation}" != "yes" ]]; then
        echo "A14.7 protected run cancelled safely."
        exit 0
    fi
    AUTHORIZATION_GIVEN="1"

    echo "========== FINAL PRE-PROGRAM RECHECK =========="
    check_target_mapping
    require_empty_render "FINAL_PRE_PROGRAM"
    FINAL_QUERY="$(query_target)" || fail "final pre-program query failed"
    require_firewall_good "${FINAL_QUERY}" "FINAL_PRE_PROGRAM"
    FINAL_UUID="$(printf '%s\n' "${FINAL_QUERY}" | extract_uuid)"
    FINAL_CU_LINE="$(printf '%s\n' "${FINAL_QUERY}" | extract_cu_line)"
    FINAL_DMA_LINES="$(printf '%s\n' "${FINAL_QUERY}" | extract_dma_lines)"
    [[ "${FINAL_UUID}" == "${ALLOWED_SOURCE_UUID}" ]] || fail "source UUID changed before programming"
    [[ "${FINAL_CU_LINE}" == "${GUARD_CU_LINE}" ]] || fail "source CU state changed after guard"
    [[ "${FINAL_DMA_LINES}" == "${GUARD_DMA_LINES}" ]] || fail "DMA counters changed after guard"
    require_hbm0_empty "${FINAL_QUERY}" "FINAL_PRE_PROGRAM"

    echo "========== PROGRAM ACCEPTED A14.6 XCLBIN ON LOCKED BDF =========="
    set +e
    xbutil program -d "${TARGET_BDF}" -p "${XCLBIN}"
    program_result="$?"
    set -e
    [[ "${program_result}" -eq 0 ]] || fail "xbutil program returned ${program_result}"
    PROGRAMMING_STATUS="PASS"
    sleep 3
fi

POST_PROGRAM_QUERY="$(query_target)" || fail "post-program image query failed"
require_firewall_good "${POST_PROGRAM_QUERY}" "POST_PROGRAM"
POST_PROGRAM_UUID="$(printf '%s\n' "${POST_PROGRAM_QUERY}" | extract_uuid)"
POST_PROGRAM_CU="$(printf '%s\n' "${POST_PROGRAM_QUERY}" | extract_cu_line)"
[[ "${POST_PROGRAM_UUID}" == "${EXPECTED_UUID}" ]] || fail "accepted A14.6 UUID not active before Host"
printf '%s\n' "${POST_PROGRAM_CU}" | grep -Fq "${EXPECTED_CU}" || fail "expected A14 CU not visible before Host"
printf '%s\n' "${POST_PROGRAM_CU}" | grep -Fq "(IDLE)" || fail "A14 CU not IDLE before Host"
require_empty_render "PRE_HOST"
require_hbm0_empty "${POST_PROGRAM_QUERY}" "PRE_HOST"
printf '%s\n' "${POST_PROGRAM_QUERY}" > "${PRE_QUERY_FILE}"
PRE_HOST_DMA="$(printf '%s\n' "${POST_PROGRAM_QUERY}" | extract_dma_lines)"
[[ -n "${PRE_HOST_DMA}" ]] || fail "pre-Host DMA counter lines are missing"

# Fresh short guard on the exact A14.6 image immediately before Host.
activity_guard "${EXPECTED_UUID}" "${EXPECTED_CU}"
FINAL_HOST_QUERY="$(query_target)" || fail "final pre-Host query failed"
FINAL_HOST_DMA="$(printf '%s\n' "${FINAL_HOST_QUERY}" | extract_dma_lines)"
FINAL_HOST_CU="$(printf '%s\n' "${FINAL_HOST_QUERY}" | extract_cu_line)"
[[ "$(printf '%s\n' "${FINAL_HOST_QUERY}" | extract_uuid)" == "${EXPECTED_UUID}" ]] || fail "UUID changed before Host"
[[ "${FINAL_HOST_CU}" == "${GUARD_CU_LINE}" ]] || fail "CU state changed before Host"
[[ "${FINAL_HOST_DMA}" == "${GUARD_DMA_LINES}" ]] || fail "DMA counters changed before Host"
require_empty_render "FINAL_PRE_HOST"
require_hbm0_empty "${FINAL_HOST_QUERY}" "FINAL_PRE_HOST"

# If no programming was needed, explicit authorization is still required before
# the first physical-HBM write/Host execution.  A single yes authorizes only
# this one protected lookup on the already locked target.
if [[ "${AUTHORIZATION_GIVEN}" != "1" ]]; then
    confirmation="${A14_7_CONFIRM:-}"
    if [[ -z "${confirmation}" ]]; then
        if [[ ! -t 0 ]]; then
            fail "interactive confirmation unavailable; set A14_7_CONFIRM=yes only after reviewing the locked A14.6 image and final guard"
        fi
        echo "The accepted A14.6 image is already loaded on ${TARGET_BDF}; exactly one physical-HBM lookup will run; no programming/reset/rollback."
        read -r -p "Proceed with the protected A14.7 lookup? [yes/no] " confirmation
    fi
    if [[ "${confirmation}" != "yes" ]]; then
        echo "A14.7 protected lookup cancelled safely."
        exit 0
    fi
    AUTHORIZATION_GIVEN="1"
fi

echo "========== EXECUTE ONE A14.7 PHYSICAL-HBM LOOKUP =========="
set +e
"${HOST_BINARY}" "${PAYLOAD}" "${LOOKUP_INDEX}" > "${HOST_LOG}" 2>&1
host_result="$?"
set -e
cat "${HOST_LOG}"
[[ "${host_result}" -eq 0 ]] || fail "A14.7 Host returned ${host_result}"
grep -Fxq "A14_7_HOST_SMOKE=PASS" "${HOST_LOG}" || fail "Host smoke PASS marker missing"
grep -Fxq "A14_7_RESULT_MATCH=PASS" "${HOST_LOG}" || fail "Host result-match PASS marker missing"
grep -Fxq "A14_7_BO_RELEASED=PASS" "${HOST_LOG}" || fail "Host BO-release PASS marker missing"
grep -Fxq "TARGET_INDEX=${TARGET_INDEX}" "${HOST_LOG}" || fail "Host target index mismatch"
grep -Fxq "TARGET_BDF=${TARGET_BDF}" "${HOST_LOG}" || fail "Host target BDF mismatch"
grep -Fxq "XCLBIN_UUID=${EXPECTED_UUID}" "${HOST_LOG}" || fail "Host xclbin UUID mismatch"
grep -Fxq "IP_INDEX=${EXPECTED_IP_INDEX}" "${HOST_LOG}" || fail "Host IP index mismatch"
grep -Fxq "HBM_MEMORY_INDEX=${EXPECTED_HBM_MEMORY_INDEX}" "${HOST_LOG}" || fail "Host HBM memory index mismatch"
grep -Fxq "PAYLOAD_BYTES=1024" "${HOST_LOG}" || fail "Host payload-size marker mismatch"
grep -Fxq "PAYLOAD_FNV1A64=40a53c3698b88325" "${HOST_LOG}" || fail "Host payload FNV marker mismatch"

echo "========== POST-HOST DEVICE/HBM RELEASE VERIFICATION =========="
POST_HOST_QUERY="$(query_target)" || fail "post-Host xbutil query failed"
printf '%s\n' "${POST_HOST_QUERY}" > "${POST_QUERY_FILE}"
require_firewall_good "${POST_HOST_QUERY}" "POST_HOST"
POST_HOST_UUID="$(printf '%s\n' "${POST_HOST_QUERY}" | extract_uuid)"
POST_HOST_CU="$(printf '%s\n' "${POST_HOST_QUERY}" | extract_cu_line)"
POST_HOST_DMA="$(printf '%s\n' "${POST_HOST_QUERY}" | extract_dma_lines)"
[[ "${POST_HOST_UUID}" == "${EXPECTED_UUID}" ]] || fail "xclbin UUID changed after Host"
printf '%s\n' "${POST_HOST_CU}" | grep -Fq "${EXPECTED_CU}" || fail "A14 CU missing after Host"
printf '%s\n' "${POST_HOST_CU}" | grep -Fq "(IDLE)" || fail "A14 CU not IDLE after Host"
[[ -n "${POST_HOST_DMA}" ]] || fail "post-Host DMA counter lines are missing"
[[ "${POST_HOST_DMA}" != "${FINAL_HOST_DMA}" ]] || fail "DMA counters did not change across Host H2C payload sync"
require_empty_render "POST_HOST"
require_hbm0_empty "${POST_HOST_QUERY}" "POST_HOST"

# Build exactly the frozen 64-line evidence schema.  Values are copied from the
# Host log only after all post-release device-state guards pass.
cat > "${EVIDENCE}" <<EOF
A14_7_FLOW=STAGE2N_A14_7_HBM_SINGLE_TABLE_BOARD_SMOKE_V1
A14_7_HOST_BUILD=PASS
A14_7_HOST_EXECUTION=PASS
A14_7_PHYSICAL_HBM=PASS
A14_7_SINGLE_TABLE_LOOKUP=PASS
A14_7_RESULT_MATCH=PASS
A14_7_BO_RELEASED=PASS
A14_7_HBM0_POST_RELEASE_ZERO=PASS
A14_7_DMA_ACTIVITY_OBSERVED=PASS
A14_7_FPGA_PROGRAMMING=${PROGRAMMING_STATUS}
A14_7_FPGA_RESET=NOT_RUN
A14_7_OTHER_DEVICE_ACCESS=NONE
FAIL_REASON=NONE
GIT_BRANCH=${CURRENT_BRANCH}
GIT_HEAD=${CURRENT_HEAD}
TARGET_INDEX=${TARGET_INDEX}
TARGET_BDF=${TARGET_BDF}
TARGET_RENDER=${TARGET_RENDER}
PLATFORM=${EXPECTED_PLATFORM}
XRT_VERSION=${EXPECTED_XRT_VERSION}
XCLBIN=$(readlink -f "${XCLBIN}")
XCLBIN_SHA256=${ACTUAL_XCLBIN_SHA256}
XCLBIN_UUID=${EXPECTED_UUID}
KERNEL=${EXPECTED_KERNEL}
COMPUTE_UNIT=${EXPECTED_INSTANCE}
IP_NAME=${EXPECTED_CU}
IP_INDEX=${EXPECTED_IP_INDEX}
HBM_BANK=HBM[0]
HBM_MEMORY_INDEX=${EXPECTED_HBM_MEMORY_INDEX}
TABLE_ROWS=64
TABLE_DIM=8
ELEMENT_TYPE=INT16
ROW_BYTES=16
PAYLOAD_BYTES=1024
PAYLOAD_SHA256=023ad250824def6b538ac40a7f0a9bd457e571136100ab1c1e574769f9061b03
PAYLOAD_FNV1A64=40a53c3698b88325
LOOKUP_INDEX=$(host_value LOOKUP_INDEX)
BO_PADDR_HEX=$(host_value BO_PADDR_HEX)
TABLE_BASE_LO_HEX=$(host_value TABLE_BASE_LO_HEX)
TABLE_BASE_HI_HEX=$(host_value TABLE_BASE_HI_HEX)
CONTROL_PRE_START_HEX=$(host_value CONTROL_PRE_START_HEX)
CONTROL_DONE_WORD_HEX=$(host_value CONTROL_DONE_WORD_HEX)
CONTROL_POST_DONE_HEX=$(host_value CONTROL_POST_DONE_HEX)
CONTROL_POLL_COUNT=$(host_value CONTROL_POLL_COUNT)
RESULT0_HEX=$(host_value RESULT0_HEX)
RESULT1_HEX=$(host_value RESULT1_HEX)
RESULT2_HEX=$(host_value RESULT2_HEX)
RESULT3_HEX=$(host_value RESULT3_HEX)
ACTUAL_LANE0=$(host_value ACTUAL_LANE0)
ACTUAL_LANE1=$(host_value ACTUAL_LANE1)
ACTUAL_LANE2=$(host_value ACTUAL_LANE2)
ACTUAL_LANE3=$(host_value ACTUAL_LANE3)
ACTUAL_LANE4=$(host_value ACTUAL_LANE4)
ACTUAL_LANE5=$(host_value ACTUAL_LANE5)
ACTUAL_LANE6=$(host_value ACTUAL_LANE6)
ACTUAL_LANE7=$(host_value ACTUAL_LANE7)
EXPECTED_LANE0=$(host_value EXPECTED_LANE0)
EXPECTED_LANE1=$(host_value EXPECTED_LANE1)
EXPECTED_LANE2=$(host_value EXPECTED_LANE2)
EXPECTED_LANE3=$(host_value EXPECTED_LANE3)
EXPECTED_LANE4=$(host_value EXPECTED_LANE4)
EXPECTED_LANE5=$(host_value EXPECTED_LANE5)
EXPECTED_LANE6=$(host_value EXPECTED_LANE6)
EXPECTED_LANE7=$(host_value EXPECTED_LANE7)
EOF

[[ "$(grep -cve '^$' "${EVIDENCE}")" == "64" ]] || fail "generated evidence is not exactly 64 non-empty lines"
python3 "${VALIDATOR}" --evidence "${EVIDENCE}" > "${VALIDATION_LOG}" 2>&1 || {
    cat "${VALIDATION_LOG}" >&2
    fail "offline A14.7 evidence validation failed"
}
grep -Fxq "A14_7_EVIDENCE_VALIDATION=PASS" "${VALIDATION_LOG}" || fail "evidence PASS marker missing"

echo "============================================================"
echo "STAGE2N_A14_7_HBM_SINGLE_TABLE_BOARD_SMOKE_V1_PASS"
echo "XCLBIN_UUID=${EXPECTED_UUID}"
echo "HBM_BANK=HBM[0]"
echo "LOOKUP_INDEX=${LOOKUP_INDEX}"
echo "PAYLOAD_SHA256=023ad250824def6b538ac40a7f0a9bd457e571136100ab1c1e574769f9061b03"
echo "A14_7_RESULT_MATCH=PASS"
echo "A14_7_HBM0_POST_RELEASE_ZERO=PASS"
echo "A14_7_DMA_ACTIVITY_OBSERVED=PASS"
echo "FPGA_PROGRAMMING=${PROGRAMMING_STATUS}"
echo "FPGA_RESET=NOT_RUN"
echo "EVIDENCE=${EVIDENCE}"
echo "LOG=${LOG}"
echo "============================================================"
