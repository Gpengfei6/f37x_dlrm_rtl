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
    decode_twos_complement,
    dot_product,
    round_shift_nearest_away,
    saturating_round,
    wrap_signed,
)
from generate_test_vectors import generate, pack_lanes, write_lines  # noqa: E402
from reference_model import ReferenceModel, load_json  # noqa: E402


def run_tests():
    config = load_json(PROJECT_ROOT / "config" / "model_config.json")
    assert config["fractional_bits"]["embedding"] == 4
    assert config["fractional_bits"]["weight"] == 4
    assert config["fractional_bits"]["bias"] == 8
    assert config["fractional_bits"]["accumulator"] == 8
    assert config["fractional_bits"]["output"] == 4
    assert config["output_shift"] == 4
    # Four INT8 values span [-512, 508]: ten signed bits are necessary and enough.
    assert -(1 << 9) <= 4 * -128
    assert 4 * 127 <= (1 << 9) - 1
    assert 4 * -128 < -(1 << 8)

    # Re-derive ties-away rounding without calling the implementation under test.
    for value in range(-4096, 4097):
        magnitude = abs(value)
        quotient, remainder = divmod(magnitude, 16)
        if remainder >= 8:
            quotient += 1
        independent = -quotient if value < 0 else quotient
        assert round_shift_nearest_away(value, 4) == independent
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

    # Re-read every checked-in hex image as two's complement and compare it with
    # the JSON model.  This independently checks file interpretation and order.
    def read_signed_hex(path, width):
        return [
            decode_twos_complement(int(line.strip(), 16), width)
            for line in path.read_text(encoding="ascii").splitlines()
            if line.strip()
        ]

    assert read_signed_hex(
        PROJECT_ROOT / "tests" / "vectors" / "embedding.hex",
        config["data_width"],
    ) == [value for row in model_data["embeddings"] for value in row]
    assert read_signed_hex(
        PROJECT_ROOT / "tests" / "vectors" / "weights.hex",
        config["weight_width"],
    ) == [value for row in model_data["weights"] for value in row]
    assert read_signed_hex(
        PROJECT_ROOT / "tests" / "vectors" / "biases.hex",
        config["bias_width"],
    ) == model_data["biases"]

    id_width = max(1, (config["num_embed_rows"] - 1).bit_length())
    packed_ids = [
        int(line, 16)
        for line in (PROJECT_ROOT / "tests" / "vectors" / "top_case_ids.hex")
        .read_text(encoding="ascii").splitlines() if line
    ]
    for packed, case in zip(packed_ids, cases):
        unpacked = [
            (packed >> (lane * id_width)) & ((1 << id_width) - 1)
            for lane in range(config["num_lookups"])
        ]
        assert unpacked == case["ids"]

    packed_outputs = [
        int(line, 16)
        for line in (PROJECT_ROOT / "tests" / "expected" / "top_outputs.hex")
        .read_text(encoding="ascii").splitlines() if line
    ]
    for packed, record in zip(packed_outputs, expected):
        unpacked = [
            decode_twos_complement(
                (packed >> (lane * config["output_width"])) &
                ((1 << config["output_width"]) - 1),
                config["output_width"],
            )
            for lane in range(config["dense_out_dim"])
        ]
        assert unpacked == record["output"]

    narrow_inputs = [508] * config["dense_in_dim"]
    narrow_weights = [127] * config["dense_in_dim"]
    full_precision = sum(a * b for a, b in zip(narrow_inputs, narrow_weights))
    wrapped = dot_product(narrow_inputs, narrow_weights, 0, 16)
    assert wrapped == wrap_signed(full_precision, 16)
    assert wrapped != full_precision
    int32_full = (1 << 31) - 1 + sum([131071 * 127] * 8)
    int32_wrapped = dot_product([131071] * 8, [127] * 8, (1 << 31) - 1, 32)
    assert int32_wrapped == wrap_signed(int32_full, 32)

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
    testbench_paths = sorted((PROJECT_ROOT / "tb").glob("tb_*.sv"))
    required_stage1_testbenches = {
        "tb_rv_fifo", "tb_saturating_round", "tb_relu_quant",
        "tb_dot_product_core", "tb_dense_layer_core",
        "tb_embedding_mem_model", "tb_minimal_recommendation_pipeline",
        "tb_dlrm_minimal_top",
    }
    required_stage2a_testbenches = {
        "tb_mac_lane", "tb_runtime_relu_quant",
        "tb_banked_activation_buffer", "tb_local_weight_provider",
        "tb_vector_dot_product_core", "tb_dense_layer_engine",
    }
    discovered_testbenches = {path.stem for path in testbench_paths}
    testbench_guards_ok = (
        required_stage1_testbenches.issubset(discovered_testbenches) and
        required_stage2a_testbenches.issubset(discovered_testbenches) and all(
            "timeout_guard" in path.read_text(encoding="utf-8") and
            (path.stem + ": PASS") in path.read_text(encoding="utf-8")
            for path in testbench_paths
        )
    )
    assert testbench_guards_ok
    timescale = "`timescale 1ns/1ps"
    rtl_module_paths = sorted(
        path for path in (PROJECT_ROOT / "rtl").rglob("*.sv")
        if path.name != "dlrm_config_pkg.sv"
    )
    required_stage2a_modules = {
        "mac_lane.sv", "runtime_relu_quant.sv",
        "banked_activation_buffer.sv", "local_weight_provider.sv",
        "vector_dot_product_core.sv", "dense_layer_engine.sv",
    }
    timescale_contract_ok = (
        required_stage2a_modules.issubset({path.name for path in rtl_module_paths}) and
        all(path.read_text(encoding="utf-8").splitlines()[0] == timescale
            for path in rtl_module_paths) and
        all(path.read_text(encoding="utf-8").splitlines()[0] == timescale
            for path in testbench_paths) and
        not (PROJECT_ROOT / "rtl" / "include" / "dlrm_config_pkg.sv")
        .read_text(encoding="utf-8").startswith("`timescale")
    )
    assert timescale_contract_ok
    dense_source = (
        PROJECT_ROOT / "rtl" / "compute" / "dense_layer_core.sv"
    ).read_text(encoding="utf-8")
    dense_loop_scope_ok = (
        "integer index;" not in dense_source and
        "integer init_index;" in dense_source and
        "integer pack_index;" in dense_source and
        "integer reset_index;" in dense_source
    )
    assert dense_loop_scope_ok
    fifo_tb = (PROJECT_ROOT / "tb" / "tb_rv_fifo.sv").read_text(
        encoding="utf-8"
    )
    dot_tb = (PROJECT_ROOT / "tb" / "tb_dot_product_core.sv").read_text(
        encoding="utf-8"
    )
    embedding_tb = (
        PROJECT_ROOT / "tb" / "tb_embedding_mem_model.sv"
    ).read_text(encoding="utf-8")
    elastic_replacement_guards_ok = (
        "depth1_dut" in fifo_tb and
        "cycle < DEPTH*2" in fifo_tb and
        "depth-one FIFO blocked replacement" in fifo_tb and
        "third_inputs" in dot_tb and
        "blocked consecutive same-edge replacement" in dot_tb and
        "third_id" in embedding_tb and
        "blocked consecutive replacement request" in embedding_tb
    )
    assert elastic_replacement_guards_ok
    fifo_source = (PROJECT_ROOT / "rtl" / "common" / "rv_fifo.sv").read_text(
        encoding="utf-8"
    )
    dot_source = (
        PROJECT_ROOT / "rtl" / "compute" / "dot_product_core.sv"
    ).read_text(encoding="utf-8")
    embedding_source = (
        PROJECT_ROOT / "rtl" / "memory" / "embedding_mem_model.sv"
    ).read_text(encoding="utf-8")
    elastic_rtl_contract_ok = (
        "assign in_ready = !full || pop;" in fifo_source and
        "case ({push, pop})" in fifo_source and
        "assign in_ready = !out_valid || out_ready;" in dot_source and
        "else if (in_ready) begin" in dot_source and
        "assign req_ready = !rsp_valid || rsp_ready;" in embedding_source and
        "else if (req_ready) begin" in embedding_source
    )
    assert elastic_rtl_contract_ok
    return {
        "status": "PASS",
        "case_count": len(cases),
        "seed": config["random_seed"],
        "categories": sorted(categories),
        "narrow_accumulator_full_precision": full_precision,
        "narrow_accumulator_wrapped_int16": wrapped,
        "int32_wrap_rederived": int32_wrapped,
        "self_compare_count": report["rtl_count"],
        "directed_saturation_observed": True,
        "relu_zero_observed": True,
        "packed_lane_zero_is_lsb": True,
        "hex_twos_complement_roundtrip": True,
        "testbench_timeout_guards": testbench_guards_ok,
        "testbench_count": len(testbench_paths),
        "rtl_module_count": len(rtl_module_paths),
        "timescale_contract": timescale_contract_ok,
        "dense_process_local_loop_indices": dense_loop_scope_ok,
        "elastic_replacement_guards": elastic_replacement_guards_ok,
        "elastic_rtl_contract": elastic_rtl_contract_ok,
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
