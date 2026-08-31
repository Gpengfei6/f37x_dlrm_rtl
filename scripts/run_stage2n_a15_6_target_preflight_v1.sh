#!/usr/bin/env bash
# Stage 2N-A15.6 target build/readiness preflight.
# This script is intentionally device-free: it does not query, open, program,
# reset, or execute an FPGA and it does not rebuild XO/xclbin.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

EXPECTED_REPO="/home/chaosuan/gpf/gpf_f37x_dlrm/f37x_dlrm_rtl_stage2n_a15_5_buildonly"
EXPECTED_BRANCH="work/stage2n-a15-hbm-pipeline-integration"
SOURCE_BASELINE="ee3dcaa7f3d90458f3b770318001f3b16d04eccf"
FROZEN_RTL_SHA256="c3da5be63d4cf195df124e572887b6aa96a464522883c6cdc95c4bd56ff4e8a1"
EXPECTED_XCLBIN_SHA256="23ee48c91b3dfb5b68b3372ac49fc6607f203cf01d3b9fcfe04b4ea42be02356"
EXPECTED_UUID="1b555645-a9e2-4f5e-95af-6ce4adacbc3c"
EXPECTED_KERNEL="dlrm_f37x_rtl_kernel_stage2n_a15_v1"
EXPECTED_CU="dlrm_a15_1"
EXPECTED_PLATFORM="inspur_f37x_xdma_201920_3"
EXPECTED_PART="xcvu37p-fsvh2892-2L-e"
EXPECTED_CLOCK_MHZ="100"

VITIS_SETTINGS="${VITIS_SETTINGS:-/opt/Xilinx/Vitis/2020.2/settings64.sh}"
XRT_SETUP="${XRT_SETUP:-/opt/xilinx/xrt/setup.sh}"
XCLBIN="${A15_6_XCLBIN:-${REPO_ROOT}/build/stage2n_a15_5/link_v1/hw/${EXPECTED_KERNEL}.xclbin}"
KERNEL_XML="${A15_6_KERNEL_XML:-${REPO_ROOT}/build/stage2n_a15_5/xo_v1/kernel.xml}"

RTL="${REPO_ROOT}/rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a15_v1.sv"
CONFIG="${REPO_ROOT}/config/stage2n_a15_5_target_v1.cfg"
LINK_SCRIPT="${REPO_ROOT}/scripts/link_stage2n_a15_5_target_v1.sh"
XCLBIN_VALIDATOR="${REPO_ROOT}/scripts/validate_stage2n_a15_5_xclbin_v2.py"
SOURCE_VALIDATOR="${REPO_ROOT}/scripts/validate_stage2n_a15_6_sources_v1.py"
PREFLIGHT_VALIDATOR="${REPO_ROOT}/scripts/validate_stage2n_a15_6_target_preflight_v1.py"
GOLDEN_BUILDER="${REPO_ROOT}/python/build_stage2n_a15_6_board_assets_v1.py"
SOURCE_PACKAGE="${REPO_ROOT}/models/stage2m/stage2m_trained_hybrid_dlrm.f37xhd"
ASSET_ROOT="${REPO_ROOT}/models/stage2n_a15_6"
HOST_BUILD_SCRIPT="${REPO_ROOT}/scripts/build_stage2n_a15_6_host_v1.sh"
HOST_BUILD_DIR="${REPO_ROOT}/build/stage2n_a15_6/host_v1"
HOST_BINARY="${HOST_BUILD_DIR}/stage2n_a15_6_all_hbm_board_validation_v1"
HOST_STATUS="${HOST_BUILD_DIR}/host_build_status.txt"

