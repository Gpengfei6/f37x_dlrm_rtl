# Stage 2N-A16.2 — Target Build and Physical Sequential Latency Baseline Preparation (V1)

Date: 2026-08-31

Stage: `Stage 2N-A16.2` (LOCAL PREPARATION ONLY)

## Status

- `A16_2_LOCAL_PREPARATION=PASS`
- `A16_2_ABI_VALIDATION=PASS`
- `A16_2_PROTECTION_GATE=PASS`
- `TARGET_XO_BUILD=NOT_RUN_TARGET_REQUIRED`
- `TARGET_XCLBIN_LINK=NOT_RUN_TARGET_REQUIRED`
- `TARGET_TIMING=NOT_RUN_TARGET_REQUIRED`
- `A16_2_PHYSICAL_HBM_LATENCY=NOT_VALIDATED`
- `A16_2_PERFORMANCE=NOT_CLAIMED`
- `FROZEN_A15_RTL_MODIFIED=NO`
- `A16_1_RTL_MODIFIED=NO`
- `A15_XCLBIN_REBUILT=NO`
- `SERVER_ACCESS=NONE`
- `NETWORK_ACCESS=NONE`
- `FPGA_DEVICE_ACCESS=NONE`
- `READY_TO_TRANSFER_A16_2_TO_TARGET=YES`

### Post-preparation evidence status

The target XO/link/timing and protected five-case physical run subsequently
passed with lookup/compute/end-to-end/residual values `112/1174/1289/3`.
Those values reconcile with the frozen counter boundaries, and the compact
original status/log/metadata/post-route files are now curated and validated
locally. The authoritative follow-up is
`docs/STAGE2N_A16_2_FINAL_ACCEPTANCE_V1.md` and records:

```text
A16_2_FINAL_ACCEPTANCE=PASS
A16_2_LATENCY_ACCOUNTING_RECONCILIATION=EXPLAINED
READY_FOR_A16_3_ARCHITECTURE=YES_ACCEPTED_SEQUENTIAL_BASELINE
A16_3_STARTED=NO
```

The original preparation-time `NOT_RUN` entries above are retained as the
historical state of this document; they are not rewritten as locally verified
target PASS results.

## Motivation

The accepted A15.6 physical baseline proves that one F37X `HBM[0]` bank,
one AXI read master and four sequential embedding lookups can feed the full
accepted A13 Bottom–Interaction–Top pipeline and produce exact golden DLRM
results on the board. The accepted A16.1 stage then added two read-only
FPGA-side interval counters (`0x30C` HBM_LOOKUP_CYCLES, `0x310`
FPGA_END_TO_END_CYCLES) and validated them in local XSim.

A16.2 prepares, entirely locally, the complete reviewed target-build and
protected board-measurement flow that a future authorized target run can use to
establish the real F37X sequential-HBM latency baseline. No target build, no
`v++`, no xclbin, no device access and no performance claim are part of this
local stage.

## Frozen architecture

- One physical `HBM[0]` bank.
- One AXI read master (`m_axi_gmem`).
- Four sequential embedding lookups (rows 37, 38, 39, 40) through one accepted
  A14 v2 lookup engine.
- Embedding slots 0–3.
- Accepted A13 Bottom MLP → Feature Interaction → Top MLP pipeline.
- Final DLRM result and accepted A13 cycle counters.

This is ONE BANK + ONE AXI MASTER + FOUR SEQUENTIAL LOOKUPS. It is not four HBM
banks, parallel lookup, multiple AXI masters, bursts, or multiple outstanding
transactions.

## Frozen baselines

### A15.6 physical functional baseline

- Target: device index 2, BDF `0000:9b:00.1`, render `/dev/dri/renderD129`.
- Kernel `dlrm_f37x_rtl_kernel_stage2n_a15_v1`, CU `dlrm_a15_1`, HBM `HBM[0]`.
- Accepted xclbin SHA256
  `23ee48c91b3dfb5b68b3372ac49fc6607f203cf01d3b9fcfe04b4ea42be02356`,
  UUID `1b555645-a9e2-4f5e-95af-6ce4adacbc3c`.
