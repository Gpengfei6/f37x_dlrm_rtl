#!/usr/bin/env python3
"""Summarize Stage 2C/2D OOC reports for the Stage 2E version review."""

import argparse
import json
import re
import sys
from pathlib import Path


def read_report(path):
    if not path.is_file():
        raise FileNotFoundError("required report is missing: {}".format(path))
    return path.read_text(encoding="utf-8", errors="replace")


def parse_tool_version(text):
    match = re.search(r"Tool Version\s*:\s*Vivado v\.?(\d{4}\.\d+)", text)
    if match is None:
        raise ValueError("Vivado tool version was not found in utilization report")
    return match.group(1)


def parse_utilization(text):
    pattern = re.compile(
        r"^\|\s*mlp_sequence_controller\s*\|\s*\(top\)\s*\|"
        r"\s*(\d+)\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|"
        r"\s*(\d+)\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|",
        re.MULTILINE,
    )
    match = pattern.search(text)
    if match is None:
        raise ValueError("top-level hierarchical utilization row was not found")
    values = [int(value) for value in match.groups()]
    return {
        "lut": values[0],
        "logic_lut": values[1],
        "lutram": values[2],
        "srl": values[3],
        "ff": values[4],
        "ramb36e1": values[5],
        "ramb18e1": values[6],
        "dsp": values[7],
    }


def parse_timing(text):
    try:
        section = text.split("| Design Timing Summary", 1)[1]
    except IndexError:
        raise ValueError("design timing summary section was not found")
    match = re.search(
        r"^\s*(-?\d+(?:\.\d+)?)\s+(-?\d+(?:\.\d+)?)\s+"
        r"(\d+)\s+(\d+)\s+",
        section,
        re.MULTILINE,
    )
    if match is None:
        raise ValueError("design timing summary values were not found")
    worst_path = re.search(
        r"Slack \((?:MET|VIOLATED)\)\s*:\s*(-?\d+(?:\.\d+)?)ns.*?"
        r"^\s*Source:\s*(\S+).*?^\s*Destination:\s*(\S+)",
        section,
        re.MULTILINE | re.DOTALL,
    )
    result = {
        "wns_ns": float(match.group(1)),
        "tns_ns": float(match.group(2)),
        "failing_setup_endpoints": int(match.group(3)),
        "total_setup_endpoints": int(match.group(4)),
    }
    if worst_path is not None:
        result["worst_path"] = {
            "slack_ns": float(worst_path.group(1)),
            "source": worst_path.group(2),
            "destination": worst_path.group(3),
        }
    return result


def parse_latch_count(text):
    match = re.search(r"^LATCH_COUNT=(\d+)\s*$", text, re.MULTILINE)
    if match is None:
        raise ValueError("LATCH_COUNT was not found in synthesis status")
    return int(match.group(1))


def parse_rule_report(text):
    total_match = re.search(r"Violations found:\s*(\d+)", text)
    if total_match is None:
        raise ValueError("violation total was not found")
    rules = {}
    for match in re.finditer(
        r"^\|\s*([A-Z][A-Z0-9_-]*-\d+)\s*\|\s*([^|]+?)\s*\|"
        r"\s*([^|]+?)\s*\|\s*(\d+)\s*\|\s*$",
        text,
        re.MULTILINE,
    ):
        rules[match.group(1)] = {
            "severity": match.group(2).strip(),
            "description": match.group(3).strip(),
            "violations": int(match.group(4)),
        }
    return {"total_violations": int(total_match.group(1)), "rules": rules}


def parse_check_timing(text):
    checks = {}
    for match in re.finditer(
        r"^\d+\.\s+checking\s+([a-z_]+)\s+\((\d+)\)\s*$",
        text,
        re.MULTILINE,
    ):
        checks[match.group(1)] = int(match.group(2))
    if not checks:
        raise ValueError("check_timing table of contents was not found")
    return checks


def parse_high_fanout(text):
    match = re.search(
        r"^\|\s*(?!Net Name\s*\|)(.+?)\s*\|\s*(\d+)\s*\|\s*([^|]+?)\s*\|\s*$",
        text,
        re.MULTILINE,
    )
    if match is None:
        raise ValueError("high-fanout table row was not found")
    return {
        "net": match.group(1).strip(),
        "fanout": int(match.group(2)),
        "driver_type": match.group(3).strip(),
    }


