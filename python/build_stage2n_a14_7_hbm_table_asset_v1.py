#!/usr/bin/env python3
"""Build the frozen Stage 2N-A14.7 1024-byte HBM[0] table payload.

This is a local/offline asset builder.  It does not import XRT and cannot access
an FPGA.  The JSON source remains authoritative; the generated binary is merely
a byte-exact transport artifact for the protected Host smoke.
"""

from __future__ import print_function

import argparse
import hashlib
import json
import os
import struct
import sys

EXPECTED_SCHEMA = "stage2n_a14_embedding_table_v1"
EXPECTED_ROWS = 64
EXPECTED_DIM = 8
EXPECTED_ROW_BYTES = 16
EXPECTED_PAYLOAD_BYTES = 1024
EXPECTED_SHA256 = "023ad250824def6b538ac40a7f0a9bd457e571136100ab1c1e574769f9061b03"
EXPECTED_FNV1A64 = 0x40A53C3698B88325
EXPECTED_HBM_BANK = "HBM[0]"
EXPECTED_FORMULA = "value[row_id][lane] = row_id * 8 + lane - 256"


def fail(message):
    raise RuntimeError(message)


def fnv1a64(data):
    value = 0xCBF29CE484222325
    for byte in bytearray(data):
        value ^= byte
        value = (value * 0x100000001B3) & 0xFFFFFFFFFFFFFFFF
    return value


def require_equal(name, actual, expected):
    if actual != expected:
        fail("{} mismatch: actual={!r} expected={!r}".format(name, actual, expected))


def load_and_validate(path):
    with open(path, "r") as handle:
        model = json.load(handle)

    require_equal("schema", model.get("schema"), EXPECTED_SCHEMA)
    require_equal("format_version", model.get("format_version"), 1)
    require_equal("hbm_bank", model.get("hbm_bank"), EXPECTED_HBM_BANK)
    require_equal("lookup_mode", model.get("lookup_mode"), "single_bank_direct")
    require_equal("base_byte_address", model.get("base_byte_address"), 0)
    require_equal("embedding_rows", model.get("embedding_rows"), EXPECTED_ROWS)
    require_equal("embedding_dimension", model.get("embedding_dimension"), EXPECTED_DIM)
    require_equal("element_type", model.get("element_type"), "int16")
    require_equal("element_width_bits", model.get("element_width_bits"), 16)
    require_equal("vector_width_bits", model.get("vector_width_bits"), 128)
    require_equal("row_stride_bytes", model.get("row_stride_bytes"), EXPECTED_ROW_BYTES)
    require_equal("byte_order", model.get("byte_order"), "little_endian")
    require_equal("lane_packing", model.get("lane_packing"), "lane_0_in_bits_15_0")
    require_equal("value_formula", model.get("value_formula"), EXPECTED_FORMULA)

    rows = model.get("table")
    if not isinstance(rows, list):
        fail("table must be a list")
    require_equal("table row count", len(rows), EXPECTED_ROWS)

    payload = bytearray()
    for row_id, row in enumerate(rows):
        require_equal("row_id[{}]".format(row_id), row.get("row_id"), row_id)
        require_equal(
            "byte_address[{}]".format(row_id),
            row.get("byte_address"),
            row_id * EXPECTED_ROW_BYTES,
        )
        values = row.get("values")
        if not isinstance(values, list):
            fail("row {} values must be a list".format(row_id))
        require_equal("row {} lane count".format(row_id), len(values), EXPECTED_DIM)
        for lane, value in enumerate(values):
            expected = row_id * EXPECTED_DIM + lane - 256
            require_equal("row {} lane {}".format(row_id, lane), value, expected)
            if value < -32768 or value > 32767:
                fail("row {} lane {} exceeds int16".format(row_id, lane))
            payload.extend(struct.pack("<h", value))

    require_equal("payload bytes", len(payload), EXPECTED_PAYLOAD_BYTES)
    sha256 = hashlib.sha256(payload).hexdigest()
    fnv = fnv1a64(payload)
    require_equal("payload SHA256", sha256, EXPECTED_SHA256)
    require_equal("payload FNV1a64", fnv, EXPECTED_FNV1A64)
    return bytes(payload), sha256, fnv


def refuse_overwrite(path):
    if path and os.path.exists(path):
        fail("refusing to overwrite existing output: {}".format(path))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, help="canonical A14 embedding JSON")
    parser.add_argument("--output", required=True, help="new 1024-byte binary output")
    parser.add_argument("--manifest", help="optional new key=value manifest")
    args = parser.parse_args()

    refuse_overwrite(args.output)
    if args.manifest:
        refuse_overwrite(args.manifest)

    payload, sha256, fnv = load_and_validate(args.input)

    output_parent = os.path.dirname(os.path.abspath(args.output))
    if not os.path.isdir(output_parent):
        os.makedirs(output_parent)
    with open(args.output, "wb") as handle:
        handle.write(payload)

    if args.manifest:
        manifest_parent = os.path.dirname(os.path.abspath(args.manifest))
        if not os.path.isdir(manifest_parent):
            os.makedirs(manifest_parent)
        with open(args.manifest, "w") as handle:
            handle.write("A14_7_CANONICAL_PAYLOAD=PASS\n")
            handle.write("SCHEMA={}\n".format(EXPECTED_SCHEMA))
            handle.write("HBM_BANK={}\n".format(EXPECTED_HBM_BANK))
            handle.write("TABLE_ROWS={}\n".format(EXPECTED_ROWS))
            handle.write("TABLE_DIM={}\n".format(EXPECTED_DIM))
            handle.write("ROW_BYTES={}\n".format(EXPECTED_ROW_BYTES))
            handle.write("PAYLOAD_BYTES={}\n".format(len(payload)))
            handle.write("PAYLOAD_SHA256={}\n".format(sha256))
            handle.write("PAYLOAD_FNV1A64={:016x}\n".format(fnv))
            handle.write("SOURCE_JSON={}\n".format(os.path.abspath(args.input)))
            handle.write("OUTPUT_BIN={}\n".format(os.path.abspath(args.output)))

    print("A14_7_CANONICAL_PAYLOAD=PASS")
    print("PAYLOAD_BYTES={}".format(len(payload)))
    print("PAYLOAD_SHA256={}".format(sha256))
    print("PAYLOAD_FNV1A64={:016x}".format(fnv))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        print("A14_7_CANONICAL_PAYLOAD=FAIL", file=sys.stderr)
        print("REASON={}".format(exc), file=sys.stderr)
        sys.exit(1)
