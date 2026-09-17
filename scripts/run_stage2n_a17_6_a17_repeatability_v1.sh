#!/usr/bin/env bash
# A17 process-restart repeatability: 1 warmup + 11 measured execute calls.
# Does not program, reset, or rebuild. Codex does not execute this script.
# Each round is a new process: BO allocate/fill/sync happen again.

set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

EXPECTED_UUID="622c839f-55f4-47c1-92e9-95ee5595ffa4"
EXPECTED_XCLBIN_SHA256="b8d2034906451cc755b6c01a50c94a4b841998c3e2794c6e417dd1ab952e46ae"
EXPECTED_HOST_ELF_SHA256="9ba376589f56d99efca6e42328d347a6539ba1c40bba56d21ab690d87e7f20fc"
EXPECTED_HOST_SOURCE_SHA256="7073b4d976e54f73887c21714a3a4d8bdf65cdf3a272e620fb54c09963ee55ce"
EXECUTE="${REPO_ROOT}/scripts/run_stage2n_a17_6_protected_board_v1.sh"
HOST_BINARY="${REPO_ROOT}/build/stage2n_a17_6/host_v1/stage2n_a17_6_four_bo_host_v1"
HOST_SOURCE="${REPO_ROOT}/host/stage2n_a17_6_four_bo_host_v1.cpp"
XCLBIN="${A17_6_XCLBIN:-${REPO_ROOT}/runs/a17_6_link_004/dlrm_f37x_rtl_kernel_stage2n_a17_v1.xclbin}"

fail()
{
    echo "ERROR: $*" >&2
    echo "A17_6_REPEATABILITY=FAIL" >&2
    echo "FPGA_PROGRAMMING=NOT_RUN" >&2
    exit 10
}

[[ "${A17_6_REPEATABILITY_AUTHORIZED:-no}" == "yes" ]] ||
    fail "set A17_6_REPEATABILITY_AUTHORIZED=yes for this A17-only slice"
[[ "${A17_6_FORCE_NO_PROGRAM:-}" == "yes" ]] ||
    fail "this slice requires A17_6_FORCE_NO_PROGRAM=yes"
[[ "${A17_6_BOARD_EXECUTION_AUTHORIZED:-no}" == "yes" ]] ||
    fail "execute still requires A17_6_BOARD_EXECUTION_AUTHORIZED=yes"
unset A17_6_BUILD_HOST A17_6_ALLOW_HOST_REBUILD || true

export A17_6_EXPECTED_HOST_ELF_SHA256="${EXPECTED_HOST_ELF_SHA256}"
export A17_6_EXPECTED_HOST_SOURCE_SHA256="${EXPECTED_HOST_SOURCE_SHA256}"
export A17_6_XCLBIN="${XCLBIN}"
export A17_6_FORCE_NO_PROGRAM=yes
export A17_6_CONFIRM="${A17_6_CONFIRM:-yes}"

command -v sha256sum >/dev/null
command -v xbutil >/dev/null || fail "xbutil missing; source XRT first"
[[ -x "${EXECUTE}" ]] || fail "protected execute missing"
[[ -x "${HOST_BINARY}" ]] || fail "accepted Host ELF missing; this slice does not rebuild"
[[ -s "${XCLBIN}" ]] || fail "A17 xclbin missing"

elf_sha="$(sha256sum "${HOST_BINARY}" | awk '{print $1}')"
src_sha="$(sha256sum "${HOST_SOURCE}" | awk '{print $1}')"
xcl_sha="$(sha256sum "${XCLBIN}" | awk '{print $1}')"
[[ "${elf_sha}" == "${EXPECTED_HOST_ELF_SHA256}" ]] ||
    fail "Host ELF SHA ${elf_sha} is not the accepted 9ba37658 identity"
[[ "${src_sha}" == "${EXPECTED_HOST_SOURCE_SHA256}" ]] ||
    fail "Host source SHA ${src_sha} is not the accepted 7073b4d9 identity"
