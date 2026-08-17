#!/usr/bin/env bash
#
# Stage 2N-A7 integrated AXI-Lite kernel/pipeline regression v1.
#
# Simulation only: no XO/xclbin build, no board programming/reset, and no
# render-node access.
#

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

VIVADO_SETTINGS="${VIVADO_SETTINGS:-/opt/Xilinx/Vivado/2020.2/settings64.sh}"
EXPECTED_BRANCH="work/stage2n-a7-kernel-pipeline"
EXPECTED_HEAD="a73e04587b184edf975205fdc3de35c254f55384"

WORK_DIR="${REPO_ROOT}/work/stage2n_a7_kernel_pipeline_xsim_v1"
LOG_DIR="${REPO_ROOT}/logs"
RESULT_DIR="${REPO_ROOT}/results/stage2n_a7"
STATUS_FILE="${RESULT_DIR}/stage2n_a7_kernel_pipeline_xsim_v1_status.txt"
XVLOG_LOG="${LOG_DIR}/xvlog_stage2n_a7_kernel_pipeline_v1.log"
XELAB_LOG="${LOG_DIR}/xelab_stage2n_a7_kernel_pipeline_v1.log"
XSIM_LOG="${LOG_DIR}/xsim_stage2n_a7_kernel_pipeline_v1.log"

TOP_MODULE="tb_dlrm_f37x_rtl_kernel_stage2n_a7"
SNAPSHOT="tb_dlrm_f37x_rtl_kernel_stage2n_a7_v1_sim"

fail()
{
    echo "ERROR: $*" >&2
    exit 10
}

[[ -f "${VIVADO_SETTINGS}" ]] ||
    fail "Vivado settings not found: ${VIVADO_SETTINGS}"

# shellcheck disable=SC1090
source "${VIVADO_SETTINGS}" >/dev/null

for tool in xvlog xelab xsim; do
    command -v "${tool}" >/dev/null 2>&1 ||
        fail "${tool} is not available"
done

CURRENT_BRANCH="$(
    cd "${REPO_ROOT}" &&
    git symbolic-ref --short HEAD 2>/dev/null || echo DETACHED
)"
CURRENT_HEAD="$(
    cd "${REPO_ROOT}" &&
    git rev-parse HEAD
)"

[[ "${CURRENT_BRANCH}" == "${EXPECTED_BRANCH}" ]] ||
    fail "wrong branch: ${CURRENT_BRANCH}; expected ${EXPECTED_BRANCH}"
[[ "${CURRENT_HEAD}" == "${EXPECTED_HEAD}" ]] ||
    fail "wrong baseline HEAD: ${CURRENT_HEAD}; expected ${EXPECTED_HEAD}"

SOURCES=(
    "${REPO_ROOT}/rtl/common/rv_fifo.sv"
    "${REPO_ROOT}/rtl/common/runtime_relu_quant.sv"
    "${REPO_ROOT}/rtl/compute/mac_lane.sv"
    "${REPO_ROOT}/rtl/memory/banked_activation_buffer.sv"
    "${REPO_ROOT}/rtl/memory/local_weight_provider.sv"
    "${REPO_ROOT}/rtl/compute/vector_dot_product_core.sv"
    "${REPO_ROOT}/rtl/compute/dense_layer_engine.sv"
    "${REPO_ROOT}/rtl/control/mlp_sequence_controller.sv"
    "${REPO_ROOT}/rtl/top/dlrm_f37x_rtl_kernel.sv"
    "${REPO_ROOT}/rtl/interaction/dlrm_feature_interaction_engine.sv"
    "${REPO_ROOT}/rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a2.sv"
    "${REPO_ROOT}/rtl/control/mlp_sequence_controller_segmented.sv"
    "${REPO_ROOT}/rtl/pipeline/dlrm_internal_pipeline_controller.sv"
    "${REPO_ROOT}/rtl/f37x/dlrm_internal_pipeline_axi_lite_adapter_stage2n_a7.sv"
    "${REPO_ROOT}/rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a7.sv"
    "${REPO_ROOT}/tb/tb_dlrm_f37x_rtl_kernel_stage2n_a7.sv"
)

for source_file in "${SOURCES[@]}"; do
    [[ -f "${source_file}" ]] ||
        fail "source is missing: ${source_file}"
done

rm -rf "${WORK_DIR}"
mkdir -p "${WORK_DIR}" "${LOG_DIR}" "${RESULT_DIR}"
rm -f "${STATUS_FILE}" "${XVLOG_LOG}" "${XELAB_LOG}" "${XSIM_LOG}"

