# Stage 2N-A16.2 Final Acceptance V1

Date: 2026-08-31

## 1. Current decision

The user has reported a successful exact-target A16.2 XO/xclbin build and a
successful protected five-case F37X latency run. The compact raw target and
board evidence is not present in this local repository or under
`_local_recovery/stage2n_a16_2_final_evidence/`; only the earlier transfer
bundle is present. Consequently the reported values are recorded below for
reconciliation, but final acceptance is deliberately not promoted to PASS.

```text
A16_2_FINAL_ACCEPTANCE=PENDING_EVIDENCE_IMPORT
A16_2_REPORTED_TARGET_XO_BUILD=PASS_UNVERIFIED_LOCALLY
A16_2_REPORTED_TARGET_LINK=PASS_UNVERIFIED_LOCALLY
A16_2_REPORTED_TARGET_TIMING=PASS_UNVERIFIED_LOCALLY
A16_2_REPORTED_PHYSICAL_HBM_LATENCY=PASS_UNVERIFIED_LOCALLY
A16_2_LATENCY_ACCOUNTING_RECONCILIATION=EXPLAINED
A16_2_PERFORMANCE=NOT_CLAIMED
FROZEN_RTL_MODIFIED=NO
XCLBIN_REBUILT_LOCALLY=NO
NETWORK_ACCESS=NONE
SERVER_ACCESS=NONE
FPGA_DEVICE_ACCESS=NONE
READY_FOR_A16_3_ARCHITECTURE=NO_PENDING_EVIDENCE_IMPORT
```

This document becomes a final PASS record only after the compact original
status/log/metadata/post-route files are imported and the offline acceptance
gate passes. A textual result supplied in the task is not substituted for raw
evidence.

## 2. Frozen source identity

| Item | Frozen value |
|---|---|
| Branch | `work/stage2n-a15-hbm-pipeline-integration` |
| A16.2 preparation HEAD | `a1fdc71097f9969c8e982926a1ce1615a0c3254e` |
| A16.1 kernel | `dlrm_f37x_rtl_kernel_stage2n_a16_v1` |
| A16.1 RTL SHA256 | `a6eec09c4ebfe358751f7dfc31c2e77d509cd55d4fc8953f465a2227c3e7f7a5` |
| A16.2 Host source SHA256 | `d2c4036bcaccba702d70fe772a436501568c593dd5b92bc08edb7d7502dafc99` |
| Protected runner SHA256 | `8370ec2f6128243a5f15e7a83a8c0c432b2cde6bf959504769d71323dc31c3ba` |

The frozen RTL, Host behavior, register ABI, model assets and protected runner
were not edited during this reconciliation.

## 3. User-reported target build result pending import

The following values are reported by the user and are gates in the offline
validator. They are not yet independently accepted by this local checkout.

| Item | User-reported value |
|---|---|
| XO SHA256 | `ea0fe950339ada07eaacd181c495dcb1f07251ed20e7d1cef44479bc36cec94a` |
| xclbin SHA256 | `5f0d6fefab1549d2e1969df3d8775409bbfac33cb46d07e7abde99abdf04b8b4` |
| xclbin UUID | `f18571de-4a43-46bd-8ab9-a89dd4b11f8e` |
| Kernel | `dlrm_f37x_rtl_kernel_stage2n_a16_v1` |
| Compute unit | `dlrm_a16_1` |
| Connectivity | `dlrm_a16_1.m_axi_gmem:HBM[0]` |
| Kernel argument | `TABLE_BASE`, offset `0x304`, size 8, `void*`, addressQualifier 1 |
| Part / platform | `xcvu37p-fsvh2892-2L-e` / `inspur_f37x_xdma_201920_3` |
| Requested clock | 100 MHz / 10.000 ns |
| WNS / TNS / failing endpoints | `0.000 ns` / `0.000 ns` / `0` |
| LUT / FF | `135153` / `161849` |
| RAMB36 / RAMB18 / URAM / DSP | `215` / `89` / `0` / `43` |
| Latch | `0` |
| DRC errors / critical warnings | `0` / `0` |
| Methodology errors / critical warnings | `0` / `55` |

WNS `0.000 ns` supports only the statement that the requested 100 MHz gate was
reported as passing. It does not establish positive timing headroom. The 55
methodology critical warnings remain explicit and cannot be summarized as zero
warnings. The resources cover the linked platform design, not a kernel-only
increment.

The reported XRT environment is `2.9.210507`. The reported Host binary SHA256
is `de0abefc0b4dbadf74dd69e6875db9051a18ab34d8ab1a6a747073cb436d6f1b`.

## 4. User-reported protected board result pending import

The reported protected run used device index 2, BDF `0000:9b:00.1`, render node
`/dev/dri/renderD129`, one 4096-byte BO in `HBM[0]`, and the returned physical
address `0x0`. The reported prior UUID/CU was explicitly allowlisted;
programming passed without FPGA reset, global HBM cleanup or access to another
device.

