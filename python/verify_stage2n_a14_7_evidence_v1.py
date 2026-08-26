#!/usr/bin/env python3
"""Offline validator for the Stage 2N-A14.7 64-line board-smoke evidence.

No XRT/device access is performed.  The validator checks the frozen A14.6
artifact identity, A14.7 geometry/hash contract, TABLE_BASE=paddr relation,
read-to-clear CONTROL semantics, and returned INT16 row contents.
"""

from __future__ import print_function

import argparse
import os
import re
import sys
import tempfile

EXPECTED_KEYS = [
    "A14_7_FLOW",
    "A14_7_HOST_BUILD",
    "A14_7_HOST_EXECUTION",
    "A14_7_PHYSICAL_HBM",
    "A14_7_SINGLE_TABLE_LOOKUP",
    "A14_7_RESULT_MATCH",
    "A14_7_BO_RELEASED",
    "A14_7_HBM0_POST_RELEASE_ZERO",
    "A14_7_DMA_ACTIVITY_OBSERVED",
    "A14_7_FPGA_PROGRAMMING",
    "A14_7_FPGA_RESET",
    "A14_7_OTHER_DEVICE_ACCESS",
    "FAIL_REASON",
    "GIT_BRANCH",
    "GIT_HEAD",
    "TARGET_INDEX",
    "TARGET_BDF",
    "TARGET_RENDER",
    "PLATFORM",
    "XRT_VERSION",
    "XCLBIN",
    "XCLBIN_SHA256",
    "XCLBIN_UUID",
    "KERNEL",
    "COMPUTE_UNIT",
    "IP_NAME",
    "IP_INDEX",
    "HBM_BANK",
    "HBM_MEMORY_INDEX",
    "TABLE_ROWS",
    "TABLE_DIM",
    "ELEMENT_TYPE",
    "ROW_BYTES",
    "PAYLOAD_BYTES",
    "PAYLOAD_SHA256",
    "PAYLOAD_FNV1A64",
    "LOOKUP_INDEX",
    "BO_PADDR_HEX",
    "TABLE_BASE_LO_HEX",
    "TABLE_BASE_HI_HEX",
    "CONTROL_PRE_START_HEX",
    "CONTROL_DONE_WORD_HEX",
    "CONTROL_POST_DONE_HEX",
    "CONTROL_POLL_COUNT",
    "RESULT0_HEX",
    "RESULT1_HEX",
    "RESULT2_HEX",
    "RESULT3_HEX",
    "ACTUAL_LANE0",
    "ACTUAL_LANE1",
    "ACTUAL_LANE2",
    "ACTUAL_LANE3",
    "ACTUAL_LANE4",
    "ACTUAL_LANE5",
    "ACTUAL_LANE6",
    "ACTUAL_LANE7",
    "EXPECTED_LANE0",
    "EXPECTED_LANE1",
    "EXPECTED_LANE2",
    "EXPECTED_LANE3",
    "EXPECTED_LANE4",
    "EXPECTED_LANE5",
    "EXPECTED_LANE6",
    "EXPECTED_LANE7",
]

if len(EXPECTED_KEYS) != 64:
    raise RuntimeError("internal validator key list is not 64 lines")

FIXED = {
    "A14_7_FLOW": "STAGE2N_A14_7_HBM_SINGLE_TABLE_BOARD_SMOKE_V1",
    "A14_7_HOST_BUILD": "PASS",
    "A14_7_HOST_EXECUTION": "PASS",
    "A14_7_PHYSICAL_HBM": "PASS",
    "A14_7_SINGLE_TABLE_LOOKUP": "PASS",
    "A14_7_RESULT_MATCH": "PASS",
    "A14_7_BO_RELEASED": "PASS",
    "A14_7_HBM0_POST_RELEASE_ZERO": "PASS",
    "A14_7_DMA_ACTIVITY_OBSERVED": "PASS",
    "A14_7_FPGA_RESET": "NOT_RUN",
    "A14_7_OTHER_DEVICE_ACCESS": "NONE",
    "FAIL_REASON": "NONE",
    "GIT_BRANCH": "work/stage2n-a13-cycle-counter",
    "TARGET_INDEX": "2",
    "TARGET_BDF": "0000:9b:00.1",
    "TARGET_RENDER": "/dev/dri/renderD129",
    "PLATFORM": "inspur_f37x_xdma_201920_3",
    "XRT_VERSION": "2.9.210507",
    "XCLBIN_SHA256": "9a7ce2518691e1d9a9ef55a0037d5d5345e3781f1e11eb7c2c7d19697144f573",
    "XCLBIN_UUID": "6f29087c-9598-4e68-877a-cc4840d078b8",
    "KERNEL": "dlrm_f37x_rtl_kernel_stage2n_a14_v2",
    "COMPUTE_UNIT": "dlrm_a14_1",
    "IP_NAME": "dlrm_f37x_rtl_kernel_stage2n_a14_v2:dlrm_a14_1",
    "IP_INDEX": "0",
    "HBM_BANK": "HBM[0]",
    "HBM_MEMORY_INDEX": "0",
    "TABLE_ROWS": "64",
    "TABLE_DIM": "8",
    "ELEMENT_TYPE": "INT16",
    "ROW_BYTES": "16",
    "PAYLOAD_BYTES": "1024",
    "PAYLOAD_SHA256": "023ad250824def6b538ac40a7f0a9bd457e571136100ab1c1e574769f9061b03",
    "PAYLOAD_FNV1A64": "40a53c3698b88325",
}

