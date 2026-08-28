#!/usr/bin/env python3
"""Validate A15.5 Vitis 2020.2 xclbin metadata without counting shell IPs as CUs."""

from __future__ import print_function

import argparse
import json
import re
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path


EXPECTED_KERNEL = "dlrm_f37x_rtl_kernel_stage2n_a15_v1"
EXPECTED_CU = "dlrm_a15_1"
EXPECTED_KERNEL_INSTANCE = EXPECTED_KERNEL + ":" + EXPECTED_CU
EXPECTED_PLATFORM = "inspur_f37x_xdma_201920_3"
EXPECTED_PART = "xcvu37p-fsvh2892-2L-e"
EXPECTED_CLOCK = 100
STALE_ARGUMENTS = ("LOOKUP_INDEX", "RESULT0", "RESULT1", "RESULT2", "RESULT3")


class ValidationError(Exception):
    pass


def require(condition, message):
    if not condition:
        raise ValidationError(message)


def local_name(tag):
    return tag.rsplit("}", 1)[-1]


def load_json(path):
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def find_sections(value, list_key):
    sections = []
    if isinstance(value, dict):
        if isinstance(value.get(list_key), list):
            sections.append(value)
        for child in value.values():
            sections.extend(find_sections(child, list_key))
    elif isinstance(value, list):
        for child in value:
            sections.extend(find_sections(child, list_key))
    return sections


def get_section(value, list_key, description):
    sections = find_sections(value, list_key)
    require(len(sections) == 1, "expected one {} section, found {}".format(description, len(sections)))
    section = sections[0]
    entries = section[list_key]
    require("m_count" in section, "{} lacks m_count".format(description))
    try:
        declared_count = int(str(section["m_count"]), 0)
    except ValueError:
        raise ValidationError("{} m_count is not an integer".format(description))
    require(declared_count == len(entries), "{} m_count/list length mismatch".format(description))
    return entries


def parse_integer(entry, key, description):
    require(key in entry, "{} lacks {}".format(description, key))
    try:
        value = entry[key]
        return value if isinstance(value, int) else int(str(value), 0)
    except ValueError:
        raise ValidationError("{} {} is not an integer".format(description, key))


def active_lines(path):
    result = []
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.split("#", 1)[0].strip()
        if line:
            result.append(line)
    return result


def parse_contract(path):
    values = {}
    for line in active_lines(path):
        require("=" in line, "invalid link-contract line: {}".format(line))
        key, value = line.split("=", 1)
        require(key and key not in values, "duplicate or empty link-contract key")
        values[key] = value
    return values


def validate_config(path, kernel, cu):
    expected = [
        "[connectivity]",
        "nk={}:1:{}".format(kernel, cu),
        "sp={}.m_axi_gmem:HBM[0]".format(cu),
    ]
    require(active_lines(path) == expected, "configuration is not the exact one-CU/one-HBM[0] contract")


def validate_contract(path, kernel, cu, platform, part, clock):
    expected = {
        "KERNEL": kernel,
        "COMPUTE_UNIT": cu,
        "PLATFORM_VBNV": platform,
        "TARGET_PART": part,
        "KERNEL_FREQUENCY_MHZ": str(clock),
        "CONNECTIVITY": "{}.m_axi_gmem:HBM[0]".format(cu),
        "M_AXI_MASTER_COUNT": "1",
    }
    require(parse_contract(path) == expected, "link contract mismatch")


