#!/usr/bin/env python3
"""Local software goldens for A18.2 variable lookup indexes.

Reads the frozen A15.6 model.bin and table.bin assets. Does not open a device,
invoke v++, or claim board/performance results.
"""
from __future__ import print_function

import argparse
import json
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "python"))

import build_stage2n_a11_pipeline_batch_asset_v2 as a11  # noqa: E402
import build_stage2n_a15_6_board_assets_v1 as a15  # noqa: E402

ROWS = 64
DIM = 8
ROW_BYTES = 16
DEFAULT_INDEXES = (37, 38, 39, 40)
LOCKED = {
    "baseline": -393,
    "slot0_sensitivity": -392,
    "slot1_sensitivity": -93,
    "slot2_sensitivity": -689,
    "slot3_sensitivity": -519,
}


class GoldenError(Exception):
    pass


def require(condition, message):
    if not condition:
        raise GoldenError(message)


def unpack_table(data):
    require(len(data) == ROWS * ROW_BYTES, "table must be 1024 bytes")
    values = struct.unpack("<{}h".format(ROWS * DIM), data)
    return [list(values[row * DIM:(row + 1) * DIM]) for row in range(ROWS)]


def unpack_descriptor(word0, word1, word2):
    value = word0 | (word1 << 32) | (word2 << 64)
    in_dim = value & 0x7FF
    out_dim = (value >> 11) & 0x7FF
    weight_base = (value >> 22) & 0xFFFFFFFF
    bias_base = (value >> 54) & 0xFFFFFFFF
    output_shift = (value >> 86) & 0x3F
    relu = bool((value >> 92) & 0x1)
    return in_dim, out_dim, weight_base, bias_base, output_shift, relu


def load_model(path):
    data = Path(path).read_bytes()
    require(len(data) >= a15.HEADER_BYTES, "model smaller than header")
    unpacked = a15.HEADER.unpack_from(data, 0)
    magic = unpacked[0]
    version = unpacked[1]
    header_bytes = unpacked[2]
    n_desc = unpacked[3]
    n_weight = unpacked[4]
    n_bias = unpacked[5]
    n_dense = unpacked[6]
    interaction_shift = unpacked[7]
    n_bottom = unpacked[9]
    n_top = unpacked[11]
    require(magic == a15.MAGIC, "model magic")
    require(version == a15.VERSION, "model version")
    require(header_bytes == a15.HEADER_BYTES, "model header bytes")
    offset = a15.HEADER_BYTES
    descriptors = []
    for _ in range(n_desc):
        descriptors.append(struct.unpack_from("<3I", data, offset))
        offset += 12
    weights = list(struct.unpack_from("<{}b".format(n_weight), data, offset))
    offset += n_weight
    biases = list(struct.unpack_from("<{}i".format(n_bias), data, offset))
    offset += n_bias * 4
    dense = list(struct.unpack_from("<{}h".format(n_dense), data, offset))
    offset += n_dense * 2
    require(offset == len(data), "model trailing bytes")
    layers = []
    weight_off = 0
    bias_off = 0
    for word0, word1, word2 in descriptors:
        in_dim, out_dim, weight_base, bias_base, output_shift, relu = unpack_descriptor(
            word0, word1, word2)
        weight_count = in_dim * out_dim
        bias_count = out_dim
        layers.append(a11.Layer(
            in_dim=in_dim,
            out_dim=out_dim,
            output_shift=output_shift,
            relu=relu,
            weight_base=weight_base,
            bias_base=bias_base,
            input_scale_log2=0,
            output_scale_log2=0,
            weight_count=weight_count,
            bias_count=bias_count,
            weights=weights[weight_off:weight_off + weight_count],
            biases=biases[bias_off:bias_off + bias_count],
        ))
        require(len(layers[-1].weights) == weight_count, "weight slice")
        require(len(layers[-1].biases) == bias_count, "bias slice")
        weight_off += weight_count
        bias_off += bias_count
    require(weight_off == n_weight, "weight cursor")
    require(bias_off == n_bias, "bias cursor")
    require(n_bottom + n_top == len(layers), "bottom/top layer count")
    return {
        "bottom_layers": layers[:n_bottom],
        "top_layers": layers[n_bottom:],
        "dense": dense,
        "interaction_shift": interaction_shift,
    }


def embeddings_for_indexes(table, indexes):
    require(len(indexes) == 4, "exactly four indexes")
    vectors = []
    for index in indexes:
        require(0 <= int(index) < ROWS, "OOB lookup index {}".format(index))
        vectors.append(list(table[int(index)]))
    return vectors


