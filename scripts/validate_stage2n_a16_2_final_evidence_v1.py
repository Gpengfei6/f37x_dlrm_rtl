#!/usr/bin/env python3
"""Offline acceptance gate for imported Stage 2N-A16.2 compact evidence.

This validator never opens a device and never invokes a target tool.  It
accepts only the frozen target identity and the five-case latency result that
was reported for the protected A16.2 run.
"""

from __future__ import print_function

import argparse
import hashlib
import re
import subprocess
import sys
from pathlib import Path


EXPECTED_XO_SHA256 = (
    "ea0fe950339ada07eaacd181c495dcb1f07251ed20e7d1cef44479bc36cec94a"
)
EXPECTED_XCLBIN_SHA256 = (
    "5f0d6fefab1549d2e1969df3d8775409bbfac33cb46d07e7abde99abdf04b8b4"
)
EXPECTED_XCLBIN_UUID = "f18571de-4a43-46bd-8ab9-a89dd4b11f8e"
EXPECTED_RTL_SHA256 = (
    "a6eec09c4ebfe358751f7dfc31c2e77d509cd55d4fc8953f465a2227c3e7f7a5"
)
EXPECTED_HOST_SOURCE_SHA256 = (
    "d2c4036bcaccba702d70fe772a436501568c593dd5b92bc08edb7d7502dafc99"
)
EXPECTED_RUNNER_SHA256 = (
    "8370ec2f6128243a5f15e7a83a8c0c432b2cde6bf959504769d71323dc31c3ba"
)
EXPECTED_HOST_BINARY_SHA256 = (
    "de0abefc0b4dbadf74dd69e6875db9051a18ab34d8ab1a6a747073cb436d6f1b"
)
EXPECTED_KERNEL = "dlrm_f37x_rtl_kernel_stage2n_a16_v1"
EXPECTED_CU = "dlrm_a16_1"
EXPECTED_PART = "xcvu37p-fsvh2892-2L-e"
EXPECTED_PLATFORM = "inspur_f37x_xdma_201920_3"
EXPECTED_PLATFORM_PATH = (
    "/opt/xilinx/platforms/inspur_f37x_xdma_201920_3/"
    "inspur_f37x_xdma_201920_3.xpfm"
)
EXPECTED_RESULTS = (-393, -392, -93, -689, -519)


class ValidationError(Exception):
    pass


def require(condition, message):
    if not condition:
        raise ValidationError(message)


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def parse_marker_lines(lines):
    """Parse progressive KEY=VALUE logs using the last valid assignment.

    Protected target runners append precheck, Host-validation, and final status
    sections to one log.  A later assignment therefore supersedes an earlier
    provisional value for the same key.
    """
    markers = {}
    for raw in lines:
        if "=" not in raw:
            continue
        key, value = raw.split("=", 1)
        key = key.strip()
        if key and re.match(r"^[A-Za-z0-9_]+$", key):
            markers[key] = value.strip()
    return markers


def parse_markers(path):
    return parse_marker_lines(
        path.read_text(encoding="utf-8", errors="replace").splitlines())


def exact(markers, key, value, context):
    require(markers.get(key) == str(value),
            "{}: {} expected {!r}, got {!r}".format(
                context, key, str(value), markers.get(key)))


def run_marker_parser_self_test():
    provisional_then_pass = parse_marker_lines(
        ("KEY=NOT_VALIDATED\nKEY=PASS\n").splitlines())
    exact(provisional_then_pass, "KEY", "PASS",
          "marker self-test provisional_then_pass")

    pass_then_fail = parse_marker_lines(
        ("KEY=PASS\nKEY=FAIL\n").splitlines())
    exact(pass_then_fail, "KEY", "FAIL", "marker self-test pass_then_fail")
    try:
        exact(pass_then_fail, "KEY", "PASS",
              "marker self-test pass_then_fail acceptance")
    except ValidationError:
        pass
    else:
        raise ValidationError(
            "marker self-test accepted an earlier PASS followed by FAIL")

    single_pass = parse_marker_lines(("KEY=PASS\n").splitlines())
    exact(single_pass, "KEY", "PASS", "marker self-test single_pass")

    missing = parse_marker_lines(("OTHER=PASS\n").splitlines())
    try:
        exact(missing, "KEY", "PASS", "marker self-test missing_marker")
    except ValidationError:
        pass
    else:
        raise ValidationError("marker self-test missing_marker was not rejected")


