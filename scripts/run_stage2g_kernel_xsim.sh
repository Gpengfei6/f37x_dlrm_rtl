#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

VIVADO_SETTINGS="${VIVADO_SETTINGS:-/opt/Xilinx/Vivado/2020.2/settings64.sh}"
WORK_DIR="${REPO_ROOT}/work/stage2g_xsim"
LOG_DIR="${REPO_ROOT}/logs"
RESULT_DIR="${REPO_ROOT}/results/stage2g"

if [[ ! -f "${VIVADO_SETTINGS}" ]]; then
    echo "ERROR: Vivado settings not found: ${VIVADO_SETTINGS}" >&2
    exit 2
fi

# shellcheck disable=SC1090
source "${VIVADO_SETTINGS}"

for tool in xvlog xelab xsim; do
    if ! command -v "${tool}" >/dev/null 2>&1; then
        echo "ERROR: ${tool} is not available" >&2
        exit 3
    fi
done

rm -rf "${WORK_DIR}"
mkdir -p "${WORK_DIR}" "${LOG_DIR}" "${RESULT_DIR}"
cd "${WORK_DIR}"

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
    "${REPO_ROOT}/tb/tb_dlrm_f37x_rtl_kernel.sv"
)

for source_file in "${SOURCES[@]}"; do
    if [[ ! -f "${source_file}" ]]; then
        echo "ERROR: missing source: ${source_file}" >&2
        exit 4
    fi
done

xvlog --sv "${SOURCES[@]}" \
    2>&1 | tee "${LOG_DIR}/xvlog_stage2g_kernel.log"

xelab tb_dlrm_f37x_rtl_kernel \
    -s tb_dlrm_f37x_rtl_kernel_sim \
    --timescale 1ns/1ps \
    2>&1 | tee "${LOG_DIR}/xelab_stage2g_kernel.log"

xsim tb_dlrm_f37x_rtl_kernel_sim \
    -runall \
    2>&1 | tee "${LOG_DIR}/xsim_stage2g_kernel.log"

if ! grep -q \
    'tb_dlrm_f37x_rtl_kernel: PASS' \
    "${LOG_DIR}/xsim_stage2g_kernel.log"; then
    echo "ERROR: Stage 2G kernel simulation PASS marker missing" >&2
    exit 5
fi

if grep -E '^(ERROR:|FATAL:)' \
    "${LOG_DIR}/xvlog_stage2g_kernel.log" \
    "${LOG_DIR}/xelab_stage2g_kernel.log" \
    "${LOG_DIR}/xsim_stage2g_kernel.log"; then
    echo "ERROR: Stage 2G simulation logs contain anchored errors" >&2
    exit 6
fi

cat > "${RESULT_DIR}/stage2g_kernel_xsim_status.txt" <<EOF
STAGE2G_KERNEL_XSIM_PASS
TOP=tb_dlrm_f37x_rtl_kernel
CORE=mlp_sequence_controller
EXPECTED_RESULT=19
EOF

echo "STAGE2G_KERNEL_XSIM_PASS"
