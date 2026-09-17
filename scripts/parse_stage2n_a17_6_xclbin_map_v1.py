#!/usr/bin/env python3
"""Resolve A17.6 arg0..3 memory indices from xclbin CONNECTIVITY/MEM_TOPOLOGY.

Memory indices are taken from metadata tags, not assumed to be 0..3.
This script never opens a device.
"""
from __future__ import print_function

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from validate_stage2n_a16_2_xclbin_v1 import get_section
from validate_stage2n_a17_6_artifacts_v1 import (
    CU,
    KERNEL,
    mapping_check,
)


MAP_HEADER = "A17_6_MEM_MAP_V1"


def load_section(path, key, description):
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    return get_section(data, key, description)


def build_map_text(connections, memories, ips, uuid_text):
    indices = mapping_check(connections, memories, ips)
    lines = [
        MAP_HEADER,
        "UUID={}".format(uuid_text),
        "KERNEL={}".format(KERNEL),
        "CU={}".format(CU),
        "IP_NAME={}:{}".format(KERNEL, CU),
    ]
    for arg, mem in enumerate(indices):
        tag = memories[mem].get("m_tag")
        lines.append("ARG{}_MEM_INDEX={}".format(arg, mem))
        lines.append("ARG{}_TAG={}".format(arg, tag))
    lines.append("MEMORY_INDICES_BY_ARGUMENT={}".format(
        ",".join(str(value) for value in indices)))
    return "\n".join(lines) + "\n", indices


def parse_host_mem_map_text(text, min_key_size=8):
    """Mirror A17.6 Host ARG key rules. min_key_size=14 is the pre-fix bug."""
    lines = text.replace("\r\n", "\n").split("\n")
    if not lines or lines[0].strip() != MAP_HEADER:
        raise ValueError("memory map header is not A17_6_MEM_MAP_V1")
    mem_index = [None] * 4
    tag = [None] * 4
    uuid_text = None
    for raw in lines[1:]:
        text_line = raw.strip()
        if not text_line or text_line.startswith("#"):
            continue
        if "=" not in text_line:
            raise ValueError("malformed memory-map line: " + text_line)
        key, value = text_line.split("=", 1)
        if key == "UUID":
            uuid_text = value
            continue
        if (len(key) >= min_key_size and key.startswith("ARG") and
                len(key) > 3 and "0" <= key[3] <= "3"):
            arg = int(key[3])
            if "_MEM_INDEX" in key:
                mem_index[arg] = int(value)
            elif "_TAG" in key:
                tag[arg] = value
    if uuid_text is None:
        raise ValueError("memory map lacks UUID")
    for arg in range(4):
        if mem_index[arg] is None or tag[arg] is None:
            raise ValueError("memory map missing argument " + str(arg))
        expected_tag = "HBM[{}]".format(arg)
        if tag[arg] != expected_tag:
            raise ValueError(
                "argument {} tag is {}, expected {}".format(
                    arg, tag[arg], expected_tag))
    return {"uuid": uuid_text, "mem_index": mem_index, "tag": tag}


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--connectivity", required=True)
    parser.add_argument("--mem-topology", required=True)
    parser.add_argument("--ip-layout", required=True)
    parser.add_argument("--uuid", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args(argv)

    connections = load_section(args.connectivity, "m_connection", "connectivity")
    memories = load_section(args.mem_topology, "m_mem_data", "mem_topology")
    ips = load_section(args.ip_layout, "m_ip_data", "ip_layout")
    text, indices = build_map_text(connections, memories, ips, args.uuid)
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(text, encoding="utf-8")
    print("A17_6_MEM_MAP=PASS")
    print("MEMORY_INDICES_BY_ARGUMENT={}".format(
        ",".join(str(value) for value in indices)))
    print("OUTPUT={}".format(output))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as error:
        print("A17_6_MEM_MAP=FAIL", file=sys.stderr)
        print("REASON={}".format(error), file=sys.stderr)
        sys.exit(1)