def required_file(root, relative):
    path = root / relative
    require(path.is_file(), "missing evidence file {}".format(relative))
    require(path.stat().st_size > 0, "empty evidence file {}".format(relative))
    return path


def validate_manifest(root):
    manifest = root / "IMPORTED_EVIDENCE_SHA256.txt"
    if not manifest.is_file():
        return 0
    count = 0
    for raw in manifest.read_text(encoding="utf-8").splitlines():
        if not raw.strip():
            continue
        match = re.match(r"^([0-9a-f]{64})  (.+)$", raw)
        require(match is not None, "malformed imported-evidence SHA line")
        # Path accepts forward slashes on both Windows and Linux; use the
        # original text to retain a stable manifest format.
        path = root / Path(match.group(2))
        require(path.is_file(), "manifest target missing: {}".format(match.group(2)))
        require(sha256(path) == match.group(1),
                "manifest SHA mismatch: {}".format(match.group(2)))
        count += 1
    require(count > 0, "imported-evidence SHA manifest is empty")
    return count


def find_physical_run(root):
    physical = root / "physical_latency_v1"
    require(physical.is_dir(), "physical_latency_v1 directory missing")
    runs = sorted(path for path in physical.iterdir() if path.is_dir())
    require(len(runs) == 1,
            "expected exactly one imported physical run, found {}".format(len(runs)))
    return runs[0]


