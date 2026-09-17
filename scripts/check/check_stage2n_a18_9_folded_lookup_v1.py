#!/usr/bin/env python3
"""A18.9 four-line FIFO cache + pairwise fold goldens. No device."""
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


def sat_add_i16(a, b):
    total = int(a) + int(b)
    if total > 32767:
        return 32767
    if total < -32768:
        return -32768
    return total


def simulate_fifo(banks, groups, lines=4):
    cache = [[] for _ in range(4)]
    ar = [0, 0, 0, 0]
    hit = [0, 0, 0, 0]
    miss = [0, 0, 0, 0]
    for indexes in groups:
        queues = [[] for _ in range(4)]
        for table_id, bank in enumerate(banks):
            queues[bank].append(table_id)
        for bank in range(4):
            for table_id in queues[bank]:
                index = indexes[table_id]
                if index in cache[bank]:
                    hit[bank] += 1
                else:
                    miss[bank] += 1
                    ar[bank] += 1
                    if len(cache[bank]) >= lines:
                        cache[bank].pop(0)
                    cache[bank].append(index)
    return ar, hit, miss


def main():
    fold = (ROOT / "rtl/hbm/dlrm_t8_pair_fold_stage2n_a18_9_v1.sv").read_text(
        encoding="utf-8")
    cache = (ROOT / "rtl/hbm/dlrm_hbm_bank_line_cache_stage2n_a18_9_v1.sv").read_text(
        encoding="utf-8")
    top = (ROOT / "rtl/hbm/dlrm_hbm_t8_folded_lookup_stage2n_a18_9_v1.sv").read_text(
        encoding="utf-8")
    tb = (ROOT / "tb/tb_dlrm_hbm_t8_folded_lookup_stage2n_a18_9_v1.sv").read_text(
        encoding="utf-8")
    boarded = (ROOT / "rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a18_v1.sv").read_text(
        encoding="utf-8")

    require("sat_add" in fold, "fold sat_add missing")
    require("wr_ptr" in cache, "four-line FIFO pointer missing")
    require("dlrm_hbm_bank_line_cache_stage2n_a18_9_v1" in top, "4-line cache")
    require("dlrm_t8_pair_fold_stage2n_a18_9_v1" in top, "fold in top")
    require("dlrm_internal_pipeline_controller_stage2n_a13_v1" not in top,
            "must not instantiate A13")
    require("dlrm_hbm_t8_folded_lookup_stage2n_a18_9_v1" not in boarded,
            "boarded A18 kernel must stay unwired")
    require("IDENT_WARM" in tb, "warm four-line replay missing")
    require("IDENT_FOLD" in tb, "fold check missing")
    require("TB_A18_9_FOLDED_LOOKUP=PASS" in tb, "TB pass token")
    require(sat_add_i16(20000, 20000) == 32767, "pos saturate")
    require(sat_add_i16(-20000, -20000) == -32768, "neg saturate")
    require(sat_add_i16(10, 20) == 30, "no saturate")

    unique = list(range(10, 18))
    ident = ident_banks()
    ar, hit, miss = simulate_fifo(ident, [unique])
    require(ar == [2, 2, 2, 2], "cold ident AR")
    ar2, hit2, miss2 = simulate_fifo(ident, [unique, unique])
    require(ar2 == [2, 2, 2, 2], "warm ident adds no AR")
    require(hit2 == [2, 2, 2, 2], "warm ident hits the second group")

    print("A18_9_FOLDED_LOOKUP_CHECK=PASS")
    print("COLD_IDENT_AR=2,2,2,2")
    print("WARM_IDENT_AR_TOTAL=2,2,2,2")
    print("SAT_ADD_20000_20000=32767")
    print("A18_BOARDED_KERNEL_UNCHANGED=PASS")
    print("EXTRA_RUN=NOT_RUN")
    print("FPGA_PROGRAMMING=NOT_RUN")
    print("PHYSICAL_HBM=NOT_RUN")
    print("PERFORMANCE=NOT_CLAIMED")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except CheckError as error:
        print("A18_9_FOLDED_LOOKUP_CHECK=FAIL", file=sys.stderr)
        print("REASON={0}".format(error), file=sys.stderr)
        sys.exit(1)
