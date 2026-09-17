#!/usr/bin/env python3
"""Local static gate for A18.2 packaging and Host ABI. Not XO/xclbin/board PASS."""
from __future__ import print_function

import argparse
import json
import subprocess
import sys
from pathlib import Path

ROOT_DEFAULT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT_DEFAULT / "scripts"))

from validate_stage2n_a18_2_artifacts_v1 import (  # noqa: E402
    KERNEL, CU, CONFIG, PACKAGE, digest, source_check,
)


LOCKED_GOLDENS = (-393, -392, -93, -689, -519)


class CheckError(Exception):
    pass


def require(condition, message):
    if not condition:
        raise CheckError(message)


def check_host(repo):
    host = (repo / "host/stage2n_a18_2_four_bo_host_v1.cpp").read_text(encoding="utf-8")
    for token in (
        "dlrm_f37x_rtl_kernel_stage2n_a18_v1:dlrm_a18_1",
        "kExpectedPipeVersion = 0x00024E18",
        "0x330",
        "0x334",
        "0x338",
        "0x33C",
        "write_and_readback_indexes",
        "A18_2_LOOKUP_INDEXES",
        "kDefaultLookupIndexes",
        "A18_2_MEM_MAP_V1",
        "xclRegWrite",
        "FourBo",
        "XSim result 36 is not a board golden",
        "-393, -392, -93, -689, -519",
        "kRejectedA17Needle",
        "non-default lookup indexes are not in the A18.2 five-case Host",
    ):
        require(token in host, "Host token missing: " + token)
    require("kExpectedPipeVersion = 0x00024E17" not in host, "Host still uses A17 version")
    require("dlrm_a17_1" in host, "Host must still reject the A17 CU needle")
    require("xclSetKernelArg" not in host, "indexes must not be kernel arguments")
    require("LOOKUP_INDEX0=" in host, "Host must log programmed indexes")
    build = (repo / "scripts/build_stage2n_a18_2_host_v1.sh").read_text(encoding="utf-8")
    require("HOST_EXECUTION=NOT_RUN" in build, "Host build must not execute")
    require("XBUTIL=NOT_INVOKED" in build, "Host build must not call xbutil")
    require("stage2n_a18_2_four_bo_host_v1.cpp" in build, "build script source")
    parser = (repo / "scripts/parse_stage2n_a18_2_xclbin_map_v1.py").read_text(encoding="utf-8")
    require("A18_2_MEM_MAP_V1" in parser, "map header")
    require("not assumed to be 0..3" in parser, "map parser must not assume 0..3")


def check_packaging(repo):
    tcl = (repo / PACKAGE).read_text(encoding="utf-8")
    require("dlrm_f37x_rtl_kernel_stage2n_a18_v1" in tcl, "package top")
    require("A18_2_XO_DIR" in tcl, "XO dir env")
    require("LOOKUP_INDEX0" in tcl, "package must reject index pointer args")
    require("exactly four pointer arguments" in tcl, "four TABLE_BASE args")
    cfg = (repo / CONFIG).read_text(encoding="utf-8")
    require("dlrm_a18_1.m_axi_gmem3:HBM[3]" in cfg, "HBM[3] map")
    require("dlrm_f37x_rtl_kernel_stage2n_a17_v1" not in cfg, "cfg must not name A17")
    source_check(repo)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", type=Path, default=ROOT_DEFAULT)
    args = parser.parse_args()
    repo = args.repo.resolve()
    check_packaging(repo)
    check_host(repo)
    golden = subprocess.run(
        [sys.executable, str(repo / "python/eval_stage2n_a18_2_index_golden_v1.py"),
         "--repo", str(repo), "--self-test",
         "--write-extras", str(repo / "models/stage2n_a18_2/index_goldens_v1.json")],
        cwd=str(repo),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        universal_newlines=True,
    )
    require(golden.returncode == 0, "index golden self-test failed: " + golden.stderr)
    require("A18_2_INDEX_GOLDEN_SELFTEST=PASS" in golden.stdout, "golden marker")
    extras = json.loads(
        (repo / "models/stage2n_a18_2/index_goldens_v1.json").read_text(encoding="utf-8"))
    require(extras.get("schema") == "a18_2_index_goldens_v1", "extras schema")
    require(len(extras.get("extras", [])) >= 1, "extras missing")
    print("A18_2_LOCAL_PREP_CHECK=PASS")
    print("A18_2_SOURCE_INTEGRITY=PASS")
    print("A18_2_INDEX_GOLDEN_SELFTEST=PASS")
    print("A18_2_HOST_ABI=PASS")
    print("KERNEL={}".format(KERNEL))
    print("CU={}".format(CU))
    print("MANIFEST_SHA256={}".format(digest(repo / "config/stage2n_a18_2_sources_v1.json")))
    print("A18_2_TARGET_XO=NOT_RUN")
    print("A18_2_TARGET_LINK=NOT_RUN")
    print("A18_2_XCLBIN=NOT_RUN")
    print("A18_2_BOARD=NOT_RUN")
    print("A18_2_PERFORMANCE=NOT_CLAIMED")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except CheckError as error:
        print("A18_2_LOCAL_PREP_CHECK=FAIL", file=sys.stderr)
        print("REASON={}".format(error), file=sys.stderr)
        sys.exit(1)
