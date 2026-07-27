#!/usr/bin/env bash
#
# Stage 2N-A2 v2 integrated AXI-Lite kernel regression.
#
# This v2 runner does not replace the v1 runner. It resolves the verified RTL
# source paths from Git by basename, so it does not assume that the original
# F37X kernel is stored under rtl/f37x/.
#
# Simulation only:
#   * no XO packaging
#   * no xclbin link
#   * no FPGA programming or reset
#   * no render-node access
#

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

VIVADO_SETTINGS="${VIVADO_SETTINGS:-/opt/Xilinx/Vivado/2020.2/settings64.sh}"
WORK_DIR="${REPO_ROOT}/work/stage2n_a2_kernel_xsim_v2"
LOG_DIR="${REPO_ROOT}/logs"
RESULT_DIR="${REPO_ROOT}/results/stage2n_a2"
STATUS_FILE="${RESULT_DIR}/stage2n_a2_kernel_xsim_v2_status.txt"

XVLOG_LOG="${LOG_DIR}/xvlog_stage2n_a2_kernel_v2.log"
XELAB_LOG="${LOG_DIR}/xelab_stage2n_a2_kernel_v2.log"
XSIM_LOG="${LOG_DIR}/xsim_stage2n_a2_kernel_v2.log"

TOP_MODULE="tb_dlrm_f37x_rtl_kernel_stage2n_a2"
SNAPSHOT="tb_dlrm_f37x_rtl_kernel_stage2n_a2_v2_sim"

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

find_tracked_unique()
{
    local basename_value="$1"
    local matches
    local match_count
    local selected

    matches="$(
        cd "${REPO_ROOT}"
        git ls-files |
            awk -F/ -v wanted="${basename_value}" \
                '$NF == wanted { print }'
    )"

    match_count="$(
        printf '%s\n' "${matches}" |
            sed '/^[[:space:]]*$/d' |
            wc -l
    )"

    if [[ "${match_count}" -ne 1 ]]; then
        echo "SOURCE_LOOKUP_BASENAME=${basename_value}" >&2
        echo "SOURCE_LOOKUP_MATCH_COUNT=${match_count}" >&2
        if [[ -n "${matches}" ]]; then
            printf '%s\n' "${matches}" >&2
        fi
        fail "expected exactly one tracked source named ${basename_value}"
    fi

    selected="$(
        printf '%s\n' "${matches}" |
            sed '/^[[:space:]]*$/d' |
            head -n 1
    )"

    printf '%s/%s\n' "${REPO_ROOT}" "${selected}"
}

[[ -f "${VIVADO_SETTINGS}" ]] ||
    fail "Vivado settings not found: ${VIVADO_SETTINGS}"

# shellcheck disable=SC1090
source "${VIVADO_SETTINGS}" >/dev/null

for tool in xvlog xelab xsim; do
    command -v "${tool}" >/dev/null 2>&1 ||
        fail "${tool} is not available"
done

SOURCE_RV_FIFO="$(find_tracked_unique rv_fifo.sv)"
SOURCE_RELU_QUANT="$(find_tracked_unique runtime_relu_quant.sv)"
SOURCE_MAC_LANE="$(find_tracked_unique mac_lane.sv)"
SOURCE_ACTIVATION_BUFFER="$(find_tracked_unique banked_activation_buffer.sv)"
SOURCE_WEIGHT_PROVIDER="$(find_tracked_unique local_weight_provider.sv)"
SOURCE_DOT_CORE="$(find_tracked_unique vector_dot_product_core.sv)"
SOURCE_DENSE_ENGINE="$(find_tracked_unique dense_layer_engine.sv)"
SOURCE_MLP_CONTROLLER="$(find_tracked_unique mlp_sequence_controller.sv)"
SOURCE_VERIFIED_KERNEL="$(find_tracked_unique dlrm_f37x_rtl_kernel.sv)"
SOURCE_INTERACTION="$(find_tracked_unique dlrm_feature_interaction_engine.sv)"
SOURCE_A2_TOP="$(find_tracked_unique dlrm_f37x_rtl_kernel_stage2n_a2.sv)"
SOURCE_A2_TB="$(find_tracked_unique tb_dlrm_f37x_rtl_kernel_stage2n_a2.sv)"