- HBM BO: size 4096 bytes, physical address `0x0000000000000000` (valid HBM[0]
  base, not a null/allocation failure).
- Five golden cases all PASS: baseline `-393`, slot0 `-392`, slot1 `-93`,
  slot2 `-689`, slot3 `-519`.
- Compute counters frozen at Bottom 322, Interaction 100, Top 744, Compute
  Total 1174. `1174` is the compute-counter interval only and excludes the four
  HBM lookups, Host orchestration, BO transfer, PCIe and programming.

### A16.1 simulation latency baseline

- Accepted A16.1 RTL SHA256
  `a6eec09c4ebfe358751f7dfc31c2e77d509cd55d4fc8953f465a2227c3e7f7a5`.
- Two complete XSim invocations PASS; deterministic fake-AXI values:
  - `HBM_LOOKUP_CYCLES=73`
  - `COMPUTE_TOTAL=1174`
  - `FPGA_END_TO_END_CYCLES=1285`
  - pipeline/control overhead `38` cycles; `1285 = 73 + 1174 + 38`.
- `73` and `1285` are XSim/RTL simulation values, not physical F37X HBM
  latency.

## A16 ABI

New read-only A16 counters (custom AXI4-Lite registers, not Vitis kernel
arguments):

- `0x30C` HBM_LOOKUP_CYCLES
- `0x310` FPGA_END_TO_END_CYCLES

Preserved ABI:

- `0x218` Bottom, `0x21C` Interaction, `0x220` Top, `0x224` Compute Total
- `0x300` CONTROL/STATUS, `0x304` TABLE_BASE_LO, `0x308` TABLE_BASE_HI

## Kernel / CU / HBM connectivity

- Kernel: `dlrm_f37x_rtl_kernel_stage2n_a16_v1`
- CU: `dlrm_a16_1`
- Control: `s_axi_control` (AXI4-Lite slave)
- Memory master: `m_axi_gmem` (64-bit address, 128-bit data), exactly one
- HBM connectivity: `dlrm_a16_1.m_axi_gmem:HBM[0]`
- Kernel pointer argument: only `TABLE_BASE` at offset `0x304`, size 8,
  `void*`, addressQualifier 1, associated with `m_axi_gmem`.
- Obsolete A14 `LOOKUP_INDEX` / `RESULT0..3` signature must never reappear.

## Target build plan (future, user-executed)

1. `scripts/build_stage2n_a16_2_target_xo_v1.sh` — exact-VU37P XO-only package
   using `scripts/package_stage2n_a16_2_rtl_kernel_v1.tcl`, then validates
   kernel.xml/component.xml with `validate_stage2n_a16_2_xo_v1.py`.
2. `scripts/link_stage2n_a16_2_target_xclbin_v1.sh` — link-only flow consuming
   the accepted XO SHA256, one CU, `m_axi_gmem -> HBM[0]`, 100 MHz; extracts
   CONNECTIVITY/MEM_TOPOLOGY/IP_LAYOUT; validates with
   `validate_stage2n_a16_2_xclbin_v1.py`; reports post-route timing through
   `scripts/report_stage2n_a16_2_vitis_post_route_v1.tcl`.
3. `scripts/build_stage2n_a16_2_host_v1.sh` — XRT 2020.2 (`2.9.210507`) Host
   build-only gate with symbol/API probe.
4. `scripts/program_and_run_stage2n_a16_2_physical_latency_v1.sh` — protected
   board runner (see below).

## Metadata validation contract

- IP_LAYOUT must not require a single total entry; Vitis 2020.2 xclbins contain
  one `IP_KERNEL` plus shell/platform IPs. The validator filters
  `m_type == IP_KERNEL` and requires exactly one.
