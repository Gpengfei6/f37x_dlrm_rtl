#!/usr/bin/env python3
"""Generate a deterministic Stage 2M hybrid-DLRM package for F37X.

The package implements the software DLRM structure used by this repository:

    dense(8)
      -> bottom MLP 8 -> 16 -> 8 on FPGA
      -> CPU embedding lookup for 4 tables
      -> CPU pairwise dot interaction, 18 values
      -> top MLP 18 -> 32 -> 16 -> 1 on FPGA

A small NumPy Adam loop trains the model on a deterministic synthetic dataset.
This is tooling/functional evidence only; it is not real Criteo evidence.

Integer contract:
  * dense, embedding and interaction vectors: signed INT16
  * weights: signed INT8
  * biases: signed INT24 stored in INT32 package words
  * signed 48-bit accumulator
  * round-to-nearest, ties away from zero
  * signed INT16 saturation
  * ReLU on hidden layers
"""

from __future__ import print_function

import argparse
import hashlib
import json
import math
import struct
from pathlib import Path

import numpy as np

MAGIC = b"F37XHD1\0"
FORMAT_VERSION = 1
HEADER_BYTES = 128
HEADER_STRUCT = struct.Struct("<8s20I2Q24x")
LAYER_STRUCT = struct.Struct("<10I")

FLAG_LABELS = 1 << 0
FLAG_EXPECTED_BOTTOM = 1 << 1
FLAG_EXPECTED_INTERACTION = 1 << 2
FLAG_EXPECTED_LOGIT = 1 << 3

MAX_LAYERS = 4
MAX_WEIGHT_VALUES = 65536
MAX_BIAS_VALUES = 1024
ACC_LIMIT = 1 << 47

MODEL_NAME = "stage2m_trained_hybrid_dlrm_8x16x8_interact18_32x16x1"
TABLE_SIZES = (64, 80, 96, 128)
DENSE_DIM = 8
EMBEDDING_DIM = 8
INTERACTION_DIM = 18
BOTTOM_DIMS = (8, 16, 8)
TOP_DIMS = (18, 32, 16, 1)

TRAIN_SAMPLES = 1536
TEST_SAMPLES = 256
TRAIN_EPOCHS = 8
BATCH_SIZE = 128
LEARNING_RATE = 0.003
SEED = 3701

DENSE_SCALE_LOG2 = 11       # 2048
VECTOR_SCALE_LOG2 = 11      # 2048
TOP_HIDDEN_SCALE_LOG2 = 9   # 512
FINAL_SCALE_LOG2 = 8        # 256
WEIGHT_SCALE_LOG2 = 6       # 64
INTERACTION_SHIFT = VECTOR_SCALE_LOG2


class Layer(object):
    def __init__(
        self,
        in_dim,
        out_dim,
        output_shift,
        relu,
        weight_base,
        bias_base,
        input_scale_log2,
        output_scale_log2,
        weights,
        biases,
    ):
        self.in_dim = int(in_dim)
        self.out_dim = int(out_dim)
        self.output_shift = int(output_shift)
        self.relu = bool(relu)
        self.weight_base = int(weight_base)
        self.bias_base = int(bias_base)
        self.input_scale_log2 = int(input_scale_log2)
        self.output_scale_log2 = int(output_scale_log2)
        self.weights = np.asarray(weights, dtype=np.int8)
        self.biases = np.asarray(biases, dtype=np.int32)

    @property
    def weight_count(self):
        return int(self.weights.size)

    @property
    def bias_count(self):
        return int(self.biases.size)


def fnv1a64(data):
    value = 0xCBF29CE484222325
    for byte in data:
        if not isinstance(byte, int):
            byte = ord(byte)
        value ^= byte
        value = (value * 0x100000001B3) & 0xFFFFFFFFFFFFFFFF
    return value


def round_ties_away_from_zero(values, shift):
    values = np.asarray(values, dtype=np.int64)
    if shift == 0:
        return values.copy()
    magnitude = np.abs(values)
    rounded = (magnitude + (1 << (shift - 1))) >> shift
    return np.where(values < 0, -rounded, rounded)


def quantize_accumulator(values, shift, relu):
    values = np.asarray(values, dtype=np.int64)
    if np.any(values <= -ACC_LIMIT) or np.any(values >= ACC_LIMIT):
        raise RuntimeError("signed 48-bit accumulator range exceeded")
    result = round_ties_away_from_zero(values, shift)
    result = np.clip(result, -32768, 32767)
    if relu:
        result = np.maximum(result, 0)
    return result.astype(np.int16)