| Case | Expected | Reported actual | Bottom / Interaction / Top / Total | Lookup / FPGA e2e / residual |
|---|---:|---:|---|---|
| 0 baseline | -393 | -393 | 322 / 100 / 744 / 1174 | 112 / 1289 / 3 |
| 1 slot0 | -392 | -392 | 322 / 100 / 744 / 1174 | 112 / 1289 / 3 |
| 2 slot1 | -93 | -93 | 322 / 100 / 744 / 1174 | 112 / 1289 / 3 |
| 3 slot2 | -689 | -689 | 322 / 100 / 744 / 1174 | 112 / 1289 / 3 |
| 4 slot3 | -519 | -519 | 322 / 100 / 744 / 1174 | 112 / 1289 / 3 |

The reported relationship is exact for every case:

```text
112 + 1174 + 3 = 1289
```

The five exact results, mask `0xF`, cleanup and log markers remain pending raw
evidence import before final board/physical-latency acceptance.

## 5. Counter boundaries and reconciliation

Define five rising-edge event numbers:

- `S`: accepted A15 START write;
- `A`: first `m_axi_gmem` AR handshake;
- `D`: fourth-slot injection / successful HBM sequence completion;
- `C`: accepted automatic A13 pipeline START; and
- `F`: first final-result visibility.

All three hardware counters include their start and stop edges:

```text
FPGA_END_TO_END_CYCLES = F - S + 1
HBM_LOOKUP_CYCLES      = D - A + 1
COMPUTE_TOTAL_CYCLES   = F - C + 1

ACCOUNTING_RESIDUAL
  = FPGA_END_TO_END_CYCLES - HBM_LOOKUP_CYCLES - COMPUTE_TOTAL_CYCLES
  = (A - S) + (C - D) - 1
```

The Host field is named `PIPELINE_OVERHEAD_CYCLES`, but mathematically it is an
algebraic interval residual. It is not a separately instrumented stage.

The A16.1 XSim values are `73/1174/1285/38`; the user-reported physical values
are `112/1174/1289/3`. Their deltas are:

```text
lookup +39, compute 0, end-to-end +4, residual -35
```

This is consistent with the frozen event definitions. The local self-checking
test deliberately adds AXI-Lite status/mask transactions, a four-edge ARREADY
stall, and a repeated-START/error-read/error-ack sequence before the first AR
handshake. Those cycles are inside `S..F` but outside `A..D`, increasing the
XSim residual. The physical Host does not insert this testbench-only pre-first-
AR stress sequence. Conversely, the real platform/interconnect/HBM service is
inside `A..D`, producing the longer reported physical lookup interval.

Because the accepted compute interval remains exactly 1174 cycles and all five
reported functional results remain exact, the source audit found no counter
semantic or arithmetic regression. The available evidence explains the
accounting shift, but without an internal physical event trace it does not
claim a unique cycle-by-cycle split of the two residual gaps.

The reproducible analysis is retained in
`docs/evidence/stage2n_a16_2/latency_accounting_reconciliation_v1.txt`.
The local validation and missing-evidence gate are retained in
`docs/evidence/stage2n_a16_2/final_acceptance_precheck_v1.txt`.

## 6. Required compact evidence import

The expected server result root reported by the user is:

```text
results/stage2n_a16_2/
  target_xo_v1/
  target_link_v1/
  physical_latency_v1/20260831_182443/
```

The local import gate is:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File scripts/import_stage2n_a16_2_final_evidence_v1.ps1 `
  -SourceRoot _local_recovery/stage2n_a16_2_final_evidence `
  -PythonExe <local-python3.exe>
```

It accepts only a source under repository `_local_recovery`, refuses to
overwrite an existing destination, imports only small whitelisted status,
metadata, JSON, report, Host/runner and query files, excludes XO/xclbin/DCP and
build trees, runs the offline validator, and creates a SHA256 manifest. The
normalized destination will be:

`docs/evidence/stage2n_a16_2/final_acceptance_v1/`

The transfer package must also include the small target Host build status from
`build/stage2n_a16_2/host_v1/host_build_status.txt`; the importer uses it to
verify the reported XRT version and Host source/binary hashes.

The validator is:

```text
scripts/validate_stage2n_a16_2_final_evidence_v1.py
```

It fail-closes on changed artifact identities, kernel/CU/HBM metadata, target
metrics, five-case outputs/counters, safety markers, Host build identity or
local frozen source hashes.

## 7. Evidence boundary and next gate

Current local evidence proves the A16.1 counter design/XSim result, A16.2 local
preparation, and the source-level explanation of the two timing partitions. It
does not yet locally prove the user-reported target artifact or board run.

Until the compact originals are imported and validated:

- `A16_2_FINAL_ACCEPTANCE=PENDING_EVIDENCE_IMPORT`;
- `READY_FOR_A16_3_ARCHITECTURE=NO_PENDING_EVIDENCE_IMPORT`;
- multi-bank/parallel lookup work must not begin from the reported numbers as
  an accepted baseline; and
- latency improvement, bandwidth, throughput, speedup, power, energy and
  performance remain unclaimed.

After a successful import, the intended frozen sequential comparison baseline
is lookup 112 cycles and complete FPGA interval 1289 cycles under the same
counter boundaries and five-case functional contract. A later architecture
must use equivalent event boundaries and workload before any comparison.
