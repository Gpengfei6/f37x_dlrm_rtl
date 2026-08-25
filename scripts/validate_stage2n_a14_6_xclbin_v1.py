#!/usr/bin/env python3
"""Validate A14.6 linked-xclbin identity and HBM[0] connectivity metadata."""

import argparse
import json
import re
from pathlib import Path


def fail(message):
    raise SystemExit("A14.6 xclbin validation failed: {}".format(message))


def load_json(path):
    try:
        with path.open("r", encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, ValueError) as error:
        fail("cannot read {}: {}".format(path, error))


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
    if key not in entry:
        fail("CONNECTIVITY record lacks {}".format(key))
    value = entry[key]
    try:
        return value if isinstance(value, int) else int(str(value), 0)
    except ValueError:
        fail("CONNECTIVITY {} is not an integer: {}".format(key, value))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--connectivity", type=Path, required=True)
    parser.add_argument("--mem-topology", type=Path, required=True)
    parser.add_argument("--ip-layout", type=Path, required=True)
    parser.add_argument("--xclbin-info", type=Path, required=True)
    parser.add_argument("--kernel", required=True)
    parser.add_argument("--compute-unit", required=True)
    parser.add_argument("--platform", required=True)
    args = parser.parse_args()

    for path in (
        args.connectivity,
        args.mem_topology,
        args.ip_layout,
        args.xclbin_info,
    ):
        if not path.is_file() or path.stat().st_size == 0:
            fail("required input is missing or empty: {}".format(path))

    try:
        info_text = args.xclbin_info.read_text(encoding="utf-8", errors="replace")
    except OSError as error:
        fail("cannot read xclbin info: {}".format(error))

    for expected, description in (
        (args.kernel, "kernel"),
        (args.compute_unit, "compute unit"),
        (args.platform, "platform"),
    ):
        if expected not in info_text:
            fail("xclbin info is missing {} {}".format(description, expected))

    uuid_match = re.search(
        r"(?mi)^\s*UUID \(xclbin\):\s*"
        r"([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-"
        r"[0-9a-f]{4}-[0-9a-f]{12})\s*$",
        info_text,
    )
    if uuid_match is None:
        fail("xclbin UUID is missing or malformed")

    connectivity = load_json(args.connectivity)
    topology = load_json(args.mem_topology)
    layout = load_json(args.ip_layout)

    connections = find_lists(connectivity, "m_connection")
    memories = find_lists(topology, "m_mem_data")
    ips = find_lists(layout, "m_ip_data")
    if not connections:
        fail("CONNECTIVITY contains no connection records")

    hbm0_entries = [
        entry for entry in memories if str(entry.get("m_tag", "")) == "HBM[0]"
    ]
    if len(hbm0_entries) != 1:
        fail("MEM_TOPOLOGY does not contain exactly one HBM[0]")
    hbm0 = hbm0_entries[0]
    if str(hbm0.get("m_used", "1")).lower() in ("0", "false"):
        fail("HBM[0] is not marked used")

    ip_names = [str(entry.get("m_name", "")) for entry in ips]
    cu_indices = [
        index for index, name in enumerate(ip_names) if args.compute_unit in name
    ]
    if len(cu_indices) != 1:
        fail("IP_LAYOUT does not contain exactly one reviewed compute unit")

    cu_index = cu_indices[0]
    hbm0_index = memories.index(hbm0)
    matching = [
        entry
        for entry in connections
        if parse_index(entry, "m_ip_layout_index") == cu_index
        and parse_index(entry, "mem_data_index") == hbm0_index
    ]
    if len(matching) != 1:
        fail("CONNECTIVITY does not contain exactly one reviewed CU-to-HBM[0] record")

    print("A14_6_XCLBIN_METADATA_VALIDATION=PASS")
    print("KERNEL={}".format(args.kernel))
    print("COMPUTE_UNIT={}".format(args.compute_unit))
    print("PLATFORM={}".format(args.platform))
    print("XCLBIN_UUID={}".format(uuid_match.group(1)))
    print("CONNECTIVITY_RECORD_COUNT={}".format(len(connections)))
    print("A14_6_CU_INDEX={}".format(cu_index))
    print("A14_6_HBM0_INDEX={}".format(hbm0_index))
    print("A14_6_CU_TO_HBM0_CONNECTION=PASS")
    print("A14_6_HBM0_USED=PASS")
    print("A14_6_PHYSICAL_HBM=NOT_VALIDATED")
    print("A14_6_FPGA_DEVICE_ACCESS=NONE")


if __name__ == "__main__":
    main()
