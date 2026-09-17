#!/usr/bin/env python3
"""A18.7 one-line cache source check. No device, no boarded-kernel edit."""
from __future__ import print_function

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


class CheckError(Exception):
    pass


def require(condition, message):
    if not condition:
        raise CheckError(message)


def main():
    rtl = (ROOT / "rtl/hbm/dlrm_hbm_bank_line_cache_stage2n_a18_7_v1.sv").read_text(
        encoding="utf-8")
    tb = (ROOT / "tb/tb_dlrm_hbm_bank_line_cache_stage2n_a18_7_v1.sv").read_text(
        encoding="utf-8")
    boarded = (ROOT / "rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a18_v1.sv").read_text(
        encoding="utf-8")

    require("line_valid" in rtl, "one-line valid missing")
    require("hit_count" in rtl and "miss_count" in rtl, "hit/miss counters")
    require("eng_req_valid" in rtl, "engine miss path missing")
    require("dlrm_hbm_bank_line_cache_stage2n_a18_7_v1" not in boarded,
            "boarded A18 kernel must not instantiate cache")
    require("TB_A18_7_LINE_CACHE=PASS" in tb, "TB pass token")
    require("second hit" in tb or "hit_count !== 16'd1" in tb, "hit case")

    print("A18_7_LINE_CACHE_CHECK=PASS")
    print("A18_BOARDED_KERNEL_UNCHANGED=PASS")
    print("XSIM=NOT_RUN")
    print("FPGA_PROGRAMMING=NOT_RUN")
    print("PHYSICAL_HBM=NOT_RUN")
    print("PERFORMANCE=NOT_CLAIMED")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except CheckError as error:
        print("A18_7_LINE_CACHE_CHECK=FAIL", file=sys.stderr)
        print("REASON={0}".format(error), file=sys.stderr)
        sys.exit(1)
