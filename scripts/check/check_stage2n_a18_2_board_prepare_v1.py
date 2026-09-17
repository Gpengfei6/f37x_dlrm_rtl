#!/usr/bin/env python3
"""A18.2 board-tree prepare check. Does not import A11 builders or run v++/xbutil.

The Windows local-prep checker recomputes software extras and needs the A11
asset module. The F37X extract does not ship that module. This checker only
locks Host ABI tokens, frozen A15.6 five-case goldens, and the closed XO
source hashes already on the extract.
"""
from __future__ import print_function

import argparse
import json
import sys
from pathlib import Path

ROOT_DEFAULT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT_DEFAULT / "scripts"))

from validate_stage2n_a18_2_artifacts_v1 import (  # noqa: E402
    KERNEL, CU, digest, source_check,
)


LOCKED_GOLDENS = (-393, -392, -93, -689, -519)
LOCKED_NAMES = (
    "baseline", "slot0_sensitivity", "slot1_sensitivity",
    "slot2_sensitivity", "slot3_sensitivity",
)


class CheckError(Exception):
    pass


def require(condition, message):
    if not condition:
        raise CheckError(message)


def check_host(repo):
    host = (repo / "host/stage2n_a18_2_four_bo_host_v1.cpp").read_text(encoding="utf-8")
    for token in (
        "dlrm_f37x_rtl_kernel_stage2n_a18_v1:dlrm_a18_1",
        "kExpectedPipeVersion = 0x00024E18",
        "0x330",
        "0x334",
        "0x338",
        "0x33C",
        "write_and_readback_indexes",
        "kDefaultLookupIndexes",
        "A18_2_MEM_MAP_V1",
        "XSim result 36 is not a board golden",
        "-393, -392, -93, -689, -519",
        "kRejectedA17Needle",
    ):
        require(token in host, "Host token missing: " + token)
    require("kExpectedPipeVersion = 0x00024E17" not in host, "Host still uses A17 version")
    require("xclSetKernelArg" not in host, "indexes must not be kernel arguments")


def check_cases(repo):
    manifest = json.loads(
        (repo / "models/stage2n_a15_6/stage2n_a15_6_cases_v1.json").read_text(
            encoding="utf-8"))
    cases = manifest["cases"]
    require(len(cases) == 5, "expected five A15.6 cases")
    model = repo / "models/stage2n_a15_6/stage2n_a15_6_model_v1.bin"
    require(model.is_file() and model.stat().st_size > 0, "A15.6 model.bin missing")
    for index, case in enumerate(cases):
        require(case["name"] == LOCKED_NAMES[index], "case name mismatch")
        require(case["expected_final_result"] == LOCKED_GOLDENS[index],
                "locked golden mismatch")
        table = repo / "models/stage2n_a15_6" / case["file"]
        require(table.is_file() and table.stat().st_size == 1024,
                "table missing or not 1024 bytes: " + case["file"])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", type=Path, default=ROOT_DEFAULT)
    args = parser.parse_args()
    repo = args.repo.resolve()
    source_check(repo)
    check_host(repo)
    check_cases(repo)
    print("A18_2_BOARD_PREPARE_CHECK=PASS")
    print("A18_2_SOURCE_INTEGRITY=PASS")
    print("A18_2_HOST_ABI=PASS")
    print("A18_2_GOLDEN_LOCK=PASS")
    print("KERNEL={}".format(KERNEL))
    print("CU={}".format(CU))
    print("MANIFEST_SHA256={}".format(digest(repo / "config/stage2n_a18_2_sources_v1.json")))
    print("A18_2_BOARD=NOT_RUN")
    print("A18_2_PERFORMANCE=NOT_CLAIMED")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except CheckError as error:
        print("A18_2_BOARD_PREPARE_CHECK=FAIL", file=sys.stderr)
        print("REASON={}".format(error), file=sys.stderr)
        sys.exit(1)