[[ "${xcl_sha}" == "${EXPECTED_XCLBIN_SHA256}" ]] ||
    fail "xclbin SHA mismatch"

extract_uuid()
{
    awk '/Xclbin UUID/ {getline; gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0); print; exit}'
}
CURRENT_UUID="$(xbutil query -d "${A17_6_TARGET_BDF}" 2>/dev/null | extract_uuid || true)"
[[ "${CURRENT_UUID}" == "${EXPECTED_UUID}" ]] ||
    fail "resident UUID is ${CURRENT_UUID:-empty}, expected ${EXPECTED_UUID}; no program authorized"

CAMPAIGN_STAMP="$(date +%Y%m%d_%H%M%S)"
CAMPAIGN_DIR="${REPO_ROOT}/results/stage2n_a17_6/repeatability_v1/${CAMPAIGN_STAMP}"
mkdir -p "${CAMPAIGN_DIR}"
ROUNDS="${CAMPAIGN_DIR}/rounds.txt"
{
    echo "A17_6_REPEATABILITY=START"
    echo "KIND=PROCESS_RESTART_NOT_STEADY_STATE"
    echo "WARMUP_ROUNDS=1"
    echo "MEASURED_ROUNDS=11"
    echo "FORCE_NO_PROGRAM=yes"
    echo "EXPECTED_UUID=${EXPECTED_UUID}"
    echo "CURRENT_UUID=${CURRENT_UUID}"
    echo "HOST_EXECUTE_SHA256=${elf_sha}"
    echo "HOST_SOURCE_SHA256=${src_sha}"
    echo "XCLBIN_SHA256=${xcl_sha}"
    echo "PERFORMANCE=NOT_CLAIMED"
    echo "A16_NOT_AUTHORIZED=1"
} | tee "${CAMPAIGN_DIR}/campaign.log"

newest_stamp()
{
    ls -1dt "${REPO_ROOT}/results/stage2n_a17_6/protected_v1"/*/ 2>/dev/null |
        head -1 | xargs -n1 basename
}

: > "${ROUNDS}"
completed=0
for round in $(seq 0 11); do
    if [[ "${round}" -eq 0 ]]; then
        role="WARMUP"
    else
        role="MEASURED"
    fi
    echo "ROUND=${round} ROLE=${role} START" | tee -a "${CAMPAIGN_DIR}/campaign.log"
    sleep 1
    set +e
    bash "${EXECUTE}" execute
    rc=$?
    set -e
    stamp="$(newest_stamp)"
    echo "ROUND=${round} ROLE=${role} STAMP=${stamp} RC=${rc}" | tee -a "${ROUNDS}" "${CAMPAIGN_DIR}/campaign.log"
    if [[ "${rc}" -ne 0 ]]; then
        echo "STOP_ON_FAILURE ROUND=${round} ROLE=${role} STAMP=${stamp}" | tee -a "${CAMPAIGN_DIR}/campaign.log"
        echo "A17_6_REPEATABILITY=STOPPED"
        echo "COMPLETED_ROUNDS=${completed}"
        echo "FAILED_ROUND=${round}"
        echo "KEEP_FAILED_ROUND=YES"
        echo "DO_NOT_EXTRA_RUN=YES"
        exit "${rc}"
    fi
    completed=$((completed + 1))
done

echo "A17_6_REPEATABILITY=PASS_PROCESS_RESTART_SLICE" | tee -a "${CAMPAIGN_DIR}/campaign.log"
echo "COMPLETED_ROUNDS=${completed}"
echo "CAMPAIGN_DIR=${CAMPAIGN_DIR}"
echo "KIND=PROCESS_RESTART_NOT_STEADY_STATE"
echo "PERFORMANCE=NOT_CLAIMED"
echo "A16_NOT_RUN=1"
exit 0