def generate_dataset(seed, train_count, test_count):
    total = int(train_count) + int(test_count)
    mode = "deterministic"
    mode_seed = sum(
        (index + 1) * ord(value) for index, value in enumerate(mode)
    )
    rng = np.random.default_rng(seed + mode_seed)

    dense = rng.normal(0.0, 1.0, (total, DENSE_DIM)).astype(np.float64)
    categorical = np.empty((total, len(TABLE_SIZES)), dtype=np.int64)
    for table_id, table_size in enumerate(TABLE_SIZES):
        categorical[:, table_id] = rng.integers(
            0, table_size, size=total
        )

    dense_score = dense[:, :4].sum(axis=1)
    categorical_score = np.zeros(total, dtype=np.float64)
    for table_id, table_size in enumerate(TABLE_SIZES):
        categorical_score += (
            (categorical[:, table_id] % 7) - 3
        ) / max(1.0, table_size ** 0.5)

    latent = dense_score + categorical_score
    threshold = float(np.median(latent[:train_count]))
    labels = (latent >= threshold).astype(np.int64)
    return dense, categorical, labels


def initialize_model(seed):
    rng = np.random.default_rng(seed)

    def he(in_dim, out_dim):
        return rng.normal(
            0.0,
            math.sqrt(2.0 / float(in_dim)),
            (in_dim, out_dim),
        ).astype(np.float64)

    model = {
        "bottom_weight_0": he(8, 16),
        "bottom_bias_0": np.zeros(16, dtype=np.float64),
        "bottom_weight_1": he(16, 8),
        "bottom_bias_1": np.zeros(8, dtype=np.float64),
        "top_weight_0": he(18, 32),
        "top_bias_0": np.zeros(32, dtype=np.float64),
        "top_weight_1": he(32, 16),
        "top_bias_1": np.zeros(16, dtype=np.float64),
        "top_weight_2": rng.normal(
            0.0, math.sqrt(1.0 / 16.0), (16, 1)
        ).astype(np.float64),
        "top_bias_2": np.zeros(1, dtype=np.float64),
    }
    for index, table_size in enumerate(TABLE_SIZES):
        model["embedding_{}".format(index)] = rng.normal(
            0.0, 0.1, (table_size, EMBEDDING_DIM)
        ).astype(np.float64)
    return model, rng


def forward_float(model, dense, categorical):
    z0 = dense @ model["bottom_weight_0"] + model["bottom_bias_0"]
    a0 = np.maximum(z0, 0.0)
    z1 = a0 @ model["bottom_weight_1"] + model["bottom_bias_1"]
    bottom = np.maximum(z1, 0.0)

    embedding_vectors = [
        model["embedding_{}".format(index)][categorical[:, index]]
        for index in range(len(TABLE_SIZES))
    ]

    stacked = np.stack([bottom] + embedding_vectors, axis=1)
    gram = stacked @ np.swapaxes(stacked, 1, 2)
    rows, columns = np.tril_indices(len(TABLE_SIZES) + 1, k=-1)
    interaction = np.concatenate(
        (bottom, gram[:, rows, columns]), axis=1
    )

    z2 = interaction @ model["top_weight_0"] + model["top_bias_0"]
    a2 = np.maximum(z2, 0.0)
    z3 = a2 @ model["top_weight_1"] + model["top_bias_1"]
    a3 = np.maximum(z3, 0.0)
    logits = (
        a3 @ model["top_weight_2"] + model["top_bias_2"]
    )[:, 0]

    return {
        "z0": z0,
        "a0": a0,
        "z1": z1,
        "bottom": bottom,
        "embedding_vectors": embedding_vectors,
        "stacked": stacked,
        "interaction": interaction,
        "z2": z2,
        "a2": a2,
        "z3": z3,
        "a3": a3,
        "logits": logits,
    }


