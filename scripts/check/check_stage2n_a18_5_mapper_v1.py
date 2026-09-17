#!/usr/bin/env python3
"""Bit-exact software golden for the A18.5 T=8/B=4 mapper. No device."""
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


def pack_banks(banks):
    value = 0
    for table_id, bank in enumerate(banks):
        value |= int(bank) << (2 * table_id)
    return value


def pack_occ(occ):
    value = 0
    for bank, count in enumerate(occ):
        value |= int(count) << (4 * bank)
    return value


def main():
    rtl = (ROOT / "rtl/hbm/dlrm_table_bank_mapper_stage2n_a18_5_v1.sv").read_text(
        encoding="utf-8")
    tb = (ROOT / "tb/tb_dlrm_table_bank_mapper_stage2n_a18_5_v1.sv").read_text(
        encoding="utf-8")
    require("MAP_COACC_SPLIT" in rtl, "coacc mapping missing")
    require("MAP_FORCE_01" in rtl, "force mapping missing")
    require("dlrm_f37x_rtl_kernel_stage2n_a18_v1" not in rtl,
            "must not edit boarded A18 into this mapper")
    require("unique case (mapping_sel)" in rtl, "mapping case missing")

    ident = ident_banks()
    coacc = coacc_split_banks()
    force = force_01_banks()
    require(ident == [0, 1, 2, 3, 0, 1, 2, 3], "ident banks")
    require(occupancy(ident) == [2, 2, 2, 2], "ident occupancy")
    require(coacc == [0, 1, 2, 3, 1, 2, 2, 3], "coacc split banks")
    require(occupancy(coacc) == [1, 2, 3, 2], "coacc occupancy")
    require(force == [0, 0, 2, 3, 0, 1, 2, 3], "force banks")
    require(occupancy(force) == [3, 1, 2, 2], "force occupancy matches A18.4 E5")
    require(coacc[0] != coacc[4], "pair 0,4 split")
    require(coacc[1] != coacc[5], "pair 1,5 split")
    require(ident[0] == ident[4], "ident keeps pair 0,4 on one bank")

    require("16'h2222" in tb, "TB ident occupancy")
    require("16'h2321" in tb, "TB coacc occupancy")
    require("16'h2213" in tb, "TB force occupancy")
    require(pack_occ([2, 2, 2, 2]) == 0x2222, "pack ident occ")
    require(pack_occ([1, 2, 3, 2]) == 0x2321, "pack coacc occ")
    require(pack_occ([3, 1, 2, 2]) == 0x2213, "pack force occ")
    require(pack_banks(ident) == 0xE4E4, "pack ident banks 11_10_01_00_11_10_01_00")
    require("TB_A18_5_MAPPER=PASS" in tb, "TB pass token")

    boarded = (ROOT / "rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a18_v1.sv").read_text(
        encoding="utf-8")
    require("dlrm_table_bank_mapper_stage2n_a18_5_v1" not in boarded,
            "boarded A18 kernel must stay unmapped")

    print("A18_5_MAPPER_CHECK=PASS")
    print("IDENT_BANKS=0,1,2,3,0,1,2,3")
    print("IDENT_OCCUPANCY=2,2,2,2")
    print("COACC_SPLIT_BANKS=0,1,2,3,1,2,2,3")
    print("COACC_SPLIT_OCCUPANCY=1,2,3,2")
    print("FORCE_01_BANKS=0,0,2,3,0,1,2,3")
    print("FORCE_01_OCCUPANCY=3,1,2,2")
    print("A18_BOARDED_KERNEL_UNCHANGED=PASS")
    print("CACHE=NOT_PRESENT")
    print("EXTRA_RUN=NOT_RUN")
    print("FPGA_PROGRAMMING=NOT_RUN")
    print("PHYSICAL_HBM=NOT_RUN")
    print("PERFORMANCE=NOT_CLAIMED")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except CheckError as error:
        print("A18_5_MAPPER_CHECK=FAIL", file=sys.stderr)
        print("REASON={0}".format(error), file=sys.stderr)
        sys.exit(1)
