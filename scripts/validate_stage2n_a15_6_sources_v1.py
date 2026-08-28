#!/usr/bin/env python3
"""Static local validator for A15.6 sources and generated assets."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Dict, Any


EXPECTED_RTL_SHA256 = "c3da5be63d4cf195df124e572887b6aa96a464522883c6cdc95c4bd56ff4e8a1"
EXPECTED_XCLBIN_SHA256 = "23ee48c91b3dfb5b68b3372ac49fc6607f203cf01d3b9fcfe04b4ea42be02356"
EXPECTED_UUID = "1b555645-a9e2-4f5e-95af-6ce4adacbc3c"


class ValidationError(RuntimeError):
    pass


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValidationError(message)


def load_manifest(path: Path) -> Dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    require(value.get("format") == "STAGE2N_A15_6_CASES_V1", "manifest format")
    return value


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", type=Path, default=Path("."))
    args = parser.parse_args()
    repo = args.repo.resolve()
    manifest_path = repo / "models/stage2n_a15_6/stage2n_a15_6_cases_v1.json"
    manifest = load_manifest(manifest_path)
    model = repo / "models/stage2n_a15_6" / manifest["model_asset"]["file"]
    require(digest(model) == manifest["model_asset"]["sha256"], "model asset SHA")
    require(model.stat().st_size == manifest["model_asset"]["bytes"], "model bytes")
    cases = manifest.get("cases", [])
    require(len(cases) == 5, "case count")
    for case in cases:
        table = repo / "models/stage2n_a15_6" / case["file"]
        require(table.stat().st_size == 1024, "table bytes " + case["name"])
        require(digest(table) == case["payload_sha256"], "table SHA " + case["name"])
    baseline = cases[0]["expected_final_result"]
    require(all(case["expected_final_result"] != baseline for case in cases[1:]),
            "slot sensitivity result")
    require(len({case["expected_final_result"] for case in cases[1:]}) == 4,
            "distinct sensitivity results")

    rtl = repo / "rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a15_v1.sv"
    require(digest(rtl) == EXPECTED_RTL_SHA256, "accepted A15.4 RTL SHA")
    host = (repo / "host/stage2n_a15_6_all_hbm_board_validation_v1.cpp").read_text(encoding="utf-8")
    runner = (repo / "scripts/program_and_run_stage2n_a15_6_all_hbm_board_validation_v1.sh").read_text(encoding="utf-8")
    for token in (
        "dlrm_f37x_rtl_kernel_stage2n_a15_v1:dlrm_a15_1",
        "A_TABLE_BASE_LO = 0x304", "A_TABLE_BASE_HI = 0x308",
        "A_BOTTOM_CYCLES = 0x218", "A_TOTAL_CYCLES = 0x224",
        "A15_CMD_START = 0x0001", "A15_CMD_CLEAR = 0x0002",
        "xclAllocBO", "xclGetBOProperties", "xclMapBO", "xclSyncBO",
        "xclUnmapBO", "xclFreeBO",
        "A physical address of zero is valid on the accepted A14.7 path",
    ):
        require(token in host, "Host token missing: " + token)
    for token in (
        EXPECTED_XCLBIN_SHA256, EXPECTED_UUID,
        "dlrm_f37x_rtl_kernel_stage2n_a15_v1", "dlrm_a15_1",
        "HBM[0]", "read -r -p", '!= "yes"', "xbutil program",
        "NO FPGA RESET", "A15_6_TARGET_INDEX",
    ):
        require(token in runner, "runner token missing: " + token)
    program_pos = runner.index("xbutil program")
    confirmation_pos = runner.index('!= "yes"')
    require(confirmation_pos < program_pos, "authorization gate must precede programming")
    require("xbutil reset" not in runner and "xbmgmt reset" not in runner,
            "runner contains reset")
    require("git clean" not in runner and "git reset --hard" not in runner,
            "runner contains destructive Git")

    print("A15_6_SOURCE_VALIDATION=PASS")
    print("A15_6_ACCEPTED_RTL_SHA256=PASS")
    print("A15_6_MODEL_ASSET=PASS")
    print("A15_6_FIVE_TABLES=PASS")
    print("A15_6_FOUR_SLOT_SENSITIVITY=PASS")
    print("A15_6_XRT_API_REUSE=PASS")
    print("A15_6_PROTECTION_GATE_ORDER=PASS")
    print("A15_6_RESET_ABSENT=PASS")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, KeyError, json.JSONDecodeError, ValidationError) as exc:
        print("A15_6_SOURCE_VALIDATION=FAIL", file=sys.stderr)
        print("REASON={}".format(exc), file=sys.stderr)
        raise SystemExit(1)
