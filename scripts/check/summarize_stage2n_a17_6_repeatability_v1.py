#!/usr/bin/env python3
"""Summarize A17 process-restart repeatability logs.

Warmup is kept on disk but excluded from min/median/max.
CASE0..CASE4 each use measured Host CASE* fields only.
REPEAT_BASELINE is a separate series; it is never merged into CASE0.
Lookup/e2e movement is not a failure. Incomplete n is reported as-is.
"""
from __future__ import print_function

import argparse
import re
import sys
from pathlib import Path


GOLDENS = {
    "CASE0": -393,
    "CASE1": -392,
    "CASE2": -93,
    "CASE3": -689,
    "CASE4": -519,
    "REPEAT_BASELINE": -393,
}
SERIES = (
    "CASE0", "CASE1", "CASE2", "CASE3", "CASE4", "REPEAT_BASELINE",
)


class CheckError(Exception):
    pass


def require(condition, message):
    if not condition:
        raise CheckError(message)


def field(text, name):
    match = re.search(r"^" + re.escape(name) + r"=(.*)\s*$", text, re.MULTILINE)
    require(match is not None, "missing " + name)
    return match.group(1).strip()


def int_field(text, name):
    return int(field(text, name))


def median(values):
    ordered = sorted(values)
    n = len(ordered)
    if n == 0:
        return None
    mid = n // 2
    if n % 2 == 1:
        return ordered[mid]
    return (ordered[mid - 1] + ordered[mid]) / 2.0


def parse_rounds(rounds_path):
    rows = []
    for line in rounds_path.read_text(encoding="utf-8", errors="replace").splitlines():
        if not line.startswith("ROUND="):
            continue
        parts = dict(item.split("=", 1) for item in line.split() if "=" in item)
        rows.append({
            "round": int(parts["ROUND"]),
            "role": parts.get("ROLE", ""),
            "stamp": parts.get("STAMP", ""),
            "rc": int(parts.get("RC", "1")),
        })
    return rows


def parse_case(host, prefix):
    actual = int_field(host, prefix + "_ACTUAL_RESULT")
    lookup = int_field(host, prefix + "_HBM_LOOKUP_CYCLES_ACTUAL")
    compute = int_field(host, prefix + "_COMPUTE_TOTAL_CYCLES_ACTUAL")
    e2e = int_field(host, prefix + "_FPGA_END_TO_END_CYCLES_ACTUAL")
    residual = int_field(host, prefix + "_PIPELINE_OVERHEAD_CYCLES_ACTUAL")
    return {
        "actual": actual,
        "lookup": lookup,
        "compute": compute,
        "e2e": e2e,
        "residual": residual,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", type=Path, default=Path("."))
    parser.add_argument("--campaign-dir", type=Path, required=True)
    args = parser.parse_args()
    repo = args.repo.resolve()
    campaign = args.campaign_dir.resolve()
    rounds_path = campaign / "rounds.txt"
    require(rounds_path.is_file(), "rounds.txt missing")
    rows = parse_rounds(rounds_path)
    require(len(rows) > 0, "no ROUND lines")

    measured = {name: [] for name in SERIES}
    warmup_kept = 0
    print("KIND=PROCESS_RESTART_NOT_STEADY_STATE")
    print("NOTE=each round reallocates/fills/syncs BOs in a new process")
    print("NOTE=N measured is a first distribution look, not full performance acceptance")
    print("PERFORMANCE=NOT_CLAIMED")
    print("A16_SPEEDUP=NOT_COMPUTED")

    for row in rows:
        stamp = row["stamp"]
        host_path = repo / "docs/evidence/stage2n_a17_6/repeatability_v1" / stamp / "host.log"
        if not host_path.is_file():
            host_path = repo / "results/stage2n_a17_6/protected_v1" / stamp / "host.log"
        print("ROUND={round} ROLE={role} STAMP={stamp} RC={rc}".format(**row))
        if row["rc"] != 0:
            print("FAILED_ROUND_KEPT=" + stamp)
            print("A17_6_REPEATABILITY_SUMMARY=STOPPED_AFTER_FAILURE")
            break
        require(host_path.is_file(), "host.log missing for " + stamp)
        host = host_path.read_text(encoding="utf-8", errors="replace")
        require("STAGE2N_A17_6_FOUR_BO_HOST_V1=PASS" in host, stamp + " Host PASS missing")
        require("A17_6_BO_CLEANUP=PASS" in host, stamp + " cleanup PASS missing")
        for name in SERIES:
            sample = parse_case(host, name)
            require(sample["actual"] == GOLDENS[name],
                    stamp + " " + name + " golden mismatch")
            line = (
                "{name} lookup={lookup} compute={compute} e2e={e2e} "
                "residual={residual} result={actual}"
            ).format(name=name, **sample)
            print("  " + line)
            if row["role"] == "WARMUP":
                continue
            if row["role"] == "MEASURED":
                measured[name].append(sample)
        if row["role"] == "WARMUP":
            warmup_kept += 1

    print("WARMUP_ROUNDS_KEPT=" + str(warmup_kept))
    print("REPEAT_BASELINE_SEPARATE_FROM_CASE0=YES")
    for name in SERIES:
        samples = measured[name]
        lookups = [s["lookup"] for s in samples]
        computes = [s["compute"] for s in samples]
        e2es = [s["e2e"] for s in samples]
        print(name + "_N=" + str(len(samples)))
        print(name + "_LOOKUP_LIST=" + ",".join(str(v) for v in lookups))
        print(name + "_COMPUTE_LIST=" + ",".join(str(v) for v in computes))
        print(name + "_E2E_LIST=" + ",".join(str(v) for v in e2es))
        if samples:
            print(name + "_LOOKUP_MIN_MEDIAN_MAX={}/{}/{}".format(
                min(lookups), median(lookups), max(lookups)))
            print(name + "_COMPUTE_MIN_MEDIAN_MAX={}/{}/{}".format(
                min(computes), median(computes), max(computes)))
            print(name + "_E2E_MIN_MEDIAN_MAX={}/{}/{}".format(
                min(e2es), median(e2es), max(e2es)))
        else:
            print(name + "_LOOKUP_MIN_MEDIAN_MAX=NA")
    print("A17_6_REPEATABILITY_SUMMARY=PASS")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except CheckError as error:
        print("A17_6_REPEATABILITY_SUMMARY=FAIL", file=sys.stderr)
        print("REASON=" + str(error), file=sys.stderr)
        sys.exit(1)
