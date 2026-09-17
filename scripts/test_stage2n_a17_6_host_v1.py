#!/usr/bin/env python3
"""Contract tests for A17.6 four-BO Host preparation. Not FPGA evidence."""
from __future__ import print_function

import hashlib
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "scripts"
sys.path.insert(0, str(SCRIPTS))

import parse_stage2n_a17_6_xclbin_map_v1 as parser  # noqa: E402


def run_check():
    return subprocess.run(
        [sys.executable, str(SCRIPTS / "check/check_stage2n_a17_6_host_prep_v1.py"),
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
        ip_entry("dlrm_f37x_rtl_kernel_stage2n_a17_v1:dlrm_a17_1", "IP_KERNEL"),
        ip_entry("shell_0", "IP_MEM"),
    ]
    return connections, memories, ips


class HostPrepTests(unittest.TestCase):
    def test_local_checker_pass(self):
        result = run_check()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("A17_6_HOST_PREP_CHECK=PASS", result.stdout)
        self.assertIn("A17_6_BOARD=NOT_RUN", result.stdout)
        self.assertIn("XSIM_RESULT_36_NOT_USED=1", result.stdout)

    def test_map_uses_metadata_indices_not_zero_through_three(self):
        connections, memories, ips = build_sections((7, 11, 19, 22))
        text, indices = parser.build_map_text(
            connections, memories, ips,
            "622c839f-55f4-47c1-92e9-95ee5595ffa4")
        self.assertEqual(indices, [7, 11, 19, 22])
        self.assertIn("ARG0_MEM_INDEX=7", text)
        self.assertIn("ARG3_TAG=HBM[3]", text)
        self.assertNotIn("ARG0_MEM_INDEX=0\n", text + "\n")

    def test_map_rejects_duplicate_bank(self):
        connections, memories, ips = build_sections((7, 11, 19, 22))
        connections[3]["mem_data_index"] = "7"
        memories[7] = mem_entry("HBM[0]", used=True)
        with self.assertRaises(Exception):
            parser.build_map_text(
                connections, memories, ips,
                "622c839f-55f4-47c1-92e9-95ee5595ffa4")

    def test_map_rejects_wrong_tag(self):
        connections, memories, ips = build_sections((7, 11, 19, 22))
        memories[11] = mem_entry("HBM[0]", used=True)
        with self.assertRaises(Exception):
            parser.build_map_text(
                connections, memories, ips,
                "622c839f-55f4-47c1-92e9-95ee5595ffa4")

    def test_parser_cli_roundtrip(self):
        connections, memories, ips = build_sections((12, 13, 14, 15))
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            conn = tmp_path / "connectivity.json"
            mem = tmp_path / "mem_topology.json"
            ip = tmp_path / "ip_layout.json"
            out = tmp_path / "map.txt"
            conn.write_text(json.dumps({
                "connectivity": {
                    "m_count": "4",
                    "m_connection": connections,
                }
            }), encoding="utf-8")
            mem.write_text(json.dumps({
                "mem_topology": {
                    "m_count": str(len(memories)),
                    "m_mem_data": memories,
                }
            }), encoding="utf-8")
            ip.write_text(json.dumps({
                "ip_layout": {
                    "m_count": str(len(ips)),
                    "m_ip_data": ips,
                }
            }), encoding="utf-8")
            result = subprocess.run(
                [sys.executable, str(SCRIPTS / "parse_stage2n_a17_6_xclbin_map_v1.py"),
                 "--connectivity", str(conn),
                 "--mem-topology", str(mem),
                 "--ip-layout", str(ip),
                 "--uuid", "622c839f-55f4-47c1-92e9-95ee5595ffa4",
                 "--output", str(out)],
                cwd=str(SCRIPTS),
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                universal_newlines=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            text = out.read_text(encoding="utf-8")
            self.assertIn("ARG0_MEM_INDEX=12", text)
            self.assertIn("MEMORY_INDICES_BY_ARGUMENT=12,13,14,15", text)

    def test_arg0_tag_parse_regression_accepts_all_four_tags(self):
        sample = "\n".join([
            "A17_6_MEM_MAP_V1",
            "UUID=622c839f-55f4-47c1-92e9-95ee5595ffa4",
            "KERNEL=dlrm_f37x_rtl_kernel_stage2n_a17_v1",
            "CU=dlrm_a17_1",
            "IP_NAME=dlrm_f37x_rtl_kernel_stage2n_a17_v1:dlrm_a17_1",
            "ARG0_MEM_INDEX=0",
            "ARG0_TAG=HBM[0]",
            "ARG1_MEM_INDEX=1",
            "ARG1_TAG=HBM[1]",
            "ARG2_MEM_INDEX=2",
            "ARG2_TAG=HBM[2]",
            "ARG3_MEM_INDEX=3",
            "ARG3_TAG=HBM[3]",
            "MEMORY_INDICES_BY_ARGUMENT=0,1,2,3",
            "",
        ])
        parsed = parser.parse_host_mem_map_text(sample, min_key_size=8)
        self.assertEqual(parsed["tag"], ["HBM[0]", "HBM[1]", "HBM[2]", "HBM[3]"])
        with self.assertRaisesRegex(ValueError, "memory map missing argument 0"):
            parser.parse_host_mem_map_text(sample, min_key_size=14)
        archived = ROOT / (
            "docs/evidence/stage2n_a17_6/function_pass_v1/"
            "20260910_102244/a17_6_mem_map.txt")
        if archived.is_file():
            archived_text = archived.read_text(encoding="utf-8")
            archived_parsed = parser.parse_host_mem_map_text(
                archived_text, min_key_size=8)
            self.assertEqual(
                archived_parsed["tag"],
                ["HBM[0]", "HBM[1]", "HBM[2]", "HBM[3]"])
            with self.assertRaisesRegex(
                    ValueError, "memory map missing argument 0"):
                parser.parse_host_mem_map_text(
                    archived_text, min_key_size=14)

    def test_host_elf_identity_rejects_stale_status_with_replaced_elf(self):
        helper = SCRIPTS / "check/check_stage2n_a17_6_host_elf_identity_v1.py"
        pre_fix = (
            "520d78efe3a4ba81a8cd3a66ee48042d39a14a0a3e4fb390e567bd7afb3bf5cd")
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            binary = tmp_path / "stage2n_a17_6_four_bo_host_v1"
            source = tmp_path / "host.cpp"
            status = tmp_path / "host_build_status.txt"
            binary.write_bytes(b"replacement-elf-bytes-not-pre-fix")
            source.write_text("int main() { return 0; }\n", encoding="utf-8")
            source_sha = hashlib.sha256(source.read_bytes()).hexdigest()
            elf_sha = hashlib.sha256(binary.read_bytes()).hexdigest()
            status.write_text(
                "A17_6_HOST_XRT_BUILD=PASS\n"
                "BINARY_SHA256={}\n"
                "SOURCE_SHA256={}\n".format(pre_fix, source_sha),
                encoding="utf-8")
            rejected = subprocess.run(
                [sys.executable, str(helper),
                 "--expected-elf-sha256", pre_fix,
                 "--binary", str(binary),
                 "--status", str(status),
                 "--source", str(source)],
                cwd=str(ROOT),
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                universal_newlines=True,
            )
            self.assertNotEqual(rejected.returncode, 0, rejected.stdout)
            self.assertIn("A17_6_HOST_ELF_IDENTITY=FAIL", rejected.stderr)
            status.write_text(
                "A17_6_HOST_XRT_BUILD=PASS\n"
                "BINARY_SHA256={}\n"
                "SOURCE_SHA256={}\n".format(elf_sha, source_sha),
                encoding="utf-8")
            accepted = subprocess.run(
                [sys.executable, str(helper),
                 "--expected-elf-sha256", elf_sha,
                 "--expected-source-sha256", source_sha,
                 "--binary", str(binary),
                 "--status", str(status),
                 "--source", str(source)],
                cwd=str(ROOT),
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                universal_newlines=True,
            )
            self.assertEqual(accepted.returncode, 0, accepted.stderr)
            self.assertIn("A17_6_HOST_ELF_IDENTITY=PASS", accepted.stdout)
            self.assertIn("HOST_EXECUTE_SHA256=" + elf_sha, accepted.stdout)
            self.assertIn("HOST_RUNTIME_PROCESS_HASH=NOT_CLAIMED", accepted.stdout)

    def test_host_parses_short_arg_tag_keys(self):
        host = (ROOT / "host/stage2n_a17_6_four_bo_host_v1.cpp").read_text(
            encoding="utf-8")
        self.assertEqual(len("ARG0_TAG"), 8)
        self.assertEqual(len("ARG0_MEM_INDEX"), 14)
        self.assertNotIn(
            'key.size() >= 14 && key.compare(0, 3, "ARG")', host)
        self.assertIn('key.size() >= 8 && key.compare(0, 3, "ARG")', host)
        sample = "\n".join([
            "A17_6_MEM_MAP_V1",
            "UUID=622c839f-55f4-47c1-92e9-95ee5595ffa4",
            "ARG0_MEM_INDEX=0",
            "ARG0_TAG=HBM[0]",
            "ARG1_MEM_INDEX=1",
            "ARG1_TAG=HBM[1]",
            "ARG2_MEM_INDEX=2",
            "ARG2_TAG=HBM[2]",
            "ARG3_MEM_INDEX=3",
            "ARG3_TAG=HBM[3]",
            "",
        ])
        seen_index = [False] * 4
        seen_tag = [False] * 4
        for line in sample.splitlines()[1:]:
            if "=" not in line:
                continue
            key, _value = line.split("=", 1)
            if (len(key) >= 8 and key.startswith("ARG") and
                    key[3] in "0123"):
                arg = int(key[3])
                if "_MEM_INDEX" in key:
                    seen_index[arg] = True
                elif "_TAG" in key:
                    seen_tag[arg] = True
        self.assertTrue(all(seen_index))
        self.assertTrue(all(seen_tag))

    def test_host_does_not_copy_a16_single_bank_assumption(self):
        host = (ROOT / "host/stage2n_a17_6_four_bo_host_v1.cpp").read_text(encoding="utf-8")
        self.assertNotIn("kExpectedMemIndex = 0", host)
        self.assertIn("load_mem_map", host)
        self.assertIn("FourBo", host)
        self.assertIn("load_restored_case", host)
        self.assertNotIn("load_and_sync_all", host)
        self.assertEqual(host.count("XCL_BO_SYNC_BO_TO_DEVICE"), 1)
        self.assertIn("independently", host)
        a16 = (ROOT / "host/stage2n_a16_2_physical_latency_v1.cpp").read_text(encoding="utf-8")
        self.assertIn("kExpectedMemIndex = 0", a16)

    def test_methodology_diff_self_check(self):
        result = subprocess.run(
            [sys.executable, str(SCRIPTS / "diff_stage2n_a17_6_methodology_v1.py"),
             "--self-test"],
            cwd=str(ROOT),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            universal_newlines=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("A17_6_METHODOLOGY_DIFF_SELF_TEST=PASS", result.stdout)

    def test_sensitivity_tables_change_only_owned_row(self):
        result = run_check()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("A17_6_PER_BO_CASE_LAYOUT=PASS", result.stdout)


if __name__ == "__main__":
    unittest.main()
