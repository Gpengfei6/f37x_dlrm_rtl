#!/usr/bin/env python3
"""Build deterministic Stage 2N-A15.6 protected-board test assets.

The model, dense input, descriptors, weights, biases and fixed-point reference
are derived from the accepted Stage 2M package through the accepted A11 v2
reader/reference.  The five 64x8 INT16 tables exercise the fixed A15.4 rows
37..40.  No FPGA, XRT, network or server access occurs.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import struct
from pathlib import Path
from typing import Dict, List, Sequence, Tuple

import build_stage2n_a11_pipeline_batch_asset_v2 as a11


FORMAT = "F37XA156_MODEL_V1"
MAGIC = b"F37XA156"
VERSION = 1
HEADER = struct.Struct("<8s12I32s8s")
HEADER_BYTES = HEADER.size
ROWS = 64
DIM = 8
ROW_BYTES = 16
TABLE_BYTES = ROWS * ROW_BYTES
SOURCE_SAMPLE_ID = 0
FIXED_ROWS = (37, 38, 39, 40)
SENSITIVITY_DELTA = 2048


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def pack_i16_table(table: Sequence[Sequence[int]]) -> bytes:
    if len(table) != ROWS or any(len(row) != DIM for row in table):
        raise a11.AssetError("A15.6 table must be exactly 64x8")
    values = [value for row in table for value in row]
    if any(value < a11.INT16_MIN or value > a11.INT16_MAX for value in values):
        raise a11.AssetError("A15.6 table exceeds signed INT16")
    data = struct.pack("<{}h".format(len(values)), *values)
    if len(data) != TABLE_BYTES:
        raise a11.AssetError("A15.6 table byte count mismatch")
    return data


def canonical_table() -> List[List[int]]:
    return [
        [row * DIM + lane - 256 for lane in range(DIM)]
        for row in range(ROWS)
    ]


def build_model_asset(package: a11.SourcePackage) -> Tuple[bytes, List[Tuple[int, int, int]]]:
    layers = package.bottom_layers + package.top_layers
    descriptors = [a11.pack_descriptor(layer) for layer in layers]
    weights = [value for layer in layers for value in layer.weights]
    biases = [value for layer in layers for value in layer.biases]
    sample = package.samples[SOURCE_SAMPLE_ID]
    source_sha = bytes.fromhex(a11.EXPECTED_SOURCE_SHA256)
    header = HEADER.pack(
        MAGIC,
        VERSION,
        HEADER_BYTES,
        len(descriptors),
        len(weights),
        len(biases),
        len(sample.dense),
        package.interaction_shift,
        0,
        len(package.bottom_layers),
        len(package.bottom_layers),
        len(package.top_layers),
        sample.sample_id,
        source_sha,
        b"\x00" * 8,
    )
    body = bytearray()
    for words in descriptors:
        body.extend(struct.pack("<3I", *words))
    body.extend(struct.pack("<{}b".format(len(weights)), *weights))
    body.extend(struct.pack("<{}i".format(len(biases)), *biases))
    body.extend(struct.pack("<{}h".format(len(sample.dense)), *sample.dense))
    return header + bytes(body), descriptors


def evaluate_case(
    package: a11.SourcePackage,
    dense: Sequence[int],
    embeddings: Sequence[Sequence[int]],
) -> Dict[str, object]:
    bottom = a11.software_mlp(package.bottom_layers, dense)
    interaction = a11.software_interaction(
        bottom, embeddings, package.interaction_shift
    )
    final = a11.software_mlp(package.top_layers, interaction)
    if len(final) != 1:
        raise a11.AssetError("A15.6 final result dimension is not one")
    return {
        "expected_bottom": bottom,
        "expected_interaction": interaction,
        "expected_final_result": final[0],
    }


def build_cases(package: a11.SourcePackage) -> List[Dict[str, object]]:
    sample = package.samples[SOURCE_SAMPLE_ID]
    baseline_embeddings = a11.resolved_embeddings(package, sample)
    definitions = [("baseline", None)] + [
        ("slot{}_sensitivity".format(slot), slot) for slot in range(4)
    ]
    cases: List[Dict[str, object]] = []
    for case_index, (name, changed_slot) in enumerate(definitions):
        embeddings = [list(row) for row in baseline_embeddings]
        changed_lane = None
        old_value = None
        new_value = None
        if changed_slot is not None:
            changed_lane = 0
            old_value = embeddings[changed_slot][changed_lane]
            new_value = old_value + SENSITIVITY_DELTA
            if new_value > a11.INT16_MAX:
                new_value = old_value - SENSITIVITY_DELTA
            embeddings[changed_slot][changed_lane] = new_value

        table = canonical_table()
        for slot, row_index in enumerate(FIXED_ROWS):
            table[row_index] = list(embeddings[slot])
        payload = pack_i16_table(table)
        reference = evaluate_case(package, sample.dense, embeddings)
        cases.append(
            {
                "case_index": case_index,
                "name": name,
                "file": "stage2n_a15_6_case{}_{}_table_v1.bin".format(
                    case_index, name
                ),
                "payload": payload,
                "payload_sha256": sha256_bytes(payload),
                "row37_to_row40": {
                    str(row): list(embeddings[slot])
                    for slot, row in enumerate(FIXED_ROWS)
                },
                "modified_slot": changed_slot,
                "modified_row": (
                    FIXED_ROWS[changed_slot] if changed_slot is not None else None
                ),
                "modified_lane": changed_lane,
                "old_value": old_value,
                "new_value": new_value,
                **reference,
            }
        )

    baseline_result = int(cases[0]["expected_final_result"])
    sensitivity_results = [
        int(case["expected_final_result"]) for case in cases[1:]
    ]
    if any(value == baseline_result for value in sensitivity_results):
        raise a11.AssetError("a sensitivity case does not change final result")
    if len(set(sensitivity_results)) != len(sensitivity_results):
        raise a11.AssetError("sensitivity final results are not pairwise distinct")
    return cases


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-package", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--status", type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    package = a11.read_source_package(args.source_package)
    sample = package.samples[SOURCE_SAMPLE_ID]
    model_data, descriptors = build_model_asset(package)
    cases = build_cases(package)

    args.output_dir.mkdir(parents=True, exist_ok=True)
    model_name = "stage2n_a15_6_model_v1.bin"
    model_path = args.output_dir / model_name
    model_path.write_bytes(model_data)
    for case in cases:
        (args.output_dir / str(case["file"])).write_bytes(case.pop("payload"))

    layers = package.bottom_layers + package.top_layers
    manifest = {
        "format": "STAGE2N_A15_6_CASES_V1",
        "format_version": 1,
        "claim_boundary": (
            "Local deterministic preparation only; no FPGA, physical HBM, "
            "board, server, network, or performance validation."
        ),
        "source": {
            "path": args.source_package.as_posix(),
            "format": "F37XHD1",
            "sha256": a11.EXPECTED_SOURCE_SHA256,
            "sample_id": sample.sample_id,
            "categorical_ids": sample.categorical_ids,
        },
        "model_asset": {
            "file": model_name,
            "format": FORMAT,
            "magic": MAGIC.decode("ascii"),
            "header_bytes": HEADER_BYTES,
            "bytes": len(model_data),
            "sha256": sha256_bytes(model_data),
        },
        "pipeline": {
            "shape": "8x16x8_interact18_32x16x1",
            "descriptor_count": len(layers),
            "weight_count": sum(layer.weight_count for layer in layers),
            "bias_count": sum(layer.bias_count for layer in layers),
            "dense_input": sample.dense,
            "bottom_descriptor_base": 0,
            "bottom_layer_count": len(package.bottom_layers),
            "top_descriptor_base": len(package.bottom_layers),
            "top_layer_count": len(package.top_layers),
            "interaction_shift": package.interaction_shift,
            "final_descriptor_tag": len(layers) - 1,
            "descriptors": [
                {
                    "index": index,
                    "word0": "0x{:08x}".format(words[0]),
                    "word1": "0x{:08x}".format(words[1]),
                    "word2": "0x{:08x}".format(words[2]),
                }
                for index, words in enumerate(descriptors)
            ],
        },
        "hbm_table": {
            "bank": 0,
            "rows": ROWS,
            "dimension": DIM,
            "element_type": "INT16_LE",
            "row_bytes": ROW_BYTES,
            "payload_bytes": TABLE_BYTES,
            "fixed_lookup_rows": list(FIXED_ROWS),
            "lane_packing": "lane0 bits[15:0] through lane7 bits[127:112]",
            "base_layout": "A14 canonical value[row][lane]=row*8+lane-256",
        },
        "cases": cases,
        "local_generation": {
            "software_bottom_reference": "accepted A11 v2",
            "software_interaction_reference": "accepted A11 v2",
            "software_top_reference": "accepted A11 v2",
            "sensitivity_delta": SENSITIVITY_DELTA,
            "deterministic": True,
            "no_device_access": True,
        },
    }
    manifest_path = args.output_dir / "stage2n_a15_6_cases_v1.json"
    manifest_path.write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )

    status_lines = [
        "A15_6_GOLDEN_ASSET_GENERATION=PASS",
        "A15_6_GOLDEN_CASES=5",
        "A15_6_BASELINE_RESULT={}".format(cases[0]["expected_final_result"]),
        "A15_6_SLOT0_RESULT={}".format(cases[1]["expected_final_result"]),
        "A15_6_SLOT1_RESULT={}".format(cases[2]["expected_final_result"]),
        "A15_6_SLOT2_RESULT={}".format(cases[3]["expected_final_result"]),
        "A15_6_SLOT3_RESULT={}".format(cases[4]["expected_final_result"]),
        "A15_6_CASES_DETERMINISTIC=PASS",
        "A15_6_EACH_SLOT_CHANGES_FINAL_RESULT=PASS",
        "FPGA_DEVICE_ACCESS=NONE",
        "SERVER_ACCESS=NONE",
        "NETWORK_ACCESS=NONE",
    ]
    if args.status:
        args.status.parent.mkdir(parents=True, exist_ok=True)
        args.status.write_text("\n".join(status_lines) + "\n", encoding="utf-8")
    print("\n".join(status_lines))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (a11.AssetError, OSError, ValueError, struct.error) as exc:
        print("A15_6_GOLDEN_ASSET_GENERATION=FAIL")
        print("REASON={}".format(exc))
        raise SystemExit(1)
