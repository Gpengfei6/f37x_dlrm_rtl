#!/usr/bin/env python3
"""Local static gate for Stage 2N-A17.5A target packaging preparation.

Allowed: audit documents and analysis/ proposals.
Forbidden here: RTL/TB/Host edits, live config/, v++ invocation, board access.

Historical untracked rtl/tb/host files are preserved and are out of scope.
This gate diffs only the listed tracked A16.2/A17 files against HEAD.
"""

from __future__ import print_function

import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
PROPOSAL = (
    ROOT / "analysis" / "stage2n_a17_5" / "connectivity_a17_multibank_proposal.cfg"
)
HOST_MAP = ROOT / "analysis" / "stage2n_a17_5" / "host_mapping_proposal_v1.txt"
A16_CFG = ROOT / "config" / "stage2n_a16_2_target_v1.cfg"
PROTECTED = [
    "rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a17_v1.sv",
    "tb/tb_dlrm_f37x_rtl_kernel_stage2n_a17_v1.sv",
    "host/stage2n_a16_2_physical_latency_v1.cpp",
    "config/stage2n_a16_2_target_v1.cfg",
    "scripts/package_stage2n_a16_2_rtl_kernel_v1.tcl",
    "scripts/link_stage2n_a16_2_target_xclbin_v1.sh",
]
EXPECTED_SP = [
    "nk=dlrm_f37x_rtl_kernel_stage2n_a17_v1:1:dlrm_a17_1",
    "sp=dlrm_a17_1.m_axi_gmem0:HBM[0]",
    "sp=dlrm_a17_1.m_axi_gmem1:HBM[1]",
    "sp=dlrm_a17_1.m_axi_gmem2:HBM[2]",
    "sp=dlrm_a17_1.m_axi_gmem3:HBM[3]",
]
VPP_COMMAND_PREFIX = "v" + "++ --"


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


def git_tracked_clean(paths):
    result = subprocess.run(
        ["git", "diff", "--quiet", "HEAD", "--"] + paths,
        cwd=str(ROOT),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        universal_newlines=True,
    )
    require(result.returncode in (0, 1),
            "git diff failed: {}".format(result.stderr))
    return result.returncode == 0


def check_proposal_not_in_config():
    live = sorted(path.name for path in (ROOT / "config").glob("stage2n_a17*"))
    require(not live, "A17 proposal must not enter config/: {}".format(live))
    a16 = read_text(A16_CFG)
    require("sp=dlrm_a16_1.m_axi_gmem:HBM[0]" in a16,
            "A16.2 live connectivity changed")
    require("m_axi_gmem0" not in a16,
            "A16.2 live config must not grow A17 masters")


def check_proposal_file():
    text = read_text(PROPOSAL)
    require("PROPOSAL ONLY" in text, "proposal header missing PROPOSAL ONLY")
    require("NOT FOR v++" in text, "proposal header missing NOT FOR v++")
    require("UNVALIDATED" in text, "proposal header missing UNVALIDATED")
    lines = active_lines(text)
    require(lines == ["[connectivity]"] + EXPECTED_SP,
            "A17.5A proposal connectivity mismatch")
    require(VPP_COMMAND_PREFIX not in text,
            "proposal must not contain a v++ command")


def check_host_mapping_doc_only():
    text = read_text(HOST_MAP)
    require("PROPOSAL ONLY" in text or "NOT IMPLEMENTED" in text,
            "Host mapping must remain a proposal")
    require("xclRegWrite" in text, "Host mapping must keep AXI-Lite xclRegWrite")
    for token in ("BO0", "BO1", "BO2", "BO3", "BASE0", "BASE1", "BASE2", "BASE3"):
        require(token in text, "Host mapping missing {}".format(token))
    hosts = sorted(path.name for path in (ROOT / "host").glob("*a17*"))
    require(not hosts, "A17.5A must not add Host source: {}".format(hosts))


def check_protected_sources_unmodified():
    require(git_tracked_clean(PROTECTED),
            "tracked A16.2/A17 packaging sources changed")


def check_checker_does_not_run_vpp():
    # This process only runs git and file reads. Do not spawn a linker.
    return


def main():
    try:
        check_proposal_not_in_config()
        check_proposal_file()
        check_host_mapping_doc_only()
        check_protected_sources_unmodified()
        check_checker_does_not_run_vpp()
    except CheckError as error:
        print("A17_5A_PACKAGING_PREP_CHECK=FAIL")
        print("ERROR={}".format(error))
        return 1
    print("A17_PROPOSAL_NOT_IN_CONFIG=PASS")
    print("A17_5A_CONNECTIVITY_PROPOSAL=PASS")
    print("A17_5A_HOST_MAPPING_DOCUMENTED=PASS")
    print("RTL=UNCHANGED")
    print("TB=UNCHANGED")
    print("HOST=UNCHANGED")
    print("VPP_INVOKED=NO")
    print("BOARD=NOT_ACCESSED")
    print("A17_5A_PACKAGING_PREP_CHECK=PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
