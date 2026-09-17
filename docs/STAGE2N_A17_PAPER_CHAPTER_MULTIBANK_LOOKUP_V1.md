# A Multi-Bank-Capable Embedding Lookup Architecture and Verification Framework

Draft date: 2026-09-08. Revision: academic refinement **in the V1 path**.

File identity (do not treat this path as an untouched engineering record):

- This file was overwritten in place. It is **not** Cursor’s first engineering
  summary.
- Independent Cursor methodology chapter:
  `docs/STAGE2N_A17_PAPER_CHAPTER_MULTIBANK_LOOKUP_V2.md`
- Recovered first engineering draft:
  `docs/STAGE2N_A17_PAPER_CHAPTER_MULTIBANK_LOOKUP_V1_ENGINEERING_SNAPSHOT.md`
- Paper-integrated writing draft:
  `docs/STAGE2N_A17_PAPER_CHAPTER_MULTIBANK_LOOKUP_V3.md`

Evidence status: local A17 architecture and verification; physical A17
evaluation pending. This revision introduces no new simulation or hardware
run.

## 1. Motivation

The implemented Deep Learning Recommendation Model (DLRM) inference path
combines embedding retrieval with Bottom MLP, feature interaction, and Top
MLP execution. A17 investigates how independent embedding requests can be
exposed concurrently while preserving the accepted arithmetic pipeline.
Its contribution is a **multi-bank-capable architecture and verification
framework**. Physical multi-bank HBM acceleration has not been demonstrated.

The accepted A16.2 comparison point uses one F37X card, one compute unit,
one AXI read master, and one physical `HBM[0]` allocation. Four canonical
embedding rows, indexed 37–40, are retrieved sequentially and supplied to
the A13 pipeline. The accepted target meets the requested 100 MHz timing
gate. Five board cases produce exact expected outputs; their recorded
lookup, compute, and FPGA end-to-end intervals are 112, 1174, and 1289
cycles, respectively. These are accepted baseline measurements, not
evidence of an acceleration over another implementation.
[Repository evidence: A16.2 final acceptance](STAGE2N_A16_2_FINAL_ACCEPTANCE_V1.md).

The compute interval accounts for approximately 91.1% of the measured FPGA
end-to-end interval, whereas lookup accounts for 8.7%. This distribution
motivates a bounded research question: can the memory-access path expose
independent requests without changing the established computation, and
what end-to-end benefit could a reduction in that path permit? The measured
stage shares establish that compute-stage execution dominates this
configuration. They do not by themselves identify bandwidth saturation,
memory latency, or arithmetic utilization as the underlying bottleneck.

A17 therefore separates architectural capability from empirical performance.
The local contribution comprises independent request issue, response
association and retention, controlled transfer into the existing pipeline,
and verification under varied response timing and faults. Whether these
logical interfaces map to distinct physical HBM resources, and whether
that mapping reduces measured latency, remain questions for A17.6.

## 2. Design rationale

### 2.1 Independent retrieval with a preserved compute boundary

A17 replaces the single-master sequential retrieval schedule with four
independent instances of the accepted A14 v2 lookup engine. Each instance
uses a 64-bit byte address and returns one 128-bit row containing eight
signed INT16 elements. Reads remain single-beat (`ARLEN=0`), with at most
one outstanding request per master. The public kernel captures four
64-bit table bases on an accepted START and requests row `37+i` through
port `i`, for `i=0,1,2,3`.

Independent address handshakes allow one port to proceed while another is
stalled. Per-slot storage retains responses arriving in different orders or
on the same cycle, maintaining their association with the intended embedding
slots. The architecture thus decouples request completion order from the
order in which the compute pipeline consumes the rows.
[Design record](STAGE2N_A17_1_PARALLEL_LOOKUP_LOCAL_V1.md).

Once every row has completed successfully, the controller transfers slots
0–3 through the existing single A13 embedding configuration port. Data and
slot identity remain stable under backpressure; slot commitment follows the
configuration handshake. A fresh completed group authorizes one compute
START. Retaining the configuration interface preserves the accepted
arithmetic and integration boundary, but also retains serial injection and
a wait for the slowest member of the group. Independent retrieval therefore
does not imply a fourfold reduction in the complete lookup interval.

