#!/usr/bin/env bash
# A16.2 process-restart repeatability.
# prepare: print frozen identities; no device.
# execute: wrap the frozen A16 protected runner 12 times. Codex does not
# run execute. Do not bypass scripts/program_and_run_stage2n_a16_2_physical_latency_v1.sh.

set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

ACTION="${1:-prepare}"
EXPECTED_UUID="f18571de-4a43-46bd-8ab9-a89dd4b11f8e"
EXPECTED_XCLBIN_SHA256="5f0d6fefab1549d2e1969df3d8775409bbfac33cb46d07e7abde99abdf04b8b4"
EXPECTED_HOST_ELF_SHA256="de0abefc0b4dbadf74dd69e6875db9051a18ab34d8ab1a6a747073cb436d6f1b"
EXPECTED_HOST_SOURCE_SHA256="d2c4036bcaccba702d70fe772a436501568c593dd5b92bc08edb7d7502dafc99"
EXPECTED_FROZEN_EXECUTE_SHA256="8370ec2f6128243a5f15e7a83a8c0c432b2cde6bf959504769d71323dc31c3ba"
EXPECTED_SOURCE_UUID="622c839f-55f4-47c1-92e9-95ee5595ffa4"
EXPECTED_SOURCE_CU="dlrm_f37x_rtl_kernel_stage2n_a17_v1:dlrm_a17_1"
EXPECTED_KERNEL="dlrm_f37x_rtl_kernel_stage2n_a16_v1"
EXPECTED_INSTANCE="dlrm_a16_1"
EXECUTE="${REPO_ROOT}/scripts/program_and_run_stage2n_a16_2_physical_latency_v1.sh"
HOST_BINARY="${REPO_ROOT}/build/stage2n_a16_2/host_v1/stage2n_a16_2_physical_latency_v1"
HOST_SOURCE="${REPO_ROOT}/host/stage2n_a16_2_physical_latency_v1.cpp"
HOST_BUILD_STATUS="${REPO_ROOT}/build/stage2n_a16_2/host_v1/host_build_status.txt"
DEFAULT_XCLBIN="${REPO_ROOT}/build/stage2n_a16_2/link_v1/hw/dlrm_f37x_rtl_kernel_stage2n_a16_v1.xclbin"
XCLBIN="${A16_2_XCLBIN:-${DEFAULT_XCLBIN}}"
REJECTED_A17_HOST="${REPO_ROOT}/build/stage2n_a17_6/host_v1/stage2n_a17_6_four_bo_host_v1"

fail()
{
    echo "ERROR: $*" >&2
    echo "A16_2_REPEATABILITY=FAIL" >&2
    echo "A16_2_PROGRAM=NOT_RUN" >&2
    echo "FPGA_RESET=NOT_RUN" >&2
    echo "PERFORMANCE=NOT_CLAIMED" >&2
    echo "A16_A17_SPEEDUP=NOT_COMPUTED" >&2
    echo "DO_NOT_EXTRA_RUN=YES" >&2
    exit 10
}

