#!/usr/bin/env python3
"""Local static gate for the A17.6 four-BO Host and protected prepare flow.

Does not open a device, invoke v++, xbutil, XRT, or claim a board PASS.
"""
from __future__ import print_function

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path


LOCKED_GOLDENS = (-393, -392, -93, -689, -519)
LOCKED_NAMES = (
    "baseline",
    "slot0_sensitivity",
    "slot1_sensitivity",
    "slot2_sensitivity",
    "slot3_sensitivity",
)
EXPECTED_XCLBIN_SHA256 = (
    "b8d2034906451cc755b6c01a50c94a4b841998c3e2794c6e417dd1ab952e46ae"
)
EXPECTED_UUID = "622c839f-55f4-47c1-92e9-95ee5595ffa4"
STALE_XO_SHA256 = (
    "1bd10d1f2a8307380ca95922e13c1680fcc7c96aeb15189ced3dff1b58a2a047"
)
LIVE_XO_SHA256 = (
    "15ded79ff75e7a12c464a8b1d65cc863cc6535ead673ba0ba445bb5e69a56be6"
)
A16_2_HOST_LOG = Path(
    "docs/evidence/stage2n_a16_2/final_acceptance_v1/"
    "physical_latency_v1/20260831_182443/host.log"
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


def lock_goldens(repo):
    manifest_path = repo / "models/stage2n_a15_6/stage2n_a15_6_cases_v1.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    require(manifest.get("format") == "STAGE2N_A15_6_CASES_V1", "case manifest format")
    cases = manifest["cases"]
    require(len(cases) == 5, "five functional cases")
    model = repo / "models/stage2n_a15_6" / manifest["model_asset"]["file"]
    require(digest(model) == manifest["model_asset"]["sha256"], "model SHA")
    for index, case in enumerate(cases):
        require(case["name"] == LOCKED_NAMES[index], "case name " + str(index))
        require(case["expected_final_result"] == LOCKED_GOLDENS[index],
                "golden mismatch " + case["name"])
        table = repo / "models/stage2n_a15_6" / case["file"]
        require(table.stat().st_size == 1024, "table bytes " + case["name"])
        require(digest(table) == case["payload_sha256"], "table SHA " + case["name"])
    host_log = repo / A16_2_HOST_LOG
    log_text = host_log.read_text(encoding="utf-8", errors="replace")
    for index, value in enumerate(LOCKED_GOLDENS):
        require("CASE{}_EXPECTED_RESULT={}".format(index, value) in log_text,
                "A16.2 host.log missing expected {}".format(value))
        require("CASE{}_ACTUAL_RESULT={}".format(index, value) in log_text,
                "A16.2 host.log missing actual {}".format(value))
    require("CASE0_ACTUAL_RESULT=36" not in log_text, "A16.2 log is not XSim 36")
    return cases


def check_host(repo, cases):
    host = (repo / "host/stage2n_a17_6_four_bo_host_v1.cpp").read_text(encoding="utf-8")
    for token in (
        "dlrm_f37x_rtl_kernel_stage2n_a17_v1:dlrm_a17_1",
        "kExpectedPipeVersion = 0x00024E17",
        "A_TABLE_BASE_LO",
        "0x318",
        "0x320",
        "0x328",
        "load_mem_map",
        "xclRegWrite",
        "xclAllocBO",
        "xclSyncBO",
        "FourBo",
        "kLockedGoldens",
        "XSim result 36 is not a board golden",
        "A16_2_LOOKUP_112_NOT_REQUIRED",
        "BOTTOM_CYCLES_ACTUAL",
        "BOTTOM_CYCLES_DELTA",
        "REPEAT_BASELINE_",
        "load_restored_case",
        "_IMAGE=",
        "A physical address of zero is valid",
        "requested_mem_index_",
        "dlrm_a16_1",
    ):
        require(token in host, "Host token missing: " + token)
    require("kExpectedMemIndex = 0" not in host,
            "Host must not hardcode a single mem_index 0")
    require('key.size() >= 14 && key.compare(0, 3, "ARG")' not in host,
            "Host must parse ARG0_TAG (8 chars); do not require key size 14")
    require('key.size() >= 8 && key.compare(0, 3, "ARG")' in host,
            "Host must accept ARG0_TAG and ARG0_MEM_INDEX keys")
    require(host.count("bo_ = xclAllocBO") == 1,
            "Host should allocate through one helper, four times at runtime")
    require("kBankCount = 4" in host, "four banks")
    require("kLockedGoldens = {{\n    -393, -392, -93, -689, -519\n}}" in host or
            "-393, -392, -93, -689, -519" in host,
            "Host locked goldens must match A15.6/A16.2")
    for value in LOCKED_GOLDENS:
        require(str(value) in host, "Host missing locked golden " + str(value))
    require("36" in host and "not a board golden" in host,
            "Host must reject XSim 36 as a board golden")
    require("112" in host and "NOT_REQUIRED" in host,
            "Host must not require A16.2 lookup 112")
    require("load_and_sync_all" not in host,
            "sensitivity cases must not blast one table onto all four BOs")
    require("load_restored_case" in host, "per-BO restore helper missing")
    require("sensitive_slot" in host, "sensitive slot selection missing")
    a16 = (repo / "host/stage2n_a16_2_physical_latency_v1.cpp").read_text(encoding="utf-8")
    require("kExpectedMemIndex = 0" in a16, "protected A16 Host must remain single-bank")
    require("dlrm_a16_1" in a16, "protected A16 Host identity")


def check_case_layout(repo, cases):
    model_dir = repo / "models/stage2n_a15_6"
    baseline = (model_dir / cases[0]["file"]).read_bytes()
    require(len(baseline) == 1024, "baseline table size")
    for index, case in enumerate(cases[1:], start=1):
        payload = (model_dir / case["file"]).read_bytes()
        slot = case["modified_slot"]
        row = case["modified_row"]
        require(slot == index - 1, "modified_slot for " + case["name"])
        require(row == 37 + slot, "modified_row for " + case["name"])
        start = row * 16
        end = start + 16
        require(payload[:start] == baseline[:start],
                case["name"] + " prefix diverges from baseline")
        require(payload[end:] == baseline[end:],
                case["name"] + " suffix diverges from baseline")
        require(payload[start:end] != baseline[start:end],
                case["name"] + " does not change row " + str(row))
        require(payload != baseline, case["name"] + " identical to baseline")


def check_runner(repo):
    runner = (repo / "scripts/run_stage2n_a17_6_protected_board_v1.sh").read_text(
        encoding="utf-8")
    build = (repo / "scripts/build_stage2n_a17_6_host_v1.sh").read_text(encoding="utf-8")
    parser = (repo / "scripts/parse_stage2n_a17_6_xclbin_map_v1.py").read_text(
        encoding="utf-8")
    for token in (
        EXPECTED_XCLBIN_SHA256,
        EXPECTED_UUID,
        STALE_XO_SHA256,
        LIVE_XO_SHA256,
        "ACTION=\"${1:-prepare}\"",
        "A17_6_BOARD_EXECUTION_AUTHORIZED",
        "A17_6_ALLOW_PROGRAM",
        "A17_6_FORCE_NO_PROGRAM",
        "A17_6_EXPECTED_HOST_ELF_SHA256",
        "execute does not rebuild",
        "HOST_IDENTITY_CHECKED_BEFORE_PROGRAM=YES",
        "HOST_EXIT_CODE=",
        "check_stage2n_a17_6_host_elf_identity_v1.py",
        "SUPERSEDED_NOT_FOR_EXECUTION",
        "FPGA_PROGRAMMING=NOT_RUN",
        "BOARD=NOT_RUN",
        "parse_stage2n_a17_6_xclbin_map_v1.py",
        "HBM[0]",
        "HBM[3]",
    ):
        require(token in runner, "runner token missing: " + token)
    require('ACTION="${1:-prepare}"' in runner or "prepare" in runner,
            "default action must be prepare")
    require("PREPARE_XBUTIL=NOT_INVOKED" in runner, "prepare must not call xbutil")
    require("PREPARE_DEVICE_OPEN=NOT_RUN" in runner, "prepare must not open a device")
    require("PREPARE_HOST_EXECUTION=NOT_RUN" in runner, "prepare must not execute Host")
    require("XBUTIL=NOT_INVOKED" in build, "build script must not invoke xbutil")
    require("xbutil --" not in build and "xbutil version" not in build,
            "build script must not call xbutil")
    require("HOST_EXECUTION=NOT_RUN" in build, "build script must not execute Host")
    require("FPGA_PROGRAMMING=NOT_RUN" in build, "build script must not program")
    require("mapping_check" in parser, "map parser must reuse metadata mapping_check")
    require("not assumed to be 0..3" in parser or "not assumed" in parser,
            "map parser must not assume indices 0..3")
    # Default prepare path must reach a clean exit before execute's program.
    prepare_index = runner.find('if [[ "${ACTION}" == "prepare" ]]')
    execute_index = runner.find('if [[ "${ACTION}" != "execute" ]]')
    program_index = runner.find("xbutil program")
    require(prepare_index != -1 and execute_index != -1 and program_index != -1,
            "runner action/program markers missing")
    require(prepare_index < program_index and execute_index < program_index,
            "xbutil program must not run on the prepare path")
    identity_index = runner.find("HOST_IDENTITY_CHECKED_BEFORE_PROGRAM=YES")
    require(identity_index != -1 and identity_index < program_index,
            "Host ELF identity must be checked before xbutil program")
    require("if [[ ! -x \"${HOST_BINARY}\" ]]; then" not in runner.split(
        'if [[ "${ACTION}" != "execute" ]]', 1)[-1],
            "execute must not auto-rebuild a missing Host ELF")


def check_stale_and_rtl(repo):
    stale = repo / "docs/evidence/stage2n_a17_6/stale_artifacts_v1.txt"
    text = stale.read_text(encoding="utf-8")
    require("SUPERSEDED_NOT_FOR_EXECUTION" in text, "stale artifact label")
    require(STALE_XO_SHA256 in text, "stale xo_001 SHA")
    require(LIVE_XO_SHA256 in text, "live xo_002 SHA")
    require(EXPECTED_XCLBIN_SHA256 in text, "link_004 xclbin SHA")
    rtl = repo / "rtl/pipeline/dlrm_hbm_pipeline_integration_stage2n_a17_v1.sv"
    require(rtl.is_file(), "LUTLP-fixed integration RTL missing")
    kernel = repo / "rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a17_v1.sv"
    require("32'h0002_4E17" in kernel.read_text(encoding="utf-8"),
            "A17 kernel version 0x00024E17")
    a16_host = repo / "host/stage2n_a16_2_physical_latency_v1.cpp"
    require(a16_host.is_file(), "accepted A16.2 Host must remain")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", type=Path, default=Path("."))
    args = parser.parse_args()
    repo = args.repo.resolve()
    cases = lock_goldens(repo)
    check_case_layout(repo, cases)
    check_host(repo, cases)
    check_runner(repo)
    check_stale_and_rtl(repo)
    print("A17_6_HOST_PREP_CHECK=PASS")
    print("A17_6_GOLDEN_LOCK=PASS")
    print("A17_6_PER_BO_CASE_LAYOUT=PASS")
    print("A17_6_BOARD=NOT_RUN")
    print("A17_6_PERFORMANCE=NOT_CLAIMED")
    print("XSIM_RESULT_36_NOT_USED=1")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except CheckError as error:
        print("A17_6_HOST_PREP_CHECK=FAIL", file=sys.stderr)
        print("REASON={}".format(error), file=sys.stderr)
        sys.exit(1)
