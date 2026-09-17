#!/usr/bin/env python3
"""Contract tests for A18.2 local packaging/Host ABI. Not FPGA evidence."""
from __future__ import print_function

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "scripts"
sys.path.insert(0, str(SCRIPTS))

import parse_stage2n_a18_2_xclbin_map_v1 as parser  # noqa: E402
import validate_stage2n_a18_2_artifacts_v1 as v  # noqa: E402


def run_check():
    return subprocess.run(
        [sys.executable, str(SCRIPTS / "check/check_stage2n_a18_2_local_prep_v1.py"),
         "--repo", str(ROOT)],
        cwd=str(ROOT),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        universal_newlines=True,
    )


def mem_entry(tag, used=True):
    return {"m_tag": tag, "m_used": "1" if used else "0", "m_base_address": "0"}


def ip_entry(name, kind):
    return {"m_name": name, "m_type": kind}


def build_sections(indices=(7, 11, 19, 22)):
    memories = [mem_entry("HOST[0]", used=False)]
    while len(memories) <= max(indices):
        memories.append(mem_entry("SPARE[{}]".format(len(memories)), used=False))
    for arg, mem in enumerate(indices):
        memories[mem] = mem_entry("HBM[{}]".format(arg), used=True)
    connections = [
        {"arg_index": str(arg), "m_ip_layout_index": "0", "mem_data_index": str(mem)}
        for arg, mem in enumerate(indices)
    ]
    ips = [
        ip_entry("dlrm_f37x_rtl_kernel_stage2n_a18_v1:dlrm_a18_1", "IP_KERNEL"),
        ip_entry("shell_0", "IP_MEM"),
    ]
    return connections, memories, ips


class HostPrepTests(unittest.TestCase):
    def test_map_uses_metadata_indices_not_zero_through_three(self):
        connections, memories, ips = build_sections((7, 11, 19, 22))
        text, indices = parser.build_map_text(
            connections, memories, ips,
            "00000000-0000-0000-0000-000000000000")
        self.assertEqual(indices, [7, 11, 19, 22])
        self.assertIn("A18_2_MEM_MAP_V1", text)
        self.assertIn("ARG0_MEM_INDEX=7", text)
        self.assertIn("ARG3_TAG=HBM[3]", text)
        self.assertNotIn("ARG0_MEM_INDEX=0\n", text + "\n")
        self.assertIn("dlrm_a18_1", text)
        self.assertNotIn("dlrm_a17_1", text)

    def test_map_rejects_a17_cu(self):
        connections, memories, ips = build_sections((7, 11, 19, 22))
        ips[0]["m_name"] = "dlrm_f37x_rtl_kernel_stage2n_a17_v1:dlrm_a17_1"
        with self.assertRaises(Exception):
            parser.build_map_text(
                connections, memories, ips,
                "00000000-0000-0000-0000-000000000000")

    def test_cfg_is_four_bank_a18(self):
        v.config_check(ROOT / v.CONFIG)
        with tempfile.TemporaryDirectory() as name:
            p = Path(name) / "bad.cfg"
            p.write_text((ROOT / v.CONFIG).read_text(encoding="utf-8").replace(
                "HBM[3]", "HBM[0]"))
            with self.assertRaises(v.ValidationError):
                v.config_check(p)

    def test_build_requires_explicit_switch(self):
        runner = SCRIPTS / "run_stage2n_a18_2_build_v1.py"
        with tempfile.TemporaryDirectory() as name:
            out = Path(name) / "not_created"
            result = subprocess.run(
                [sys.executable, str(runner), "xo", "--output", str(out)],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(b"--confirm-build", result.stderr)
            self.assertFalse(out.exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