print_identities()
{
    echo "KIND=PROCESS_RESTART_NOT_STEADY_STATE"
    echo "WARMUP_ROUNDS=1"
    echo "MEASURED_ROUNDS=11"
    echo "CASE_ORDER=CASE0,CASE1,CASE2,CASE3,CASE4"
    echo "REPEAT_BASELINE=ABSENT_ON_FROZEN_A16_HOST"
    echo "BO_INIT=one_HBM0_BO_reload_full_image_each_case"
    echo "LOOKUP_START_A=first_AR_on_single_m_axi_gmem"
    echo "EXPECTED_UUID=${EXPECTED_UUID}"
    echo "EXPECTED_XCLBIN_SHA256=${EXPECTED_XCLBIN_SHA256}"
    echo "EXPECTED_HOST_ELF_SHA256=${EXPECTED_HOST_ELF_SHA256}"
    echo "EXPECTED_HOST_SOURCE_SHA256=${EXPECTED_HOST_SOURCE_SHA256}"
    echo "EXPECTED_FROZEN_EXECUTE_SHA256=${EXPECTED_FROZEN_EXECUTE_SHA256}"
    echo "ALLOWED_SOURCE_UUID=${EXPECTED_SOURCE_UUID}"
    echo "ALLOWED_SOURCE_CU=${EXPECTED_SOURCE_CU}"
    echo "KERNEL=${EXPECTED_KERNEL}"
    echo "CU=${EXPECTED_INSTANCE}"
    echo "FROZEN_EXECUTE=scripts/program_and_run_stage2n_a16_2_physical_latency_v1.sh"
    echo "TARGET_TREE=/home/chaosuan/gpf/gpf_f37x_dlrm/f37x_dlrm_rtl_stage2n_a16_2_buildonly"
    echo "PERFORMANCE=NOT_CLAIMED"
    echo "A16_A17_SPEEDUP=NOT_COMPUTED"
    echo "A17_RESTORE_PROGRAM=NOT_AUTHORIZED"
}

if [[ "${ACTION}" == "prepare" ]]; then
    echo "A16_2_REPEATABILITY=PREPARE_ONLY"
    print_identities
    echo "A16_2_PROGRAM=NOT_RUN"
    echo "BOARD=NOT_RUN"
    echo "NOTE=execute wraps the frozen A16 protected runner; do not bypass it"
    echo "NOTE=do not run from the A17.6 overlay tree"
    exit 0
fi
[[ "${ACTION}" == "execute" ]] || fail "usage: ${0} prepare|execute"

[[ "${REPO_ROOT}" != *a17_6_buildonly* ]] ||
    fail "refuse A17 overlay tree: ${REPO_ROOT}"
[[ ! -e "${REJECTED_A17_HOST}" ]] ||
    echo "NOTE=A17 Host path exists nearby but will not be executed"

[[ "${A16_2_REPEATABILITY_AUTHORIZED:-no}" == "yes" ]] ||
    fail "set A16_2_REPEATABILITY_AUTHORIZED=yes after review"
[[ "${A16_2_PROGRAM_AUTHORIZED:-no}" == "yes" ]] ||
    fail "bitstream switch needs A16_2_PROGRAM_AUTHORIZED=yes"
[[ "${A16_2_PROGRAM_DESTINATION_UUID:-}" == "${EXPECTED_UUID}" ]] ||
    fail "name destination UUID ${EXPECTED_UUID} exactly"
[[ "${A16_2_BOARD_EXECUTION_AUTHORIZED:-no}" == "yes" ]] ||
    fail "set A16_2_BOARD_EXECUTION_AUTHORIZED=yes"
[[ -n "${A16_2_TARGET_INDEX:-}" && "${A16_2_TARGET_INDEX}" =~ ^[0-9]+$ ]] ||
    fail "set A16_2_TARGET_INDEX explicitly"
[[ -n "${A16_2_TARGET_BDF:-}" ]] || fail "set A16_2_TARGET_BDF explicitly"
[[ -n "${A16_2_TARGET_RENDER:-}" ]] || fail "set A16_2_TARGET_RENDER explicitly"

command -v sha256sum >/dev/null || fail "sha256sum missing"
command -v xbutil >/dev/null || fail "xbutil missing; source XRT first"
[[ -f "${EXECUTE}" && -s "${EXECUTE}" ]] ||
    fail "frozen A16 protected execute missing: ${EXECUTE}"
[[ -x "${HOST_BINARY}" ]] || fail "frozen A16 Host ELF missing; this slice does not rebuild"
[[ -s "${HOST_SOURCE}" ]] || fail "frozen A16 Host source missing"
[[ -s "${HOST_BUILD_STATUS}" ]] || fail "Host build record missing"
[[ "${XCLBIN}" != *"/build/stage2n_a16_v1/"* ]] ||
    fail "A16_2_XCLBIN uses stale build/stage2n_a16_v1; use ${DEFAULT_XCLBIN}"
