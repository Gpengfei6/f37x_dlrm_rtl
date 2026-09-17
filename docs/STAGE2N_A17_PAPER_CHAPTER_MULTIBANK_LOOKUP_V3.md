# A Multi-Bank-Capable Embedding Lookup Architecture
## Paper-integrated draft (V3)

Date: 2026-09-08. Status: **writing integration only**.

V3 stitches existing documents into a paper outline. Completing this file
does **not** close experiments, does **not** close paper evidence, and does
**not** create academic novelty by itself.

| Evidence class | What may be stated | Source |
|---|---|---|
| **Measured** | A16.2 single-bank physical baseline | F37X board, five cases, `112/1174/1289/3` |
| **Simulated** | A17 logical four-master function | local XSim; sample result 36 |
| **Designed** | multi-bank-capable access architecture | A17 RTL and public ports |
| **Analytical** | lookup-reduction sensitivity under fixed compute | Discussion only; ≈1.07× / ≈1.10× |
| **Pending** | physical four-bank map and A17 latency | A17.6, waiting authorization |
| **Literature review** | selected prior work and scoped comparison | Section II; first pass, not exhaustive; exclusive novelty unestablished |

### File identity

| Path | Role |
|---|---|
| `..._V1.md` | current V1 path: later academic refinement (overwrote the first draft) |
| `..._V1_ENGINEERING_SNAPSHOT.md` | recovered Cursor first engineering draft |
| `..._V2.md` | independent Cursor methodology chapter |
| `..._V3.md` | this integrated writing draft |
| `STAGE2N_A17_EVALUATION_PLAN_V1.md` | empty physical-A17 Results table |
| `STAGE2N_A16_2_FINAL_ACCEPTANCE_V1.md` | measured baseline record |

### Claim boundary

Allowed now:

- describe a multi-bank-capable embedding-access **architecture design**;
- describe a layered **verification framework**;
- report A16.2 as an accepted physical single-bank baseline;
- report A17 XSim as local functional evidence with an explicit bound.

Forbidden as a **measured result**:

- physical four-bank HBM operation on F37X;
- achieved multi-bank acceleration, bandwidth, throughput, or speedup.

A later mapping PASS still requires a comparable measurement before any
performance claim. An engineering increment is not, by itself, an academic
novelty claim.

---

## I. Introduction

Deep Learning Recommendation Model (DLRM) inference couples sparse embedding
retrieval with dense Bottom MLP, feature interaction, and Top MLP. On an
FPGA with HBM, FPGA-side logic can retrieve embedding rows from HBM rather
than relying on CPU lookup followed by embedding writes. HBM retrieval and
computation are measured separately in the present baseline.

On the accepted Stage 2N-A16.2 fixture—one Inspur F37X card, one compute
unit, one AXI master, one physical `HBM[0]` bank, requested 100 MHz—four
canonical rows (indices 37–40) are read sequentially and then consumed by
the frozen A13 pipeline. The measured FPGA-internal intervals are:

- lookup (first AR through four-slot injection): **112** cycles;
- compute (Bottom + Interaction + Top): **1174** cycles;
- FPGA end-to-end (accepted START through first result): **1289** cycles;
- residual: **3** cycles.

Lookup is about 8.7% of this FPGA end-to-end interval; compute is about
91%. These counters exclude host buffer movement and result polling. They
are measurements of **this** configuration, not a universal DLRM law, and
they do not by themselves prove HBM-bandwidth saturation or PE saturation.

**Research question.** How can four embedding requests proceed independently
while preserving the accepted computation pipeline, and what end-to-end
benefit could a reduction in their retrieval interval permit in this
configuration? Compute-stage dominance motivates evaluating both intervals;
it does not establish that a particular memory architecture is necessary.

This work reports (i) that architecture as a multi-bank-capable design
layered on a validated compute and HBM-read baseline, and (ii) a
verification framework that separates simulation, mapping, and
measurement. Physical four-bank execution and any speedup remain pending
(A17.6). Joint storage–compute co-design remains future work (A18).

Section II positions this implementation against selected model,
characterization, FPGA, heterogeneous-system, and computational-storage
work. The resulting contribution is scoped to the present implementation
and its verification boundaries. This review does not establish an
exclusive algorithmic or architectural research gap.

---

## II. Related Work

