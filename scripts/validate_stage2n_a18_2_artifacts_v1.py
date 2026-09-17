#!/usr/bin/env python3
"""Offline A18.2 artifact checks. A successful check is never a board PASS."""
from __future__ import print_function

import hashlib
import json
import math
import re
import zipfile
import xml.etree.ElementTree as ET
from pathlib import Path

from validate_stage2n_a16_2_xo_v1 import (
    ValidationError, require, require_one, direct_children, child_text,
    named_children, parameter_values, parse_scaled_integer, local_name,
)
from validate_stage2n_a16_2_xclbin_v1 import (
    get_section, parse_integer, validate_xclbin_info,
)

KERNEL = "dlrm_f37x_rtl_kernel_stage2n_a18_v1"
CU = "dlrm_a18_1"
PART = "xcvu37p-fsvh2892-2L-e"
PLATFORM = "inspur_f37x_xdma_201920_3"
OFFSETS = (0x304, 0x318, 0x320, 0x328)
INDEX_OFFSETS = (0x330, 0x334, 0x338, 0x33C)
PORTS = tuple("m_axi_gmem{}".format(i) for i in range(4))
PACKAGE = "scripts/package_stage2n_a18_2_rtl_kernel_v1.tcl"
CONFIG = "config/stage2n_a18_2_target_v1.cfg"
REPORT = "scripts/report_stage2n_a16_2_vitis_post_route_v1.tcl"
MANIFEST = "config/stage2n_a18_2_sources_v1.json"


def digest(path):
    h = hashlib.sha256()
    with Path(path).open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def source_files(root):
    text = (root / PACKAGE).read_text(encoding="utf-8")
    sources = re.findall(r"\[source_path \$root_dir (rtl/[^\s\]]+)\]", text)
    require(len(sources) == 19 and len(set(sources)) == 19, "expected 19 unique RTL sources")
    require("rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a18_v1.sv" in sources, "A18 kernel missing from package Tcl")
    require("rtl/pipeline/dlrm_hbm_pipeline_integration_stage2n_a18_v1.sv" in sources, "A18 integration missing from package Tcl")
    require("rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a17_v1.sv" not in sources, "A17 kernel must not be the A18 package top")
    require("rtl/pipeline/dlrm_hbm_pipeline_integration_stage2n_a17_v1.sv" not in sources, "A17 integration must not be packaged as A18")
    return sources


def config_check(path):
    lines = [line.split("#", 1)[0].strip() for line in path.read_text(encoding="utf-8").splitlines()]
    actual = [line for line in lines if line]
    expected = ["[connectivity]", "nk={}:1:{}".format(KERNEL, CU)]
    expected += ["sp={}.{}:HBM[{}]".format(CU, port, i) for i, port in enumerate(PORTS)]
    require(actual == expected, "connectivity must contain one A18 CU and exact four-bank map")


def source_check(root):
    manifest = json.loads((root / MANIFEST).read_text(encoding="utf-8"))
    require(manifest.get("schema") == "a18_2_source_manifest_v1", "source manifest schema mismatch")
    files = manifest["files"]
    expected = set(source_files(root) + [PACKAGE, CONFIG, REPORT,
        "scripts/validate_stage2n_a16_2_xo_v1.py",
        "scripts/validate_stage2n_a16_2_xclbin_v1.py",
        "scripts/validate_stage2n_a18_2_artifacts_v1.py",
        "scripts/run_stage2n_a18_2_build_v1.py",
        "scripts/test_stage2n_a18_2_build_v1.py",
        "docs/STAGE2N_A18_2_TARGET_PACKAGING_HOST_PREP_V1.md"])
    require(set(files) == expected, "source manifest closure mismatch")
    for relative, expected_hash in files.items():
        require(digest(root / relative) == expected_hash, "source hash mismatch: " + relative)
    config_check(root / CONFIG)
    kernel_rtl = (root / "rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a18_v1.sv").read_text(
        encoding="utf-8")
    for token in ("12'h330", "12'h334", "12'h338", "12'h33C",
                  "a18_lookup_index_cmd <= a18_lookup_index_stage",
                  "32'h0002_4E18"):
        require(token in kernel_rtl, "A18 kernel missing " + token)
    require("dlrm_internal_pipeline_axi_lite_decode_stage2n_a18_v1" not in kernel_rtl,
            "A18 kernel must not instantiate the leftover decode draft")
    return manifest


