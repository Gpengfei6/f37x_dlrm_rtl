#!/usr/bin/env bash
#
# Collect and validate final Stage 2N-A10 evidence (v4 board-status schema fix).
#
# This script does not access any FPGA device:
#   - no xbutil;
#   - no render-node access;
#   - no FPGA programming;
#   - no FPGA reset.
#

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

EXPECTED_BRANCH="work/stage2n-a10-model-batch-regression"
EXPECTED_UUID="f7a23117-5218-4fba-adb5-f093b596df03"
EXPECTED_KERNEL="dlrm_f37x_rtl_kernel_stage2n_a10_v2"
EXPECTED_CU="${EXPECTED_KERNEL}:dlrm_a10_1"
EXPECTED_XCLBIN_SIZE="43078792"

XSIM_STATUS="${REPO_ROOT}/results/stage2n_a10/stage2n_a10_capacity_xsim_v2_status.txt"
PACKAGE_STATUS="${REPO_ROOT}/results/stage2n_a10/package_v2/stage2n_a10_xo_package_v2_status.txt"
LINK_STATUS="${REPO_ROOT}/results/stage2n_a10/link_v1/stage2n_a10_f37x_link_v1_status.txt"
LINK_ACCEPT_STATUS="${REPO_ROOT}/results/stage2n_a10/link_v1/stage2n_a10_f37x_link_artifact_accept_v1_status.txt"
LINK_ACCEPT_DETAILS="${REPO_ROOT}/results/stage2n_a10/link_v1/stage2n_a10_f37x_link_artifact_accept_v1_details.txt"
XCLBIN_INFO="${REPO_ROOT}/results/stage2n_a10/link_v1/${EXPECTED_KERNEL}.xclbin.info"
TIMING_REPORT="${REPO_ROOT}/results/stage2n_a10/link_v1/${EXPECTED_KERNEL}_timing_summary_routed.rpt"
XCLBIN="${REPO_ROOT}/build/stage2n_a10/link_v1/hw/${EXPECTED_KERNEL}.xclbin"

BOARD_STATUS_DIR="${REPO_ROOT}/results/stage2n_a10_board_v3"
BOARD_LOG_DIR="${REPO_ROOT}/server_results/stage2n_a10"

EVIDENCE_DIR="${REPO_ROOT}/docs/evidence/stage2n_a10_final_v4"
FINAL_STATUS="${EVIDENCE_DIR}/stage2n_a10_final_acceptance_v4_status.txt"
MANIFEST="${EVIDENCE_DIR}/stage2n_a10_final_evidence_manifest_v4.sha256"

fail()
{
    local reason="$*"
    mkdir -p "${EVIDENCE_DIR}"
    cat > "${FINAL_STATUS}" <<EOF
STAGE2N_A10_FINAL_ACCEPTANCE_V4_FAILED
REASON=${reason}
NO_FPGA_ACCESS=1
NO_FPGA_PROGRAMMING_OR_RESET=1
EOF
    echo "ERROR: ${reason}" >&2
    exit 20
}

require_file()
{
    local file="$1"
    [[ -s "${file}" ]] ||
        fail "required file missing or empty: ${file}"
}

require_exact()
{
    local file="$1"
    local line="$2"
    grep -Fxq "${line}" "${file}" ||
        fail "missing exact line in ${file}: ${line}"
}

cd "${REPO_ROOT}"

CURRENT_BRANCH="$(git symbolic-ref --short HEAD 2>/dev/null || echo DETACHED)"
CURRENT_HEAD="$(git rev-parse HEAD)"

[[ "${CURRENT_BRANCH}" == "${EXPECTED_BRANCH}" ]] ||
    fail "wrong branch: ${CURRENT_BRANCH}"

for file in \
    "${XSIM_STATUS}" \
    "${PACKAGE_STATUS}" \
    "${LINK_STATUS}" \
    "${LINK_ACCEPT_STATUS}" \
    "${LINK_ACCEPT_DETAILS}" \
    "${XCLBIN_INFO}" \
    "${TIMING_REPORT}" \
    "${XCLBIN}"
do
    require_file "${file}"
done

BOARD_STATUS="$(
    find "${BOARD_STATUS_DIR}" \
        -maxdepth 1 \
        -type f \
        -name 'stage2n_a10_pipeline_board_smoke_v3_status_*.txt' \
        -print |
    sort |
    tail -n 1
)"
[[ -n "${BOARD_STATUS}" ]] ||
    fail "no Stage 2N-A10 v3 board status was found"