STAMP="$(date +%Y%m%d_%H%M%S)"
RESULT_ROOT="${REPO_ROOT}/results/stage2n_a15_6/target_preflight_v1/${STAMP}"
STATUS="${RESULT_ROOT}/a15_6_target_preflight_v1_status.txt"
GIT_STATUS_FILE="${RESULT_ROOT}/git_status_porcelain.txt"
TOOL_LOG="${RESULT_ROOT}/tool_versions.log"
SOURCE_LOG="${RESULT_ROOT}/source_validation.log"
PREFLIGHT_SOURCE_LOG="${RESULT_ROOT}/preflight_source_validation.log"
GOLDEN_LOG="${RESULT_ROOT}/golden_regeneration.log"
GOLDEN_STATUS="${RESULT_ROOT}/golden_regeneration_status.txt"
GENERATED_ASSETS="${RESULT_ROOT}/generated_assets"
XCLBIN_INFO="${RESULT_ROOT}/${EXPECTED_KERNEL}.xclbin.info"
CONNECTIVITY_JSON="${RESULT_ROOT}/xclbin_connectivity.json"
MEM_TOPOLOGY_JSON="${RESULT_ROOT}/xclbin_mem_topology.json"
IP_LAYOUT_JSON="${RESULT_ROOT}/xclbin_ip_layout.json"
LINK_CONTRACT="${RESULT_ROOT}/link_contract.txt"
XCLBIN_VALIDATION_LOG="${RESULT_ROOT}/xclbin_metadata_validation_v2.log"
HOST_STATUS_COPY="${RESULT_ROOT}/host_build_status.txt"
SOURCE_HASHES="${RESULT_ROOT}/preflight_sources.sha256"

A15_6_TARGET_PREFLIGHT="NOT_RUN"
A15_6_HOST_BUILD="NOT_RUN"
A15_6_FIXED_XCLBIN_IDENTITY="NOT_RUN"
A15_6_GOLDEN_ASSETS="NOT_RUN"
A15_6_PROTECTION_GATE="NOT_RUN"
FAIL_REASON="NONE"
CURRENT_BRANCH="NOT_RECORDED"
CURRENT_HEAD="NOT_RECORDED"
XCLBIN_UUID="NOT_RECORDED"
HOST_BUILD_MODE="NOT_RUN"
READY_FOR_PROTECTED_BOARD_EXECUTION="NO"

write_status()
{
    cat > "${STATUS}" <<EOF
A15_6_FLOW=TARGET_PREFLIGHT_V1
A15_6_LOCAL_PREPARATION=PASS
A15_6_TARGET_PREFLIGHT=${A15_6_TARGET_PREFLIGHT}
A15_6_HOST_BUILD=${A15_6_HOST_BUILD}
A15_6_FIXED_XCLBIN_IDENTITY=${A15_6_FIXED_XCLBIN_IDENTITY}
A15_6_GOLDEN_ASSETS=${A15_6_GOLDEN_ASSETS}
A15_6_PROTECTION_GATE=${A15_6_PROTECTION_GATE}
A15_6_TARGET_PREFLIGHT_PREPARED=YES
READY_TO_TRANSFER_TO_TARGET=YES
READY_FOR_PROTECTED_BOARD_EXECUTION=${READY_FOR_PROTECTED_BOARD_EXECUTION}
FPGA_PROGRAMMING=NOT_RUN
HOST_EXECUTION=NOT_RUN
PHYSICAL_HBM=NOT_VALIDATED
BOARD_FUNCTIONAL=NOT_RUN
PERFORMANCE=NOT_CLAIMED
FPGA_DEVICE_ACCESS=NONE
SERVER_ACCESS=USER_LOCAL_TARGET_ONLY
NETWORK_ACCESS=NONE_BY_PREFLIGHT
XCLBIN_REBUILT=NO
FAIL_REASON=${FAIL_REASON}
GIT_BRANCH=${CURRENT_BRANCH}
GIT_HEAD=${CURRENT_HEAD}
SOURCE_BASELINE=${SOURCE_BASELINE}
FROZEN_RTL_SHA256=${FROZEN_RTL_SHA256}
KERNEL=${EXPECTED_KERNEL}
COMPUTE_UNIT=${EXPECTED_CU}
PLATFORM_VBNV=${EXPECTED_PLATFORM}
TARGET_PART=${EXPECTED_PART}
REQUESTED_CLOCK_MHZ=${EXPECTED_CLOCK_MHZ}
CONNECTIVITY=${EXPECTED_CU}.m_axi_gmem:HBM[0]
XCLBIN=${XCLBIN}
XCLBIN_SHA256=${EXPECTED_XCLBIN_SHA256}
XCLBIN_UUID=${XCLBIN_UUID}
HOST_BUILD_MODE=${HOST_BUILD_MODE}
RESULT_ROOT=${RESULT_ROOT}
EOF
}

fail()
{
    local code="$1"
    shift
    FAIL_REASON="$*"
    [[ -d "${RESULT_ROOT}" ]] && write_status
    echo "ERROR: ${FAIL_REASON}" >&2
    exit "${code}"
}

