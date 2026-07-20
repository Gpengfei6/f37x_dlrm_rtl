#!/usr/bin/env python3
"""Deterministic Stage-2A arithmetic, schedule, and boundary regression."""

import json
import random
import re
import sys
import tempfile
import traceback
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT_ROOT))
sys.path.insert(0, str(PROJECT_ROOT / "python"))

from scripts import collect_validation_bundle as validation_bundle  # noqa: E402
from scripts.collect_validation_bundle import (  # noqa: E402
    STAGE2A_TESTBENCHES,
    update_validation_summary,
)

from fixed_point import (  # noqa: E402
    decode_twos_complement,
    dot_product,
    relu_quant,
    wrap_signed,
)
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


def decode_packed_hex_row(line, lane_width, lane_count):
    packed = int(line, 16)
    mask = (1 << lane_width) - 1
    return [
        decode_twos_complement((packed >> (lane * lane_width)) & mask,
                               lane_width)
        for lane in range(lane_count)
    ]


def check_phase1_vector_loader():
    config = json.loads((PROJECT_ROOT / "config/model_config.json")
                        .read_text(encoding="utf-8"))
    expected = json.loads((PROJECT_ROOT / "tests/expected/top_expected.json")
                          .read_text(encoding="utf-8"))
    input_lines = (PROJECT_ROOT / "tests/vectors/dense_inputs.hex").read_text(
        encoding="ascii"
    ).splitlines()
    output_lines = (PROJECT_ROOT / "tests/expected/dense_outputs.hex").read_text(
        encoding="ascii"
    ).splitlines()

    aggregate_width = config["data_width"] + (config["num_lookups"] - 1).bit_length()
    input_row_width = aggregate_width * config["dense_in_dim"]
    output_row_width = config["output_width"] * config["dense_out_dim"]
    input_hex_chars = (input_row_width + 3) // 4
    output_hex_chars = (output_row_width + 3) // 4

    assert len(input_lines) == config["num_test_cases"] == len(expected)
    assert len(output_lines) == config["num_test_cases"]
    assert input_row_width == 80 and output_row_width == 64
    assert all(len(line) == input_hex_chars == 20 for line in input_lines)
    assert all(len(line) == output_hex_chars == 16 for line in output_lines)

    decoded_inputs = [
        decode_packed_hex_row(line, aggregate_width, config["dense_in_dim"])
        for line in input_lines
    ]
    decoded_outputs = [
        decode_packed_hex_row(line, config["output_width"],
                              config["dense_out_dim"])
        for line in output_lines
    ]
    assert decoded_inputs == [record["aggregate"] for record in expected]
    assert decoded_outputs == [record["output"] for record in expected]
    assert decoded_outputs[0] == [32767, 0, 0, 315]
    # Explicit lane-zero check: the first output is the low 16 bits of the row.
    assert decoded_outputs[0][0] == decode_twos_complement(
        int(output_lines[0], 16) & 0xffff, 16
    )

    testbench = (PROJECT_ROOT / "tb/tb_dense_layer_engine.sv").read_text(
        encoding="utf-8"
    )
    stage1_testbench = (PROJECT_ROOT / "tb/tb_dense_layer_core.sv").read_text(
        encoding="utf-8"
    )
    required_patterns = (
        r"localparam integer PHASE1_INPUT_ROW_WIDTH\s*=\s*"
        r"PHASE1_IN_DIM\*PHASE1_INPUT_WIDTH\s*;",
        r"localparam integer PHASE1_OUTPUT_ROW_WIDTH\s*=\s*"
        r"PHASE1_OUT_DIM\*OUTPUT_WIDTH\s*;",
        r"logic\s*\[PHASE1_INPUT_ROW_WIDTH-1:0\]\s*"
        r"phase1_input_rows\s*\[0:PHASE1_CASE_COUNT-1\]\s*;",
        r"logic\s*\[PHASE1_OUTPUT_ROW_WIDTH-1:0\]\s*"
        r"phase1_output_rows\s*\[0:PHASE1_CASE_COUNT-1\]\s*;",
        r"\$readmemh\(\"tests/vectors/dense_inputs\.hex\",\s*"
        r"phase1_input_rows\s*\)\s*;",
        r"\$readmemh\(\"tests/expected/dense_outputs\.hex\",\s*"
        r"phase1_output_rows\s*\)\s*;",
        r"phase1_input_rows\[case_index\]\s*"
        r"\[lane_index\*PHASE1_INPUT_WIDTH\s*\+:\s*PHASE1_INPUT_WIDTH\]",
        r"phase1_output_rows\[case_index\]\s*"
        r"\[lane_index\*OUTPUT_WIDTH\s*\+:\s*OUTPUT_WIDTH\]",
        r"\$signed\(\s*phase1_input_rows\[case_index\]",
        r"\$signed\(\s*phase1_output_rows\[case_index\]",
        r"INPUT_WIDTH'\(phase1_input_element\)",
        r"RUN_COMPAT\s*&&\s*INPUT_WIDTH\s*<\s*PHASE1_INPUT_WIDTH",
    )
    assert all(re.search(pattern, testbench, re.MULTILINE) is not None
               for pattern in required_patterns)
    assert re.search(r"phase1_inputs\s*\[", testbench) is None
    assert re.search(r"phase1_outputs\s*\[", testbench) is None
    assert "{{6{" not in testbench
    assert "logic [IN_DIM*IN_WIDTH-1:0] input_vectors" in stage1_testbench
    assert "logic [OUT_DIM*OUTPUT_WIDTH-1:0] expected_vectors" in stage1_testbench

    return {
        "input_hex_chars": input_hex_chars,
        "input_row_width": input_row_width,
        "output_hex_chars": output_hex_chars,
        "output_row_width": output_row_width,
        "case0_outputs": decoded_outputs[0],
        "checked_cases": len(expected),
        "lane0_is_lsb": True,
        "row_width_storage": True,
    }


