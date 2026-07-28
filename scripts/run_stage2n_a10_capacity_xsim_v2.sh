#!/usr/bin/env bash
#
# Stage 2N-A10 capacity-expanded automatic-pipeline XSim regression v2.
#
# Simulation only:
#   no XO/xclbin build;
#   no board access;
#   no FPGA programming or reset.
#

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

VIVADO_SETTINGS="${VIVADO_SETTINGS:-/opt/Xilinx/Vivado/2020.2/settings64.sh}"
EXPECTED_BRANCH="work/stage2n-a10-model-batch-regression"

WORK_DIR="${REPO_ROOT}/work/stage2n_a10_capacity_xsim_v2"
LOG_DIR="${REPO_ROOT}/logs"
RESULT_DIR="${REPO_ROOT}/results/stage2n_a10"
STATUS_FILE="${RESULT_DIR}/stage2n_a10_capacity_xsim_v2_status.txt"
XVLOG_LOG="${LOG_DIR}/xvlog_stage2n_a10_capacity_v2.log"
XELAB_LOG="${LOG_DIR}/xelab_stage2n_a10_capacity_v2.log"
XSIM_LOG="${LOG_DIR}/xsim_stage2n_a10_capacity_v2.log"

TOP_MODULE="tb_dlrm_f37x_rtl_kernel_stage2n_a10_capacity_v2"
SNAPSHOT="tb_dlrm_f37x_rtl_kernel_stage2n_a10_capacity_v2_sim"

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
    git symbolic-ref --short HEAD 2>/dev/null ||
        echo DETACHED
)"
CURRENT_HEAD="$(
    cd "${REPO_ROOT}" &&
    git rev-parse HEAD
)"

[[ "${CURRENT_BRANCH}" == "${EXPECTED_BRANCH}" ]] ||
    fail "wrong branch: ${CURRENT_BRANCH}; expected ${EXPECTED_BRANCH}"

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
    "${REPO_ROOT}/rtl/f37x/dlrm_internal_pipeline_axi_lite_adapter_stage2n_a10_v2.sv"
    "${REPO_ROOT}/rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a10_v2.sv"
    "${REPO_ROOT}/tb/tb_dlrm_f37x_rtl_kernel_stage2n_a10_capacity_v2.sv"
)

for source_file in "${SOURCES[@]}"; do
    [[ -s "${source_file}" ]] ||
        fail "source is missing or empty: ${source_file}"
done

rm -rf "${WORK_DIR}"
mkdir -p "${WORK_DIR}" "${LOG_DIR}" "${RESULT_DIR}"
rm -f "${STATUS_FILE}" "${XVLOG_LOG}" "${XELAB_LOG}" "${XSIM_LOG}"

{
    echo "============================================================"
    echo "Stage 2N-A10 capacity-expanded pipeline XSim v1"
    echo "TIME=$(date -Is)"
    echo "REPO=${REPO_ROOT}"
    echo "BRANCH=${CURRENT_BRANCH}"
    echo "HEAD=${CURRENT_HEAD}"
    echo "TOP=${TOP_MODULE}"
    echo "PIPELINE_VERSION=0x00024E11"
    echo "MAX_LAYERS=8"
    echo "MAX_WEIGHT_VALUES=2048"
    echo "MAX_BIAS_VALUES=128"
    echo "MODEL_SHAPE=8x16x8_interact18_32x16x1"
    echo "MODEL_DESCRIPTOR_COUNT=5"
    echo "MODEL_WEIGHT_VALUES=1360"
    echo "MODEL_BIAS_VALUES=73"
    echo "NO XO/XCLBIN BUILD"
    echo "NO FPGA PROGRAMMING OR RESET"
    echo "============================================================"
    printf '%s\n' "${SOURCES[@]}"
    echo "============================================================"
} | tee "${LOG_DIR}/stage2n_a10_capacity_v2_preamble.log"

cd "${WORK_DIR}"

xvlog --sv "${SOURCES[@]}" 2>&1 | tee "${XVLOG_LOG}"

xelab \
    "${TOP_MODULE}" \
    -s "${SNAPSHOT}" \
    --timescale 1ns/1ps \
    2>&1 | tee "${XELAB_LOG}"

xsim "${SNAPSHOT}" -runall 2>&1 | tee "${XSIM_LOG}"

PASS_MARKER="tb_dlrm_f37x_rtl_kernel_stage2n_a10_capacity_v2: PASS runs=2 final=36 descriptors=5 weights=1360 biases=73"

grep -qF "${PASS_MARKER}" "${XSIM_LOG}" ||
    fail "Stage 2N-A10 capacity PASS marker is missing"

if grep -E '^(ERROR:|FATAL:)' \
    "${XVLOG_LOG}" "${XELAB_LOG}" "${XSIM_LOG}"
then
    fail "Stage 2N-A10 logs contain anchored errors"
fi

{
    echo "STAGE2N_A10_CAPACITY_XSIM_V2_PASS"
    echo "TIME=$(date -Is)"
    echo "BRANCH=${CURRENT_BRANCH}"
    echo "HEAD=${CURRENT_HEAD}"
    echo "TOP=${TOP_MODULE}"
    echo "PIPELINE_VERSION=0x00024E11"
    echo "MAX_LAYERS=8"
    echo "MAX_WEIGHT_VALUES=2048"
    echo "MAX_BIAS_VALUES=128"
    echo "MODEL_SHAPE=8x16x8_interact18_32x16x1"
    echo "MODEL_DESCRIPTOR_COUNT=5"
    echo "MODEL_WEIGHT_VALUES=1360"
    echo "MODEL_BIAS_VALUES=73"
    echo "PIPELINE_START_COMMANDS=2"
    echo "BOTTOM_OUTPUTS=8"
    echo "INTERACTION_OUTPUTS=18"
    echo "FINAL_RESULT=36"
    echo "FINAL_BACKPRESSURE_CYCLES=12"
    echo "LEGACY_MLP_WINDOW_PRESERVED=1"
    echo "STANDALONE_INTERACTION_WINDOW_PRESERVED=1"
    echo "A10_ADAPTER_SHA256=$(sha256sum "${SOURCES[13]}" | awk '{print $1}')"
    echo "A10_TOP_SHA256=$(sha256sum "${SOURCES[14]}" | awk '{print $1}')"
    echo "A10_TB_SHA256=$(sha256sum "${SOURCES[15]}" | awk '{print $1}')"
    echo "RUNNER_SHA256=$(sha256sum "${REPO_ROOT}/scripts/run_stage2n_a10_capacity_xsim_v2.sh" | awk '{print $1}')"
    echo "LOG=${XSIM_LOG}"
    echo "NO_XO_OR_XCLBIN_BUILD=1"
    echo "NO_FPGA_PROGRAMMING_OR_RESET=1"
} > "${STATUS_FILE}"

echo
echo "============================================================"
echo "STAGE2N_A10_CAPACITY_XSIM_V2_PASS"
echo "FINAL_RESULT=36"
echo "STATUS=${STATUS_FILE}"
echo "LOG=${XSIM_LOG}"
echo "NO XO/XCLBIN BUILD"
echo "NO FPGA PROGRAMMING OR RESET"
echo "============================================================"
