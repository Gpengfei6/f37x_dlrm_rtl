#!/usr/bin/env python3
"""Deterministic Stage-2A arithmetic, schedule, and boundary regression."""

import json
import random
import sys
import traceback
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT_ROOT / "python"))

from fixed_point import dot_product, relu_quant, wrap_signed  # noqa: E402
from stage2a_reference import (  # noqa: E402
    DenseJob,
    SUPPORTED_PE_COUNTS,
    cycle_model,
    dense_layer_multicycle,
    lane_mask,
    quantize_runtime,
    validate_job,
    vector_dot_multicycle,
)


def make_layer(rng, input_dim, output_dim, input_limit=32768):
    inputs = [rng.randrange(-input_limit, input_limit) for _ in range(input_dim)]
    weights = [[rng.randrange(-128, 128) for _ in range(input_dim)]
               for _ in range(output_dim)]
    biases = [rng.randrange(-(1 << 23), 1 << 23) for _ in range(output_dim)]
    return inputs, weights, biases


def independent_dense(inputs, weights, biases, acc_width, shift, relu):
    accumulators = []
    outputs = []
    for row, bias in zip(weights, biases):
        accumulator = wrap_signed(bias, acc_width)
        for x_value, w_value in zip(inputs, row):
            accumulator = wrap_signed(
                accumulator + x_value * w_value, acc_width
            )
        accumulators.append(accumulator)
        quantized = relu_quant(accumulator, acc_width, 16, shift)
        if not relu:
            from fixed_point import saturating_round
            quantized = saturating_round(accumulator, acc_width, 16, shift)
        outputs.append(quantized)
    return accumulators, outputs


