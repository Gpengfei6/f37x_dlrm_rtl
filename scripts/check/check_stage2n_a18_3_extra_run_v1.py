#!/usr/bin/env python3
"""Static check for the A18.3 extra-run runner. Does not execute Host."""
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
    runner = (ROOT / "scripts/run_stage2n_a18_3_extra_run_v1.sh").read_text(
        encoding="utf-8")
    require("xbutil program" not in runner, "extra-run must never program")
    require("xbutil reset" not in runner, "extra-run must never reset")
    require("A18_3_EXTRA_RUN_AUTHORIZED" in runner, "authorization gate")
    require("32a9c911-af15-47fc-90c8-0bfe3894a3ef" in runner, "A18 UUID")
    require("011a0b8f" not in runner, "ELF SHA must come from env, not hardcoded")
    require("refuses to program" in runner, "UUID mismatch must refuse program")
    require("PERFORMANCE=NOT_CLAIMED" in runner, "no speedup")
    boarded = (ROOT / "rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a18_v1.sv").read_text(
        encoding="utf-8")
    require("dlrm_hbm_t8_mapped_lookup_stage2n_a18_6_v1" not in boarded,
            "extra-run still uses boarded A18, not T=8 RTL")

    print("A18_3_EXTRA_RUN_CHECK=PASS")
    print("A18_3_EXTRA_RUN=NOT_RUN")
    print("FPGA_PROGRAMMING=NOT_RUN")
    print("FPGA_RESET=NOT_RUN")
    print("PERFORMANCE=NOT_CLAIMED")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except CheckError as error:
        print("A18_3_EXTRA_RUN_CHECK=FAIL", file=sys.stderr)
        print("REASON={0}".format(error), file=sys.stderr)
        sys.exit(1)
