#!/usr/bin/env python3
"""Accept archived A17.6 function-run originals. No device access."""
from __future__ import print_function

import argparse
import hashlib
import sys
from pathlib import Path


EXPECTED_UUID = "622c839f-55f4-47c1-92e9-95ee5595ffa4"
EXPECTED_XCLBIN_SHA256 = (
    "b8d2034906451cc755b6c01a50c94a4b841998c3e2794c6e417dd1ab952e46ae"
)
EXPECTED_HOST_SOURCE_SHA256 = (
    "7073b4d976e54f73887c21714a3a4d8bdf65cdf3a272e620fb54c09963ee55ce"
)
EXPECTED_HOST_ELF_SHA256 = (
    "9ba376589f56d99efca6e42328d347a6539ba1c40bba56d21ab690d87e7f20fc"
)
GOLDENS = (
    ("CASE0", "baseline", -393),
    ("CASE1", "slot0_sensitivity", -392),
    ("CASE2", "slot1_sensitivity", -93),
    ("CASE3", "slot2_sensitivity", -689),
    ("CASE4", "slot3_sensitivity", -519),
)
RUN_FILES = (
    "host.log",
    "runner.log",
    "pre_device_query.txt",
    "a17_6_mem_map.txt",
    "connectivity.json",
    "mem_topology.json",
    "ip_layout.json",
    "dlrm_f37x_rtl_kernel_stage2n_a17_v1.xclbin.info",
)


class CheckError(Exception):
    pass


def require(condition, message):
    if not condition:
        raise CheckError(message)


def digest(path):
    hasher = hashlib.sha256()
    with Path(path).open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            hasher.update(block)
    return hasher.hexdigest()