unexpected_error()
{
    local code="$?"
    local line="${BASH_LINENO[0]:-UNKNOWN}"
    if [[ "${FAIL_REASON}" == "NONE" ]]; then
        FAIL_REASON="unexpected command failure at line ${line}"
        [[ -d "${RESULT_ROOT}" ]] && write_status
    fi
    exit "${code}"
}

status_value()
{
    local key="$1" file="$2"
    awk -F= -v key="${key}" '$1 == key {sub(/^[^=]*=/, ""); print; exit}' "${file}"
}

[[ "${REPO_ROOT}" == "${EXPECTED_REPO}" ]] || {
    echo "ERROR: run only in the established A15.5 build-only repo: ${EXPECTED_REPO}" >&2
    exit 2
}
[[ ! -e "${RESULT_ROOT}" ]] || {
    echo "ERROR: refusing to overwrite preflight result root: ${RESULT_ROOT}" >&2
    exit 2
}

for required in "${RTL}" "${CONFIG}" "${LINK_SCRIPT}" "${XCLBIN_VALIDATOR}" \
    "${SOURCE_VALIDATOR}" "${PREFLIGHT_VALIDATOR}" "${GOLDEN_BUILDER}" \
    "${SOURCE_PACKAGE}" "${HOST_BUILD_SCRIPT}" "${XCLBIN}" "${KERNEL_XML}" \
    "${VITIS_SETTINGS}" "${XRT_SETUP}"; do
    [[ -s "${required}" ]] || {
        echo "ERROR: required preflight input is missing or empty: ${required}" >&2
        exit 3
    }
done

CURRENT_BRANCH="$(git -C "${REPO_ROOT}" symbolic-ref --short HEAD 2>/dev/null || true)"
CURRENT_HEAD="$(git -C "${REPO_ROOT}" rev-parse HEAD 2>/dev/null || true)"
[[ "${CURRENT_BRANCH}" == "${EXPECTED_BRANCH}" ]] || {
    echo "ERROR: wrong branch: ${CURRENT_BRANCH}" >&2
    exit 4
}
git -C "${REPO_ROOT}" merge-base --is-ancestor "${SOURCE_BASELINE}" HEAD || {
    echo "ERROR: A15.6 source baseline is not an ancestor of HEAD" >&2
    exit 4
}
git -C "${REPO_ROOT}" diff --quiet || {
    echo "ERROR: tracked worktree must be clean" >&2
    exit 4
}
git -C "${REPO_ROOT}" diff --cached --quiet || {
    echo "ERROR: index must be clean" >&2
    exit 4
}
actual_rtl_sha256="$(sha256sum "${RTL}" | awk '{print $1}')"
[[ "${actual_rtl_sha256}" == "${FROZEN_RTL_SHA256}" ]] || {
    echo "ERROR: frozen A15.4 RTL SHA256 mismatch" >&2
    exit 4
}

mkdir -p "${RESULT_ROOT}" "${GENERATED_ASSETS}"
trap unexpected_error ERR
git -C "${REPO_ROOT}" status --porcelain > "${GIT_STATUS_FILE}"
write_status

set +u
# shellcheck disable=SC1090
source "${XRT_SETUP}" >/dev/null
set -u
for tool in git python3 g++ nm sha256sum xclbinutil xbutil awk grep sed \
    stat cmp cp head date hostname; do
    command -v "${tool}" >/dev/null 2>&1 || fail 5 "required tool missing: ${tool}"
done
[[ -n "${XILINX_XRT:-}" ]] || fail 5 "XILINX_XRT is not set"
[[ -f "${XILINX_XRT}/include/xrt.h" ]] || fail 5 "xrt.h is missing"
[[ -f "${XILINX_XRT}/include/experimental/xrt-next.h" ]] ||
    fail 5 "experimental/xrt-next.h is missing"
[[ -e "${XILINX_XRT}/lib/libxrt_core.so" ]] || fail 5 "libxrt_core.so is missing"
{
    echo "HOSTNAME=$(hostname)"
    echo "DATE=$(date -Iseconds)"
    echo "VITIS_SETTINGS=${VITIS_SETTINGS}"
    echo "XRT_SETUP=${XRT_SETUP}"
    g++ --version | head -n 1
    xclbinutil --version
} > "${TOOL_LOG}" 2>&1

