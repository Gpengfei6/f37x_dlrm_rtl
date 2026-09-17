#!/usr/bin/env python3
"""A18.3 board-tree prepare check. No A11 import, no v++/xbutil."""
from __future__ import print_function

import argparse
import sys
from pathlib import Path

ROOT_DEFAULT = Path(__file__).resolve().parents[2]


class CheckError(Exception):
    pass


def require(condition, message):
    if not condition:
        raise CheckError(message)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", type=Path, default=ROOT_DEFAULT)
    args = parser.parse_args()
    repo = args.repo.resolve()

    a18_2 = (repo / "host/stage2n_a18_2_four_bo_host_v1.cpp").read_text(encoding="utf-8")
    require(
        "non-default board compares are not authorized in this file" in a18_2,
        "A18.2 Host lock missing")

    host = (repo / "host/stage2n_a18_3_index_tuple_host_v1.cpp").read_text(encoding="utf-8")
    for token in (
        "dlrm_f37x_rtl_kernel_stage2n_a18_v1:dlrm_a18_1",
        "kExpectedPipeVersion = 0x00024E18",
        "load_baseline_all",
        "A18_2_MEM_MAP_V1",
        "-393, -61, -60, -162, -185",
        "SOFTWARE_GOLDENS_NOT_BOARD_PASS=1",
        "STAGE2N_A18_3_INDEX_TUPLE_HOST_V1=PASS",
    ):
        require(token in host, "A18.3 Host token missing: " + token)
    require("load_restored_case" not in host, "A18.3 must not mutate slot images")
    require("xclSetKernelArg" not in host, "indexes must not be kernel arguments")
    require("xbutil" not in host.lower(), "A18.3 Host must not call xbutil")

    model = repo / "models/stage2n_a15_6/stage2n_a15_6_model_v1.bin"
    baseline = repo / "models/stage2n_a15_6/stage2n_a15_6_case0_baseline_table_v1.bin"
    require(model.is_file() and model.stat().st_size > 0, "A15.6 model.bin missing")
    require(baseline.is_file() and baseline.stat().st_size == 1024, "baseline table must be 1024 bytes")
    require((repo / "scripts/parse_stage2n_a18_2_xclbin_map_v1.py").is_file(), "A18.2 map parser missing")

    print("A18_3_BOARD_PREPARE_CHECK=PASS")
    print("A18_3_HOST_ABI=PASS")
    print("A18_3_BASELINE_TABLE=PASS")
    print("A18_3_BOARD=NOT_RUN")
    print("A18_3_PERFORMANCE=NOT_CLAIMED")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except CheckError as error:
        print("A18_3_BOARD_PREPARE_CHECK=FAIL", file=sys.stderr)
        print("REASON={}".format(error), file=sys.stderr)
        sys.exit(1)