def kernel_check(data):
    root = ET.fromstring(data)
    kernel = require_one([n for n in root.iter() if local_name(n.tag) == "kernel"], "kernel")
    require(kernel.get("name") == KERNEL, "wrong kernel")
    require(kernel.get("hwControlProtocol") == "user_managed", "wrong control protocol")
    nodes = direct_children(require_one(direct_children(kernel, "ports"), "ports"), "port")
    ports = {p.get("name"): p for p in nodes}
    require(len(nodes) == 5 and set(ports) == set(PORTS) | {"s_axi_control"}, "wrong kernel port set")
    require(ports["s_axi_control"].get("mode") == "slave" and
            ports["s_axi_control"].get("dataWidth") == "32", "wrong control interface")
    for name in PORTS:
        port = ports[name]
        require(port.get("mode") == "master" and port.get("dataWidth") == "128", "wrong master width/mode")
        # Vitis 2020.2 can serialize a 32-bit kernel.xml range despite a 64-bit
        # pointer. The component address space AND physical ports below must
        # independently prove 64 bits, following the accepted A16 target flow.
        require(int(port.get("range", "-1"), 0) in (0xffffffff, 0xffffffffffffffff), "wrong master range")
    args = direct_children(require_one(direct_children(kernel, "args"), "args"), "arg")
    require(len(args) == 4, "expected four pointer arguments")
    by_id = {int(arg.get("id", "-1"), 0): arg for arg in args}
    require(set(by_id) == set(range(4)), "duplicate/missing argument ID")
    names = {arg.get("name") for arg in args}
    for stale in ("LOOKUP_INDEX", "LOOKUP_INDEX0", "LOOKUP_INDEX1",
                  "LOOKUP_INDEX2", "LOOKUP_INDEX3", "RESULT0"):
        require(stale not in names, "indexes must not be kernel pointer arguments")
    for i, offset in enumerate(OFFSETS):
        arg = by_id[i]
        for key, value in (("name", "TABLE_BASE{}".format(i)), ("port", PORTS[i]),
                           ("addressQualifier", "1"), ("type", "void*")):
            require(arg.get(key) == value, "argument {} {} mismatch".format(i, key))
        for key, value in (("offset", offset), ("size", 8), ("hostSize", 8)):
            require(int(arg.get(key, "-1"), 0) == value, "argument {} {} mismatch".format(i, key))


def component_check(data):
    root = ET.fromstring(data)
    buses = named_children(require_one(direct_children(root, "busInterfaces"), "busInterfaces"), "busInterface")
    require(set(buses) == set(PORTS) | {"s_axi_control", "ap_clk", "ap_rst_n"}, "wrong component interfaces")
    spaces = named_children(require_one(direct_children(root, "addressSpaces"), "addressSpaces"), "addressSpace")
    require(set(spaces) == set(PORTS), "wrong address spaces")
    for name in PORTS:
        bus = buses[name]
        master = require_one(direct_children(bus, "master"), "AXI master")
        require(not direct_children(bus, "slave"), "AXI master also marked slave")
        ref = require_one(direct_children(master, "addressSpaceRef"), "addressSpaceRef")
        refs = [v for k, v in ref.attrib.items() if local_name(k) == "addressSpaceRef"]
        require(refs == [name], "wrong master addressSpaceRef")
        params = parameter_values(bus)
        require(params.get("ADDR_WIDTH") == ["64"] and params.get("DATA_WIDTH") == ["128"], "wrong bus widths")
        require(parse_scaled_integer(child_text(spaces[name], "range", "range")) == 1 << 64, "address space is not 64 bit")
        require(int(child_text(spaces[name], "width", "width"), 0) == 128, "address-space data width mismatch")
    maps = named_children(require_one(direct_children(root, "memoryMaps"), "memoryMaps"), "memoryMap")
    block = require_one(direct_children(maps["s_axi_control"], "addressBlock"), "control block")
    require(parse_scaled_integer(child_text(block, "range", "range")) >= 0x340, "control range too small for A18 indexes")
    regs = named_children(block, "register")
    require(set(regs) == {"TABLE_BASE{}".format(i) for i in range(4)}, "wrong argument registers")
    for i, offset in enumerate(OFFSETS):
        reg = regs["TABLE_BASE{}".format(i)]
        require(int(child_text(reg, "addressOffset", "offset"), 0) == offset, "wrong register offset")
        require(int(child_text(reg, "size", "size"), 0) == 64, "wrong pointer width")
        require(child_text(reg, "access", "access") == "read-write", "pointer is not writable")
        require(parameter_values(reg).get("ASSOCIATED_BUSIF") == [PORTS[i]], "wrong pointer bus association")
    model = require_one(direct_children(root, "model"), "model")
    physical = named_children(require_one(direct_children(model, "ports"), "model ports"), "port")
    for port in PORTS:
        for suffix, width in (("araddr", 64), ("awaddr", 64), ("rdata", 128), ("wdata", 128)):
            name = port + "_" + suffix
            require(name in physical, "missing physical port " + name)
            wire = require_one(direct_children(physical[name], "wire"), "wire")
            vector = require_one(direct_children(wire, "vector"), "vector")
            require(int(child_text(vector, "left", "left"), 0) == width - 1 and
                    int(child_text(vector, "right", "right"), 0) == 0, "wrong physical port width " + name)


