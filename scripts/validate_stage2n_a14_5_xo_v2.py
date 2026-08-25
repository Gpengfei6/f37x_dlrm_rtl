#!/usr/bin/env python3
"""Validate the Stage 2N-A14.5 runtime-table-base XO metadata.

Vivado 2020.2 can emit a 32-bit-looking ``range`` attribute in kernel.xml
even when the packaged AXI address interface is 64 bits.  Treat that field as
descriptive metadata, not as the sole address-width proof.  The acceptance
gate instead requires consistent evidence from the kernel argument, IP-XACT
bus/model parameters and address space, component ports, and source RTL.
"""

import argparse
import re
import xml.etree.ElementTree as ET
from pathlib import Path


def fail(message):
    raise SystemExit(message)


def local_name(tag):
    return tag.rsplit("}", 1)[-1]


def direct_children(node, name):
    return [child for child in node if local_name(child.tag) == name]


def require_one(nodes, description):
    if len(nodes) != 1:
        fail("expected one {}, found {}".format(description, len(nodes)))
    return nodes[0]


def child_text(node, name, description):
    child = require_one(direct_children(node, name), description)
    return (child.text or "").strip()


def named_children(container, child_kind):
    result = {}
    for child in direct_children(container, child_kind):
        name = child_text(child, "name", "{} name".format(child_kind))
        if not name or name in result:
            fail("empty or duplicate {} name: {}".format(child_kind, name))
        result[name] = child
    return result


def parse_scaled_integer(value):
    match = re.fullmatch(r"([0-9]+)([KMGT]?)", value.strip(), re.IGNORECASE)
    if match is None:
        fail("unsupported IP-XACT integer: {}".format(value))
    suffix_shift = {"": 0, "K": 10, "M": 20, "G": 30, "T": 40}
    return int(match.group(1)) << suffix_shift[match.group(2).upper()]


def parameter_values(node):
    values = {}
    for candidate in node.iter():
        if local_name(candidate.tag) not in ("parameter", "modelParameter"):
            continue
        names = direct_children(candidate, "name")
        value_nodes = direct_children(candidate, "value")
        if len(names) != 1 or len(value_nodes) != 1:
            continue
        name = (names[0].text or "").strip()
        value = (value_nodes[0].text or "").strip()
        values.setdefault(name, []).append(value)
    return values


def validate_kernel_xml(path, expected_kernel):
    root = ET.parse(str(path)).getroot()
    kernels = [node for node in root.iter() if local_name(node.tag) == "kernel"]
    kernel = require_one(kernels, "kernel.xml kernel element")

    if kernel.get("name") != expected_kernel:
        fail("kernel.xml kernel name mismatch")
    if kernel.get("hwControlProtocol") != "user_managed":
        fail("kernel.xml control protocol is not user_managed")

    ports_container = require_one(direct_children(kernel, "ports"), "ports element")
    ports = {node.get("name"): node for node in direct_children(ports_container, "port")}
    if set(ports) != {"s_axi_control", "m_axi_gmem"}:
        fail("kernel.xml port set mismatch: {}".format(sorted(ports)))

    control = ports["s_axi_control"]
    if control.get("mode") != "slave" or control.get("dataWidth") != "32":
        fail("s_axi_control metadata mismatch")
    memory = ports["m_axi_gmem"]
    if memory.get("mode") != "master" or memory.get("dataWidth") != "128":
        fail("m_axi_gmem data metadata mismatch")

    range_text = memory.get("range", "")
    try:
        range_value = int(range_text, 0)
    except ValueError:
        fail("invalid kernel.xml m_axi_gmem range: {}".format(range_text))
    if range_value not in (0xFFFFFFFF, 0xFFFFFFFFFFFFFFFF):
        fail("unexpected kernel.xml m_axi_gmem range: {}".format(range_text))

    args_container = require_one(direct_children(kernel, "args"), "args element")
    args = {}
    for arg in direct_children(args_container, "arg"):
        name = arg.get("name")
        if not name or name in args:
            fail("unnamed or duplicate kernel argument")
        args[name] = arg

    expected = {
        "LOOKUP_INDEX": (0, 0x10, 4),
        "TABLE_BASE": (1, 0x18, 8),
        "RESULT0": (2, 0x20, 4),
        "RESULT1": (3, 0x24, 4),
        "RESULT2": (4, 0x28, 4),
        "RESULT3": (5, 0x2C, 4),
    }
    if set(args) != set(expected):
        fail("kernel.xml argument set mismatch: {}".format(sorted(args)))

    for name, (expected_id, expected_offset, expected_size) in expected.items():
        arg = args[name]
        if int(arg.get("id", "-1"), 0) != expected_id:
            fail("{} argument ID mismatch".format(name))
        if int(arg.get("offset", "-1"), 0) != expected_offset:
            fail("{} argument offset mismatch".format(name))
        if int(arg.get("size", "-1"), 0) != expected_size:
            fail("{} argument size mismatch".format(name))
        if int(arg.get("hostSize", "-1"), 0) != expected_size:
            fail("{} argument host size mismatch".format(name))
        if int(arg.get("hostOffset", "0"), 0) != 0:
            fail("{} argument host offset mismatch".format(name))

    table_base = args["TABLE_BASE"]
    if table_base.get("addressQualifier") != "1":
        fail("TABLE_BASE is not a global-memory argument")
    if table_base.get("port") != "m_axi_gmem":
        fail("TABLE_BASE is not bound to m_axi_gmem")
    if table_base.get("type") != "void*":
        fail("TABLE_BASE type is not void*")

    for name, arg in args.items():
        if name == "TABLE_BASE":
            continue
        if arg.get("addressQualifier") != "0":
            fail("{} is not a scalar argument".format(name))
        if arg.get("port") != "s_axi_control":
            fail("{} is not bound to s_axi_control".format(name))

    return range_text


