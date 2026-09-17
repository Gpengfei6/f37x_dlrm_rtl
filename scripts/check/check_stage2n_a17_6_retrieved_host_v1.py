#!/usr/bin/env python3
"""Hash retrieved A17.6 Host files and report 20260910_100942 log facts.

Does not open a device, run the Host, or backfill a missing pre-exec hash.
"""
from __future__ import print_function

import hashlib
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RETRIEVAL = ROOT / "docs/evidence/stage2n_a17_6/host_identity_retrieval_v1"
CANDIDATE_ELF = (
    "9ba376589f56d99efca6e42328d347a6539ba1c40bba56d21ab690d87e7f20fc"
)
CANDIDATE_SOURCE = (
    "7073b4d976e54f73887c21714a3a4d8bdf65cdf3a272e620fb54c09963ee55ce"
)
PRE_FIX_ELF = (
    "520d78efe3a4ba81a8cd3a66ee48042d39a14a0a3e4fb390e567bd7afb3bf5cd"
)


def sha256_file(path):
    hasher = hashlib.sha256()
    with Path(path).open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            hasher.update(block)
    return hasher.hexdigest()


def present(text, token):
    return token in text


def main():
    elf = RETRIEVAL / "current_elf/stage2n_a17_6_four_bo_host_v1"
    source = RETRIEVAL / "current_source/stage2n_a17_6_four_bo_host_v1.cpp"
    status = RETRIEVAL / "host_build_status.txt"
    fail_dir = RETRIEVAL / "fail_20260910_100942"
    missing = []
    for path in (elf, source, status):
        if not path.is_file() or path.stat().st_size == 0:
            missing.append(str(path))
    if missing:
        print("A17_6_HOST_IDENTITY_RETRIEVAL=NOT_PRESENT")
        for path in missing:
            print("MISSING=" + path)
        return 2

    elf_sha = sha256_file(elf)
    source_sha = sha256_file(source)
    status_text = status.read_text(encoding="utf-8", errors="replace")
    elf_match = elf_sha == CANDIDATE_ELF
    source_match = source_sha == CANDIDATE_SOURCE
    print("RETRIEVED_ELF_SHA256=" + elf_sha)
    print("RETRIEVED_ELF_BYTES=" + str(elf.stat().st_size))
    print("RETRIEVED_SOURCE_SHA256=" + source_sha)
    print("RETRIEVED_SOURCE_BYTES=" + str(source.stat().st_size))
    print("CANDIDATE_ELF_SHA256=" + CANDIDATE_ELF)
    print("CANDIDATE_SOURCE_SHA256=" + CANDIDATE_SOURCE)
    print("ELF_MATCH_CANDIDATE=" + ("YES" if elf_match else "NO"))
    print("SOURCE_MATCH_CANDIDATE=" + ("YES" if source_match else "NO"))
    print("ELF_IS_PRE_FIX_520d78=" + ("YES" if elf_sha == PRE_FIX_ELF else "NO"))
    print("STATUS_HAS_CANDIDATE_ELF=" + (
        "YES" if CANDIDATE_ELF in status_text else "NO"))
    print("STATUS_HAS_PRE_FIX_ELF=" + (
        "YES" if PRE_FIX_ELF in status_text else "NO"))
    print("RUNTIME_PRE_EXEC_HASH_BACKFILL=NO")
    if elf_match and source_match:
        print("REUSE_CANDIDATE=YES")
        print("A17_6_HOST_IDENTITY_RETRIEVAL=MATCH")
        print("NOTE=candidate for the next locked function re-check; not a")
        print("NOTE=reconstructed pre-exec hash from 20260910_102244")
    else:
        print("REUSE_CANDIDATE=NO")
        print("A17_6_HOST_IDENTITY_RETRIEVAL=MISMATCH_OR_INCOMPLETE")
        print("NOTE=do not rewrite expected SHA or status to force a match")
        print("NOTE=use a newly labeled build for re-check if originals differ")

    print("FAIL_DIR_100942=" + str(fail_dir))
    if not fail_dir.is_dir():
        print("FAIL_100942=NOT_PRESENT")
        return 0
    host_log = fail_dir / "host.log"
    runner_log = fail_dir / "runner.log"
    host_text = host_log.read_text(encoding="utf-8", errors="replace") if host_log.is_file() else ""
    runner_text = runner_log.read_text(encoding="utf-8", errors="replace") if runner_log.is_file() else ""
    print("FAIL_100942_HOST_LOG=" + ("YES" if host_text else "NO"))
    print("FAIL_100942_RUNNER_LOG=" + ("YES" if runner_text else "NO"))
    if not host_text and not runner_text:
        print("FAIL_100942=NOT_PRESENT")
        return 0
    print("FAIL_100942_HOST_LOG_BYTES=" + str(len(host_text.encode("utf-8"))))
    print("FAIL_100942_RUNNER_LOG_BYTES=" + str(len(runner_text.encode("utf-8"))))
    facts = [
        ("FAIL_TOKEN_MEMORY_MAP_MISSING_ARG0",
         present(host_text, "memory map missing argument 0") or
         present(runner_text, "memory map missing argument 0")),
        ("FAIL_TOKEN_HOST_V1_FAIL",
         present(host_text, "STAGE2N_A17_6_FOUR_BO_HOST_V1_FAIL") or
         present(runner_text, "STAGE2N_A17_6_FOUR_BO_HOST_V1_FAIL")),
        ("FAIL_TOKEN_XBUTIL_PROGRAM_SUCCEEDED",
         present(runner_text, "INFO: xbutil program succeeded.")),
        ("FAIL_TOKEN_HOST_START",
         present(host_text, "A17_6_HOST_START=1") or
         present(runner_text, "A17_6_HOST_START=1")),
        ("FAIL_TOKEN_BO0_HANDLE",
         present(host_text, "BO0_HANDLE=") or
         present(runner_text, "BO0_HANDLE=")),
        ("FAIL_TOKEN_PIPE_CMD_OR_START_CASE",
         present(host_text, "CASE0_NAME=") or
         present(runner_text, "CASE0_NAME=")),
    ]
    for name, found in facts:
        print(name + "=" + ("YES" if found else "NO"))
    print("FAIL_100942_INTERPRETATION=TOKENS_ONLY_NO_SPECULATION")
    return 0


if __name__ == "__main__":
    sys.exit(main())
