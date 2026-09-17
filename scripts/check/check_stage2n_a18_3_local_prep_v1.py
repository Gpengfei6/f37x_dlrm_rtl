#!/usr/bin/env python3
"""Static gate for A18.3 index-tuple Host source. Not compile, not board PASS."""
from __future__ import print_function

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


class CheckError(Exception):
    pass


def require(condition, message):
    if not condition:
        raise CheckError(message)


def main():
    extras = json.loads(
        (ROOT / "models/stage2n_a18_2/index_goldens_v1.json").read_text(
            encoding="utf-8"))
    require(extras.get("schema") == "a18_2_index_goldens_v1", "golden schema")
    locked = {
        (1, 2, 3, 4): -61,
        (0, 0, 0, 0): -60,
        (0, 63, 37, 40): -162,
        (63, 62, 61, 60): -185,
    }
    found = {}
    for row in extras.get("extras", []):
        key = tuple(row["indexes"])
        found[key] = row["expected_final_result"]
        require("20260917_202130" in row.get("note", ""),
                "boarded extra must cite 20260917_202130")
    for key, value in locked.items():
        require(found.get(key) == value, "missing extra golden %s" % (key,))

    a18_2 = (ROOT / "host/stage2n_a18_2_four_bo_host_v1.cpp").read_text(
        encoding="utf-8")
    require(
        "non-default board compares are not authorized in this file" in a18_2,
        "A18.2 Host must keep the second non-default lock")
    require("kExpectedPipeVersion = 0x00024E18" in a18_2, "A18.2 version")

    host_path = ROOT / "host/stage2n_a18_3_index_tuple_host_v1.cpp"
    require(host_path.is_file(), "A18.3 Host missing")
    host = host_path.read_text(encoding="utf-8")
    for token in (
        "dlrm_f37x_rtl_kernel_stage2n_a18_v1:dlrm_a18_1",
        "kExpectedPipeVersion = 0x00024E18",
        "0x330",
        "0x334",
        "0x338",
        "0x33C",
        "write_and_readback_indexes",
        "load_baseline_all",
        "A18_2_MEM_MAP_V1",
        "xclRegWrite",
        "xclOpen",
        "-393, -61, -60, -162, -185",
        "1u, 2u, 3u, 4u",
        "63u, 62u, 61u, 60u",
        "OOB lookup index is not a passing A18.3 tuple",
        "PER_BO_LAYOUT=baseline_table_on_all_four_banks",
        "SOFTWARE_GOLDENS_NOT_BOARD_PASS=1",
        "A18_3_PERFORMANCE=NOT_CLAIMED",
        "STAGE2N_A18_3_INDEX_TUPLE_HOST_V1=PASS",
    ):
        require(token in host, "A18.3 Host token missing: " + token)
    require("load_restored_case" not in host, "A18.3 must not mutate slot images")
    require("slot0_sensitivity" not in host, "A18.3 must not use sensitivity cases")
    require("xclSetKernelArg" not in host, "indexes must not be kernel arguments")
    require("xbutil" not in host.lower(), "A18.3 Host must not call xbutil")
    require("argc != 7" in host, "A18.3 usage is six path args plus argv0")

    build = (ROOT / "scripts/build_stage2n_a18_3_host_v1.sh").read_text(
        encoding="utf-8")
    require("HOST_EXECUTION=NOT_RUN" in build, "Host build must not execute")
    require("XBUTIL=NOT_INVOKED" in build, "Host build must not call xbutil")
    require("stage2n_a18_3_index_tuple_host_v1.cpp" in build, "build script source")
    require("A18_3_HOST_XRT_BUILD=PASS" in build, "A18.3 build token")

    kernel = (ROOT / "rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a18_v1.sv").read_text(
        encoding="utf-8")
    for token in ("12'h330", "12'h334", "12'h338", "12'h33C", "32'h0002_4E18"):
        require(token in kernel, "kernel token missing: " + token)

    leftover = ROOT / "rtl/f37x/dlrm_internal_pipeline_axi_lite_decode_stage2n_a18_v1.sv"
    if leftover.exists():
        integ = (ROOT / "rtl/pipeline/dlrm_hbm_pipeline_integration_stage2n_a18_v1.sv").read_text(
            encoding="utf-8")
        require("dlrm_internal_pipeline_axi_lite_decode_stage2n_a18_v1" not in integ,
                "leftover decode instantiated")
        require("dlrm_internal_pipeline_axi_lite_decode_stage2n_a18_v1" not in kernel,
                "leftover decode instantiated")

    print("A18_3_LOCAL_PREP_CHECK=PASS")
    print("A18_3_HOST_CPP=PRESENT")
    print("A18_3_THIS_CHECKER=SOURCE_ONLY")
    print("A18_3_BOARD_FUNCTION=SEE_FUNCTION_ACCEPTANCE")
    print("A18_3_PERFORMANCE=NOT_CLAIMED")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except CheckError as exc:
        print("A18_3_LOCAL_PREP_CHECK=FAIL")
        print(exc)
        sys.exit(1)
