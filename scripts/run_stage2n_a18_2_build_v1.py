#!/usr/bin/env python3
"""A18.2 source bundle / user-executed XO / link. No device or Host operations.

Target commands require an already initialized Vitis 2020.2 shell and explicit
--confirm-build. This process must not execute those subcommands on the target.
"""
from __future__ import print_function

import argparse
import json
import os
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

from validate_stage2n_a18_2_artifacts_v1 import (
    KERNEL, CU, PART, PLATFORM, PACKAGE, CONFIG, REPORT, MANIFEST,
    require, digest, source_check, xo_check, linked_check, timing_check,
)

ROOT = Path(__file__).resolve().parent.parent


def write_json(path, value):
    with path.open("w", encoding="utf-8", newline="\n") as stream:
        json.dump(value, stream, indent=2, sort_keys=True)
        stream.write("\n")


def run_command(command, log, cwd, env=None):
    with log.open("w", encoding="utf-8") as stream:
        stream.write("ARGV=" + json.dumps(command) + "\n")
        stream.flush()
        process = subprocess.Popen(command, cwd=str(cwd), env=env,
                                   stdout=stream, stderr=subprocess.STDOUT)
        code = process.wait()
    require(code == 0, "command failed (exit {}), inspect {}".format(code, log))


def require_tools(names):
    result = {}
    for name in names:
        result[name] = shutil.which(name)
        require(result[name] is not None, "missing tool {}; initialize Vitis 2020.2 first".format(name))
    return result


def xo_paths(directory):
    return (directory / "xo" / (KERNEL + ".xo"),
            directory / "xo/kernel.xml",
            directory / "xo/dlrm_f37x_stage2n_a18_ip_v1/component.xml")


def check_input_xo(directory):
    status = json.loads((directory / "status.json").read_text(encoding="utf-8"))
    require(status.get("phase") == "xo" and status.get("result") == "PASS", "input XO build not PASS")
    require(status.get("source_manifest_sha256") == digest(ROOT / MANIFEST), "XO came from a different source bundle")
    paths = xo_paths(directory)
    for path in paths:
        require(status["artifacts"].get(path.relative_to(directory).as_posix()) == digest(path), "input XO artifact changed")
    xo_check(*paths)
    return paths


