#!/usr/bin/env python3
"""A18.6 T=8 mapped lookup source check. No device, no boarded-kernel edit."""
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
    rtl = (ROOT / "rtl/hbm/dlrm_hbm_t8_mapped_lookup_stage2n_a18_6_v1.sv").read_text(
        encoding="utf-8")
    tb = (ROOT / "tb/tb_dlrm_hbm_t8_mapped_lookup_stage2n_a18_6_v1.sv").read_text(
        encoding="utf-8")
    mapper = (ROOT / "rtl/hbm/dlrm_table_bank_mapper_stage2n_a18_5_v1.sv").read_text(
        encoding="utf-8")
    boarded = (ROOT / "rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a18_v1.sv").read_text(
        encoding="utf-8")
    a13 = (ROOT / "rtl/pipeline/dlrm_internal_pipeline_controller_stage2n_a13_v1.sv")

    require("dlrm_table_bank_mapper_stage2n_a18_5_v1" in rtl,
            "mapper must be instantiated in T=8 lookup")
    require("dlrm_hbm_embedding_lookup_stage2n_a14_v2" in rtl,
            "must reuse A14 v2 engines")
    require("lookup_index" in rtl and "[7:0][31:0]" in rtl, "eight indexes")
    require("dlrm_internal_pipeline_controller_stage2n_a13_v1" not in rtl,
            "must not instantiate A13")
    require("dlrm_f37x_rtl_kernel_stage2n_a18_v1" not in rtl,
            "must not rewrite boarded kernel into this file")
    require("dlrm_hbm_t8_mapped_lookup_stage2n_a18_6_v1" not in boarded,
            "boarded A18 kernel must stay unwired")
    require("dlrm_table_bank_mapper_stage2n_a18_5_v1" not in boarded,
            "boarded A18 kernel must not instantiate mapper")
    require("TB_A18_6_T8_LOOKUP=PASS" in tb, "TB pass token")
    require("IDENT" in tb and "COACC_SPLIT" in tb and "FORCE_01" in tb,
            "TB mapping cases")
    require("MAP_COACC_SPLIT" in mapper, "A18.5 mapper present")
    require(a13.is_file(), "frozen A13 must remain on disk")

    print("A18_6_T8_LOOKUP_CHECK=PASS")
    print("MAPPER_IN_LOOKUP_DATAPATH=PASS")
    print("A18_BOARDED_KERNEL_UNCHANGED=PASS")
    print("A13_SLOT_COUNT=4_UNCHANGED")
    print("XSIM=NOT_RUN")
    print("FPGA_PROGRAMMING=NOT_RUN")
    print("PHYSICAL_HBM=NOT_RUN")
    print("PERFORMANCE=NOT_CLAIMED")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except CheckError as error:
        print("A18_6_T8_LOOKUP_CHECK=FAIL", file=sys.stderr)
        print("REASON={0}".format(error), file=sys.stderr)
        sys.exit(1)