def validate_component_xml(path):
    component = ET.parse(str(path)).getroot()

    bus_interfaces_container = require_one(
        direct_children(component, "busInterfaces"), "busInterfaces element"
    )
    interfaces = named_children(bus_interfaces_container, "busInterface")
    for required in ("m_axi_gmem", "s_axi_control", "ap_clk", "ap_rst_n"):
        if required not in interfaces:
            fail("component.xml is missing bus interface {}".format(required))

    memory_interface = interfaces["m_axi_gmem"]
    master = require_one(
        direct_children(memory_interface, "master"), "m_axi_gmem master interface"
    )
    address_space_ref = require_one(
        direct_children(master, "addressSpaceRef"), "m_axi_gmem address-space reference"
    )
    reference_values = [
        value
        for key, value in address_space_ref.attrib.items()
        if local_name(key) == "addressSpaceRef"
    ]
    if reference_values != ["m_axi_gmem"]:
        fail("m_axi_gmem address-space reference mismatch: {}".format(reference_values))
    interface_parameters = parameter_values(memory_interface)
    if interface_parameters.get("DATA_WIDTH") != ["128"]:
        fail("m_axi_gmem DATA_WIDTH bus parameter mismatch")
    if interface_parameters.get("ADDR_WIDTH") != ["64"]:
        fail("m_axi_gmem ADDR_WIDTH bus parameter mismatch")

    clock_parameters = parameter_values(interfaces["ap_clk"])
    associated_busifs = clock_parameters.get("ASSOCIATED_BUSIF", [])
    if len(associated_busifs) != 1:
        fail("ap_clk ASSOCIATED_BUSIF parameter is missing or duplicated")
    associated_set = set(associated_busifs[0].split(":"))
    if associated_set != {"s_axi_control", "m_axi_gmem"}:
        fail("ap_clk interface association mismatch: {}".format(associated_set))

    address_spaces_container = require_one(
        direct_children(component, "addressSpaces"), "addressSpaces element"
    )
    address_spaces = named_children(address_spaces_container, "addressSpace")
    if set(address_spaces) != {"m_axi_gmem"}:
        fail("component address-space set mismatch: {}".format(sorted(address_spaces)))
    address_space = address_spaces["m_axi_gmem"]
    address_range_text = child_text(address_space, "range", "m_axi_gmem range")
    if parse_scaled_integer(address_range_text) != (1 << 64):
        fail("m_axi_gmem IP-XACT address space is not 2^64 bytes")
    if int(child_text(address_space, "width", "m_axi_gmem width"), 0) != 128:
        fail("m_axi_gmem IP-XACT data width is not 128")

    memory_maps_container = require_one(
        direct_children(component, "memoryMaps"), "memoryMaps element"
    )
    memory_maps = named_children(memory_maps_container, "memoryMap")
    control_map = memory_maps.get("s_axi_control")
    if control_map is None:
        fail("component.xml has no s_axi_control memory map")
    address_blocks = direct_children(control_map, "addressBlock")
    address_block = require_one(address_blocks, "s_axi_control address block")

    registers = {}
    register_nodes = named_children(address_block, "register")
    for name, register in register_nodes.items():
        registers[name] = (
            int(child_text(register, "addressOffset", "{} offset".format(name)), 0),
            int(child_text(register, "size", "{} size".format(name)), 0),
            child_text(register, "access", "{} access".format(name)),
        )
    expected_registers = {
        "CONTROL": (0x00, 32, "read-write"),
        "LOOKUP_INDEX": (0x10, 32, "read-write"),
        "TABLE_BASE": (0x18, 64, "read-write"),
        "RESULT0": (0x20, 32, "read-only"),
        "RESULT1": (0x24, 32, "read-only"),
        "RESULT2": (0x28, 32, "read-only"),
        "RESULT3": (0x2C, 32, "read-only"),
    }
    if registers != expected_registers:
        fail("component register map mismatch: {}".format(registers))

    table_parameters = parameter_values(register_nodes["TABLE_BASE"])
    if table_parameters.get("ASSOCIATED_BUSIF") != ["m_axi_gmem"]:
        fail("TABLE_BASE register is not associated with m_axi_gmem")

    all_parameters = parameter_values(component)
    for parameter_name, expected_value in (
        ("C_M_AXI_GMEM_ADDR_WIDTH", "64"),
        ("C_M_AXI_GMEM_DATA_WIDTH", "128"),
    ):
        values = all_parameters.get(parameter_name, [])
        if len(values) < 2 or set(values) != {expected_value}:
            fail("{} component parameter mismatch: {}".format(parameter_name, values))

    models = direct_children(component, "model")
    model = require_one(models, "component model")
    ports_container = require_one(direct_children(model, "ports"), "component ports")
    physical_ports = named_children(ports_container, "port")
    for name in ("m_axi_gmem_awaddr", "m_axi_gmem_araddr"):
        port = physical_ports.get(name)
        if port is None:
            fail("component.xml is missing {}".format(name))
        wire = require_one(direct_children(port, "wire"), "{} wire".format(name))
        vector = require_one(direct_children(wire, "vector"), "{} vector".format(name))
        left = int(child_text(vector, "left", "{} left".format(name)), 0)
        right = int(child_text(vector, "right", "{} right".format(name)), 0)
        if (left, right) != (63, 0):
            fail("{} is not a 64-bit port".format(name))

    return address_range_text


