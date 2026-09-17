#!/usr/bin/env python3
"""Local static gate for Stage 2N-A17.5C execution-checklist preparation.

This is not physical execution. The checker must not open a device or spawn
v++, xbutil, or XRT. Frozen A16.2 scripts that already contain those tools
are out of scope; this gate forbids new A17 execution code.
"""

from __future__ import print_function

import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
GATE_DOC = ROOT / "docs" / "STAGE2N_A17_5C_EXECUTION_GATE_V1.md"
RISK_DOC = ROOT / "analysis" / "stage2n_a17_5" / "a17_5c_risk_register.md"
NEW_A17_5C_DOCS = [
    "docs/STAGE2N_A17_5C_EXECUTION_GATE_V1.md",
    "analysis/stage2n_a17_5/a17_5c_risk_register.md",
]
PROTECTED = [
    "rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a17_v1.sv",
    "tb/tb_dlrm_f37x_rtl_kernel_stage2n_a17_v1.sv",
    "host/stage2n_a16_2_physical_latency_v1.cpp",
    "config/stage2n_a16_2_target_v1.cfg",
]
FORBIDDEN_NEW = (
    "xclOpen(",
    "xrt::device",
    "xbutil ",
)
VPP_INVOKE = "v" + "++ --"


class CheckError(Exception):
    pass


def require(condition, message):
    if not condition:
        raise CheckError(message)


def read_text(path):
    require(path.is_file(), "missing file: {}".format(path))
    return path.read_text(encoding="utf-8")


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


def check_docs():
    gate = read_text(GATE_DOC)
    require("AUTHORIZED EXECUTION ONLY" in gate,
            "execution gate missing authorization language")
    require("A17_5C_PHYSICAL_MULTI_BANK_VALIDATION=NOT_RUN" in gate,
            "gate must not pre-declare physical multi-bank validation")
    for token in (
        "xclbin PASS",
        "device PASS",
        "BO mapping PASS",
        "kernel run PASS",
        "latency measured",
    ):
        require(token in gate, "success criterion missing: {}".format(token))
    require("m_axi_gmem0" in gate and "HBM[0]" in gate, "gmem0 mapping missing")
    require("m_axi_gmem3" in gate and "HBM[3]" in gate, "gmem3 mapping missing")
    risk = read_text(RISK_DOC)
    for token in (
        "Connectivity",
        "same bank",
        "group",
        "UUID",
        "Latency",
        "bottleneck",
    ):
        require(token.lower() in risk.lower(),
                "risk register missing {}".format(token))


def check_no_new_execution_code():
    require(not list((ROOT / "host").glob("*a17*")),
            "A17.5C gate must not add Host execution source")
    require(not list((ROOT / "config").glob("stage2n_a17*")),
            "A17.5C gate must not add live config/")
    runners = list((ROOT / "scripts").glob("*a17_5c*"))
    extra = [path.name for path in runners
             if path.suffix in (".sh", ".ps1", ".tcl", ".cpp")]
    require(not extra, "A17.5C must not add execution runners: {}".format(extra))
    for relative in NEW_A17_5C_DOCS:
        text = read_text(ROOT / relative)
        require(VPP_INVOKE not in text,
                "{} must not contain a v++ command".format(relative))
        for token in FORBIDDEN_NEW:
            require(token not in text,
                    "{} must not add execution token {}".format(relative, token))


def check_protected():
    require(git_tracked_clean(PROTECTED),
            "rtl/tb/host/config tracked files changed")


def main():
    try:
        check_docs()
        check_no_new_execution_code()
        check_protected()
    except CheckError as error:
        print("A17_5C_EXECUTION_GATE_CHECK=FAIL")
        print("ERROR={}".format(error))
        return 1
    print("EXECUTION_CHECKLIST=DONE")
    print("RISK_REGISTER=DONE")
    print("RTL=UNCHANGED")
    print("TB=UNCHANGED")
    print("HOST=UNCHANGED")
    print("CONFIG=UNCHANGED")
    print("VPP_INVOKED=NO")
    print("DEVICE_OPEN=NO")
    print("BOARD=NOT_ACCESSED")
    print("READY=AUTHORIZED_EXECUTION_ONLY")
    print("A17_5C_EXECUTION_GATE_CHECK=PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