def evaluate_indexes(model, table, indexes):
    embeddings = embeddings_for_indexes(table, indexes)
    bottom = a11.software_mlp(model["bottom_layers"], model["dense"])
    interaction = a11.software_interaction(
        bottom, embeddings, model["interaction_shift"])
    final = a11.software_mlp(model["top_layers"], interaction)
    require(len(final) == 1, "final result dimension")
    return {
        "indexes": [int(v) for v in indexes],
        "embeddings": embeddings,
        "expected_bottom": bottom,
        "expected_interaction": interaction,
        "expected_final_result": int(final[0]),
    }


def parse_indexes(text):
    parts = [item.strip() for item in text.split(",")]
    require(len(parts) == 4, "indexes must be four comma-separated integers")
    return tuple(int(part, 0) for part in parts)


def self_test(repo):
    model_dir = repo / "models/stage2n_a15_6"
    manifest = json.loads(
        (model_dir / "stage2n_a15_6_cases_v1.json").read_text(encoding="utf-8"))
    model = load_model(model_dir / manifest["model_asset"]["file"])
    require(model["dense"] == manifest["pipeline"]["dense_input"], "dense mismatch")
    for case in manifest["cases"]:
        table = unpack_table((model_dir / case["file"]).read_bytes())
        result = evaluate_indexes(model, table, DEFAULT_INDEXES)
        require(result["expected_final_result"] == case["expected_final_result"],
                "golden mismatch " + case["name"])
        require(result["expected_final_result"] == LOCKED[case["name"]],
                "locked golden mismatch " + case["name"])
        for slot, row in enumerate(DEFAULT_INDEXES):
            require(result["embeddings"][slot] == case["row37_to_row40"][str(row)],
                    "row vector mismatch " + case["name"] + " row " + str(row))
    baseline = unpack_table(
        (model_dir / manifest["cases"][0]["file"]).read_bytes())
    other = evaluate_indexes(model, baseline, (1, 2, 3, 4))
    require(other["expected_final_result"] != LOCKED["baseline"],
            "rows 1-4 must not reuse board golden -393")
    try:
        evaluate_indexes(model, baseline, (64, 38, 39, 40))
        raise GoldenError("OOB 64 must fail")
    except GoldenError as error:
        require("OOB" in str(error), "OOB error text")
    extras = []
    for indexes in ((1, 2, 3, 4), (0, 0, 0, 0), (0, 63, 37, 40), (63, 62, 61, 60)):
        item = evaluate_indexes(model, baseline, indexes)
        extras.append({
            "indexes": item["indexes"],
            "expected_final_result": item["expected_final_result"],
            "table": "stage2n_a15_6_case0_baseline_table_v1.bin",
            "note": "software golden only; not a board result",
        })
    return extras


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", type=Path, default=ROOT)
    parser.add_argument("--indexes", default="37,38,39,40")
    parser.add_argument("--table", type=Path)
    parser.add_argument("--write-extras", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    repo = args.repo.resolve()
    extras = self_test(repo)
    print("A18_2_INDEX_GOLDEN_SELFTEST=PASS")
    print("A18_2_DEFAULT_37_40_MATCHES_LOCKED_BOARD_GOLDENS=PASS")
    print("A18_2_OOB_REJECT=PASS")
    print("A18_2_BOARD=NOT_RUN")
    print("A18_2_PERFORMANCE=NOT_CLAIMED")
    if args.write_extras:
        args.write_extras.parent.mkdir(parents=True, exist_ok=True)
        payload = {
            "schema": "a18_2_index_goldens_v1",
            "claim_boundary": (
                "Local software goldens from frozen A15.6 assets. "
                "Not FPGA, XO, xclbin, or performance evidence."
            ),
            "default_indexes": list(DEFAULT_INDEXES),
            "extras": extras,
        }
        args.write_extras.write_text(
            json.dumps(payload, indent=2, sort_keys=True) + "\n",
            encoding="utf-8")
        print("WROTE={}".format(args.write_extras))
    if args.self_test and args.indexes == "37,38,39,40" and args.table is None:
        return 0
    model_dir = repo / "models/stage2n_a15_6"
    model = load_model(model_dir / "stage2n_a15_6_model_v1.bin")
    table_path = args.table or (model_dir / "stage2n_a15_6_case0_baseline_table_v1.bin")
    table = unpack_table(Path(table_path).read_bytes())
    result = evaluate_indexes(model, table, parse_indexes(args.indexes))
    print("INDEXES={}".format(",".join(str(v) for v in result["indexes"])))
    print("EXPECTED_FINAL_RESULT={}".format(result["expected_final_result"]))
    print("TABLE={}".format(Path(table_path).as_posix()))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except GoldenError as error:
        print("A18_2_INDEX_GOLDEN=FAIL", file=sys.stderr)
        print("REASON={}".format(error), file=sys.stderr)
        sys.exit(1)
