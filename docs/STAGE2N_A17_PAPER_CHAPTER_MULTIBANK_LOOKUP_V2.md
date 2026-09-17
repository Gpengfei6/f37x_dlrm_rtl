# Multi-bank-capable Embedding Lookup Architecture

Draft: V2. Date: 2026-09-08. Status: **thesis-style methodology chapter**.

This file is an **independent** methodology draft created by Cursor. It did
not overwrite V1. The V1 path was later rewritten in place by a separate
academic pass; recover the first engineering text from
`docs/STAGE2N_A17_PAPER_CHAPTER_MULTIBANK_LOOKUP_V1_ENGINEERING_SNAPSHOT.md`.
The paper-integrated writing draft is V3.

This document does not add experiments, change RTL, or fill empty
physical-A17 result cells. Quantitative facts are those already accepted on
F37X for Stage 2N-A16.2, plus local A17 simulation and documentation status.
A18 is named only as future work.

## Claim boundary

Allowed:

- describe a *multi-bank-capable architecture design* and a layered
  *verification framework* against an accepted single-bank sequential
  baseline.

Forbidden as a **measured result** until an authorized A17.6 board run meets
the execution gate **and** a comparable measurement exists:

- physical four-bank HBM operation on F37X;
- achieved multi-bank HBM acceleration, latency reduction, bandwidth,
  throughput, or speedup;
- any statement that A18 already jointly optimizes storage and compute.

A later mapping PASS still does not by itself authorize a performance claim.

## 1. Motivation: from measured split to research question

Deep Learning Recommendation Model (DLRM) inference couples two costs that
must not be collapsed into a single “accelerator latency” number. Sparse
embedding lookup is a short-vector memory access problem: several rows must
be read from HBM before Feature Interaction and Top MLP may start. Dense
Bottom MLP, Feature Interaction, and Top MLP are a neural-computation
problem: they occupy the accepted Stage 2N-A13 engine and dominate the
FPGA-visible interval once embeddings are present.

Stage 2N-A16.2 makes that split quantitative on one Inspur F37X card, one
AXI master, and one `HBM[0]` bank at a requested 100 MHz kernel clock:

| Interval | Definition | Accepted cycles |
|---|---|---|
| Lookup | first AR handshake through four-slot injection | 112 |
| Compute | A13 Bottom + Interaction + Top | 1174 |
| FPGA end-to-end | accepted START through first result | 1289 |
| Residual | control not attributed to lookup or compute | 3 |

Lookup is `112/1289 ≈ 8.7%` of FPGA end-to-end latency. Compute is
`1174/1289 ≈ 91%`. These figures are FPGA-internal counter edges. They do
not include host buffer movement or result polling, and they are not a
claim that embedding access is negligible in every DLRM configuration.

The research question is therefore not “how many cycles is embedding
lookup?” It is:

> Although embedding lookup introduces additional memory-access overhead,
> the measured end-to-end latency indicates that DLRM inference is still
> dominated by neural computation. Therefore, a scalable embedding-access
> architecture is required, but must be evaluated together with the
> computation bottleneck.

A17 answers the first half of that question: how to expose memory-side
scalability (four independent HBM-capable read paths) without rewriting the
validated dense pipeline. Whether a physical four-bank map reduces lookup
or end-to-end time is a later, separately gated measurement (A17.6).
Whether the remaining compute bound should be attacked jointly with table
placement and occupancy overlap is later still (A18).

## 2. Design: decoupling access parallelism from computation

The comparison baseline remains A16.2: one compute unit, one `m_axi_gmem`
mapped to `HBM[0]`, four sequential lookups of canonical rows 37–40, then
the unchanged A13 Bottom–Interaction–Top pipeline.

A naïve reading of A17 is “add four AXI interfaces.” That is a packaging
prerequisite, not the architectural claim. The design rationale is:

> decouple embedding-access parallelism from the existing DLRM computation
> pipeline.

A17 therefore addresses *memory-side scalability*. It does not complete
system-level performance optimization. The dense engine, PE count,
datatypes, layer schedule, and A13 register map are frozen. The new
boundary only changes *how four embedding rows are obtained* before the
same computation starts.

