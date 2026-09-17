#!/usr/bin/env python3
"""Accept one A17.6 identity-gated function re-check.

This run's logged ELF/source trio can complete execution-artifact identity
for the new directory only. It does not backfill 20260910_102244.
Does not require lookup/e2e to equal the historical 33/1210 observation.
"""
from __future__ import print_function

import argparse
import hashlib
import re
import sys
from pathlib import Path


EXPECTED_UUID = "622c839f-55f4-47c1-92e9-95ee5595ffa4"
EXPECTED_XCLBIN_SHA256 = (
    "b8d2034906451cc755b6c01a50c94a4b841998c3e2794c6e417dd1ab952e46ae"
)
EXPECTED_HOST_ELF_SHA256 = (
    "9ba376589f56d99efca6e42328d347a6539ba1c40bba56d21ab690d87e7f20fc"
)
EXPECTED_HOST_SOURCE_SHA256 = (
    "7073b4d976e54f73887c21714a3a4d8bdf65cdf3a272e620fb54c09963ee55ce"
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


def field(text, name):
    match = re.search(r"^" + re.escape(name) + r"=(.*)\s*$", text, re.MULTILINE)
    require(match is not None, "missing field " + name)
    return match.group(1).strip()


def int_field(text, name):
    return int(field(text, name))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", type=Path, default=Path("."))
    parser.add_argument("--stamp", required=True)
    args = parser.parse_args()
    repo = args.repo.resolve()
    archive = repo / "docs/evidence/stage2n_a17_6/identity_recheck_v1"
    run_dir = archive / args.stamp
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
        print("A17_6_IDENTITY_RECHECK_ARCHIVE=NOT_PRESENT")
        print("A17_6_IDENTITY_RECHECK_ACCEPTANCE=NOT_RUN")
        print("PERFORMANCE=NOT_CLAIMED")
        for path in missing:
            print("MISSING=" + path)
        return 2

    host = (run_dir / "host.log").read_text(encoding="utf-8", errors="replace")
    runner = (run_dir / "runner.log").read_text(encoding="utf-8", errors="replace")
    mem_map = (run_dir / "a17_6_mem_map.txt").read_text(
        encoding="utf-8", errors="replace")
    info = (run_dir / "dlrm_f37x_rtl_kernel_stage2n_a17_v1.xclbin.info").read_text(
        encoding="utf-8", errors="replace")
    status = status_path.read_text(encoding="utf-8", errors="replace")
    query = (run_dir / "pre_device_query.txt").read_text(
        encoding="utf-8", errors="replace")

    require_text(runner, "A17_6_HOST_ELF_IDENTITY=PASS", "runner.log")
    require_text(runner, "HOST_IDENTITY_CHECKED_BEFORE_PROGRAM=YES", "runner.log")
    require_text(runner, "HOST_EXECUTE_SHA256=" + EXPECTED_HOST_ELF_SHA256,
                 "runner.log")
    require_text(runner, "HOST_SOURCE_SHA256=" + EXPECTED_HOST_SOURCE_SHA256,
                 "runner.log")
    require_text(runner, "HOST_EXPECTED_ELF_SHA256=" + EXPECTED_HOST_ELF_SHA256,
                 "runner.log")
    require_text(runner, "HOST_EXPECTED_SOURCE_SHA256=" + EXPECTED_HOST_SOURCE_SHA256,
                 "runner.log")
    require_text(runner, "HOST_EXIT_CODE=0", "runner.log")
    require_text(runner, "A17_6_FORCE_NO_PROGRAM=yes", "runner.log")
    require_text(runner, "ACTION_PROGRAM_FPGA_IF_NEEDED=NO_ALREADY_LOADED",
                 "runner.log")
    require_text(runner, "A17_6_PROGRAM=SKIPPED_ALREADY_LOADED", "runner.log")
    require_text(runner, "A17_6_FPGA_PROGRAMMING=SKIPPED_ALREADY_LOADED",
                 "runner.log")
    require("INFO: xbutil program succeeded." not in runner,
            "this re-check must not have programmed")
    require_text(runner, "CURRENT_UUID=" + EXPECTED_UUID, "runner.log")
    require_text(runner, EXPECTED_XCLBIN_SHA256, "runner.log xclbin SHA")
    require_text(runner, "A17_6_BOARD_FUNCTIONAL=HOST_RETURNED_PASS", "runner.log")
    require_text(runner, "FPGA_RESET=NOT_RUN", "runner.log")
    require_text(runner, "A17_6_PERFORMANCE=NOT_CLAIMED", "runner.log")

    require_text(host, "A17_6_HOST_START=1", "host.log")
    require_text(host, "STAGE2N_A17_6_FOUR_BO_HOST_V1=PASS", "host.log")
    require_text(host, "A17_6_BO_CLEANUP=PASS", "host.log")
    require_text(host, "A17_6_REPEAT_BASELINE=PASS", "host.log")
    require_text(host, "A17_6_ALL_FIVE_CASES=PASS", "host.log")
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
        require_text(host, prefix + "_INTERACTION_CYCLES_DELTA=0", "host.log")
        require_text(host, prefix + "_TOP_CYCLES_DELTA=0", "host.log")
        require_text(host, prefix + "_COMPUTE_TOTAL_CYCLES_DELTA=0", "host.log")
    require_text(host, "REPEAT_BASELINE_ACTUAL_RESULT=-393", "host.log")
    require_text(host, "BO0_TAG=HBM[0]", "host.log")
    require_text(host, "BO3_TAG=HBM[3]", "host.log")
    require_text(host, "BO0_HANDLE=", "host.log")
    require_text(host, "CASE1_BO0_IMAGE=slot0_sensitivity", "host.log")
    require_text(host, "CASE2_BO1_IMAGE=slot1_sensitivity", "host.log")
    require_text(host, "CASE3_BO2_IMAGE=slot2_sensitivity", "host.log")
    require_text(host, "CASE4_BO3_IMAGE=slot3_sensitivity", "host.log")

    lookup = int_field(host, "CASE0_HBM_LOOKUP_CYCLES_ACTUAL")
    compute = int_field(host, "CASE0_COMPUTE_TOTAL_CYCLES_ACTUAL")
    e2e = int_field(host, "CASE0_FPGA_END_TO_END_CYCLES_ACTUAL")
    residual = int_field(host, "CASE0_PIPELINE_OVERHEAD_CYCLES_ACTUAL")
    require(compute == 1174, "CASE0 compute is not 1174")
    require(lookup + compute + residual == e2e,
            "CASE0 residual algebra lookup+compute+residual != e2e")
    case4_lookup = int_field(host, "CASE4_HBM_LOOKUP_CYCLES_ACTUAL")
    case4_compute = int_field(host, "CASE4_COMPUTE_TOTAL_CYCLES_ACTUAL")
    case4_e2e = int_field(host, "CASE4_FPGA_END_TO_END_CYCLES_ACTUAL")
    case4_residual = int_field(host, "CASE4_PIPELINE_OVERHEAD_CYCLES_ACTUAL")
    require(case4_compute == 1174, "CASE4 compute is not 1174")
    require(case4_lookup + case4_compute + case4_residual == case4_e2e,
            "CASE4 residual algebra lookup+compute+residual != e2e")
    require_text(status, "SOURCE_SHA256=" + EXPECTED_HOST_SOURCE_SHA256,
                 "host status")
    require_text(status, "BINARY_SHA256=" + EXPECTED_HOST_ELF_SHA256,
                 "host status")
    require_text(mem_map, "UUID=" + EXPECTED_UUID, "mem map")
    require_text(mem_map, "ARG0_TAG=HBM[0]", "mem map")
    require_text(mem_map, "ARG3_TAG=HBM[3]", "mem map")
    require_text(info, EXPECTED_UUID, "xclbin.info")
    require_text(query, EXPECTED_UUID, "pre_device_query")
    require_text(query, "Level 0 : 0x0(GOOD)", "pre_device_query firewall")

    sha_path = archive / "ARCHIVED_SHA256.txt"
    lines = []
    for name in RUN_FILES:
        path = run_dir / name
        lines.append("{}  {}/{}".format(digest(path), args.stamp, name))
    lines.append("{}  host_build_status.txt".format(digest(status_path)))
    sha_path.write_text("\n".join(lines) + "\n", encoding="utf-8")

    print("A17_6_IDENTITY_RECHECK_ARCHIVE=PASS")
    print("A17_6_IDENTITY_RECHECK_ACCEPTANCE=PASS")
    print("FUNCTION=PASS")
    print("EXECUTION_ARTIFACT_IDENTITY=PASS_THIS_RUN_ONLY")
    print("HISTORICAL_102244_PRE_EXEC_HASH=STILL_MISSING")
    print("PROGRAMMING=SKIPPED_ALREADY_LOADED")
    print("HOST_EXIT_CODE=0")
    print("HOST_EXECUTE_SHA256=" + EXPECTED_HOST_ELF_SHA256)
    print("HOST_SOURCE_SHA256=" + EXPECTED_HOST_SOURCE_SHA256)
    print("OBSERVED_CASE0_LOOKUP_COMPUTE_E2E_RESIDUAL={}/{}/{}/{}".format(
        lookup, compute, e2e, residual))
    print("OBSERVED_CASE4_LOOKUP_COMPUTE_E2E_RESIDUAL={}/{}/{}/{}".format(
        case4_lookup, case4_compute, case4_e2e, case4_residual))
    print("OBSERVED_LOOKUP_COMPUTE_E2E_RESIDUAL={}/{}/{}/{}".format(
        lookup, compute, e2e, residual))
    print("RESIDUAL=COUNTER_INTERVAL_DIFFERENCE")
    print("NOTE=CASE4 lookup/e2e may differ from CASE0; function does not require 33")
    print("PERFORMANCE=NOT_CLAIMED")
    print("SHA256_LIST=" + str(sha_path))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except CheckError as error:
        print("A17_6_IDENTITY_RECHECK_ACCEPTANCE=FAIL", file=sys.stderr)
        print("REASON={}".format(error), file=sys.stderr)
        sys.exit(1)
