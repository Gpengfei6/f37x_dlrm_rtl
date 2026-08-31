#!/usr/bin/env python3
"""Fail-closed Stage 2N-A16.2 XO/source metadata validator.

The accepted A16.1 kernel uses a user-managed AXI4-Lite register space. Only
TABLE_BASE is an XRT kernel argument; the complete A13/A15/A16 ABI remains
visible as raw register offsets in the accepted wrapper RTL.
"""

from __future__ import print_function

import argparse
import re
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path


EXPECTED_KERNEL = "dlrm_f37x_rtl_kernel_stage2n_a16_v1"
EXPECTED_PART = "xcvu37p-fsvh2892-2L-e"
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
STALE_ARGUMENTS = ("LOOKUP_INDEX", "RESULT0", "RESULT1", "RESULT2", "RESULT3")


class ValidationError(Exception):
    pass


def require(condition, message):
    if not condition:
        raise ValidationError(message)


def local_name(tag):
    return tag.rsplit("}", 1)[-1]


def direct_children(node, name):
    return [child for child in node if local_name(child.tag) == name]


def require_one(nodes, description):
    require(len(nodes) == 1, "expected one {}, found {}".format(description, len(nodes)))
    return nodes[0]


def child_text(node, name, description):
    child = require_one(direct_children(node, name), description)
    return (child.text or "").strip()


def named_children(container, kind):
    result = {}
    for child in direct_children(container, kind):
        name = child_text(child, "name", "{} name".format(kind))
        require(name and name not in result, "empty or duplicate {} name".format(kind))
        result[name] = child
    return result


def parameter_values(node):
    values = {}
    for candidate in node.iter():
        if local_name(candidate.tag) not in ("parameter", "modelParameter"):
            continue
        names = direct_children(candidate, "name")
        value_nodes = direct_children(candidate, "value")
        if len(names) == 1 and len(value_nodes) == 1:
            name = (names[0].text or "").strip()
            value = (value_nodes[0].text or "").strip()
            values.setdefault(name, []).append(value)
    return values


def parse_scaled_integer(value):
    match = re.fullmatch(r"([0-9]+)([KMGT]?)", value.strip(), re.IGNORECASE)
    require(match is not None, "unsupported IP-XACT integer {}".format(value))
    shifts = {"": 0, "K": 10, "M": 20, "G": 30, "T": 40}
    return int(match.group(1)) << shifts[match.group(2).upper()]


def validate_kernel_xml(path, expected_kernel):
    root = ET.parse(str(path)).getroot()
    kernel = require_one(
        [node for node in root.iter() if local_name(node.tag) == "kernel"],
        "kernel.xml kernel element",
    )
    require(kernel.get("name") == expected_kernel, "kernel name mismatch")
    require(kernel.get("hwControlProtocol") == "user_managed", "control protocol mismatch")

    ports_node = require_one(direct_children(kernel, "ports"), "ports element")
    ports = {}
    for port in direct_children(ports_node, "port"):
        name = port.get("name")
        require(name and name not in ports, "unnamed or duplicate kernel port")
        ports[name] = port
    require(set(ports) == {"s_axi_control", "m_axi_gmem"}, "kernel port set mismatch")
    require(ports["s_axi_control"].get("mode") == "slave", "control port is not slave")
    require(ports["s_axi_control"].get("dataWidth") == "32", "control width mismatch")
    require(ports["m_axi_gmem"].get("mode") == "master", "memory port is not master")
    require(ports["m_axi_gmem"].get("dataWidth") == "128", "memory data width mismatch")
    range_text = ports["m_axi_gmem"].get("range", "")
    try:
        range_value = int(range_text, 0)
    except ValueError:
        raise ValidationError("invalid m_axi_gmem range {}".format(range_text))
    require(range_value in (0xFFFFFFFF, 0xFFFFFFFFFFFFFFFF), "unexpected m_axi_gmem range")
    master_ports = [p for p in ports.values() if p.get("mode") == "master"]
    require(len(master_ports) == 1, "kernel metadata must contain exactly one master port")

    args_node = require_one(direct_children(kernel, "args"), "args element")
    args = direct_children(args_node, "arg")
    require(len(args) == 1, "kernel metadata must contain exactly one argument")
    table_base = args[0]
    require(table_base.get("name") == "TABLE_BASE", "only TABLE_BASE may be a kernel argument")
    require(int(table_base.get("id", "-1"), 0) == 0, "TABLE_BASE ID mismatch")
    require(int(table_base.get("offset", "-1"), 0) == 0x304, "TABLE_BASE offset mismatch")
    require(int(table_base.get("size", "-1"), 0) == 8, "TABLE_BASE size mismatch")
    require(int(table_base.get("hostSize", "-1"), 0) == 8, "TABLE_BASE host size mismatch")
    require(int(table_base.get("hostOffset", "0"), 0) == 0, "TABLE_BASE host offset mismatch")
    require(table_base.get("addressQualifier") == "1", "TABLE_BASE is not a pointer")
    require(table_base.get("port") == "m_axi_gmem", "TABLE_BASE port mismatch")
    require(table_base.get("type") == "void*", "TABLE_BASE type mismatch")
    xml_text = path.read_text(encoding="utf-8", errors="replace")
    for stale in STALE_ARGUMENTS:
        require(
            re.search(r'<arg\b[^>]*\bname="{}"'.format(re.escape(stale)), xml_text) is None,
            "obsolete A14 argument present: {}".format(stale),
        )