def xo_check(path, kernel_xml, component_xml):
    require(path.is_file() and path.stat().st_size > 0, "missing/empty XO")
    with zipfile.ZipFile(str(path)) as archive:
        require(archive.testzip() is None, "XO zip integrity failure")
        names = archive.namelist()
        k = require_one([n for n in names if n.endswith("/kernel.xml")], "archived kernel.xml")
        c = require_one([n for n in names if n.startswith("ip_repo/") and n.endswith("/component.xml")], "archived component.xml")
        kernel, component = archive.read(k), archive.read(c)
        require(kernel == kernel_xml.read_bytes(), "external/archived kernel.xml mismatch")
        require(component == component_xml.read_bytes(), "external/archived component.xml mismatch")
        kernel_check(kernel)
        component_check(component)


def mapping_check(connections, memories, ips):
    kernels = [(i, ip) for i, ip in enumerate(ips) if ip.get("m_type") == "IP_KERNEL"]
    index, ip = require_one(kernels, "IP_KERNEL")
    require(ip.get("m_name") == KERNEL + ":" + CU, "wrong CU identity")
    require(len(connections) == 4, "expected four connections")
    result = {}
    for conn in connections:
        arg = parse_integer(conn, "arg_index", "connection")
        mem = parse_integer(conn, "mem_data_index", "connection")
        require(arg in range(4) and arg not in result, "duplicate/invalid connected argument")
        require(parse_integer(conn, "m_ip_layout_index", "connection") == index, "connection targets shell/other IP")
        require(0 <= mem < len(memories), "memory index out of range")
        require(memories[mem].get("m_tag") == "HBM[{}]".format(arg), "wrong bank tag for argument")
        require(str(memories[mem].get("m_used", "0")).lower() in ("1", "true"), "connected bank unused")
        result[arg] = mem
    require(len(set(result.values())) == 4, "four arguments share a memory index")
    return [result[i] for i in range(4)]


def linked_check(directory):
    values = []
    for filename, key in (("connectivity.json", "m_connection"), ("mem_topology.json", "m_mem_data"), ("ip_layout.json", "m_ip_data")):
        values.append(get_section(json.loads((directory / filename).read_text(encoding="utf-8")), key, filename))
    indices = mapping_check(*values)
    uuid = validate_xclbin_info(directory / "xclbin.info", KERNEL, CU, PLATFORM)
    return {"xclbin_uuid": uuid, "memory_indices_by_argument": indices}


def timing_check(path):
    metrics = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            require(key not in metrics, "duplicate timing metric")
            metrics[key] = value
    require(metrics.get("TARGET_PART") == PART, "wrong routed part")
    for key in ("WNS_NS", "TNS_NS", "FAILING_ENDPOINTS", "DRC_ERROR_COUNT", "METHODOLOGY_ERROR_COUNT", "LATCH"):
        value = float(metrics.get(key, "nan"))
        require(math.isfinite(value), "missing/non-numeric timing metric " + key)
        require(value >= 0 if key == "WNS_NS" else value == 0, "routed gate failed: " + key)
    clocks = metrics.get("CLOCKS", "").split(",")
    kernel_clocks = [row.rsplit(":", 1)[1] for row in clocks
                     if "clkwiz_kernel_0:" in row]
    require(len(kernel_clocks) == 1 and float(kernel_clocks[0]) == 10.0,
            "actual routed kernel clock is not the expected 10 ns")
    summary = (path.parent / "post_route_timing_summary.rpt").read_text(encoding="utf-8", errors="replace")
    header = re.search(r"WNS\(ns\).*WHS\(ns\).*WPWS\(ns\)[^\n]*", summary)
    require(header is not None, "missing setup/hold/pulse summary")
    values = None
    for row in summary[header.end():].splitlines()[:8]:
        fields = row.split()
        if len(fields) != 12:
            continue
        try:
            values = [float(v) for v in fields]
            break
        except ValueError:
            continue
    require(values is not None and all(math.isfinite(v) for v in values), "unparsed timing summary")
    for start in (0, 4, 8):
        require(values[start] >= 0 and values[start + 1] == 0 and values[start + 2] == 0,
                "setup/hold/pulse timing violation")
    check = (path.parent / "post_route_check_timing.rpt").read_text(encoding="utf-8", errors="replace")
    for name in ("no_clock", "unconstrained_internal_endpoints"):
        counts = re.findall(r"checking " + name + r"\s+\((\d+)\)", check)
        require(counts and all(int(n) == 0 for n in counts), "unconstrained timing: " + name)
    # Warning counts are retained; zero errors does not mean zero warnings.
    return metrics