require_file "${BOARD_STATUS}"

BOARD_LOG="$(
    find "${BOARD_LOG_DIR}" \
        -maxdepth 1 \
        -type f \
        -name 'stage2n_a10_pipeline_board_smoke_v3_*.log' \
        -print |
    sort |
    tail -n 1
)"
[[ -n "${BOARD_LOG}" ]] ||
    fail "no Stage 2N-A10 v3 board log was found"
require_file "${BOARD_LOG}"

# Canonical source files must be non-empty. Historical v1 placeholders are
# intentionally not modified or removed.
for file in \
    rtl/f37x/dlrm_internal_pipeline_axi_lite_adapter_stage2n_a10_v2.sv \
    rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a10_v2.sv \
    tb/tb_dlrm_f37x_rtl_kernel_stage2n_a10_capacity_v2.sv \
    scripts/run_stage2n_a10_capacity_xsim_v2.sh \
    tcl/package_stage2n_a10_xo_v2.tcl \
    scripts/run_stage2n_a10_xo_package_v2.sh \
    scripts/link_stage2n_a10_f37x_xclbin_v1.sh \
    scripts/accept_stage2n_a10_f37x_link_artifact_v1.sh \
    host/stage2n_a10_pipeline_board_smoke_v3.cpp \
    scripts/program_and_run_stage2n_a10_pipeline_board_smoke_v3.sh
do
    require_file "${REPO_ROOT}/${file}"
done

# Simulation acceptance.
require_exact "${XSIM_STATUS}" "STAGE2N_A10_CAPACITY_XSIM_V2_PASS"
require_exact "${XSIM_STATUS}" "PIPELINE_VERSION=0x00024E11"
require_exact "${XSIM_STATUS}" "MODEL_DESCRIPTOR_COUNT=5"
require_exact "${XSIM_STATUS}" "MODEL_WEIGHT_VALUES=1360"
require_exact "${XSIM_STATUS}" "MODEL_BIAS_VALUES=73"
require_exact "${XSIM_STATUS}" "FINAL_RESULT=36"

# XO package acceptance.
require_exact "${PACKAGE_STATUS}" "STAGE2N_A10_XO_PACKAGE_V2_PASS"
require_exact "${PACKAGE_STATUS}" "KERNEL=${EXPECTED_KERNEL}"
require_exact "${PACKAGE_STATUS}" "PIPELINE_VERSION=0x00024E11"
require_exact "${PACKAGE_STATUS}" "KERNEL_XML_ARG_COUNT=74"
require_exact "${PACKAGE_STATUS}" "COMPONENT_XML_REGISTER_COUNT=77"

# Hardware link acceptance.
require_exact "${LINK_STATUS}" "STAGE2N_A10_F37X_LINK_V1_PASS"
require_exact "${LINK_STATUS}" "XCLBIN_SIZE_BYTES=${EXPECTED_XCLBIN_SIZE}"
require_exact "${LINK_STATUS}" "XCLBIN_UUID=${EXPECTED_UUID}"
require_exact "${LINK_STATUS}" "COMPUTE_UNIT=dlrm_a10_1"
require_exact "${LINK_STATUS}" "TIMING_MET=1"
require_exact "${LINK_STATUS}" "NO_FPGA_PROGRAMMING_OR_RESET=1"

require_exact "${LINK_ACCEPT_STATUS}" \
    "STAGE2N_A10_F37X_LINK_ARTIFACT_ACCEPT_V1_PASS"
require_exact "${LINK_ACCEPT_STATUS}" "XCLBIN_SIZE_BYTES=${EXPECTED_XCLBIN_SIZE}"
require_exact "${LINK_ACCEPT_STATUS}" "XCLBIN_UUID=${EXPECTED_UUID}"
require_exact "${LINK_ACCEPT_STATUS}" "TIMING_MET=1"
require_exact "${LINK_ACCEPT_STATUS}" "NO_FPGA_ACCESS=1"