def train_model(model, rng, dense, categorical, labels, train_count, epochs):
    parameter_names = [
        "bottom_weight_0",
        "bottom_bias_0",
        "bottom_weight_1",
        "bottom_bias_1",
        "embedding_0",
        "embedding_1",
        "embedding_2",
        "embedding_3",
        "top_weight_0",
        "top_bias_0",
        "top_weight_1",
        "top_bias_1",
        "top_weight_2",
        "top_bias_2",
    ]
    first = {
        name: np.zeros_like(model[name]) for name in parameter_names
    }
    second = {
        name: np.zeros_like(model[name]) for name in parameter_names
    }

    beta1 = 0.9
    beta2 = 0.999
    epsilon = 1.0e-8
    step = 0
    train_indices = np.arange(train_count, dtype=np.int64)

    for _epoch in range(int(epochs)):
        order = rng.permutation(train_indices)
        for start in range(0, train_count, BATCH_SIZE):
            selection = order[start : start + BATCH_SIZE]
            batch_dense = dense[selection]
            batch_categorical = categorical[selection]
            batch_labels = labels[selection].astype(np.float64)
            stages = forward_float(
                model, batch_dense, batch_categorical
            )
            batch_size = float(selection.size)

            logits = stages["logits"]
            sigmoid = 1.0 / (1.0 + np.exp(-np.clip(logits, -60, 60)))
            dlogit = (sigmoid - batch_labels) / batch_size

            gradients = {}
            gradients["top_weight_2"] = (
                stages["a3"].T @ dlogit[:, None]
            )
            gradients["top_bias_2"] = np.array(
                [dlogit.sum()], dtype=np.float64
            )

            da3 = dlogit[:, None] @ model["top_weight_2"].T
            dz3 = da3 * (stages["z3"] > 0.0)
            gradients["top_weight_1"] = stages["a2"].T @ dz3
            gradients["top_bias_1"] = dz3.sum(axis=0)

            da2 = dz3 @ model["top_weight_1"].T
            dz2 = da2 * (stages["z2"] > 0.0)
            gradients["top_weight_0"] = stages["interaction"].T @ dz2
            gradients["top_bias_0"] = dz2.sum(axis=0)

            dinteraction = dz2 @ model["top_weight_0"].T
            dbottom = dinteraction[:, :EMBEDDING_DIM].copy()
            dpairs = dinteraction[:, EMBEDDING_DIM:]

            dstacked = np.zeros_like(stages["stacked"])
            rows, columns = np.tril_indices(
                len(TABLE_SIZES) + 1, k=-1
            )
            for pair_index, pair in enumerate(zip(rows, columns)):
                row, column = pair
                pair_gradient = dpairs[:, pair_index][:, None]
                dstacked[:, row] += (
                    pair_gradient * stages["stacked"][:, column]
                )
                dstacked[:, column] += (
                    pair_gradient * stages["stacked"][:, row]
                )

            dbottom += dstacked[:, 0]
            for table_index, table_size in enumerate(TABLE_SIZES):
                gradient = np.zeros(
                    (table_size, EMBEDDING_DIM), dtype=np.float64
                )
                np.add.at(
                    gradient,
                    batch_categorical[:, table_index],
                    dstacked[:, table_index + 1],
                )
                gradients["embedding_{}".format(table_index)] = gradient

            dz1 = dbottom * (stages["z1"] > 0.0)
            gradients["bottom_weight_1"] = stages["a0"].T @ dz1
            gradients["bottom_bias_1"] = dz1.sum(axis=0)

            da0 = dz1 @ model["bottom_weight_1"].T
            dz0 = da0 * (stages["z0"] > 0.0)
            gradients["bottom_weight_0"] = batch_dense.T @ dz0
            gradients["bottom_bias_0"] = dz0.sum(axis=0)

            step += 1
            for name in parameter_names:
                gradient = gradients[name]
                first[name] = (
                    beta1 * first[name] + (1.0 - beta1) * gradient
                )
                second[name] = (
                    beta2 * second[name]
                    + (1.0 - beta2) * np.square(gradient)
                )
                first_hat = first[name] / (1.0 - beta1 ** step)
                second_hat = second[name] / (1.0 - beta2 ** step)
                model[name] -= (
                    LEARNING_RATE
                    * first_hat
                    / (np.sqrt(second_hat) + epsilon)
                )


def float_accuracy(model, dense, categorical, labels):
    logits = forward_float(model, dense, categorical)["logits"]
    return float(np.mean((logits >= 0.0) == labels))


