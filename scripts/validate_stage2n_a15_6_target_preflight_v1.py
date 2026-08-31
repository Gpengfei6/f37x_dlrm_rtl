#!/usr/bin/env python3
"""Static, device-free validation for the A15.6 target-preflight sources."""

from __future__ import print_function

import argparse
import hashlib
import json
import re
from pathlib import Path


EXPECTED_BRANCH = "work/stage2n-a15-hbm-pipeline-integration"
EXPECTED_BASELINE = "ee3dcaa7f3d90458f3b770318001f3b16d04eccf"
EXPECTED_RTL_SHA256 = "c3da5be63d4cf195df124e572887b6aa96a464522883c6cdc95c4bd56ff4e8a1"
EXPECTED_XCLBIN_SHA256 = "23ee48c91b3dfb5b68b3372ac49fc6607f203cf01d3b9fcfe04b4ea42be02356"
EXPECTED_UUID = "1b555645-a9e2-4f5e-95af-6ce4adacbc3c"
EXPECTED_KERNEL = "dlrm_f37x_rtl_kernel_stage2n_a15_v1"
EXPECTED_CU = "dlrm_a15_1"
EXPECTED_REPO = "/home/chaosuan/gpf/gpf_f37x_dlrm/f37x_dlrm_rtl_stage2n_a15_5_buildonly"


class ValidationError(RuntimeError):
    pass


def require(condition, message):
    if not condition:
        raise ValidationError(message)


def read(path):
    return path.read_text(encoding="utf-8", errors="strict")


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def command_lines(shell_text):
    result = []
    for raw in shell_text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        result.append(line)
    return result


def validate_no_device_actions(preflight_text):
    lines = command_lines(preflight_text)
    forbidden_patterns = (
        r"^xbutil\s+(scan|query|program|reset)\b",
        r"^xbmgmt\b",
        r"^v\+\+\b",
        r"^vivado\b",
        r"^(ssh|scp|sftp|rsync|curl|wget)\b",
    )
    for line in lines:
        for pattern in forbidden_patterns:
            require(re.search(pattern, line) is None,
                    "preflight contains forbidden executable command: " + line)
    for token in ("/dev/dri", "xbutil scan", "xbutil query", "xbutil program",
                  "xbutil reset", "xbmgmt", "xclOpen(", "xclAllocBO(",
                  "git clean", "git reset --hard"):
        require(token not in preflight_text, "preflight contains forbidden token: " + token)


