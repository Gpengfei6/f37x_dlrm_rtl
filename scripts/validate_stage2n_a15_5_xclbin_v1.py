#!/usr/bin/env python3
"""Validate Stage 2N-A15.5 link inputs and linked-xclbin metadata."""

from __future__ import print_function

import argparse
import json
import re
import tempfile
from pathlib import Path


EXPECTED_KERNEL = "dlrm_f37x_rtl_kernel_stage2n_a15_v1"
EXPECTED_CU = "dlrm_a15_1"
EXPECTED_PLATFORM = "inspur_f37x_xdma_201920_3"
EXPECTED_PART = "xcvu37p-fsvh2892-2L-e"
EXPECTED_CLOCK = 100
STALE_ARGUMENTS = ("LOOKUP_INDEX", "RESULT0", "RESULT1", "RESULT2", "RESULT3")


class ValidationError(Exception):
    pass


def require(condition, message):
    if not condition:
        raise ValidationError(message)


def load_json(path):
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def find_lists(value, key):
    found = []
    if isinstance(value, dict):
        for child_key, child in value.items():
            if child_key == key and isinstance(child, list):
                found.extend(child)
            found.extend(find_lists(child, key))
    elif isinstance(value, list):
        for child in value:
            found.extend(find_lists(child, key))
    return found


def parse_index(entry, key):
    require(key in entry, "CONNECTIVITY record lacks {}".format(key))
    value = entry[key]
    try:
        return value if isinstance(value, int) else int(str(value), 0)
    except ValueError:
        raise ValidationError("CONNECTIVITY {} is not an integer".format(key))


def active_lines(path):
    lines = []
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.split("#", 1)[0].strip()
        if line:
            lines.append(line)
    return lines


def parse_contract(path):
    values = {}
    for line in active_lines(path):
        require("=" in line, "invalid link-contract line: {}".format(line))
        key, value = line.split("=", 1)
        require(key and key not in values, "duplicate or empty link-contract key")
        values[key] = value
    return values


def validate_config(path, kernel, cu):
    lines = active_lines(path)
    expected = [
        "[connectivity]",
        "nk={}:1:{}".format(kernel, cu),
        "sp={}.m_axi_gmem:HBM[0]".format(cu),
    ]
    require(lines == expected, "connectivity config is not the exact one-CU/one-HBM[0] contract")


def validate_link_script(path, config_path, kernel, cu, platform, part, clock):
    text = path.read_text(encoding="utf-8", errors="replace")
    code = "\n".join(line.split("#", 1)[0] for line in text.splitlines())
    required = [
        'KERNEL_NAME="{}"'.format(kernel),
        'CU_NAME="{}"'.format(cu),
        'PLATFORM_VBNV="{}"'.format(platform),
        'PART_NAME="{}"'.format(part),
        'KERNEL_FREQUENCY_MHZ="${KERNEL_FREQUENCY_MHZ:-%d}"' % clock,
        "--target hw",
        "--link",
        '--kernel_frequency "${KERNEL_FREQUENCY_MHZ}"',
        "config/stage2n_a15_5_target_v1.cfg",
    ]
    for fragment in required:
        require(fragment in text, "link runner is missing {}".format(fragment))
    invocations = re.findall(r"(?m)^\s*v\+\+\s", code)
    require(len(invocations) == 1, "link runner must invoke v++ exactly once")
    forbidden = ("xbutil", "xbmgmt", "ssh", "scp", "rsync", "xrt::device", "program(", "reset(")
    lower_code = code.lower()
    for token in forbidden:
        require(token.lower() not in lower_code, "link runner contains forbidden operation {}".format(token))
    require(config_path.name in text, "link runner does not name reviewed config")


def validate_metadata(connectivity_path, topology_path, layout_path, info_path, kernel, cu, platform):
    info = info_path.read_text(encoding="utf-8", errors="replace")
    for value, description in ((kernel, "kernel"), (cu, "compute unit"), (platform, "platform")):
        require(value in info, "xclbin info is missing {} {}".format(description, value))
    for stale in STALE_ARGUMENTS:
        require(stale not in info, "xclbin info contains obsolete A14 signature {}".format(stale))
    uuid_match = re.search(
        r"(?mi)^\s*UUID \(xclbin\):\s*([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\s*$",
        info,
    )
    require(uuid_match is not None, "xclbin UUID missing or malformed")

    connectivity = load_json(connectivity_path)
    topology = load_json(topology_path)
    layout = load_json(layout_path)
    connections = find_lists(connectivity, "m_connection")
    memories = find_lists(topology, "m_mem_data")
    ips = find_lists(layout, "m_ip_data")
    require(len(connections) == 1, "linked metadata must contain exactly one memory connection")
    require(len(ips) == 1, "IP_LAYOUT must contain exactly one compute unit")

    ip_name = str(ips[0].get("m_name", ""))
    require(cu in ip_name and kernel in info, "reviewed CU identity mismatch")
    hbm0 = [entry for entry in memories if str(entry.get("m_tag", "")) == "HBM[0]"]
    require(len(hbm0) == 1, "MEM_TOPOLOGY must contain exactly one HBM[0] entry")
    used = [entry for entry in memories if str(entry.get("m_used", "0")).lower() not in ("0", "false")]
    require(used == hbm0, "only HBM[0] may be marked used")
    connection = connections[0]
    require(parse_index(connection, "m_ip_layout_index") == 0, "connection targets wrong CU")
    require(parse_index(connection, "mem_data_index") == memories.index(hbm0[0]), "connection targets wrong memory")
    return uuid_match.group(1)


