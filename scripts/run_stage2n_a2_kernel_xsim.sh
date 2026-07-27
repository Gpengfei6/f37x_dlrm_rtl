#!/usr/bin/env bash
#
# Stage 2N-A2 integrated AXI-Lite kernel regression.
#
# New top and testbench names are used deliberately. Existing verified files
# are not replaced. This script performs simulation only and never accesses
# an FPGA device.
#

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

VIVADO_SETTINGS="${VIVADO_SETTINGS:-/opt/Xilinx/Vivado/2020.2/settings64.sh}"
WORK_DIR="${REPO_ROOT}/work/stage2n_a2_kernel_xsim"
LOG_DIR="${REPO_ROOT}/logs"
RESULT_DIR="${REPO_ROOT}/results/stage2n_a2"
STATUS_FILE="${RESULT_DIR}/stage2n_a2_kernel_xsim_status.txt"

XVLOG_LOG="${LOG_DIR}/xvlog_stage2n_a2_kernel.log"
XELAB_LOG="${LOG_DIR}/xelab_stage2n_a2_kernel.log"
XSIM_LOG="${LOG_DIR}/xsim_stage2n_a2_kernel.log"

TOP_MODULE="tb_dlrm_f37x_rtl_kernel_stage2n_a2"
SNAPSHOT="tb_dlrm_f37x_rtl_kernel_stage2n_a2_sim"

fail()
{
    echo "ERROR: $*" >&2
    exit 10
}

git_value()
{
    local command_name="$1"
    (
        cd "${REPO_ROOT}"
        case "${command_name}" in
            branch)
                git symbolic-ref --short HEAD 2>/dev/null || echo UNKNOWN
                ;;
            head)
                git rev-parse HEAD 2>/dev/null || echo UNKNOWN
                ;;
            *)
                echo UNKNOWN
                ;;
        esac
    )
}

[[ -f "${VIVADO_SETTINGS}" ]] ||
    fail "Vivado settings not found: ${VIVADO_SETTINGS}"

# shellcheck disable=SC1090
source "${VIVADO_SETTINGS}" >/dev/null

for tool in xvlog xelab xsim; do
    command -v "${tool}" >/dev/null 2>&1 ||
        fail "${tool} is not available"
done

SOURCES=(
    "${REPO_ROOT}/rtl/common/rv_fifo.sv"
    "${REPO_ROOT}/rtl/common/runtime_relu_quant.sv"
    "${REPO_ROOT}/rtl/compute/mac_lane.sv"
    "${REPO_ROOT}/rtl/memory/banked_activation_buffer.sv"
    "${REPO_ROOT}/rtl/memory/local_weight_provider.sv"
    "${REPO_ROOT}/rtl/compute/vector_dot_product_core.sv"
    "${REPO_ROOT}/rtl/compute/dense_layer_engine.sv"
    "${REPO_ROOT}/rtl/control/mlp_sequence_controller.sv"
    "${REPO_ROOT}/rtl/f37x/dlrm_f37x_rtl_kernel.sv"
    "${REPO_ROOT}/rtl/interaction/dlrm_feature_interaction_engine.sv"
    "${REPO_ROOT}/rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a2.sv"
    "${REPO_ROOT}/tb/tb_dlrm_f37x_rtl_kernel_stage2n_a2.sv"
)

for source_file in "${SOURCES[@]}"; do
    [[ -f "${source_file}" ]] ||
        fail "missing source: ${source_file}"
done

GIT_BRANCH="$(git_value branch)"
GIT_HEAD="$(git_value head)"

rm -rf "${WORK_DIR}"
mkdir -p "${WORK_DIR}" "${LOG_DIR}" "${RESULT_DIR}"
rm -f "${STATUS_FILE}" "${XVLOG_LOG}" "${XELAB_LOG}" "${XSIM_LOG}"

cd "${WORK_DIR}"

echo "============================================================"
echo "Stage 2N-A2 Integrated Kernel XSim"
echo "TIME=$(date -Is)"
echo "REPO=${REPO_ROOT}"
echo "BRANCH=${GIT_BRANCH}"
echo "HEAD=${GIT_HEAD}"
echo "TOP=${TOP_MODULE}"
echo "WORK=${WORK_DIR}"
echo "NO XO/XCLBIN BUILD"
echo "NO FPGA PROGRAMMING OR RESET"
echo "============================================================"

xvlog --sv "${SOURCES[@]}" 2>&1 | tee "${XVLOG_LOG}"

xelab \
    "${TOP_MODULE}" \
    -s "${SNAPSHOT}" \
    --timescale 1ns/1ps \
    2>&1 | tee "${XELAB_LOG}"

xsim "${SNAPSHOT}" -runall 2>&1 | tee "${XSIM_LOG}"

PASS_MARKER="tb_dlrm_f37x_rtl_kernel_stage2n_a2: PASS mlp_result=19 interaction_outputs=18"

grep -qF "${PASS_MARKER}" "${XSIM_LOG}" ||
    fail "Stage 2N-A2 PASS marker is missing"

if grep -E '^(ERROR:|FATAL:)' \
    "${XVLOG_LOG}" \
    "${XELAB_LOG}" \
    "${XSIM_LOG}"
then
    fail "Stage 2N-A2 logs contain anchored errors"
fi

{
    echo "STAGE2N_A2_KERNEL_XSIM_PASS"
    echo "TIME=$(date -Is)"
    echo "BRANCH=${GIT_BRANCH}"
    echo "HEAD=${GIT_HEAD}"
    echo "TOP=${TOP_MODULE}"
    echo "LEGACY_MLP_RESULT=19"
    echo "INTERACTION_VECTOR_COUNT=5"
    echo "INTERACTION_VECTOR_DIM=8"
    echo "INTERACTION_OUTPUT_DIM=18"
    echo "INTERACTION_REGISTER_BASE=0x100"
    echo "OLD_MLP_WINDOW_PRESERVED=0x000-0x0FF"
    echo "NO_EXISTING_RTL_REPLACED=1"
    echo "TOP_SHA256=$(sha256sum "${REPO_ROOT}/rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a2.sv" | awk '{print $1}')"
    echo "TB_SHA256=$(sha256sum "${REPO_ROOT}/tb/tb_dlrm_f37x_rtl_kernel_stage2n_a2.sv" | awk '{print $1}')"
    echo "LOG=${XSIM_LOG}"
} > "${STATUS_FILE}"

echo
echo "============================================================"
echo "STAGE2N_A2_KERNEL_XSIM_PASS"
echo "STATUS=${STATUS_FILE}"
echo "LOG=${XSIM_LOG}"
echo "============================================================"