**Status: selected-source review, 2026-09-08.** This first pass covers five
relevant works and distinguishes full-text section review from abstract
and artifact inspection. It is not an exhaustive survey through 2026.
The comparisons below are this chapter's analysis of the cited sources,
not claims made by those authors about A17.

### 2.1 Model structure and workload-dependent bottlenecks

Naumov et al. describe DLRM as a combination of categorical embeddings,
a bottom MLP for continuous features, explicit feature interactions, and
a top MLP. Their treatment of embedding and MLP parallelism already
recognizes distinct memory and computation requirements. A17 retains a
bounded fixed-point instance of this computation structure; it does not
introduce the sparse/dense decomposition. [R1, Sections 2–3].

Hsia et al. examine eight recommendation models across CPU/GPU platforms
and batch sizes. Their operator and microarchitectural analyses show that
optimization targets depend on deployment conditions. Their end-to-end
measurements include data loading and computation, unlike A16.2's
FPGA-internal interval. This supports restricting the 91.1% compute share
to the measured A16.2 fixture, rather than treating it as a general DLRM
property or a directly comparable literature metric. [R2, Sections III–VI].

### 2.2 Parallel embedding retrieval and heterogeneous inference

MicroRec combines parallel access across HBM, DDR, and on-chip memories
with Cartesian-product table combinations and placement heuristics. It
also implements a pipelined DNN computation path and evaluates embedding
and complete-inference performance. Thus neither parallel HBM lookup nor
attention to downstream computation is new in A17. The present design
instead preserves an accepted RTL pipeline and studies a bounded four-row
gather/injection interface without implementing MicroRec's table
transformations or placement search. [R3, Sections 3–5].

FleetRec's published abstract describes disaggregated memory and
computation on a networked GPU–FPGA system; its author-maintained artifact
contains separate FPGA and GPU implementations. This is prior work on
system-level coordination, not an embedding-only accelerator. A17 targets
one FPGA and introduces no GPU or cluster execution. This pass uses the
abstract and artifact description only; detailed scheduling and evaluation
claims require a full-paper review. [R4].

### 2.3 Capacity and storage–compute coordination

SCRec's 2025 preprint combines statistical sharding, a mixed-integer cost
model, tensor-train embeddings, and assignment of embedding/MLP cores in
a SmartSSD-based design. Its evaluation uses GPU accuracy experiments,
memory/core simulation, and synthesized and placed-and-routed kernels;
these evidence types should not be collapsed into an all-board result.
It is relevant to future A18 positioning because placement and compute
allocation are already coupled in prior work. A17 implements none of those
compression or resource-allocation mechanisms. [R5, Sections III–IV].

### 2.4 Comparison with the current implementation

| Work | Relevant mechanism or scope | Evidence inspected in this pass | Relation to A17 |
|---|---|---|---|
| DLRM [R1] | Embeddings, MLPs, interactions; model/data parallelism | Model and parallelism sections | Inherited model foundation |
| Cross-Stack [R2] | Workload/platform/batch-dependent characterization | Methodology and analysis sections | Supports scoped bottleneck interpretation |
| MicroRec [R3] | Parallel lookup, table transformation/placement, DNN pipeline | Architecture and FPGA evaluation sections | Overlap in access parallelism; broader memory optimization |
| FleetRec [R4] | Networked GPU–FPGA memory/compute separation | Published abstract and author artifact overview | Different deployment; detailed comparison still partial |
| SCRec [R5] | Sharding, compression, adaptive core allocation | Design and mixed-method evaluation sections | Relevant co-design precedent; different storage system |
| A16.2 / A17 | Fixed-point baseline; four-master gather and preserved compute | Repository acceptance records | Single-bank physical baseline; A17 local simulation only |

This is a qualitative comparison, not a performance ranking. Published
speedup numbers are not normalized against A16.2: model shape, precision,
table sizes, batch size, hardware, measurement boundaries, and baselines
differ. No A17 physical result exists to support such a ranking.

The defensible present contribution remains a multi-bank-capable
architecture and verification framework built on a validated DLRM FPGA
baseline. Group validity, response retention, recovery, and explicit
measurement boundaries describe the implementation's engineering content.
This review does not establish that these mechanisms, separately or in
combination, are absent from prior art. A distinct academic contribution
would require a specific mechanism or experimentally supported insight
and a comparison sufficient to establish its difference and value.

### 2.5 Source register and remaining coverage

