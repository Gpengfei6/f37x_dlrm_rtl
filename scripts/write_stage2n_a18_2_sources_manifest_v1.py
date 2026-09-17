#!/usr/bin/env python3
from pathlib import Path
import hashlib
import json
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import validate_stage2n_a18_2_artifacts_v1 as v  # noqa: E402


def digest(path):
    hasher = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            hasher.update(block)
    return hasher.hexdigest()


def main():
    files = v.source_files(ROOT) + [
        v.PACKAGE, v.CONFIG, v.REPORT,
        "scripts/validate_stage2n_a16_2_xo_v1.py",
        "scripts/validate_stage2n_a16_2_xclbin_v1.py",
        "scripts/validate_stage2n_a18_2_artifacts_v1.py",
        "scripts/run_stage2n_a18_2_build_v1.py",
        "scripts/test_stage2n_a18_2_build_v1.py",
        "docs/STAGE2N_A18_2_TARGET_PACKAGING_HOST_PREP_V1.md",
    ]
    manifest = {
        "schema": "a18_2_source_manifest_v1",
        "files": {rel.replace("\\", "/"): digest(ROOT / rel) for rel in files},
    }
    out = ROOT / v.MANIFEST
    out.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("WROTE", out)
    print("COUNT", len(manifest["files"]))


if __name__ == "__main__":
    main()