def validate_component_xml(path):
    component = ET.parse(str(path)).getroot()
    bus_container = require_one(direct_children(component, "busInterfaces"), "busInterfaces")
    interfaces = named_children(bus_container, "busInterface")
    require(
        set(interfaces) == {"m_axi_gmem", "s_axi_control", "ap_clk", "ap_rst_n"},
        "component bus-interface set mismatch: {}".format(sorted(interfaces)),
    )
    master = require_one(direct_children(interfaces["m_axi_gmem"], "master"), "m_axi master")
    require(not direct_children(interfaces["m_axi_gmem"], "slave"), "m_axi is also marked slave")
    address_ref = require_one(direct_children(master, "addressSpaceRef"), "address-space reference")
    ref_values = [value for key, value in address_ref.attrib.items() if local_name(key) == "addressSpaceRef"]
    require(ref_values == ["m_axi_gmem"], "m_axi address-space reference mismatch")
    params = parameter_values(interfaces["m_axi_gmem"])
    require(params.get("DATA_WIDTH") == ["128"], "m_axi DATA_WIDTH mismatch")
    require(params.get("ADDR_WIDTH") == ["64"], "m_axi ADDR_WIDTH mismatch")

    spaces_node = require_one(direct_children(component, "addressSpaces"), "addressSpaces")
    spaces = named_children(spaces_node, "addressSpace")
    require(set(spaces) == {"m_axi_gmem"}, "component address-space set mismatch")
    address_space = spaces["m_axi_gmem"]
    require(
        parse_scaled_integer(child_text(address_space, "range", "m_axi range")) == (1 << 64),
        "m_axi address space is not 2^64 bytes",
    )
    require(int(child_text(address_space, "width", "m_axi width"), 0) == 128, "m_axi width mismatch")

    maps_node = require_one(direct_children(component, "memoryMaps"), "memoryMaps")
    maps = named_children(maps_node, "memoryMap")
    require("s_axi_control" in maps, "s_axi_control memory map missing")
    block = require_one(direct_children(maps["s_axi_control"], "addressBlock"), "control address block")
    require(parse_scaled_integer(child_text(block, "range", "control range")) >= 0x314, "control map range too small")
    registers = named_children(block, "register")
    require(set(registers) == {"TABLE_BASE"}, "component argument-register set mismatch")
    reg = registers["TABLE_BASE"]
    require(int(child_text(reg, "addressOffset", "TABLE_BASE offset"), 0) == 0x304, "component TABLE_BASE offset mismatch")
    require(int(child_text(reg, "size", "TABLE_BASE size"), 0) == 64, "component TABLE_BASE size mismatch")
    require(child_text(reg, "access", "TABLE_BASE access") == "read-write", "component TABLE_BASE access mismatch")
    require(parameter_values(reg).get("ASSOCIATED_BUSIF") == ["m_axi_gmem"], "TABLE_BASE bus association mismatch")

    model = require_one(direct_children(component, "model"), "component model")
    model_ports = named_children(require_one(direct_children(model, "ports"), "model ports"), "port")
    expected_vectors = {
        "m_axi_gmem_awaddr": (63, 0),
        "m_axi_gmem_araddr": (63, 0),
        "m_axi_gmem_wdata": (127, 0),
        "m_axi_gmem_rdata": (127, 0),
    }
    for name, expected in expected_vectors.items():
        require(name in model_ports, "component port missing: {}".format(name))
        wire = require_one(direct_children(model_ports[name], "wire"), "{} wire".format(name))
        vector = require_one(direct_children(wire, "vector"), "{} vector".format(name))
        actual = (
            int(child_text(vector, "left", "{} left".format(name)), 0),
            int(child_text(vector, "right", "{} right".format(name)), 0),
        )
        require(actual == expected, "{} vector mismatch: {}".format(name, actual))


