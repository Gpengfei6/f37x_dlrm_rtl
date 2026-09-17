#!/usr/bin/env python3
"""Scoped methodology-warning diff: content, not equal counts.

Same critical-warning count is not equivalence. This helper compares rule
IDs and path classes. It does not clear warnings and does not prove timing
signoff. Missing A17 candidate remains NOT_RUN.
"""
from __future__ import print_function

import argparse
import collections
import re
import sys
from pathlib import Path


SUMMARY_ROW = re.compile(
    r"^\|\s*([A-Z0-9-]+)\s*\|\s*(Critical Warning|Warning|Advisory|Error)\s*\|"
    r"\s*(.*?)\s*\|\s*(\d+)\s*\|"
)
DETAIL_HEADER = re.compile(
    r"^([A-Z0-9-]+)#(\d+)\s+(Critical Warning|Warning|Advisory|Error)\s*$"
)
A17_MARKERS = (
    "dlrm_f37x",
    "stage2n_a17",
    "u_hbm_lookup",
    "hbm_pipeline_integration",
    "clkwiz_kernel",
)
PLATFORM_MARKERS = (
    "static_region",
    "clkwiz_pcie",
    "clkwiz_scheduler",
    "clkwiz_sysclks",
    "pcie/inst",
    "base_clocking",
)


class DiffError(Exception):
    pass


def require(condition, message):
    if not condition:
        raise DiffError(message)


def parse_summary(text):
    counts = collections.OrderedDict()
    for line in text.splitlines():
        match = SUMMARY_ROW.match(line.strip())
        if not match:
            continue
        rule, severity, description, count = match.groups()
        counts[rule] = {
            "severity": severity,
            "description": description.strip(),
            "count": int(count),
        }
    return counts


def classify_path(text):
    lowered = text.lower()
    if any(marker.lower() in lowered for marker in A17_MARKERS):
        return "A17_OR_KERNEL_CLOCK"
    if any(marker.lower() in lowered for marker in PLATFORM_MARKERS):
        return "PLATFORM_STATIC"
    return "OTHER"


def parse_details(text):
    items = []
    current = None
    for raw in text.splitlines():
        line = raw.rstrip()
        header = DETAIL_HEADER.match(line)
        if header:
            if current is not None:
                items.append(current)
            current = {
                "rule": header.group(1),
                "index": int(header.group(2)),
                "severity": header.group(3),
                "body": [],
            }
            continue
        if current is not None:
            current["body"].append(line)
    if current is not None:
        items.append(current)
    for item in items:
        body = "\n".join(item["body"])
        item["class"] = classify_path(body)
        item["body_text"] = body
    return items


def critical_rules(summary):
    return {
        rule: info for rule, info in summary.items()
        if info["severity"] == "Critical Warning"
    }


def diff_reports(baseline_text, candidate_text):
    base_summary = parse_summary(baseline_text)
    cand_summary = parse_summary(candidate_text)
    base_crit = critical_rules(base_summary)
    cand_crit = critical_rules(cand_summary)
    shared = sorted(set(base_crit) & set(cand_crit))
    only_base = sorted(set(base_crit) - set(cand_crit))
    only_cand = sorted(set(cand_crit) - set(base_crit))
    count_changed = []
    for rule in shared:
        if base_crit[rule]["count"] != cand_crit[rule]["count"]:
            count_changed.append((
                rule, base_crit[rule]["count"], cand_crit[rule]["count"]
            ))
    cand_details = [
        item for item in parse_details(candidate_text)
        if item["severity"] == "Critical Warning"
    ]
    classes = collections.Counter(item["class"] for item in cand_details)
    kernel_hits = [item for item in cand_details if item["class"] == "A17_OR_KERNEL_CLOCK"]
    return {
        "baseline_critical_rules": len(base_crit),
        "candidate_critical_rules": len(cand_crit),
        "baseline_critical_count": sum(info["count"] for info in base_crit.values()),
        "candidate_critical_count": sum(info["count"] for info in cand_crit.values()),
        "shared_rules": shared,
        "only_baseline_rules": only_base,
        "only_candidate_rules": only_cand,
        "count_changed": count_changed,
        "candidate_classes": dict(classes),
        "kernel_clock_hits": kernel_hits,
        "count_equal": (
            sum(info["count"] for info in base_crit.values()) ==
            sum(info["count"] for info in cand_crit.values())
        ),
    }


