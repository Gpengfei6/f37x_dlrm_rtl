#!/usr/bin/env python3
"""Review copied A18.2 link metadata/timing. This is not a board PASS."""
from __future__ import print_function

import json
import sys
from pathlib import Path

import validate_stage2n_a18_2_artifacts_v1 as v

ROOT = Path(__file__).resolve().parent.parent
DEFAULT = ROOT / "docs/evidence/stage2n_a18_2/link_001"
EXPECTED_MANIFEST = "e59524bfb085adbeb2b8101b8072163f9c9c35154f89118b4faa2cdd1944c86d"


def main():
    directory = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT
    status_path = directory / "status.json"
    for name in ("status.json", "vivado_version.log", "vpp_version.log",
                 "xclbin.info", "connectivity.json", "mem_topology.json",
                 "ip_layout.json", "post_route.log",
                 "post_route/post_route_metrics.txt",
                 "post_route/post_route_timing_summary.rpt",
                 "post_route/post_route_check_timing.rpt"):
        path = directory / name
        v.require(path.is_file() and path.stat().st_size > 0, "missing " + name)
    status = json.loads(status_path.read_text(encoding="utf-8"))
    v.require(status.get("phase") == "link" and status.get("result") == "PASS",
              "status is not LINK PASS")
    v.require(status.get("kernel") == v.KERNEL, "wrong kernel in status")
    v.require(status.get("part") == v.PART, "wrong part in status")
    v.require(status.get("source_manifest_sha256") == EXPECTED_MANIFEST,
              "link source manifest does not match the closed A18.2 bundle")
    v.require(status.get("board") == "NOT_RUN" and
              status.get("performance") == "NOT_CLAIMED" and
              status.get("physical_mapping") == "NOT_RUN",
              "status overclaims board/performance/physical mapping")
    v.require(status.get("link_mapping") == "PASS", "link_mapping is not PASS")
    v.require(status.get("requested_clock_mhz") == 100, "requested clock is not 100 MHz")
    version = (directory / "vivado_version.log").read_text(encoding="utf-8", errors="replace")
    v.require("v2020.2" in version or "Vivado v2020.2" in version,
              "copied vivado_version.log is not Vivado 2020.2")
    vpp = (directory / "vpp_version.log").read_text(encoding="utf-8", errors="replace")
    v.require("v++ v2020.2" in vpp or "2020.2" in vpp, "copied v++ log is not 2020.2")
    mapping = v.linked_check(directory)
    v.require(mapping.get("xclbin_uuid") == status.get("xclbin_uuid"),
              "status UUID does not match xclbin.info")
    v.require(mapping.get("memory_indices_by_argument") ==
              status.get("memory_indices_by_argument"),
              "status memory indices do not match CONNECTIVITY")
    metrics = v.timing_check(directory / "post_route/post_route_metrics.txt")
    v.require(metrics.get("WNS_NS") == str(status.get("timing_metrics", {}).get("WNS_NS", "")),
              "status WNS does not match post_route metrics")
    print("A18_2_LINK_EVIDENCE_REVIEW=PASS")
    print("KERNEL=" + v.KERNEL)
    print("CU=" + v.CU)
    print("XCLBIN_UUID=" + mapping["xclbin_uuid"])
    print("MEMORY_INDICES_BY_ARGUMENT=" + ",".join(
        str(i) for i in mapping["memory_indices_by_argument"]))
    print("WNS_NS=" + metrics["WNS_NS"])
    print("TNS_NS=" + metrics["TNS_NS"])
    print("ACTUAL_KERNEL_CLOCK_NS=" + metrics.get("CLOCKS", ""))
    print("SOURCE_MANIFEST_SHA256=" + EXPECTED_MANIFEST)
    print("A18_2_BOARD=NOT_RUN")
    print("A18_2_PHYSICAL_MAPPING=NOT_RUN")
    print("A18_2_PERFORMANCE=NOT_CLAIMED")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as error:
        print("A18_2_LINK_EVIDENCE_REVIEW=FAIL: {}".format(error), file=sys.stderr)
        sys.exit(1)