def validate_wrapper_rtl(path, expected_kernel):
    text = path.read_text(encoding="utf-8", errors="replace")
    module_start = text.find("module {}".format(expected_kernel))
    require(module_start >= 0, "wrapper top module is missing")
    module_end = text.find(");", module_start)
    require(module_end >= 0, "wrapper top header is incomplete")
    header = text[module_start:module_end + 2]
    required_patterns = {
        "module": r"module\s+{}\s*#\s*\(".format(re.escape(expected_kernel)),
        "64-bit address parameter": r"C_M_AXI_GMEM_ADDR_WIDTH\s*=\s*64",
        "128-bit data parameter": r"C_M_AXI_GMEM_DATA_WIDTH\s*=\s*128",
        "one-bit ID parameter": r"C_M_AXI_GMEM_ID_WIDTH\s*=\s*1",
        "write address disabled": r"assign\s+m_axi_gmem_awvalid\s*=\s*1'b0\s*;",
        "write data disabled": r"assign\s+m_axi_gmem_wvalid\s*=\s*1'b0\s*;",
        "write response disabled": r"assign\s+m_axi_gmem_bready\s*=\s*1'b0\s*;",
    }
    for description, pattern in required_patterns.items():
        require(re.search(pattern, text) is not None, "wrapper missing {}".format(description))
    for name, value in {
        "ADDR_PIPE_BOTTOM_CYCLES": "218",
        "ADDR_PIPE_INTERACTION_CYCLES": "21C",
        "ADDR_PIPE_TOP_CYCLES": "220",
        "ADDR_PIPE_TOTAL_CYCLES": "224",
        "ADDR_A15_CONTROL_STATUS": "300",
        "ADDR_A15_TABLE_BASE_LO": "304",
        "ADDR_A15_TABLE_BASE_HI": "308",
        "ADDR_A16_HBM_LOOKUP_CYCLES": "30C",
        "ADDR_A16_FPGA_END_TO_END_CYCLES": "310",
    }.items():
        pattern = r"{}\s*=\s*12'h{}\s*;".format(name, value)
        require(re.search(pattern, text) is not None, "wrapper ABI mismatch for {}".format(name))
    a15_offsets = dict(re.findall(r"(ADDR_A15_[A-Z0-9_]+)\s*=\s*12'h([0-9A-Fa-f]+)\s*;", text))
    require(
        a15_offsets == {
            "ADDR_A15_CONTROL_STATUS": "300",
            "ADDR_A15_TABLE_BASE_LO": "304",
            "ADDR_A15_TABLE_BASE_HI": "308",
        },
        "unexpected public A15 register constants: {}".format(a15_offsets),
    )
    a16_offsets = dict(re.findall(r"(ADDR_A16_[A-Z0-9_]+)\s*=\s*12'h([0-9A-Fa-f]+)\s*;", text))
    require(
        a16_offsets == {
            "ADDR_A16_HBM_LOOKUP_CYCLES": "30C",
            "ADDR_A16_FPGA_END_TO_END_CYCLES": "310",
        },
        "unexpected public A16 register constants: {}".format(a16_offsets),
    )
    public_axi = set()
    for name in re.findall(r"\b(m_axi_[A-Za-z0-9_]+)\b", header):
        match = re.match(r"m_axi_(.+)_(?:awid|awaddr|awlen|awsize|awburst|awlock|awcache|awprot|awqos|awvalid|awready|wdata|wstrb|wlast|wvalid|wready|bid|bresp|bvalid|bready|arid|araddr|arlen|arsize|arburst|arlock|arcache|arprot|arqos|arvalid|arready|rid|rdata|rresp|rlast|rvalid|rready)$", name)
        if match:
            public_axi.add(match.group(1))
    require(public_axi == {"gmem"}, "wrapper must expose exactly one m_axi master")