def validate_wrapper_rtl(path):
    text = path.read_text(encoding="utf-8")
    required_patterns = {
        "64-bit AXI address parameter": (
            r"parameter\s+integer\s+C_M_AXI_GMEM_ADDR_WIDTH\s*=\s*64"
        ),
        "64-bit AXI AWADDR port": (
            r"\[C_M_AXI_GMEM_ADDR_WIDTH-1:0\]\s+m_axi_gmem_awaddr"
        ),
        "64-bit AXI ARADDR port": (
            r"\[C_M_AXI_GMEM_ADDR_WIDTH-1:0\]\s+m_axi_gmem_araddr"
        ),
        "64-bit table-base register": (
            r"\[C_M_AXI_GMEM_ADDR_WIDTH-1:0\]\s+table_base_reg"
        ),
    }
    for description, pattern in required_patterns.items():
        if re.search(pattern, text) is None:
            fail("wrapper RTL is missing {}".format(description))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--kernel-xml", type=Path, required=True)
    parser.add_argument("--component-xml", type=Path, required=True)
    parser.add_argument("--wrapper-rtl", type=Path, required=True)
    parser.add_argument("--kernel-name", required=True)
    args = parser.parse_args()

    for path in (args.kernel_xml, args.component_xml, args.wrapper_rtl):
        if not path.is_file() or path.stat().st_size == 0:
            fail("required validation input is missing or empty: {}".format(path))

    kernel_range = validate_kernel_xml(args.kernel_xml, args.kernel_name)
    component_range = validate_component_xml(args.component_xml)
    validate_wrapper_rtl(args.wrapper_rtl)

    print("A14_5_TARGET_XO_METADATA_VALIDATION_V2=PASS")
    print("KERNEL_XML_ARGUMENT_COUNT=6")
    print("COMPONENT_XML_REGISTER_COUNT=7")
    print("TABLE_BASE_ADDRESS_QUALIFIER=1")
    print("TABLE_BASE_PORT=m_axi_gmem")
    print("TABLE_BASE_OFFSET=0x18")
    print("TABLE_BASE_SIZE_BYTES=8")
    print("M_AXI_GMEM_DATA_WIDTH=128")
    print("M_AXI_GMEM_ADDR_WIDTH=64")
    print("M_AXI_GMEM_AWADDR_LEFT=63")
    print("M_AXI_GMEM_ARADDR_LEFT=63")
    print("IPXACT_ADDRESS_SPACE_BYTES=18446744073709551616")
    print("IPXACT_ADDRESS_SPACE_LITERAL={}".format(component_range))
    print("KERNEL_XML_PORT_RANGE={}".format(kernel_range))
    print("KERNEL_XML_PORT_RANGE_ROLE=DESCRIPTIVE_NOT_SOLE_WIDTH_PROOF")
    print("AXI_ADDRESS_WIDTH_EVIDENCE=RTL_COMPONENT_IPXACT_POINTER_CONSISTENT")


if __name__ == "__main__":
    main()