def validate_repo(repo):
    preflight = repo / "scripts/run_stage2n_a15_6_target_preflight_v1.sh"
    validator = repo / "scripts/validate_stage2n_a15_6_target_preflight_v1.py"
    host = repo / "host/stage2n_a15_6_all_hbm_board_validation_v1.cpp"
    host_builder = repo / "scripts/build_stage2n_a15_6_host_v1.sh"
    protected_runner = repo / "scripts/program_and_run_stage2n_a15_6_all_hbm_board_validation_v1.sh"
    rtl = repo / "rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a15_v1.sv"
    manifest_path = repo / "models/stage2n_a15_6/stage2n_a15_6_cases_v1.json"
    template = repo / "docs/evidence/stage2n_a15_6/A15_6_TARGET_PREFLIGHT_STATUS_TEMPLATE_V1.txt"
    for path in (preflight, validator, host, host_builder, protected_runner,
                 rtl, manifest_path, template):
        require(path.is_file() and path.stat().st_size > 0,
                "missing or empty preflight input: {}".format(path))

    preflight_text = read(preflight)
    host_text = read(host)
    host_builder_text = read(host_builder)
    runner_text = read(protected_runner)
    template_text = read(template)
    validate_no_device_actions(preflight_text)

    require("git -C" not in preflight_text,
            "preflight must use repository-local Git commands for old Git")
    require("symbolic-ref --short" not in preflight_text,
            "preflight uses unsupported old-Git branch detection")
    require("git rev-parse --abbrev-ref HEAD" in preflight_text,
            "preflight old-Git-compatible branch detection missing")
    require("git -C" not in runner_text,
            "protected runner must use repository-local Git commands")
    require("symbolic-ref --short" not in runner_text,
            "protected runner uses unsupported old-Git branch detection")
    require("git rev-parse --abbrev-ref HEAD" in runner_text,
            "protected runner old-Git-compatible branch detection missing")

    for token in (
        EXPECTED_REPO, EXPECTED_BRANCH, EXPECTED_BASELINE, EXPECTED_RTL_SHA256,
        EXPECTED_XCLBIN_SHA256, EXPECTED_UUID, EXPECTED_KERNEL, EXPECTED_CU,
        "inspur_f37x_xdma_201920_3", "xcvu37p-fsvh2892-2L-e",
        "m_axi_gmem:HBM[0]", "status --porcelain", "diff --quiet",
        "diff --cached --quiet", "merge-base --is-ancestor",
        "validate_stage2n_a15_5_xclbin_v2.py", "xclbinutil --quiet --force --info",
        "CONNECTIVITY:JSON", "MEM_TOPOLOGY:JSON", "IP_LAYOUT:JSON",
        "build_stage2n_a15_6_host_v1.sh", "cmp -s",
        "A15_6_TARGET_PREFLIGHT=PASS", "FPGA_PROGRAMMING=NOT_RUN",
        "HOST_EXECUTION=NOT_RUN", "PHYSICAL_HBM=NOT_VALIDATED",
        "BOARD_FUNCTIONAL=NOT_RUN", "PERFORMANCE=NOT_CLAIMED",
        "FPGA_DEVICE_ACCESS=NONE", "XCLBIN_REBUILT=NO",
    ):
        require(token in preflight_text, "preflight token missing: " + token)

    require(sha256(rtl) == EXPECTED_RTL_SHA256, "frozen A15.4 RTL SHA256")
    for token in (
        "A_A15_CONTROL = 0x300", "A_TABLE_BASE_LO = 0x304",
        "A_TABLE_BASE_HI = 0x308", "A_BOTTOM_CYCLES = 0x218",
        "A_INTERACTION_CYCLES = 0x21C", "A_TOP_CYCLES = 0x220",
        "A_TOTAL_CYCLES = 0x224", "A15_CMD_START = 0x0001",
        "A15_CMD_CLEAR = 0x0002", "A15_DONE = 1u << 4",
        "A15_ERROR = 1u << 5", "A15_START_READY = 1u << 6",
    ):
        require(token in host_text, "Host ABI token missing: " + token)

    for token in (
        "xclOpen", "xclClose", "xclOpenContext", "xclCloseContext",
        "xclIPName2Index", "xclRegRead", "xclRegWrite", "xclAllocBO",
        "xclFreeBO", "xclMapBO", "xclUnmapBO", "xclSyncBO",
        "xclGetBOProperties",
    ):
        require(token in host_text, "Host XRT API missing: " + token)
        require(token in host_builder_text, "Host symbol probe missing: " + token)
    for token in ("-std=gnu++11", "-lxrt_core", "-pthread", "-ldl",
                  "/opt/xilinx/xrt/setup.sh", "2.9.210507"):
        require(token in host_builder_text, "Host build convention missing: " + token)

    for token in (
        "A15_6_TARGET_INDEX", "TARGET_BDF", EXPECTED_XCLBIN_SHA256,
        EXPECTED_UUID, EXPECTED_KERNEL, EXPECTED_CU, "HBM[0]",
        "ACTION_PROGRAM_FPGA_IF_NEEDED=YES", "FPGA_RESET=NOT_RUN",
        "read -r -p", '!= "yes"',
    ):
        require(token in runner_text, "protected runner token missing: " + token)
    require(runner_text.index('!= "yes"') < runner_text.index("xbutil program"),
            "protected runner authorization must precede programming")
    require("A15_6_TARGET_INDEX:-2" not in runner_text,
            "protected runner silently defaults to historical index 2")

    manifest = json.loads(read(manifest_path))
    require(manifest.get("format") == "STAGE2N_A15_6_CASES_V1", "manifest format")
    cases = manifest.get("cases", [])
    require(len(cases) == 5, "manifest case count")
    require([case.get("expected_final_result") for case in cases] ==
            [-393, -392, -93, -689, -519], "manifest golden results")
    require(manifest.get("hbm_table", {}).get("fixed_lookup_rows") == [37, 38, 39, 40],
            "manifest lookup rows")

    for token in (
        "A15_6_TARGET_PREFLIGHT=NOT_RUN", "A15_6_HOST_BUILD=NOT_RUN",
        "A15_6_FIXED_XCLBIN_IDENTITY=NOT_RUN", "A15_6_GOLDEN_ASSETS=NOT_RUN",
        "A15_6_PROTECTION_GATE=NOT_RUN", "FPGA_PROGRAMMING=NOT_RUN",
        "HOST_EXECUTION=NOT_RUN", "PHYSICAL_HBM=NOT_VALIDATED",
        "BOARD_FUNCTIONAL=NOT_RUN", "FPGA_DEVICE_ACCESS=NONE",
        "PERFORMANCE=NOT_CLAIMED",
    ):
        require(token in template_text, "preflight template token missing: " + token)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", type=Path, default=Path("."))
    args = parser.parse_args()
    validate_repo(args.repo.resolve())
    print("A15_6_TARGET_PREFLIGHT_SOURCE_VALIDATION=PASS")
    print("A15_6_TARGET_PREFLIGHT_NO_DEVICE_ACTIONS=PASS")
    print("A15_6_TARGET_PREFLIGHT_GIT_GATES=PASS")
    print("A15_6_TARGET_PREFLIGHT_XCLBIN_GATES=PASS")
    print("A15_6_TARGET_PREFLIGHT_HOST_API_COMPATIBILITY=PASS")
    print("A15_6_TARGET_PREFLIGHT_ABI_FREEZE=PASS")
    print("A15_6_TARGET_PREFLIGHT_GOLDEN_CONTRACT=PASS")
    print("A15_6_TARGET_PREFLIGHT_PROTECTION_GATE=PASS")
    print("FPGA_DEVICE_ACCESS=NONE")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, json.JSONDecodeError, ValidationError) as exc:
        raise SystemExit("A15.6 target preflight source validation failed: {}".format(exc))