def validate(root, repo):
    xo_root = root / "target_xo_v1"
    link_root = root / "target_link_v1"
    run_root = find_physical_run(root)

    xo_status_path = required_file(xo_root, "a16_2_target_xo_v1_status.txt")
    link_status_path = required_file(link_root, "a16_2_target_link_v1_status.txt")
    metrics_path = required_file(link_root, "post_route/post_route_metrics.txt")
    host_log = required_file(run_root, "host.log")
    runner_log = required_file(run_root, "runner.log")
    required_file(run_root, "latency_validation.log")
    required_file(run_root, "pre_device_query.txt")
    required_file(run_root, "post_host_query.txt")

    xo = parse_markers(xo_status_path)
    for key in ("A16_2_TARGET_XO_BUILD", "A16_2_TARGET_XO_VALIDATION"):
        exact(xo, key, "PASS", "XO status")
    exact(xo, "XO_SHA256", EXPECTED_XO_SHA256, "XO status")
    exact(xo, "KERNEL", EXPECTED_KERNEL, "XO status")
    exact(xo, "TARGET_PART", EXPECTED_PART, "XO status")
    exact(xo, "PLATFORM", EXPECTED_PLATFORM_PATH, "XO status")
    exact(xo, "M_AXI_MASTER_COUNT", 1, "XO status")
    exact(xo, "M_AXI_DATA_WIDTH", 128, "XO status")
    exact(xo, "M_AXI_ADDR_WIDTH", 64, "XO status")
    exact(xo, "TABLE_BASE_OFFSET", "0x304", "XO status")
    exact(xo, "KERNEL_ARGUMENT_COUNT", 1, "XO status")

    link = parse_markers(link_status_path)
    for key in ("A16_2_INPUT_XO", "A16_2_TARGET_LINK", "A16_2_XCLBIN",
                "A16_2_HBM0_LINK_MAPPING", "A16_2_TARGET_TIMING"):
        exact(link, key, "PASS", "link status")
    exact(link, "XO_SHA256", EXPECTED_XO_SHA256, "link status")
    exact(link, "XCLBIN_SHA256", EXPECTED_XCLBIN_SHA256, "link status")
    exact(link, "XCLBIN_UUID", EXPECTED_XCLBIN_UUID, "link status")
    exact(link, "TARGET_PART", EXPECTED_PART, "link status")
    exact(link, "PLATFORM", EXPECTED_PLATFORM_PATH, "link status")
    exact(link, "PLATFORM_VBNV", EXPECTED_PLATFORM, "link status")
    exact(link, "KERNEL", EXPECTED_KERNEL, "link status")
    exact(link, "COMPUTE_UNIT", EXPECTED_CU, "link status")
    exact(link, "REQUESTED_HBM_MAPPING",
          EXPECTED_CU + ".m_axi_gmem:HBM[0]", "link status")
    exact(link, "REQUESTED_CLOCK_MHZ", 100, "link status")

    metrics = parse_markers(metrics_path)
    expected_metrics = {
        "A16_2_VITIS_POST_ROUTE_REPORT": "COMPLETE",
        "TARGET_PART": EXPECTED_PART,
        "REQUESTED_CLOCK_NS": "10.000",
        "REQUESTED_CLOCK_MHZ": "100",
        "WNS_NS": "0.000",
        "TNS_NS": "0.000",
        "FAILING_ENDPOINTS": "0",
        "LUT": "135153",
        "FF": "161849",
        "RAMB36": "215",
        "RAMB18": "89",
        "URAM": "0",
        "DSP": "43",
        "LATCH": "0",
        "DRC_ERROR_COUNT": "0",
        "DRC_CRITICAL_WARNING_COUNT": "0",
        "METHODOLOGY_ERROR_COUNT": "0",
        "METHODOLOGY_CRITICAL_WARNING_COUNT": "55",
    }
    for key, value in expected_metrics.items():
        exact(metrics, key, value, "post-route metrics")

    board_validator = repo / "scripts/validate_stage2n_a16_2_board_log_v1.py"
    require(board_validator.is_file(), "existing board-log validator missing")
    process = subprocess.run(
        [sys.executable, str(board_validator), "--log", str(host_log)],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        universal_newlines=True, check=False)
    require(process.returncode == 0,
            "board-log validator failed:\n{}".format(process.stdout))
    require("A16_2_BOARD_LOG_VALIDATION=PASS" in process.stdout,
            "board-log PASS marker missing")

    host = parse_markers(host_log)
    for index, result in enumerate(EXPECTED_RESULTS):
        prefix = "CASE{}_".format(index)
        exact(host, prefix + "EXPECTED_RESULT", result, "host case")
        exact(host, prefix + "ACTUAL_RESULT", result, "host case")
        exact(host, prefix + "EMBEDDING_LOADED_MASK", "0xF", "host case")
        exact(host, prefix + "BOTTOM_CYCLES", 322, "host case")
        exact(host, prefix + "INTERACTION_CYCLES", 100, "host case")
        exact(host, prefix + "TOP_CYCLES", 744, "host case")
        exact(host, prefix + "COMPUTE_TOTAL_CYCLES", 1174, "host case")
        exact(host, prefix + "HBM_LOOKUP_CYCLES", 112, "host case")
        exact(host, prefix + "FPGA_END_TO_END_CYCLES", 1289, "host case")
        exact(host, prefix + "PIPELINE_OVERHEAD_CYCLES", 3, "host case")
        exact(host, prefix + "LATENCY_ACCOUNTING", "PASS", "host case")

    exact(host, "TARGET_INDEX", 2, "host")
    exact(host, "TARGET_BDF", "0000:9b:00.1", "host")
    exact(host, "XCLBIN_UUID", EXPECTED_XCLBIN_UUID, "host")
    exact(host, "IP_NAME", EXPECTED_KERNEL + ":" + EXPECTED_CU, "host")
    exact(host, "HBM_BANK", "HBM[0]", "host")
    exact(host, "HBM_MEMORY_INDEX", 0, "host")
    exact(host, "BO_SIZE_BYTES", 4096, "host")
    exact(host, "BO_PADDR_HEX", "0x0000000000000000", "host")
    exact(host, "MODEL_DESCRIPTOR_COUNT", 5, "host")
    exact(host, "MODEL_WEIGHT_COUNT", 1360, "host")
    exact(host, "MODEL_BIAS_COUNT", 73, "host")
    for key in ("A16_2_BO_CLEANUP", "A16_2_ALL_FIVE_CASES",
                "A16_2_PHYSICAL_HBM_FUNCTIONAL_HOST",
                "A16_2_PHYSICAL_HBM_LATENCY_COUNTERS"):
        exact(host, key, "PASS", "host")
    exact(host, "A16_2_PERFORMANCE", "NOT_CLAIMED", "host")
    exact(host, "STAGE2N_A16_2_PHYSICAL_LATENCY_V1", "PASS", "host")

    runner = parse_markers(runner_log)
    exact(runner, "XCLBIN_SHA256", EXPECTED_XCLBIN_SHA256, "runner")
    exact(runner, "XCLBIN_UUID", EXPECTED_XCLBIN_UUID, "runner")
    exact(runner, "TARGET_INDEX", 2, "runner")
    exact(runner, "TARGET_BDF", "0000:9b:00.1", "runner")
    exact(runner, "KERNEL", EXPECTED_KERNEL, "runner")
    exact(runner, "CU", EXPECTED_CU, "runner")
    exact(runner, "HBM_BANK", "HBM[0]", "runner")
    for key in ("A16_2_FIXED_XCLBIN_IDENTITY", "A16_2_DEVICE_IDENTITY",
                "A16_2_HBM0_BO_ALLOCATION", "A16_2_PAYLOAD_TRANSFER",
                "A16_2_TABLE_BASE_PROGRAMMING", "A16_2_COMPLETE_DLRM_RESULT",
                "A16_2_BO_CLEANUP", "A16_2_PHYSICAL_HBM",
                "A16_2_PHYSICAL_HBM_LATENCY", "A16_2_BOARD_FUNCTIONAL"):
        exact(runner, key, "PASS", "runner")
    exact(runner, "A16_2_FPGA_PROGRAMMING", "PASS", "runner")
    exact(runner, "A16_2_PERFORMANCE", "NOT_CLAIMED", "runner")
    exact(runner, "FPGA_RESET", "NOT_RUN", "runner")
    exact(runner, "OTHER_DEVICE_ACCESS", "NONE", "runner")

    local_rtl = repo / "rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a16_v1.sv"
    local_host = repo / "host/stage2n_a16_2_physical_latency_v1.cpp"
    local_runner = repo / "scripts/program_and_run_stage2n_a16_2_physical_latency_v1.sh"
    require(sha256(local_rtl) == EXPECTED_RTL_SHA256, "frozen A16.1 RTL SHA")
    require(sha256(local_host) == EXPECTED_HOST_SOURCE_SHA256, "Host source SHA")
    require(sha256(local_runner) == EXPECTED_RUNNER_SHA256, "protected runner SHA")

    host_build = root / "host_build_status.txt"
    require(host_build.is_file(), "host_build_status.txt missing")
    build = parse_markers(host_build)
    exact(build, "A16_2_HOST_XRT_BUILD", "PASS", "Host build")
    exact(build, "A16_2_XRT2020_2_API_PROBE", "PASS", "Host build")
    exact(build, "EXPECTED_XRT_VERSION", "2.9.210507", "Host build")
    exact(build, "SOURCE_SHA256", EXPECTED_HOST_SOURCE_SHA256, "Host build")
    exact(build, "BINARY_SHA256", EXPECTED_HOST_BINARY_SHA256, "Host build")

    return validate_manifest(root)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence-root", type=Path)
    parser.add_argument("--repo", default=Path(__file__).resolve().parents[1], type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()

    if args.self_test:
        try:
            run_marker_parser_self_test()
        except ValidationError as error:
            raise SystemExit(
                "A16.2 marker parser self-test failed: {}".format(error))
        print("A16_2_MARKER_PARSER_SELF_TEST=PASS")
        print("A16_2_MARKER_PARSER_SELF_TEST_CASES=4")
        print("A16_2_MARKER_SEMANTICS=LAST_VALID_OCCURRENCE")
        return

    repo = args.repo.resolve()
    try:
        require(args.evidence_root is not None,
                "--evidence-root is required unless --self-test is used")
        root = args.evidence_root.resolve()
        require(root.is_dir(), "evidence root is missing")
        manifest_count = validate(root, repo)
    except (OSError, ValueError, ValidationError) as error:
        raise SystemExit("A16.2 final evidence validation failed: {}".format(error))
    print("A16_2_FINAL_EVIDENCE_VALIDATION=PASS")
    print("A16_2_TARGET_XO_BUILD=PASS")
    print("A16_2_TARGET_LINK=PASS")
    print("A16_2_TARGET_TIMING=PASS")
    print("A16_2_PHYSICAL_HBM_LATENCY=PASS")
    print("A16_2_LATENCY_ACCOUNTING_RECONCILIATION=EXPLAINED")
    print("A16_2_PERFORMANCE=NOT_CLAIMED")
    print("A16_2_IMPORTED_MANIFEST_ENTRY_COUNT={}".format(manifest_count))


if __name__ == "__main__":
    main()
