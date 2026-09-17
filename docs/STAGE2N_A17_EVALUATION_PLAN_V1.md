# Stage 2N-A17 Evaluation Plan V1

Date: 2026-09-08. Status: **PAPER EXPERIMENT DESIGN**. Not a physical result.

A17 implementation work is paused. This document is the evaluation chapter
skeleton: accepted evidence stays filled; future board cells stay empty until
an authorized F37X run returns logs. It does not modify RTL, testbenches, Host,
or live `config/`.

Allowed paper sentence now:

> This work describes a multi-bank-capable FPGA embedding-access
> architecture and a verification framework, compared against an accepted
> single-bank sequential baseline.

Forbidden as a **measured result** until an authorized A17.6 run meets the
execution gate **and** a comparable measurement exists:

> physical four-bank HBM operation, or achieved multi-bank HBM acceleration.

Describing the intended architecture is allowed. Mapping PASS alone is not
a performance claim.

GPT’s later board-experiment label **A17.6 Physical Four-Bank Validation** is
the same pending physical comparison. Locally it remains
`A17_5C_PHYSICAL_MULTI_BANK_VALIDATION=NOT_RUN` /
`WAITING AUTHORIZATION`. Do not expand A17.5C checklists further.

Prose files:

- V1 path (academic refinement, overwritten in place):
  `docs/STAGE2N_A17_PAPER_CHAPTER_MULTIBANK_LOOKUP_V1.md`
- V2 (independent methodology chapter):
  `docs/STAGE2N_A17_PAPER_CHAPTER_MULTIBANK_LOOKUP_V2.md`
- V3 (writing integration only):
  `docs/STAGE2N_A17_PAPER_CHAPTER_MULTIBANK_LOOKUP_V3.md`

Keep Results cells in §5 empty until user-returned A17.6 logs exist. The
≈1.07× / ≈1.10× sensitivity numbers are **not** Results; they are in §7.

## 1. Baseline

Accepted physical sequential baseline: Stage 2N-A16.2.

| Item | Value |
|---|---|
| Kernel / CU | `dlrm_f37x_rtl_kernel_stage2n_a16_v1` / `dlrm_a16_1` |
| Mapping | `m_axi_gmem -> HBM[0]` |
| Clock | 100 MHz, WNS/TNS `0.000/0.000 ns` |
| Lookup / compute / FPGA e2e / residual | `112 / 1174 / 1289 / 3` cycles |
| Function | five trained-model cases `-393/-392/-93/-689/-519` |
| Performance | `NOT_CLAIMED` |

Lookup is `112/1289 ≈ 8.7%` of FPGA e2e. Compute is `1174/1289 ≈ 91%`.
XSim fake-memory values (`24/1256` on A17.3, `73/1174/1285/38` on A16.1) are
not this baseline.

## 2. Architecture under test

A17 public top `dlrm_f37x_rtl_kernel_stage2n_a17_v1`:

- four independent A14 v2 single-beat read engines;
- public masters `m_axi_gmem0..3`;
- four captured bases BASE0–BASE3;
- gather-then-inject into unchanged A13 Bottom–Interaction–Top;
- A16 inclusive counters at `0x30C` / `0x310`.

Local XSim (A17.3): golden result 36 on the A13 sample; compute counters
`322/100/744/1174`. That proves logical four-master function, not four
physical banks.

## 3. Verification methodology

| Layer | What it proves | What it does not prove |
|---|---|---|
| A17.1 | Four-engine gather, reorder, stall, error drain | Packaged Vitis masters |
| A17.2/A17.3 | Public-port XSim of `gmem0..3` | XO/xclbin, HBM, latency |
| A17.4–A17.5B | Mapping/Host/evidence plan | Live `sp`, four BOs |
| A17.5C gate | Pre-run checklist | Any board PASS |
| Authorized physical run | Four-bank map + measured counters | Speedup unless comparison rules below hold |

Comparison rules for the future board experiment:

1. Same five A16.2 payloads and expected results.
2. Same 100 MHz request and inclusive counter edges.
3. Mapping PASS (unique `HBM[0..3]`) is independent of e2e reduction.
4. Report lookup, compute, e2e, residual separately.
5. Do not convert a single-job latency ratio into throughput.

## 4. HBM mapping strategy

Proposed, not linked:

```text
dlrm_a17_1.m_axi_gmem0:HBM[0]
dlrm_a17_1.m_axi_gmem1:HBM[1]
dlrm_a17_1.m_axi_gmem2:HBM[2]
dlrm_a17_1.m_axi_gmem3:HBM[3]
```

Runtime: four BOs, `xclRegWrite` BASE0–BASE3 from paddrs, mem index from
`MEM_TOPOLOGY` tags. First fixture copies the canonical 1024-byte table into
each BO (concurrency fixture, not four business tables). A18 placement remains
unauthorized.

## 5. Expected evaluation (empty Results cells)

Fill only from authorized logs. Do not copy A16.2 numbers into the A17
measured row.

| Metric | A16.2 (accepted) | A17 physical (pending) |
|---|---|---|
| Banks used | `HBM[0]` | `NOT_RECORDED` |
| Unique four-bank map | no | `NOT_RECORDED` |
| Five-case function | PASS | `NOT_RECORDED` |
| Lookup cycles | 112 | `NOT_RECORDED` |
| Compute total | 1174 | `NOT_RECORDED` |
| FPGA e2e | 1289 | `NOT_RECORDED` |
| Residual | 3 | `NOT_RECORDED` |
| Speedup | not claimed | not claimed until rules in §3 hold |

Do not put the 28-cycle / ≈1.07× / ≈1.10× sensitivity rows in this table.
Those calculations assume fixed compute, residual, and clock; they belong
in §7 (analytical bounds), not in Results.

## 6. Current A17 status (local)

| Stage | Result | Boundary |
|---|---|---|
| A16.2 | Physical single-HBM baseline PASS | `112/1174/1289/3` |
| A17.1 | Four-engine architecture XSim PASS | packed local ports |
| A17.2/A17.3 | Public kernel XSim PASS | fake memory |
| A17.4 | Mapping preparation PASS | proposal only |
| A17.5A | Packaging audit PASS | no live `config/` |
| A17.5B | Physical-validation prep PASS | templates empty |
| A17.5C | Execution gate PREPARED | not a board PASS |
| A17.5C-PHYSICAL / A17.6 | WAITING AUTHORIZATION | no XO/xclbin/XRT |

Next engineering value is user-authorized F37X XO, link, program, four-BO
map, and latency logs. Until then, do not add A17 RTL, Host, or live
connectivity.

## 7. Analytical bounds (not Results)

Hold compute = 1174, residual = 3, and clock fixed. Then
`L_FPGA ≈ 112/s + 1177`. A hypothetical fourfold lookup interval (28 cycles)
gives about 1205 cycles (`1289/1205 ≈ 1.07`). An algebraic zero-lookup
limit gives about 1177 cycles (`≈1.10`). Only A16.2’s 112/1289 row is
measured. A16.2 is already compute-dominated; these rows are not observed
bottleneck migration and are not A17 predictions or gates.
