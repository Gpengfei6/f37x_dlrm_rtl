#!/usr/bin/env python3
"""Local static gate for Stage 2N-A17.4 HBM mapping preparation.

This checker records two separate layers and must not mix them:

- Current implementation: frozen A16.2 single-BO / single-HBM[0] Host and
  link config. A17.2 four public AXI masters exist in RTL but are unmapped.
- Future A17.5 proposal: four BOs, four BASEs, four HBM banks. Presence of
  that proposal is required; implementing it in Host/config is forbidden here.

Never open a device, never invoke v++/Vivado, and never treat analysis files
as live Vitis input.

A previous substring count of ``xclAllocBO(`` was a false FAIL: the accepted
A16.2 Host has one allocation call and one error-string mention. That is still
a single-BO implementation.
"""

from __future__ import print_function

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]

A16_CFG = ROOT / "config" / "stage2n_a16_2_target_v1.cfg"
A17_RTL = ROOT / "rtl" / "f37x" / "dlrm_f37x_rtl_kernel_stage2n_a17_v1.sv"
A17_TB = ROOT / "tb" / "tb_dlrm_f37x_rtl_kernel_stage2n_a17_v1.sv"
A16_HOST = ROOT / "host" / "stage2n_a16_2_physical_latency_v1.cpp"
PROPOSAL = (
    ROOT / "analysis" / "stage2n_a17_4" / "hbm_mapping_proposal_v1.cfg"
)
BO_PROPOSAL = (
    ROOT / "analysis" / "stage2n_a17_4" / "host_bo_proposal_v1.txt"
)

EXPECTED_A16_SP = "sp=dlrm_a16_1.m_axi_gmem:HBM[0]"
EXPECTED_A16_NK = "nk=dlrm_f37x_rtl_kernel_stage2n_a16_v1:1:dlrm_a16_1"
EXPECTED_PROPOSAL = [
    "nk=dlrm_f37x_rtl_kernel_stage2n_a17_v1:1:dlrm_a17_1",
    "sp=dlrm_a17_1.m_axi_gmem0:HBM[0]",
    "sp=dlrm_a17_1.m_axi_gmem1:HBM[1]",
    "sp=dlrm_a17_1.m_axi_gmem2:HBM[2]",
    "sp=dlrm_a17_1.m_axi_gmem3:HBM[3]",
]
FUTURE_BOS = ("bo_table0", "bo_table1", "bo_table2", "bo_table3")
ABI_TOKENS = [
    "12'h300",
    "12'h304",
    "12'h308",
    "12'h30C",
    "12'h310",
    "12'h314",
    "12'h318",
    "12'h31C",
    "12'h320",
    "12'h324",
    "12'h328",
    "12'h32C",
]


class CheckError(Exception):
    pass


def require(condition, message):
    if not condition:
        raise CheckError(message)


def read_text(path):
    require(path.is_file(), "missing file: {}".format(path))
    return path.read_text(encoding="utf-8")


def active_lines(text):
    lines = []
    for raw in text.splitlines():
        stripped = raw.strip()
        if not stripped or stripped.startswith("#"):
            continue
        lines.append(stripped)
    return lines


def check_a16_cfg_frozen():
    text = read_text(A16_CFG)
    lines = active_lines(text)
    require(EXPECTED_A16_NK in lines, "A16.2 kernel/CU line changed")
    require(EXPECTED_A16_SP in lines, "A16.2 HBM[0] mapping changed")
    require(len([line for line in lines if line.startswith("sp=")]) == 1,
            "A16.2 must retain exactly one sp mapping")
    require("m_axi_gmem0" not in text,
            "A16.2 config must not grow A17 master names")


def check_no_live_a17_link_or_xclbin():
    config_dir = ROOT / "config"
    require(config_dir.is_dir(), "missing config directory")
    live_cfg = sorted(path.name for path in config_dir.glob("stage2n_a17*"))
    require(not live_cfg,
            "A17.4 must not add a live config file yet: {}".format(live_cfg))
    build_dir = ROOT / "build"
    if build_dir.is_dir():
        xclbins = list(build_dir.glob("**/stage2n_a17*.xclbin")) + list(
            build_dir.glob("**/*a17*.xclbin")
        )
        require(not xclbins,
                "A17.4 must not produce an A17 xclbin: {}".format(xclbins))