def require_text(text, token, label):
    require(token in text, label + " missing " + token)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", type=Path, default=Path("."))
    args = parser.parse_args()
    repo = args.repo.resolve()
    archive = repo / "docs/evidence/stage2n_a17_6/function_pass_v1"
    run_dir = archive / "20260910_102244"
    status_path = archive / "host_build_status.txt"
    missing = []
    if not run_dir.is_dir():
        missing.append(str(run_dir))
    else:
        for name in RUN_FILES:
            path = run_dir / name
            if not path.is_file() or path.stat().st_size == 0:
                missing.append(str(path))
    if not status_path.is_file() or status_path.stat().st_size == 0:
        missing.append(str(status_path))
    if missing:
        print("A17_6_ORIGINAL_EVIDENCE_ARCHIVE=NOT_PRESENT")
        print("A17_6_ORIGINAL_EVIDENCE_ACCEPTANCE=NOT_RUN")
        print("PERFORMANCE=NOT_CLAIMED")
        for path in missing:
            print("MISSING=" + path)
        print("HINT=run handoff/copy_a17_6_function_evidence.ps1 in Windows PowerShell")
        return 2

    host = (run_dir / "host.log").read_text(encoding="utf-8", errors="replace")
    runner = (run_dir / "runner.log").read_text(encoding="utf-8", errors="replace")
    mem_map = (run_dir / "a17_6_mem_map.txt").read_text(encoding="utf-8", errors="replace")
    info = (run_dir / "dlrm_f37x_rtl_kernel_stage2n_a17_v1.xclbin.info").read_text(
        encoding="utf-8", errors="replace")
    status = status_path.read_text(encoding="utf-8", errors="replace")
    query = (run_dir / "pre_device_query.txt").read_text(
        encoding="utf-8", errors="replace")

    require_text(host, "STAGE2N_A17_6_FOUR_BO_HOST_V1=PASS", "host.log")
    require_text(host, "A17_6_BO_CLEANUP=PASS", "host.log")
    require_text(host, "A17_6_REPEAT_BASELINE=PASS", "host.log")
    require_text(host, "A17_6_PERFORMANCE=NOT_CLAIMED", "host.log")
    require_text(host, "XSIM_RESULT_36_NOT_USED=1", "host.log")
    require_text(host, EXPECTED_UUID, "host.log UUID")
    require("CASE0_ACTUAL_RESULT=36" not in host, "XSim 36 must not appear as a result")
    for prefix, name, value in GOLDENS:
        require_text(host, prefix + "_NAME=" + name, "host.log")
        require_text(host, prefix + "_EXPECTED_RESULT=" + str(value), "host.log")
        require_text(host, prefix + "_ACTUAL_RESULT=" + str(value), "host.log")
        require_text(host, prefix + "_EMBEDDING_LOADED_MASK=0xF", "host.log")
        require_text(host, prefix + "_BOTTOM_CYCLES_ACTUAL=322", "host.log")
        require_text(host, prefix + "_INTERACTION_CYCLES_ACTUAL=100", "host.log")
        require_text(host, prefix + "_TOP_CYCLES_ACTUAL=744", "host.log")
        require_text(host, prefix + "_COMPUTE_TOTAL_CYCLES_ACTUAL=1174", "host.log")
        require_text(host, prefix + "_BOTTOM_CYCLES_DELTA=0", "host.log")
        require_text(host, prefix + "_HBM_LOOKUP_CYCLES_ACTUAL=33", "host.log")
        require_text(host, prefix + "_FPGA_END_TO_END_CYCLES_ACTUAL=1210", "host.log")
        require_text(host, prefix + "_PIPELINE_OVERHEAD_CYCLES_ACTUAL=3", "host.log")
    require_text(host, "REPEAT_BASELINE_ACTUAL_RESULT=-393", "host.log")
    require_text(host, "REPEAT_BASELINE_HBM_LOOKUP_CYCLES_ACTUAL=33", "host.log")
    require_text(host, "BO0_TAG=HBM[0]", "host.log")
    require_text(host, "BO3_TAG=HBM[3]", "host.log")
    require_text(host, "BO0_PADDR_HEX=0x0000000000000000", "host.log")
    require_text(host, "BO1_PADDR_HEX=0x0000000010000000", "host.log")
    require_text(host, "BO2_PADDR_HEX=0x0000000020000000", "host.log")
    require_text(host, "BO3_PADDR_HEX=0x0000000030000000", "host.log")
    require_text(host, "CASE1_BO0_IMAGE=slot0_sensitivity", "host.log")
    require_text(host, "CASE2_BO1_IMAGE=slot1_sensitivity", "host.log")
    require_text(host, "CASE3_BO2_IMAGE=slot2_sensitivity", "host.log")
    require_text(host, "CASE4_BO3_IMAGE=slot3_sensitivity", "host.log")
    require(33 + 1174 + 3 == 1210, "counter-interval difference algebra")

    require_text(runner, "A17_6_FPGA_PROGRAMMING=SKIPPED_ALREADY_LOADED", "runner.log")
    require_text(runner, "A17_6_BOARD_FUNCTIONAL=HOST_RETURNED_PASS", "runner.log")
    require_text(runner, EXPECTED_XCLBIN_SHA256, "runner.log xclbin SHA")
    require_text(runner, "CURRENT_UUID=" + EXPECTED_UUID, "runner.log")
    require("INFO: xbutil program succeeded." not in runner,
            "this execute must not have programmed")
    require_text(runner, "FPGA_RESET=NOT_RUN", "runner.log")

    require_text(mem_map, "A17_6_MEM_MAP_V1", "mem map")
    require_text(mem_map, "UUID=" + EXPECTED_UUID, "mem map")
    require_text(mem_map, "ARG0_TAG=HBM[0]", "mem map")
    require_text(mem_map, "ARG3_TAG=HBM[3]", "mem map")
    require_text(info, EXPECTED_UUID, "xclbin.info")
    require_text(status, "SOURCE_SHA256=" + EXPECTED_HOST_SOURCE_SHA256, "host status")
    require_text(status, "BINARY_SHA256=" + EXPECTED_HOST_ELF_SHA256, "host status")
    require_text(status, "HOST_EXECUTION=NOT_RUN", "host status is compile-only")
    require_text(query, EXPECTED_UUID, "pre_device_query")
    require_text(query, "Level 0 : 0x0(GOOD)", "pre_device_query firewall")

    sha_path = archive / "ARCHIVED_SHA256.txt"
    lines = []
    for name in RUN_FILES:
        path = run_dir / name
        lines.append("{}  20260910_102244/{}".format(digest(path), name))
    lines.append("{}  host_build_status.txt".format(digest(status_path)))
    sha_path.write_text("\n".join(lines) + "\n", encoding="utf-8")

    print("A17_6_ORIGINAL_EVIDENCE_ARCHIVE=PASS")
    print("A17_6_ORIGINAL_EVIDENCE_ACCEPTANCE=PASS")
    print("FUNCTION=PASS")
    print("PROGRAMMING=SKIPPED_ALREADY_LOADED")
    print("OBSERVED_LOOKUP_COMPUTE_E2E_RESIDUAL=33/1174/1210/3")
    print("RESIDUAL=COUNTER_INTERVAL_DIFFERENCE")
    print("PERFORMANCE=NOT_CLAIMED")
    print("SHA256_LIST={}".format(sha_path))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except CheckError as error:
        print("A17_6_ORIGINAL_EVIDENCE_ACCEPTANCE=FAIL", file=sys.stderr)
        print("REASON={}".format(error), file=sys.stderr)
        sys.exit(1)