python3 "${PREFLIGHT_VALIDATOR}" --repo "${REPO_ROOT}" \
    > "${PREFLIGHT_SOURCE_LOG}" 2>&1 || fail 6 "preflight source validation failed"
grep -Fxq "A15_6_TARGET_PREFLIGHT_SOURCE_VALIDATION=PASS" \
    "${PREFLIGHT_SOURCE_LOG}" || fail 6 "preflight source PASS marker missing"
python3 "${SOURCE_VALIDATOR}" --repo "${REPO_ROOT}" \
    > "${SOURCE_LOG}" 2>&1 || fail 6 "A15.6 source/asset validation failed"
grep -Fxq "A15_6_SOURCE_VALIDATION=PASS" "${SOURCE_LOG}" ||
    fail 6 "A15.6 source PASS marker missing"
A15_6_PROTECTION_GATE="PASS"
write_status

python3 "${GOLDEN_BUILDER}" --source-package "${SOURCE_PACKAGE}" \
    --output-dir "${GENERATED_ASSETS}" --status "${GOLDEN_STATUS}" \
    > "${GOLDEN_LOG}" 2>&1 || fail 7 "deterministic golden regeneration failed"
for asset in \
    stage2n_a15_6_model_v1.bin \
    stage2n_a15_6_cases_v1.json \
    stage2n_a15_6_case0_baseline_table_v1.bin \
    stage2n_a15_6_case1_slot0_sensitivity_table_v1.bin \
    stage2n_a15_6_case2_slot1_sensitivity_table_v1.bin \
    stage2n_a15_6_case3_slot2_sensitivity_table_v1.bin \
    stage2n_a15_6_case4_slot3_sensitivity_table_v1.bin; do
    cmp -s "${GENERATED_ASSETS}/${asset}" "${ASSET_ROOT}/${asset}" ||
        fail 7 "regenerated golden asset differs: ${asset}"
done
grep -Fxq "A15_6_GOLDEN_ASSET_GENERATION=PASS" "${GOLDEN_STATUS}" ||
    fail 7 "golden generation PASS marker missing"
A15_6_GOLDEN_ASSETS="PASS"
write_status

actual_xclbin_sha256="$(sha256sum "${XCLBIN}" | awk '{print $1}')"
[[ "${actual_xclbin_sha256}" == "${EXPECTED_XCLBIN_SHA256}" ]] ||
    fail 8 "fixed xclbin SHA256 mismatch"
xclbinutil --quiet --force --info "${XCLBIN_INFO}" --input "${XCLBIN}" ||
    fail 8 "xclbin info extraction failed"
xclbinutil --quiet --force --dump-section \
    "CONNECTIVITY:JSON:${CONNECTIVITY_JSON}" --input "${XCLBIN}" ||
    fail 8 "CONNECTIVITY extraction failed"
xclbinutil --quiet --force --dump-section \
    "MEM_TOPOLOGY:JSON:${MEM_TOPOLOGY_JSON}" --input "${XCLBIN}" ||
    fail 8 "MEM_TOPOLOGY extraction failed"
xclbinutil --quiet --force --dump-section \
    "IP_LAYOUT:JSON:${IP_LAYOUT_JSON}" --input "${XCLBIN}" ||
    fail 8 "IP_LAYOUT extraction failed"
cat > "${LINK_CONTRACT}" <<EOF
KERNEL=${EXPECTED_KERNEL}
COMPUTE_UNIT=${EXPECTED_CU}
PLATFORM_VBNV=${EXPECTED_PLATFORM}
TARGET_PART=${EXPECTED_PART}
KERNEL_FREQUENCY_MHZ=${EXPECTED_CLOCK_MHZ}
CONNECTIVITY=${EXPECTED_CU}.m_axi_gmem:HBM[0]
M_AXI_MASTER_COUNT=1
EOF
python3 "${XCLBIN_VALIDATOR}" \
    --connectivity "${CONNECTIVITY_JSON}" \
    --mem-topology "${MEM_TOPOLOGY_JSON}" \
    --ip-layout "${IP_LAYOUT_JSON}" \
    --xclbin-info "${XCLBIN_INFO}" \
    --config "${CONFIG}" \
    --link-script "${LINK_SCRIPT}" \
    --link-contract "${LINK_CONTRACT}" \
    --kernel-xml "${KERNEL_XML}" \
    --kernel "${EXPECTED_KERNEL}" \
    --compute-unit "${EXPECTED_CU}" \
    --platform "${EXPECTED_PLATFORM}" \
    --part "${EXPECTED_PART}" \
    --clock-mhz "${EXPECTED_CLOCK_MHZ}" > "${XCLBIN_VALIDATION_LOG}" 2>&1 ||
    fail 8 "fixed xclbin metadata validation failed"
