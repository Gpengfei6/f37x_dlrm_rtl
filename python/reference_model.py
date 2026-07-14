"""Floating and bit-accurate reference for the phase-1 recommendation pipeline."""

import argparse
import json
from pathlib import Path

from fixed_point import dense_relu, embedding_aggregate


PROJECT_ROOT = Path(__file__).resolve().parents[1]


def load_json(path):
    with Path(path).open("r", encoding="utf-8") as handle:
        return json.load(handle)


def save_json(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="\n") as handle:
        json.dump(value, handle, indent=2, sort_keys=True)
        handle.write("\n")


class ReferenceModel:
    def __init__(self, config, model_data):
        self.config = config
        self.embeddings = model_data["embeddings"]
        self.weights = model_data["weights"]
        self.biases = model_data["biases"]
        self._validate()

    def _validate(self):
        c = self.config
        if c["dense_in_dim"] != c["embed_dim"]:
            raise ValueError("phase 1 requires dense_in_dim == embed_dim")
        if len(self.embeddings) != c["num_embed_rows"]:
            raise ValueError("embedding row count does not match configuration")
        if any(len(row) != c["embed_dim"] for row in self.embeddings):
            raise ValueError("embedding dimension mismatch")
        if len(self.weights) != c["dense_out_dim"]:
            raise ValueError("dense output dimension mismatch")
        if any(len(row) != c["dense_in_dim"] for row in self.weights):
            raise ValueError("dense input dimension mismatch")
        if len(self.biases) != c["dense_out_dim"]:
            raise ValueError("bias count mismatch")

    @property
    def aggregate_width(self):
        lookup_growth = (self.config["num_lookups"] - 1).bit_length()
        return self.config["data_width"] + lookup_growth

    def fixed_forward(self, ids):
        c = self.config
        if len(ids) != c["num_lookups"]:
            raise ValueError("lookup count mismatch")
        if any(index < 0 or index >= c["num_embed_rows"] for index in ids):
            raise ValueError("embedding ID out of range")
        selected = [self.embeddings[index] for index in ids]
        aggregate = embedding_aggregate(selected, self.aggregate_width)
        accumulators, output = dense_relu(
            aggregate,
            self.weights,
            self.biases,
            c["acc_width"],
            c["output_width"],
            c["output_shift"],
        )
        return {
            "ids": list(ids),
            "embedding_rows": selected,
            "aggregate": aggregate,
            "accumulators": accumulators,
            "output": output,
        }

    def float_forward(self, ids):
        c = self.config
        frac = c["fractional_bits"]
        embedding_scale = float(1 << frac["embedding"])
        weight_scale = float(1 << frac["weight"])
        bias_scale = float(1 << frac["bias"])
        output_scale = float(1 << frac["output"])
        aggregate = [
            sum(self.embeddings[row][lane] / embedding_scale for row in ids)
            for lane in range(c["embed_dim"])
        ]
        pre_activation = []
        output = []
        for weight_row, bias in zip(self.weights, self.biases):
            value = bias / bias_scale
            value += sum(
                item * (weight / weight_scale)
                for item, weight in zip(aggregate, weight_row)
            )
            pre_activation.append(value)
            output.append(max(0.0, value))
        return {
            "ids": list(ids),
            "aggregate": aggregate,
            "pre_activation": pre_activation,
            "output": output,
            "output_raw_scale": output_scale,
        }

    def evaluate(self, ids):
        fixed = self.fixed_forward(ids)
        floating = self.float_forward(ids)
        fixed_as_float = [
            value / floating["output_raw_scale"] for value in fixed["output"]
        ]
        errors = [
            fixed_value - float_value
            for fixed_value, float_value in zip(fixed_as_float, floating["output"])
        ]
        return {
            "fixed": fixed,
            "float": floating,
            "fixed_output_as_float": fixed_as_float,
            "quantization_error": errors,
            "max_abs_quantization_error": max(abs(value) for value in errors),
        }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--config", default=PROJECT_ROOT / "config" / "model_config.json", type=Path
    )
    parser.add_argument(
        "--model", default=PROJECT_ROOT / "tests" / "vectors" / "model_data.json", type=Path
    )
    parser.add_argument(
        "--cases", default=PROJECT_ROOT / "tests" / "vectors" / "test_cases.json", type=Path
    )
    parser.add_argument(
        "--output", default=PROJECT_ROOT / "results" / "reference_run.json", type=Path
    )
    args = parser.parse_args()
    model = ReferenceModel(load_json(args.config), load_json(args.model))
    cases = load_json(args.cases)
    results = []
    for case in cases:
        evaluation = model.evaluate(case["ids"])
        evaluation["name"] = case["name"]
        evaluation["category"] = case["category"]
        results.append(evaluation)
    save_json(args.output, results)
    maximum_error = max(item["max_abs_quantization_error"] for item in results)
    print("reference_model: {} cases, max absolute quantization error {:.8f}".format(
        len(results), maximum_error
    ))


if __name__ == "__main__":
    main()