[[ -s "${XCLBIN}" ]] ||
    fail "frozen A16.2 xclbin missing at ${XCLBIN}; expected ${DEFAULT_XCLBIN}"

exec_sha="$(sha256sum "${EXECUTE}" | awk '{print $1}')"
elf_sha="$(sha256sum "${HOST_BINARY}" | awk '{print $1}')"
src_sha="$(sha256sum "${HOST_SOURCE}" | awk '{print $1}')"
xcl_sha="$(sha256sum "${XCLBIN}" | awk '{print $1}')"
record_elf="$(awk -F= '/^BINARY_SHA256=/{print $2}' "${HOST_BUILD_STATUS}" | tail -1)"
record_src="$(awk -F= '/^SOURCE_SHA256=/{print $2}' "${HOST_BUILD_STATUS}" | tail -1)"
[[ "${exec_sha}" == "${EXPECTED_FROZEN_EXECUTE_SHA256}" ]] ||
    fail "frozen execute SHA ${exec_sha} is not 8370ec2f6128243a5f15e7a83a8c0c432b2cde6bf959504769d71323dc31c3ba"
[[ "${elf_sha}" == "${EXPECTED_HOST_ELF_SHA256}" ]] ||
    fail "Host ELF SHA ${elf_sha} is not de0abefc0b4dbadf74dd69e6875db9051a18ab34d8ab1a6a747073cb436d6f1b"
[[ "${src_sha}" == "${EXPECTED_HOST_SOURCE_SHA256}" ]] ||
    fail "Host source SHA ${src_sha} is not d2c4036bcaccba702d70fe772a436501568c593dd5b92bc08edb7d7502dafc99"
[[ "${xcl_sha}" == "${EXPECTED_XCLBIN_SHA256}" ]] ||
    fail "xclbin SHA ${xcl_sha} is not 5f0d6fefab1549d2e1969df3d8775409bbfac33cb46d07e7abde99abdf04b8b4"
[[ "${record_elf}" == "${EXPECTED_HOST_ELF_SHA256}" ]] ||
    fail "build-record BINARY_SHA256 ${record_elf} does not match frozen ELF"
[[ "${record_src}" == "${EXPECTED_HOST_SOURCE_SHA256}" ]] ||
    fail "build-record SOURCE_SHA256 ${record_src} does not match frozen source"
grep -Fxq "A16_2_HOST_XRT_BUILD=PASS" "${HOST_BUILD_STATUS}" ||
    fail "Host build record PASS missing"
echo "HOST_IDENTITY_CHECKED_BEFORE_PROGRAM=YES"
echo "HOST_EXECUTE_PATH=${HOST_BINARY}"
echo "HOST_EXECUTE_SHA256=${elf_sha}"
echo "HOST_SOURCE_SHA256=${src_sha}"
echo "HOST_BUILD_RECORD_ELF_SHA256=${record_elf}"
echo "HOST_BUILD_RECORD_SOURCE_SHA256=${record_src}"
echo "FROZEN_EXECUTE_SHA256=${exec_sha}"
echo "XCLBIN_SHA256=${xcl_sha}"

extract_uuid()
{
    awk '/Xclbin UUID/ {getline; gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0); print; exit}'
}
CURRENT_UUID="$(xbutil query -d "${A16_2_TARGET_BDF}" 2>/dev/null | extract_uuid || true)"
echo "CURRENT_UUID=${CURRENT_UUID:-empty}"
if [[ "${CURRENT_UUID}" == "${EXPECTED_UUID}" ]]; then
    echo "A16_2_PROGRAM_PLAN=SKIP_ALREADY_A16"
