#!/usr/bin/env bash
# Stage 2N-A14.7 build-only Host/XRT API gate.
# This script creates the canonical 1024-byte table payload and compiles/links
# the protected legacy-HAL Host.  It never opens a device or executes the Host.

set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
XRT_SETUP="${XRT_SETUP:-/opt/xilinx/xrt/setup.sh}"
EXPECTED_XRT_VERSION="${EXPECTED_XRT_VERSION:-2.9.210507}"
SOURCE="${REPO_ROOT}/host/stage2n_a14_7_hbm_single_table_board_smoke_v1.cpp"
ASSET_BUILDER="${REPO_ROOT}/python/build_stage2n_a14_7_hbm_table_asset_v1.py"
SOURCE_JSON="${REPO_ROOT}/models/stage2n_a14_embedding_table.json"
BUILD_DIR="${REPO_ROOT}/build/stage2n_a14_7/host_v1"
BINARY="${BUILD_DIR}/stage2n_a14_7_hbm_single_table_board_smoke_v1"
PAYLOAD="${BUILD_DIR}/stage2n_a14_7_hbm_table.bin"
PAYLOAD_MANIFEST="${BUILD_DIR}/stage2n_a14_7_hbm_table_manifest.txt"
LOG="${BUILD_DIR}/host_build.log"
SYMBOL_LOG="${BUILD_DIR}/xrt_symbol_probe.log"
VERSION_LOG="${BUILD_DIR}/xrt_version.log"
STATUS="${BUILD_DIR}/host_build_status.txt"
EXPECTED_PAYLOAD_SHA256="023ad250824def6b538ac40a7f0a9bd457e571136100ab1c1e574769f9061b03"

fail()
{
    local code="$1"
    shift
    echo "A14_7_HOST_XRT_BUILD=FAIL" >&2
    echo "REASON=$*" >&2
    exit "${code}"
}

[[ ! -e "${BUILD_DIR}" ]] ||
    fail 2 "refusing to overwrite existing A14.7 Host build directory: ${BUILD_DIR}"
[[ -s "${SOURCE}" ]] || fail 3 "A14.7 Host source is missing: ${SOURCE}"
[[ -s "${ASSET_BUILDER}" ]] || fail 3 "A14.7 asset builder is missing: ${ASSET_BUILDER}"
[[ -s "${SOURCE_JSON}" ]] || fail 3 "canonical A14 table JSON is missing: ${SOURCE_JSON}"
[[ -f "${XRT_SETUP}" ]] || fail 4 "XRT setup is missing: ${XRT_SETUP}"

mkdir -p "${BUILD_DIR}"
command -v python3 >/dev/null 2>&1 || fail 5 "python3 is unavailable"
command -v sha256sum >/dev/null 2>&1 || fail 5 "sha256sum is unavailable"

python3 "${ASSET_BUILDER}" \
    --input "${SOURCE_JSON}" \
    --output "${PAYLOAD}" \
    --manifest "${PAYLOAD_MANIFEST}" ||
    fail 6 "canonical payload construction/validation failed"

actual_payload_sha256="$(sha256sum "${PAYLOAD}" | awk '{print $1}')"
[[ "${actual_payload_sha256}" == "${EXPECTED_PAYLOAD_SHA256}" ]] ||
    fail 6 "canonical payload SHA256 mismatch: ${actual_payload_sha256}"
[[ "$(stat -c '%s' "${PAYLOAD}")" == "1024" ]] ||
    fail 6 "canonical payload size is not 1024 bytes"

# shellcheck disable=SC1090
source "${XRT_SETUP}" >/dev/null
for tool in g++ nm sha256sum xbutil; do
    command -v "${tool}" >/dev/null 2>&1 || fail 7 "required tool unavailable: ${tool}"
done
[[ -n "${XILINX_XRT:-}" ]] || fail 8 "XILINX_XRT is not set"
[[ -f "${XILINX_XRT}/include/xrt.h" ]] || fail 8 "legacy XRT header xrt.h is missing"
[[ -f "${XILINX_XRT}/include/experimental/xrt-next.h" ]] ||
    fail 8 "XRT experimental/xrt-next.h is missing"
[[ -e "${XILINX_XRT}/lib/libxrt_core.so" ]] || fail 8 "libxrt_core.so is missing"