The versioned public top `dlrm_f37x_rtl_kernel_stage2n_a17_v1` does the
following:

1. Snapshot four 64-bit table bases on one accepted START.
2. Issue one single-beat read per port (`ARLEN=0`, 128-bit data, at most
   one outstanding request per master).
3. Retain responses that may return in any order.
4. Inject slots 0–3 through the existing single A13 embedding-configuration
   port only after all four rows succeed.
5. Start A13 Bottom–Interaction–Top only from a fresh completed group.

Identity mapping for a future link, not yet live in `config/`, is port *i*
to `HBM[i]`. Runtime programming remains user-managed AXI-Lite
(`xclRegWrite` of BASE0–BASE3). Four kernel pointer arguments would exist
only for Vitis association; they are not an OpenCL `setArg` ABI change.

Error handling is group-scoped. Any fault forbids all four A13 commits for
that job, drains issued single-beat responses, and returns to IDLE through
CLEAR. Busy or repeated START cannot overwrite an in-flight group.

The first physical fixture, when authorized, may copy the same 1024-byte
canonical table into four buffer objects so that port *i* still reads
logical row `37+i`. That fixture tests concurrent access, not four
production tables and not a placement optimizer.

## 3. RTL structure: a scalability layer on a frozen baseline

A17 is not a reconstruction of the DLRM system. It adds a memory
scalability layer on top of two already validated subsystems.

```text
Existing validated compute subsystem (A13)
        +
HBM access subsystem (A14 v2 lookup engine)
        +
Parallel lookup extension (A17)
```

Frozen blocks are instantiated, not edited: four copies of the accepted
A14 v2 lookup engine, the accepted A13 pipeline and cycle counters, and the
A16 inclusive interval counters (`0x30C`, `0x310`). The A13 map through
`0x224` is unchanged. BASE0 remains `0x304/0x308`; BASE1–BASE3 occupy
`0x318` through `0x32C`.

New versioned files only:

- `rtl/hbm/dlrm_hbm_parallel_lookup_stage2n_a17_v1.sv` — four engines and
  independent AR/R gather;
- `rtl/pipeline/dlrm_hbm_pipeline_integration_stage2n_a17_v1.sv` — group
  commit, ordered inject, error drain;
- `rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a17_v1.sv` — public `s_axi_control`
  plus `m_axi_gmem0` through `m_axi_gmem3`.

Internal packed AXI arrays between the kernel top and the integration
wrapper are not a fifth Vitis master. Public names remain `m_axi_gmem0`
through `m_axi_gmem3`.

This layering is the methodological point: compute correctness stays with
A13; single-beat HBM read semantics stay with A14; concurrency, gather,
and four public masters stay with A17. Reviewers can attribute a later
physical result to mapping or interconnect without reopening the dense
golden.

## 4. Verification: evidence hierarchy

The most important methodological rule is that RTL simulation is not
physical HBM. A later reviewer must not promote XSim PASS to four-bank
acceleration. Verification is therefore an evidence hierarchy, not a
single test.

| Verification layer | Purpose | Evidence |
|---|---|---|
| RTL simulation | functional correctness of gather, inject, and A13 start | local XSim PASS (A17.1 controller; A17.2/A17.3 public kernel) |
| AXI behavior | parallel request handling | independent AR issues; response reorder (including 2/0/3/1) |
| Robustness | stall, error, and restart | backpressure hold; SLVERR drain; no-reset restart PASS |
| Physical mapping | HBM bank assignment | **not evaluated** (A17.6 waiting authorization) |

Repository mapping of the same hierarchy:

| Stage | What it proves | Bound |
|---|---|---|
| A16.2 | physical single-bank sequential baseline | `112/1174/1289/3`; five exact cases `-393/-392/-93/-689/-519` |
| A17.1 | four-engine gather, 24 response orders, faults | packed local ports; 73 cases |
| A17.2/A17.3 | public four-master kernel | fake memory; result 36; A13 `322/100/744/1174`; lookup/e2e `24/1256` are not A16.2’s 112/1289 |
| A17.4–A17.5C | mapping, packaging, Host, and execution-gate documents | no XO, no xclbin, no device |
| A17.6 | authorized F37X four-bank run | `WAITING AUTHORIZATION` |