### 2.2 Group validity and recovery

The gather-before-injection policy prevents a group containing an address
or response fault from partially updating the A13 embedding slots. The
controller completes response collection and drains outstanding single-beat
transactions before exposing an acknowledgeable error. CLEAR permits
recovery after that handshake; it does not cancel an outstanding AXI
transaction. A peer that never responds can consequently keep the group
busy, because the design does not implement timeout-based recovery.

Busy or repeated START requests cannot replace the active group. A fresh
completion permission is consumed when computation starts, preventing a
previously loaded mask from authorizing a stale inference. These controls
address transaction validity and recovery; they do not add overlap between
successive inference jobs.

### 2.3 Intended physical mapping

The proposed target association is `m_axi_gmemi -> HBM[i]` for ports 0–3.
This is a mapping objective, not a completed link or runtime allocation.
The planned Host path retains explicit AXI-Lite programming of BASE0–BASE3;
proposed pointer metadata supports tool association and does not establish
a new, implemented Host ABI.

The initial physical fixture may replicate the canonical 1024-byte table
into four buffer objects (BOs), allowing each port to retrieve its assigned
logical row from a separate allocation. Such replication would provide a
controlled concurrency fixture. It would not demonstrate placement of four
distinct production tables or a capacity-aware placement algorithm.
[Existing evaluation plan](STAGE2N_A17_EVALUATION_PLAN_V1.md).

## 3. RTL organization

The implementation separates memory transaction handling, pipeline
integration, and the public kernel interface. Four unchanged A14 v2 engines
provide the read behavior, while the accepted A13 pipeline and its
arithmetic remain unchanged. A17-specific coordination is confined to
versioned modules:

| Module | Responsibility |
|---|---|
| `rtl/hbm/dlrm_hbm_parallel_lookup_stage2n_a17_v1.sv` | Independent read engines, response retention, group validity, and ordered slot transfer |
| `rtl/pipeline/dlrm_hbm_pipeline_integration_stage2n_a17_v1.sv` | Connection to A13, fresh-group compute gating, and protection of embedding ownership |
| `rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a17_v1.sv` | Public AXI-Lite control, four AXI memory masters, base capture, and interval instrumentation |

This organization supports verification at both the controller and public
kernel boundaries. Internal packed AXI arrays express the four channels;
they do not constitute an additional public master. The externally visible
masters are `m_axi_gmem0` through `m_axi_gmem3`.

The A13 register map through `0x224` remains unchanged. BASE0 retains
`0x304/0x308`, and BASE1–BASE3 occupy `0x318` through `0x32C`.
The lookup and FPGA end-to-end counters remain at `0x30C` and `0x310`,
with the accepted inclusive event definitions. Preserving these boundaries
supports a later comparison; it does not guarantee identical physical
timing or overhead.
[Public-kernel specification](STAGE2N_A17_2_PUBLIC_KERNEL_XSIM_V1.md).

## 4. Verification methodology

### 4.1 Layered evidence and functional coverage

Verification proceeds from independent lookup behavior to integration with
A13 and then to the public kernel interfaces. Each layer supports a
specific claim, as summarized below. All PASS statements refer to retained
historical evidence; this chapter revision introduces no new simulation
or hardware run.

| Layer | Retained evidence | Supported conclusion and boundary |
|---|---|---|
| A16.2 physical baseline | Five exact board cases; 112/1174/1289 cycles | Accepted single-bank function and interval baseline; no multi-bank result |
| A17.1 controller and integration | 73 lookup cases, including all 24 response-order permutations; integration runs | Exercised gather, slot transfer, errors, backpressure, and A13 integration in local simulation |
| A17.2/A17.3 public kernel | Concurrent requests, response order 2/0/3/1, isolated stall, SLVERR drain, and restart | Exercised four-master public-port behavior in local simulation |
| A17.4–A17.5C preparation | Mapping and packaging proposals, Host/BO plan, execution checklist | Preparation completed; no A17 target or physical acceptance |
| A17.6 physical evaluation | Pending; WAITING AUTHORIZATION | No physical four-bank mapping or measured A17 performance result |

