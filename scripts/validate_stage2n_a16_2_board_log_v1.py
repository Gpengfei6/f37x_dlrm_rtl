#!/usr/bin/env python3
"""Validate future A16.2 physical-latency Host output without device access."""

from __future__ import print_function

import argparse
import tempfile
from pathlib import Path


CASE_COUNT = 5
EXPECTED_BOTTOM = 322
EXPECTED_INTERACTION = 100
EXPECTED_TOP = 744
EXPECTED_TOTAL = 1174


class ValidationError(Exception):
    pass


def require(condition, message):
    if not condition:
        raise ValidationError(message)


def parse_markers(path):
    markers = {}
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if "=" not in raw:
            continue
        key, value = raw.split("=", 1)
        key = key.strip()
        if not key or not (key.startswith("CASE") or key.startswith("A16_2_") or
                           key.startswith("STAGE2N_A16_2_")):
            continue
        require(key not in markers, "duplicate marker {}".format(key))
        markers[key] = value.strip()
    return markers


def integer(markers, key):
    require(key in markers, "missing marker {}".format(key))
    try:
        return int(markers[key], 0)
    except ValueError:
        raise ValidationError("non-integer marker {}".format(key))


def validate(path):
    markers = parse_markers(path)
    require(markers.get("A16_2_ALL_FIVE_CASES") == "PASS", "five-case PASS missing")
    require(markers.get("A16_2_PHYSICAL_HBM_FUNCTIONAL_HOST") == "PASS",
            "functional Host PASS missing")
    require(markers.get("A16_2_PHYSICAL_HBM_LATENCY_COUNTERS") == "PASS",
            "latency-counter PASS missing")
    require(markers.get("A16_2_PERFORMANCE") == "NOT_CLAIMED",
            "performance boundary missing")
    require(markers.get("STAGE2N_A16_2_PHYSICAL_LATENCY_V1") == "PASS",
            "Host terminal PASS missing")

    rows = []
    for index in range(CASE_COUNT):
        prefix = "CASE{}_".format(index)
        expected = integer(markers, prefix + "EXPECTED_RESULT")
        actual = integer(markers, prefix + "ACTUAL_RESULT")
        bottom = integer(markers, prefix + "BOTTOM_CYCLES")
        interaction = integer(markers, prefix + "INTERACTION_CYCLES")
        top = integer(markers, prefix + "TOP_CYCLES")
        total = integer(markers, prefix + "COMPUTE_TOTAL_CYCLES")
        lookup = integer(markers, prefix + "HBM_LOOKUP_CYCLES")
        end_to_end = integer(markers, prefix + "FPGA_END_TO_END_CYCLES")
        overhead = integer(markers, prefix + "PIPELINE_OVERHEAD_CYCLES")
        require(expected == actual, "case{} result mismatch".format(index))
        require(markers.get(prefix + "EMBEDDING_LOADED_MASK") == "0xF",
                "case{} loaded mask".format(index))
        require((bottom, interaction, top, total) ==
                (EXPECTED_BOTTOM, EXPECTED_INTERACTION, EXPECTED_TOP, EXPECTED_TOTAL),
                "case{} accepted A13 counters changed".format(index))
        require(lookup > 0, "case{} lookup interval is zero".format(index))
        require(end_to_end > 0, "case{} end-to-end interval is zero".format(index))
        require(overhead >= 0, "case{} latency accounting is negative".format(index))
        require(end_to_end == lookup + total + overhead,
                "case{} latency accounting mismatch".format(index))
        require(markers.get(prefix + "LATENCY_ACCOUNTING") == "PASS",
                "case{} accounting PASS missing".format(index))
        rows.append((lookup, total, end_to_end, overhead))
    return rows


