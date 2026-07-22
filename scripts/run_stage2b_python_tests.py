#!/usr/bin/env python3
"""Deterministic and randomized Stage-2B multilayer software regression."""

import json
import random
import sys
import tempfile
import traceback
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT_ROOT / "python"))

from fixed_point import decode_twos_complement, wrap_signed  # noqa: E402
from generate_stage2b_vectors import (  # noqa: E402
    BIAS_WIDTH,
    DESCRIPTOR_ROW_WIDTH,
    INPUT_WIDTH,
    MAX_BIAS_VALUES,
    MAX_IN_DIM,
    MAX_LAYERS,
    MAX_OUT_DIM,
    MAX_WEIGHT_VALUES,
    OUTPUT_WIDTH,
    VECTOR_FILES,
    WEIGHT_WIDTH,
    generate,
)
from stage2a_reference import (  # noqa: E402
    SUPPORTED_PE_COUNTS,
    dense_layer_multicycle,
)
from stage2b_reference import (  # noqa: E402
    LayerDescriptor,
    activation_chunk_masks,
    execute_mlp,
    layer_buffer_selections,
    unpack_layer_descriptor,
    validate_descriptors,
)


RANDOM_SEED = 0xF37B2B
RANDOM_CASES_PER_MODE = 20


def decode_packed_row(line, width, lane_count):
    value = int(line, 16)
    mask = (1 << width) - 1
    return [
        decode_twos_complement((value >> (lane * width)) & mask, width)
        for lane in range(lane_count)
    ]


def read_signed_scalar_hex(path, width):
    return [
        decode_twos_complement(int(line, 16), width)
        for line in path.read_text(encoding="ascii").splitlines()
        if line
    ]


def descriptor_list(case):
    return [
        LayerDescriptor.from_dict(value) for value in case["descriptors"]
    ]


