#!/usr/bin/env python3
"""Recover A17 sources for A18 materialization. Does not modify A17 originals."""
from __future__ import print_function

import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "build" / "stage2n_a18_recover_v1"
OUT.mkdir(parents=True, exist_ok=True)

A17_PATHS = [
    "rtl/hbm/dlrm_hbm_embedding_lookup_stage2n_a14_v2.sv",
    "rtl/hbm/dlrm_hbm_parallel_lookup_stage2n_a17_v1.sv",
    "rtl/pipeline/dlrm_hbm_pipeline_integration_stage2n_a17_v1.sv",
    "rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a17_v1.sv",
    "tb/tb_dlrm_f37x_rtl_kernel_stage2n_a17_v1.sv",
    "scripts/run_stage2n_a17_2_public_kernel_xsim_v1.ps1",
    "scripts/run_stage2n_a17_2_public_kernel_xsim_v1.tcl",
]


def try_open(rel):
    p = ROOT / rel
    try:
        data = p.read_bytes()
        return "fs", data
    except Exception as e:
        return "fs_fail:%s" % e, None


def try_git(rel):
    try:
        data = subprocess.check_output(
            ["git", "show", "HEAD:%s" % rel.replace("\\", "/")],
            cwd=str(ROOT),
            stderr=subprocess.STDOUT,
        )
        return "git", data
    except Exception as e:
        return "git_fail:%s" % e, None


def main():
    log = []
    for rel in A17_PATHS:
        src, data = try_open(rel)
        if data is None:
            src2, data = try_git(rel)
            src = src + ";" + src2
        dest = OUT / Path(rel).name
        if data is not None:
            dest.write_bytes(data)
            log.append("%s OK via %s bytes=%d -> %s" % (rel, src, len(data), dest))
        else:
            log.append("%s FAIL %s" % (rel, src))

    jsonl = Path(
        r"C:\Users\管鹏飞\.cursor\projects\d-FpgaWork-f37x-dlrm-rtl\agent-transcripts"
        r"\473812d5-bb8a-4c9d-bd0a-cbfc8ccb78fd\473812d5-bb8a-4c9d-bd0a-cbfc8ccb78fd.jsonl"
    )
    if jsonl.exists():
        n_write = 0
        with jsonl.open("r", encoding="utf-8", errors="replace") as f:
            for n, line in enumerate(f, 1):
                try:
                    obj = json.loads(line)
                except Exception:
                    continue
                content = obj.get("message", {}).get("content")
                if not isinstance(content, list):
                    continue
                for i, c in enumerate(content):
                    if not isinstance(c, dict):
                        continue
                    name = c.get("name")
                    inp = c.get("input") or {}
                    path = str(inp.get("path", ""))
                    if name == "Write" and path.endswith(
                        "tb_dlrm_f37x_rtl_kernel_stage2n_a17_v1.sv"
                    ):
                        body = inp.get("contents", "")
                        dest = OUT / ("tb_a17_from_jsonl_line%d.sv" % n)
                        dest.write_text(body, encoding="utf-8")
                        log.append("jsonl Write TB line %d bytes=%d" % (n, len(body)))
                        n_write += 1
                    if name == "Write" and "run_stage2n_a17_2_public_kernel_xsim" in path:
                        body = inp.get("contents", "")
                        dest = OUT / (
                            "script_from_jsonl_line%d_%s" % (n, Path(path).name)
                        )
                        dest.write_text(body, encoding="utf-8")
                        log.append("jsonl Write script line %d %s bytes=%d" % (n, path, len(body)))
                    if name == "StrReplace" and path.replace("\\", "/").endswith(
                        "rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a17_v1.sv"
                    ):
                        dest = OUT / ("kernel_strreplace_line%d_%d.json" % (n, i))
                        dest.write_text(
                            json.dumps(
                                {
                                    "old": inp.get("old_string", ""),
                                    "new": inp.get("new_string", ""),
                                },
                                ensure_ascii=False,
                                indent=2,
                            ),
                            encoding="utf-8",
                        )
                        log.append(
                            "jsonl kernel StrReplace line %d old=%d new=%d"
                            % (
                                n,
                                len(inp.get("old_string", "")),
                                len(inp.get("new_string", "")),
                            )
                        )
        log.append("jsonl writes scanned")
    else:
        log.append("jsonl missing")

    (OUT / "recover_log.txt").write_text("\n".join(log) + "\n", encoding="utf-8")
    print("\n".join(log))
    return 0


if __name__ == "__main__":
    sys.exit(main())
