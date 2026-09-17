#!/usr/bin/env python3
"""Cheap existence/syntax check for A18 variable-index RTL. Not a sim PASS."""

from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
files = [
    ROOT / "rtl/pipeline/dlrm_hbm_pipeline_integration_stage2n_a18_v1.sv",
    ROOT / "rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a18_v1.sv",
    ROOT / "tb/tb_dlrm_f37x_rtl_kernel_stage2n_a18_v1.sv",
    ROOT / "scripts/run_stage2n_a18_variable_index_xsim_v1.ps1",
    ROOT / "scripts/run_stage2n_a18_variable_index_xsim_v1.tcl",
    ROOT / "docs/STAGE2N_A18_VARIABLE_INDEX_RTL_V1.md",
]
fail = 0
for p in files:
    if not p.is_file():
        print("MISSING", p.relative_to(ROOT))
        fail = 1
        continue
    text = p.read_text(encoding="utf-8", errors="replace")
    if p.suffix == ".sv":
        if "module " not in text:
            print("NO_MODULE", p.name)
            fail = 1
        if p.name.endswith("_a18_v1.sv") and "endmodule" not in text:
            print("NO_ENDMODULE", p.name)
            fail = 1
    print("OK", p.relative_to(ROOT), "bytes", p.stat().st_size)

kernel = (ROOT / "rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a18_v1.sv").read_text(
    encoding="utf-8", errors="replace"
)
for addr in ("12'h330", "12'h334", "12'h338", "12'h33C"):
    if addr not in kernel:
        print("KERNEL_MISSING_ADDR", addr)
        fail = 1
if "a18_lookup_index_cmd <= a18_lookup_index_stage" not in kernel:
    print("KERNEL_MISSING_INDEX_LATCH_ON_START")
    fail = 1
if "dlrm_internal_pipeline_axi_lite_decode_stage2n_a18_v1" in kernel:
    print("KERNEL_STILL_USES_GUESSED_DECODE")
    fail = 1
if "dlrm_internal_pipeline_axi_lite_adapter_stage2n_a18_v1" not in kernel:
    print("KERNEL_MISSING_A17_DERIVED_ADAPTER")
    fail = 1
if "(a15_state != A15_DONE) &&" not in kernel:
    print("KERNEL_MISSING_A17_CLEAR_GUARD")
    fail = 1
integ = (ROOT / "rtl/pipeline/dlrm_hbm_pipeline_integration_stage2n_a18_v1.sv").read_text(
    encoding="utf-8", errors="replace"
)
if "lookup_index" not in integ:
    print("INTEGRATION_MISSING_LOOKUP_INDEX")
    fail = 1
if re.search(r"32'd40,\s*32'd39,\s*32'd38,\s*32'd37", integ):
    print("INTEGRATION_STILL_HARDCODES_INDEXES")
    fail = 1
if "assign lookup_indexes = lookup_index;" not in integ:
    print("INTEGRATION_MISSING_INDEX_PORT_WIRE")
    fail = 1
if "index_oob" not in integ:
    print("INTEGRATION_MISSING_OOB_PRECHECK")
    fail = 1

tb = (ROOT / "tb/tb_dlrm_f37x_rtl_kernel_stage2n_a18_v1.sv").read_text(
    encoding="utf-8", errors="replace"
)
for marker in (
    "A18_1_CASE_A_DEFAULT_37_40_GOLDEN36=PASS",
    "A18_1_CASE_H_OOB_FFFFFFFF=PASS",
    "expected_row",
):
    if marker not in tb:
        print("TB_MISSING", marker)
        fail = 1

print("A18_VARIABLE_INDEX_EXISTENCE_CHECK=" + ("PASS" if fail == 0 else "FAIL"))
sys.exit(fail)