elif [[ "${CURRENT_UUID}" == "${EXPECTED_SOURCE_UUID}" ]]; then
    echo "A16_2_PROGRAM_PLAN=ONCE_FROM_ALLOWLISTED_A17"
else
    fail "resident UUID is ${CURRENT_UUID:-empty}; expected ${EXPECTED_UUID} or allowlisted ${EXPECTED_SOURCE_UUID}"
fi

export A16_2_EXPECTED_XCLBIN_SHA256="${EXPECTED_XCLBIN_SHA256}"
export A16_2_EXPECTED_UUID="${EXPECTED_UUID}"
export A16_2_XCLBIN="${XCLBIN}"
export A16_2_CONFIRM="${A16_2_CONFIRM:-yes}"
export A16_2_ALLOWED_SOURCE_UUID="${EXPECTED_SOURCE_UUID}"
export A16_2_ALLOWED_SOURCE_CU="${EXPECTED_SOURCE_CU}"
export A16_2_TARGET_INDEX A16_2_TARGET_BDF A16_2_TARGET_RENDER

CAMPAIGN_STAMP="$(date +%Y%m%d_%H%M%S)"
CAMPAIGN_DIR="${REPO_ROOT}/results/stage2n_a16_2/repeatability_v1/${CAMPAIGN_STAMP}"
mkdir -p "${CAMPAIGN_DIR}"
ROUNDS="${CAMPAIGN_DIR}/rounds.txt"
{
    echo "A16_2_REPEATABILITY=START"
    print_identities
    echo "CURRENT_UUID=${CURRENT_UUID}"
    echo "HOST_EXECUTE_SHA256=${elf_sha}"
    echo "HOST_SOURCE_SHA256=${src_sha}"
    echo "XCLBIN_SHA256=${xcl_sha}"
    echo "HOST_IDENTITY_CHECKED_BEFORE_PROGRAM=YES"
    echo "WRAPS_FROZEN_EXECUTE=YES"
} | tee "${CAMPAIGN_DIR}/campaign.log"

newest_stamp()
{
    ls -1dt "${REPO_ROOT}/results/stage2n_a16_2/physical_latency_v1"/*/ 2>/dev/null |
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
    bash "${EXECUTE}"
    rc=$?
    set -e
    stamp="$(newest_stamp)"
    echo "ROUND=${round} ROLE=${role} STAMP=${stamp} RC=${rc}" | tee -a "${ROUNDS}" "${CAMPAIGN_DIR}/campaign.log"
    if [[ "${rc}" -ne 0 ]]; then
        echo "STOP_ON_FAILURE ROUND=${round} ROLE=${role} STAMP=${stamp}" | tee -a "${CAMPAIGN_DIR}/campaign.log"
        echo "A16_2_REPEATABILITY=STOPPED"
        echo "COMPLETED_ROUNDS=${completed}"
        echo "FAILED_ROUND=${round}"
        echo "KEEP_FAILED_ROUND=YES"
        echo "DO_NOT_EXTRA_RUN=YES"
        echo "FPGA_RESET=NOT_RUN"
        echo "A17_RESTORE_PROGRAM=NOT_AUTHORIZED"
        exit "${rc}"
    fi
    completed=$((completed + 1))
done

echo "A16_2_REPEATABILITY=PASS_PROCESS_RESTART_SLICE" | tee -a "${CAMPAIGN_DIR}/campaign.log"
echo "COMPLETED_ROUNDS=${completed}"
echo "CAMPAIGN_DIR=${CAMPAIGN_DIR}"
echo "KIND=PROCESS_RESTART_NOT_STEADY_STATE"
echo "REPEAT_BASELINE=ABSENT_ON_FROZEN_A16_HOST"
echo "PERFORMANCE=NOT_CLAIMED"
echo "A16_A17_SPEEDUP=NOT_COMPUTED"
echo "A17_RESTORE_PROGRAM=NOT_AUTHORIZED"
exit 0