def run_tests():
    rng = random.Random(0xF37A2A)

    # Schedule and mask matrix, including D<P and non-divisible tails.
    schedule_cases = 0
    for pe_count in SUPPORTED_PE_COUNTS:
        for input_dim in (1, pe_count - 1, pe_count, pe_count + 1,
                          13, 64, 65, 1024):
            k = (input_dim + pe_count - 1) // pe_count
            masks = [lane_mask(input_dim, pe_count, chunk) for chunk in range(k)]
            assert all(mask != 0 for mask in masks)
            assert sum(mask.bit_count() for mask in masks) == input_dim
            assert masks[-1] == ((1 << (input_dim-(k-1)*pe_count)) - 1)
            model = cycle_model(input_dim, 7, pe_count)
            assert model["baseline_layer_cycles"] == 7 * (k + model["r"] + 1)
            assert model["overlap_target_layer_cycles"] == 7*k + model["r"] + 1
            schedule_cases += 1

    # Phase-1 8->4 bit compatibility for all 24 checked-in vectors.
    model_data = json.loads((PROJECT_ROOT / "tests/vectors/model_data.json")
                            .read_text(encoding="utf-8"))
    expected = json.loads((PROJECT_ROOT / "tests/expected/top_expected.json")
                          .read_text(encoding="utf-8"))
    phase1_cases = 0
    for record in expected:
        for pe_count in SUPPORTED_PE_COUNTS:
            accumulators, outputs = dense_layer_multicycle(
                record["aggregate"], model_data["weights"], model_data["biases"],
                num_pe=pe_count, acc_width=32, output_width=16,
                output_shift=4, relu_enable=True,
            )
            assert accumulators == record["accumulators"]
            assert outputs == record["output"]
            phase1_cases += 1

    # Required named sizes, both widths, shifts, ReLU modes, and all P values.
    named_shapes = ((64, 32), (13, 7), (65, 17), (3, 5))
    layer_cases = 0
    for input_dim, output_dim in named_shapes:
        inputs, weights, biases = make_layer(rng, input_dim, output_dim)
        for acc_width in (32, 48):
            for shift in (0, 1, 4, 11):
                for relu in (False, True):
                    expected_acc, expected_out = independent_dense(
                        inputs, weights, biases, acc_width, shift, relu
                    )
                    for pe_count in SUPPORTED_PE_COUNTS:
                        actual_acc, actual_out = dense_layer_multicycle(
                            inputs, weights, biases, pe_count, acc_width, 16,
                            shift, relu
                        )
                        assert actual_acc == expected_acc
                        assert actual_out == expected_out
                        layer_cases += 1

    # Boundary products, biases, rounding, saturation, and 32/48 distinction.
    maximum_inputs = [-32768] * 1024
    maximum_weights = [-128] * 1024
    exact = (1 << 23) - 1 + 1024 * 32768 * 128
    result32 = vector_dot_multicycle(
        maximum_inputs, maximum_weights, (1 << 23) - 1, 16, 32
    )
    result48 = vector_dot_multicycle(
        maximum_inputs, maximum_weights, (1 << 23) - 1, 16, 48
    )
    assert result32 == wrap_signed(exact, 32)
    assert result48 == exact
    assert result32 != result48
    assert quantize_runtime(-8, 48, 16, 4, False) == -1
    assert quantize_runtime(-8, 48, 16, 4, True) == 0
    assert quantize_runtime(8, 48, 16, 4, False) == 1
    assert quantize_runtime(1 << 40, 48, 16, 0, False) == 32767
    assert quantize_runtime(-(1 << 40), 48, 16, 0, False) == -32768

    # The multicycle lane/reduction order must match the existing serial oracle.
    for _ in range(200):
        input_dim = rng.randrange(1, 130)
        pe_count = rng.choice(SUPPORTED_PE_COUNTS)
        acc_width = rng.choice((32, 48))
        inputs = [rng.randrange(-32768, 32768) for _ in range(input_dim)]
        weights = [rng.randrange(-128, 128) for _ in range(input_dim)]
        bias = rng.randrange(-(1 << 23), 1 << 23)
        assert vector_dot_multicycle(inputs, weights, bias, pe_count, acc_width) == \
            dot_product(inputs, weights, bias, acc_width)

    invalid = (
        (DenseJob(0, 1), "BAD_DIMENSION"),
        (DenseJob(1025, 1), "BAD_DIMENSION"),
        (DenseJob(1, 0), "BAD_DIMENSION"),
        (DenseJob(1, 1025), "BAD_DIMENSION"),
        (DenseJob(1, 1, 0, 0), "BUFFER_ALIAS"),
        (DenseJob(1, 1, output_shift=49), "BAD_SHIFT"),
    )
    for job, error_name in invalid:
        assert validate_job(job) == (False, error_name)
    assert validate_job(DenseJob(1024, 1024, output_shift=48)) == (True, None)

    return {
        "status": "PASS",
        "seed": "0xF37A2A",
        "supported_pe": list(SUPPORTED_PE_COUNTS),
        "schedule_mask_cases": schedule_cases,
        "phase1_compatibility_checks": phase1_cases,
        "named_layer_mode_checks": layer_cases,
        "random_dot_checks": 200,
        "acc32_wrap_result": result32,
        "acc48_safe_result": result48,
        "invalid_descriptor_checks": len(invalid) + 1,
        "rtl_status": "SKIPPED locally; no simulator installed",
    }


def main():
    log_path = PROJECT_ROOT / "logs/stage2a_python_tests.log"
    result_path = PROJECT_ROOT / "results/stage2a_python_summary.json"
    log_path.parent.mkdir(parents=True, exist_ok=True)
    result_path.parent.mkdir(parents=True, exist_ok=True)
    try:
        summary = run_tests()
        text = json.dumps(summary, indent=2, sort_keys=True)
        log_path.write_text("run_stage2a_python_tests: PASS\n" + text + "\n",
                            encoding="utf-8")
        result_path.write_text(text + "\n", encoding="utf-8")
        print("run_stage2a_python_tests: PASS")
        print(text)
    except Exception:
        text = "run_stage2a_python_tests: FAIL\n" + traceback.format_exc()
        log_path.write_text(text, encoding="utf-8")
        print(text, file=sys.stderr)
        raise SystemExit(1)


if __name__ == "__main__":
    main()
