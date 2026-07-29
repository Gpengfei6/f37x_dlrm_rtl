#!/usr/bin/env python3
"""Build the Stage 2N-A11 automatic-pipeline batch asset.

Input:
    models/stage2m/stage2m_trained_hybrid_dlrm.f37xhd

Outputs:
    build/stage2n_a11/assets_v1/stage2n_a11_real_model_batch_v1.f37xpb
    results/stage2n_a11/assets_v1/stage2n_a11_real_model_batch_v1_manifest.json
    results/stage2n_a11/assets_v1/stage2n_a11_real_model_batch_v1_samples.csv
    results/stage2n_a11/assets_v1/stage2n_a11_real_model_batch_v1_status.txt

The generated asset is tailored to the Stage 2N-A10 automatic pipeline:
five descriptors, 1,360 INT8 weights, 73 INT24-compatible biases,
four resolved embedding vectors per sample, one eight-value dense vector,
and one expected final logit per sample.

This script performs no FPGA access.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import struct
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import BinaryIO, Iterable, List, Sequence, Tuple

SOURCE_MAGIC = b"F37XHD1\x00"
SOURCE_VERSION = 1
SOURCE_HEADER_BYTES = 128
SOURCE_HEADER = struct.Struct("<8s20I5Q")
SOURCE_LAYER = struct.Struct("<10I")

OUTPUT_MAGIC = b"F37XPB1"
OUTPUT_VERSION = 1
OUTPUT_HEADER_BYTES = 128
OUTPUT_HEADER_FIXED = struct.Struct("<8s15I5Q")
OUTPUT_DESCRIPTOR_WORDS = struct.Struct("<3I")

FLAG_LABELS = 1 << 0
FLAG_EXPECTED_BOTTOM = 1 << 1
FLAG_EXPECTED_INTERACTION = 1 << 2
FLAG_EXPECTED_LOGIT = 1 << 3
REQUIRED_SOURCE_FLAGS = (
    FLAG_LABELS
    | FLAG_EXPECTED_BOTTOM
    | FLAG_EXPECTED_INTERACTION
    | FLAG_EXPECTED_LOGIT
)

OUTPUT_FLAG_LABELS = 1 << 0
OUTPUT_FLAG_CATEGORICAL_IDS = 1 << 1
OUTPUT_FLAG_RESOLVED_EMBEDDINGS = 1 << 2
OUTPUT_FLAG_EXPECTED_BOTTOM = 1 << 3
OUTPUT_FLAG_EXPECTED_INTERACTION = 1 << 4
OUTPUT_FLAG_EXPECTED_LOGIT = 1 << 5
OUTPUT_FLAG_EXPECTED_PREDICTION = 1 << 6

EXPECTED_SOURCE_SHA256 = (
    "b953289de8910f8402c4eefb79c516ab7d2468dba34fcc44532b9469cdcb2b3b"
)
EXPECTED_SAMPLE_COUNT = 256
EXPECTED_TABLE_SIZES = [64, 80, 96, 128]
EXPECTED_DENSE_DIM = 8
EXPECTED_EMBEDDING_DIM = 8
EXPECTED_INTERACTION_DIM = 18
EXPECTED_BOTTOM_LAYERS = 2
EXPECTED_TOP_LAYERS = 3
EXPECTED_DESCRIPTOR_COUNT = 5
EXPECTED_WEIGHT_COUNT = 1360
EXPECTED_BIAS_COUNT = 73
EXPECTED_INTERACTION_SHIFT = 11
EXPECTED_CORRECT = 228
EXPECTED_ACCURACY = 0.890625

MAX_ACC_MAGNITUDE = 1 << 47
INT16_MIN = -(1 << 15)
INT16_MAX = (1 << 15) - 1
INT24_MIN = -(1 << 23)
INT24_MAX = (1 << 23) - 1


class AssetError(RuntimeError):
    """Raised when source or generated assets violate the A11 contract."""


@dataclass
class Layer:
    in_dim: int
    out_dim: int
    output_shift: int
    relu: bool
    weight_base: int
    bias_base: int
    input_scale_log2: int
    output_scale_log2: int
    weight_count: int
    bias_count: int
    weights: List[int]
    biases: List[int]


@dataclass
class Sample:
    sample_id: int
    label: int
    dense: List[int]
    categorical_ids: List[int]
    expected_bottom: List[int]
    expected_interaction: List[int]
    expected_logit: List[int]


@dataclass
class SourcePackage:
    name: str
    flags: int
    table_sizes: List[int]
    dense_dim: int
    embedding_dim: int
    interaction_dim: int
    interaction_shift: int
    payload_fnv1a64: int
    bottom_layers: List[Layer]
    top_layers: List[Layer]
    embeddings: List[List[int]]
    samples: List[Sample]


class Reader:
    def __init__(self, data: bytes, offset: int = 0) -> None:
        self.data = data
        self.offset = offset

    def _take(self, size: int) -> bytes:
        end = self.offset + size
        if end > len(self.data):
            raise AssetError(
                f"truncated package: need {size} bytes at offset {self.offset}"
            )
        chunk = self.data[self.offset:end]
        self.offset = end
        return chunk

    def u32(self) -> int:
        return struct.unpack("<I", self._take(4))[0]

    def u64(self) -> int:
        return struct.unpack("<Q", self._take(8))[0]

    def i16_values(self, count: int) -> List[int]:
        if count < 0:
            raise AssetError("negative i16 count")
        return list(struct.unpack(f"<{count}h", self._take(2 * count)))

    def u32_values(self, count: int) -> List[int]:
        if count < 0:
            raise AssetError("negative u32 count")
        return list(struct.unpack(f"<{count}I", self._take(4 * count)))

    def i32_values(self, count: int) -> List[int]:
        if count < 0:
            raise AssetError("negative i32 count")
        return list(struct.unpack(f"<{count}i", self._take(4 * count)))

    def i8_values(self, count: int) -> List[int]:
        if count < 0:
            raise AssetError("negative i8 count")
        return list(struct.unpack(f"<{count}b", self._take(count)))


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def fnv1a64(data: bytes) -> int:
    value = 0xCBF29CE484222325
    for byte in data:
        value ^= byte
        value = (value * 0x100000001B3) & 0xFFFFFFFFFFFFFFFF
    return value


def round_ties_away_from_zero(value: int, shift: int) -> int:
    if shift < 0:
        raise AssetError(f"negative shift: {shift}")
    if shift == 0:
        return value
    magnitude = abs(value)
    rounded = (magnitude + (1 << (shift - 1))) >> shift
    return -rounded if value < 0 else rounded


def quantize_accumulator(value: int, shift: int, relu: bool) -> int:
    if value <= -MAX_ACC_MAGNITUDE or value >= MAX_ACC_MAGNITUDE:
        raise AssetError(f"signed INT48 accumulator overflow: {value}")
    result = round_ties_away_from_zero(value, shift)
    result = max(INT16_MIN, min(INT16_MAX, result))
    if relu and result < 0:
        result = 0
    return result


def software_mlp(layers: Sequence[Layer], inputs: Sequence[int]) -> List[int]:
    activations = list(inputs)
    for layer_index, layer in enumerate(layers):
        if len(activations) != layer.in_dim:
            raise AssetError(
                f"layer {layer_index} input mismatch: "
                f"{len(activations)} != {layer.in_dim}"
            )
        outputs: List[int] = []
        for output_index in range(layer.out_dim):
            accumulator = layer.biases[output_index]
            base = output_index * layer.in_dim
            for input_index, activation in enumerate(activations):
                accumulator += activation * layer.weights[base + input_index]
            outputs.append(
                quantize_accumulator(
                    accumulator, layer.output_shift, layer.relu
                )
            )
        activations = outputs
    return activations


def software_interaction(
    bottom: Sequence[int],
    embedding_vectors: Sequence[Sequence[int]],
    shift: int,
) -> List[int]:
    vectors = [list(bottom)] + [list(v) for v in embedding_vectors]
    if any(len(v) != EXPECTED_EMBEDDING_DIM for v in vectors):
        raise AssetError("interaction vector dimension mismatch")

    pairs: List[int] = []
    for row in range(len(vectors)):
        for column in range(row):
            accumulator = sum(
                vectors[row][index] * vectors[column][index]
                for index in range(EXPECTED_EMBEDDING_DIM)
            )
            pairs.append(quantize_accumulator(accumulator, shift, False))

    result = list(bottom) + pairs
    if len(result) != EXPECTED_INTERACTION_DIM:
        raise AssetError(
            f"interaction output mismatch: {len(result)} "
            f"!= {EXPECTED_INTERACTION_DIM}"
        )
    return result


def read_source_package(path: Path) -> SourcePackage:
    data = path.read_bytes()
    digest = sha256_bytes(data)
    if digest != EXPECTED_SOURCE_SHA256:
        raise AssetError(
            "source package SHA256 mismatch: "
            f"expected {EXPECTED_SOURCE_SHA256}, got {digest}"
        )
    if len(data) < SOURCE_HEADER_BYTES:
        raise AssetError("source package is smaller than its header")

    values = SOURCE_HEADER.unpack_from(data, 0)
    magic = values[0]
    u32 = list(values[1:21])
    u64 = list(values[21:26])

    (
        version,
        header_bytes,
        flags,
        sample_count,
        num_tables,
        dense_dim,
        embedding_dim,
        interaction_dim,
        bottom_layer_count,
        top_layer_count,
        bottom_weight_count,
        bottom_bias_count,
        top_weight_count,
        top_bias_count,
        embedding_value_count,
        dense_scale_log2,
        vector_scale_log2,
        top_hidden_scale_log2,
        final_scale_log2,
        interaction_shift,
    ) = u32

    payload_bytes, expected_payload_hash, reserved0, reserved1, reserved2 = u64

    if magic != SOURCE_MAGIC:
        raise AssetError(f"source magic mismatch: {magic!r}")
    if version != SOURCE_VERSION or header_bytes != SOURCE_HEADER_BYTES:
        raise AssetError("unsupported source package version/header")
    if (flags & REQUIRED_SOURCE_FLAGS) != REQUIRED_SOURCE_FLAGS:
        raise AssetError("source package required flags are missing")
    if any((reserved0, reserved1, reserved2)):
        raise AssetError("source package reserved field is nonzero")
    if payload_bytes != len(data) - SOURCE_HEADER_BYTES:
        raise AssetError("source payload byte count mismatch")

    payload = data[SOURCE_HEADER_BYTES:]
    observed_payload_hash = fnv1a64(payload)
    if observed_payload_hash != expected_payload_hash:
        raise AssetError(
            "source payload FNV1a64 mismatch: "
            f"expected 0x{expected_payload_hash:016x}, "
            f"got 0x{observed_payload_hash:016x}"
        )

    expected_scalars = {
        "sample_count": (sample_count, EXPECTED_SAMPLE_COUNT),
        "num_tables": (num_tables, len(EXPECTED_TABLE_SIZES)),
        "dense_dim": (dense_dim, EXPECTED_DENSE_DIM),
        "embedding_dim": (embedding_dim, EXPECTED_EMBEDDING_DIM),
        "interaction_dim": (interaction_dim, EXPECTED_INTERACTION_DIM),
        "bottom_layer_count": (
            bottom_layer_count,
            EXPECTED_BOTTOM_LAYERS,
        ),
        "top_layer_count": (top_layer_count, EXPECTED_TOP_LAYERS),
        "total_weight_count": (
            bottom_weight_count + top_weight_count,
            EXPECTED_WEIGHT_COUNT,
        ),
        "total_bias_count": (
            bottom_bias_count + top_bias_count,
            EXPECTED_BIAS_COUNT,
        ),
        "embedding_value_count": (
            embedding_value_count,
            sum(EXPECTED_TABLE_SIZES) * EXPECTED_EMBEDDING_DIM,
        ),
        "interaction_shift": (
            interaction_shift,
            EXPECTED_INTERACTION_SHIFT,
        ),
    }
    for name, (actual, expected) in expected_scalars.items():
        if actual != expected:
            raise AssetError(f"{name} mismatch: {actual} != {expected}")

    reader = Reader(payload)
    name_bytes = reader.u32()
    if not 1 <= name_bytes <= 4096:
        raise AssetError(f"invalid model name length: {name_bytes}")
    name = reader._take(name_bytes).decode("utf-8")

    table_sizes = reader.u32_values(num_tables)
    if table_sizes != EXPECTED_TABLE_SIZES:
        raise AssetError(
            f"embedding table sizes mismatch: {table_sizes} "
            f"!= {EXPECTED_TABLE_SIZES}"
        )

    def read_layer_descriptors(count: int) -> List[Layer]:
        layers: List[Layer] = []
        for index in range(count):
            fields = SOURCE_LAYER.unpack(reader._take(SOURCE_LAYER.size))
            (
                in_dim,
                out_dim,
                output_shift,
                relu_raw,
                weight_base,
                bias_base,
                input_scale,
                output_scale,
                weight_count,
                bias_count,
            ) = fields
            if relu_raw not in (0, 1):
                raise AssetError(f"invalid ReLU flag at layer {index}")
            if weight_count != in_dim * out_dim:
                raise AssetError(f"weight count mismatch at layer {index}")
            if bias_count != out_dim:
                raise AssetError(f"bias count mismatch at layer {index}")
            layers.append(
                Layer(
                    in_dim=in_dim,
                    out_dim=out_dim,
                    output_shift=output_shift,
                    relu=bool(relu_raw),
                    weight_base=weight_base,
                    bias_base=bias_base,
                    input_scale_log2=input_scale,
                    output_scale_log2=output_scale,
                    weight_count=weight_count,
                    bias_count=bias_count,
                    weights=[],
                    biases=[],
                )
            )
        return layers

    bottom_layers = read_layer_descriptors(bottom_layer_count)
    top_layers = read_layer_descriptors(top_layer_count)

    for layer in bottom_layers:
        layer.weights = reader.i8_values(layer.weight_count)
    for layer in bottom_layers:
        layer.biases = reader.i32_values(layer.bias_count)
    for layer in top_layers:
        layer.weights = reader.i8_values(layer.weight_count)
    for layer in top_layers:
        layer.biases = reader.i32_values(layer.bias_count)

    for layer_index, layer in enumerate(bottom_layers + top_layers):
        if any(value < INT24_MIN or value > INT24_MAX for value in layer.biases):
            raise AssetError(f"INT24 bias range exceeded at layer {layer_index}")

    embeddings: List[List[int]] = []
    observed_embedding_values = 0
    for table_size in table_sizes:
        count = table_size * embedding_dim
        embeddings.append(reader.i16_values(count))
        observed_embedding_values += count
    if observed_embedding_values != embedding_value_count:
        raise AssetError("embedding value count mismatch after parsing")

    samples: List[Sample] = []
    for sample_index in range(sample_count):
        sample_id = reader.u32()
        label = reader.u32()
        dense = reader.i16_values(dense_dim)
        categorical_ids = reader.u32_values(num_tables)
        expected_bottom = reader.i16_values(embedding_dim)
        expected_interaction = reader.i16_values(interaction_dim)
        expected_logit = reader.i16_values(1)

        if sample_id != sample_index:
            raise AssetError(
                f"sample id mismatch at index {sample_index}: {sample_id}"
            )
        if label not in (0, 1):
            raise AssetError(f"invalid label at sample {sample_id}: {label}")
        for table_index, categorical_id in enumerate(categorical_ids):
            if categorical_id >= table_sizes[table_index]:
                raise AssetError(
                    f"categorical id out of range at sample {sample_id}, "
                    f"table {table_index}: {categorical_id}"
                )

        samples.append(
            Sample(
                sample_id=sample_id,
                label=label,
                dense=dense,
                categorical_ids=categorical_ids,
                expected_bottom=expected_bottom,
                expected_interaction=expected_interaction,
                expected_logit=expected_logit,
            )
        )

    if reader.offset != len(payload):
        raise AssetError(
            f"source payload trailing bytes: {len(payload) - reader.offset}"
        )

    package = SourcePackage(
        name=name,
        flags=flags,
        table_sizes=table_sizes,
        dense_dim=dense_dim,
        embedding_dim=embedding_dim,
        interaction_dim=interaction_dim,
        interaction_shift=interaction_shift,
        payload_fnv1a64=observed_payload_hash,
        bottom_layers=bottom_layers,
        top_layers=top_layers,
        embeddings=embeddings,
        samples=samples,
    )
    validate_package_reference(package)
    return package


def resolved_embeddings(
    package: SourcePackage, sample: Sample
) -> List[List[int]]:
    result: List[List[int]] = []
    for table_index, categorical_id in enumerate(sample.categorical_ids):
        start = categorical_id * package.embedding_dim
        end = start + package.embedding_dim
        result.append(package.embeddings[table_index][start:end])
    return result


def validate_package_reference(package: SourcePackage) -> None:
    bottom_exact = 0
    interaction_exact = 0
    top_exact = 0
    classification_correct = 0

    for sample in package.samples:
        bottom = software_mlp(package.bottom_layers, sample.dense)
        if bottom != sample.expected_bottom:
            raise AssetError(
                f"bottom reference mismatch at sample {sample.sample_id}"
            )
        bottom_exact += 1

        embeddings = resolved_embeddings(package, sample)
        interaction = software_interaction(
            bottom, embeddings, package.interaction_shift
        )
        if interaction != sample.expected_interaction:
            raise AssetError(
                f"interaction reference mismatch at sample {sample.sample_id}"
            )
        interaction_exact += 1

        logit = software_mlp(package.top_layers, interaction)
        if logit != sample.expected_logit:
            raise AssetError(
                f"top reference mismatch at sample {sample.sample_id}"
            )
        top_exact += 1

        prediction = 1 if logit[0] >= 0 else 0
        if prediction == sample.label:
            classification_correct += 1

    if bottom_exact != EXPECTED_SAMPLE_COUNT:
        raise AssetError("bottom exact-count mismatch")
    if interaction_exact != EXPECTED_SAMPLE_COUNT:
        raise AssetError("interaction exact-count mismatch")
    if top_exact != EXPECTED_SAMPLE_COUNT:
        raise AssetError("top exact-count mismatch")
    if classification_correct != EXPECTED_CORRECT:
        raise AssetError(
            f"classification count mismatch: "
            f"{classification_correct} != {EXPECTED_CORRECT}"
        )


def pack_descriptor(layer: Layer) -> Tuple[int, int, int]:
    value = 0
    value |= layer.in_dim & 0x7FF
    value |= (layer.out_dim & 0x7FF) << 11
    value |= layer.weight_base << 22
    value |= layer.bias_base << 54
    value |= (layer.output_shift & 0x3F) << 86
    value |= (1 if layer.relu else 0) << 92
    return (
        value & 0xFFFFFFFF,
        (value >> 32) & 0xFFFFFFFF,
        (value >> 64) & 0xFFFFFFFF,
    )


def flatten_weights(layers: Sequence[Layer]) -> List[int]:
    size = max(layer.weight_base + layer.weight_count for layer in layers)
    values: List[int | None] = [None] * size
    for layer in layers:
        for index, value in enumerate(layer.weights):
            address = layer.weight_base + index
            if values[address] is not None:
                raise AssetError(f"overlapping weight address: {address}")
            values[address] = value
    if any(value is None for value in values):
        first = next(i for i, value in enumerate(values) if value is None)
        raise AssetError(f"unassigned weight address: {first}")
    return [int(value) for value in values]


def flatten_biases(layers: Sequence[Layer]) -> List[int]:
    size = max(layer.bias_base + layer.bias_count for layer in layers)
    values: List[int | None] = [None] * size
    for layer in layers:
        for index, value in enumerate(layer.biases):
            address = layer.bias_base + index
            if values[address] is not None:
                raise AssetError(f"overlapping bias address: {address}")
            values[address] = value
    if any(value is None for value in values):
        first = next(i for i, value in enumerate(values) if value is None)
        raise AssetError(f"unassigned bias address: {first}")
    return [int(value) for value in values]


def build_output_payload(
    package: SourcePackage,
) -> Tuple[bytes, List[dict], List[Tuple[int, int, int]]]:
    layers = package.bottom_layers + package.top_layers
    descriptors = [pack_descriptor(layer) for layer in layers]
    weights = flatten_weights(layers)
    biases = flatten_biases(layers)

    if len(descriptors) != EXPECTED_DESCRIPTOR_COUNT:
        raise AssetError("descriptor count mismatch")
    if len(weights) != EXPECTED_WEIGHT_COUNT:
        raise AssetError("flattened weight count mismatch")
    if len(biases) != EXPECTED_BIAS_COUNT:
        raise AssetError("flattened bias count mismatch")

    payload = bytearray()
    encoded_name = package.name.encode("utf-8")
    payload.extend(struct.pack("<I", len(encoded_name)))
    payload.extend(encoded_name)

    for descriptor in descriptors:
        payload.extend(OUTPUT_DESCRIPTOR_WORDS.pack(*descriptor))
    payload.extend(struct.pack(f"<{len(weights)}b", *weights))
    payload.extend(struct.pack(f"<{len(biases)}i", *biases))

    sample_rows: List[dict] = []
    sample_struct = struct.Struct(
        "<II4I8h32h8h18hhIH"
    )

    for sample in package.samples:
        embeddings = resolved_embeddings(package, sample)
        flat_embeddings = [
            value for vector in embeddings for value in vector
        ]
        prediction = 1 if sample.expected_logit[0] >= 0 else 0
        payload.extend(
            sample_struct.pack(
                sample.sample_id,
                sample.label,
                *sample.categorical_ids,
                *sample.dense,
                *flat_embeddings,
                *sample.expected_bottom,
                *sample.expected_interaction,
                sample.expected_logit[0],
                prediction,
                0,
            )
        )
        sample_rows.append(
            {
                "sample_id": sample.sample_id,
                "label": sample.label,
                "prediction": prediction,
                "classification_correct": int(prediction == sample.label),
                "expected_logit": sample.expected_logit[0],
                "dense": ";".join(str(v) for v in sample.dense),
                "categorical_ids": ";".join(
                    str(v) for v in sample.categorical_ids
                ),
                "embedding_0": ";".join(str(v) for v in embeddings[0]),
                "embedding_1": ";".join(str(v) for v in embeddings[1]),
                "embedding_2": ";".join(str(v) for v in embeddings[2]),
                "embedding_3": ";".join(str(v) for v in embeddings[3]),
                "expected_bottom": ";".join(
                    str(v) for v in sample.expected_bottom
                ),
                "expected_interaction": ";".join(
                    str(v) for v in sample.expected_interaction
                ),
            }
        )

    return bytes(payload), sample_rows, descriptors


def write_output_asset(
    output_path: Path,
    package: SourcePackage,
    source_package_sha256: str,
) -> Tuple[str, int, int]:
    payload, _, _ = build_output_payload(package)
    payload_hash = fnv1a64(payload)

    layers = package.bottom_layers + package.top_layers
    weights = flatten_weights(layers)
    biases = flatten_biases(layers)

    fixed_header = OUTPUT_HEADER_FIXED.pack(
        OUTPUT_MAGIC,
        OUTPUT_VERSION,
        OUTPUT_HEADER_BYTES,
        OUTPUT_FLAG_LABELS
        | OUTPUT_FLAG_CATEGORICAL_IDS
        | OUTPUT_FLAG_RESOLVED_EMBEDDINGS
        | OUTPUT_FLAG_EXPECTED_BOTTOM
        | OUTPUT_FLAG_EXPECTED_INTERACTION
        | OUTPUT_FLAG_EXPECTED_LOGIT
        | OUTPUT_FLAG_EXPECTED_PREDICTION,
        len(package.samples),
        len(layers),
        len(weights),
        len(biases),
        len(package.table_sizes),
        package.embedding_dim,
        package.dense_dim,
        package.interaction_dim,
        1,
        len(package.bottom_layers),
        len(package.top_layers),
        package.interaction_shift,
        len(payload),
        payload_hash,
        package.payload_fnv1a64,
        int(source_package_sha256[:16], 16),
        0,
    )
    if len(fixed_header) > OUTPUT_HEADER_BYTES:
        raise AssetError("output fixed header exceeds 128 bytes")
    header = fixed_header + bytes(OUTPUT_HEADER_BYTES - len(fixed_header))

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_bytes(header + payload)
    output_data = output_path.read_bytes()
    return sha256_bytes(output_data), len(output_data), payload_hash


def write_csv(path: Path, rows: Sequence[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fieldnames = [
        "sample_id",
        "label",
        "prediction",
        "classification_correct",
        "expected_logit",
        "dense",
        "categorical_ids",
        "embedding_0",
        "embedding_1",
        "embedding_2",
        "embedding_3",
        "expected_bottom",
        "expected_interaction",
    ]
    with path.open("w", newline="", encoding="utf-8") as output:
        writer = csv.DictWriter(output, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def verify_output_asset(path: Path) -> dict:
    data = path.read_bytes()
    if len(data) < OUTPUT_HEADER_BYTES:
        raise AssetError("output asset is smaller than its header")

    values = OUTPUT_HEADER_FIXED.unpack_from(data, 0)
    magic = values[0]
    u32 = list(values[1:16])
    u64 = list(values[16:21])

    (
        version,
        header_bytes,
        flags,
        sample_count,
        descriptor_count,
        weight_count,
        bias_count,
        embedding_tables,
        embedding_dim,
        dense_dim,
        interaction_dim,
        result_dim,
        bottom_layers,
        top_layers,
        interaction_shift,
    ) = u32
    payload_bytes, payload_hash, source_fnv, source_sha_prefix, reserved = u64

    if magic != OUTPUT_MAGIC:
        raise AssetError("output magic mismatch")
    if version != OUTPUT_VERSION or header_bytes != OUTPUT_HEADER_BYTES:
        raise AssetError("output version/header mismatch")
    if reserved != 0:
        raise AssetError("output reserved field is nonzero")
    if payload_bytes != len(data) - OUTPUT_HEADER_BYTES:
        raise AssetError("output payload byte count mismatch")
    observed_hash = fnv1a64(data[OUTPUT_HEADER_BYTES:])
    if observed_hash != payload_hash:
        raise AssetError("output payload FNV1a64 mismatch")

    expected = {
        "sample_count": EXPECTED_SAMPLE_COUNT,
        "descriptor_count": EXPECTED_DESCRIPTOR_COUNT,
        "weight_count": EXPECTED_WEIGHT_COUNT,
        "bias_count": EXPECTED_BIAS_COUNT,
        "embedding_tables": len(EXPECTED_TABLE_SIZES),
        "embedding_dim": EXPECTED_EMBEDDING_DIM,
        "dense_dim": EXPECTED_DENSE_DIM,
        "interaction_dim": EXPECTED_INTERACTION_DIM,
        "result_dim": 1,
        "bottom_layers": EXPECTED_BOTTOM_LAYERS,
        "top_layers": EXPECTED_TOP_LAYERS,
        "interaction_shift": EXPECTED_INTERACTION_SHIFT,
    }
    actual = {
        "sample_count": sample_count,
        "descriptor_count": descriptor_count,
        "weight_count": weight_count,
        "bias_count": bias_count,
        "embedding_tables": embedding_tables,
        "embedding_dim": embedding_dim,
        "dense_dim": dense_dim,
        "interaction_dim": interaction_dim,
        "result_dim": result_dim,
        "bottom_layers": bottom_layers,
        "top_layers": top_layers,
        "interaction_shift": interaction_shift,
    }
    for key, expected_value in expected.items():
        if actual[key] != expected_value:
            raise AssetError(
                f"output {key} mismatch: {actual[key]} != {expected_value}"
            )

    return {
        **actual,
        "flags": flags,
        "payload_bytes": payload_bytes,
        "payload_fnv1a64": f"0x{payload_hash:016x}",
        "source_payload_fnv1a64": f"0x{source_fnv:016x}",
        "source_sha256_prefix_u64": f"0x{source_sha_prefix:016x}",
        "sha256": sha256_bytes(data),
        "bytes": len(data),
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--source-package",
        type=Path,
        required=True,
        help="Stage 2M .f37xhd package",
    )
    parser.add_argument(
        "--output-asset",
        type=Path,
        required=True,
        help="Generated A11 .f37xpb asset",
    )
    parser.add_argument(
        "--manifest",
        type=Path,
        required=True,
        help="Generated JSON manifest",
    )
    parser.add_argument(
        "--samples-csv",
        type=Path,
        required=True,
        help="Generated sample summary CSV",
    )
    parser.add_argument(
        "--status",
        type=Path,
        required=True,
        help="Generated status text",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    source_data = args.source_package.read_bytes()
    source_sha256 = sha256_bytes(source_data)

    package = read_source_package(args.source_package)
    payload, sample_rows, descriptors = build_output_payload(package)

    output_sha256, output_bytes, output_payload_hash = write_output_asset(
        args.output_asset, package, source_sha256
    )
    output_info = verify_output_asset(args.output_asset)
    write_csv(args.samples_csv, sample_rows)

    classification_correct = sum(
        int(row["classification_correct"]) for row in sample_rows
    )
    accuracy = classification_correct / len(sample_rows)
    if classification_correct != EXPECTED_CORRECT:
        raise AssetError("generated classification count mismatch")
    if accuracy != EXPECTED_ACCURACY:
        raise AssetError("generated classification accuracy mismatch")

    layers = package.bottom_layers + package.top_layers
    manifest = {
        "format": "F37XPB1",
        "format_version": OUTPUT_VERSION,
        "claim_boundary": (
            "deterministic synthetic Stage 2M trained-model regression asset; "
            "not real Criteo evidence"
        ),
        "source": {
            "path": str(args.source_package),
            "format": "F37XHD1",
            "sha256": source_sha256,
            "payload_fnv1a64": f"0x{package.payload_fnv1a64:016x}",
            "model_name": package.name,
        },
        "pipeline": {
            "version": "0x00024E11",
            "bottom_descriptor_base": 0,
            "bottom_layer_count": len(package.bottom_layers),
            "top_descriptor_base": len(package.bottom_layers),
            "top_layer_count": len(package.top_layers),
            "final_descriptor_tag": len(layers) - 1,
            "interaction_shift": package.interaction_shift,
            "descriptor_capacity": 8,
            "weight_capacity": 2048,
            "bias_capacity": 128,
        },
        "model": {
            "shape": "8x16x8_interact18_32x16x1",
            "sample_count": len(package.samples),
            "embedding_table_sizes": package.table_sizes,
            "embedding_dim": package.embedding_dim,
            "dense_dim": package.dense_dim,
            "interaction_dim": package.interaction_dim,
            "descriptor_count": len(layers),
            "weight_count": sum(layer.weight_count for layer in layers),
            "bias_count": sum(layer.bias_count for layer in layers),
            "descriptors": [
                {
                    "index": index,
                    "in_dim": layer.in_dim,
                    "out_dim": layer.out_dim,
                    "weight_base": layer.weight_base,
                    "bias_base": layer.bias_base,
                    "output_shift": layer.output_shift,
                    "relu": layer.relu,
                    "word0": f"0x{descriptors[index][0]:08x}",
                    "word1": f"0x{descriptors[index][1]:08x}",
                    "word2": f"0x{descriptors[index][2]:08x}",
                }
                for index, layer in enumerate(layers)
            ],
        },
        "reference": {
            "software_bottom_exact": len(package.samples),
            "software_interaction_exact": len(package.samples),
            "software_top_exact": len(package.samples),
            "classification_correct": classification_correct,
            "classification_accuracy": accuracy,
        },
        "output": {
            "path": str(args.output_asset),
            **output_info,
            "samples_csv": str(args.samples_csv),
        },
        "no_fpga_access": True,
        "no_fpga_programming_or_reset": True,
    }

    args.manifest.parent.mkdir(parents=True, exist_ok=True)
    args.manifest.write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )

    args.status.parent.mkdir(parents=True, exist_ok=True)
    status_lines = [
        "STAGE2N_A11_PIPELINE_BATCH_ASSET_V1_PASS",
        f"MODEL_NAME={package.name}",
        "MODEL_SHAPE=8x16x8_interact18_32x16x1",
        f"SOURCE_PACKAGE_SHA256={source_sha256}",
        f"SOURCE_PAYLOAD_FNV1A64=0x{package.payload_fnv1a64:016x}",
        f"OUTPUT_ASSET={args.output_asset}",
        f"OUTPUT_ASSET_SIZE_BYTES={output_bytes}",
        f"OUTPUT_ASSET_SHA256={output_sha256}",
        f"OUTPUT_PAYLOAD_FNV1A64=0x{output_payload_hash:016x}",
        f"OUTPUT_MANIFEST={args.manifest}",
        f"OUTPUT_SAMPLES_CSV={args.samples_csv}",
        f"SAMPLE_COUNT={len(package.samples)}",
        f"DESCRIPTOR_COUNT={len(layers)}",
        f"WEIGHT_COUNT={sum(layer.weight_count for layer in layers)}",
        f"BIAS_COUNT={sum(layer.bias_count for layer in layers)}",
        f"EMBEDDING_TABLES={len(package.table_sizes)}",
        f"EMBEDDING_DIM={package.embedding_dim}",
        f"DENSE_DIM={package.dense_dim}",
        f"INTERACTION_DIM={package.interaction_dim}",
        f"INTERACTION_SHIFT={package.interaction_shift}",
        f"FINAL_DESCRIPTOR_TAG={len(layers) - 1}",
        f"SOFTWARE_BOTTOM_EXACT={len(package.samples)}",
        f"SOFTWARE_INTERACTION_EXACT={len(package.samples)}",
        f"SOFTWARE_TOP_EXACT={len(package.samples)}",
        f"SOFTWARE_CLASSIFICATION_CORRECT={classification_correct}",
        f"SOFTWARE_CLASSIFICATION_ACCURACY={accuracy:.6f}",
        "A10_PIPELINE_VERSION=0x00024E11",
        "A10_DESCRIPTOR_CAPACITY=8",
        "A10_WEIGHT_CAPACITY=2048",
        "A10_BIAS_CAPACITY=128",
        "NO_FPGA_ACCESS=1",
        "NO_FPGA_PROGRAMMING_OR_RESET=1",
    ]
    args.status.write_text("\n".join(status_lines) + "\n", encoding="utf-8")

    print("============================================================")
    for line in status_lines:
        if (
            "SHA256=" not in line
            or line.startswith("SOURCE_PACKAGE_SHA256=")
        ):
            # Source SHA is a fixed contract; output SHA is kept in status.
            print(line)
        elif line.startswith("OUTPUT_ASSET_SHA256="):
            print("OUTPUT_ASSET_SHA256_LENGTH=64")
            print("OUTPUT_ASSET_SHA256_VALID_HEX=1")
    print("============================================================")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (AssetError, OSError, ValueError, struct.error) as exc:
        print(
            f"STAGE2N_A11_PIPELINE_BATCH_ASSET_V1_FAILED: {exc}",
            file=sys.stderr,
        )
        raise SystemExit(1)