def parse_ram_mapping(text):
    weight_banks = len(
        set(re.findall(
            r"(weight_bank\[\d+\]\.memory_reg)\s*\|\s*RAMB36E1\s*\|"
            r"\s*A:A:4096x8\b",
            text,
        ))
    )
    bias_rams = len(
        set(re.findall(
            r"(bias_memory_reg)\s*\|\s*RAMB36E1\s*\|\s*A:A:1024x24\b",
            text,
        ))
    )
    activation_banks = len(
        set(re.findall(
            r"(u_activation_buffer[01]/activation_bank\[\d+\]\.memory_reg)"
            r"\s*\|\s*RAMB18E1\s*\|"
            r"\s*A:A:64x16\b",
            text,
        ))
    )
    return {
        "weight_4096x8_ramb36": weight_banks,
        "bias_1024x24_ramb36": bias_rams,
        "activation_64x16_ramb18": activation_banks,
        "expected_mapping_preserved": (
            weight_banks == 16 and bias_rams == 1 and activation_banks == 32
        ),
    }


def build_summary(result_dir, expected_version):
    utilization = read_report(result_dir / "post_synth_utilization.rpt")
    timing = read_report(result_dir / "post_synth_timing_summary.rpt")
    status = read_report(result_dir / "stage2c_synth_status.txt")
    ram = read_report(result_dir / "post_synth_ram_utilization.rpt")
    check_timing = read_report(result_dir / "post_synth_check_timing.rpt")
    drc = read_report(result_dir / "post_synth_drc.rpt")
    methodology = read_report(result_dir / "post_synth_methodology.rpt")
    high_fanout = read_report(result_dir / "post_synth_high_fanout.rpt")

    tool_version = parse_tool_version(utilization)
    resources = parse_utilization(utilization)
    timing_values = parse_timing(timing)
    latch_count = parse_latch_count(status)
    ram_mapping = parse_ram_mapping(ram)
    version_matches = expected_version is None or tool_version == expected_version
    timing_met = (
        timing_values["wns_ns"] >= 0.0
        and timing_values["tns_ns"] == 0.0
        and timing_values["failing_setup_endpoints"] == 0
    )
    structural_pass = (
        latch_count == 0
        and ram_mapping["expected_mapping_preserved"]
        and resources["ramb36e1"] == 17
        and resources["ramb18e1"] == 32
    )
    return {
        "status": "PASS" if version_matches and timing_met and structural_pass else "FAIL",
        "vivado_version": tool_version,
        "expected_vivado_version": expected_version,
        "version_matches": version_matches,
        "part": "xc7a200tfbg484-2",
        "clock_period_ns": 10.0,
        "mode": "out_of_context_post_synthesis",
        "resources": resources,
        "timing": timing_values,
        "timing_met": timing_met,
        "latch_count": latch_count,
        "ram_mapping": ram_mapping,
        "check_timing": parse_check_timing(check_timing),
        "drc": parse_rule_report(drc),
        "methodology": parse_rule_report(methodology),
        "highest_fanout": parse_high_fanout(high_fanout),
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--result-dir", default="results/stage2c", type=Path,
        help="directory containing run_synth_stage2c.tcl reports",
    )
    parser.add_argument("--expected-version", default=None)
    parser.add_argument("--output", type=Path, default=None)
    args = parser.parse_args()

    try:
        summary = build_summary(args.result_dir, args.expected_version)
    except (FileNotFoundError, ValueError) as exc:
        print("summarize_stage2e_reports: FAIL - {}".format(exc), file=sys.stderr)
        return 1

    text = json.dumps(summary, indent=2, sort_keys=True) + "\n"
    if args.output is not None:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text, encoding="utf-8")
    print(text, end="")
    print("summarize_stage2e_reports: {}".format(summary["status"]))
    return 0 if summary["status"] == "PASS" else 2


if __name__ == "__main__":
    sys.exit(main())
