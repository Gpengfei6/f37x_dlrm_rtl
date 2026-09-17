#!/usr/bin/env python3
"""Compare expected A18.3 Host ELF SHA, on-disk ELF SHA, and build-record SHA.

Does not open a device or run the Host.
"""
from __future__ import print_function

import argparse
import hashlib
import re
import sys
from pathlib import Path


class IdentityError(Exception):
    pass


def require(condition, message):
    if not condition:
        raise IdentityError(message)


def sha256_file(path):
    hasher = hashlib.sha256()
    with Path(path).open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            hasher.update(block)
    return hasher.hexdigest()


def read_status_field(status_text, name):
    match = re.search(
        r"^" + re.escape(name) + r"=([0-9a-f]{64})\s*$",
        status_text,
        re.MULTILINE,
    )
    require(match is not None, "build status missing " + name)
    return match.group(1)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--expected-elf-sha256", required=True)
    parser.add_argument("--expected-source-sha256", required=True)
    parser.add_argument("--binary", required=True)
    parser.add_argument("--status", required=True)
    parser.add_argument("--source", required=True)
    args = parser.parse_args()
    expected_elf = args.expected_elf_sha256.strip().lower()
    expected_source = args.expected_source_sha256.strip().lower()
    require(re.match(r"^[0-9a-f]{64}$", expected_elf) is not None, "bad ELF sha")
    require(re.match(r"^[0-9a-f]{64}$", expected_source) is not None, "bad source sha")
    binary = Path(args.binary)
    status = Path(args.status)
    source = Path(args.source)
    require(binary.is_file() and binary.stat().st_size > 0, "Host ELF missing")
    require(status.is_file() and status.stat().st_size > 0, "build status missing")
    require(source.is_file() and source.stat().st_size > 0, "Host source missing")
    actual_elf = sha256_file(binary)
    actual_source = sha256_file(source)
    status_text = status.read_text(encoding="utf-8")
    require("A18_3_HOST_XRT_BUILD=PASS" in status_text, "build status is not PASS")
    require("HOST_EXECUTION=NOT_RUN" in status_text, "build status must keep execution NOT_RUN")
    status_elf = read_status_field(status_text, "BINARY_SHA256")
    status_source = read_status_field(status_text, "SOURCE_SHA256")
    require(actual_elf == expected_elf, "on-disk ELF SHA mismatch")
    require(status_elf == expected_elf, "build-record ELF SHA mismatch")
    require(actual_source == expected_source, "on-disk source SHA mismatch")
    require(status_source == expected_source, "build-record source SHA mismatch")
    print("A18_3_HOST_ELF_IDENTITY=PASS")
    print("HOST_EXECUTE_PATH=" + str(binary))
    print("HOST_EXECUTE_SHA256=" + actual_elf)
    print("HOST_SOURCE_SHA256=" + actual_source)
    print("HOST_RUNTIME_PROCESS_HASH=NOT_CLAIMED")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except IdentityError as error:
        print("A18_3_HOST_ELF_IDENTITY=FAIL", file=sys.stderr)
        print("REASON={}".format(error), file=sys.stderr)
        sys.exit(1)
