# Stage 2N-A16.2 Final Acceptance V1

Date: 2026-08-31

## 1. Current decision

The compact exact-target and protected-board evidence has been imported under
`docs/evidence/stage2n_a16_2/final_acceptance_v1/`. The offline validator checks
the fixed artifact identities, target metadata and reports, Host build, all
five board cases, latency accounting, cleanup and safety markers, and local
frozen-source hashes. The repaired progressive-marker parser and the complete
imported evidence both pass.

```text
A16_2_FINAL_ACCEPTANCE=PASS
A16_2_TARGET_XO_BUILD=PASS
A16_2_TARGET_LINK=PASS
A16_2_TARGET_TIMING=PASS
A16_2_PHYSICAL_HBM_LATENCY=PASS
A16_2_LATENCY_ACCOUNTING_RECONCILIATION=EXPLAINED
A16_2_PERFORMANCE=NOT_CLAIMED
FROZEN_RTL_MODIFIED=NO
XCLBIN_REBUILT_LOCALLY=NO
NETWORK_ACCESS=NONE
SERVER_ACCESS=NONE
FPGA_DEVICE_ACCESS=NONE
READY_FOR_A16_3_ARCHITECTURE=YES_ACCEPTED_SEQUENTIAL_BASELINE
A16_3_STARTED=NO
```

This acceptance does not start A16.3 and does not establish a performance,
bandwidth, throughput, speedup, power or energy result.

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

## 3. Accepted target build result

The following values are present in the imported raw target evidence and pass
the offline acceptance gate.

| Item | Accepted value |
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

WNS `0.000 ns` supports only the statement that the requested 100 MHz gate
passes. It does not establish positive timing headroom. The 55
methodology critical warnings remain explicit and cannot be summarized as zero
warnings. The resources cover the linked platform design, not a kernel-only
increment.

The accepted XRT environment is `2.9.210507`. The accepted Host binary SHA256
is `de0abefc0b4dbadf74dd69e6875db9051a18ab34d8ab1a6a747073cb436d6f1b`.

## 4. Accepted protected board result

The protected run used device index 2, BDF `0000:9b:00.1`, render node
`/dev/dri/renderD129`, one 4096-byte BO in `HBM[0]`, and the returned physical
address `0x0`. The prior UUID/CU was explicitly allowlisted;
programming passed without FPGA reset, global HBM cleanup or access to another
device.

| Case | Expected | Actual | Bottom / Interaction / Top / Total | Lookup / FPGA e2e / residual |
|---|---:|---:|---|---|
| 0 baseline | -393 | -393 | 322 / 100 / 744 / 1174 | 112 / 1289 / 3 |
| 1 slot0 | -392 | -392 | 322 / 100 / 744 / 1174 | 112 / 1289 / 3 |
| 2 slot1 | -93 | -93 | 322 / 100 / 744 / 1174 | 112 / 1289 / 3 |
| 3 slot2 | -689 | -689 | 322 / 100 / 744 / 1174 | 112 / 1289 / 3 |
| 4 slot3 | -519 | -519 | 322 / 100 / 744 / 1174 | 112 / 1289 / 3 |

The relationship is exact for every case:

```text
112 + 1174 + 3 = 1289
```

All five exact results, mask `0xF`, BO cleanup and protected-runner markers pass
the imported-evidence validator.

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

The A16.1 XSim values are `73/1174/1285/38`; the accepted physical values
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
inside `A..D`, producing the longer accepted physical lookup interval.

Because the accepted compute interval remains exactly 1174 cycles and all five
accepted functional results remain exact, the source audit found no counter
semantic or arithmetic regression. The available evidence explains the
accounting shift, but without an internal physical event trace it does not
claim a unique cycle-by-cycle split of the two residual gaps.

The reproducible analysis is retained in
`docs/evidence/stage2n_a16_2/latency_accounting_reconciliation_v1.txt`.
The local validation and missing-evidence gate are retained in
`docs/evidence/stage2n_a16_2/final_acceptance_precheck_v1.txt`.

## 6. Imported compact evidence

The original compact evidence was recovered from the following result groups:

```text
results/stage2n_a16_2/
  target_xo_v1/
  target_link_v1/
  physical_latency_v1/20260831_182443/
```

The archive and local import identities are:

```text
ARCHIVE_SHA256=83508c00c58a52e7154bacd5cd2277c34e27fdf4c1900ac51246d3aa088de061
EXTRACTED_RAW_EVIDENCE_FILE_COUNT=30
IMPORTED_EVIDENCE_MANIFEST_ENTRY_COUNT=31
IMPORTED_EVIDENCE_MANIFEST_SHA256=fc2a900c70a16c5be931cb8518ea96495490441e070bbf1a78ce5e716596c568
IMPORTED_VALIDATION_LOG_SHA256=87952dc818e03e9f955e27bed62c16a3cc2a823fd9b0fd64e39b9b8d5618af00
```

The non-overwriting importer retained only the whitelisted small status,
metadata, JSON, report, Host/runner and query files. XO, xclbin, DCP and target
build trees were not imported. The normalized destination is:

`docs/evidence/stage2n_a16_2/final_acceptance_v1/`

The imported Host build status verifies the XRT version and Host source/binary
hashes. `IMPORTED_EVIDENCE_SHA256.txt` covers every imported file that existed
when the manifest was generated.

The validator is:

```text
scripts/validate_stage2n_a16_2_final_evidence_v1.py
```

It fail-closes on changed artifact identities, kernel/CU/HBM metadata, target
metrics, five-case outputs/counters, safety markers, Host build identity or
local frozen source hashes. Its independent post-import run reports
`A16_2_FINAL_EVIDENCE_VALIDATION=PASS` and 31 validated manifest entries.
The local acceptance transcript is retained at
`docs/evidence/stage2n_a16_2/final_acceptance_validation_v1.txt`.

## 7. Evidence boundary and next gate

The evidence proves the exact A16 XO/link identity, the requested 100 MHz timing
gate, one `m_axi_gmem -> HBM[0]` connection, the protected F37X execution, five
exact complete-DLRM results, and the sequential physical lookup/complete-FPGA
counter baseline of 112/1289 cycles under the documented boundaries.

It does not prove multi-bank or parallel lookup, bandwidth, throughput,
latency improvement, speedup, power, energy or any general performance claim.
A16.3 has not started. Any later architecture must use equivalent event
boundaries and workload before comparison.