grep -Fxq "A15_5_XCLBIN_METADATA_VALIDATION_V2=PASS" \
    "${XCLBIN_VALIDATION_LOG}" || fail 8 "xclbin metadata PASS marker missing"
XCLBIN_UUID="$(status_value XCLBIN_UUID "${XCLBIN_VALIDATION_LOG}")"
[[ "${XCLBIN_UUID}" == "${EXPECTED_UUID}" ]] || fail 8 "fixed xclbin UUID mismatch"
A15_6_FIXED_XCLBIN_IDENTITY="PASS"
write_status

if [[ -e "${HOST_BUILD_DIR}" ]]; then
    [[ -s "${HOST_STATUS}" && -x "${HOST_BINARY}" ]] ||
        fail 9 "existing Host build is incomplete"
    grep -Fxq "A15_6_HOST_XRT_BUILD=PASS" "${HOST_STATUS}" ||
        fail 9 "existing Host build lacks PASS marker"
    source_sha="$(sha256sum "${REPO_ROOT}/host/stage2n_a15_6_all_hbm_board_validation_v1.cpp" | awk '{print $1}')"
    [[ "$(status_value SOURCE_SHA256 "${HOST_STATUS}")" == "${source_sha}" ]] ||
        fail 9 "existing Host binary was built from another source"
    binary_sha="$(sha256sum "${HOST_BINARY}" | awk '{print $1}')"
    [[ "$(status_value BINARY_SHA256 "${HOST_STATUS}")" == "${binary_sha}" ]] ||
        fail 9 "existing Host binary SHA256 mismatch"
    HOST_BUILD_MODE="REUSED_VALIDATED"
else
    bash "${HOST_BUILD_SCRIPT}" || fail 9 "A15.6 target Host build failed"
    [[ -s "${HOST_STATUS}" && -x "${HOST_BINARY}" ]] ||
        fail 9 "Host build completed without retained binary/status"
    grep -Fxq "A15_6_HOST_XRT_BUILD=PASS" "${HOST_STATUS}" ||
        fail 9 "Host build PASS marker missing"
    HOST_BUILD_MODE="BUILT"
fi
cp "${HOST_STATUS}" "${HOST_STATUS_COPY}"
A15_6_HOST_BUILD="PASS"

sha256sum "${RTL}" "${PREFLIGHT_VALIDATOR}" "${SOURCE_VALIDATOR}" \
    "${GOLDEN_BUILDER}" "${HOST_BUILD_SCRIPT}" "${BASH_SOURCE[0]}" \
    > "${SOURCE_HASHES}"
A15_6_TARGET_PREFLIGHT="PASS"
READY_FOR_PROTECTED_BOARD_EXECUTION="YES"
write_status

echo "A15_6_TARGET_PREFLIGHT=PASS"
echo "A15_6_HOST_BUILD=PASS"
echo "A15_6_FIXED_XCLBIN_IDENTITY=PASS"
echo "A15_6_GOLDEN_ASSETS=PASS"
echo "A15_6_PROTECTION_GATE=PASS"
echo "A15_6_TARGET_PREFLIGHT_PREPARED=YES"
echo "READY_TO_TRANSFER_TO_TARGET=YES"
echo "READY_FOR_PROTECTED_BOARD_EXECUTION=YES"
echo "FPGA_PROGRAMMING=NOT_RUN"
echo "HOST_EXECUTION=NOT_RUN"
echo "PHYSICAL_HBM=NOT_VALIDATED"
echo "BOARD_FUNCTIONAL=NOT_RUN"
echo "PERFORMANCE=NOT_CLAIMED"
echo "FPGA_DEVICE_ACCESS=NONE"
echo "XCLBIN_REBUILT=NO"
echo "STATUS=${STATUS}"
