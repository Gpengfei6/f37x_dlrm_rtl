#!/usr/bin/env python3
"""Self-check for the A18 L1 request-distribution checker. No device."""
from __future__ import print_function

import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from analysis.stage2n_a18_l1.workload_analyzer import (  # noqa: E402
    A17_FIXED_ROWS,
    FORBIDDEN_METRIC_TOKENS,
    format_records,
    format_summary,
    ident_bank,
    rr_bank,
    run_scenario,
    stripe_bank,
    summarize_forbidden_ok,
)


class CheckError(Exception):
    pass


def require(condition, message):
    if not condition:
        raise CheckError(message)


def main():
    rec_a, sum_a = run_scenario(4, "ident", "e0", n_rounds=1, seed=1)
    rec_b, sum_b = run_scenario(4, "ident", "e0", n_rounds=1, seed=1)
    require(rec_a == rec_b and sum_a == sum_b, "e0 must be deterministic")
    require(len(rec_a) == 4, "e0 has four lookups")
    for table_id, row, expected_index in zip(range(4), rec_a, A17_FIXED_ROWS):
        require(row["table_id"] == table_id, "e0 table order")
        require(row["index"] == expected_index, "e0 rows must be 37-40")
        require(row["bank"] == table_id, "e0 ident is table i -> HBM[i]")
        require(row["concurrency"] == 4, "concurrency is used-channel count")
        require(row["conflict_count"] == 0, "conflict is requests minus used channels")
        require(row["max_completion_proxy"] == 1, "e0 unit proxy is 1")
        require(row["bank_occupancy"] == 1, "e0 one lookup per bank")
    require(sum_a["OVERSUBSCRIBE"] is False, "T=4 is not oversubscribed")
    require(sum_a["PHYSICAL_HBM"] == "NOT_MODELED", "must not claim HBM")
    require(sum_a["GATHER"] == "ONE_LOOKUP_PER_TABLE_PER_ROUND", "full gather")
    require(sum_a["CONFLICT_DEF"] == "N_REQUESTS_MINUS_USED_CHANNELS", "conflict def")
    require(sum_a["CONCURRENCY_DEF"] == "USED_CHANNELS", "concurrency def")
    require(summarize_forbidden_ok(format_summary(sum_a)), "e0 summary tokens")
    require(summarize_forbidden_ok(format_records(rec_a)), "e0 record tokens")

    rec8, sum8 = run_scenario(8, "ident", "uniform", n_rounds=4, seed=7)
    rec8b, sum8b = run_scenario(8, "ident", "uniform", n_rounds=4, seed=7)
    require(rec8 == rec8b, "uniform ident must be deterministic")
    require(sum8["OVERSUBSCRIBE"] is True, "T=8 stripe must oversubscribe")
    require(sum8["TABLE_BANKS"] == [0, 1, 2, 3, 0, 1, 2, 3], "stripe wrap")
    require(sum8["BANK_OCCUPANCY"] == [2, 2, 2, 2], "T=8,B=4 occupancy is by construction")
    require(sum8["PROXY_MAX"] == 2, "T=8 occupancy 2 is by construction")
    require(sum8["CONFLICT_SUM"] == 4 * 4, "each round: 8 requests - 4 channels")
    require(sum8["IDLE_CHANNELS"] == [], "T=8 stripe uses all channels")
    require(len(sum8["REUSED_BANKS"]) == 4, "all four banks reused")

    rec16, sum16 = run_scenario(16, "ident", "uniform", n_rounds=1, seed=1)
    require(sum16["BANK_OCCUPANCY"] == [4, 4, 4, 4], "T=16 occupancy is by construction")
    require(sum16["PROXY_MAX"] == 4, "T=16 occupancy 4 is by construction")
    require(rec16[0]["conflict_count"] == 16 - 4, "conflict is requests minus used channels")

    for table_id in range(16):
        require(ident_bank(table_id, 4) == rr_bank(table_id, 4), "ident/rr aliases")
        require(ident_bank(table_id, 4) == stripe_bank(table_id, 4), "shared stripe")
    rec_rr, sum_rr = run_scenario(8, "rr", "uniform", n_rounds=4, seed=7)
    require(sum_rr["TABLE_BANKS"] == sum8["TABLE_BANKS"], "rr is the ident stripe")
    require(sum_rr["MAPPING_FAMILY"] == "STRIPE_MOD_B", "rr family")
    require(sum8["IDENT_RR_EQUIVALENT"] is True, "ident/rr not independent")
    require(rec_rr == rec8, "ident and rr records match on same seed")

    _rec_cap, sum_cap = run_scenario(
        8, "cap", "uniform", n_rounds=1, seed=1, cap_skew=True)
    require(sum_cap["TABLE_BANKS"] != [0, 1, 2, 3, 0, 1, 2, 3],
            "skewed cap pairing differs from stripe")
    require(sum_cap["MAPPING_FAMILY"] == "CAP", "cap family")

    rec_c, sum_c = run_scenario(8, "ident", "coaccess", n_rounds=3, seed=3)
    require(sum_c["PATTERN_KIND"] == "SAME_ROW_INDEX", "coaccess is same-row-index")
    require(sum_c["SAME_ROW_INDEX_CHANGES_TABLE_SET"] is False, "table set unchanged")
    require(sum_c["GATHER"] == "ONE_LOOKUP_PER_TABLE_PER_ROUND", "still full gather")
    require(sum_c["SAME_ROW_INDEX_PAIRS"] == [(0, 4), (1, 5)], "designated index pairs")
    require(sum_c["SAME_ROW_INDEX_SAME_BANK"] == 6, "pairs land on stripe wrap")
    require(sum_c["BANK_OCCUPANCY"] == [2, 2, 2, 2], "index copy does not change occupancy")
    require(len(rec_c) == 8 * 3, "must not skip tables")
    for row in rec_c:
        if row["round_id"] != 0:
            continue
        if row["table_id"] == 4:
            idx0 = [r["index"] for r in rec_c
                    if r["round_id"] == 0 and r["table_id"] == 0][0]
            require(row["index"] == idx0, "same numeric row index on pair")

    rec_f, sum_f = run_scenario(
        8, "ident", "forced_conflict", n_rounds=2, seed=2)
    require(sum_f["TABLE_BANKS"][0] == 0 and sum_f["TABLE_BANKS"][1] == 0,
            "forced_conflict pins tables 0 and 1 to bank 0")
    require(sum_f["BANK_OCCUPANCY"] == [3, 1, 2, 2], "occupancy 3/1/2/2")
    require(sum_f["IDLE_CHANNELS"] == [], "no idle channel")
    require(sum_f["PROXY_MAX"] == 3, "max occupancy 3")
    require(rec_f[0]["concurrency"] == 4, "all four channels used")
    require(rec_f[0]["conflict_count"] == 8 - 4, "still 8 requests minus 4 channels")

    rec_h, sum_h = run_scenario(8, "ident", "hotspot", n_rounds=8, seed=11)
    require(len(rec_h) == 8 * 8, "hotspot still one lookup per table")
    require(sum_h["HOTSPOT_SCOPE"] == "ROW_INDEX_ONLY", "zipf is row-only")
    require(sum_h["BANK_OCCUPANCY"] == [2, 2, 2, 2], "hotspot does not change table counts")

    blob = format_summary(sum_f) + format_records(rec_f) + format_summary(sum_c)
    for token in FORBIDDEN_METRIC_TOKENS:
        require(token.lower() not in blob.lower(), "token " + token)

    print("A18_L1_WORKLOAD_ANALYZER_SELFTEST=PASS")
    print("E0_A17_IDENT_MATCH=PASS")
    print("DETERMINISM=PASS")
    print("T8_T16_OCCUPANCY_BY_CONSTRUCTION=PASS")
    print("IDENT_RR_EQUIVALENT=PASS")
    print("SAME_ROW_INDEX_PAIRS=PASS")
    print("SAME_ROW_INDEX_NOT_COOCCURRENCE=PASS")
    print("FORCED_OCCUPANCY_3_1_2_2=PASS")
    print("IDLE_CHANNELS=NONE")
    print("PHYSICAL_HBM=NOT_MODELED")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except CheckError as error:
        print("A18_L1_WORKLOAD_ANALYZER_SELFTEST=FAIL", file=sys.stderr)
        print("REASON=" + str(error), file=sys.stderr)
        sys.exit(1)