def validate_link_script(path, kernel, cu, platform, part, clock):
    text = path.read_text(encoding="utf-8", errors="replace")
    code = "\n".join(line.split("#", 1)[0] for line in text.splitlines())
    required = (
        'KERNEL_NAME="{}"'.format(kernel),
        'CU_NAME="{}"'.format(cu),
        'PLATFORM_VBNV="{}"'.format(platform),
        'PART_NAME="{}"'.format(part),
        'KERNEL_FREQUENCY_MHZ="${{KERNEL_FREQUENCY_MHZ:-{}}}"'.format(clock),
        "config/stage2n_a15_5_target_v1.cfg",
        "--target hw",
        "--link",
        '--kernel_frequency "${KERNEL_FREQUENCY_MHZ}"',
    )
    for fragment in required:
        require(fragment in text, "link runner lacks {}".format(fragment))
    require(len(re.findall(r"(?m)^\s*v\+\+\s", code)) == 1, "link runner must invoke v++ exactly once")
    for token in ("xbutil", "xbmgmt", "ssh", "scp", "rsync"):
        require(re.search(r"(?m)^\s*{}\b".format(re.escape(token)), code) is None, "forbidden operation {}".format(token))


def validate_kernel_xml(path, kernel):
    root = ET.parse(str(path)).getroot()
    kernels = [node for node in root.iter() if local_name(node.tag) == "kernel"]
    require(len(kernels) == 1, "kernel.xml must contain exactly one kernel")
    kernel_node = kernels[0]
    require(kernel_node.get("name") == kernel, "kernel.xml kernel name mismatch")
    args = [node for node in kernel_node.iter() if local_name(node.tag) == "arg"]
    require(len(args) == 1, "kernel.xml must contain TABLE_BASE only")
    arg = args[0]
    require(arg.get("name") == "TABLE_BASE", "kernel.xml argument is not TABLE_BASE")
    require(int(arg.get("id", "-1"), 0) == 0, "TABLE_BASE argument index mismatch")
    require(int(arg.get("offset", "-1"), 0) == 0x304, "TABLE_BASE offset mismatch")
    require(int(arg.get("size", "-1"), 0) == 8, "TABLE_BASE size mismatch")
    require(arg.get("addressQualifier") == "1", "TABLE_BASE is not a global pointer")
    require(arg.get("port") == "m_axi_gmem", "TABLE_BASE port mismatch")
    require(arg.get("type") == "void*", "TABLE_BASE type mismatch")
    text = path.read_text(encoding="utf-8", errors="replace")
    for stale in STALE_ARGUMENTS:
        require(stale not in text, "stale A14 argument present: {}".format(stale))


def validate_xclbin_info(path, kernel, cu, platform):
    text = path.read_text(encoding="utf-8", errors="replace")
    for expected, description in ((kernel, "kernel"), (cu, "compute unit"), (platform, "platform")):
        require(expected in text, "xclbin info lacks {} {}".format(description, expected))
    for stale in STALE_ARGUMENTS:
        require(stale not in text, "xclbin info contains stale A14 argument {}".format(stale))
    match = re.search(
        r"(?mi)^\s*UUID \(xclbin\):\s*([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\s*$",
        text,
    )
    require(match is not None, "xclbin UUID missing or malformed")
    return match.group(1)


def validate_layout_and_connectivity(connectivity_path, topology_path, layout_path, kernel, cu):
    connections = get_section(load_json(connectivity_path), "m_connection", "CONNECTIVITY")
    memories = get_section(load_json(topology_path), "m_mem_data", "MEM_TOPOLOGY")
    ips = get_section(load_json(layout_path), "m_ip_data", "IP_LAYOUT")

    require(len(connections) == 1, "CONNECTIVITY must contain exactly one connection")
    kernel_entries = [
        (index, entry) for index, entry in enumerate(ips)
        if str(entry.get("m_type", "")) == "IP_KERNEL"
    ]
    require(len(kernel_entries) == 1, "IP_LAYOUT must contain exactly one IP_KERNEL entry")
    kernel_index, kernel_entry = kernel_entries[0]
    expected_instance = "{}:{}".format(kernel, cu)
    require(str(kernel_entry.get("m_name", "")) == expected_instance, "IP_KERNEL name mismatch")

    connection = connections[0]
    require(parse_integer(connection, "arg_index", "connection") == 0, "connection arg_index must be zero")
    ip_index = parse_integer(connection, "m_ip_layout_index", "connection")
    memory_index = parse_integer(connection, "mem_data_index", "connection")
    require(0 <= ip_index < len(ips), "m_ip_layout_index is out of range")
    require(ip_index == kernel_index, "m_ip_layout_index does not reference the unique IP_KERNEL")
    require(0 <= memory_index < len(memories), "mem_data_index is out of range")
    memory = memories[memory_index]
    require(str(memory.get("m_tag", "")) == "HBM[0]", "connected memory is not HBM[0]")
    require(str(memory.get("m_used", "0")).lower() in ("1", "true"), "connected HBM[0] is not used")

    return {
        "ip_layout_count": len(ips),
        "kernel_index": kernel_index,
        "memory_count": len(memories),
        "memory_index": memory_index,
        "shell_ip_count": len(ips) - 1,
        "kernel_instance": expected_instance,
    }


