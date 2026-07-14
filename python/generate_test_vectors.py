"""Generate deterministic phase-1 model images, inputs, and expected outputs."""

import argparse
import json
import random
from pathlib import Path

from fixed_point import encode_twos_complement
from reference_model import PROJECT_ROOT, ReferenceModel, load_json, save_json


def signed_hex(value, width):
    digits = (width + 3) // 4
    return "{:0{}x}".format(encode_twos_complement(value, width), digits)


def write_lines(path, lines):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="ascii", newline="\n") as handle:
        for line in lines:
            handle.write(str(line))
            handle.write("\n")


def build_model(config):
    rng = random.Random(config["random_seed"])
    rows = config["num_embed_rows"]
    dim = config["embed_dim"]
    embeddings = [[rng.randint(-96, 96) for _ in range(dim)] for _ in range(rows)]
    embeddings[0] = [0] * dim
    embeddings[1] = [127] * dim
    embeddings[2] = [-128] * dim
    embeddings[3] = [127 if lane % 2 == 0 else -128 for lane in range(dim)]
    embeddings[4] = [-128 if lane % 2 == 0 else 127 for lane in range(dim)]

    output_dim = config["dense_out_dim"]
    weights = [[rng.randint(-64, 64) for _ in range(dim)] for _ in range(output_dim)]
    if output_dim > 0:
        weights[0] = [127] * dim
    if output_dim > 1:
        weights[1] = [-128] * dim
    if output_dim > 2:
        weights[2] = [127 if lane % 2 == 0 else -128 for lane in range(dim)]
    biases = [rng.randint(-(1 << 17), (1 << 17) - 1) for _ in range(output_dim)]
    if output_dim > 0:
        biases[0] = (1 << (config["bias_width"] - 1)) - 1
    if output_dim > 1:
        biases[1] = -(1 << (config["bias_width"] - 1))
    if output_dim > 2:
        biases[2] = 0
    return {"embeddings": embeddings, "weights": weights, "biases": biases}


def build_cases(config):
    count = config["num_test_cases"]
    lookups = config["num_lookups"]
    rows = config["num_embed_rows"]
    directed = [
        ("all_zero", "all_zero", [0] * lookups),
        ("maximum_positive", "maximum_positive", [1] * lookups),
        ("maximum_negative", "maximum_negative", [2] * lookups),
        ("positive_negative_mix", "positive_negative_mix", [1, 2] * (lookups // 2)),
        ("alternating_mix", "positive_negative_mix", [3, 4] * (lookups // 2)),
        ("repeated_id", "repeated_id", [7] * lookups),
        ("repeated_pairs", "repeated_id", [5, 5, 9, 9][:lookups]),
        ("positive_saturation", "output_saturation", [1] * lookups),
        ("negative_path_relu", "output_saturation", [2] * lookups),
    ]
    cases = [
        {"name": name, "category": category, "ids": ids}
        for name, category, ids in directed
    ]
    rng = random.Random(config["random_seed"] + 1)
    while len(cases) < count:
        index = len(cases)
        ids = [rng.randrange(rows) for _ in range(lookups)]
        cases.append({"name": "random_{:02d}".format(index), "category": "random", "ids": ids})
    return cases[:count]


def pack_lanes(values, width):
    packed = 0
    for lane, value in enumerate(values):
        packed |= encode_twos_complement(value, width) << (lane * width)
    return packed


def generate(config_path=None):
    config_path = Path(config_path or PROJECT_ROOT / "config" / "model_config.json")
    config = load_json(config_path)
    vectors = PROJECT_ROOT / "tests" / "vectors"
    expected_dir = PROJECT_ROOT / "tests" / "expected"
    model_data = build_model(config)
    cases = build_cases(config)
    model = ReferenceModel(config, model_data)

    save_json(vectors / "model_data.json", model_data)
    save_json(vectors / "test_cases.json", cases)

    write_lines(
        vectors / "embedding.hex",
        (
            signed_hex(value, config["data_width"])
            for row in model_data["embeddings"]
            for value in row
        ),
    )
    write_lines(
        vectors / "weights.hex",
        (
            signed_hex(value, config["weight_width"])
            for row in model_data["weights"]
            for value in row
        ),
    )
    write_lines(
        vectors / "biases.hex",
        (signed_hex(value, config["bias_width"]) for value in model_data["biases"]),
    )

    id_width = max(1, (config["num_embed_rows"] - 1).bit_length())
    id_vector_width = id_width * config["num_lookups"]
    output_vector_width = config["output_width"] * config["dense_out_dim"]
    fixed_expected = []
    floating_expected = []
    id_lines = []
    aggregate_lines = []
    output_lines = []
    for case in cases:
        evaluation = model.evaluate(case["ids"])
        fixed_entry = dict(evaluation["fixed"])
        fixed_entry.update({"name": case["name"], "category": case["category"]})
        fixed_expected.append(fixed_entry)
        floating_expected.append(
            {
                "name": case["name"],
                "category": case["category"],
                "float": evaluation["float"],
                "fixed_output_as_float": evaluation["fixed_output_as_float"],
                "quantization_error": evaluation["quantization_error"],
                "max_abs_quantization_error": evaluation["max_abs_quantization_error"],
            }
        )
        id_lines.append("{:0{}x}".format(
            pack_lanes(case["ids"], id_width), (id_vector_width + 3) // 4
        ))
        aggregate_lines.append("{:0{}x}".format(
            pack_lanes(fixed_entry["aggregate"], model.aggregate_width),
            (model.aggregate_width * config["dense_in_dim"] + 3) // 4,
        ))
        output_lines.append("{:0{}x}".format(
            pack_lanes(fixed_entry["output"], config["output_width"]),
            (output_vector_width + 3) // 4,
        ))

    save_json(expected_dir / "top_expected.json", fixed_expected)
    save_json(expected_dir / "float_expected.json", floating_expected)
    write_lines(vectors / "top_case_ids.hex", id_lines)
    write_lines(vectors / "dense_inputs.hex", aggregate_lines)
    write_lines(expected_dir / "dense_outputs.hex", output_lines)
    write_lines(expected_dir / "top_outputs.hex", output_lines)

    overflow_inputs = [508] * config["dense_in_dim"]
    overflow_weights = [127] * config["dense_in_dim"]
    save_json(
        vectors / "directed_arithmetic_cases.json",
        {
            "accumulator_overflow": {
                "inputs": overflow_inputs,
                "weights": overflow_weights,
                "bias": 0,
                "acc_width": 16
            },
            "rounding_boundaries_shift4": [7, 8, 23, 24, -7, -8, -23, -24],
            "saturation_inputs": [2147483647, -2147483648]
        },
    )
    print("generate_test_vectors: wrote {} deterministic cases (seed {})".format(
        len(cases), config["random_seed"]
    ))
    return model_data, cases, fixed_expected


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, default=PROJECT_ROOT / "config" / "model_config.json")
    args = parser.parse_args()
    generate(args.config)


if __name__ == "__main__":
    main()
