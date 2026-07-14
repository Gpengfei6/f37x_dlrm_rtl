"""Compare packed RTL output lines against Python fixed-point expected outputs."""

import argparse
import json
from pathlib import Path

from fixed_point import decode_twos_complement
from reference_model import PROJECT_ROOT, load_json, save_json


def read_rtl_lines(path, lane_width, lane_count):
    outputs = []
    with Path(path).open("r", encoding="ascii") as handle:
        for line_number, line in enumerate(handle, 1):
            token = line.split("#", 1)[0].strip().replace("_", "")
            if not token:
                continue
            if token.lower().startswith("0x"):
                token = token[2:]
            packed = int(token, 16)
            mask = (1 << lane_width) - 1
            outputs.append([
                decode_twos_complement((packed >> (lane * lane_width)) & mask, lane_width)
                for lane in range(lane_count)
            ])
    return outputs


def compare(rtl_path, expected_path, lane_width, lane_count):
    rtl = read_rtl_lines(rtl_path, lane_width, lane_count)
    expected_records = load_json(expected_path)
    expected = [record["output"] for record in expected_records]
    mismatches = []
    for index in range(max(len(rtl), len(expected))):
        actual_value = rtl[index] if index < len(rtl) else None
        expected_value = expected[index] if index < len(expected) else None
        if actual_value != expected_value:
            mismatches.append({
                "index": index,
                "name": expected_records[index]["name"] if index < len(expected) else None,
                "expected": expected_value,
                "actual": actual_value,
            })
    return {
        "passed": not mismatches,
        "rtl_count": len(rtl),
        "expected_count": len(expected),
        "mismatches": mismatches,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rtl", type=Path, required=True)
    parser.add_argument(
        "--expected", type=Path,
        default=PROJECT_ROOT / "tests" / "expected" / "top_expected.json"
    )
    parser.add_argument("--width", type=int, default=16)
    parser.add_argument("--lanes", type=int, default=4)
    parser.add_argument(
        "--report", type=Path, default=PROJECT_ROOT / "results" / "compare_report.json"
    )
    args = parser.parse_args()
    report = compare(args.rtl, args.expected, args.width, args.lanes)
    save_json(args.report, report)
    if report["passed"]:
        print("compare_results: PASS ({} vectors)".format(report["rtl_count"]))
        return
    print("compare_results: FAIL ({} mismatch records)".format(len(report["mismatches"])))
    raise SystemExit(1)


if __name__ == "__main__":
    main()