- CONNECTIVITY: exactly one record, `arg_index == 0`, `m_ip_layout_index`
  pointing at the unique IP_KERNEL, `mem_data_index` pointing at used `HBM[0]`.
- MEM_TOPOLOGY: the connected entry has tag `HBM[0]` and `m_used == 1`.
- kernel.xml: exactly one `TABLE_BASE` argument with correct offset/size/type/
  addressQualifier/port; stale A14 arguments rejected.

## Host validation plan

The Host is a minimal derivation of the accepted A15.6 Host:

- XRT 2020.2 API compatibility (`xclOpen`, `xclIPName2Index`, `xclOpenContext`,
  `xclRegRead/Write`, `xclAllocBO`, `xclGetBOProperties`, `xclMapBO`,
  `xclSyncBO`, `xclUnmapBO`, `xclFreeBO`).
- Physical `HBM[0]` BO allocation and `TABLE_BASE` programming/readback.
- Accepted model asset loading.
- The five A15.6 functional cases.
- Per-case reads of `0x218/0x21C/0x220/0x224` and the new `0x30C/0x310`.
- Explicit non-negative accounting check: the Host verifies
  `end_to_end >= lookup + compute` before subtraction, and
  `PIPELINE_OVERHEAD_CYCLES =
   FPGA_END_TO_END_CYCLES - HBM_LOOKUP_CYCLES - COMPUTE_TOTAL_CYCLES`
  is computed in signed 64-bit so an invalid result cannot become a huge
  unsigned value.
- BO cleanup and device close.

## Protected board execution plan (future, user-executed)

The runner requires explicit user-provided:

- `A16_2_TARGET_INDEX`
- `A16_2_TARGET_BDF`
- `A16_2_TARGET_RENDER`
- `A16_2_XCLBIN`
- `A16_2_EXPECTED_XCLBIN_SHA256`
- `A16_2_EXPECTED_UUID`

It never defaults to the historical index 2 / `9b` / `renderD129`. Before any
programming it checks device-index/BDF/render mapping, firewall GOOD, unused
render node, empty `HBM[0]`, xclbin SHA256/UUID, kernel identity, CU identity,
and (when the resident UUID differs) an explicit
`A16_2_ALLOWED_SOURCE_UUID`/`A16_2_ALLOWED_SOURCE_CU` allowlist. A simple
`yes`/`no` prompt authorizes programming; any other input exits safely. The
runner programs (`xbutil program`) only when needed, never resets the FPGA, and
never touches another device.

## Physical latency accounting

For each case the accepted Host and validator record:

- `HBM_LOOKUP_CYCLES` (`0x30C`)
- `BOTTOM_CYCLES` / `INTERACTION_CYCLES` / `TOP_CYCLES` /
  `COMPUTE_TOTAL_CYCLES`
- `FPGA_END_TO_END_CYCLES` (`0x310`)
- `PIPELINE_OVERHEAD_CYCLES = END_TO_END - LOOKUP - COMPUTE_TOTAL` (must be
  non-negative, checked before the unsigned-looking path)

## Performance claim boundary

- `FPGA_END_TO_END_CYCLES` is an FPGA-side hardware interval. At the requested
  100 MHz clock, 1 cycle corresponds to 10 ns in theory, but no physical
  nanosecond latency, bandwidth, throughput, speedup, power or energy claim is
  made before a real board run.
- The A16.1 XSim values 73/1285 are not physical latency.

## Local validation results (this stage)

The Windows-local preparation entry
`scripts/run_stage2n_a16_2_local_preparation_v1.ps1` passed:

- Branch `work/stage2n-a15-hbm-pipeline-integration` and HEAD
  `585ec44547dd9eaeee44c6b857bd49dfd279e275` confirmed; A16.1 baseline is an
  ancestor of HEAD.
