#!/usr/bin/env python3
"""Static, device-free acceptance validator for A16.2 preparation sources."""

from __future__ import print_function

import argparse
import hashlib
import re
from pathlib import Path


EXPECTED_A16_RTL_SHA256 = "a6eec09c4ebfe358751f7dfc31c2e77d509cd55d4fc8953f465a2227c3e7f7a5"
EXPECTED_A15_RTL_SHA256 = "c3da5be63d4cf195df124e572887b6aa96a464522883c6cdc95c4bd56ff4e8a1"
EXPECTED_KERNEL = "dlrm_f37x_rtl_kernel_stage2n_a16_v1"
EXPECTED_CU = "dlrm_a16_1"
EXPECTED_SOURCES = [
    "rtl/common/rv_fifo.sv",
    "rtl/common/runtime_relu_quant.sv",
    "rtl/compute/mac_lane.sv",
    "rtl/memory/banked_activation_buffer.sv",
    "rtl/memory/local_weight_provider.sv",
    "rtl/compute/vector_dot_product_core.sv",
    "rtl/compute/dense_layer_engine.sv",
    "rtl/control/mlp_sequence_controller.sv",
    "rtl/top/dlrm_f37x_rtl_kernel.sv",
    "rtl/interaction/dlrm_feature_interaction_engine.sv",
    "rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a2.sv",
    "rtl/control/mlp_sequence_controller_segmented.sv",
    "rtl/pipeline/dlrm_internal_pipeline_controller.sv",
    "rtl/pipeline/dlrm_internal_pipeline_controller_stage2n_a13_v1.sv",
    "rtl/hbm/dlrm_hbm_embedding_lookup_stage2n_a14_v2.sv",
    "rtl/pipeline/dlrm_hbm_pipeline_integration_stage2n_a15_v2.sv",
    "rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a16_v1.sv",
]


class ValidationError(Exception):
    pass


def require(condition, message):
    if not condition:
        raise ValidationError(message)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def text(path):
    return path.read_text(encoding="utf-8", errors="replace")


def active_config_lines(value):
    lines = []
    for raw in value.splitlines():
        line = raw.split("#", 1)[0].strip()
        if line:
            lines.append(line)
    return lines


def validate_contract(package, config, build, link, host, host_build, runner):
    expected_config = [
        "[connectivity]",
        "nk={}:1:{}".format(EXPECTED_KERNEL, EXPECTED_CU),
        "sp={}.m_axi_gmem:HBM[0]".format(EXPECTED_CU),
    ]
    require(active_config_lines(config) == expected_config, "one-CU/HBM[0] config")
    sources = re.findall(r"\[source_path\s+\$root_dir\s+([^\]\s]+)\]", package)
    require(sources == EXPECTED_SOURCES, "package source closure")
    for token in (
        'set top_name "{}"'.format(EXPECTED_KERNEL),
        'set target_part_name "xcvu37p-fsvh2892-2L-e"',
        "$address_block TABLE_BASE 0x304 64 read-write",
        "DATA_WIDTH 128", "ADDR_WIDTH 64", "user_managed",
    ):
        require(token in package, "package token {}".format(token))
    for stale in ("LOOKUP_INDEX", "RESULT0", "RESULT1", "RESULT2", "RESULT3"):
        require("$address_block {} ".format(stale) not in package,
                "stale package argument {}".format(stale))

    for body, label in ((build, "XO build"), (link, "link"), (runner, "board runner")):
        for forbidden in ("git -C", "git branch --show-current", "git symbolic-ref --short"):
            require(forbidden not in body, "{} old-Git incompatibility {}".format(label, forbidden))
        code = "\n".join(line.split("#", 1)[0] for line in body.splitlines())
        for command in ("ssh", "scp", "sftp", "rsync", "curl", "wget"):
            require(re.search(r"(?m)^\s*{}\b".format(command), code) is None,
                    "{} network command {}".format(label, command))
    for body, label in ((build, "XO build"), (link, "link")):
        require("xbutil" not in body and "xbmgmt" not in body and "/dev/dri" not in body,
                "{} contains device access".format(label))

    for token in (
        'CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD',
        'CURRENT_HEAD="$(git rev-parse HEAD',
        EXPECTED_A16_RTL_SHA256,
        EXPECTED_KERNEL,
    ):
        require(token in build, "XO runner token {}".format(token))
    for token in (
        EXPECTED_KERNEL, EXPECTED_CU, "inspur_f37x_xdma_201920_3",
        "xcvu37p-fsvh2892-2L-e", "KERNEL_FREQUENCY_MHZ=\"${KERNEL_FREQUENCY_MHZ:-100}\"",
        "config/stage2n_a16_2_target_v1.cfg", "--target hw", "--link",
        "IP_LAYOUT:JSON", "MEM_TOPOLOGY:JSON", "CONNECTIVITY:JSON",
        "DRC_ERROR_COUNT", "METHODOLOGY_ERROR_COUNT", "LATCH",
    ):
        require(token in link, "link runner token {}".format(token))

    for token in (
        'A_BOTTOM_CYCLES = 0x218', 'A_INTERACTION_CYCLES = 0x21C',
        'A_TOP_CYCLES = 0x220', 'A_TOTAL_CYCLES = 0x224',
        'A_A15_CONTROL = 0x300', 'A_TABLE_BASE_LO = 0x304',
        'A_TABLE_BASE_HI = 0x308', 'A_HBM_LOOKUP_CYCLES = 0x30C',
        'A_FPGA_END_TO_END_CYCLES = 0x310',
        'PIPELINE_OVERHEAD_CYCLES=', 'pipeline_overhead_cycles < 0',
        "xclAllocBO", "xclGetBOProperties", "xclSyncBO", "xclFreeBO",
        EXPECTED_KERNEL + ":" + EXPECTED_CU,
    ):
        require(token in host, "Host token {}".format(token))
    require("-std=gnu++11" in host_build, "C++11 Host build")

    for token in (
        'TARGET_BDF="${A16_2_TARGET_BDF:-}"',
        'TARGET_INDEX="${A16_2_TARGET_INDEX:-}"',
        'TARGET_RENDER="${A16_2_TARGET_RENDER:-}"',
        'XCLBIN="${A16_2_XCLBIN:-}"',
        'EXPECTED_XCLBIN_SHA256="${A16_2_EXPECTED_XCLBIN_SHA256:-}"',
        'EXPECTED_UUID="${A16_2_EXPECTED_UUID:-}"',
        "firewall is not GOOD", "require_empty_hbm0", "require_empty_render",
        "read -r -p", '!= "yes"', "xbutil program", "A16_2_ALLOWED_SOURCE_UUID",
        "A16_2_ALLOWED_SOURCE_CU", "validate_stage2n_a16_2_board_log_v1.py",
    ):
        require(token in runner, "protected runner token {}".format(token))
    confirmation = runner.find('!= "yes"')
    programming = runner.find("xbutil program")
    require(confirmation >= 0 and programming > confirmation,
            "authorization must precede programming")
    require("xbutil reset" not in runner and "xbmgmt reset" not in runner,
            "runner contains FPGA reset")
    require("git clean" not in runner and "git reset --hard" not in runner,
            "runner contains destructive Git")