def check_generated_vectors():
    generated = generate(PROJECT_ROOT)
    with tempfile.TemporaryDirectory() as first_directory, \
            tempfile.TemporaryDirectory() as second_directory:
        first_root = Path(first_directory)
        second_root = Path(second_directory)
        first = generate(first_root)
        second = generate(second_root)
        assert first == second == generated
        for relative_name in VECTOR_FILES:
            checked = (PROJECT_ROOT / relative_name).read_bytes()
            assert checked == (first_root / relative_name).read_bytes()
            assert checked == (second_root / relative_name).read_bytes()

    expected_path = PROJECT_ROOT / "tests/expected/stage2b_expected.json"
    metadata = json.loads(expected_path.read_text(encoding="utf-8"))
    assert metadata == generated
    assert metadata["case_count"] == 20
    assert metadata["lane_zero_is_lsb"] is True

    input_lines = (PROJECT_ROOT / "tests/vectors/stage2b_inputs.hex") \
        .read_text(encoding="ascii").splitlines()
    output_lines = (PROJECT_ROOT / "tests/expected/stage2b_final_outputs.hex") \
        .read_text(encoding="ascii").splitlines()
    descriptor_lines = (PROJECT_ROOT / "tests/vectors/stage2b_descriptors.hex") \
        .read_text(encoding="ascii").splitlines()
    weight_path = PROJECT_ROOT / "tests/vectors/stage2b_weights.hex"
    bias_path = PROJECT_ROOT / "tests/vectors/stage2b_biases.hex"
    weight_lines = weight_path.read_text(encoding="ascii").splitlines()
    bias_lines = bias_path.read_text(encoding="ascii").splitlines()

    assert len(input_lines) == len(output_lines) == metadata["case_count"]
    assert len(descriptor_lines) == metadata["case_count"] * MAX_LAYERS
    assert all(len(line) == metadata["input_row_hex_chars"] == 4096
               for line in input_lines)
    assert all(len(line) == metadata["output_row_hex_chars"] == 4096
               for line in output_lines)
    assert all(len(line) == metadata["descriptor_row_hex_chars"] == 24
               for line in descriptor_lines)
    assert all(len(line) == (WEIGHT_WIDTH + 3) // 4 == 2
               for line in weight_lines)
    assert all(len(line) == (BIAS_WIDTH + 3) // 4 == 6
               for line in bias_lines)
    assert all((int(line, 16) >> 93) == 0 for line in descriptor_lines)

    weight_memory = read_signed_scalar_hex(weight_path, WEIGHT_WIDTH)
    bias_memory = read_signed_scalar_hex(bias_path, BIAS_WIDTH)
    assert len(weight_memory) == metadata["weight_values_written"]
    assert len(bias_memory) == metadata["bias_values_written"]

    valid_count = 0
    invalid_count = 0
    for case in metadata["cases"]:
        case_index = case["case_index"]
        inputs = decode_packed_row(input_lines[case_index], INPUT_WIDTH, MAX_IN_DIM)
        assert inputs[:len(case["inputs"])] == case["inputs"]
        assert not any(inputs[len(case["inputs"]):])
        assert inputs[0] == decode_twos_complement(
            int(input_lines[case_index], 16) & 0xffff, INPUT_WIDTH
        )

        descriptors = descriptor_list(case)
        for descriptor_slot in range(MAX_LAYERS):
            row_index = case_index * MAX_LAYERS + descriptor_slot
            packed_value = int(descriptor_lines[row_index], 16)
            expected_descriptor = (
                descriptors[descriptor_slot]
                if descriptor_slot < len(descriptors) else None
            )
            if expected_descriptor is None:
                assert packed_value == 0
            else:
                assert unpack_layer_descriptor(packed_value) == expected_descriptor

        validation = validate_descriptors(
            descriptors, case["layer_count"], case["descriptor_loaded"],
            max_layers=MAX_LAYERS, max_in_dim=MAX_IN_DIM,
            max_out_dim=MAX_OUT_DIM, acc_width=case["acc_width"],
            max_weight_values=MAX_WEIGHT_VALUES,
            max_bias_values=MAX_BIAS_VALUES,
        )
        assert validation.to_dict() == case["expected_validation"]
        if validation.valid:
            valid_count += 1
            actual = execute_mlp(
                case["inputs"], descriptors, weight_memory, bias_memory,
                layer_count=case["layer_count"],
                descriptor_loaded=case["descriptor_loaded"],
                num_pe=case["num_pe"], acc_width=case["acc_width"],
                initial_buffer_select=case["initial_buffer_select"],
                max_layers=MAX_LAYERS, max_in_dim=MAX_IN_DIM,
                max_out_dim=MAX_OUT_DIM,
                max_weight_values=MAX_WEIGHT_VALUES,
                max_bias_values=MAX_BIAS_VALUES,
            )
            assert actual.to_dict() == case["expected_execution"]
            outputs = decode_packed_row(
                output_lines[case_index], OUTPUT_WIDTH, MAX_OUT_DIM
            )
            assert outputs[:len(actual.final_output)] == actual.final_output
            assert not any(outputs[len(actual.final_output):])
            assert outputs[0] == decode_twos_complement(
                int(output_lines[case_index], 16) & 0xffff, OUTPUT_WIDTH
            )
            expected_final_buffer = (
                case["initial_buffer_select"] ^ (case["layer_count"] & 1)
            )
            assert actual.final_buffer_select == expected_final_buffer
        else:
            invalid_count += 1
            assert int(output_lines[case_index], 16) == 0

    assert valid_count == 11 and invalid_count == 9
    return metadata, weight_memory, bias_memory