def validate_package_tcl(path, expected_kernel, expected_part):
    text = path.read_text(encoding="utf-8", errors="replace")
    require('set top_name "{}"'.format(expected_kernel) in text, "package top mismatch")
    require('set target_part_name "{}"'.format(expected_part) in text, "package target part mismatch")
    require("-ctrl_protocol user_managed" in text, "package control protocol missing")
    require("set_required_bus_parameter $m_axi_gmem DATA_WIDTH 128" in text, "package data width missing")
    require("set_required_bus_parameter $m_axi_gmem ADDR_WIDTH 64" in text, "package address width missing")
    require("$address_block TABLE_BASE 0x304 64 read-write" in text, "package TABLE_BASE spec mismatch")
    found_sources = re.findall(r"\[source_path\s+\$root_dir\s+([^\]\s]+)\]", text)
    require(found_sources == EXPECTED_SOURCES, "package RTL source list mismatch")
    for stale in STALE_ARGUMENTS:
        register_pattern = r"\$address_block\s+{}\s+0x".format(re.escape(stale))
        require(re.search(register_pattern, text) is None, "package creates stale argument {}".format(stale))


def validate_all(kernel_xml, component_xml, wrapper_rtl, package_tcl, kernel, part):
    validate_kernel_xml(kernel_xml, kernel)
    validate_component_xml(component_xml)
    validate_wrapper_rtl(wrapper_rtl, kernel)
    validate_package_tcl(package_tcl, kernel, part)


def good_kernel_xml():
    return """<root><kernel name=\"{0}\" hwControlProtocol=\"user_managed\"><ports>
<port name=\"s_axi_control\" mode=\"slave\" dataWidth=\"32\"/>
<port name=\"m_axi_gmem\" mode=\"master\" dataWidth=\"128\" range=\"0xFFFFFFFF\"/>
</ports><args><arg name=\"TABLE_BASE\" id=\"0\" offset=\"0x304\" size=\"0x8\" hostSize=\"0x8\" hostOffset=\"0x0\" addressQualifier=\"1\" port=\"m_axi_gmem\" type=\"void*\"/></args></kernel></root>""".format(EXPECTED_KERNEL)


def param(name, value):
    return "<parameter><name>{}</name><value>{}</value></parameter>".format(name, value)


def vector_port(name, left):
    return "<port><name>{}</name><wire><vector><left>{}</left><right>0</right></vector></wire></port>".format(name, left)


