#!/usr/bin/env bash
#
# Stage 2N-A10 F37X link artifact acceptance v1.
#
# Read-only with respect to the FPGA:
#   - no xbutil;
#   - no render-node access;
#   - no FPGA programming or reset.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

EXPECTED_BRANCH="work/stage2n-a10-model-batch-regression"
EXPECTED_KERNEL="dlrm_f37x_rtl_kernel_stage2n_a10_v2"
EXPECTED_CU="dlrm_a10_1"
EXPECTED_UUID="f7a23117-5218-4fba-adb5-f093b596df03"
EXPECTED_SIZE="43078792"
EXPECTED_PLATFORM="inspur_f37x_xdma_201920_3"
EXPECTED_FREQUENCY="100"

PACKAGE_STATUS="${REPO_ROOT}/results/stage2n_a10/package_v2/stage2n_a10_xo_package_v2_status.txt"
LINK_STATUS="${REPO_ROOT}/results/stage2n_a10/link_v1/stage2n_a10_f37x_link_v1_status.txt"
XCLBIN="${REPO_ROOT}/build/stage2n_a10/link_v1/hw/${EXPECTED_KERNEL}.xclbin"
XCLBIN_INFO="${REPO_ROOT}/results/stage2n_a10/link_v1/${EXPECTED_KERNEL}.xclbin.info"
TIMING_COPY="${REPO_ROOT}/results/stage2n_a10/link_v1/${EXPECTED_KERNEL}_timing_summary_routed.rpt"

RESULT_DIR="${REPO_ROOT}/results/stage2n_a10/link_v1"
STATUS="${RESULT_DIR}/stage2n_a10_f37x_link_artifact_accept_v1_status.txt"
DETAILS="${RESULT_DIR}/stage2n_a10_f37x_link_artifact_accept_v1_details.txt"
EVIDENCE_DIR="${REPO_ROOT}/docs/evidence/stage2n_a10_link_v1"

fail()
{
    local reason="$*"
    mkdir -p "${RESULT_DIR}"
    cat > "${STATUS}" <<EOF
STAGE2N_A10_F37X_LINK_ARTIFACT_ACCEPT_V1_FAILED
REASON=${reason}
NO_FPGA_ACCESS=1
NO_FPGA_PROGRAMMING_OR_RESET=1
EOF
    echo "ERROR: ${reason}" >&2
    exit 10
}

require_exact()
{
    local file="$1"
    local line="$2"
    grep -Fxq "${line}" "${file}" ||
        fail "missing exact line in ${file}: ${line}"
}

require_key()
{
    local file="$1"
    local key="$2"
    local expected="$3"
    local actual
    actual="$(sed -n "s/^${key}=//p" "${file}" | head -n 1)"
    [[ "${actual}" == "${expected}" ]] ||
        fail "${key}=${actual:-<missing>}, expected ${expected}"
}

cd "${REPO_ROOT}"

CURRENT_BRANCH="$(git symbolic-ref --short HEAD 2>/dev/null || echo DETACHED)"
CURRENT_HEAD="$(git rev-parse HEAD)"

[[ "${CURRENT_BRANCH}" == "${EXPECTED_BRANCH}" ]] ||
    fail "wrong branch: ${CURRENT_BRANCH}"

for file in \
    "${PACKAGE_STATUS}" \
    "${LINK_STATUS}" \
    "${XCLBIN}" \
    "${XCLBIN_INFO}" \
    "${TIMING_COPY}"
do
    [[ -s "${file}" ]] ||
        fail "required artifact missing or empty: ${file}"
done

require_exact "${PACKAGE_STATUS}" "STAGE2N_A10_XO_PACKAGE_V2_PASS"
require_key "${PACKAGE_STATUS}" "KERNEL" "${EXPECTED_KERNEL}"
require_key "${PACKAGE_STATUS}" "PIPELINE_VERSION" "0x00024E11"
require_key "${PACKAGE_STATUS}" "MAX_LAYERS" "8"
require_key "${PACKAGE_STATUS}" "MAX_WEIGHT_VALUES" "2048"
require_key "${PACKAGE_STATUS}" "MAX_BIAS_VALUES" "128"
require_key "${PACKAGE_STATUS}" "KERNEL_XML_ARG_COUNT" "74"
require_key "${PACKAGE_STATUS}" "COMPONENT_XML_REGISTER_COUNT" "77"

