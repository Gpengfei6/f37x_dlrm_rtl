#!/usr/bin/env python3
"""Static gate for A18.3 local prep. Not Host compile, not board PASS."""
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
    require(list(extras.get("default_indexes")) == [37, 38, 39, 40], "defaults")
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
        require("not a board result" in row.get("note", ""), "extras must stay software-only")
    for key, value in locked.items():
        require(found.get(key) == value, "missing extra golden %s" % (key,))

    host = (ROOT / "host/stage2n_a18_2_four_bo_host_v1.cpp").read_text(
        encoding="utf-8")
    require(
        "non-default board compares are not authorized in this file" in host,
        "A18.2 Host must keep the second non-default lock")
    require("kExpectedPipeVersion = 0x00024E18" in host, "A18.2 version")
    a18_3_host = ROOT / "host/stage2n_a18_3_index_tuple_host_v1.cpp"
    require(not a18_3_host.exists(), "A18.3 Host must not appear until a later increment")

    kernel = (ROOT / "rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a18_v1.sv").read_text(
        encoding="utf-8")
    for token in ("12'h330", "12'h334", "12'h338", "12'h33C", "32'h0002_4E18"):
        require(token in kernel, "kernel token missing: " + token)

    leftover = ROOT / "rtl/f37x/dlrm_internal_pipeline_axi_lite_decode_stage2n_a18_v1.sv"
    if leftover.exists():
        integ = (ROOT / "rtl/pipeline/dlrm_hbm_pipeline_integration_stage2n_a18_v1.sv").read_text(
            encoding="utf-8")
        top = kernel
        require("dlrm_internal_pipeline_axi_lite_decode_stage2n_a18_v1" not in integ, "leftover decode instantiated")
        require("dlrm_internal_pipeline_axi_lite_decode_stage2n_a18_v1" not in top, "leftover decode instantiated")

    print("A18_3_LOCAL_PREP_CHECK=PASS")
    print("A18_3_HOST_CPP=NOT_CREATED")
    print("A18_3_BOARD=NOT_RUN")
    print("A18_3_PERFORMANCE=NOT_CLAIMED")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except CheckError as exc:
        print("A18_3_LOCAL_PREP_CHECK=FAIL")
        print(exc)
        sys.exit(1)
