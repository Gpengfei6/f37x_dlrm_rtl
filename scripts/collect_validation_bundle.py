#!/usr/bin/env python3
"""Create credential-free Stage-1 or Stage-2A validation artifacts."""

import argparse
import hashlib
import json
import subprocess
import zipfile
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]
STAGE1_HANDOFF_DIR = PROJECT_ROOT / "handoff" / "stage1_validation"
STAGE2A_HANDOFF_DIR = PROJECT_ROOT / "handoff" / "stage2a_validation"
RESULTS_DIR = PROJECT_ROOT / "results"

PAYLOAD_ROOT_FILES = [
    ".gitattributes",
    ".gitignore",
    "AGENTS.md",
    "README.md",
]
PAYLOAD_DIRECTORIES = [
    "config",
    "docs",
    "host",
    "python",
    "rtl",
    "scripts",
    "tb",
    "tests",
    "handoff/stage1_validation",
    "handoff/stage2a_validation",
]
FORBIDDEN_SUFFIXES = {".pem", ".key", ".p12", ".pfx"}
FORBIDDEN_NAMES = {".env", "id_rsa", "id_ed25519", "credentials"}


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def repository_revision():
    try:
        revision = subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=str(PROJECT_ROOT),
            stderr=subprocess.DEVNULL, text=True
        ).strip()
    except (OSError, subprocess.CalledProcessError):
        revision = "UNKNOWN"
    try:
        dirty = bool(subprocess.check_output(
            ["git", "status", "--porcelain"], cwd=str(PROJECT_ROOT),
            stderr=subprocess.DEVNULL, text=True
        ).strip())
    except (OSError, subprocess.CalledProcessError):
        dirty = None
    return revision, dirty


def is_safe_payload_file(path):
    relative = path.relative_to(PROJECT_ROOT)
    if ".git" in relative.parts or "__pycache__" in relative.parts:
        return False
    if path.suffix.lower() in FORBIDDEN_SUFFIXES:
        return False
    if path.name.lower() in FORBIDDEN_NAMES:
        return False
    if path.suffix.lower() == ".zip":
        return False
    return path.is_file()


def payload_files():
    files = []
    for name in PAYLOAD_ROOT_FILES:
        path = PROJECT_ROOT / name
        if path.is_file():
            files.append(path)
    for directory in PAYLOAD_DIRECTORIES:
        root = PROJECT_ROOT / directory
        if not root.exists():
            continue
        files.extend(path for path in root.rglob("*") if is_safe_payload_file(path))
    return sorted(set(files), key=lambda item: item.as_posix())


def write_source_manifest(files):
    revision, dirty = repository_revision()
    records = [
        {
            "path": path.relative_to(PROJECT_ROOT).as_posix(),
            "bytes": path.stat().st_size,
            "sha256": sha256(path),
        }
        for path in files
    ]
    manifest = {
        "git_revision": revision,
        "git_worktree_dirty": dirty,
        "files": records,
    }
    RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    manifest_path = RESULTS_DIR / "source_manifest_sha256.json"
    manifest_path.write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    return manifest_path


def add_file(archive, path, archive_name):
    archive.write(str(path), archive_name.as_posix())