def check_validation_summary_merge():
    stage1_testbenches = (
        "tb_rv_fifo",
        "tb_saturating_round",
        "tb_relu_quant",
        "tb_dot_product_core",
        "tb_dense_layer_core",
        "tb_embedding_mem_model",
        "tb_minimal_recommendation_pipeline",
        "tb_dlrm_minimal_top",
    )

    def status_rows(testbenches, failing_sim=None):
        rows = ["xvlog COMPILE PASS 0"]
        for testbench in testbenches:
            rows.append("{} ELAB PASS 0".format(testbench))
            status = "FAIL" if testbench == failing_sim else "PASS"
            rows.append("{} SIM {} 0".format(testbench, status))
        return rows

    python_record = {
        "name": "python_regression",
        "category": "python",
        "status": "PASS",
        "exit_code": 0,
        "log": "logs/python_tests.log",
        "reason": "fixture",
    }
    legacy_tests = [python_record, {
        "name": "xvlog_compile",
        "category": "rtl_compile",
        "status": "PASS",
    }]
    legacy_tests.extend({
        "name": "{}_{}".format(testbench, stage.lower()),
        "category": "rtl_simulation" if stage == "SIM" else "rtl_compile",
        "status": "PASS",
    } for testbench in stage1_testbenches for stage in ("ELAB", "SIM"))
    legacy_tests.extend((
        {
            "name": "xsim_stage1_tb_rv_fifo_sim",
            "category": "rtl_simulation",
            "status": "PASS",
        },
        {
            "name": "xsim_stage2a_suite",
            "category": "rtl_simulation",
            "status": "SKIPPED",
        },
    ))
    original = {"overall_status": "PASS", "tests": legacy_tests}

    with tempfile.TemporaryDirectory() as temporary_directory:
        temporary_path = Path(temporary_directory)
        stage1_path = temporary_path / "xsim_stage1_status.txt"
        stage2a_path = temporary_path / "xsim_stage2a_status.txt"
        missing_path = temporary_path / "missing_stage2a_status.txt"
        stage1_path.write_text(
            "\n".join(status_rows(stage1_testbenches)) + "\n", encoding="utf-8"
        )
        stage2a_path.write_text(
            "\n".join(status_rows(STAGE2A_TESTBENCHES)) + "\n",
            encoding="utf-8",
        )

        # Existing legacy and new-format records must be replaced, not duplicated.
        merged = update_validation_summary(
            original, stage1_path, stage2a_path, require_stage2a=True
        )
        assert merged["overall_status"] == "PASS"
        assert merged["counts"] == {"pass": 31, "fail": 0, "skipped": 0}
        assert merged["stage2a_rtl_satisfied"] is True
        names = [item["name"] for item in merged["tests"]]
        assert len(names) == len(set(names))
        assert "python_regression" in names
        assert "xvlog_compile" not in names
        assert "xsim_stage2a_suite" not in names
        assert not any(name.startswith("tb_") and
                       (name.endswith("_elab") or name.endswith("_sim"))
                       for name in names)
        for suite, testbenches in (
            ("stage1", stage1_testbenches),
            ("stage2a", STAGE2A_TESTBENCHES),
        ):
            suite_records = [
                item for item in merged["tests"]
                if item["name"].startswith("xsim_{}_".format(suite))
            ]
            expected_pairs = {("xvlog", "COMPILE")}
            expected_pairs.update(
                (testbench, stage)
                for testbench in testbenches for stage in ("ELAB", "SIM")
            )
            actual_pairs = [
                (item.get("source_name"), item.get("stage"))
                for item in suite_records
            ]
            assert len(actual_pairs) == len(expected_pairs)
            assert set(actual_pairs) == expected_pairs

        # Stage-2A collection requires the status file and complete records.
        missing = update_validation_summary(
            {"tests": [python_record]}, stage1_path, missing_path,
            require_stage2a=True,
        )
        assert missing["overall_status"] == "FAIL"
        assert missing["counts"] == {"pass": 18, "fail": 1, "skipped": 0}
        assert missing["stage2a_rtl_satisfied"] is False
        assert "status file" in missing["stage2a_note"]
        assert "missing" in missing["stage2a_note"]

        stage2a_path.write_text("xvlog COMPILE PASS 0\n", encoding="utf-8")
        incomplete = update_validation_summary(
            {"tests": [python_record]}, stage1_path, stage2a_path,
            require_stage2a=True,
        )
        assert incomplete["overall_status"] == "FAIL"
        assert incomplete["stage2a_rtl_satisfied"] is False
        assert "incomplete" in incomplete["stage2a_note"]

        # Ordinary Stage-1 collection must not require Stage-2A evidence.
        stage1_only = update_validation_summary(
            original, stage1_path, missing_path, require_stage2a=False
        )
        assert stage1_only["overall_status"] == "PASS"
        assert stage1_only["counts"] == {"pass": 18, "fail": 0, "skipped": 0}

        # Match the downloaded failure: XSim returned zero despite a fatal marker.
        stage2a_path.write_text(
            "\n".join(status_rows(
                STAGE2A_TESTBENCHES, failing_sim="tb_dense_layer_engine"
            )) + "\n",
            encoding="utf-8",
        )
        failed = update_validation_summary(
            {"tests": [python_record]}, stage2a_status=stage2a_path,
            require_stage2a=True,
        )
        stage2a_tests = [
            item for item in failed["tests"]
            if item["name"].startswith("xsim_stage2a_")
        ]
        assert failed["overall_status"] == "FAIL"
        assert failed["counts"]["fail"] == 1
        assert failed["stage2a_rtl_satisfied"] is False
        assert len(stage2a_tests) == 13
        assert sum(item.get("stage") == "COMPILE" for item in stage2a_tests) == 1
        assert sum(item.get("stage") == "ELAB" for item in stage2a_tests) == 6
        assert sum(item.get("stage") == "SIM" for item in stage2a_tests) == 6
        dense_sim = next(
            item for item in stage2a_tests
            if item.get("source_name") == "tb_dense_layer_engine"
            and item.get("stage") == "SIM"
        )
        assert dense_sim["status"] == "FAIL" and dense_sim["exit_code"] == 0
        assert dense_sim["log"] == "logs/xsim_stage2a_tb_dense_layer_engine.log"

    collector_source = (PROJECT_ROOT / "scripts/collect_validation_bundle.py") \
        .read_text(encoding="utf-8")
    assert "def ensure_validation_summary(require_stage2a=False):" in collector_source
    assert "ensure_validation_summary(require_stage2a=stage2a)" in collector_source

    with tempfile.TemporaryDirectory() as temporary_directory:
        temporary_results = Path(temporary_directory)
        summary_path = temporary_results / "validation_summary.json"
        summary_path.write_text(json.dumps({
            "git_revision": "OLD_OR_UNKNOWN",
            "tests": [{
                "name": "python_regression",
                "category": "python",
                "status": "PASS",
            }],
        }), encoding="utf-8")
        original_results_dir = validation_bundle.RESULTS_DIR
        try:
            validation_bundle.RESULTS_DIR = temporary_results
            validation_bundle.ensure_validation_summary()
        finally:
            validation_bundle.RESULTS_DIR = original_results_dir
        refreshed = json.loads(summary_path.read_text(encoding="utf-8"))
        current_revision, _ = validation_bundle.repository_revision()
        assert current_revision != "OLD_OR_UNKNOWN"
        assert refreshed["git_revision"] == current_revision

    engine_source = (PROJECT_ROOT / "rtl/compute/dense_layer_engine.sv") \
        .read_text(encoding="utf-8")
    assert "ACT_INDEX_WIDTH'(output_index_counter)" in engine_source
    assert "ACT_MAX_DIM < MAX_OUT_DIM" in engine_source
    assert "ACT_INDEX_WIDTH < OUT_INDEX_WIDTH" in engine_source
    assert "{{(ACT_INDEX_WIDTH-OUT_INDEX_WIDTH)" not in engine_source

    return {
        "stage2a_status_records": 13,
        "legacy_stage1_records_deduplicated": True,
        "required_stage2a_missing_fails": True,
        "required_stage2a_incomplete_fails": True,
        "stage1_only_without_stage2a_passes": True,
        "git_revision_refreshed": True,
        "stage2a_failure_forces_overall_fail": True,
        "fatal_with_exit_zero_preserved": True,
        "all_pass_fixture_accepted": True,
    }


def run_tests():
    rng = random.Random(0xF37A2A)
    vector_loader = check_phase1_vector_loader()
    validation_summary = check_validation_summary_merge()

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
        "phase1_vector_loader": vector_loader,
        "validation_summary": validation_summary,
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