def good_component_xml():
    ports = "".join([
        vector_port("m_axi_gmem_awaddr", 63), vector_port("m_axi_gmem_araddr", 63),
        vector_port("m_axi_gmem_wdata", 127), vector_port("m_axi_gmem_rdata", 127),
        vector_port("m_axi_gmem_awid", 0), vector_port("m_axi_gmem_arid", 0),
    ])
    return """<component><busInterfaces>
<busInterface><name>m_axi_gmem</name><master><addressSpaceRef addressSpaceRef=\"m_axi_gmem\"/></master>{0}{1}</busInterface>
<busInterface><name>s_axi_control</name><slave/></busInterface>
<busInterface><name>ap_clk</name></busInterface><busInterface><name>ap_rst_n</name></busInterface>
</busInterfaces><addressSpaces><addressSpace><name>m_axi_gmem</name><range>18446744073709551616</range><width>128</width></addressSpace></addressSpaces>
<memoryMaps><memoryMap><name>s_axi_control</name><addressBlock><name>reg0</name><range>4096</range>
<register><name>TABLE_BASE</name><addressOffset>0x304</addressOffset><size>64</size><access>read-write</access>{2}</register>
</addressBlock></memoryMap></memoryMaps><model><ports>{3}</ports></model></component>""".format(
        param("DATA_WIDTH", "128"), param("ADDR_WIDTH", "64"),
        param("ASSOCIATED_BUSIF", "m_axi_gmem"), ports,
    )


def good_wrapper():
    return """module {0} #(parameter integer C_M_AXI_GMEM_ADDR_WIDTH = 64,
parameter integer C_M_AXI_GMEM_DATA_WIDTH = 128, parameter integer C_M_AXI_GMEM_ID_WIDTH = 1)(
output logic [C_M_AXI_GMEM_ADDR_WIDTH-1:0] m_axi_gmem_awaddr,
output logic [C_M_AXI_GMEM_DATA_WIDTH-1:0] m_axi_gmem_wdata,
output logic [C_M_AXI_GMEM_ADDR_WIDTH-1:0] m_axi_gmem_araddr);
localparam ADDR_PIPE_BOTTOM_CYCLES = 12'h218;
localparam ADDR_PIPE_INTERACTION_CYCLES = 12'h21C;
localparam ADDR_PIPE_TOP_CYCLES = 12'h220;
localparam ADDR_PIPE_TOTAL_CYCLES = 12'h224;
localparam ADDR_A15_CONTROL_STATUS = 12'h300;
localparam ADDR_A15_TABLE_BASE_LO = 12'h304;
localparam ADDR_A15_TABLE_BASE_HI = 12'h308;
localparam ADDR_A16_HBM_LOOKUP_CYCLES = 12'h30C;
localparam ADDR_A16_FPGA_END_TO_END_CYCLES = 12'h310;
assign m_axi_gmem_awvalid = 1'b0;
assign m_axi_gmem_wvalid = 1'b0;
assign m_axi_gmem_bready = 1'b0;
endmodule""".format(EXPECTED_KERNEL)


def good_package():
    source_lines = " \\\n+".join("    [source_path $root_dir {}]".format(item) for item in EXPECTED_SOURCES)
    return """set top_name \"{0}\"
set target_part_name \"{1}\"
set rtl_files [list \\
{2} \\
]
set_required_bus_parameter $m_axi_gmem DATA_WIDTH 128
set_required_bus_parameter $m_axi_gmem ADDR_WIDTH 64
set table_base_register [add_control_register \\
    $address_block TABLE_BASE 0x304 64 read-write description]
package_xo -ctrl_protocol user_managed
""".format(EXPECTED_KERNEL, EXPECTED_PART, source_lines)