# Board acceptance.
#
# The protected board runner writes machine-readable keys to BOARD_STATUS.
# Its human-readable stdout summary uses TARGET/UUID/CU, but those summary
# spellings are not present in the status file. Validate the actual status
# schema here.
require_exact "${BOARD_STATUS}" "STAGE2N_A10_PIPELINE_BOARD_SMOKE_V3_PASS"
require_exact "${BOARD_STATUS}" "TARGET_INDEX=2"
require_exact "${BOARD_STATUS}" "TARGET_BDF=0000:9b:00.1"
require_exact "${BOARD_STATUS}" "TARGET_RENDER=/dev/dri/renderD129"
require_exact "${BOARD_STATUS}" "XCLBIN_UUID=${EXPECTED_UUID}"
require_exact "${BOARD_STATUS}" "KERNEL=${EXPECTED_KERNEL}"
require_exact "${BOARD_STATUS}" "COMPUTE_UNIT=dlrm_a10_1"
require_exact "${BOARD_STATUS}" "IP_NAME=${EXPECTED_CU}"
require_exact "${BOARD_STATUS}" "IP_INDEX=0"
require_exact "${BOARD_STATUS}" "KERNEL_FREQUENCY_MHZ=100"
require_exact "${BOARD_STATUS}" "PIPELINE_RUNS=2"
require_exact "${BOARD_STATUS}" "PIPELINE_DESCRIPTOR_COUNT=5"
require_exact "${BOARD_STATUS}" "PIPELINE_WEIGHT_VALUES=1360"
require_exact "${BOARD_STATUS}" "PIPELINE_BIAS_VALUES=73"
require_exact "${BOARD_STATUS}"     "PIPELINE_MODEL_SHAPE=8x16x8_interact18_32x16x1"
require_exact "${BOARD_STATUS}" "PIPELINE_EXPECTED_RESULT_TAG=4"
require_exact "${BOARD_STATUS}" "PIPELINE_RESULT=36"
require_exact "${BOARD_STATUS}" "BOTTOM_OUTPUTS=8"
require_exact "${BOARD_STATUS}" "INTERACTION_OUTPUTS=18"
require_exact "${BOARD_STATUS}" "FINAL_BACKPRESSURE_READS=12"
require_exact "${BOARD_STATUS}" "FIREWALL_GOOD_AFTER_TEST=1"
require_exact "${BOARD_STATUS}" "CU_IDLE_AFTER_TEST=1"
require_exact "${BOARD_STATUS}" "NO_FPGA_RESET=1"
require_exact "${BOARD_STATUS}" "NO_AUTOMATIC_ROLLBACK=1"
require_exact "${BOARD_STATUS}" "NO_OTHER_DEVICE_ACCESS=1"

# Core Host-level evidence inside the complete log.
for line in     "PIPELINE_RUN[0]_RESULT=36"     "PIPELINE_RUN[0]_TAG=4"     "PIPELINE_RUN[0]_EXPECTED_FINAL_DESCRIPTOR_TAG=4"     "PIPELINE_RUN[1]_RESULT=36"     "PIPELINE_RUN[1]_TAG=4"     "PIPELINE_RUN[1]_EXPECTED_FINAL_DESCRIPTOR_TAG=4"     "FINAL_BACKPRESSURE_READS=12"
do
    require_exact "${BOARD_LOG}" "${line}"
done

# Stale-result recovery is diagnostic evidence, not a prerequisite for every
# future successful v3 run. Validate its full tuple only when it occurred.
STALE_RESULT_RECOVERY_OBSERVED=0
if grep -Fxq "PIPELINE_STALE_RESULT_DETECTED=1" "${BOARD_LOG}"; then
    for line in         "PIPELINE_STALE_RESULT=36"         "PIPELINE_STALE_TAG=4"         "PIPELINE_STALE_RESULT_POPPED=1"
    do
        require_exact "${BOARD_LOG}" "${line}"
    done
    STALE_RESULT_RECOVERY_OBSERVED=1
fi

grep -Fq \
    "STAGE2N_A10_PIPELINE_BOARD_SMOKE_V3_PASS runs=2 final=36" \
    "${BOARD_LOG}" ||
    fail "Host v3 PASS marker is missing from board log"

ACTUAL_XCLBIN_SIZE="$(stat -c '%s' "${XCLBIN}")"
[[ "${ACTUAL_XCLBIN_SIZE}" == "${EXPECTED_XCLBIN_SIZE}" ]] ||
    fail "xclbin size mismatch: ${ACTUAL_XCLBIN_SIZE}"

XCLBIN_SHA256="$(sha256sum "${XCLBIN}" | awk '{print $1}')"
[[ "${XCLBIN_SHA256}" =~ ^[0-9a-f]{64}$ ]] ||
    fail "computed xclbin SHA256 is invalid"

grep -qF "All user specified timing constraints are met." \
    "${TIMING_REPORT}" ||
    fail "timing report does not confirm that all constraints are met"

mkdir -p "${EVIDENCE_DIR}"

copy_evidence()
{
    local source="$1"
    cp -f "${source}" "${EVIDENCE_DIR}/"
}

