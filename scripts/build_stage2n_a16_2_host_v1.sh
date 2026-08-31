#!/usr/bin/env bash
# Build-only XRT 2020.2 gate for the A16.2 protected latency Host.
# This script never opens a device or executes the Host.

set -Eeuo pipefail
SELF_SCRIPT="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd "$(dirname "${SELF_SCRIPT}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
XRT_SETUP="${XRT_SETUP:-/opt/xilinx/xrt/setup.sh}"
EXPECTED_XRT_VERSION="${EXPECTED_XRT_VERSION:-2.9.210507}"
SOURCE="${REPO_ROOT}/host/stage2n_a16_2_physical_latency_v1.cpp"
BUILD_DIR="${REPO_ROOT}/build/stage2n_a16_2/host_v1"
BINARY="${BUILD_DIR}/stage2n_a16_2_physical_latency_v1"
LOG="${BUILD_DIR}/host_build.log"
SYMBOL_LOG="${BUILD_DIR}/xrt_symbol_probe.log"
VERSION_LOG="${BUILD_DIR}/xrt_version.log"
STATUS="${BUILD_DIR}/host_build_status.txt"

fail()
{
    local code="$1"; shift
    echo "A16_2_HOST_XRT_BUILD=FAIL" >&2
    echo "REASON=$*" >&2
    exit "${code}"
}

[[ -s "${SOURCE}" ]] || fail 3 "A16.2 Host source is missing"
[[ -f "${XRT_SETUP}" ]] || fail 4 "XRT setup is missing: ${XRT_SETUP}"
if [[ -e "${BUILD_DIR}" ]]; then
    [[ "${A16_2_ALLOW_HOST_REBUILD:-no}" == "yes" ]] ||
        fail 2 "Host build directory exists; set A16_2_ALLOW_HOST_REBUILD=yes only to rebuild this Host"
    rm -f "${BINARY}" "${LOG}" "${SYMBOL_LOG}" "${VERSION_LOG}" "${STATUS}"
else
    mkdir -p "${BUILD_DIR}"
fi

set +u
# shellcheck disable=SC1090
source "${XRT_SETUP}" >/dev/null
set -u
for tool in g++ nm sha256sum xbutil; do
    command -v "${tool}" >/dev/null 2>&1 || fail 5 "required tool unavailable: ${tool}"
done
[[ -n "${XILINX_XRT:-}" ]] || fail 6 "XILINX_XRT is not set"
[[ -f "${XILINX_XRT}/include/xrt.h" ]] || fail 6 "xrt.h is missing"
[[ -f "${XILINX_XRT}/include/experimental/xrt-next.h" ]] || fail 6 "xrt-next.h is missing"
[[ -e "${XILINX_XRT}/lib/libxrt_core.so" ]] || fail 6 "libxrt_core.so is missing"

xbutil --version > "${VERSION_LOG}" 2>&1 || true
xbutil version >> "${VERSION_LOG}" 2>&1 || true
grep -Fq "${EXPECTED_XRT_VERSION}" "${VERSION_LOG}" ||
    fail 7 "XRT version does not contain ${EXPECTED_XRT_VERSION}"

XRT_SYMBOL_LIBS=("${XILINX_XRT}/lib/libxrt_core.so")
[[ -e "${XILINX_XRT}/lib/libxrt_coreutil.so" ]] &&
    XRT_SYMBOL_LIBS+=("${XILINX_XRT}/lib/libxrt_coreutil.so")
: > "${SYMBOL_LOG}"
for symbol in \
    xclOpen xclClose xclOpenContext xclCloseContext \
    xclIPName2Index xclRegRead xclRegWrite \
    xclAllocBO xclFreeBO xclMapBO xclUnmapBO xclSyncBO xclGetBOProperties
do
    found=""
    for library in "${XRT_SYMBOL_LIBS[@]}"; do
        if nm -D --defined-only "${library}" 2>/dev/null |
            awk '{print $NF}' | sed 's/@.*$//' | grep -Fx "${symbol}" >/dev/null
        then
            found="${library}"; break
        fi
    done
    [[ -n "${found}" ]] || fail 8 "required XRT symbol is missing: ${symbol}"
    echo "FOUND_SYMBOL=${symbol} LIBRARY=${found}" >> "${SYMBOL_LOG}"
done

set +e
g++ -std=gnu++11 -O2 -Wall -Wextra -Wpedantic \
    -I"${XILINX_XRT}/include" "${SOURCE}" \
    -L"${XILINX_XRT}/lib" -Wl,-rpath,"${XILINX_XRT}/lib" \
    -lxrt_core -pthread -ldl -o "${BINARY}" 2>&1 | tee "${LOG}"
build_exit="${PIPESTATUS[0]}"
set -e
[[ "${build_exit}" -eq 0 ]] || fail "${build_exit}" "A16.2 Host compile/link failed"
[[ -s "${BINARY}" ]] || fail 9 "compiler returned success without binary"

source_sha="$(sha256sum "${SOURCE}" | awk '{print $1}')"
binary_sha="$(sha256sum "${BINARY}" | awk '{print $1}')"
cat > "${STATUS}" <<EOF
A16_2_HOST_XRT_BUILD=PASS
A16_2_XRT2020_2_API_PROBE=PASS
EXPECTED_XRT_VERSION=${EXPECTED_XRT_VERSION}
CXX_STANDARD=gnu++11
SOURCE=${SOURCE}
SOURCE_SHA256=${source_sha}
BINARY=${BINARY}
BINARY_SHA256=${binary_sha}
HOST_EXECUTION=NOT_RUN
FPGA_PROGRAMMING=NOT_RUN
PHYSICAL_HBM=NOT_RUN
FPGA_DEVICE_ACCESS=NONE
EOF
echo "A16_2_HOST_XRT_BUILD=PASS"
echo "A16_2_XRT2020_2_API_PROBE=PASS"
echo "BINARY=${BINARY}"
echo "BINARY_SHA256=${binary_sha}"
echo "HOST_EXECUTION=NOT_RUN"
echo "FPGA_DEVICE_ACCESS=NONE"
