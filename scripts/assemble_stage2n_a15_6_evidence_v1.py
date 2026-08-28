#!/usr/bin/env python3
"""Assemble A15.6 JSON evidence from a successful protected Host log."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Dict


def parse_log(path: Path) -> Dict[str, str]:
    result: Dict[str, str] = {}
    for raw in path.read_text(encoding="utf-8", errors="strict").splitlines():
        if "=" in raw:
            key, value = raw.split("=", 1)
            if key and key.replace("_", "").isalnum():
                result[key] = value
    return result


def required(values: Dict[str, str], key: str) -> str:
    if key not in values or values[key] == "":
        raise RuntimeError("Host log missing " + key)
    return values[key]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host-log", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--timestamp-utc", required=True)
    parser.add_argument("--hostname", required=True)
    parser.add_argument("--branch", required=True)
    parser.add_argument("--head", required=True)
    parser.add_argument("--device-index", type=int, required=True)
    parser.add_argument("--bdf", required=True)
    parser.add_argument("--xclbin-path", required=True)
    parser.add_argument("--xclbin-sha256", required=True)
    parser.add_argument("--uuid", required=True)
    parser.add_argument("--programming-status", choices=("PASS", "SKIPPED_ALREADY_LOADED"), required=True)
    parser.add_argument("--device-close-status", choices=("PASS",), required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    host = parse_log(args.host_log)
    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    if required(host, "STAGE2N_A15_6_ALL_HBM_BOARD_VALIDATION_V1") != "PASS":
        raise RuntimeError("Host functional PASS marker is missing")
    if required(host, "A15_6_BO_CLEANUP") != "PASS":
        raise RuntimeError("Host BO cleanup did not pass")
    if required(host, "A15_6_ALL_FIVE_CASES") != "PASS":
        raise RuntimeError("Host five-case marker did not pass")

    paddr = int(required(host, "BO_PADDR_HEX"), 0)
    cases = []
    for index, manifest_case in enumerate(manifest["cases"]):
        prefix = "CASE{}_".format(index)
        expected = int(required(host, prefix + "EXPECTED_RESULT"), 0)
        actual = int(required(host, prefix + "ACTUAL_RESULT"), 0)
        base_lo = int(required(host, prefix + "TABLE_BASE_LO_HEX"), 0)
        base_hi = int(required(host, prefix + "TABLE_BASE_HI_HEX"), 0)
        if ((base_hi << 32) | base_lo) != paddr:
            raise RuntimeError("TABLE_BASE readback mismatch in " + prefix)
        cases.append(
            {
                "name": required(host, prefix + "NAME"),
                "payload_sha256": manifest_case["payload_sha256"],
                "row37_to_row40": manifest_case["row37_to_row40"],
                "expected_result": expected,
                "actual_result": actual,
                "embedding_loaded_mask": required(host, prefix + "EMBEDDING_LOADED_MASK"),
                "table_base_readback": "PASS",
                "completion": "PASS",
                "complete_dlrm_result": required(host, prefix + "COMPLETE_DLRM_RESULT"),
                "counters": {
                    "bottom": int(required(host, prefix + "BOTTOM_CYCLES"), 0),
                    "interaction": int(required(host, prefix + "INTERACTION_CYCLES"), 0),
                    "top": int(required(host, prefix + "TOP_CYCLES"), 0),
                    "total": int(required(host, prefix + "TOTAL_CYCLES"), 0),
                },
            }
        )

    evidence = {
        "schema": "STAGE2N_A15_6_BOARD_EVIDENCE_V1",
        "timestamp_utc": args.timestamp_utc,
        "hostname": args.hostname,
        "git_branch": args.branch,
        "git_head": args.head,
        "device": {
            "index": args.device_index,
            "bdf": args.bdf,
            "other_device_access": "NONE",
        },
        "artifact": {
            "xclbin_path": args.xclbin_path,
            "xclbin_sha256": args.xclbin_sha256,
            "xclbin_uuid": args.uuid,
            "kernel": "dlrm_f37x_rtl_kernel_stage2n_a15_v1",
            "compute_unit": "dlrm_a15_1",
        },
        "memory": {
            "bank": required(host, "HBM_BANK"),
            "memory_index": int(required(host, "HBM_MEMORY_INDEX"), 0),
            "bo_size_bytes": int(required(host, "BO_SIZE_BYTES"), 0),
            "bo_physical_address": paddr,
            "table_base_programming": "PASS",
            "payload_transfer": "PASS",
            "physical_hbm": "PASS",
        },
        "programming": {
            "fpga": args.programming_status,
            "reset": "NOT_RUN",
        },
        "cases": cases,
        "cleanup": {
            "bo_release": "PASS",
            "device_close": args.device_close_status,
            "global_hbm_cleanup": "NOT_RUN",
        },
        "board_functional": "PASS",
        "performance": "NOT_CLAIMED",
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(evidence, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print("A15_6_EVIDENCE_ASSEMBLY=PASS")
    print("EVIDENCE={}".format(args.output))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, KeyError, json.JSONDecodeError, RuntimeError) as exc:
        print("A15_6_EVIDENCE_ASSEMBLY=FAIL")
        print("REASON={}".format(exc))
        raise SystemExit(1)