def check_directed_properties(metadata, weight_memory, bias_memory):
    cases = {case["name"]: case for case in metadata["cases"]}

    phase1_expected = json.loads(
        (PROJECT_ROOT / "tests/expected/top_expected.json").read_text(
            encoding="utf-8"
        )
    )
    assert (cases["single_stage2a_compat"]["expected_execution"]["final_output"] ==
            phase1_expected[0]["output"])
    assert cases["two_layer_a_b_a"]["expected_execution"][
        "final_buffer_select"] == 0
    assert cases["three_layer_a_b_a_b"]["expected_execution"][
        "final_buffer_select"] == 1
    assert cases["four_layer_boundary"]["expected_execution"][
        "final_buffer_select"] == 0

    relu_case = cases["intermediate_relu_final_linear"]["expected_execution"]
    assert all(value >= 0 for value in relu_case["layer_outputs"][0])
    assert any(value < 0 for value in relu_case["final_output"])
    negative_case = cases["negative_intermediate"]["expected_execution"]
    assert any(value < 0 for value in negative_case["layer_outputs"][0])
    saturation_case = cases[
        "intermediate_positive_negative_saturation"
    ]["expected_execution"]
    assert 32767 in saturation_case["layer_outputs"][0]
    assert -32768 in saturation_case["layer_outputs"][0]

    tail_case = cases["tail_13_7_5"]
    for descriptor in descriptor_list(tail_case):
        masks = activation_chunk_masks(descriptor.in_dim, tail_case["num_pe"])
        assert sum(mask.bit_count() for mask in masks) == descriptor.in_dim
        assert masks[-1] != (1 << tail_case["num_pe"]) - 1
    small_case = cases["input_dim_less_than_num_pe"]
    small_descriptor = descriptor_list(small_case)[0]
    assert small_descriptor.in_dim < small_case["num_pe"]
    assert activation_chunk_masks(
        small_descriptor.in_dim, small_case["num_pe"]
    ) == [(1 << small_descriptor.in_dim) - 1]

    for case_name, acc_width in (("acc32_wrap", 32), ("acc48_safe", 48)):
        case = cases[case_name]
        descriptor = descriptor_list(case)[0]
        row = weight_memory[
            descriptor.weight_base:descriptor.weight_base + descriptor.in_dim
        ]
        bias = bias_memory[descriptor.bias_base]
        exact = bias + sum(
            input_value * weight_value
            for input_value, weight_value in zip(case["inputs"], row)
        )
        accumulator = case["expected_execution"]["layer_accumulators"][0][0]
        assert accumulator == wrap_signed(exact, acc_width)
        if acc_width == 32:
            assert accumulator != exact
        else:
            assert accumulator == exact

    # Prove that exclusive-end arithmetic is not allowed to wrap at 32 bits.
    wrapped_address = LayerDescriptor(
        4, 2, (1 << 32) - 4, 0, 4, True
    )
    validation = validate_descriptors(
        [wrapped_address], 1, [True], max_weight_values=1 << 32
    )
    assert not validation.valid and validation.error == "WEIGHT_RANGE"
    negative_address = LayerDescriptor(1, 1, -1, 0, 4, True)
    validation = validate_descriptors([negative_address], 1, [True])
    assert not validation.valid and validation.error == "WEIGHT_RANGE"