Sources were located using the named-system queries MicroRec/FleetRec,
DLRM and cross-stack characterization, followed by searches for recent
FPGA/DLRM work and primary-source link following. No performance result
was reproduced. Search snippets and secondary summaries are not used as
evidence for the mechanism claims above.

- **R1.** Maxim Naumov et al. *Deep Learning Recommendation Model for
  Personalization and Recommendation Systems*. arXiv:1906.00091 (2019),
  Sections 2–3. [Author manuscript](https://arxiv.org/pdf/1906.00091).
- **R2.** Samuel Hsia et al. *Cross-Stack Workload Characterization of Deep
  Recommendation Systems*. IISWC 2020; arXiv:2010.05037v1, Sections III–VI.
  [Full text](https://arxiv.org/html/2010.05037v1).
- **R3.** Wenqi Jiang et al. *MicroRec: Efficient Recommendation Inference
  by Hardware and Data Structure Solutions*. MLSys 2021, Sections 3–5.
  [Proceedings paper](https://proceedings.mlsys.org/paper_files/paper/2021/file/9e9a5486cb2f8e44d5b5fedd2a9e5fcd-Paper.pdf).
- **R4.** Wenqi Jiang et al. *FleetRec: Large-Scale Recommendation Inference
  on Hybrid GPU-FPGA Clusters*. KDD 2021, pp. 3097–3105,
  DOI: 10.1145/3447548.3467139.
  [Institutional abstract and publication record](https://www.research-collection.ethz.ch/handle/20.500.11850/485153);
  [author artifact overview](https://github.com/fpgasystems/GPU-FPGA-Recommendation-System).
  Full-paper retrieval was unsuccessful in this pass; no claim of full-text
  review is made.
- **R5.** Jinho Yang, Ji-Hoon Kim, and Joo-Young Kim. *SCRec: A Scalable
  Computational Storage System with Statistical Sharding and Tensor-train
  Decomposition for Recommendation Models*. arXiv:2504.00520v1 (2025),
  Sections III–IV. [Full text](https://arxiv.org/html/2504.00520v1).
  This register cites the reviewed preprint, without asserting a final
  publication venue.

Remaining coverage includes FleetRec's full design/evaluation, near-memory
embedding reduction, request coalescing/caching, additional FPGA inference
systems, and forward citation tracing. A failure to locate a newer directly
comparable paper in this pass is not evidence that none exists. These
limits prevent a comprehensive novelty claim but do not invalidate the
scoped comparisons above.

---

## III. Methodology: FPGA-based DLRM Acceleration Framework

This chapter can be written now. That does **not** mean the method has been
fully validated on hardware for A17.

### 3.1 Baseline system and bottleneck analysis (measured)

The comparison baseline is Stage 2N-A16.2.

| Item | Value | Class |
|---|---|---|
| Kernel / CU | `dlrm_f37x_rtl_kernel_stage2n_a16_v1` / `dlrm_a16_1` | measured artifact |
| Mapping | `m_axi_gmem → HBM[0]` | measured |
| Clock / timing gate | 100 MHz; WNS/TNS `0.000/0.000 ns` | measured (gate pass, not positive slack) |
| Lookup / compute / e2e / residual | `112 / 1174 / 1289 / 3` | measured |
| Function | five cases `-393/-392/-93/-689/-519` | measured |
| Performance | `NOT_CLAIMED` | bound |

Compute already dominates this baseline. A17 is not required in order to
“discover” that fact.

The counter boundaries use rising-edge event indices: S is the accepted
wrapper START, A the first successful read-address handshake, D completion
of four-slot injection, C the accepted A13 compute START, and F first
final-result visibility. All three counters include their start and stop
edges:

```text
L_lookup  = D - A + 1
L_compute = F - C + 1
L_FPGA    = F - S + 1
R         = L_FPGA - L_lookup - L_compute
          = (A - S) + (C - D) - 1
```

The 3-cycle residual is algebraically derived, not an independently
instrumented control stage. Lookup includes slot injection and does not
measure HBM device access alone. The 1174-cycle compute total is a separate
interval, not the arithmetic sum of the three substage counters.
[A16.2 acceptance and counter reconciliation](STAGE2N_A16_2_FINAL_ACCEPTANCE_V1.md).

### 3.2 Multi-bank-capable embedding lookup architecture (designed)

A17 does not reconstruct the DLRM system. It adds a memory-side scalability
layer:

```text
validated compute subsystem (A13)
        +
HBM access subsystem (A14 v2 lookup engine)
        +
parallel lookup extension (A17)
```

The architectural rationale is **decoupling embedding-access parallelism
from the existing computation pipeline**, not “adding four AXI ports.”
Four public masters are a packaging prerequisite for a future four-bank
map. They are not, by themselves, four physical banks.

The versioned public top `dlrm_f37x_rtl_kernel_stage2n_a17_v1`:

1. snapshots four 64-bit table bases on one accepted START;
2. issues one single-beat read per port (`ARLEN=0`, 128-bit data, at most
   one outstanding request per master);
3. retains responses that may return in any order;
4. injects slots 0–3 through the existing single A13 configuration port
   only after all four rows succeed;
5. starts Bottom–Interaction–Top only from a fresh completed group.

Proposed, not linked, connectivity is port *i* to `HBM[i]`. Runtime
programming remains user-managed AXI-Lite writes of BASE0–BASE3. The first
physical fixture, when authorized, may copy the same 1024-byte table into
four buffer objects. That is a concurrency fixture, not four production
tables and not a placement algorithm.

### 3.3 RTL and dataflow design (designed)

New versioned files only; A13 and A14 v2 are instantiated, not edited:

- `rtl/hbm/dlrm_hbm_parallel_lookup_stage2n_a17_v1.sv`
- `rtl/pipeline/dlrm_hbm_pipeline_integration_stage2n_a17_v1.sv`
- `rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a17_v1.sv`

Public masters are `m_axi_gmem0`–`m_axi_gmem3`. Internal packed AXI arrays
are not a fifth Vitis master. The A13 map through `0x224` is unchanged.
BASE0 remains `0x304/0x308`; BASE1–BASE3 occupy `0x318`–`0x32C`. Inclusive
lookup and FPGA end-to-end counters remain at `0x30C` and `0x310`.

Gather-then-inject waits for the slowest member of the group and then uses
one configuration port. Independent request issue therefore does not imply
a fourfold reduction of the measured lookup interval.

Any address or response fault prevents all embedding commits for that
group. Issued responses are drained before the error is acknowledgeable;
CLEAR does not cancel an outstanding transaction. A nonresponding peer
can therefore keep the group busy. Fresh-group gating prevents retained
embedding state from authorizing a stale compute run.
[Controller and integration design](STAGE2N_A17_1_PARALLEL_LOOKUP_LOCAL_V1.md).

### 3.4 Verification methodology (framework, not full hardware proof)

| Layer | Purpose | Evidence class | Does not prove |
|---|---|---|---|
| RTL simulation | gather, inject, A13 start | simulated (A17.1) | physical HBM |
| AXI behavior | parallel request handling | simulated (reorder 2/0/3/1) | four banks |
| Robustness | stall, error, restart | simulated | board recovery |
| A16.2 board | single-bank function and intervals | measured | A17 physical behavior |
| Physical mapping | HBM bank assignment | **pending** | — |

A17 deterministic integration returns sample **36** with A13 counters
`322/100/744/1174`. That sample is **not** a substitute for the A16.2 five
trained-model board cases. Fake-memory lookup cycles (A17.3 `24`, A16.1
`73`) are not comparable to A16.2’s 112.

### 3.5 Limitations and design implications

- Ports are not banks until A17.6 connectivity and BO metadata agree.
- No burst, cache, coalescer, or cross-job overlap.
- End-to-end acceleration, if any, is bounded by the already-dominant
  compute interval under the fixed-compute, fixed-clock assumptions of §5.1.
- Shared interconnect may hide bank-level concurrency.
- A16.2 WNS is 0.000 ns, without demonstrated positive timing headroom;
  target timing closure and resource cost remain unvalidated for A17.
- Engineering capability is not, without literature comparison, an
  academic novelty claim.

---

## IV. Experimental Evaluation

Do not place analytical 1.07× / 1.10× numbers in this section.

### 4.1 FPGA platform and baseline (measured)

Inspur F37X, part `xcvu37p-fsvh2892-2L-e`, platform
`inspur_f37x_xdma_201920_3`, requested 100 MHz. A16.2 identities and the
five-case function are accepted. Performance is not claimed.

### 4.2 Functional verification (simulated, bounded)

Local A17.1: 73 controller cases, including all 24 response orders.
Local A17.2/A17.3: public four-master ports, stall, SLVERR drain, restart.
These runs support logical correctness of the designed architecture.
They do **not** repeat A16.2’s five physical cases on A17 hardware and do
**not** prove physical four-bank performance.

The claim is limited to the exercised directed cases, not exhaustive AXI
verification. The retained local runs use Vivado/XSim 2022.1; this does not
establish acceptance of the target Vivado/Vitis 2020.2 flow. No simulation
was rerun for this writing revision.
[A17.1 acceptance](evidence/stage2n_a17_1/local_xsim_v1/acceptance_summary.txt);
[A17.2/A17.3 public-kernel acceptance](STAGE2N_A17_2_PUBLIC_KERNEL_XSIM_V1.md).

### 4.3 Physical HBM mapping evaluation (pending)

| Metric | A16.2 (measured) | A17 physical |
|---|---|---|
| Banks used | `HBM[0]` | `NOT_RECORDED` |
| Unique four-bank map | no | `NOT_RECORDED` |

Fill only from authorized A17.6 logs. Mapping PASS is independent of
end-to-end reduction.

Physical acceptance requires the existing artifact, device, BO mapping,
functional-run, and measured-counter evidence together. Connectivity or
BO metadata alone does not establish physical execution or concurrent
memory service. The experiment remains **WAITING AUTHORIZATION**.
[Existing execution gate](STAGE2N_A17_5C_EXECUTION_GATE_V1.md).

### 4.4 Latency analysis (measured baseline; A17 physical pending)

| Metric | A16.2 (measured) | A17 physical |
|---|---|---|
| Lookup cycles | 112 | `NOT_RECORDED` |
| Compute total | 1174 | `NOT_RECORDED` |
| FPGA e2e | 1289 | `NOT_RECORDED` |
| Residual | 3 | `NOT_RECORDED` |
| Speedup | not claimed | not claimed until comparable measurement |

A future comparison must retain equivalent workloads and counter events,
record the clock and runtime conditions, and measure lookup, compute, and
residual separately. A single-job latency ratio does not establish
sustained throughput. These are the existing comparison boundaries, not
new experiment results.
[Evaluation plan](STAGE2N_A17_EVALUATION_PLAN_V1.md).

---

## V. Discussion

### 5.1 Analytical bounds (not Results)

Let s be a hypothetical reduction factor for the entire lookup interval.
Hold compute = 1174, residual = 3, and clock fixed, with no new overlap or
additional overhead:

```text
L_FPGA(s) = 112/s + 1177
S_FPGA(s) = 1289 / (112/s + 1177)
```

| Scenario | Lookup | FPGA e2e | Conditional ratio |
|---|---:|---:|---:|
| Measured A16.2 | 112 | 1289 | 1.000× (reference) |
| Hypothetical fourfold lookup interval | 28 | 1205 | ≈1.07× |
| Algebraic zero-lookup limit | 0 | 1177 | ≈1.10× |

Only the first row is measured. The 28-cycle row assumes the **entire**
lookup interval scales by four, including control and serial injection;
the gather-then-inject design does not justify that assumption. These
figures are not predictions, gates, or observed A17 outcomes.
The zero-lookup row is an algebraic limit as s tends to infinity, not an
implementable zero-cycle transaction under the inclusive counter contract.

### 5.2 Compute already dominates

A16.2 already shows compute-stage dominance. There is **no observed
bottleneck migration** attributed to A17, because A17 has no physical
latency result. A future drop in lookup with little end-to-end change
would be consistent with §5.1 if measured compute and residual values
support its assumptions. It would not establish a universal DLRM bottleneck
or independently diagnose arithmetic-resource saturation.

### 5.3 Outlook: storage–compute co-design

Future work will investigate jointly optimizing embedding access and
neural-computation parallelism (placement, overlap, ablations). A18 is
not started. Do not write that A18 achieves a co-design result.

---

## VI. Writing versus evidence closure

| Item | V3 status |
|---|---|
| Methodology chapter structure | written |
| Measured A16.2 facts | copied, not re-run |
| A17 physical Results | empty |
| Related Work | first selected-source review; five works, partial FleetRec review; coverage incomplete |
| Academic novelty | **not claimed** |
| Experiment closure | **no** |
| Paper evidence closure | **no** |

```text
A17_PAPER_V3_STATUS
Writing integration:  DONE
Related Work:         FIRST_PASS (not exhaustive)
Experiment closure:   NO
Evidence closure:     NO
Claim boundary:       CHECKED
Engineering files:    UNCHANGED
```