def run_self_test():
    cases = [
        ("wrong_kernel", "kernel", lambda text: text.replace(EXPECTED_KERNEL, "wrong_kernel", 1)),
        ("second_master", "kernel", lambda text: text.replace("</ports>", '<port name="m_axi_extra" mode="master" dataWidth="128"/></ports>')),
        ("stale_lookup_index", "kernel", lambda text: text.replace("</args>", '<arg name="LOOKUP_INDEX"/></args>')),
        ("stale_result0", "kernel", lambda text: text.replace("</args>", '<arg name="RESULT0"/></args>')),
        ("wrong_data_width", "component", lambda text: text.replace("<value>128</value>", "<value>64</value>", 1)),
        ("wrong_address_width", "component", lambda text: text.replace("<value>64</value>", "<value>32</value>", 1)),
        ("wrong_table_base_offset", "kernel", lambda text: text.replace('offset="0x304"', 'offset="0x18"')),
        ("wrong_a16_counter_offset", "wrapper", lambda text: text.replace("12'h30C", "12'h314")),
        ("wrong_target_part", "package", lambda text: text.replace(EXPECTED_PART, "xc7a200tfbg484-2")),
    ]
    with tempfile.TemporaryDirectory(prefix="a16_2_xo_validator_") as temp_name:
        temp = Path(temp_name)
        paths = {
            "kernel": temp / "kernel.xml",
            "component": temp / "component.xml",
            "wrapper": temp / "wrapper.sv",
            "package": temp / "package.tcl",
        }
        originals = {
            "kernel": good_kernel_xml(),
            "component": good_component_xml(),
            "wrapper": good_wrapper(),
            "package": good_package(),
        }

        def write_all(overrides=None):
            overrides = overrides or {}
            for name, path in paths.items():
                path.write_text(overrides.get(name, originals[name]), encoding="utf-8")

        write_all()
        validate_all(paths["kernel"], paths["component"], paths["wrapper"], paths["package"], EXPECTED_KERNEL, EXPECTED_PART)
        print("XO_SELF_TEST_GOOD=PASS")
        for label, target, mutate in cases:
            write_all({target: mutate(originals[target])})
            try:
                validate_all(paths["kernel"], paths["component"], paths["wrapper"], paths["package"], EXPECTED_KERNEL, EXPECTED_PART)
            except ValidationError:
                print("XO_SELF_TEST_REJECT_{}=PASS".format(label.upper()))
            else:
                raise ValidationError("negative self-test was accepted: {}".format(label))
    print("A16_2_XO_VALIDATOR_SELF_TEST=PASS")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--kernel-xml", type=Path)
    parser.add_argument("--component-xml", type=Path)
    parser.add_argument("--wrapper-rtl", type=Path)
    parser.add_argument("--package-tcl", type=Path)
    parser.add_argument("--kernel-name", default=EXPECTED_KERNEL)
    parser.add_argument("--target-part", default=EXPECTED_PART)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    try:
        if args.self_test:
            run_self_test()
            return
        inputs = (args.kernel_xml, args.component_xml, args.wrapper_rtl, args.package_tcl)
        require(all(path is not None for path in inputs), "metadata paths are required without --self-test")
        for path in inputs:
            require(path.is_file() and path.stat().st_size > 0, "missing or empty input: {}".format(path))
        validate_all(*inputs, kernel=args.kernel_name, part=args.target_part)
    except (OSError, ValueError, ET.ParseError, ValidationError) as error:
        raise SystemExit("A16.2 XO validation failed: {}".format(error))
    print("A16_2_TARGET_XO_METADATA_VALIDATION=PASS")
    print("KERNEL={}".format(args.kernel_name))
    print("TARGET_PART={}".format(args.target_part))
    print("KERNEL_ARGUMENT_COUNT=1")
    print("TABLE_BASE_OFFSET=0x304")
    print("TABLE_BASE_SIZE_BYTES=8")
    print("TABLE_BASE_PORT=m_axi_gmem")
    print("M_AXI_GMEM_MASTER_COUNT=1")
    print("M_AXI_GMEM_DATA_WIDTH=128")
    print("M_AXI_GMEM_ADDR_WIDTH=64")
    print("A13_CYCLE_COUNTER_ABI=0x218,0x21C,0x220,0x224")
    print("A15_CONTROL_ABI=0x300,0x304,0x308")
    print("A16_LATENCY_COUNTER_ABI=0x30C,0x310")
    print("STALE_A14_ARGUMENTS=ABSENT")


if __name__ == "__main__":
    main()