def good_log():
    lines = [
        "A16_2_ALL_FIVE_CASES=PASS",
        "A16_2_PHYSICAL_HBM_FUNCTIONAL_HOST=PASS",
        "A16_2_PHYSICAL_HBM_LATENCY_COUNTERS=PASS",
        "A16_2_PERFORMANCE=NOT_CLAIMED",
        "STAGE2N_A16_2_PHYSICAL_LATENCY_V1=PASS",
    ]
    for index in range(CASE_COUNT):
        lookup = 80 + index
        overhead = 40 + index
        end_to_end = lookup + EXPECTED_TOTAL + overhead
        prefix = "CASE{}_".format(index)
        lines.extend([
            prefix + "EXPECTED_RESULT={}".format(index - 2),
            prefix + "ACTUAL_RESULT={}".format(index - 2),
            prefix + "EMBEDDING_LOADED_MASK=0xF",
            prefix + "BOTTOM_CYCLES={}".format(EXPECTED_BOTTOM),
            prefix + "INTERACTION_CYCLES={}".format(EXPECTED_INTERACTION),
            prefix + "TOP_CYCLES={}".format(EXPECTED_TOP),
            prefix + "COMPUTE_TOTAL_CYCLES={}".format(EXPECTED_TOTAL),
            prefix + "HBM_LOOKUP_CYCLES={}".format(lookup),
            prefix + "FPGA_END_TO_END_CYCLES={}".format(end_to_end),
            prefix + "PIPELINE_OVERHEAD_CYCLES={}".format(overhead),
            prefix + "LATENCY_ACCOUNTING=PASS",
        ])
    return "\n".join(lines) + "\n"


def run_self_test():
    original = good_log()
    mutations = [
        ("MISSING_LOOKUP", lambda value: value.replace("CASE0_HBM_LOOKUP_CYCLES=80\n", "")),
        ("RESULT_MISMATCH", lambda value: value.replace("CASE1_ACTUAL_RESULT=-1", "CASE1_ACTUAL_RESULT=99")),
        ("ZERO_LOOKUP", lambda value: value.replace("CASE2_HBM_LOOKUP_CYCLES=82", "CASE2_HBM_LOOKUP_CYCLES=0")),
        ("NEGATIVE_ACCOUNTING", lambda value: value.replace("CASE3_PIPELINE_OVERHEAD_CYCLES=43", "CASE3_PIPELINE_OVERHEAD_CYCLES=-1")),
        ("ACCOUNTING_MISMATCH", lambda value: value.replace("CASE4_FPGA_END_TO_END_CYCLES=1302", "CASE4_FPGA_END_TO_END_CYCLES=1303")),
        ("COMPUTE_ABI_CHANGE", lambda value: value.replace("CASE0_COMPUTE_TOTAL_CYCLES=1174", "CASE0_COMPUTE_TOTAL_CYCLES=1175")),
    ]
    with tempfile.TemporaryDirectory(prefix="a16_2_board_log_") as temp_name:
        path = Path(temp_name) / "host.log"
        path.write_text(original, encoding="utf-8")
        validate(path)
        print("BOARD_LOG_SELF_TEST_GOOD=PASS")
        for label, mutate in mutations:
            path.write_text(mutate(original), encoding="utf-8")
            try:
                validate(path)
            except ValidationError:
                print("BOARD_LOG_SELF_TEST_REJECT_{}=PASS".format(label))
            else:
                raise ValidationError("negative self-test accepted: {}".format(label))
    print("A16_2_BOARD_LOG_VALIDATOR_SELF_TEST=PASS")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--log", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    try:
        if args.self_test:
            run_self_test()
            return
        require(args.log is not None and args.log.is_file(), "--log is required")
        rows = validate(args.log)
    except (OSError, ValueError, ValidationError) as error:
        raise SystemExit("A16.2 board-log validation failed: {}".format(error))
    print("A16_2_BOARD_LOG_VALIDATION=PASS")
    print("A16_2_CASE_COUNT={}".format(len(rows)))
    print("A16_2_LATENCY_ACCOUNTING=PASS")
    print("A16_2_PHYSICAL_HBM_LATENCY=VALIDATED_BY_RETURNED_HOST_LOG")
    print("A16_2_PERFORMANCE=NOT_CLAIMED")


if __name__ == "__main__":
    main()
