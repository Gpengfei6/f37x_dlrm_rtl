#!/usr/bin/env python3
"""Dependency-free deterministic regression for the Python fixed-point model."""

import json
import sys
import traceback
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]
PYTHON_DIR = PROJECT_ROOT / "python"
sys.path.insert(0, str(PYTHON_DIR))

from compare_results import compare  # noqa: E402
from fixed_point import (  # noqa: E402
    dot_product,
    round_shift_nearest_away,
    saturating_round,
    wrap_signed,
)
from generate_test_vectors import generate, pack_lanes, write_lines  # noqa: E402
from reference_model import ReferenceModel, load_json  # noqa: E402


def run_tests():
    config = load_json(PROJECT_ROOT / "config" / "model_config.json")
    assert round_shift_nearest_away(7, 4) == 0
    assert round_shift_nearest_away(8, 4) == 1
    assert round_shift_nearest_away(23, 4) == 1
    assert round_shift_nearest_away(24, 4) == 2
    assert round_shift_nearest_away(-7, 4) == 0
    assert round_shift_nearest_away(-8, 4) == -1
    assert round_shift_nearest_away(-23, 4) == -1
    assert round_shift_nearest_away(-24, 4) == -2
    assert saturating_round(2147483647, 32, 16, 4) == 32767
    assert saturating_round(-2147483648, 32, 16, 4) == -32768
    assert wrap_signed(32768, 16) == -32768

    model_data, cases, expected = generate()
    assert len(cases) >= 20
    categories = {case["category"] for case in cases}
    required = {
        "random", "all_zero", "maximum_positive", "maximum_negative",
        "positive_negative_mix", "output_saturation", "repeated_id"
    }
    assert required.issubset(categories)
    assert any(len(set(case["ids"])) < len(case["ids"]) for case in cases)
    assert expected[0]["aggregate"] == [0] * config["embed_dim"]
    assert any(
        32767 in record["output"]
        for case, record in zip(cases, expected)
        if case["category"] == "output_saturation"
    )
    assert any(0 in record["output"] for record in expected)

    model = ReferenceModel(config, model_data)
    for case, expected_record in zip(cases, expected):
        actual = model.fixed_forward(case["ids"])
        assert actual["aggregate"] == expected_record["aggregate"]
        assert actual["accumulators"] == expected_record["accumulators"]
        assert actual["output"] == expected_record["output"]

    narrow_inputs = [508] * config["dense_in_dim"]
    narrow_weights = [127] * config["dense_in_dim"]
    full_precision = sum(a * b for a, b in zip(narrow_inputs, narrow_weights))
    wrapped = dot_product(narrow_inputs, narrow_weights, 0, 16)
    assert wrapped == wrap_signed(full_precision, 16)
    assert wrapped != full_precision

    selfcheck_path = PROJECT_ROOT / "results" / "python_selfcheck.hex"
    write_lines(
        selfcheck_path,
        (
            "{:016x}".format(pack_lanes(record["output"], config["output_width"]))
            for record in expected
        ),
    )
    report = compare(
        selfcheck_path,
        PROJECT_ROOT / "tests" / "expected" / "top_expected.json",
        config["output_width"],
        config["dense_out_dim"],
    )
    assert report["passed"]
    return {
        "status": "PASS",
        "case_count": len(cases),
        "seed": config["random_seed"],
        "categories": sorted(categories),
        "narrow_accumulator_full_precision": full_precision,
        "narrow_accumulator_wrapped_int16": wrapped,
        "self_compare_count": report["rtl_count"],
        "directed_saturation_observed": True,
        "relu_zero_observed": True,
    }


def main():
    log_path = PROJECT_ROOT / "logs" / "python_tests.log"
    log_path.parent.mkdir(parents=True, exist_ok=True)
    try:
        summary = run_tests()
        text = json.dumps(summary, indent=2, sort_keys=True)
        log_path.write_text(text + "\n", encoding="utf-8")
        print("run_python_tests: PASS")
        print(text)
    except Exception:
        text = "run_python_tests: FAIL\n" + traceback.format_exc()
        log_path.write_text(text, encoding="utf-8")
        print(text, file=sys.stderr)
        raise SystemExit(1)


if __name__ == "__main__":
    main()