The controller tests compare row contents and lane ordering, while timing
variations exercise independent request progress and response retention.
The public-port regression checks control-register behavior, captured
addresses, rejection of busy operations, failure recovery, and repeated
inference without a DUT reset. The retained summaries report successful
compile, elaboration, and simulation with zero warnings for those local
runs. This is directed functional coverage, not an exhaustive proof of
all AXI behaviors.
[Controller acceptance](evidence/stage2n_a17_1/local_xsim_v1/acceptance_summary.txt);
[public-kernel acceptance](STAGE2N_A17_2_PUBLIC_KERNEL_XSIM_V1.md).

The A17 deterministic integration sample returns 36, with Bottom,
Interaction, Top, and Total counters of 322/100/744/1174. Its final output
checks preservation of the selected compute sample; explicit slot
comparisons check embedding transfer. This sample does not replace the
five trained-model physical cases used by A16.2. Moreover, the total compute
counter is its own measured interval and should not be reconstructed by
simply summing the three substage counters.

### 4.2 Measurement definitions

Let S denote the accepted wrapper START, A the first successful read-address
handshake on any active port, D completion of the four-slot injection group,
C the accepted A13 compute START, and F first final-result visibility.
Using rising-edge event indices, the inclusive intervals are

```text
L_lookup  = D - A + 1
L_compute = F - C + 1
L_FPGA    = F - S + 1
R         = L_FPGA - L_lookup - L_compute
          = (A - S) + (C - D) - 1
```

The A16.2 values give R = 3 cycles. R is an algebraic accounting residual,
not an independently instrumented overhead stage. The lookup interval
includes retrieval and slot injection; it is not a direct measurement of
HBM device access latency. Similarly, FPGA end-to-end excludes Host-side
preparation, programming, and result polling outside the defined events.
[Counter reconciliation](STAGE2N_A16_2_FINAL_ACCEPTANCE_V1.md).

Fake-memory response timing and testbench control traffic affect these
intervals. A17 simulation cycles therefore cannot be compared directly
with the physical A16.2 value of 112 cycles to infer a speedup. Equal event
definitions are necessary for comparison, but equivalent workloads,
execution conditions, and measurement environments are also required.

### 4.3 Physical validation boundary

A17.5C records execution readiness only. Physical validation remains
contingent on the separately authorized A17.6 experiment, including target
artifact identity, protected device execution, consistent connectivity and
BO mapping, functional correctness, and measured counters. The intended
four-bank mapping requires agreement between the linked connectivity,
runtime BO properties, HBM tags, and programmed base addresses.
[Existing execution gate](STAGE2N_A17_5C_EXECUTION_GATE_V1.md).

Mapping correctness and performance improvement are separate outcomes.
Distinct bank assignments do not establish simultaneous physical service
or reduced latency. Conversely, unchanged end-to-end latency does not,
by itself, invalidate a verified mapping. A later performance statement
must specify the measured metric and a comparable baseline; completion
of the physical gate alone does not establish acceleration.

## 5. Limitations

**Physical realization.** Four public AXI masters establish logical access
independence, while physical bank connectivity and runtime operation remain
unvalidated for A17. Shared interconnect resources may restrict realized
concurrency. The A16.2 target reports WNS = 0.000 ns, which establishes
passage of its requested 100 MHz timing gate without demonstrating positive
timing headroom. Timing closure and resource cost cannot be inferred for
the expanded A17 design.

**Granularity and serialization.** Each engine supports a single-beat read
and at most one outstanding request. A17 adds no burst access, cache,
coalescer, or prefetcher. Gather completion depends on all four responses,
and injection uses one configuration port. Computation starts after the
group is loaded; cross-job memory/compute overlap is outside the present
design. A failed or nonresponding channel can delay group recovery.

