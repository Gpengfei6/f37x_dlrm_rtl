#!/usr/bin/env bash
# Build-only validation for the A13 legacy-HAL XRT host.
# The resulting binary is never executed by this script.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
XRT_SETUP="${XRT_SETUP:-/opt/xilinx/xrt/setup.sh}"
EXPECTED_XRT_VERSION="${EXPECTED_XRT_VERSION:-2.9.210507}"
SOURCE="${REPO_ROOT}/host/stage2n_a13_cycle_counter_board_v1.cpp"
BUILD_DIR="${REPO_ROOT}/build/stage2n_a13/host_v1"
BINARY="${BUILD_DIR}/stage2n_a13_cycle_counter_board_v1"
LOG="${BUILD_DIR}/host_build.log"
STATUS="${BUILD_DIR}/host_build_status.txt"

fail()
{
    local code="$1"
    shift
    echo "A13_HOST_XRT_BUILD=FAIL" >&2
    echo "REASON=$*" >&2
    exit "${code}"
}

[[ ! -e "${BUILD_DIR}" ]] ||
    fail 2 "refusing to overwrite existing Host build directory: ${BUILD_DIR}"
[[ -s "${SOURCE}" ]] || fail 3 "A13 Host source is missing: ${SOURCE}"
[[ -f "${XRT_SETUP}" ]] || fail 4 "XRT setup is missing: ${XRT_SETUP}"

# shellcheck disable=SC1090
source "${XRT_SETUP}" >/dev/null

command -v g++ >/dev/null 2>&1 || fail 5 "g++ is unavailable"
command -v sha256sum >/dev/null 2>&1 || fail 6 "sha256sum is unavailable"
[[ -n "${XILINX_XRT:-}" ]] || fail 7 "XILINX_XRT is not set"
[[ -f "${XILINX_XRT}/include/xrt.h" ]] ||
    fail 8 "legacy XRT header xrt.h is missing"
[[ -f "${XILINX_XRT}/include/experimental/xrt-next.h" ]] ||
    fail 9 "XRT experimental/xrt-next.h is missing"
[[ -e "${XILINX_XRT}/lib/libxrt_core.so" ]] ||
    fail 10 "libxrt_core.so is missing"

mkdir -p "${BUILD_DIR}"

set +e
g++ \
    -std=gnu++11 \
    -O2 \
    -Wall \
    -Wextra \
    -Wpedantic \
    -I"${XILINX_XRT}/include" \
    "${SOURCE}" \
    -L"${XILINX_XRT}/lib" \
    -Wl,-rpath,"${XILINX_XRT}/lib" \
    -lxrt_core \
    -pthread \
    -ldl \
    -o "${BINARY}" \
    2>&1 | tee "${LOG}"
build_exit="${PIPESTATUS[0]}"
set -e

[[ "${build_exit}" -eq 0 ]] ||
    fail "${build_exit}" "A13 Host compile/link failed; inspect ${LOG}"
[[ -s "${BINARY}" ]] || fail 11 "Host compiler returned success without a binary"

binary_sha256="$(sha256sum "${BINARY}" | awk '{print $1}')"
source_sha256="$(sha256sum "${SOURCE}" | awk '{print $1}')"
compiler_version="$(g++ --version | head -n 1)"

cat > "${STATUS}" <<EOF
A13_HOST_XRT_BUILD=PASS
EXPECTED_XRT_VERSION=${EXPECTED_XRT_VERSION}
XILINX_XRT=${XILINX_XRT}
COMPILER=${compiler_version}
CXX_STANDARD=gnu++11
XRT_LINK_LIBRARIES=xrt_core,pthread,dl
XRT_COREUTIL_LINKED=NO_CANONICAL_LEGACY_HAL_USES_XRT_CORE
SOURCE=${SOURCE}
SOURCE_SHA256=${source_sha256}
BINARY=${BINARY}
BINARY_SHA256=${binary_sha256}
HOST_EXECUTION=NOT_RUN
FPGA_ACCESS=NONE
EOF

echo "A13_HOST_XRT_BUILD=PASS"
echo "BINARY=${BINARY}"
echo "BINARY_SHA256=${binary_sha256}"
echo "HOST_EXECUTION=NOT_RUN"
echo "FPGA_ACCESS=NONE"
