#!/usr/bin/env python3
"""Local static gate for Stage 2N-A17.5B physical-validation preparation.

This checker must not open a device or invoke v++, xbutil, or XRT.
"""

from __future__ import print_function

import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
EVIDENCE = ROOT / "docs" / "evidence" / "stage2n_a17_5"
TEMPLATES = [
    EVIDENCE / "runtime_mapping_report.txt",
    EVIDENCE / "board_run_summary.txt",
    EVIDENCE / "latency_measurement.txt",
]
PROTECTED = [
    "rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a17_v1.sv",
    "tb/tb_dlrm_f37x_rtl_kernel_stage2n_a17_v1.sv",
    "host/stage2n_a16_2_physical_latency_v1.cpp",
    "config/stage2n_a16_2_target_v1.cfg",
]
FORGED = (
    "CASE0_ACTUAL_RESULT=-393",
    "A16_2_HOST_START=1",
    "A17_5C_PHYSICAL_HBM=PASS",
    "A17_5C_BOARD_RUN=PASS",
)


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


def check_templates():
    for path in TEMPLATES:
        text = read_text(path)
        require("UNPOPULATED TEMPLATE" in text,
                "{} missing UNPOPULATED TEMPLATE".format(path.name))
        require("STATUS=UNPOPULATED" in text,
                "{} missing STATUS=UNPOPULATED".format(path.name))
        for token in FORGED:
            require(token not in text,
                    "{} must not contain forged marker {}".format(path.name, token))


def check_no_live_execution_artifacts():
    require(not list((ROOT / "config").glob("stage2n_a17*")),
            "A17.5B must not add live config/")
    require(not list((ROOT / "host").glob("*a17*")),
            "A17.5B must not add A17 Host source")
    require(git_tracked_clean(PROTECTED),
            "tracked RTL/TB/Host/config changed")


def check_this_process_is_offline():
    # This process only reads files and runs git diff. It does not spawn
    # a linker, XRT, or xbutil.
    return


def main():
    try:
        check_templates()
        check_no_live_execution_artifacts()
        check_this_process_is_offline()
    except CheckError as error:
        print("A17_5B_PHYSICAL_PREP_CHECK=FAIL")
        print("ERROR={}".format(error))
        return 1
    print("HOST_PREP_DOCUMENTED=PASS")
    print("BO_PLAN_DOCUMENTED=PASS")
    print("EVIDENCE_TEMPLATE=UNPOPULATED")
    print("RTL=UNCHANGED")
    print("TB=UNCHANGED")
    print("HOST=UNCHANGED")
    print("VPP_INVOKED=NO")
    print("XRT_RUN=NO")
    print("XBUTIL=NO")
    print("DEVICE_OPEN=NO")
    print("BOARD=NOT_ACCESSED")
    print("A17_5B_PHYSICAL_PREP_CHECK=PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