HEX32 = re.compile(r"^0x[0-9a-fA-F]{8}$")
HEX64 = re.compile(r"^0x[0-9a-fA-F]{16}$")
HEAD_RE = re.compile(r"^[0-9a-fA-F]{40}$")


def fail(message):
    raise RuntimeError(message)


def parse_file(path):
    with open(path, "r") as handle:
        raw_lines = [line.rstrip("\r\n") for line in handle]
    lines = [line for line in raw_lines if line != ""]
    if len(lines) != 64:
        fail("evidence must contain exactly 64 non-empty lines; got {}".format(len(lines)))

    data = {}
    order = []
    for line_number, line in enumerate(lines, 1):
        if "=" not in line:
            fail("line {} is not KEY=VALUE".format(line_number))
        key, value = line.split("=", 1)
        if not key or key in data:
            fail("invalid or duplicate key at line {}: {}".format(line_number, key))
        data[key] = value
        order.append(key)
    if order != EXPECTED_KEYS:
        fail("evidence key order/set does not match frozen 64-line schema")
    return data


def parse_u32_hex(name, value):
    if not HEX32.match(value):
        fail("{} must be 0x + 8 hex digits".format(name))
    return int(value, 16)


def parse_u64_hex(name, value):
    if not HEX64.match(value):
        fail("{} must be 0x + 16 hex digits".format(name))
    return int(value, 16)


def signed16(value):
    value &= 0xFFFF
    return value - 0x10000 if value & 0x8000 else value


def pack_pair(low, high):
    return (low & 0xFFFF) | ((high & 0xFFFF) << 16)


def validate(data):
    for key, expected in FIXED.items():
        if data.get(key) != expected:
            fail("{} mismatch: actual={!r} expected={!r}".format(key, data.get(key), expected))

    if data["A14_7_FPGA_PROGRAMMING"] not in ("PASS", "SKIPPED_ALREADY_LOADED"):
        fail("A14_7_FPGA_PROGRAMMING must be PASS or SKIPPED_ALREADY_LOADED")
    if not HEAD_RE.match(data["GIT_HEAD"]):
        fail("GIT_HEAD must be a full 40-hex commit")
    if not data["XCLBIN"]:
        fail("XCLBIN path must be non-empty")

    try:
        lookup_index = int(data["LOOKUP_INDEX"], 10)
        poll_count = int(data["CONTROL_POLL_COUNT"], 10)
    except ValueError:
        fail("LOOKUP_INDEX and CONTROL_POLL_COUNT must be decimal integers")
    if lookup_index < 0 or lookup_index >= 64:
        fail("LOOKUP_INDEX must be in [0, 63]")
    if poll_count < 1 or poll_count > 5000:
        fail("CONTROL_POLL_COUNT is outside [1, 5000]")

    paddr = parse_u64_hex("BO_PADDR_HEX", data["BO_PADDR_HEX"])
    base_lo = parse_u32_hex("TABLE_BASE_LO_HEX", data["TABLE_BASE_LO_HEX"])
    base_hi = parse_u32_hex("TABLE_BASE_HI_HEX", data["TABLE_BASE_HI_HEX"])
    if paddr & 0xF:
        fail("BO_PADDR_HEX is not 16-byte aligned")
    if base_lo != (paddr & 0xFFFFFFFF) or base_hi != ((paddr >> 32) & 0xFFFFFFFF):
        fail("TABLE_BASE_LO/HI do not reconstruct BO_PADDR_HEX")
    if paddr > 0xFFFFFFFFFFFFFFFF - 1023:
        fail("BO address range overflows 64 bits")

    pre = parse_u32_hex("CONTROL_PRE_START_HEX", data["CONTROL_PRE_START_HEX"])
    done = parse_u32_hex("CONTROL_DONE_WORD_HEX", data["CONTROL_DONE_WORD_HEX"])
    post = parse_u32_hex("CONTROL_POST_DONE_HEX", data["CONTROL_POST_DONE_HEX"])
    if pre & 0x1 or pre & 0x10 or (pre & 0xC) != 0xC:
        fail("CONTROL_PRE_START_HEX is not clean idle+ready")
    if (done & 0x2) == 0 or (done & 0x10) != 0:
        fail("CONTROL_DONE_WORD_HEX must contain DONE and no response error")
    if post & 0x3 or post & 0x10 or (post & 0xC) != 0xC:
        fail("CONTROL_POST_DONE_HEX does not prove read-to-clear DONE and idle+ready")

    expected_lanes = [lookup_index * 8 + lane - 256 for lane in range(8)]
    actual_lanes = []
    recorded_expected = []
    for lane in range(8):
        try:
            actual_lanes.append(int(data["ACTUAL_LANE{}".format(lane)], 10))
            recorded_expected.append(int(data["EXPECTED_LANE{}".format(lane)], 10))
        except ValueError:
            fail("lane values must be decimal signed integers")
    if recorded_expected != expected_lanes:
        fail("recorded expected row does not match frozen value formula")
    if actual_lanes != expected_lanes:
        fail("actual returned row does not match canonical expected row")

    result_words = [
        parse_u32_hex("RESULT{}_HEX".format(word), data["RESULT{}_HEX".format(word)])
        for word in range(4)
    ]
    expected_words = [pack_pair(expected_lanes[2 * word], expected_lanes[2 * word + 1]) for word in range(4)]
    if result_words != expected_words:
        fail("RESULT0..3 do not match packed expected lanes")
    unpacked = []
    for word in result_words:
        unpacked.extend([signed16(word), signed16(word >> 16)])
    if unpacked != actual_lanes:
        fail("RESULT0..3 do not unpack to ACTUAL_LANE0..7")


