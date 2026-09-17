#!/usr/bin/env python3
"""Contract tests for A18.3 index-tuple Host source. Not FPGA evidence."""
from __future__ import print_function

import subprocess
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class A18_3HostTests(unittest.TestCase):
    def test_checker_pass(self):
        result = subprocess.run(
            [sys.executable,
             str(ROOT / "scripts/check/check_stage2n_a18_3_local_prep_v1.py")],
            cwd=str(ROOT),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            universal_newlines=True,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("A18_3_LOCAL_PREP_CHECK=PASS", result.stdout)
        self.assertIn("A18_3_HOST_CPP=PRESENT", result.stdout)
        self.assertIn("A18_3_THIS_CHECKER=SOURCE_ONLY", result.stdout)

    def test_a18_2_host_untouched_lock(self):
        text = (ROOT / "host/stage2n_a18_2_four_bo_host_v1.cpp").read_text(
            encoding="utf-8")
        self.assertIn(
            "non-default board compares are not authorized in this file", text)
        self.assertIn("-393, -392, -93, -689, -519", text)

    def test_a18_3_rejects_sensitivity_and_kernel_args(self):
        text = (ROOT / "host/stage2n_a18_3_index_tuple_host_v1.cpp").read_text(
            encoding="utf-8")
        self.assertNotIn("slot0_sensitivity", text)
        self.assertNotIn("load_restored_case", text)
        self.assertNotIn("xclSetKernelArg", text)
        self.assertIn("load_baseline_all", text)
        self.assertIn("-61", text)


if __name__ == "__main__":
    unittest.main(verbosity=2)