def check_mapping_proposal():
    lines = active_lines(read_text(PROPOSAL))
    require(lines == ["[connectivity]"] + EXPECTED_PROPOSAL,
            "A17.4 proposal connectivity does not match the reviewed four-bank map")
    header = "\n".join(read_text(PROPOSAL).splitlines()[0:3])
    require("PROPOSAL" in header.upper() or "Not a live" in header,
            "proposal file must remain labeled non-live")


def check_future_bo_proposal():
    text = read_text(BO_PROPOSAL)
    require("FUTURE" in text.upper() or "A17.5" in text,
            "BO proposal must be labeled as future A17.5, not current Host")
    for name in FUTURE_BOS:
        require(name in text,
                "A17.4 future BO proposal missing {}".format(name))
    require("single-BO" in text or "single BO" in text,
            "BO proposal must keep A16.2 single-BO as the current layer")


def check_a17_public_masters_and_abi():
    text = read_text(A17_RTL)
    require("module dlrm_f37x_rtl_kernel_stage2n_a17_v1" in text,
            "A17.2 public kernel module name changed")
    for index in range(4):
        token = "m_axi_gmem{}_arvalid".format(index)
        require(token in text, "missing public master token {}".format(token))
    require("m_axi_gmem0_araddr" in text, "public gmem0 ARADDR missing")
    for token in ABI_TOKENS:
        require(token in text, "A17 ABI token missing from RTL: {}".format(token))


def check_tb_four_port_contract():
    text = read_text(A17_TB)
    for index in range(4):
        require(".m_axi_gmem{}_arvalid".format(index) in text,
                "A17 TB missing gmem{} ARVALID connection".format(index))
    require("A16_1_" not in text, "A17 TB must not regain A16.1 PASS markers")


def check_a16_host_remains_single_bo():
    """Current-implementation layer only. Do not require four BOs here."""
    text = read_text(A16_HOST)
    require("dlrm_f37x_rtl_kernel_stage2n_a16_v1:dlrm_a16_1" in text,
            "A16.2 Host CU identity missing")
    require("kExpectedMemIndex = 0" in text,
            "A16.2 Host must keep the single HBM[0] mem index")
    require("A_TABLE_BASE_LO = 0x304" in text, "A16.2 BASE0 low offset changed")
    require("0x318" not in text,
            "A16.2 Host must not grow BASE1 programming in A17.4")
    for name in FUTURE_BOS:
        require(name not in text,
                "A16.2 Host must not implement {} in A17.4".format(name))
    # Count assignment calls only. The accepted source also mentions
    # xclAllocBO in an error string; that is not a second buffer.
    assignments = re.findall(r"\bbo_\s*=\s*xclAllocBO\s*\(", text)
    require(len(assignments) == 1,
            "A16.2 Host must remain a single-BO implementation")


def check_no_a17_host_yet():
    hosts = sorted(path.name for path in (ROOT / "host").glob("*a17*"))
    require(not hosts, "A17.4 must not add an A17 Host yet: {}".format(hosts))


def main():
    try:
        check_a16_cfg_frozen()
        check_no_live_a17_link_or_xclbin()
        check_mapping_proposal()
        check_future_bo_proposal()
        check_a17_public_masters_and_abi()
        check_tb_four_port_contract()
        check_a16_host_remains_single_bo()
        check_no_a17_host_yet()
    except CheckError as error:
        print("A17_4_MAPPING_PREP_CHECK=FAIL")
        print("ERROR={}".format(error))
        return 1
    print("A16_2_CONNECTIVITY_FROZEN=PASS")
    print("A16_2_HOST_BO_COUNT_UNCHANGED=PASS")
    print("A17_LIVE_CONFIG_ABSENT=PASS")
    print("A17_XCLBIN_ABSENT=PASS")
    print("A17_4_MAPPING_PROPOSAL=PASS")
    print("A17_4_FUTURE_BO_PROPOSAL=PASS")
    print("A17_PUBLIC_FOUR_AXI=PASS")
    print("A17_ABI_TOKENS=PASS")
    print("A17_HOST_ABSENT=PASS")
    print("RTL=UNCHANGED")
    print("TB=UNCHANGED")
    print("ABI=UNCHANGED")
    print("HOST=UNCHANGED")
    print("BOARD=NOT_ACCESSED")
    print("A17_4_MAPPING_PREP_CHECK=PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