def check_random_multilayer_cases():
    rng = random.Random(RANDOM_SEED)
    random_cases = 0
    layer_count_coverage = {count: 0 for count in range(1, MAX_LAYERS + 1)}

    for num_pe in SUPPORTED_PE_COUNTS:
        for acc_width in (32, 48):
            for mode_case in range(RANDOM_CASES_PER_MODE):
                layer_count = (mode_case % MAX_LAYERS) + 1
                layer_count_coverage[layer_count] += 1
                input_dim = rng.randint(1, 18)
                inputs = [rng.randint(-32768, 32767) for _ in range(input_dim)]
                weight_memory = [0] * rng.randint(0, 3)
                bias_memory = [0] * rng.randint(0, 3)
                descriptors = []
                current_dim = input_dim

                for _ in range(layer_count):
                    out_dim = rng.randint(1, 18)
                    weight_memory.extend([0] * rng.randint(0, 2))
                    weight_base = len(weight_memory)
                    rows = [
                        [rng.randint(-128, 127) for _ in range(current_dim)]
                        for _ in range(out_dim)
                    ]
                    for row in rows:
                        weight_memory.extend(row)
                    bias_memory.extend([0] * rng.randint(0, 1))
                    bias_base = len(bias_memory)
                    biases = [
                        rng.randint(-(1 << 23), (1 << 23) - 1)
                        for _ in range(out_dim)
                    ]
                    bias_memory.extend(biases)
                    descriptors.append(LayerDescriptor(
                        in_dim=current_dim,
                        out_dim=out_dim,
                        weight_base=weight_base,
                        bias_base=bias_base,
                        output_shift=rng.choice((0, 1, 4, 11)),
                        relu_enable=bool(rng.randrange(2)),
                    ))
                    current_dim = out_dim

                validation = validate_descriptors(
                    descriptors, layer_count, [True] * layer_count,
                    acc_width=acc_width,
                    max_weight_values=len(weight_memory),
                    max_bias_values=len(bias_memory),
                )
                assert validation.valid
                initial_buffer = rng.randrange(2)
                actual = execute_mlp(
                    inputs, descriptors, weight_memory, bias_memory,
                    layer_count=layer_count,
                    descriptor_loaded=[True] * layer_count,
                    num_pe=num_pe, acc_width=acc_width,
                    initial_buffer_select=initial_buffer,
                    max_weight_values=len(weight_memory),
                    max_bias_values=len(bias_memory),
                )

                manual_inputs = list(inputs)
                manual_outputs = []
                manual_accumulators = []
                for descriptor in descriptors:
                    rows = []
                    for output_index in range(descriptor.out_dim):
                        start = (descriptor.weight_base +
                                 output_index * descriptor.in_dim)
                        rows.append(weight_memory[start:start + descriptor.in_dim])
                    biases = bias_memory[
                        descriptor.bias_base:descriptor.bias_base + descriptor.out_dim
                    ]
                    accumulators, outputs = dense_layer_multicycle(
                        manual_inputs, rows, biases, num_pe=num_pe,
                        acc_width=acc_width, output_width=OUTPUT_WIDTH,
                        output_shift=descriptor.output_shift,
                        relu_enable=descriptor.relu_enable,
                    )
                    manual_accumulators.append(accumulators)
                    manual_outputs.append(outputs)
                    manual_inputs = list(outputs)
                    masks = activation_chunk_masks(descriptor.in_dim, num_pe)
                    assert sum(mask.bit_count() for mask in masks) == descriptor.in_dim

                selections, final_buffer = layer_buffer_selections(
                    layer_count, initial_buffer
                )
                assert actual.layer_accumulators == manual_accumulators
                assert actual.layer_outputs == manual_outputs
                assert actual.final_output == manual_inputs
                assert actual.buffer_selections == selections
                assert actual.final_buffer_select == final_buffer
                random_cases += 1

    assert all(count > 0 for count in layer_count_coverage.values())
    assert random_cases == (
        len(SUPPORTED_PE_COUNTS) * 2 * RANDOM_CASES_PER_MODE
    )
    return random_cases, layer_count_coverage


def run_tests():
    metadata, weight_memory, bias_memory = check_generated_vectors()
    check_directed_properties(metadata, weight_memory, bias_memory)
    random_cases, layer_count_coverage = check_random_multilayer_cases()
    return {
        "status": "PASS",
        "seed": "0x{:X}".format(RANDOM_SEED),
        "deterministic_cases": metadata["case_count"],
        "deterministic_valid_cases": 11,
        "deterministic_invalid_cases": 9,
        "random_multilayer_cases": random_cases,
        "random_cases_per_pe_acc_mode": RANDOM_CASES_PER_MODE,
        "random_layer_count_coverage": layer_count_coverage,
        "supported_pe": list(SUPPORTED_PE_COUNTS),
        "accumulator_widths": [32, 48],
        "packed_input_hex_chars": metadata["input_row_hex_chars"],
        "packed_output_hex_chars": metadata["output_row_hex_chars"],
        "descriptor_hex_chars": metadata["descriptor_row_hex_chars"],
        "lane_zero_is_lsb": True,
        "repeat_generation_identical": True,
        "active_rtl_status": (
            "NOT_EVALUATED; inspect the independent Stage 2B XSim status/log"
        ),
    }


def main():
    log_path = PROJECT_ROOT / "logs/stage2b_python_tests.log"
    result_path = PROJECT_ROOT / "results/stage2b_python_summary.json"
    log_path.parent.mkdir(parents=True, exist_ok=True)
    result_path.parent.mkdir(parents=True, exist_ok=True)
    try:
        summary = run_tests()
        text = json.dumps(summary, indent=2, sort_keys=True)
        log_path.write_text(
            "run_stage2b_python_tests: PASS\n" + text + "\n",
            encoding="utf-8",
        )
        result_path.write_text(text + "\n", encoding="utf-8")
        print("run_stage2b_python_tests: PASS")
        print(text)
    except Exception:
        text = "run_stage2b_python_tests: FAIL\n" + traceback.format_exc()
        log_path.write_text(text, encoding="utf-8")
        print(text, file=sys.stderr)
        raise SystemExit(1)


if __name__ == "__main__":
    main()