def validate_all(args):
    validate_config(args.config, args.kernel, args.compute_unit)
    validate_contract(args.link_contract, args.kernel, args.compute_unit, args.platform, args.part, args.clock_mhz)
    validate_link_script(args.link_script, args.kernel, args.compute_unit, args.platform, args.part, args.clock_mhz)
    validate_kernel_xml(args.kernel_xml, args.kernel)
    uuid = validate_xclbin_info(args.xclbin_info, args.kernel, args.compute_unit, args.platform)
    layout = validate_layout_and_connectivity(
        args.connectivity, args.mem_topology, args.ip_layout, args.kernel, args.compute_unit
    )
    return uuid, layout


def make_ip_entries(kernel_name=EXPECTED_KERNEL_INSTANCE, kernel_count=1):
    entries = []
    for index in range(kernel_count):
        name = kernel_name if index == 0 else EXPECTED_KERNEL + ":dlrm_a15_2"
        entries.append({"m_type": "IP_KERNEL", "m_name": name, "m_base_address": hex(0x1800000 + index * 0x10000)})
    entries.extend(
        {"m_type": "IP_MEM_DDR4", "m_name": "platform_ddr{}".format(index)}
        for index in range(3)
    )
    entries.extend(
        {"m_type": "IP_MEM_HBM", "m_name": "platform_hbm{}".format(index)}
        for index in range(32)
    )
    return entries


def json_section(name, list_key, entries):
    return json.dumps({name: {"m_count": len(entries), list_key: entries}})


def good_kernel_xml():
    return """<root><kernel name=\"{0}\"><args><arg name=\"TABLE_BASE\" id=\"0\" offset=\"0x304\" size=\"0x8\" addressQualifier=\"1\" port=\"m_axi_gmem\" type=\"void*\"/></args></kernel></root>""".format(EXPECTED_KERNEL)


def good_config():
    return "[connectivity]\nnk={0}:1:{1}\nsp={1}.m_axi_gmem:HBM[0]\n".format(EXPECTED_KERNEL, EXPECTED_CU)


def good_contract():
    return "\n".join((
        "KERNEL=" + EXPECTED_KERNEL,
        "COMPUTE_UNIT=" + EXPECTED_CU,
        "PLATFORM_VBNV=" + EXPECTED_PLATFORM,
        "TARGET_PART=" + EXPECTED_PART,
        "KERNEL_FREQUENCY_MHZ=100",
        "CONNECTIVITY=" + EXPECTED_CU + ".m_axi_gmem:HBM[0]",
        "M_AXI_MASTER_COUNT=1",
        "",
    ))


def good_link_script():
    return """#!/usr/bin/env bash
KERNEL_NAME=\"{0}\"
CU_NAME=\"{1}\"
PLATFORM_VBNV=\"{2}\"
PART_NAME=\"{3}\"
KERNEL_FREQUENCY_MHZ=\"${{KERNEL_FREQUENCY_MHZ:-100}}\"
CONFIG=\"config/stage2n_a15_5_target_v1.cfg\"
v++ --target hw --link --config \"${{CONFIG}}\" --kernel_frequency \"${{KERNEL_FREQUENCY_MHZ}}\"
""".format(EXPECTED_KERNEL, EXPECTED_CU, EXPECTED_PLATFORM, EXPECTED_PART)