def quantize_weight(matrix):
    scale = 1 << WEIGHT_SCALE_LOG2
    # Hardware stores each layer out-major.
    values = np.rint(matrix.T * scale)
    if np.any(values < -128) or np.any(values > 127):
        raise RuntimeError("INT8 weight range exceeded")
    return values.astype(np.int8)


def quantize_bias(values, input_scale_log2):
    scale_log2 = input_scale_log2 + WEIGHT_SCALE_LOG2
    quantized = np.rint(values * float(1 << scale_log2)).astype(np.int64)
    if np.any(quantized < -8388608) or np.any(quantized > 8388607):
        raise RuntimeError("INT24 bias range exceeded")
    return quantized.astype(np.int32)


def build_quantized_model(model):
    bottom_weight_base = 0
    bottom_bias_base = 0

    bottom0_weights = quantize_weight(model["bottom_weight_0"])
    bottom0_biases = quantize_bias(
        model["bottom_bias_0"], DENSE_SCALE_LOG2
    )
    bottom0 = Layer(
        8, 16, 6, True,
        bottom_weight_base,
        bottom_bias_base,
        DENSE_SCALE_LOG2,
        VECTOR_SCALE_LOG2,
        bottom0_weights,
        bottom0_biases,
    )

    bottom1_weight_base = bottom0.weight_count
    bottom1_bias_base = bottom0.bias_count
    bottom1_weights = quantize_weight(model["bottom_weight_1"])
    bottom1_biases = quantize_bias(
        model["bottom_bias_1"], VECTOR_SCALE_LOG2
    )
    bottom1 = Layer(
        16, 8, 6, True,
        bottom1_weight_base,
        bottom1_bias_base,
        VECTOR_SCALE_LOG2,
        VECTOR_SCALE_LOG2,
        bottom1_weights,
        bottom1_biases,
    )

    bottom_weight_count = bottom0.weight_count + bottom1.weight_count
    bottom_bias_count = bottom0.bias_count + bottom1.bias_count

    top0_weights = quantize_weight(model["top_weight_0"])
    top0_biases = quantize_bias(
        model["top_bias_0"], VECTOR_SCALE_LOG2
    )
    top0 = Layer(
        18, 32, 6, True,
        bottom_weight_count,
        bottom_bias_count,
        VECTOR_SCALE_LOG2,
        VECTOR_SCALE_LOG2,
        top0_weights,
        top0_biases,
    )

    top1_weight_base = top0.weight_base + top0.weight_count
    top1_bias_base = top0.bias_base + top0.bias_count
    top1_weights = quantize_weight(model["top_weight_1"])
    top1_biases = quantize_bias(
        model["top_bias_1"], VECTOR_SCALE_LOG2
    )
    top1 = Layer(
        32, 16, 8, True,
        top1_weight_base,
        top1_bias_base,
        VECTOR_SCALE_LOG2,
        TOP_HIDDEN_SCALE_LOG2,
        top1_weights,
        top1_biases,
    )

    top2_weight_base = top1.weight_base + top1.weight_count
    top2_bias_base = top1.bias_base + top1.bias_count
    top2_weights = quantize_weight(model["top_weight_2"])
    top2_biases = quantize_bias(
        model["top_bias_2"], TOP_HIDDEN_SCALE_LOG2
    )
    top2 = Layer(
        16, 1, 7, False,
        top2_weight_base,
        top2_bias_base,
        TOP_HIDDEN_SCALE_LOG2,
        FINAL_SCALE_LOG2,
        top2_weights,
        top2_biases,
    )

    embeddings = []
    vector_scale = 1 << VECTOR_SCALE_LOG2
    for table_index in range(len(TABLE_SIZES)):
        values = np.rint(
            model["embedding_{}".format(table_index)] * vector_scale
        )
        if np.any(values < -32768) or np.any(values > 32767):
            raise RuntimeError("INT16 embedding range exceeded")
        embeddings.append(values.astype(np.int16))

    bottom_layers = [bottom0, bottom1]
    top_layers = [top0, top1, top2]

    total_weights = sum(
        layer.weight_count for layer in bottom_layers + top_layers
    )
    total_biases = sum(
        layer.bias_count for layer in bottom_layers + top_layers
    )
    if total_weights > MAX_WEIGHT_VALUES:
        raise RuntimeError("hardware weight capacity exceeded")
    if total_biases > MAX_BIAS_VALUES:
        raise RuntimeError("hardware bias capacity exceeded")
    if len(bottom_layers) > MAX_LAYERS or len(top_layers) > MAX_LAYERS:
        raise RuntimeError("hardware layer-count capacity exceeded")

    return bottom_layers, top_layers, embeddings