def synthetic_data():
    lookup = 37
    lanes = [lookup * 8 + lane - 256 for lane in range(8)]
    words = [pack_pair(lanes[2 * word], lanes[2 * word + 1]) for word in range(4)]
    paddr = 0x0000000123456000
    data = dict((key, "") for key in EXPECTED_KEYS)
    data.update(FIXED)
    data["A14_7_FPGA_PROGRAMMING"] = "SKIPPED_ALREADY_LOADED"
    data["GIT_HEAD"] = "3e98995191450000000000000000000000000000"
    data["XCLBIN"] = "/synthetic/dlrm_f37x_rtl_kernel_stage2n_a14_v2.xclbin"
    data["LOOKUP_INDEX"] = str(lookup)
    data["BO_PADDR_HEX"] = "0x{:016x}".format(paddr)
    data["TABLE_BASE_LO_HEX"] = "0x{:08x}".format(paddr & 0xFFFFFFFF)
    data["TABLE_BASE_HI_HEX"] = "0x{:08x}".format((paddr >> 32) & 0xFFFFFFFF)
    data["CONTROL_PRE_START_HEX"] = "0x0000000c"
    data["CONTROL_DONE_WORD_HEX"] = "0x00000006"
    data["CONTROL_POST_DONE_HEX"] = "0x0000000c"
    data["CONTROL_POLL_COUNT"] = "2"
    for word in range(4):
        data["RESULT{}_HEX".format(word)] = "0x{:08x}".format(words[word])
    for lane in range(8):
        data["ACTUAL_LANE{}".format(lane)] = str(lanes[lane])
        data["EXPECTED_LANE{}".format(lane)] = str(lanes[lane])
    return data


def write_data(path, data):
    with open(path, "w") as handle:
        for key in EXPECTED_KEYS:
            handle.write("{}={}\n".format(key, data[key]))


def self_test():
    directory = tempfile.mkdtemp(prefix="a14_7_validator_")
    valid_path = os.path.join(directory, "valid.txt")
    tampered_path = os.path.join(directory, "tampered.txt")
    try:
        valid = synthetic_data()
        write_data(valid_path, valid)
        validate(parse_file(valid_path))

        tampered = dict(valid)
        tampered["RESULT0_HEX"] = "0x00290029"
        write_data(tampered_path, tampered)
        rejected = False
        try:
            validate(parse_file(tampered_path))
        except RuntimeError:
            rejected = True
        if not rejected:
            fail("self-test tampered evidence was incorrectly accepted")
        print("A14_7_EVIDENCE_VALIDATOR_SELF_TEST=PASS")
        print("A14_7_VALID_64_LINE_FIXTURE=PASS")
        print("A14_7_TAMPER_REJECTION=PASS")
    finally:
        for path in (valid_path, tampered_path):
            try:
                os.remove(path)
            except OSError:
                pass
        try:
            os.rmdir(directory)
        except OSError:
            pass


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence", help="64-line A14.7 evidence file")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
    if args.evidence:
        validate(parse_file(args.evidence))
        print("A14_7_EVIDENCE_VALIDATION=PASS")
        print("EVIDENCE={}".format(os.path.abspath(args.evidence)))
    if not args.self_test and not args.evidence:
        parser.error("provide --evidence and/or --self-test")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        print("A14_7_EVIDENCE_VALIDATION=FAIL", file=sys.stderr)
        print("REASON={}".format(exc), file=sys.stderr)
        sys.exit(1)