def good_info(extra=""):
    return """Kernel: {0}
Compute Unit: {1}
Platform: {2}
UUID (xclbin): 12345678-1234-1234-1234-123456789abc
{3}""".format(EXPECTED_KERNEL, EXPECTED_CU, EXPECTED_PLATFORM, extra)


def run_self_test():
    with tempfile.TemporaryDirectory(prefix="a15_5_xclbin_v2_") as temp_name:
        temp = Path(temp_name)
        names = ("connectivity", "mem", "ip", "info", "config", "link", "contract", "kernel_xml")
        paths = {name: temp / name for name in names}
        memories = [
            {"m_type": "MEM_DDR4", "m_tag": "HBM[0]", "m_used": "1", "m_base_address": "0x0"},
            {"m_type": "MEM_DDR4", "m_tag": "HBM[1]", "m_used": "0"},
            {"m_type": "MEM_DRAM", "m_tag": "HBM[2]", "m_used": "0"},
        ]
        originals = {
            "connectivity": json_section("connectivity", "m_connection", [
                {"arg_index": 0, "m_ip_layout_index": 0, "mem_data_index": 0}
            ]),
            "mem": json_section("mem_topology", "m_mem_data", memories),
            "ip": json_section("ip_layout", "m_ip_data", make_ip_entries()),
            "info": good_info(),
            "config": good_config(),
            "link": good_link_script(),
            "contract": good_contract(),
            "kernel_xml": good_kernel_xml(),
        }

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
        args.kernel_xml = paths["kernel_xml"]
        args.kernel = EXPECTED_KERNEL
        args.compute_unit = EXPECTED_CU
        args.platform = EXPECTED_PLATFORM
        args.part = EXPECTED_PART
        args.clock_mhz = EXPECTED_CLOCK

        def write_all(overrides=None):
            overrides = overrides or {}
            for name, path in paths.items():
                path.write_text(overrides.get(name, originals[name]), encoding="utf-8")

        write_all()
        _, result = validate_all(args)
        require(result["ip_layout_count"] == 36, "positive fixture is not Vitis 2020.2 style")
        require(result["shell_ip_count"] == 35, "positive fixture shell count mismatch")
        print("XCLBIN_V2_SELF_TEST_VITIS_2020_2_LAYOUT=PASS")

        zero_kernel = json_section("ip_layout", "m_ip_data", make_ip_entries(kernel_count=0))
        two_kernels = json_section("ip_layout", "m_ip_data", make_ip_entries(kernel_count=2))
        wrong_kernel = json_section("ip_layout", "m_ip_data", make_ip_entries("wrong_kernel:" + EXPECTED_CU))
        wrong_cu = json_section("ip_layout", "m_ip_data", make_ip_entries(EXPECTED_KERNEL + ":wrong_cu"))
        wrong_bank_memories = list(memories)
        wrong_bank_memories[0] = dict(wrong_bank_memories[0], m_tag="HBM[1]")
        unused_memories = list(memories)
        unused_memories[0] = dict(unused_memories[0], m_used="0")
        second_connection = json_section("connectivity", "m_connection", [
            {"arg_index": 0, "m_ip_layout_index": 0, "mem_data_index": 0},
            {"arg_index": 0, "m_ip_layout_index": 0, "mem_data_index": 1},
        ])
        wrong_ip_index = json_section("connectivity", "m_connection", [
            {"arg_index": 0, "m_ip_layout_index": 1, "mem_data_index": 0}
        ])
        wrong_arg_index = json_section("connectivity", "m_connection", [
            {"arg_index": 1, "m_ip_layout_index": 0, "mem_data_index": 0}
        ])
        wrong_mem_index = json_section("connectivity", "m_connection", [
            {"arg_index": 0, "m_ip_layout_index": 0, "mem_data_index": 1}
        ])
        cases = [
            ("NO_IP_KERNEL", "ip", zero_kernel),
            ("SECOND_IP_KERNEL", "ip", two_kernels),
            ("WRONG_KERNEL", "ip", wrong_kernel),
            ("WRONG_CU", "ip", wrong_cu),
            ("WRONG_HBM_BANK", "mem", json_section("mem_topology", "m_mem_data", wrong_bank_memories)),
            ("HBM0_UNUSED", "mem", json_section("mem_topology", "m_mem_data", unused_memories)),
            ("SECOND_CONNECTIVITY", "connectivity", second_connection),
            ("WRONG_ARG_INDEX", "connectivity", wrong_arg_index),
            ("WRONG_IP_LAYOUT_INDEX", "connectivity", wrong_ip_index),
            ("WRONG_MEM_DATA_INDEX", "connectivity", wrong_mem_index),
            ("STALE_LOOKUP_INDEX", "kernel_xml", good_kernel_xml().replace("</args>", '<arg name="LOOKUP_INDEX"/></args>')),
            ("STALE_RESULT0", "kernel_xml", good_kernel_xml().replace("</args>", '<arg name="RESULT0"/></args>')),
        ]
        for label, target, replacement in cases:
            write_all({target: replacement})
            try:
                validate_all(args)
            except ValidationError:
                print("XCLBIN_V2_SELF_TEST_REJECT_{}=PASS".format(label))
            else:
                raise ValidationError("negative self-test was accepted: {}".format(label))

    print("A15_5_XCLBIN_VALIDATOR_V2_SELF_TEST=PASS")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--connectivity", type=Path)
    parser.add_argument("--mem-topology", type=Path)
    parser.add_argument("--ip-layout", type=Path)
    parser.add_argument("--xclbin-info", type=Path)
    parser.add_argument("--config", type=Path)
    parser.add_argument("--link-script", type=Path)
    parser.add_argument("--link-contract", type=Path)
    parser.add_argument("--kernel-xml", type=Path)
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
            args.config, args.link_script, args.link_contract, args.kernel_xml,
        )
        require(all(path is not None for path in paths), "all metadata paths are required")
        for path in paths:
            require(path.is_file() and path.stat().st_size > 0, "missing or empty input: {}".format(path))
        uuid, layout = validate_all(args)
    except (OSError, ValueError, json.JSONDecodeError, ET.ParseError, ValidationError) as error:
        raise SystemExit("A15.5 xclbin v2 validation failed: {}".format(error))

    print("A15_5_XCLBIN_METADATA_VALIDATION_V2=PASS")
    print("KERNEL={}".format(args.kernel))
    print("COMPUTE_UNIT={}".format(args.compute_unit))
    print("IP_KERNEL_INSTANCE={}".format(layout["kernel_instance"]))
    print("IP_LAYOUT_ENTRY_COUNT={}".format(layout["ip_layout_count"]))
    print("IP_KERNEL_ENTRY_COUNT=1")
    print("SHELL_IP_ENTRY_COUNT={}".format(layout["shell_ip_count"]))
    print("KERNEL_IP_LAYOUT_INDEX={}".format(layout["kernel_index"]))
    print("CONNECTIVITY_RECORD_COUNT=1")
    print("CONNECTIVITY_ARG_INDEX=0")
    print("MEM_TOPOLOGY_ENTRY_COUNT={}".format(layout["memory_count"]))
    print("CONNECTED_MEM_DATA_INDEX={}".format(layout["memory_index"]))
    print("CONNECTED_MEMORY_TAG=HBM[0]")
    print("CONNECTED_MEMORY_USED=1")
    print("TABLE_BASE_ONLY_ARGUMENT=PASS")
    print("STALE_A14_ARGUMENTS=ABSENT")
    print("XCLBIN_UUID={}".format(uuid))
    print("PHYSICAL_HBM=NOT_VALIDATED")
    print("FPGA_DEVICE_ACCESS=NONE")


if __name__ == "__main__":
    main()