copy_evidence "${XSIM_STATUS}"
copy_evidence "${PACKAGE_STATUS}"
copy_evidence "${LINK_STATUS}"
copy_evidence "${LINK_ACCEPT_STATUS}"
copy_evidence "${LINK_ACCEPT_DETAILS}"
copy_evidence "${XCLBIN_INFO}"
copy_evidence "${TIMING_REPORT}"
copy_evidence "${BOARD_STATUS}"
copy_evidence "${BOARD_LOG}"

BOARD_STATUS_BASENAME="$(basename "${BOARD_STATUS}")"
BOARD_LOG_BASENAME="$(basename "${BOARD_LOG}")"

cat > "${FINAL_STATUS}" <<EOF
STAGE2N_A10_FINAL_ACCEPTANCE_V4_PASS
GIT_BRANCH=${CURRENT_BRANCH}
GIT_HEAD=${CURRENT_HEAD}
PIPELINE_VERSION=0x00024E11
MODEL_SHAPE=8x16x8_interact18_32x16x1
MODEL_DESCRIPTOR_COUNT=5
MODEL_WEIGHT_VALUES=1360
MODEL_BIAS_VALUES=73
XSIM_RUNS=2
XSIM_RESULT=36
XO_PACKAGE_ACCEPTED=1
XCLBIN_LINK_ACCEPTED=1
XCLBIN_SIZE_BYTES=${ACTUAL_XCLBIN_SIZE}
XCLBIN_SHA256=${XCLBIN_SHA256}
XCLBIN_UUID=${EXPECTED_UUID}
KERNEL=${EXPECTED_KERNEL}
COMPUTE_UNIT=dlrm_a10_1
KERNEL_FREQUENCY_MHZ=100
TIMING_MET=1
BOARD_TARGET_INDEX=2
BOARD_TARGET_BDF=0000:9b:00.1
BOARD_RENDER_NODE=/dev/dri/renderD129
BOARD_RUNS=2
BOARD_RESULT=36
BOARD_RESULT_TAG=4
BOTTOM_OUTPUTS=8
INTERACTION_OUTPUTS=18
FINAL_BACKPRESSURE_READS=12
BOARD_STATUS_SCHEMA=TARGET_INDEX_TARGET_BDF_TARGET_RENDER_XCLBIN_UUID_IP_NAME
STALE_RESULT_RECOVERY_OBSERVED=${STALE_RESULT_RECOVERY_OBSERVED}
BOARD_STATUS_FILE=${BOARD_STATUS_BASENAME}
BOARD_LOG_FILE=${BOARD_LOG_BASENAME}
XO_PACKAGE_TCL=tcl/package_stage2n_a10_xo_v2.tcl
EVIDENCE_COLLECTOR_VERSION=4
NO_FPGA_ACCESS_DURING_COLLECTION=1
NO_FPGA_PROGRAMMING_OR_RESET_DURING_COLLECTION=1
EOF

(
    cd "${EVIDENCE_DIR}"
    find . \
        -maxdepth 1 \
        -type f \
        ! -name "$(basename "${MANIFEST}")" \
        -print0 |
    sort -z |
    xargs -0 sha256sum
) > "${MANIFEST}"

echo "============================================================"
echo "STAGE2N_A10_FINAL_ACCEPTANCE_V4_PASS"
echo "EVIDENCE_COLLECTOR_VERSION=4"
echo "XO_PACKAGE_TCL=tcl/package_stage2n_a10_xo_v2.tcl"
echo "PIPELINE_VERSION=0x00024E11"
echo "MODEL_SHAPE=8x16x8_interact18_32x16x1"
echo "XSIM_RUNS=2"
echo "BOARD_RUNS=2"
echo "BOARD_RESULT=36"
echo "BOARD_RESULT_TAG=4"
echo "BOARD_STATUS_SCHEMA_VALID=1"
echo "STALE_RESULT_RECOVERY_OBSERVED=${STALE_RESULT_RECOVERY_OBSERVED}"
echo "XCLBIN_UUID=${EXPECTED_UUID}"
echo "XCLBIN_SHA256_LENGTH=${#XCLBIN_SHA256}"
echo "TIMING_MET=1"
echo "EVIDENCE_DIR=${EVIDENCE_DIR}"
echo "FINAL_STATUS=${FINAL_STATUS}"
echo "MANIFEST=${MANIFEST}"
echo "NO FPGA ACCESS WAS PERFORMED"
echo "============================================================"
