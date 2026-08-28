#!/usr/bin/env python3
"""Validate Stage 2N-A15.6 protected-board JSON evidence offline."""

from __future__ import annotations

import argparse
import copy
import json
import re
import sys
import tempfile
from pathlib import Path
from typing import Any, Dict, List


EXPECTED_XCLBIN_SHA256 = (
    "23ee48c91b3dfb5b68b3372ac49fc6607f203cf01d3b9fcfe04b4ea42be02356"
)
EXPECTED_UUID = "1b555645-a9e2-4f5e-95af-6ce4adacbc3c"
EXPECTED_KERNEL = "dlrm_f37x_rtl_kernel_stage2n_a15_v1"
EXPECTED_CU = "dlrm_a15_1"
EXPECTED_BDF = "0000:9b:00.1"
EXPECTED_BANK = "HBM[0]"
EXPECTED_COUNTERS = {
    "bottom": 322,
    "interaction": 100,
    "top": 744,
    "total": 1174,
}
CASE_NAMES = [
    "baseline",
    "slot0_sensitivity",
    "slot1_sensitivity",
    "slot2_sensitivity",
    "slot3_sensitivity",
]


class EvidenceError(RuntimeError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise EvidenceError(message)


def load_json(path: Path) -> Dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise EvidenceError("malformed evidence/manifest: {}".format(exc))
    require(isinstance(value, dict), "top-level JSON must be an object")
    return value


def validate_manifest(manifest: Dict[str, Any]) -> None:
    require(manifest.get("format") == "STAGE2N_A15_6_CASES_V1", "manifest format")
    cases = manifest.get("cases")
    require(isinstance(cases, list) and len(cases) == 5, "manifest case count")
    require([case.get("name") for case in cases] == CASE_NAMES, "manifest case names")


def validate_evidence(value: Dict[str, Any], manifest: Dict[str, Any]) -> None:
    validate_manifest(manifest)
    require(value.get("schema") == "STAGE2N_A15_6_BOARD_EVIDENCE_V1", "schema")
    for key in ("timestamp_utc", "hostname", "git_branch", "git_head"):
        require(isinstance(value.get(key), str) and value[key], "missing " + key)

    device = value.get("device", {})
    require(isinstance(device.get("index"), int) and device["index"] >= 0, "device index")
    require(device.get("bdf") == EXPECTED_BDF, "wrong device/BDF")
    require(device.get("other_device_access") == "NONE", "other device access")

    artifact = value.get("artifact", {})
    require(artifact.get("xclbin_sha256") == EXPECTED_XCLBIN_SHA256, "wrong xclbin SHA")
    require(artifact.get("xclbin_uuid") == EXPECTED_UUID, "wrong UUID")
    require(isinstance(artifact.get("xclbin_path"), str) and artifact["xclbin_path"], "xclbin path")
    require(artifact.get("kernel") == EXPECTED_KERNEL, "kernel")
    require(artifact.get("compute_unit") == EXPECTED_CU, "CU")

    memory = value.get("memory", {})
    require(memory.get("bank") == EXPECTED_BANK, "wrong HBM bank")
    require(memory.get("memory_index") == 0, "HBM memory index")
    require(isinstance(memory.get("bo_size_bytes"), int) and memory["bo_size_bytes"] >= 1024, "BO size")
    paddr = memory.get("bo_physical_address")
    require(isinstance(paddr, int) and 0 <= paddr < (1 << 64), "BO physical address")
    # paddr == 0 is intentionally accepted; A14.7 proved this is legal.
    require(memory.get("table_base_programming") == "PASS", "TABLE_BASE programming")
    require(memory.get("payload_transfer") == "PASS", "payload transfer")
    require(memory.get("physical_hbm") == "PASS", "physical HBM")

    programming = value.get("programming", {})
    require(programming.get("fpga") in ("PASS", "SKIPPED_ALREADY_LOADED"), "FPGA programming")
    require(programming.get("reset") == "NOT_RUN", "FPGA reset")

    cases = value.get("cases")
    require(isinstance(cases, list) and len(cases) == 5, "missing result/case count")
    manifest_cases = {case["name"]: case for case in manifest["cases"]}
    seen: List[str] = []
    for case in cases:
        name = case.get("name")
        require(name in manifest_cases and name not in seen, "case name/duplicate")
        seen.append(name)
        expected_case = manifest_cases[name]
        require(case.get("payload_sha256") == expected_case["payload_sha256"], "wrong payload SHA")
        require(case.get("expected_result") == expected_case["expected_final_result"], "mismatched golden")
        require("actual_result" in case, "missing result")
        require(case.get("actual_result") == case.get("expected_result"), "actual/golden mismatch")
        require(case.get("embedding_loaded_mask") == "0xF", "loaded mask")
        require(case.get("completion") == "PASS", "case completion")
        require(case.get("complete_dlrm_result") == "PASS", "complete DLRM result")
        require(case.get("table_base_readback") == "PASS", "TABLE_BASE readback")
        require(case.get("counters") == EXPECTED_COUNTERS, "cycle counters")
    require(seen == CASE_NAMES, "case order")
    sensitivity = [case["actual_result"] for case in cases[1:]]
    require(all(value != cases[0]["actual_result"] for value in sensitivity), "sensitivity did not change result")

    cleanup = value.get("cleanup", {})
    require(cleanup.get("bo_release") == "PASS", "BO cleanup")
    require(cleanup.get("device_close") == "PASS", "device close")
    require(cleanup.get("global_hbm_cleanup") == "NOT_RUN", "global HBM cleanup")
    require(value.get("board_functional") == "PASS", "board functional")
    require(value.get("performance") == "NOT_CLAIMED", "performance boundary")


def valid_fixture(manifest: Dict[str, Any]) -> Dict[str, Any]:
    return {
        "schema": "STAGE2N_A15_6_BOARD_EVIDENCE_V1",
        "timestamp_utc": "2026-08-28T00:00:00Z",
        "hostname": "fixture-host",
        "git_branch": "work/stage2n-a15-hbm-pipeline-integration",
        "git_head": "0" * 40,
        "device": {"index": 2, "bdf": EXPECTED_BDF, "other_device_access": "NONE"},
        "artifact": {
            "xclbin_path": "/fixture/a15.xclbin",
            "xclbin_sha256": EXPECTED_XCLBIN_SHA256,
            "xclbin_uuid": EXPECTED_UUID,
            "kernel": EXPECTED_KERNEL,
            "compute_unit": EXPECTED_CU,
        },
        "memory": {
            "bank": EXPECTED_BANK,
            "memory_index": 0,
            "bo_size_bytes": 1024,
            "bo_physical_address": 0,
            "table_base_programming": "PASS",
            "payload_transfer": "PASS",
            "physical_hbm": "PASS",
        },
        "programming": {"fpga": "PASS", "reset": "NOT_RUN"},
        "cases": [
            {
                "name": case["name"],
                "payload_sha256": case["payload_sha256"],
                "expected_result": case["expected_final_result"],
                "actual_result": case["expected_final_result"],
                "embedding_loaded_mask": "0xF",
                "table_base_readback": "PASS",
                "completion": "PASS",
                "complete_dlrm_result": "PASS",
                "counters": dict(EXPECTED_COUNTERS),
            }
            for case in manifest["cases"]
        ],
        "cleanup": {
            "bo_release": "PASS",
            "device_close": "PASS",
            "global_hbm_cleanup": "NOT_RUN",
        },
        "board_functional": "PASS",
        "performance": "NOT_CLAIMED",
    }


def run_negative(name: str, fixture: Dict[str, Any], manifest: Dict[str, Any], mutate) -> None:
    candidate = copy.deepcopy(fixture)
    mutate(candidate)
    try:
        validate_evidence(candidate, manifest)
    except EvidenceError:
        print("A15_6_NEGATIVE_{}=PASS".format(name))
        return
    raise EvidenceError("negative fixture was accepted: " + name)


def self_test(manifest: Dict[str, Any]) -> None:
    fixture = valid_fixture(manifest)
    validate_evidence(fixture, manifest)
    print("A15_6_VALIDATOR_POSITIVE=PASS")
    print("A15_6_ZERO_PHYSICAL_ADDRESS_ACCEPTED=PASS")
    run_negative("WRONG_XCLBIN_SHA", fixture, manifest,
                 lambda v: v["artifact"].update(xclbin_sha256="f" * 64))
    run_negative("WRONG_UUID", fixture, manifest,
                 lambda v: v["artifact"].update(xclbin_uuid="00000000-0000-0000-0000-000000000000"))
    run_negative("WRONG_DEVICE_BDF", fixture, manifest,
                 lambda v: v["device"].update(bdf="0000:00:00.0"))
    run_negative("WRONG_HBM_BANK", fixture, manifest,
                 lambda v: v["memory"].update(bank="HBM[1]"))
    run_negative("WRONG_PAYLOAD_SHA", fixture, manifest,
                 lambda v: v["cases"][0].update(payload_sha256="0" * 64))
    run_negative("MISSING_RESULT", fixture, manifest,
                 lambda v: v["cases"][0].pop("actual_result"))
    run_negative("MISMATCHED_GOLDEN", fixture, manifest,
                 lambda v: v["cases"][0].update(expected_result=12345))
    with tempfile.TemporaryDirectory() as directory:
        malformed = Path(directory) / "malformed.json"
        malformed.write_text("{not-json", encoding="utf-8")
        try:
            load_json(malformed)
        except EvidenceError:
            print("A15_6_NEGATIVE_MALFORMED_EVIDENCE=PASS")
        else:
            raise EvidenceError("malformed evidence was accepted")
    print("A15_6_VALIDATOR_SELF_TEST=PASS")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", type=Path, required=True)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--evidence", type=Path)
    group.add_argument("--self-test", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    manifest = load_json(args.manifest)
    if args.self_test:
        self_test(manifest)
    else:
        evidence = load_json(args.evidence)
        validate_evidence(evidence, manifest)
        print("A15_6_EVIDENCE_VALIDATION=PASS")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except EvidenceError as exc:
        print("A15_6_EVIDENCE_VALIDATION=FAIL", file=sys.stderr)
        print("REASON={}".format(exc), file=sys.stderr)
        raise SystemExit(1)