def prepare_handoff(stage2a=False):
    handoff_dir = STAGE2A_HANDOFF_DIR if stage2a else STAGE1_HANDOFF_DIR
    payload_name = (
        "stage2a_validation_payload.zip" if stage2a
        else "stage1_validation_payload.zip"
    )
    handoff_dir.mkdir(parents=True, exist_ok=True)
    files = payload_files()
    manifest_path = write_source_manifest(files)
    payload_path = handoff_dir / payload_name
    with zipfile.ZipFile(payload_path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for path in files:
            relative = path.relative_to(PROJECT_ROOT)
            add_file(archive, path, Path("f37x_dlrm_rtl") / relative)
        add_file(
            archive, manifest_path,
            Path("f37x_dlrm_rtl/results/source_manifest_sha256.json")
        )
    print("collect_validation_bundle: payload {} files -> {}".format(
        len(files), payload_path
    ))
    return payload_path


def ensure_validation_summary():
    summary_path = RESULTS_DIR / "validation_summary.json"
    if summary_path.is_file():
        return summary_path
    tests = []
    python_log = PROJECT_ROOT / "logs" / "python_tests.log"
    if python_log.is_file():
        try:
            python_status = json.loads(python_log.read_text(encoding="utf-8"))["status"]
        except (ValueError, KeyError):
            python_status = "FAIL"
        tests.append({
            "name": "python_regression",
            "category": "python",
            "status": python_status if python_status in ("PASS", "FAIL") else "FAIL",
            "exit_code": None,
            "log": "logs/python_tests.log",
            "reason": "Reconstructed from standalone server log",
        })
    status_path = RESULTS_DIR / "xsim_stage1_status.txt"
    if status_path.is_file():
        for line in status_path.read_text(encoding="utf-8").splitlines():
            if not line.strip():
                continue
            name, stage, raw_status, exit_code = line.split(None, 3)
            tests.append({
                "name": "{}_{}".format(name, stage.lower()),
                "category": "rtl_simulation" if stage == "SIM" else "rtl_compile",
                "status": "PASS" if raw_status == "PASS" else "FAIL",
                "exit_code": int(exit_code),
                "log": (
                    "logs/xvlog_stage1.log" if stage == "COMPILE" else
                    "logs/xelab_{}.log".format(name) if stage == "ELAB" else
                    "logs/xsim_{}.log".format(name)
                ),
                "reason": raw_status,
            })
    if not tests:
        tests.append({
            "name": "validation",
            "category": "environment",
            "status": "SKIPPED",
            "exit_code": None,
            "log": None,
            "reason": "No validation logs were found",
        })
    counts = {
        status.lower(): sum(item["status"] == status for item in tests)
        for status in ("PASS", "FAIL", "SKIPPED")
    }
    overall = "FAIL" if counts["fail"] else ("PASS" if counts["pass"] else "SKIPPED")
    revision, _ = repository_revision()
    summary = {
        "git_revision": revision,
        "overall_status": overall,
        "counts": counts,
        "gate1_satisfied": False,
        "gate1_note": "Standalone logs require Codex review before gate approval.",
        "tests": tests,
    }
    summary_path.write_text(
        json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    return summary_path


def collect_logs(stage2a=False):
    files = payload_files()
    manifest_path = write_source_manifest(files)
    summary_path = ensure_validation_summary()
    candidates = [manifest_path, summary_path]
    logs_dir = PROJECT_ROOT / "logs"
    if logs_dir.exists():
        candidates.extend(path for path in logs_dir.rglob("*") if path.is_file())
    for name in (
        "validation_summary.json",
        "xsim_stage1_summary.json",
        "xsim_stage1_status.txt",
        "xsim_stage2a_summary.json",
        "xsim_stage2a_status.txt",
        "stage2a_python_summary.json",
        "rtl_top_outputs.hex",
        "python_compare_report.json",
    ):
        path = RESULTS_DIR / name
        if path.is_file():
            candidates.append(path)
    output_path = RESULTS_DIR / (
        "stage2a_validation_logs.zip" if stage2a
        else "stage1_validation_logs.zip"
    )
    with zipfile.ZipFile(output_path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(set(candidates), key=lambda item: item.as_posix()):
            add_file(archive, path, path.relative_to(PROJECT_ROOT))
    print("collect_validation_bundle: logs {} files -> {}".format(
        len(set(candidates)), output_path
    ))
    return output_path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--prepare-handoff", action="store_true")
    parser.add_argument("--collect-logs", action="store_true")
    parser.add_argument(
        "--stage2a", action="store_true",
        help="write Stage-2A-named payload/log archives",
    )
    args = parser.parse_args()
    if not args.prepare_handoff and not args.collect_logs:
        parser.error("select --prepare-handoff and/or --collect-logs")
    if args.prepare_handoff:
        prepare_handoff(stage2a=args.stage2a)
    if args.collect_logs:
        collect_logs(stage2a=args.stage2a)


if __name__ == "__main__":
    main()