def render(result):
    lines = [
        "A17_6_METHODOLOGY_DIFF=PASS" if not result["only_candidate_rules"]
        and not result["count_changed"] and not result["kernel_clock_hits"]
        else "A17_6_METHODOLOGY_DIFF=REVIEW",
        "COUNT_EQUAL={}".format("YES" if result["count_equal"] else "NO"),
        "COUNT_EQUAL_IS_NOT_EQUIVALENCE=1",
        "BASELINE_CRITICAL_COUNT={}".format(result["baseline_critical_count"]),
        "CANDIDATE_CRITICAL_COUNT={}".format(result["candidate_critical_count"]),
        "SHARED_RULES={}".format(",".join(result["shared_rules"]) or "NONE"),
        "ONLY_BASELINE_RULES={}".format(
            ",".join(result["only_baseline_rules"]) or "NONE"),
        "ONLY_CANDIDATE_RULES={}".format(
            ",".join(result["only_candidate_rules"]) or "NONE"),
        "KERNEL_OR_A17_CRITICAL_DETAILS={}".format(
            len(result["kernel_clock_hits"])),
        "CANDIDATE_CLASSES={}".format(result["candidate_classes"]),
    ]
    if result["count_changed"]:
        lines.append("COUNT_CHANGED=" + ";".join(
            "{}:{}->{}".format(rule, old, new)
            for rule, old, new in result["count_changed"]))
    if result["kernel_clock_hits"]:
        lines.append("A17_CLOCK_RESET_OR_INTERFACE_REVIEW_REQUIRED=YES")
    else:
        lines.append("A17_CLOCK_RESET_OR_INTERFACE_REVIEW_REQUIRED=NO")
    lines.append("WORST_PATH_DOES_NOT_SUBSTITUTE_OTHER_CHECKS=1")
    lines.append("CLEARING_ALL_WARNINGS=NOT_A_GOAL")
    return "\n".join(lines) + "\n"


def self_test():
    baseline = """
+-----------+------------------+------------------+------------+
| Rule      | Severity         | Description      | Violations |
+-----------+------------------+------------------+------------+
| TIMING-3  | Critical Warning | Invalid clock    | 2          |
| TIMING-9  | Warning          | Unknown CDC      | 1          |
+-----------+------------------+------------------+------------+
TIMING-3#1 Critical Warning
A primary clock pfm_top_i/static_region/base_clocking/clkwiz_pcie/inst/clk_in1
TIMING-3#2 Critical Warning
A primary clock pfm_top_i/static_region/pcie/inst/gt_top_i
"""
    same = diff_reports(baseline, baseline)
    require(same["count_equal"], "self baseline count")
    require(not same["only_candidate_rules"], "self new rules")
    require(same["candidate_classes"].get("PLATFORM_STATIC") == 2, "self class")
    require(same["kernel_clock_hits"] == [], "self kernel hits")

    added = baseline + """
| TIMING-1  | Critical Warning | Invalid waveform | 1          |
TIMING-1#1 Critical Warning
Invalid clock waveform for clock clk_out1_pfm_top_clkwiz_kernel_0
"""
    changed = diff_reports(baseline, added)
    require("TIMING-1" in changed["only_candidate_rules"], "detect new rule")
    require(changed["kernel_clock_hits"], "detect kernel-clock path")
    require(not changed["count_equal"], "count changed")
    print("A17_6_METHODOLOGY_DIFF_SELF_TEST=PASS")
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument(
        "--baseline",
        default=str(Path("docs/evidence/stage2n_a16_2/final_acceptance_v1/"
                         "target_link_v1/post_route/post_route_methodology.rpt")),
    )
    parser.add_argument("--candidate")
    parser.add_argument("--output")
    args = parser.parse_args(argv)
    if args.self_test:
        return self_test()

    baseline_path = Path(args.baseline)
    require(baseline_path.is_file(), "missing A16.2 methodology baseline")
    if not args.candidate:
        text = (
            "A17_6_METHODOLOGY_DIFF=NOT_RUN\n"
            "REASON=A17.6 post_route_methodology.rpt was not supplied\n"
            "COUNT_EQUAL_IS_NOT_EQUIVALENCE=1\n"
            "BOARD=NOT_RUN\n"
        )
        print(text, end="")
        if args.output:
            Path(args.output).write_text(text, encoding="utf-8")
        return 0

    candidate_path = Path(args.candidate)
    require(candidate_path.is_file(), "missing A17 methodology candidate")
    result = diff_reports(
        baseline_path.read_text(encoding="utf-8", errors="replace"),
        candidate_path.read_text(encoding="utf-8", errors="replace"),
    )
    text = render(result)
    print(text, end="")
    if args.output:
        Path(args.output).write_text(text, encoding="utf-8")
    if result["only_candidate_rules"] or result["kernel_clock_hits"]:
        return 2
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except DiffError as error:
        print("A17_6_METHODOLOGY_DIFF=FAIL", file=sys.stderr)
        print("REASON={}".format(error), file=sys.stderr)
        sys.exit(1)