{
    echo "============================================================"
    echo "Stage 2N-A7 integrated kernel/pipeline XSim v1"
    echo "TIME=$(date -Is)"
    echo "REPO=${REPO_ROOT}"
    echo "BRANCH=${CURRENT_BRANCH}"
    echo "HEAD=${CURRENT_HEAD}"
    echo "TOP=${TOP_MODULE}"
    echo "WORK=${WORK_DIR}"
    echo "LEGACY_MLP_WINDOW=0x000-0x0FF"
    echo "STANDALONE_INTERACTION_WINDOW=0x100-0x13F"
    echo "AUTOMATIC_PIPELINE_WINDOW=0x180-0x217"
    echo "NO XO/XCLBIN BUILD"
    echo "NO FPGA PROGRAMMING OR RESET"
    echo "============================================================"
    echo "========== SOURCE ORDER =========="
    printf '%s\n' "${SOURCES[@]}"
    echo "============================================================"
} | tee "${LOG_DIR}/stage2n_a7_kernel_pipeline_v1_preamble.log"

cd "${WORK_DIR}"

xvlog --sv "${SOURCES[@]}" 2>&1 | tee "${XVLOG_LOG}"

xelab \
    "${TOP_MODULE}" \
    -s "${SNAPSHOT}" \
    --timescale 1ns/1ps \
    2>&1 | tee "${XELAB_LOG}"

xsim "${SNAPSHOT}" -runall 2>&1 | tee "${XSIM_LOG}"

PASS_MARKER="tb_dlrm_f37x_rtl_kernel_stage2n_a7: PASS runs=2 final=-60 legacy_windows=2"

grep -qF "${PASS_MARKER}" "${XSIM_LOG}" ||
    fail "Stage 2N-A7 PASS marker is missing"

if grep -E '^(ERROR:|FATAL:)' \
    "${XVLOG_LOG}" "${XELAB_LOG}" "${XSIM_LOG}"
then
    fail "Stage 2N-A7 logs contain anchored errors"
fi

{
    echo "STAGE2N_A7_KERNEL_PIPELINE_XSIM_V1_PASS"
    echo "TIME=$(date -Is)"
    echo "BRANCH=${CURRENT_BRANCH}"
    echo "HEAD=${CURRENT_HEAD}"
    echo "TOP=${TOP_MODULE}"
    echo "LEGACY_MLP_VERSION=0x00024701"
    echo "INTERACTION_VERSION=0x00024E02"
    echo "PIPELINE_VERSION=0x00024E07"
    echo "PIPELINE_REGISTER_BASE=0x180"
    echo "PIPELINE_REGISTER_END=0x217"
    echo "PIPELINE_START_COMMANDS=2"
    echo "BOTTOM_OUTPUTS=8"
    echo "INTERACTION_OUTPUTS=18"
    echo "FINAL_RESULT=-60"
    echo "FINAL_BACKPRESSURE_CYCLES=12"
    echo "OLD_MLP_WINDOW_PRESERVED=1"
    echo "OLD_INTERACTION_WINDOW_PRESERVED=1"
    echo "ONE_START_RUNS_FULL_PIPELINE=1"
    echo "NO_EXISTING_RTL_REPLACED=1"
    echo "ADAPTER_SHA256=$(sha256sum "${SOURCES[13]}" | awk '{print $1}')"
    echo "A7_TOP_SHA256=$(sha256sum "${SOURCES[14]}" | awk '{print $1}')"
    echo "A7_TB_SHA256=$(sha256sum "${SOURCES[15]}" | awk '{print $1}')"
    echo "RUNNER_SHA256=$(sha256sum "${REPO_ROOT}/scripts/run_stage2n_a7_kernel_pipeline_xsim_v1.sh" | awk '{print $1}')"
    echo "LOG=${XSIM_LOG}"
    echo "NO_XO_OR_XCLBIN_BUILD=1"
    echo "NO_FPGA_PROGRAMMING_OR_RESET=1"
} > "${STATUS_FILE}"

echo
echo "============================================================"
echo "STAGE2N_A7_KERNEL_PIPELINE_XSIM_V1_PASS"
echo "STATUS=${STATUS_FILE}"
echo "LOG=${XSIM_LOG}"
echo "NO XO/XCLBIN BUILD"
echo "NO FPGA PROGRAMMING OR RESET"
echo "============================================================"