SOURCES=(
    "${SOURCE_RV_FIFO}"
    "${SOURCE_RELU_QUANT}"
    "${SOURCE_MAC_LANE}"
    "${SOURCE_ACTIVATION_BUFFER}"
    "${SOURCE_WEIGHT_PROVIDER}"
    "${SOURCE_DOT_CORE}"
    "${SOURCE_DENSE_ENGINE}"
    "${SOURCE_MLP_CONTROLLER}"
    "${SOURCE_VERIFIED_KERNEL}"
    "${SOURCE_INTERACTION}"
    "${SOURCE_A2_TOP}"
    "${SOURCE_A2_TB}"
)

for source_file in "${SOURCES[@]}"; do
    [[ -f "${source_file}" ]] ||
        fail "resolved source is missing: ${source_file}"
done

GIT_BRANCH="$(git_value branch)"
GIT_HEAD="$(git_value head)"

rm -rf "${WORK_DIR}"
mkdir -p "${WORK_DIR}" "${LOG_DIR}" "${RESULT_DIR}"
rm -f "${STATUS_FILE}" "${XVLOG_LOG}" "${XELAB_LOG}" "${XSIM_LOG}"

echo "============================================================"
echo "Stage 2N-A2 v2 Integrated Kernel XSim"
echo "TIME=$(date -Is)"
echo "REPO=${REPO_ROOT}"
echo "BRANCH=${GIT_BRANCH}"
echo "HEAD=${GIT_HEAD}"
echo "TOP=${TOP_MODULE}"
echo "WORK=${WORK_DIR}"
echo "VERIFIED_KERNEL_SOURCE=${SOURCE_VERIFIED_KERNEL}"
echo "A2_TOP_SOURCE=${SOURCE_A2_TOP}"
echo "A2_TB_SOURCE=${SOURCE_A2_TB}"
echo "NO XO/XCLBIN BUILD"
echo "NO FPGA PROGRAMMING OR RESET"
echo "============================================================"
echo "========== RESOLVED SOURCE ORDER =========="
printf '%s\n' "${SOURCES[@]}"
echo "============================================================"

cd "${WORK_DIR}"

xvlog --sv "${SOURCES[@]}" 2>&1 | tee "${XVLOG_LOG}"

xelab \
    "${TOP_MODULE}" \
    -s "${SNAPSHOT}" \
    --timescale 1ns/1ps \
    2>&1 | tee "${XELAB_LOG}"

xsim "${SNAPSHOT}" -runall 2>&1 | tee "${XSIM_LOG}"

PASS_MARKER="tb_dlrm_f37x_rtl_kernel_stage2n_a2: PASS mlp_result=19 interaction_outputs=18"

grep -qF "${PASS_MARKER}" "${XSIM_LOG}" ||
    fail "Stage 2N-A2 v2 PASS marker is missing"

if grep -E '^(ERROR:|FATAL:)' \
    "${XVLOG_LOG}" \
    "${XELAB_LOG}" \
    "${XSIM_LOG}"
then
    fail "Stage 2N-A2 v2 logs contain anchored errors"
fi

{
    echo "STAGE2N_A2_KERNEL_XSIM_V2_PASS"
    echo "TIME=$(date -Is)"
    echo "BRANCH=${GIT_BRANCH}"
    echo "HEAD=${GIT_HEAD}"
    echo "TOP=${TOP_MODULE}"
    echo "VERIFIED_KERNEL_SOURCE=${SOURCE_VERIFIED_KERNEL}"
    echo "LEGACY_MLP_RESULT=19"
    echo "INTERACTION_VECTOR_COUNT=5"
    echo "INTERACTION_VECTOR_DIM=8"
    echo "INTERACTION_OUTPUT_DIM=18"
    echo "INTERACTION_REGISTER_BASE=0x100"
    echo "OLD_MLP_WINDOW_PRESERVED=0x000-0x0FF"
    echo "NO_EXISTING_RTL_REPLACED=1"
    echo "A2_TOP_SHA256=$(sha256sum "${SOURCE_A2_TOP}" | awk '{print $1}')"
    echo "A2_TB_SHA256=$(sha256sum "${SOURCE_A2_TB}" | awk '{print $1}')"
    echo "RUNNER_V2_SHA256=$(sha256sum "${REPO_ROOT}/scripts/run_stage2n_a2_kernel_xsim_v2.sh" | awk '{print $1}')"
    echo "LOG=${XSIM_LOG}"
} > "${STATUS_FILE}"

echo
echo "============================================================"
echo "STAGE2N_A2_KERNEL_XSIM_V2_PASS"
echo "STATUS=${STATUS_FILE}"
echo "LOG=${XSIM_LOG}"
echo "============================================================"
