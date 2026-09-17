#!/usr/bin/env python3
"""Compare expected Host ELF SHA, on-disk ELF SHA, and build-record SHA.

Does not open a device, run the Host, or treat a build-record SHA as a
runtime-verified process hash.
"""
from __future__ import print_function

import argparse
import hashlib
import re
import sys
from pathlib import Path


PRE_FIX_HOST_ELF_SHA256 = (
    "520d78efe3a4ba81a8cd3a66ee48042d39a14a0a3e4fb390e567bd7afb3bf5cd"
)
BUILD_RECORD_HOST_ELF_SHA256 = (
    "9ba376589f56d99efca6e42328d347a6539ba1c40bba56d21ab690d87e7f20fc"
)
BUILD_RECORD_HOST_SOURCE_SHA256 = (
    "7073b4d976e54f73887c21714a3a4d8bdf65cdf3a272e620fb54c09963ee55ce"
)
PRE_FIX_HOST_SOURCE_SHA256 = (
    "2ef3a5a69b7104abc3b71e2642c31af72934491ec015c9ca4af1e79918d4800e"
)


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


def check_host_elf_identity(
        expected_elf_sha256, binary_path, status_path, source_path,
        expected_source_sha256=None):
    expected_elf = expected_elf_sha256.strip().lower()
    require(re.match(r"^[0-9a-f]{64}$", expected_elf) is not None,
            "expected Host ELF SHA256 is not 64 hex characters")
    binary = Path(binary_path)
    status = Path(status_path)
    source = Path(source_path)
    require(binary.is_file() and binary.stat().st_size > 0,
            "Host ELF missing or empty: " + str(binary))
    require(status.is_file() and status.stat().st_size > 0,
            "Host build status missing or empty")
    require(source.is_file() and source.stat().st_size > 0,
            "Host source missing or empty")

    actual_elf = sha256_file(binary)
    actual_source = sha256_file(source)
    status_text = status.read_text(encoding="utf-8")
    status_elf = read_status_field(status_text, "BINARY_SHA256")
    status_source = read_status_field(status_text, "SOURCE_SHA256")
    require("A17_6_HOST_XRT_BUILD=PASS" in status_text,
            "build status is not PASS")

    require(actual_elf == expected_elf,
            "on-disk ELF SHA256 {} does not match expected {}".format(
                actual_elf, expected_elf))
    require(status_elf == expected_elf,
            "build-record BINARY_SHA256 {} does not match expected {}".format(
                status_elf, expected_elf))
    require(actual_elf == status_elf,
            "on-disk ELF SHA256 {} does not match build-record {}".format(
                actual_elf, status_elf))
    require(actual_source == status_source,
            "on-disk source SHA256 {} does not match build-record {}".format(
                actual_source, status_source))
    if expected_source_sha256:
        expected_source = expected_source_sha256.strip().lower()
        require(re.match(r"^[0-9a-f]{64}$", expected_source) is not None,
                "expected Host source SHA256 is not 64 hex characters")
        require(actual_source == expected_source,
                "on-disk source SHA256 {} does not match expected {}".format(
                    actual_source, expected_source))

    size = binary.stat().st_size
    return {
        "path": str(binary),
        "elf_sha256": actual_elf,
        "elf_bytes": size,
        "source_sha256": actual_source,
        "status_elf_sha256": status_elf,
        "status_source_sha256": status_source,
        "expected_elf_sha256": expected_elf,
        "runtime_process_hash": "NOT_CLAIMED",
    }


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--expected-elf-sha256", required=True)
    parser.add_argument("--binary", required=True)
    parser.add_argument("--status", required=True)
    parser.add_argument("--source", required=True)
    parser.add_argument("--expected-source-sha256", default="")
    args = parser.parse_args(argv)
    info = check_host_elf_identity(
        args.expected_elf_sha256,
        args.binary,
        args.status,
        args.source,
        args.expected_source_sha256 or None,
    )
    print("A17_6_HOST_ELF_IDENTITY=PASS")
    print("HOST_EXECUTE_PATH={}".format(info["path"]))
    print("HOST_EXECUTE_SHA256={}".format(info["elf_sha256"]))
    print("HOST_EXECUTE_BYTES={}".format(info["elf_bytes"]))
    print("HOST_SOURCE_SHA256={}".format(info["source_sha256"]))
    print("HOST_BUILD_RECORD_ELF_SHA256={}".format(info["status_elf_sha256"]))
    print("HOST_BUILD_RECORD_SOURCE_SHA256={}".format(
        info["status_source_sha256"]))
    print("HOST_RUNTIME_PROCESS_HASH=NOT_CLAIMED")
    print("NOTE=trio match is execute-time file identity, not a reconstructed")
    print("NOTE=hash from a previous run that omitted the pre-exec hash")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except IdentityError as error:
        print("A17_6_HOST_ELF_IDENTITY=FAIL", file=sys.stderr)
        print("REASON={}".format(error), file=sys.stderr)
        sys.exit(1)