xbutil --version > "${VERSION_LOG}" 2>&1 || true
if ! grep -Fq "${EXPECTED_XRT_VERSION}" "${VERSION_LOG}"; then
    # Some 2020.2 xbutil builds report the version only through `xbutil version`.
    xbutil version >> "${VERSION_LOG}" 2>&1 || true
fi
grep -Fq "${EXPECTED_XRT_VERSION}" "${VERSION_LOG}" ||
    fail 9 "XRT version does not contain expected ${EXPECTED_XRT_VERSION}; inspect ${VERSION_LOG}"

XRT_SYMBOL_LIBS=("${XILINX_XRT}/lib/libxrt_core.so")
[[ -e "${XILINX_XRT}/lib/libxrt_coreutil.so" ]] &&
    XRT_SYMBOL_LIBS+=("${XILINX_XRT}/lib/libxrt_coreutil.so")
: > "${SYMBOL_LOG}"
for symbol in \
    xclOpen xclClose xclOpenContext xclCloseContext \
    xclIPName2Index xclRegRead xclRegWrite \
    xclAllocBO xclFreeBO xclMapBO xclUnmapBO xclSyncBO xclGetBOProperties
do
    found_library=""
    for library in "${XRT_SYMBOL_LIBS[@]}"; do
        if nm -D --defined-only "${library}" 2>/dev/null |
            awk '{print $NF}' | sed 's/@.*$//' | grep -Fx "${symbol}" >/dev/null
        then
            found_library="${library}"
            break
        fi
    done
    [[ -n "${found_library}" ]] || fail 10 "required XRT 2020.2 symbol is missing: ${symbol}"
    echo "FOUND_SYMBOL=${symbol} LIBRARY=${found_library}" >> "${SYMBOL_LOG}"
done

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
    fail "${build_exit}" "A14.7 Host compile/link failed; inspect ${LOG}"
[[ -s "${BINARY}" ]] || fail 11 "Host compiler returned success without a binary"

binary_sha256="$(sha256sum "${BINARY}" | awk '{print $1}')"
source_sha256="$(sha256sum "${SOURCE}" | awk '{print $1}')"
builder_sha256="$(sha256sum "${ASSET_BUILDER}" | awk '{print $1}')"
json_sha256="$(sha256sum "${SOURCE_JSON}" | awk '{print $1}')"
compiler_version="$(g++ --version | head -n 1)"

cat > "${STATUS}" <<EOF
A14_7_HOST_XRT_BUILD=PASS
A14_7_XRT2020_2_API_PROBE=PASS
A14_7_CANONICAL_PAYLOAD=PASS
EXPECTED_XRT_VERSION=${EXPECTED_XRT_VERSION}
XILINX_XRT=${XILINX_XRT}
COMPILER=${compiler_version}
CXX_STANDARD=gnu++11
SOURCE=${SOURCE}
SOURCE_SHA256=${source_sha256}
ASSET_BUILDER=${ASSET_BUILDER}
ASSET_BUILDER_SHA256=${builder_sha256}
SOURCE_JSON=${SOURCE_JSON}
SOURCE_JSON_SHA256=${json_sha256}
PAYLOAD=${PAYLOAD}
PAYLOAD_BYTES=1024
PAYLOAD_SHA256=${actual_payload_sha256}
PAYLOAD_FNV1A64=40a53c3698b88325
BINARY=${BINARY}
BINARY_SHA256=${binary_sha256}
XRT_SYMBOL_LOG=${SYMBOL_LOG}
XRT_VERSION_LOG=${VERSION_LOG}
HOST_EXECUTION=NOT_RUN
FPGA_PROGRAMMING=NOT_RUN
PHYSICAL_HBM=NOT_RUN
FPGA_DEVICE_ACCESS=NONE
EOF

echo "A14_7_HOST_XRT_BUILD=PASS"
echo "A14_7_XRT2020_2_API_PROBE=PASS"
echo "A14_7_CANONICAL_PAYLOAD=PASS"
echo "BINARY=${BINARY}"
echo "BINARY_SHA256=${binary_sha256}"
echo "PAYLOAD=${PAYLOAD}"
echo "PAYLOAD_SHA256=${actual_payload_sha256}"
echo "HOST_EXECUTION=NOT_RUN"
echo "FPGA_DEVICE_ACCESS=NONE"
