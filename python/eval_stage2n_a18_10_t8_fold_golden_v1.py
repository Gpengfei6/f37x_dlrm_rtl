#!/usr/bin/env python3
"""Local T=8 pairwise-fold then A13 software goldens.

Uses frozen A15.6 model.bin and the baseline table. Fold is
slot[i] = sat_add(vec[i], vec[i+4]) per INT16 lane. Not a board result,
not an A18.3 golden, and not a performance claim.
"""
from __future__ import print_function

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "python"))

import eval_stage2n_a18_2_index_golden_v1 as a18  # noqa: E402

LOCKED = {
    "unique_0_7": {
        "indexes": [0, 1, 2, 3, 4, 5, 6, 7],
        "expected_final_result": -333,
    },
    "default_ext_37_44": {
        "indexes": [37, 38, 39, 40, 41, 42, 43, 44],
        "expected_final_result": -480,
    },
    "doubled_37_40": {
        "indexes": [37, 38, 39, 40, 37, 38, 39, 40],
        "expected_final_result": -774,
    },
    "zeros": {
        "indexes": [0, 0, 0, 0, 0, 0, 0, 0],
        "expected_final_result": -318,
    },
    "mixed_1_4_10_13": {
        "indexes": [1, 2, 3, 4, 10, 11, 12, 13],
        "expected_final_result": -289,
    },
    "high_63_56": {
        "indexes": [63, 62, 61, 60, 59, 58, 57, 56],
        "expected_final_result": -299,
    },
    "default_plus_zeros": {
        "indexes": [37, 38, 39, 40, 0, 0, 0, 0],
        "expected_final_result": -223,
    },
}

A18_3_BOARD_OR_SOFTWARE = (-393, -61, -60, -162, -185, -392, -93, -689, -519)


class GoldenError(Exception):
    pass


def require(condition, message):
    if not condition:
        raise GoldenError(message)


def sat_add_i16(a, b):
    total = int(a) + int(b)
    if total > 32767:
        return 32767
    if total < -32768:
        return -32768
    return total


def fold_embeddings(table, indexes):
    require(len(indexes) == 8, "exactly eight indexes")
    vectors = []
    for index in indexes:
        require(0 <= int(index) < a18.ROWS, "OOB lookup index {}".format(index))
        vectors.append(list(table[int(index)]))
    slots = []
    for slot in range(4):
        slots.append([
            sat_add_i16(vectors[slot][lane], vectors[slot + 4][lane])
            for lane in range(a18.DIM)
        ])
    return vectors, slots


def evaluate_t8(model, table, indexes):
    vectors, slots = fold_embeddings(table, indexes)
    bottom = a18.a11.software_mlp(model["bottom_layers"], model["dense"])
    interaction = a18.a11.software_interaction(
        bottom, slots, model["interaction_shift"])
    final = a18.a11.software_mlp(model["top_layers"], interaction)
    require(len(final) == 1, "final result dimension")
    return {
        "indexes": [int(v) for v in indexes],
        "raw_vectors": vectors,
        "folded_slots": slots,
        "expected_bottom": bottom,
        "expected_interaction": interaction,
        "expected_final_result": int(final[0]),
    }


def self_test(repo):
    model_dir = repo / "models/stage2n_a15_6"
    model = a18.load_model(model_dir / "stage2n_a15_6_model_v1.bin")
    table = a18.unpack_table(
        (model_dir / "stage2n_a15_6_case0_baseline_table_v1.bin").read_bytes())
    require(sat_add_i16(20000, 20000) == 32767, "pos saturate")
    require(sat_add_i16(-20000, -20000) == -32768, "neg saturate")
    t4 = a18.evaluate_indexes(model, table, (37, 38, 39, 40))
    require(t4["expected_final_result"] == -393, "A15.6 T=4 baseline still -393")
    extras = []
    for name, spec in LOCKED.items():
        item = evaluate_t8(model, table, spec["indexes"])
        require(
            item["expected_final_result"] == spec["expected_final_result"],
            "golden mismatch " + name)
        require(
            item["expected_final_result"] not in A18_3_BOARD_OR_SOFTWARE,
            "folded T=8 must not reuse an A18.3 golden " + name)
        extras.append({
            "name": name,
            "indexes": item["indexes"],
            "expected_final_result": item["expected_final_result"],
            "table": "stage2n_a15_6_case0_baseline_table_v1.bin",
            "note": "software fold-then-A13 only; not a board result",
        })
    try:
        evaluate_t8(model, table, (64, 1, 2, 3, 4, 5, 6, 7))
        raise GoldenError("OOB 64 must fail")
    except GoldenError as error:
        require("OOB" in str(error), "OOB error text")
    return extras


def main():
    repo = ROOT
    extras = self_test(repo)
    out = repo / "analysis/stage2n_a18_10/t8_fold_a13_goldens_v1.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "schema": "a18_10_t8_fold_a13_goldens_v1",
        "claim_boundary": (
            "Local software goldens: pairwise INT16 sat-add fold of eight "
            "baseline-table rows, then the frozen A15.6 A13 numeric path. "
            "Not FPGA, XO, xclbin, extra-run, or performance evidence. "
            "Not an A18.3 board golden."
        ),
        "model": "stage2n_a15_6_model_v1.bin",
        "table": "stage2n_a15_6_case0_baseline_table_v1.bin",
        "fold": "slot[i] = sat_add(vec[i], vec[i+4]) per INT16 lane",
        "cases": extras,
    }
    out.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n",
                   encoding="utf-8")
    print("A18_10_T8_FOLD_A13_GOLDEN=PASS")
    print("WROTE={}".format(out.as_posix()))
    print("T4_BASELINE_STILL=-393")
    print("FOLD_DEFAULT_PLUS_ZEROS=-223")
    print("A18_3_BOARD=NOT_REUSED")
    print("FPGA_PROGRAMMING=NOT_RUN")
    print("EXTRA_RUN=NOT_RUN")
    print("PERFORMANCE=NOT_CLAIMED")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except GoldenError as error:
        print("A18_10_T8_FOLD_A13_GOLDEN=FAIL", file=sys.stderr)
        print("REASON={}".format(error), file=sys.stderr)
        sys.exit(1)