def integer_mlp(inputs, layers):
    activations = np.asarray(inputs, dtype=np.int64)
    for layer in layers:
        accumulator = (
            activations @ layer.weights.astype(np.int64).T
            + layer.biases.astype(np.int64)
        )
        activations = quantize_accumulator(
            accumulator, layer.output_shift, layer.relu
        ).astype(np.int64)
    return activations.astype(np.int16)


def integer_interaction(bottom_output, embedding_vectors):
    vectors = [
        np.asarray(bottom_output, dtype=np.int64)
    ] + [
        np.asarray(value, dtype=np.int64)
        for value in embedding_vectors
    ]
    pair_values = []
    for row in range(len(vectors)):
        for column in range(row):
            accumulator = np.sum(
                vectors[row] * vectors[column], axis=1
            )
            pair_values.append(
                quantize_accumulator(
                    accumulator, INTERACTION_SHIFT, False
                )
            )
    interactions = np.stack(pair_values, axis=1)
    return np.concatenate(
        (np.asarray(bottom_output, dtype=np.int16), interactions),
        axis=1,
    ).astype(np.int16)


def pack_layer(layer):
    return LAYER_STRUCT.pack(
        layer.in_dim,
        layer.out_dim,
        layer.output_shift,
        1 if layer.relu else 0,
        layer.weight_base,
        layer.bias_base,
        layer.input_scale_log2,
        layer.output_scale_log2,
        layer.weight_count,
        layer.bias_count,
    )


