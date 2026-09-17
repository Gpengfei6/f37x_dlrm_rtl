#!/usr/bin/env python3
"""Lock L1 E2/E4/E5 geometry summaries. Local only. Not FPGA or performance."""
from __future__ import print_function

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from analysis.stage2n_a18_l1.workload_analyzer import run_scenario  # noqa: E402

LOCK_PATH = ROOT / "analysis/stage2n_a18_l1/e2_e4_e5_lock_v1.json"
SCHEMA = "a18_4_l1_geometry_lock_v1"
SUMMARY_KEYS = (
    "T", "B", "MAPPING", "MAPPING_FAMILY", "PATTERN", "PATTERN_KIND",
    "ROUNDS", "SEED", "TABLE_BANKS", "BANK_OCCUPANCY", "IDLE_CHANNELS",
    "OVERSUBSCRIBE", "CONFLICT_SUM", "PROXY_MAX", "PHYSICAL_HBM",
    "PERFORMANCE", "SAME_ROW_INDEX_PAIRS", "SAME_ROW_INDEX_SAME_BANK",
    "SAME_ROW_INDEX_CHANGES_TABLE_SET", "HOTSPOT_SCOPE",
)

CELLS = (
    {
        "id": "E2_T8_STRIPE_UNIFORM",
        "experiment": "E2",
        "n_tables": 8,
        "mapping": "ident",
        "pattern": "uniform",
        "n_rounds": 8,
        "seed": 7,
        "note": "T>B stripe occupancy [2,2,2,2] is by construction",
    },
    {
        "id": "E2_T16_STRIPE_UNIFORM",
        "experiment": "E2",
        "n_tables": 16,
        "mapping": "ident",
        "pattern": "uniform",
        "n_rounds": 4,
        "seed": 7,
        "note": "T=16 stripe occupancy [4,4,4,4] is by construction",
    },
    {
        "id": "E4_T8_STRIPE_SAME_ROW_INDEX",
        "experiment": "E4",
        "n_tables": 8,
        "mapping": "ident",
        "pattern": "coaccess",
        "n_rounds": 8,
        "seed": 3,
        "note": "same numeric row index on pairs; not a co-occurrence mapping",
    },
    {
        "id": "E5_T8_FORCE_01_BANK0",
        "experiment": "E5",
        "n_tables": 8,
        "mapping": "ident",
        "pattern": "forced_conflict",
        "n_rounds": 4,
        "seed": 2,
        "note": "tables 0 and 1 pinned to bank 0; occupancy [3,1,2,2]",
    },
)


class LockError(Exception):
    pass


def require(condition, message):
    if not condition:
        raise LockError(message)


def cell_summary(spec):
    _records, summary = run_scenario(
        spec["n_tables"], spec["mapping"], spec["pattern"],
        n_rounds=spec["n_rounds"], seed=spec["seed"])
    sliced = {key: summary[key] for key in SUMMARY_KEYS if key in summary}
    return {
        "id": spec["id"],
        "experiment": spec["experiment"],
        "note": spec["note"],
        "summary": sliced,
    }


def build_lock():
    cells = [cell_summary(spec) for spec in CELLS]
    payload = {
        "schema": SCHEMA,
        "claim_boundary": (
            "L1 geometry only. Occupancy and conflict_count are by "
            "construction from T, B, and table_id%B. Not FPGA HBM, "
            "not RTL placement, not performance."
        ),
        "PHYSICAL_HBM": "NOT_MODELED",
        "PERFORMANCE": "NOT_CLAIMED",
        "IDENT_RR_EQUIVALENT": True,
        "COOCCURRENCE_MAPPING": "NOT_IMPLEMENTED",
        "cells": cells,
    }
    e2_t8 = cells[0]["summary"]
    e2_t16 = cells[1]["summary"]
    e4 = cells[2]["summary"]
    e5 = cells[3]["summary"]
    require(e2_t8["BANK_OCCUPANCY"] == [2, 2, 2, 2], "E2 T=8 occupancy")
    require(e2_t8["CONFLICT_SUM"] == 8 * 4, "E2 T=8 conflict sum")
    require(e2_t16["BANK_OCCUPANCY"] == [4, 4, 4, 4], "E2 T=16 occupancy")
    require(e4["BANK_OCCUPANCY"] == [2, 2, 2, 2], "E4 occupancy unchanged")
    require(e4["SAME_ROW_INDEX_CHANGES_TABLE_SET"] is False, "E4 table set")
    require(e5["BANK_OCCUPANCY"] == [3, 1, 2, 2], "E5 occupancy")
    require(e5["IDLE_CHANNELS"] == [], "E5 no idle")
    return payload


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--write", action="store_true")
    args = parser.parse_args()
    payload = build_lock()
    text = json.dumps(payload, indent=2, sort_keys=True) + "\n"
    if args.write:
        LOCK_PATH.parent.mkdir(parents=True, exist_ok=True)
        LOCK_PATH.write_text(text, encoding="utf-8")
        print("WROTE={0}".format(LOCK_PATH.as_posix()))
    require(LOCK_PATH.is_file(), "lock file missing; run with --write")
    existing = LOCK_PATH.read_text(encoding="utf-8")
    require(existing == text, "lock file drifted from analyzer")
    print("A18_4_L1_GEOMETRY_LOCK=PASS")
    print("PHYSICAL_HBM=NOT_MODELED")
    print("PERFORMANCE=NOT_CLAIMED")
    print("COOCCURRENCE_MAPPING=NOT_IMPLEMENTED")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except LockError as error:
        print("A18_4_L1_GEOMETRY_LOCK=FAIL", file=sys.stderr)
        print("REASON={0}".format(error), file=sys.stderr)
        sys.exit(1)