def validate_contract(path, kernel, cu, platform, part, clock):
    values = parse_contract(path)
    expected = {
        "KERNEL": kernel,
        "COMPUTE_UNIT": cu,
        "PLATFORM_VBNV": platform,
        "TARGET_PART": part,
        "KERNEL_FREQUENCY_MHZ": str(clock),
        "CONNECTIVITY": "{}.m_axi_gmem:HBM[0]".format(cu),
        "M_AXI_MASTER_COUNT": "1",
    }
    require(values == expected, "link contract mismatch: {}".format(values))


def validate_all(args):
    validate_config(args.config, args.kernel, args.compute_unit)
    validate_link_script(
        args.link_script,
        args.config,
        args.kernel,
        args.compute_unit,
        args.platform,
        args.part,
        args.clock_mhz,
    )
    validate_contract(
        args.link_contract,
        args.kernel,
        args.compute_unit,
        args.platform,
        args.part,
        args.clock_mhz,
    )
    return validate_metadata(
        args.connectivity,
        args.mem_topology,
        args.ip_layout,
        args.xclbin_info,
        args.kernel,
        args.compute_unit,
        args.platform,
    )


def good_config(kernel=EXPECTED_KERNEL, cu=EXPECTED_CU, bank="HBM[0]"):
    return "[connectivity]\nnk={}:1:{}\nsp={}.m_axi_gmem:{}\n".format(kernel, cu, cu, bank)


def good_contract(kernel=EXPECTED_KERNEL, cu=EXPECTED_CU, platform=EXPECTED_PLATFORM, part=EXPECTED_PART, clock=EXPECTED_CLOCK):
    return "\n".join([
        "KERNEL={}".format(kernel),
        "COMPUTE_UNIT={}".format(cu),
        "PLATFORM_VBNV={}".format(platform),
        "TARGET_PART={}".format(part),
        "KERNEL_FREQUENCY_MHZ={}".format(clock),
        "CONNECTIVITY={}.m_axi_gmem:HBM[0]".format(cu),
        "M_AXI_MASTER_COUNT=1",
        "",
    ])


def good_link_script():
    return """#!/usr/bin/env bash
KERNEL_NAME=\"{0}\"
CU_NAME=\"{1}\"
PLATFORM_VBNV=\"{2}\"
PART_NAME=\"{3}\"
KERNEL_FREQUENCY_MHZ=\"${{KERNEL_FREQUENCY_MHZ:-100}}\"
CONFIG=\"config/stage2n_a15_5_target_v1.cfg\"
v++ --target hw --link --platform platform --config \"${{CONFIG}}\" --kernel_frequency \"${{KERNEL_FREQUENCY_MHZ}}\" input.xo
""".format(EXPECTED_KERNEL, EXPECTED_CU, EXPECTED_PLATFORM, EXPECTED_PART)


def good_info(kernel=EXPECTED_KERNEL, cu=EXPECTED_CU, platform=EXPECTED_PLATFORM, clock=EXPECTED_CLOCK):
    return """Kernel: {0}
Compute Unit: {1}
Platform: {2}
Clock Frequency: {3} MHz
UUID (xclbin): 12345678-1234-1234-1234-123456789abc
""".format(kernel, cu, platform, clock)


def make_args(paths):
    class Args(object):
        pass
    args = Args()
    args.connectivity = paths["connectivity"]
    args.mem_topology = paths["mem"]
    args.ip_layout = paths["ip"]
    args.xclbin_info = paths["info"]
    args.config = paths["config"]
    args.link_script = paths["link"]
    args.link_contract = paths["contract"]
    args.kernel = EXPECTED_KERNEL
    args.compute_unit = EXPECTED_CU
    args.platform = EXPECTED_PLATFORM
    args.part = EXPECTED_PART
    args.clock_mhz = EXPECTED_CLOCK
    return args


