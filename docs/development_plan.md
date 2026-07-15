# Final research development plan

## 1. Thesis target and evidence order

The final target is a complete, single-F37X, all-RTL DLRM inference system.
The thesis contribution hierarchy is frozen as follows:

1. **Primary contribution:** bounded-window duplicate embedding-request
   coalescing plus one-read/multi-consumer result broadcast.
2. **Secondary contribution:** lightweight HBM-channel-aware scheduling applied
   after coalescing.
3. **System optimization:** double buffering that overlaps embedding reads with
   MLP computation.
4. **Compute foundation, not the main contribution:** the parameterized
   multi-cycle vector PE engine from Stage 2A.

Software access-trace analysis must precede any coalescer or channel-scheduler
RTL.  Synthetic data validates tools and explores sensitivity; only user-supplied
real Criteo traces may satisfy the trace feasibility gates.

## 2. Frozen work and current gate

- GATE-1 approval: `37c3990c0973b52910debac35a854e0c2bc875a1`.
- Stage-2 architecture: `748013312e9cb7dce106a8be4ea7a17aacbb87a7`.
- Stage-2A implementation: `54dad7bd5a4cd2b18cb8f2fe42c9b6ebca2e5b66`.
- Stage-2A RTL is frozen until user-provided Vivado 2020.2/XSim logs arrive.
- Stage 2B is downgraded to an optional later performance optimization, not a
  prerequisite for trace feasibility work and not the thesis contribution.

## 3. Approved software-first phases

### Phase S1 — Configurable DLRM reference

- configurable continuous-feature count, table count/cardinalities, embedding
  dimension, Bottom MLP, Top MLP, interaction, and seed;
- PyTorch CPU execution and optional CUDA execution when an installed runtime is
  available;
- deterministic synthetic data and a local-path-only Criteo loader;
- per-stage intermediates, save/reload, parameter and embedding capacity counts;
- AUC, LogLoss, end-to-end and forward-only latency, percentiles, throughput,
  batch size, device metadata, and stage timings in JSON/CSV;
- no claim that synthetic weights or data have meaningful production AUC.

### Phase S2 — Embedding trace extraction

- export request ID, batch ID, table ID, embedding ID, arrival order, optional
  timestamp, duplicate flag, and window membership;
- JSONL, CSV, and compact NPY output;
- table/hotspot/frequency/duplicate-distance and window sensitivity statistics;
- required windows: 1, 2, 4, 8, 16, 32, and 64 requests.

### Phase S3 — Bounded coalescing simulation

Compare no coalescing, count-bounded, time-bounded, dual-bound, and a simple
rule-based adaptive close.  Sweep maximum requests, wait cycles, unique IDs,
arrival rate, embedding latency, broadcast cost, and reorder cost.  Report HBM
read reduction, added mean/P95/P99 wait, occupancy, fan-out tags, state bytes,
and theoretical throughput.

### Phase S4 — Channel mapping and lightweight scheduling

For 4/8/16/32 abstract channels, compare address modulo, static table mapping,
per-channel FIFO round robin, post-coalescing shortest-queue selection, and
age-priority with queue-length assistance.  Report per-channel requests, mean
and peak queue length, max/mean load, load standard deviation, idle ratio,
completion cycles, and P95/P99 completion latency.

### Phase S5 — Trace feasibility gates

- **GATE-T1, coalescing value:** report read reduction versus added mean and P99
  latency.  A project-internal reference line is 20-35% or better read
  reduction under acceptable waiting; it is not a universal academic standard.
- **GATE-T2, scheduling value:** compare static max/mean channel load and queue
  peaks with lightweight scheduling.  If static mapping is already balanced,
  explicitly report limited value.
- **GATE-T3, combined value:** compare no optimization, coalescing only,
  scheduling only, and combined.  Small predicted end-to-end improvement stops
  corresponding RTL work and triggers scope reassessment.

Synthetic traces cannot pass GATE-T1/T2/T3.  They only validate the software and
produce preliminary sensitivity results.  Real gates require local Criteo files
manually supplied by the user.

## 4. Later hardware phases — blocked

Only after real-trace gates and a separate architecture review may work begin on
bounded coalescer RTL, fan-out/broadcast RTL, lightweight channel scheduling
RTL, or embedding/MLP double buffering.  Real HBM/AXI/Vitis work remains behind
GATE-4.  A complete Bottom/Top MLP or feature-interaction RTL hierarchy is also
not authorized by this software phase.

## 5. Explicit exclusions

No DLRMv3, full DCN V2, transformer recommender, multi-FPGA or GPU-FPGA cluster,
HBM/server-memory hierarchy, reinforcement-learning scheduler, global access
co-occurrence graph optimization, complex dynamic precision, online training,
or training acceleration is planned.
