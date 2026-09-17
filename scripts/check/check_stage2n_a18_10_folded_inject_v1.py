#!/usr/bin/env python3
"""A18.10 folded-inject source/ABI checks plus locked software goldens."""
from __future__ import print_function

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


class CheckError(Exception):
    pass


def require(condition, message):
    if not condition:
        raise CheckError(message)


def main():
    rtl = (ROOT / "rtl/hbm/dlrm_hbm_t8_folded_inject_stage2n_a18_10_v1.sv").read_text(
        encoding="utf-8")
    tb = (ROOT / "tb/tb_dlrm_hbm_t8_folded_inject_stage2n_a18_10_v1.sv").read_text(
        encoding="utf-8")
    boarded = (ROOT / "rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a18_v1.sv").read_text(
        encoding="utf-8")
    require("dlrm_hbm_t8_folded_lookup_stage2n_a18_9_v1" in rtl, "wrap A18.9")
    require("cfg_valid" in rtl and "cfg_index" in rtl, "A13 cfg handshake")
    require("dlrm_internal_pipeline_controller_stage2n_a13_v1" not in rtl,
            "must not instantiate A13")
    require("dlrm_hbm_t8_folded_inject_stage2n_a18_10_v1" not in boarded,
            "boarded A18 kernel must stay unwired")
    require("dlrm_hbm_t8_folded_lookup_stage2n_a18_9_v1" not in boarded,
            "boarded A18 kernel must stay unwired")
    require("BACKPRESSURE" in tb, "cfg backpressure case")
    require("OOB" in tb, "OOB case")
    require("TB_A18_10_FOLDED_INJECT=PASS" in tb, "TB pass token")
    proc = subprocess.run(
        [sys.executable, str(ROOT / "python/eval_stage2n_a18_10_t8_fold_golden_v1.py")],
        cwd=str(ROOT),
        check=False,
    )
    require(proc.returncode == 0, "fold-then-A13 software golden")
    print("A18_10_FOLDED_INJECT_CHECK=PASS")
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
        print("A18_10_FOLDED_INJECT_CHECK=FAIL", file=sys.stderr)
        print("REASON={0}".format(error), file=sys.stderr)
        sys.exit(1)