require_exact "${LINK_STATUS}" "STAGE2N_A10_F37X_LINK_V1_PASS"
require_key "${LINK_STATUS}" "KERNEL" "${EXPECTED_KERNEL}"
require_key "${LINK_STATUS}" "COMPUTE_UNIT" "${EXPECTED_CU}"
require_key "${LINK_STATUS}" "TARGET" "hw"
require_key "${LINK_STATUS}" "KERNEL_FREQUENCY_MHZ" "${EXPECTED_FREQUENCY}"
require_key "${LINK_STATUS}" "PIPELINE_VERSION" "0x00024E11"
require_key "${LINK_STATUS}" "MAX_LAYERS" "8"
require_key "${LINK_STATUS}" "MAX_WEIGHT_VALUES" "2048"
require_key "${LINK_STATUS}" "MAX_BIAS_VALUES" "128"
require_key "${LINK_STATUS}" "MODEL_SHAPE" "8x16x8_interact18_32x16x1"
require_key "${LINK_STATUS}" "XCLBIN_SIZE_BYTES" "${EXPECTED_SIZE}"
require_key "${LINK_STATUS}" "XCLBIN_UUID" "${EXPECTED_UUID}"
require_key "${LINK_STATUS}" "TIMING_MET" "1"
require_key "${LINK_STATUS}" "ERROR_COUNT" "0"
require_key "${LINK_STATUS}" "CRITICAL_WARNING_COUNT" "0"
require_key "${LINK_STATUS}" "NO_FPGA_PROGRAMMING_OR_RESET" "1"

ACTUAL_SIZE="$(stat -c '%s' "${XCLBIN}")"
[[ "${ACTUAL_SIZE}" == "${EXPECTED_SIZE}" ]] ||
    fail "xclbin size ${ACTUAL_SIZE}, expected ${EXPECTED_SIZE}"

XCLBIN_SHA256="$(sha256sum "${XCLBIN}" | awk '{print $1}')"
[[ "${XCLBIN_SHA256}" =~ ^[0-9a-f]{64}$ ]] ||
    fail "computed xclbin SHA256 is not valid lowercase hexadecimal"

METADATA_UUID="$(
    sed -n 's/^[[:space:]]*UUID (xclbin):[[:space:]]*//p' \
        "${XCLBIN_INFO}" |
    head -n 1 |
    tr -d '\r'
)"
[[ "${METADATA_UUID}" == "${EXPECTED_UUID}" ]] ||
    fail "xclbin metadata UUID mismatch: ${METADATA_UUID}"

METADATA_KERNEL="$(
    sed -n \
        -e 's/^[[:space:]]*Kernel:[[:space:]]*//p' \
        -e 's/^[[:space:]]*Kernels:[[:space:]]*//p' \
        "${XCLBIN_INFO}" |
    head -n 1 |
    tr -d '\r'
)"
[[ "${METADATA_KERNEL}" == "${EXPECTED_KERNEL}" ]] ||
    fail "xclbin metadata kernel mismatch: ${METADATA_KERNEL}"

METADATA_CU="$(
    sed -n 's/^[[:space:]]*Instance:[[:space:]]*//p' \
        "${XCLBIN_INFO}" |
    head -n 1 |
    awk '{print $1}' |
    tr -d '\r'
)"
[[ "${METADATA_CU}" == "${EXPECTED_CU}" ]] ||
    fail "xclbin metadata CU mismatch: ${METADATA_CU}"

grep -qF "Platform VBNV:          ${EXPECTED_PLATFORM}" "${XCLBIN_INFO}" ||
    fail "expected platform is missing from xclbin metadata"

grep -qF "All user specified timing constraints are met." "${TIMING_COPY}" ||
    fail "routed timing report does not confirm all constraints are met"

