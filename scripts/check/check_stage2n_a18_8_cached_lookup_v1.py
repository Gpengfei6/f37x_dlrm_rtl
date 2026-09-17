#!/usr/bin/env python3
"""A18.8 cached T=8 lookup: source gates plus a per-bank line-cache golden."""
from __future__ import print_function

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


class CheckError(Exception):
    pass


def require(condition, message):
    if not condition:
        raise CheckError(message)


def ident_banks():
    return [t % 4 for t in range(8)]


def coacc_split_banks():
    banks = ident_banks()
    if banks[4] == banks[0]:
        banks[4] = (banks[0] + 1) % 4
    if banks[5] == banks[1]:
        banks[5] = (banks[1] + 1) % 4
    return banks


def force_01_banks():
    banks = ident_banks()
    banks[0] = 0
    banks[1] = 0
    return banks


def occupancy(banks):
    occ = [0, 0, 0, 0]
    for bank in banks:
        occ[bank] += 1
    return occ


def simulate_line_cache(banks, indexes):
    """One outstanding per bank, issue lowest table id first, one-line cache."""
    queues = [[] for _ in range(4)]
    for table_id, bank in enumerate(banks):
        queues[bank].append(table_id)
    line = [None, None, None, None]
    ar = [0, 0, 0, 0]
    hit = [0, 0, 0, 0]
    miss = [0, 0, 0, 0]
    for bank in range(4):
        for table_id in queues[bank]:
            index = indexes[table_id]
            if line[bank] == index:
                hit[bank] += 1
            else:
                miss[bank] += 1
                ar[bank] += 1
                line[bank] = index
    return ar, hit, miss


def main():
    rtl = (ROOT / "rtl/hbm/dlrm_hbm_t8_cached_lookup_stage2n_a18_8_v1.sv").read_text(
        encoding="utf-8")
    tb = (ROOT / "tb/tb_dlrm_hbm_t8_cached_lookup_stage2n_a18_8_v1.sv").read_text(
        encoding="utf-8")
    boarded = (ROOT / "rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a18_v1.sv").read_text(
        encoding="utf-8")

    require("dlrm_table_bank_mapper_stage2n_a18_5_v1" in rtl, "mapper missing")
    require("dlrm_hbm_bank_line_cache_stage2n_a18_7_v1" in rtl, "cache missing")
    require("dlrm_hbm_embedding_lookup_stage2n_a14_v2" in rtl, "A14 v2 missing")
    require("dlrm_internal_pipeline_controller_stage2n_a13_v1" not in rtl,
            "must not instantiate A13")
    require("dlrm_hbm_t8_cached_lookup_stage2n_a18_8_v1" not in boarded,
            "boarded A18 kernel must stay unwired")
    require("dlrm_hbm_bank_line_cache_stage2n_a18_7_v1" not in boarded,
            "boarded kernel must not instantiate cache")
    require("TB_A18_8_CACHED_LOOKUP=PASS" in tb, "TB pass token")
    require("SAME_LINE_BANK0" in tb, "same-line hit case missing")
    require("pulse_rst" in tb, "cold tests must reset cache")

    unique = list(range(10, 18))
    ident = ident_banks()
    coacc = coacc_split_banks()
    force = force_01_banks()
    ar, hit, miss = simulate_line_cache(ident, unique)
    require(ar == [2, 2, 2, 2], "cold ident AR")
    require(hit == [0, 0, 0, 0], "cold ident hits")
    require(occupancy(ident) == [2, 2, 2, 2], "ident occupancy")

    ar, hit, miss = simulate_line_cache(coacc, unique)
    require(ar == [1, 2, 3, 2], "cold coacc AR equals occupancy")
    require(occupancy(coacc) == [1, 2, 3, 2], "coacc occupancy")

    ar, hit, miss = simulate_line_cache(force, unique)
    require(ar == [3, 1, 2, 2], "cold force AR")
    require(occupancy(force) == [3, 1, 2, 2], "force occupancy")

    same = [7, 11, 12, 13, 7, 15, 16, 17]
    ar, hit, miss = simulate_line_cache(ident, same)
    require(ar == [1, 2, 2, 2], "same-line bank0 AR")
    require(hit == [1, 0, 0, 0], "same-line bank0 hit")
    require(miss == [1, 2, 2, 2], "same-line misses")
    require("1, 2, 2, 2" in tb, "TB same-line AR vector")

    print("A18_8_CACHED_LOOKUP_CHECK=PASS")
    print("COLD_IDENT_AR=2,2,2,2")
    print("SAME_LINE_BANK0_AR=1,2,2,2")
    print("SAME_LINE_BANK0_HIT=1,0,0,0")
    print("A18_BOARDED_KERNEL_UNCHANGED=PASS")
    print("XSIM=NOT_RUN")
    print("EXTRA_RUN=NOT_RUN")
    print("FPGA_PROGRAMMING=NOT_RUN")
    print("PHYSICAL_HBM=NOT_RUN")
    print("PERFORMANCE=NOT_CLAIMED")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except CheckError as error:
        print("A18_8_CACHED_LOOKUP_CHECK=FAIL", file=sys.stderr)
        print("REASON={0}".format(error), file=sys.stderr)
        sys.exit(1)
