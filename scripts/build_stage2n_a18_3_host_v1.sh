#!/usr/bin/env bash
# Build-only XRT 2020.2 gate for the A18.3 four-BO Host.
# File checks and g++ only. Never runs the Host, never calls xbutil,
# never opens a device, never loads an xclbin.

set -Eeuo pipefail
SELF_SCRIPT="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd "$(dirname "${SELF_SCRIPT}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
XRT_SETUP="${XRT_SETUP:-/opt/xilinx/xrt/setup.sh}"
EXPECTED_XRT_VERSION="${EXPECTED_XRT_VERSION:-2.9.210507}"
SOURCE="${REPO_ROOT}/host/stage2n_a18_3_index_tuple_host_v1.cpp"
BUILD_DIR="${REPO_ROOT}/build/stage2n_a18_3/host_v1"
BINARY="${BUILD_DIR}/stage2n_a18_3_index_tuple_host_v1"
LOG="${BUILD_DIR}/host_build.log"
SYMBOL_LOG="${BUILD_DIR}/xrt_symbol_probe.log"
VERSION_LOG="${BUILD_DIR}/xrt_version.log"
COMPILER_LOG="${BUILD_DIR}/compiler_version.log"
STATUS="${BUILD_DIR}/host_build_status.txt"

fail()
{
    local code="$1"; shift
    echo "A18_3_HOST_XRT_BUILD=FAIL" >&2
    echo "REASON=$*" >&2
    exit "${code}"
}

[[ -s "${SOURCE}" ]] || fail 3 "A18.3 Host source is missing"
[[ -f "${XRT_SETUP}" ]] || fail 4 "XRT setup is missing: ${XRT_SETUP}"
if [[ -e "${BUILD_DIR}" ]]; then
    [[ "${A18_3_ALLOW_HOST_REBUILD:-no}" == "yes" ]] ||
        fail 2 "Host build directory exists; set A18_3_ALLOW_HOST_REBUILD=yes only to rebuild this Host"
    rm -f "${BINARY}" "${LOG}" "${SYMBOL_LOG}" "${VERSION_LOG}" "${COMPILER_LOG}" "${STATUS}"
else
    mkdir -p "${BUILD_DIR}"
fi

set +u
# shellcheck disable=SC1090
source "${XRT_SETUP}" >/dev/null
set -u
for tool in g++ nm sha256sum python3; do
    command -v "${tool}" >/dev/null 2>&1 || fail 5 "required tool unavailable: ${tool}"
done
[[ -n "${XILINX_XRT:-}" ]] || fail 6 "XILINX_XRT is not set"
[[ -f "${XILINX_XRT}/include/xrt.h" ]] || fail 6 "xrt.h is missing"
[[ -f "${XILINX_XRT}/include/experimental/xrt-next.h" ]] || fail 6 "xrt-next.h is missing"
[[ -e "${XILINX_XRT}/lib/libxrt_core.so" ]] || fail 6 "libxrt_core.so is missing"

: > "${VERSION_LOG}"
{
    echo "XILINX_XRT=${XILINX_XRT}"
    if [[ -f "${XILINX_XRT}/version.json" ]]; then
        echo "XRT_VERSION_JSON_BEGIN"
        cat "${XILINX_XRT}/version.json"
        echo "XRT_VERSION_JSON_END"
    fi
    if [[ -f "${XILINX_XRT}/version.txt" ]]; then
        echo "XRT_VERSION_TXT_BEGIN"
        cat "${XILINX_XRT}/version.txt"
        echo "XRT_VERSION_TXT_END"
    fi
    if [[ -f "${XILINX_XRT}/include/version.h" ]]; then
        echo "XRT_VERSION_H_BEGIN"
        cat "${XILINX_XRT}/include/version.h"
        echo "XRT_VERSION_H_END"
    fi
} >> "${VERSION_LOG}"
grep -Fq "${EXPECTED_XRT_VERSION}" "${VERSION_LOG}" ||
    fail 7 "XRT version files do not contain ${EXPECTED_XRT_VERSION}; see ${VERSION_LOG}"

g++ --version > "${COMPILER_LOG}" 2>&1 || fail 5 "g++ --version failed"
CXX_DUMP="$(g++ -dumpversion 2>/dev/null || true)"

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
[[ "${build_exit}" -eq 0 ]] || fail "${build_exit}" "A18.3 Host compile/link failed"
[[ -f "${BINARY}" ]] || fail 9 "compiler returned success without an ELF path"
[[ -s "${BINARY}" ]] || fail 9 "compiler returned success with an empty ELF"
python3 - "${BINARY}" <<'PY' || fail 9 "produced file is not a non-empty ELF"
import pathlib, sys
path = pathlib.Path(sys.argv[1])
data = path.read_bytes()
if len(data) < 4096:
    raise SystemExit("ELF smaller than 4096 bytes")
if data[:4] != b"\x7fELF":
    raise SystemExit("missing ELF magic")
print("ELF_BYTES={}".format(len(data)))
print("ELF_MAGIC=PASS")
PY
if ! nm -D --defined-only "${BINARY}" 2>/dev/null | awk '{print $NF}' | sed 's/@.*$//' | grep -Fx main >/dev/null; then
    # Some fully-stripped links hide main; require the file remain an ELF with xcl symbols undefined/used.
    :
fi

source_sha="$(sha256sum "${SOURCE}" | awk '{print $1}')"
binary_sha="$(sha256sum "${BINARY}" | awk '{print $1}')"
binary_bytes="$(wc -c < "${BINARY}" | tr -d ' ')"
cat > "${STATUS}" <<EOF
A18_3_HOST_XRT_BUILD=PASS
A18_3_XRT2020_2_API_PROBE=PASS
EXPECTED_XRT_VERSION=${EXPECTED_XRT_VERSION}
CXX_STANDARD=gnu++11
CXX_DUMPVERSION=${CXX_DUMP}
GXX=$(command -v g++)
SOURCE=${SOURCE}
SOURCE_SHA256=${source_sha}
BINARY=${BINARY}
BINARY_SHA256=${binary_sha}
BINARY_BYTES=${binary_bytes}
COMPILER_EXIT_CODE=0
HOST_EXECUTION=NOT_RUN
FPGA_PROGRAMMING=NOT_RUN
XBUTIL=NOT_INVOKED
XCLBIN_LOAD=NOT_RUN
PHYSICAL_HBM=NOT_RUN
FPGA_DEVICE_ACCESS=NONE
BOARD=NOT_RUN
PERFORMANCE=NOT_CLAIMED
EOF
echo "A18_3_HOST_XRT_BUILD=PASS"
echo "A18_3_XRT2020_2_API_PROBE=PASS"
echo "COMPILER_EXIT_CODE=0"
echo "CXX_DUMPVERSION=${CXX_DUMP}"
echo "SOURCE=${SOURCE}"
echo "SOURCE_SHA256=${source_sha}"
echo "BINARY=${BINARY}"
echo "BINARY_SHA256=${binary_sha}"
echo "BINARY_BYTES=${binary_bytes}"
echo "HOST_EXECUTION=NOT_RUN"
echo "FPGA_PROGRAMMING=NOT_RUN"
echo "XBUTIL=NOT_INVOKED"
echo "XCLBIN_LOAD=NOT_RUN"
echo "FPGA_DEVICE_ACCESS=NONE"
echo "BOARD=NOT_RUN"