def validate_repo(repo):
    a16 = repo / "rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a16_v1.sv"
    a15 = repo / "rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a15_v1.sv"
    require(digest(a16) == EXPECTED_A16_RTL_SHA256, "frozen A16.1 RTL SHA")
    require(digest(a15) == EXPECTED_A15_RTL_SHA256, "frozen A15.4 RTL SHA")
    paths = {
        "package": repo / "scripts/package_stage2n_a16_2_rtl_kernel_v1.tcl",
        "config": repo / "config/stage2n_a16_2_target_v1.cfg",
        "build": repo / "scripts/build_stage2n_a16_2_target_xo_v1.sh",
        "link": repo / "scripts/link_stage2n_a16_2_target_xclbin_v1.sh",
        "host": repo / "host/stage2n_a16_2_physical_latency_v1.cpp",
        "host_build": repo / "scripts/build_stage2n_a16_2_host_v1.sh",
        "runner": repo / "scripts/program_and_run_stage2n_a16_2_physical_latency_v1.sh",
    }
    for path in paths.values():
        require(path.is_file() and path.stat().st_size > 0, "missing {}".format(path))
    values = {name: text(path) for name, path in paths.items()}
    validate_contract(values["package"], values["config"], values["build"],
                      values["link"], values["host"], values["host_build"],
                      values["runner"])
    return paths


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", type=Path, default=Path("."))
    args = parser.parse_args()
    try:
        paths = validate_repo(args.repo.resolve())
    except (OSError, ValueError, ValidationError) as error:
        raise SystemExit("A16.2 source validation failed: {}".format(error))
    print("A16_2_SOURCE_VALIDATION=PASS")
    print("A16_2_ABI_VALIDATION=PASS")
    print("A16_2_PROTECTION_GATE=PASS")
    print("A16_2_RTL_SOURCE_COUNT={}".format(len(EXPECTED_SOURCES)))
    print("A16_2_A16_RTL_SHA256={}".format(EXPECTED_A16_RTL_SHA256))
    for name in ("host", "runner"):
        print("A16_2_{}_SHA256={}".format(name.upper(), digest(paths[name])))
    print("A16_2_TARGET_XO_BUILD=NOT_RUN_TARGET_REQUIRED")
    print("A16_2_TARGET_XCLBIN_LINK=NOT_RUN_TARGET_REQUIRED")
    print("A16_2_TARGET_TIMING=NOT_RUN_TARGET_REQUIRED")
    print("A16_2_PHYSICAL_HBM_LATENCY=NOT_VALIDATED")
    print("A16_2_PERFORMANCE=NOT_CLAIMED")
    print("SERVER_ACCESS=NONE")
    print("NETWORK_ACCESS=NONE")
    print("FPGA_DEVICE_ACCESS=NONE")


if __name__ == "__main__":
    main()
