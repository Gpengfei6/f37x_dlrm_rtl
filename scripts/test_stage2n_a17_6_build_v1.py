#!/usr/bin/env python3
"""Contract regression tests; generated fixtures are not FPGA evidence."""
from __future__ import print_function
import copy
import json
import subprocess
import sys
import tempfile
import unittest
import zipfile
import xml.etree.ElementTree as ET
from pathlib import Path

import validate_stage2n_a16_2_xo_v1 as old
import validate_stage2n_a17_6_artifacts_v1 as v


def metadata():
    kernel = ET.fromstring(old.good_kernel_xml())
    node = kernel.find("kernel")
    node.set("name", v.KERNEL)
    ports, args = node.find("ports"), node.find("args")
    master, arg = ports.findall("port")[1], args.find("arg")
    ports.remove(master)
    args.remove(arg)
    component = ET.fromstring(old.good_component_xml())
    buses, spaces = component.find("busInterfaces"), component.find("addressSpaces")
    regs, physical = component.find("memoryMaps/memoryMap/addressBlock"), component.find("model/ports")
    bus, space, reg = buses.find("busInterface"), spaces.find("addressSpace"), regs.find("register")
    buses.remove(bus)
    spaces.remove(space)
    regs.remove(reg)
    originals = list(physical)
    for p in originals:
        physical.remove(p)
    for i, offset in enumerate(v.OFFSETS):
        p, a = copy.deepcopy(master), copy.deepcopy(arg)
        p.set("name", v.PORTS[i])
        for k, value in {"name": "TABLE_BASE{}".format(i), "id": str(i), "offset": hex(offset), "port": v.PORTS[i]}.items():
            a.set(k, value)
        ports.append(p)
        args.append(a)
        for container, original in ((buses, bus), (spaces, space), (regs, reg)):
            text = ET.tostring(original, encoding="unicode").replace("m_axi_gmem", v.PORTS[i]).replace("TABLE_BASE", "TABLE_BASE{}".format(i))
            text = text.replace("0x304", hex(offset))
            container.append(ET.fromstring(text))
        for original in originals:
            physical.append(ET.fromstring(ET.tostring(original, encoding="unicode").replace("m_axi_gmem", v.PORTS[i])))
    return ET.tostring(kernel), ET.tostring(component)


def mapping():
    # Bank tags deliberately do not equal memory indices; shell IP precedes CU.
    memories = [{"m_tag": tag, "m_used": "1"} for tag in ("DDR[0]", "HBM[2]", "HBM[0]", "HBM[3]", "HBM[1]")]
    ips = [{"m_type": "IP_MEM_HBM", "m_name": "shell"}, {"m_type": "IP_KERNEL", "m_name": v.KERNEL + ":" + v.CU}]
    connections = [{"arg_index": i, "mem_data_index": mem, "m_ip_layout_index": 1} for i, mem in enumerate((2, 4, 1, 3))]
    return connections, memories, ips