TIMING_LINE="$(
    awk '
        /WNS\(ns\)/ && /TNS\(ns\)/ {
            found = 1
            next
        }
        found && /^[[:space:]]*-+/ {
            next
        }
        found && NF >= 4 {
            print
            exit
        }
    ' "${TIMING_COPY}"
)"
[[ -n "${TIMING_LINE}" ]] ||
    fail "timing summary line could not be parsed"

mkdir -p "${RESULT_DIR}" "${EVIDENCE_DIR}"

cp -f "${PACKAGE_STATUS}" "${EVIDENCE_DIR}/"
cp -f "${LINK_STATUS}" "${EVIDENCE_DIR}/"
cp -f "${XCLBIN_INFO}" "${EVIDENCE_DIR}/"
cp -f "${TIMING_COPY}" "${EVIDENCE_DIR}/"

cat > "${DETAILS}" <<EOF
STAGE2N_A10_F37X_LINK_ARTIFACT_ACCEPT_V1_DETAILS
GIT_BRANCH=${CURRENT_BRANCH}
GIT_HEAD=${CURRENT_HEAD}
KERNEL=${EXPECTED_KERNEL}
COMPUTE_UNIT=${EXPECTED_CU}
PLATFORM=${EXPECTED_PLATFORM}
KERNEL_FREQUENCY_MHZ=${EXPECTED_FREQUENCY}
PIPELINE_VERSION=0x00024E11
MAX_LAYERS=8
MAX_WEIGHT_VALUES=2048
MAX_BIAS_VALUES=128
MODEL_SHAPE=8x16x8_interact18_32x16x1
XCLBIN=${XCLBIN}
XCLBIN_SIZE_BYTES=${ACTUAL_SIZE}
XCLBIN_SHA256=${XCLBIN_SHA256}
XCLBIN_UUID=${METADATA_UUID}
TIMING_MET=1
TIMING_SUMMARY_LINE=${TIMING_LINE}
TIMING_MARGIN_NOTE=Timing met at report precision; WNS/WHS are displayed as 0.000 ns.
NO_FPGA_ACCESS=1
NO_FPGA_PROGRAMMING_OR_RESET=1
EOF

cat > "${STATUS}" <<EOF
STAGE2N_A10_F37X_LINK_ARTIFACT_ACCEPT_V1_PASS
KERNEL=${EXPECTED_KERNEL}
COMPUTE_UNIT=${EXPECTED_CU}
PLATFORM=${EXPECTED_PLATFORM}
KERNEL_FREQUENCY_MHZ=${EXPECTED_FREQUENCY}
PIPELINE_VERSION=0x00024E11
MAX_LAYERS=8
MAX_WEIGHT_VALUES=2048
MAX_BIAS_VALUES=128
MODEL_SHAPE=8x16x8_interact18_32x16x1
XCLBIN=${XCLBIN}
XCLBIN_SIZE_BYTES=${ACTUAL_SIZE}
XCLBIN_SHA256=${XCLBIN_SHA256}
XCLBIN_UUID=${METADATA_UUID}
TIMING_MET=1
TIMING_SUMMARY_LINE=${TIMING_LINE}
DETAILS=${DETAILS}
EVIDENCE_DIR=${EVIDENCE_DIR}
NO_FPGA_ACCESS=1
NO_FPGA_PROGRAMMING_OR_RESET=1
EOF

echo "============================================================"
echo "STAGE2N_A10_F37X_LINK_ARTIFACT_ACCEPT_V1_PASS"
echo "KERNEL=${EXPECTED_KERNEL}"
echo "COMPUTE_UNIT=${EXPECTED_CU}"
echo "XCLBIN_SIZE_BYTES=${ACTUAL_SIZE}"
echo "XCLBIN_UUID=${METADATA_UUID}"
echo "XCLBIN_SHA256_LENGTH=${#XCLBIN_SHA256}"
echo "XCLBIN_SHA256_VALID_HEX=1"
echo "TIMING_MET=1"
echo "TIMING_SUMMARY_LINE=${TIMING_LINE}"
echo "STATUS=${STATUS}"
echo "DETAILS=${DETAILS}"
echo "NO FPGA ACCESS WAS PERFORMED"
echo "============================================================"
