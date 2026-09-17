#!/usr/bin/env python3
"""Review copied A18.2 XO logs/XML. This is not a board or link PASS."""
from __future__ import print_function

import json
import sys
from pathlib import Path

import validate_stage2n_a18_2_artifacts_v1 as v

ROOT = Path(__file__).resolve().parent.parent
DEFAULT = ROOT / "docs/evidence/stage2n_a18_2/xo_001"
EXPECTED_MANIFEST = "e59524bfb085adbeb2b8101b8072163f9c9c35154f89118b4faa2cdd1944c86d"


def main():
    directory = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT
    status_path = directory / "status.json"
    version_path = directory / "vivado_version.log"
    kernel_xml = directory / "xo/kernel.xml"
    component_xml = directory / "xo/dlrm_f37x_stage2n_a18_ip_v1/component.xml"
    for path in (status_path, version_path, kernel_xml, component_xml,
                 directory / "package.log"):
        v.require(path.is_file() and path.stat().st_size > 0, "missing " + str(path))
    status = json.loads(status_path.read_text(encoding="utf-8"))
    v.require(status.get("phase") == "xo" and status.get("result") == "PASS",
              "status is not XO PASS")
    v.require(status.get("kernel") == v.KERNEL, "wrong kernel in status")
    v.require(status.get("part") == v.PART, "wrong part in status")
    v.require(status.get("source_manifest_sha256") == EXPECTED_MANIFEST,
              "XO source manifest does not match the closed A18.2 bundle")
    v.require(status.get("board") == "NOT_RUN" and status.get("performance") == "NOT_CLAIMED",
              "status overclaims board/performance")
    v.require(status.get("target_link") == "NOT_RUN", "XO status must leave link NOT_RUN")
    version = version_path.read_text(encoding="utf-8", errors="replace")
    v.require("v2020.2" in version or "Vivado v2020.2" in version,
              "copied vivado_version.log is not Vivado 2020.2")
    artifacts = status.get("artifacts") or {}
    expected = {
        "xo/kernel.xml": kernel_xml,
        "xo/dlrm_f37x_stage2n_a18_ip_v1/component.xml": component_xml,
    }
    for relative, path in expected.items():
        digest = artifacts.get(relative)
        v.require(digest == v.digest(path), "copied {} hash mismatch".format(relative))
    v.kernel_check(kernel_xml.read_bytes())
    v.component_check(component_xml.read_bytes())
    print("A18_2_XO_EVIDENCE_REVIEW=PASS")
    print("KERNEL=" + v.KERNEL)
    print("PART=" + v.PART)
    print("SOURCE_MANIFEST_SHA256=" + EXPECTED_MANIFEST)
    print("VIVADO=2020.2")
    print("POINTER_ARGS=TABLE_BASE0..3")
    print("LOOKUP_INDEX_KERNEL_ARGS=ABSENT")
    print("A18_2_TARGET_LINK=NOT_RUN")
    print("A18_2_BOARD=NOT_RUN")
    print("A18_2_PERFORMANCE=NOT_CLAIMED")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as error:
        print("A18_2_XO_EVIDENCE_REVIEW=FAIL: {}".format(error), file=sys.stderr)
        sys.exit(1)