Two predicates must stay separate. Unique `HBM[0..3]` connectivity can
hold while FPGA end-to-end stays near 1289 cycles. Mapping PASS is not
end-to-end reduction. Fake-memory lookup cycles from A17.3 are not
comparable to A16.2’s 112.

## 5. Limitations

The architecture improves memory-side scalability. It does not yet prove
physical multi-bank behavior, and it does not rewrite computation.

- Four AXI ports are a packaging prerequisite, not four physical banks,
  until A17.6 connectivity and buffer-object metadata say so.
- Each engine remains single-beat and one-outstanding. There is no burst,
  cache, or request coalescer.
- Gather-then-inject pays a join wait and then a serial A13 configuration
  port. Parallel HBM reads do not parallelize MLP.
- The four-buffer copied table is a concurrency fixture, not multi-table
  placement.
- A16.2 timing already sits at WNS `0.000 ns`; four slave interfaces may
  fail the 100 MHz gate.
- Interconnect sharing can hide bank-level concurrency even if four
  topology entries are marked used.
- Host programming and result polling sit outside the FPGA end-to-end
  counter.

End-to-end limitation:

> The current architecture improves memory-side scalability but does not
> modify the DLRM computation engine. Therefore, the achievable
> system-level acceleration is bounded by the dominant compute latency.

That bound is not a defect in A17. It is the reason A17 must be reported
as a memory-side result, and the reason A18 is a different research
question.

## 6. Discussion: analytical bounds, not observed bottleneck migration

A16.2 is already compute-dominated (1174 of 1289 cycles). The following is
a **sensitivity analysis** under fixed compute, residual, and clock. It is
not a Results observation and not evidence that a bottleneck migrated after
A17.

Keep the A16.2 numbers fixed. Suppose four-bank lookup collapsed the
112-cycle interval by four to 28 cycles, and compute 1174 and residual 3
did not move. FPGA end-to-end would become about 1205 cycles, a factor of
`1289/1205 ≈ 1.07`. If lookup vanished entirely, the bound would still be
about `1289/1177 ≈ 1.10`. Neither figure is a prediction or an acceptance
threshold. Dividing 112 by four also assumes the whole lookup interval
scales, including serial injection, which the gather-then-inject design
does not justify.

If a later A17.6 run shows lower lookup with little end-to-end change, that
would be consistent with this bound. It would not be a new discovery that
compute dominates; A16.2 already showed that.

An authorized A17.6 run should be reported as two questions, not as a
blanket accelerator speedup: (i) whether the four-bank map is real; (ii)
how lookup and end-to-end moved. Mapping PASS still requires a comparable
measurement before any performance claim.

## 7. Outlook: storage–compute co-design

A18 is not authorized in this draft and has not started. Do not write that
A18 already achieves a joint optimum.

Future work will investigate storage–compute co-design by jointly
optimizing embedding access and neural computation parallelism. Concrete
questions, once A17.6 logs exist, include:

- table and bank placement under capacity and co-access constraints;
- whether embedding traffic and dense occupancy can be overlapped;
- ablation against round-robin or capacity-only maps.

A17 supplies only the controllable four-master substrate and the A16.2
instrumented baseline. A18 would have to change *what is stored where* or
*when compute starts relative to outstanding reads*. Until A17.6 evidence
exists, A18 remains future work.

## 8. Milestone record

| Stage | Status |
|---|---|
| Stage 2N-A16.2 | Physical single-HBM baseline completed (`112/1174/1289`) |
| Stage 2N-A17.0–A17.5C | Architecture and verification framework completed locally |
| Stage 2N-A17.6 | Physical four-bank experiment, **WAITING AUTHORIZATION** |
| Stage 2N-A18 | Storage–compute co-design, not started |

## V2 status block

```text
A17_PAPER_V2_STATUS
Academic style:     UPDATED
Claims:             CHECKED
Evidence boundary:  CHECKED
Engineering files:  UNCHANGED
Quantitative facts: UNCHANGED (A16.2 112 / 1174 / 1289)
New experiments:    NONE
```