def write_package(
    output_path,
    manifest_path,
    bottom_layers,
    top_layers,
    embeddings,
    dense_test,
    categorical_test,
    labels_test,
    expected_bottom,
    expected_interaction,
    expected_logits,
    float_train_accuracy,
    float_test_accuracy,
    quantized_train_accuracy,
    quantized_test_accuracy,
):
    payload = bytearray()
    encoded_name = MODEL_NAME.encode("utf-8")
    payload.extend(struct.pack("<I", len(encoded_name)))
    payload.extend(encoded_name)

    for table_size in TABLE_SIZES:
        payload.extend(struct.pack("<I", table_size))
    for layer in bottom_layers:
        payload.extend(pack_layer(layer))
    for layer in top_layers:
        payload.extend(pack_layer(layer))

    for layer in bottom_layers:
        payload.extend(layer.weights.tobytes(order="C"))
    for layer in bottom_layers:
        payload.extend(layer.biases.astype("<i4").tobytes(order="C"))
    for layer in top_layers:
        payload.extend(layer.weights.tobytes(order="C"))
    for layer in top_layers:
        payload.extend(layer.biases.astype("<i4").tobytes(order="C"))
    for table in embeddings:
        payload.extend(table.astype("<i2").tobytes(order="C"))

    for sample_index in range(TEST_SAMPLES):
        payload.extend(
            struct.pack(
                "<II", sample_index, int(labels_test[sample_index])
            )
        )
        payload.extend(
            dense_test[sample_index].astype("<i2").tobytes(order="C")
        )
        payload.extend(
            categorical_test[sample_index]
            .astype("<u4")
            .tobytes(order="C")
        )
        payload.extend(
            expected_bottom[sample_index]
            .astype("<i2")
            .tobytes(order="C")
        )
        payload.extend(
            expected_interaction[sample_index]
            .astype("<i2")
            .tobytes(order="C")
        )
        payload.extend(
            expected_logits[sample_index]
            .astype("<i2")
            .tobytes(order="C")
        )

    bottom_weight_count = sum(
        layer.weight_count for layer in bottom_layers
    )
    bottom_bias_count = sum(
        layer.bias_count for layer in bottom_layers
    )
    top_weight_count = sum(
        layer.weight_count for layer in top_layers
    )
    top_bias_count = sum(
        layer.bias_count for layer in top_layers
    )
    embedding_value_count = sum(table.size for table in embeddings)

    flags = (
        FLAG_LABELS
        | FLAG_EXPECTED_BOTTOM
        | FLAG_EXPECTED_INTERACTION
        | FLAG_EXPECTED_LOGIT
    )
    payload_hash = fnv1a64(payload)
    header = HEADER_STRUCT.pack(
        MAGIC,
        FORMAT_VERSION,
        HEADER_BYTES,
        flags,
        TEST_SAMPLES,
        len(TABLE_SIZES),
        DENSE_DIM,
        EMBEDDING_DIM,
        INTERACTION_DIM,
        len(bottom_layers),
        len(top_layers),
        bottom_weight_count,
        bottom_bias_count,
        top_weight_count,
        top_bias_count,
        embedding_value_count,
        DENSE_SCALE_LOG2,
        VECTOR_SCALE_LOG2,
        TOP_HIDDEN_SCALE_LOG2,
        FINAL_SCALE_LOG2,
        INTERACTION_SHIFT,
        len(payload),
        payload_hash,
    )

    output_path = Path(output_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_bytes(header + payload)
    package_sha256 = hashlib.sha256(output_path.read_bytes()).hexdigest()

    generator_sha256 = hashlib.sha256(
        Path(__file__).read_bytes()
    ).hexdigest()

    manifest = {
        "format": "F37XHD1",
        "format_version": FORMAT_VERSION,
        "model": {
            "name": MODEL_NAME,
            "architecture": {
                "bottom_mlp": list(BOTTOM_DIMS),
                "embedding_tables": list(TABLE_SIZES),
                "embedding_dim": EMBEDDING_DIM,
                "feature_vectors": len(TABLE_SIZES) + 1,
                "interaction_pairs": 10,
                "interaction_output_dim": INTERACTION_DIM,
                "top_mlp": list(TOP_DIMS),
            },
            "execution_partition": {
                "bottom_mlp": "F37X FPGA",
                "embedding_lookup": "CPU host",
                "feature_interaction": "CPU host integer reference",
                "top_mlp": "F37X FPGA",
            },
        },
        "dataset": {
            "source": "deterministic synthetic",
            "seed": SEED,
            "train_samples": TRAIN_SAMPLES,
            "test_samples": TEST_SAMPLES,
            "claim_boundary": (
                "functional hybrid-DLRM validation only; "
                "not real Criteo evidence"
            ),
        },
        "training": {
            "method": "numpy_adam_full_hybrid_dlrm",
            "epochs": TRAIN_EPOCHS,
            "batch_size": BATCH_SIZE,
            "learning_rate": LEARNING_RATE,
            "float_train_accuracy": float_train_accuracy,
            "float_test_accuracy": float_test_accuracy,
        },
        "quantization": {
            "dense_scale_log2": DENSE_SCALE_LOG2,
            "vector_scale_log2": VECTOR_SCALE_LOG2,
            "top_hidden_scale_log2": TOP_HIDDEN_SCALE_LOG2,
            "final_scale_log2": FINAL_SCALE_LOG2,
            "weight_scale_log2": WEIGHT_SCALE_LOG2,
            "interaction_shift": INTERACTION_SHIFT,
            "rounding": "nearest_ties_away_from_zero",
            "activation": "int16",
            "weight": "int8",
            "bias": "int24",
            "accumulator": "signed_int48",
            "quantized_train_accuracy": quantized_train_accuracy,
            "quantized_test_accuracy": quantized_test_accuracy,
            "quantized_test_correct": int(
                round(quantized_test_accuracy * TEST_SAMPLES)
            ),
        },
        "package": {
            "path": str(output_path),
            "bytes": output_path.stat().st_size,
            "sha256": package_sha256,
            "payload_fnv1a64": "0x{:016x}".format(payload_hash),
            "sample_count": TEST_SAMPLES,
            "bottom_weight_values": bottom_weight_count,
            "bottom_bias_values": bottom_bias_count,
            "top_weight_values": top_weight_count,
            "top_bias_values": top_bias_count,
            "embedding_values": embedding_value_count,
        },
        "provenance": {
            "generator": str(Path(__file__)),
            "generator_sha256": generator_sha256,
            "numpy_version": np.__version__,
        },
    }

    manifest_path = Path(manifest_path)
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    manifest_path.write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return manifest


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--output",
        default=(
            "models/stage2m/"
            "stage2m_trained_hybrid_dlrm.f37xhd"
        ),
    )
    parser.add_argument(
        "--manifest",
        default=(
            "models/stage2m/"
            "stage2m_trained_hybrid_dlrm_manifest.json"
        ),
    )
    parser.add_argument("--epochs", type=int, default=TRAIN_EPOCHS)
    args = parser.parse_args()

    if args.epochs != TRAIN_EPOCHS:
        raise ValueError(
            "this deterministic package contract requires epochs={}".format(
                TRAIN_EPOCHS
            )
        )

    dense, categorical, labels = generate_dataset(
        SEED, TRAIN_SAMPLES, TEST_SAMPLES
    )
    model, rng = initialize_model(SEED)
    train_model(
        model,
        rng,
        dense,
        categorical,
        labels,
        TRAIN_SAMPLES,
        TRAIN_EPOCHS,
    )

    train_dense = dense[:TRAIN_SAMPLES]
    train_categorical = categorical[:TRAIN_SAMPLES]
    train_labels = labels[:TRAIN_SAMPLES]
    test_dense = dense[TRAIN_SAMPLES:]
    test_categorical = categorical[TRAIN_SAMPLES:]
    test_labels = labels[TRAIN_SAMPLES:]

    float_train_accuracy = float_accuracy(
        model, train_dense, train_categorical, train_labels
    )
    float_test_accuracy = float_accuracy(
        model, test_dense, test_categorical, test_labels
    )

    bottom_layers, top_layers, embeddings = build_quantized_model(model)

    dense_scale = 1 << DENSE_SCALE_LOG2
    dense_int16 = np.rint(test_dense * dense_scale)
    if np.any(dense_int16 < -32768) or np.any(dense_int16 > 32767):
        raise RuntimeError("INT16 dense input range exceeded")
    dense_int16 = dense_int16.astype(np.int16)

    all_dense_int16 = np.rint(dense * dense_scale).astype(np.int16)
    all_bottom = integer_mlp(all_dense_int16, bottom_layers)
    all_embedding_vectors = [
        embeddings[index][categorical[:, index]]
        for index in range(len(TABLE_SIZES))
    ]
    all_interaction = integer_interaction(
        all_bottom, all_embedding_vectors
    )
    all_logits = integer_mlp(all_interaction, top_layers)[:, 0]
    all_predictions = all_logits >= 0

    quantized_train_accuracy = float(
        np.mean(all_predictions[:TRAIN_SAMPLES] == train_labels)
    )
    quantized_test_accuracy = float(
        np.mean(all_predictions[TRAIN_SAMPLES:] == test_labels)
    )

    expected_bottom = all_bottom[TRAIN_SAMPLES:]
    expected_interaction = all_interaction[TRAIN_SAMPLES:]
    expected_logits = all_logits[TRAIN_SAMPLES:, None]

    manifest = write_package(
        args.output,
        args.manifest,
        bottom_layers,
        top_layers,
        embeddings,
        dense_int16,
        test_categorical,
        test_labels,
        expected_bottom,
        expected_interaction,
        expected_logits,
        float_train_accuracy,
        float_test_accuracy,
        quantized_train_accuracy,
        quantized_test_accuracy,
    )

    print("MODEL_NAME={}".format(MODEL_NAME))
    print("BOTTOM_ARCHITECTURE=8,16,8")
    print("TOP_ARCHITECTURE=18,32,16,1")
    print("TRAIN_SAMPLES={}".format(TRAIN_SAMPLES))
    print("TEST_SAMPLES={}".format(TEST_SAMPLES))
    print(
        "FLOAT_TRAIN_ACCURACY={:.6f}".format(float_train_accuracy)
    )
    print(
        "FLOAT_TEST_ACCURACY={:.6f}".format(float_test_accuracy)
    )
    print(
        "QUANTIZED_TRAIN_ACCURACY={:.6f}".format(
            quantized_train_accuracy
        )
    )
    print(
        "QUANTIZED_TEST_ACCURACY={:.6f}".format(
            quantized_test_accuracy
        )
    )
    print(
        "QUANTIZED_TEST_CORRECT={}".format(
            manifest["quantization"]["quantized_test_correct"]
        )
    )
    print("PACKAGE={}".format(Path(args.output)))
    print("PACKAGE_SHA256={}".format(manifest["package"]["sha256"]))
    print(
        "PAYLOAD_FNV1A64={}".format(
            manifest["package"]["payload_fnv1a64"]
        )
    )
    print("MANIFEST={}".format(Path(args.manifest)))
    print("STAGE2M_HYBRID_PACKAGE_GENERATION_PASS")


if __name__ == "__main__":
    main()