- Frozen A16.1 RTL SHA256 `a6eec09c...` confirmed unchanged.
- `validate_stage2n_a16_2_sources_v1.py` PASS: 17-RTL source closure, one-CU/
  HBM[0] config, package tokens, stale A14 rejection, old-Git-safe target
  scripts, no network/device commands, Host ABI tokens, protected-runner tokens,
  authorization-before-programming, no FPGA reset, no destructive Git.
- `validate_stage2n_a16_2_xo_v1.py --self-test` PASS: 1 positive + 9 negative
  fixtures (wrong kernel, second master, stale LOOKUP_INDEX/RESULT0, wrong data/
  address width, wrong TABLE_BASE offset, wrong A16 counter offset, wrong target
  part).
- `validate_stage2n_a16_2_xclbin_v1.py --self-test` PASS: Vitis 2020.2 36-entry
  (1 IP_KERNEL + 35 shell) positive fixture + 12 negative fixtures (no/second
  IP_KERNEL, wrong kernel, wrong CU, wrong HBM bank, HBM[0] unused, second
  connectivity, wrong arg/IP-layout/mem-data index, stale A14 args).
- `validate_stage2n_a16_2_board_log_v1.py --self-test` PASS: 1 positive + 6
  negative fixtures (missing lookup, result mismatch, zero lookup, negative
  accounting, accounting mismatch, compute-ABI change).
- Old-Git compatibility scan of the four target shell scripts: PASS.
- `bash -n` on the four target shell scripts via Git Bash: PASS (recorded
  separately; the PS1 entry reports `BASH_SYNTAX=NOT_RUN_WINDOWS_BASH_UNAVAILABLE`
  because `bash` is not on the local PATH).

Key SHA256 values:

- A16.1 RTL: `a6eec09c4ebfe358751f7dfc31c2e77d509cd55d4fc8953f465a2227c3e7f7a5`
- Host: `d2c4036bcaccba702d70fe772a436501568c593dd5b92bc08edb7d7502dafc99`
- Protected runner:
  `8370ec2f6128243a5f15e7a83a8c0c432b2cde6bf959504769d71323dc31c3ba`
- XO validator: `9be25c6d8ba74dd77e5ffaa0cbf291d1be61a750fe44e3b823d359a641527b4f`
- xclbin validator:
  `764a6bb8d6a45c32aa7415ee6303edf5efbeffc19369216c62217bc9aeafacf6`

## Known limitations

- No XO, xclbin, routed DCP, or board log exists locally.
- Vivado 2020.2 / Vitis / exact VU37P platform database are absent locally.
- `BASH_SYNTAX` in the PS1 status is `NOT_RUN_WINDOWS_BASH_UNAVAILABLE`;
  a manual `bash -n` run with Git Bash passed all four target scripts.
- XSim values 73/1285 are fake-memory simulation values, not physical latency.

## Target transfer plan (future, user-executed)

The user may manually transfer the reviewed A16.2 files to the controlled
target environment and run, in order:

1. `scripts/build_stage2n_a16_2_target_xo_v1.sh`
2. `scripts/link_stage2n_a16_2_target_xclbin_v1.sh`
3. `scripts/build_stage2n_a16_2_host_v1.sh`
4. `scripts/program_and_run_stage2n_a16_2_physical_latency_v1.sh`

and return the retained status/log/evidence files for a separate acceptance
review.

## Next acceptance criteria

- Review of this preparation and the retained local evidence.
- Separate authorization for the target XO build, link and physical run.
- Target evidence records: exact XO/xclbin identity (SHA256/UUID), one-CU
  `HBM[0]` mapping, 100 MHz routed timing, Host XRT 2020.2 build, the five
  functional cases, and per-case `HBM_LOOKUP_CYCLES` / `FPGA_END_TO_END_CYCLES`
  / non-negative overhead accounting.
- Only after a real sequential target baseline exists may any later multi-bank
  or parallel design be compared.
