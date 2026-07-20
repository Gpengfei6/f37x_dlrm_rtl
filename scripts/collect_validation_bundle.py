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
STAGE2A_TESTBENCHES = (
    "tb_mac_lane",
    "tb_runtime_relu_quant",
    "tb_banked_activation_buffer",
    "tb_local_weight_provider",
    "tb_vector_dot_product_core",
    "tb_dense_layer_engine",
)

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


def xsim_status_log(suite, name, stage):
    if stage == "COMPILE":
        return "logs/xvlog_{}.log".format(suite)
    tool = "xelab" if stage == "ELAB" else "xsim"
    if suite == "stage2a":
        return "logs/{}_stage2a_{}.log".format(tool, name)
    return "logs/{}_{}.log".format(tool, name)


def parse_xsim_status(status_path, suite):
    records = []
    for line_number, line in enumerate(
            status_path.read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip():
            continue
        parts = line.split()
        if len(parts) != 4:
            records.append({
                "name": "xsim_{}_status_line_{}".format(suite, line_number),
                "category": "rtl_compile",
                "status": "FAIL",
                "exit_code": None,
                "log": "results/xsim_{}_status.txt".format(suite),
                "reason": "Malformed status line: {}".format(line),
                "source_name": "status_line_{}".format(line_number),
                "stage": "PARSE",
            })
            continue
        name, stage, raw_status, raw_exit_code = parts
        try:
            exit_code = int(raw_exit_code)
        except ValueError:
            exit_code = None
            raw_status = "FAIL"
        status = (
            "PASS" if raw_status == "PASS" and exit_code == 0 else "FAIL"
        )
        records.append({
            "name": "xsim_{}_{}_{}".format(suite, name, stage.lower()),
            "category": "rtl_simulation" if stage == "SIM" else "rtl_compile",
            "status": status,
            "exit_code": exit_code,
            "log": xsim_status_log(suite, name, stage),
            "reason": raw_status,
            "source_name": name,
            "stage": stage,
        })
    return records


def remove_stale_xsim_records(tests):
    def is_stale(item):
        name = str(item.get("name", ""))
        return (
            name.startswith("xsim_stage1_") or
            name.startswith("xsim_stage2a_") or
            name == "xvlog_compile" or
            (name.startswith("tb_") and
             (name.endswith("_elab") or name.endswith("_sim")))
        )

    return [item for item in tests if not is_stale(item)]


def update_validation_summary(
        summary, stage1_status=None, stage2a_status=None,
        require_stage2a=False):
    updated = dict(summary)
    tests = remove_stale_xsim_records(updated.get("tests", []))
    stage2a_records = None
    for suite, status_path in (
        ("stage1", stage1_status),
        ("stage2a", stage2a_status),
    ):
        if status_path is None or not status_path.is_file():
            continue
        records = parse_xsim_status(status_path, suite)
        tests.extend(records)
        if suite == "stage2a":
            stage2a_records = records

    if stage2a_records is not None:
        expected = {("xvlog", "COMPILE")}
        expected.update(
            (testbench, stage)
            for testbench in STAGE2A_TESTBENCHES
            for stage in ("ELAB", "SIM")
        )
        observed = {
            (item.get("source_name"), item.get("stage"))
            for item in stage2a_records
        }
        complete = expected.issubset(observed)
        all_pass = complete and all(
            item["status"] == "PASS" for item in stage2a_records
        )
        if not complete:
            missing = sorted(expected - observed)
            tests.append({
                "name": "xsim_stage2a_status_completeness",
                "category": "rtl_compile",
                "status": "FAIL",
                "exit_code": None,
                "log": "results/xsim_stage2a_status.txt",
                "reason": "Missing Stage-2A status records: {}".format(missing),
            })
        updated["stage2a_rtl_satisfied"] = all_pass
        if all_pass:
            updated["stage2a_note"] = (
                "Stage-2A status includes xvlog plus 6/6 elaboration and "
                "6/6 simulation PASS records; independent log review is still required."
            )
        elif not complete:
            updated["stage2a_note"] = (
                "Stage-2A status is incomplete; missing compile/elaboration/simulation records."
            )
        else:
            updated["stage2a_note"] = (
                "Stage-2A status contains one or more FAIL records."
            )
    elif require_stage2a:
        tests.append({
            "name": "xsim_stage2a_status_missing",
            "category": "rtl_compile",
            "status": "FAIL",
            "exit_code": None,
            "log": "results/xsim_stage2a_status.txt",
            "reason": "Required Stage-2A status file is missing",
        })
        updated["stage2a_rtl_satisfied"] = False
        updated["stage2a_note"] = (
            "Stage-2A status file results/xsim_stage2a_status.txt is missing."
        )

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
    updated["tests"] = tests
    updated["counts"] = counts
    updated["overall_status"] = (
        "FAIL" if counts["fail"] else ("PASS" if counts["pass"] else "SKIPPED")
    )
    return updated


def ensure_validation_summary(require_stage2a=False):
    summary_path = RESULTS_DIR / "validation_summary.json"
    if summary_path.is_file():
        try:
            summary = json.loads(summary_path.read_text(encoding="utf-8"))
        except ValueError:
            summary = {
                "tests": [{
                    "name": "validation_summary_parse",
                    "category": "packaging",
                    "status": "FAIL",
                    "exit_code": None,
                    "log": "results/validation_summary.json",
                    "reason": "Existing validation summary is invalid JSON",
                }]
            }
    else:
        summary = {"tests": []}
    tests = list(summary.get("tests", []))
    python_log = PROJECT_ROOT / "logs" / "python_tests.log"
    if python_log.is_file() and not tests:
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
    summary["tests"] = tests
    revision, _ = repository_revision()
    summary["git_revision"] = revision
    summary.setdefault("gate1_satisfied", False)
    summary.setdefault(
        "gate1_note", "Standalone logs require Codex review before gate approval."
    )
    summary = update_validation_summary(
        summary,
        RESULTS_DIR / "xsim_stage1_status.txt",
        RESULTS_DIR / "xsim_stage2a_status.txt",
        require_stage2a=require_stage2a,
    )
    summary_path.write_text(
        json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    return summary_path


def collect_logs(stage2a=False):
    files = payload_files()
    manifest_path = write_source_manifest(files)
    summary_path = ensure_validation_summary(require_stage2a=stage2a)
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