class Contracts(unittest.TestCase):
    def test_four_master_metadata(self):
        k, c = metadata()
        v.kernel_check(k)
        v.component_check(c)

    def test_reject_pointer_corruption(self):
        k, c = metadata()
        cases = [(v.kernel_check, k.replace(b'offset="0x318"', b'offset="0x30c"')),
                 (v.kernel_check, k.replace(b'id="3"', b'id="2"')),
                 (v.kernel_check, k.replace(b'port="m_axi_gmem3"', b'port="m_axi_gmem0"')),
                 (v.kernel_check, old.good_kernel_xml().encode()),
                 (v.component_check, c.replace(b'<value>64</value>', b'<value>32</value>', 1)),
                 (v.component_check, c.replace(b'<range>18446744073709551616</range>', b'<range>4294967296</range>', 1)),
                 (v.component_check, c.replace(b'<value>m_axi_gmem3</value>', b'<value>m_axi_gmem0</value>')),
                 (v.component_check, c.replace(b'<left>63</left>', b'<left>31</left>', 1))]
        for check, data in cases:
            with self.subTest(check=check.__name__, data=data[:60]):
                with self.assertRaises(v.ValidationError):
                    check(data)

    def test_mapping_by_tag_not_index(self):
        self.assertEqual(v.mapping_check(*mapping()), [2, 4, 1, 3])

    def test_reject_wrong_mapping(self):
        for mutation in ("bank", "arg", "shell", "unused", "cu", "extra_cu"):
            con, mem, ips = mapping()
            if mutation == "bank": con[3]["mem_data_index"] = 2
            if mutation == "arg": con[3]["arg_index"] = 0
            if mutation == "shell": con[0]["m_ip_layout_index"] = 0
            if mutation == "unused": mem[2]["m_used"] = "0"
            if mutation == "cu": ips[1]["m_name"] = "old:dlrm_a16_1"
            if mutation == "extra_cu": ips.append(dict(ips[1]))
            with self.subTest(mutation=mutation):
                with self.assertRaises(v.ValidationError):
                    v.mapping_check(con, mem, ips)

    def test_archive_metadata_must_match(self):
        k, c = metadata()
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            (root / "kernel.xml").write_bytes(k)
            (root / "component.xml").write_bytes(c)
            with zipfile.ZipFile(str(root / "test.xo"), "w") as z:
                z.writestr("kernel/kernel.xml", k)
                z.writestr("ip_repo/test/component.xml", c)
            v.xo_check(root / "test.xo", root / "kernel.xml", root / "component.xml")
            (root / "kernel.xml").write_bytes(k + b" ")
            with self.assertRaises(v.ValidationError):
                v.xo_check(root / "test.xo", root / "kernel.xml", root / "component.xml")

    def test_timing_gate(self):
        metrics = {"TARGET_PART": v.PART, "WNS_NS": "0.01", "TNS_NS": "0", "FAILING_ENDPOINTS": "0",
                   "DRC_ERROR_COUNT": "0", "METHODOLOGY_ERROR_COUNT": "0", "LATCH": "0",
                   "CLOCKS": "clk_out1_pfm_top_clkwiz_kernel_0:10.000"}
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            p = root / "post_route_metrics.txt"
            p.write_text("\n".join(k + "=" + val for k, val in metrics.items()))
            summary = root / "post_route_timing_summary.rpt"
            header = "WNS(ns) TNS(ns) WHS(ns) THS(ns) WPWS(ns) TPWS(ns)\n-----\n"
            good = "0.01 0 0 10 0.02 0 0 10 0.03 0 0 10\n"
            summary.write_text(header + good)
            (root / "post_route_check_timing.rpt").write_text("1. checking no_clock (0)\n4. checking unconstrained_internal_endpoints (0)\n")
            v.timing_check(p)
            for bad in (good.replace("0.02", "-0.02"), good.replace("0.03", "-0.03")):
                summary.write_text(header + bad)
                with self.assertRaises(v.ValidationError): v.timing_check(p)
            summary.write_text(header + good)
            p.write_text(p.read_text().replace("WNS_NS=0.01", "WNS_NS=NOT_PARSED"))
            with self.assertRaises((v.ValidationError, ValueError)): v.timing_check(p)

    def test_configuration(self):
        root = Path(__file__).resolve().parent.parent
        v.config_check(root / v.CONFIG)
        with tempfile.TemporaryDirectory() as name:
            p = Path(name) / "bad.cfg"
            p.write_text((root / v.CONFIG).read_text().replace("HBM[3]", "HBM[0]"))
            with self.assertRaises(v.ValidationError): v.config_check(p)

    def test_build_requires_explicit_switch(self):
        runner = Path(__file__).with_name("run_stage2n_a17_6_build_v1.py")
        with tempfile.TemporaryDirectory() as name:
            out = Path(name) / "not_created"
            result = subprocess.run([sys.executable, str(runner), "xo", "--output", str(out)],
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(b"--confirm-build", result.stderr)
            self.assertFalse(out.exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