def execute(args):
    manifest = source_check(ROOT)
    if args.phase == "check":
        print("A18_2_SOURCE_INTEGRITY=PASS")
        print("SOURCE_FILES={}".format(len(manifest["files"])))
        print("TARGET_XO=NOT_RUN\nTARGET_LINK=NOT_RUN\nBOARD=NOT_RUN")
        return
    output = args.output.resolve()
    require(not output.exists(), "refusing to overwrite " + str(output))
    if args.phase == "bundle":
        output.parent.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(str(output), "x", compression=zipfile.ZIP_DEFLATED) as archive:
            for relative in sorted(list(manifest["files"]) + [MANIFEST]):
                archive.write(str(ROOT / relative), relative)
        print("BUNDLE=" + str(output))
        print("SHA256=" + digest(output))
        return
    require(args.confirm_build, "target build requires explicit --confirm-build")
    names = ["vivado"] + (["v++", "xclbinutil"] if args.phase == "link" else [])
    tools = require_tools(names)
    if args.phase == "link":
        require(args.platform is not None and args.xo_run is not None, "link requires --platform and --xo-run")
        platform = args.platform.resolve()
        require(platform.is_file() and platform.name == PLATFORM + ".xpfm", "wrong/missing F37X platform")
        require(args.jobs > 0, "jobs must be positive")
        input_paths = check_input_xo(args.xo_run.resolve())
    output.mkdir(parents=True)
    status = {"phase": args.phase, "result": "RUNNING", "kernel": KERNEL,
              "part": PART, "source_manifest_sha256": digest(ROOT / MANIFEST),
              "physical_mapping": "NOT_RUN", "board": "NOT_RUN", "performance": "NOT_CLAIMED"}
    status_path = output / "status.json"
    write_json(status_path, status)
    try:
        run_command([tools["vivado"], "-version"], output / "vivado_version.log", output)
        require("2020.2" in (output / "vivado_version.log").read_text(encoding="utf-8", errors="replace"), "target Vivado must be 2020.2")
        env = os.environ.copy()
        if args.phase == "xo":
            env["A18_2_XO_DIR"] = str(output / "xo")
            run_command([tools["vivado"], "-mode", "batch", "-nolog", "-nojournal", "-source", str(ROOT / PACKAGE)],
                        output / "package.log", output, env)
            paths = xo_paths(output)
            xo_check(*paths)
            status["artifacts"] = {p.relative_to(output).as_posix(): digest(p) for p in paths}
            status["target_link"] = "NOT_RUN"
        else:
            run_command([tools["v++"], "--version"], output / "vpp_version.log", output)
            require("2020.2" in (output / "vpp_version.log").read_text(encoding="utf-8", errors="replace"), "target Vitis must be 2020.2")
            run_command([tools["xclbinutil"], "--version"], output / "xclbinutil_version.log", output)
            status.update({"platform": str(platform), "platform_sha256": digest(platform),
                           "requested_clock_mhz": 100, "input_xo_sha256": digest(input_paths[0])})
            write_json(status_path, status)
            xclbin = output / (KERNEL + ".xclbin")
            run_command([tools["v++"], "--target", "hw", "--link", "--platform", str(platform),
                         "--config", str(ROOT / CONFIG), "--kernel_frequency", "100", "--jobs", str(args.jobs),
                         "--save-temps", "--temp_dir", str(output / "_x"), "--output", str(xclbin),
                         "--vivado.prop", "run.impl_1.strategy=Performance_Explore",
                         "--vivado.prop", "run.impl_1.steps.phys_opt_design.is_enabled=1",
                         "--vivado.prop", "run.impl_1.steps.post_route_phys_opt_design.is_enabled=1",
                         str(input_paths[0])], output / "link.log", output)
            require(xclbin.is_file() and xclbin.stat().st_size > 0, "missing/empty xclbin")
            run_command([tools["xclbinutil"], "--quiet", "--info", str(output / "xclbin.info"), "--input", str(xclbin)],
                        output / "info_extract.log", output)
            for section, name in (("CONNECTIVITY", "connectivity"), ("MEM_TOPOLOGY", "mem_topology"), ("IP_LAYOUT", "ip_layout")):
                run_command([tools["xclbinutil"], "--quiet", "--dump-section", section + ":JSON:" + str(output / (name + ".json")),
                             "--input", str(xclbin)], output / (name + "_extract.log"), output)
            status.update(linked_check(output))
            dcps = sorted(set((output / "_x").rglob("*_routed.dcp")) | set((output / "_x").rglob("*route_design*.dcp")))
            require(len(dcps) == 1, "expected exactly one routed checkpoint, found {}; inspect before selecting".format(len(dcps)))
            # Reuse the frozen A16 report helper with its original environment ABI.
            env["A16_2_ROUTED_DCP"] = str(dcps[0])
            env["A16_2_REPORT_DIR"] = str(output / "post_route")
            run_command([tools["vivado"], "-mode", "batch", "-nolog", "-nojournal", "-source", str(ROOT / REPORT)],
                        output / "post_route.log", output, env)
            status["timing_metrics"] = timing_check(output / "post_route/post_route_metrics.txt")
            status["link_mapping"] = "PASS"
            status["input_xo_run"] = str(args.xo_run.resolve())
            artifacts = [xclbin, output / "connectivity.json", output / "mem_topology.json", output / "ip_layout.json",
                         output / "xclbin.info"] + sorted((output / "post_route").iterdir())
            status["artifacts"] = {p.relative_to(output).as_posix(): digest(p) for p in artifacts if p.is_file()}
        # Detect changes during a long-running build before accepting its output.
        source_check(ROOT)
        require(digest(ROOT / MANIFEST) == status["source_manifest_sha256"],
                "source manifest changed during build")
        if args.phase == "link":
            check_input_xo(args.xo_run.resolve())
        status["result"] = "PASS"
    except Exception as error:
        status["result"] = "FAIL"
        status["error"] = str(error)
        raise
    finally:
        write_json(status_path, status)
    print("A18_2_{}=PASS".format(args.phase.upper()))
    print("STATUS=" + str(status_path))
    print("BOARD=NOT_RUN\nPERFORMANCE=NOT_CLAIMED")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("phase", choices=("check", "bundle", "xo", "link"))
    parser.add_argument("--output", type=Path)
    parser.add_argument("--confirm-build", action="store_true")
    parser.add_argument("--xo-run", type=Path)
    parser.add_argument("--platform", type=Path)
    parser.add_argument("--jobs", type=int, default=8)
    args = parser.parse_args()
    if args.phase != "check" and args.output is None:
        parser.error("--output is required")
    try:
        execute(args)
    except Exception as error:
        print("A18_2_{}=FAIL: {}".format(args.phase.upper(), error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