def run_self_test():
    with tempfile.TemporaryDirectory(prefix="a15_5_xclbin_validator_") as temp_name:
        temp = Path(temp_name)
        paths = {name: temp / name for name in ("connectivity", "mem", "ip", "info", "config", "link", "contract")}
        originals = {
            "connectivity": json.dumps({"connectivity": {"m_connection": [{"m_ip_layout_index": 0, "mem_data_index": 0, "arg_index": 0}]}}),
            "mem": json.dumps({"mem_topology": {"m_mem_data": [{"m_tag": "HBM[0]", "m_used": "1"}, {"m_tag": "HBM[1]", "m_used": "0"}]}}),
            "ip": json.dumps({"ip_layout": {"m_ip_data": [{"m_name": "{}:{}".format(EXPECTED_CU, EXPECTED_CU)}]}}),
            "info": good_info(),
            "config": good_config(),
            "link": good_link_script(),
            "contract": good_contract(),
        }

        def write_all(overrides=None):
            overrides = overrides or {}
            for name, path in paths.items():
                path.write_text(overrides.get(name, originals[name]), encoding="utf-8")

        write_all()
        args = make_args(paths)
        validate_all(args)
        print("XCLBIN_SELF_TEST_GOOD=PASS")
        second_connection = json.dumps({"connectivity": {"m_connection": [
            {"m_ip_layout_index": 0, "mem_data_index": 0},
            {"m_ip_layout_index": 0, "mem_data_index": 1},
        ]}})
        cases = [
            ("wrong_kernel", "info", good_info(kernel="wrong_kernel")),
            ("wrong_cu", "info", good_info(cu="wrong_cu")),
            ("wrong_hbm_bank", "config", good_config(bank="HBM[1]")),
            ("second_hbm_mapping", "connectivity", second_connection),
            ("second_memory_master", "config", good_config() + "sp={}.m_axi_extra:HBM[1]\n".format(EXPECTED_CU)),
            ("stale_lookup_index", "info", good_info() + "LOOKUP_INDEX\n"),
            ("stale_result0", "info", good_info() + "RESULT0\n"),
            ("wrong_clock", "contract", good_contract(clock=200)),
            ("wrong_platform", "contract", good_contract(platform="wrong_platform")),
            ("wrong_part", "contract", good_contract(part="xc7a200tfbg484-2")),
        ]
        for label, target, replacement in cases:
            write_all({target: replacement})
            try:
                validate_all(args)
            except ValidationError:
                print("XCLBIN_SELF_TEST_REJECT_{}=PASS".format(label.upper()))
            else:
                raise ValidationError("negative self-test was accepted: {}".format(label))
    print("A15_5_XCLBIN_VALIDATOR_SELF_TEST=PASS")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--connectivity", type=Path)
    parser.add_argument("--mem-topology", type=Path)
    parser.add_argument("--ip-layout", type=Path)
    parser.add_argument("--xclbin-info", type=Path)
    parser.add_argument("--config", type=Path)
    parser.add_argument("--link-script", type=Path)
    parser.add_argument("--link-contract", type=Path)
    parser.add_argument("--kernel", default=EXPECTED_KERNEL)
    parser.add_argument("--compute-unit", default=EXPECTED_CU)
    parser.add_argument("--platform", default=EXPECTED_PLATFORM)
    parser.add_argument("--part", default=EXPECTED_PART)
    parser.add_argument("--clock-mhz", type=int, default=EXPECTED_CLOCK)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    try:
        if args.self_test:
            run_self_test()
            return
        paths = (
            args.connectivity, args.mem_topology, args.ip_layout, args.xclbin_info,
            args.config, args.link_script, args.link_contract,
        )
        require(all(path is not None for path in paths), "metadata paths are required without --self-test")
        for path in paths:
            require(path.is_file() and path.stat().st_size > 0, "missing or empty input: {}".format(path))
        uuid = validate_all(args)
    except (OSError, ValueError, json.JSONDecodeError, ValidationError) as error:
        raise SystemExit("A15.5 xclbin validation failed: {}".format(error))
    print("A15_5_XCLBIN_METADATA_VALIDATION=PASS")
    print("KERNEL={}".format(args.kernel))
    print("COMPUTE_UNIT={}".format(args.compute_unit))
    print("PLATFORM={}".format(args.platform))
    print("TARGET_PART={}".format(args.part))
    print("KERNEL_FREQUENCY_MHZ={}".format(args.clock_mhz))
    print("CONNECTIVITY={}.m_axi_gmem:HBM[0]".format(args.compute_unit))
    print("M_AXI_MASTER_COUNT=1")
    print("XCLBIN_UUID={}".format(uuid))
    print("PHYSICAL_HBM=NOT_VALIDATED")
    print("FPGA_DEVICE_ACCESS=NONE")


if __name__ == "__main__":
    main()