**Workload scope.** The implemented path retrieves four fixed logical rows,
and the proposed replicated-table fixture isolates access concurrency.
Neither establishes scalability across production table sizes, skewed
request distributions, varying table counts, or capacity-constrained
placement. The A17 deterministic simulation sample also differs from the
A16.2 physical validation workload.

**Scope of performance interpretation.** The evidence provides a physical
single-bank latency baseline and local A17 functional verification. It does
not quantify A17 physical latency, sustained throughput, bandwidth, power,
or energy. Local XSim 2022.1 acceptance is also distinct from acceptance
of the target Vivado/Vitis 2020.2 flow.

## 6. Discussion: conditional end-to-end benefit

The A16.2 measurements permit a sensitivity analysis of lookup reduction
while computation is held fixed. Let s be a hypothetical reduction factor
for the entire measured lookup interval. If the compute interval remains
1174 cycles, the accounting residual remains 3 cycles, the clock is
unchanged, and no new overlap or additional overhead is introduced, then

```text
L_FPGA(s) = 112/s + 1174 + 3
S_FPGA(s) = 1289 / (112/s + 1177)
```

| Scenario | Assumed lookup interval | Derived FPGA interval | Conditional latency ratio |
|---|---:|---:|---:|
| Accepted A16.2 reference | 112 cycles | 1289 cycles | 1.000× reference |
| Hypothetical fourfold interval reduction | 28 cycles | 1205 cycles | 1.070× |
| Algebraic limit as lookup tends to zero | 0 cycles | 1177 cycles | 1.095×, approximately 1.10× |

Only the first row reports measured baseline intervals. The other rows
are conditional calculations, not A17 predictions, measurements, or
acceptance thresholds. In particular, dividing 112 by four assumes that
the whole lookup interval scales, including costs associated with control
and injection. The actual gather-then-inject architecture retains serial
work, so the four-port structure does not justify that assumption. The
zero-lookup case is an algebraic limit, not an implementable zero-cycle
transaction under the inclusive counter definition.

Within this fixed-compute model, lookup reduction has limited influence
on FPGA end-to-end latency because the compute interval already dominates.
A future observation of substantially lower lookup latency with a small
end-to-end change would be consistent with this analysis. Its interpretation
would still require measured compute and residual values rather than an
assumption that either stayed constant.

This distinction also limits bottleneck claims. The current decomposition
supports the statement that compute-stage execution dominates the measured
workload. It does not independently establish that the MLP saturates
arithmetic resources or that embedding access saturates HBM bandwidth.
Those causal diagnoses require additional evidence. A single-job latency
ratio likewise cannot be reported as a sustained throughput improvement.

## 7. Research implications and outlook

A17 demonstrates, within the exercised local verification scope, how
independent embedding retrieval can be integrated with a preserved compute
pipeline through explicit response association, group validity, and
controlled slot transfer. Its research value is the resulting
multi-bank-capable architecture and verification framework, together with
measurement boundaries that distinguish logical concurrency, physical
mapping, and end-to-end benefit.

The baseline analysis suggests that memory parallelism alone may offer
limited end-to-end benefit for the present configuration. Storage–compute
co-design is therefore a subsequent research question: table placement,
compute scheduling, and potential overlap may need to be considered
together. This is a motivation for future investigation, not a demonstrated
co-design result or a claim that multi-bank memory is necessary for every
DLRM accelerator.

A18 remains unstarted future work. A17.6 remains the pending physical
comparison against A16.2 under the existing evaluation plan. Until its
evidence is available, this chapter makes no claim of achieved multi-bank
HBM acceleration and reports no measured A17 performance values.

## Milestone record

| Stage | Status |
|---|---|
| Stage 2N-A16.2 | Physical single-HBM baseline completed; 112/1174/1289 cycles |
| Stage 2N-A17.1–A17.3 | Architecture and public-kernel verification completed locally |
| Stage 2N-A17.4–A17.5C | Mapping and execution preparation completed; A17.5C is checklist preparation only |
| Stage 2N-A17.6 | Physical four-bank experiment: **WAITING AUTHORIZATION** |
| Stage 2N-A18 | Storage–compute co-design: not started |
