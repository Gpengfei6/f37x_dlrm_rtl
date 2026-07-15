# Final single-F37X DLRM architecture scope

## 1. End-to-end target

The target system is a complete inference-only DLRM on one F37X/VU37P.  FPGA
compute remains SystemVerilog RTL.  The final logical flow is:

```text
continuous features -> Bottom MLP ------------------------------+
                                                               |
categorical IDs -> bounded duplicate coalescer -> HBM scheduler |
                     |                         |                 |
                     + fan-out metadata       + embedding reads |
                                               -> result broadcast
                                               -> table pooling -+
                                                                 v
                                                    dot interaction
                                                                 |
                                                                 v
                                                             Top MLP
                                                                 |
                                                                 v
                                                    fixed-point score
```

Embedding reads and compute may later use ping-pong buffers so request service
for one context overlaps MLP work for another.  Double buffering is a system
optimization, not the core novelty.

## 2. Contribution boundaries

### Primary: bounded request coalescing and broadcast

The proposed block observes a finite request-count and/or wait-cycle window,
merges identical `(table_id, embedding_id)` keys, performs one physical read,
and stores bounded fan-out metadata so the response can be replayed/broadcast to
all logical consumers in order.  Capacity limits and fallback behavior must be
explicit; no unbounded associative structure is permitted.

### Secondary: post-coalescing channel-aware scheduling

After merging, a lightweight scheduler may consider channel queue length and
request age while preserving bounded fairness.  It does not use reinforcement
learning, integer programming, global graph optimization, or complex prediction.
Software analysis must first show imbalance and measurable improvement over
static mapping.

### Foundation: Stage-2A vector PE

The P=4/8/16/32 multi-cycle vector PE, ACC32/ACC48 modes, runtime dimensions,
banked ping-pong activation storage, abstract weight provider, and per-layer
shift/ReLU are retained unchanged.  This reusable engine is necessary for Bottom
and Top MLPs but is not presented as the thesis's primary innovation.  It is
frozen until real Vivado 2020.2 logs are returned.

## 3. Software reference architecture

```text
local configuration
  -> deterministic synthetic dataset OR user-supplied local Criteo files
  -> configurable DLRM reference
       continuous -> Bottom MLP
       categorical -> table embeddings
       concat(bottom, embeddings) -> DLRM pairwise dot interaction
       dense vector -> Top MLP -> one logit/probability
  -> stage intermediates and evaluation metrics
  -> embedding access trace
  -> bounded coalescing simulator
  -> channel mapping/scheduler simulator
  -> GATE-T1/T2/T3 feasibility report
```

The PyTorch model is the intended executable reference.  A deterministic NumPy
oracle may validate structure when the local PyTorch package is unavailable,
but it does not convert a PyTorch-only test into PASS.  CUDA is optional and is
SKIPPED when unavailable.

## 4. Trace and HBM abstraction boundary

Trace records contain logical table/row accesses only.  Channel mapping is a
software abstraction parameterized by 4/8/16/32 channels; it is not a physical
F37X HBM address-map claim.  No AXI ID, burst, pseudo-channel, platform shell, or
board timing is introduced at this stage.

Future HBM integration replaces the storage-facing side of an embedding
provider.  The coalescer operates on logical keys and fan-out tags; the PE engine
continues to see the existing abstract activation/weight providers.

## 5. Evidence discipline

Synthetic high/low duplication, balanced/skewed channels, and hotspot-shift
traces are required for tool validation and deterministic regression.  They are
not evidence that production traces contain the same locality.  Real innovation
claims and corresponding RTL authorization require user-supplied real data and
completed GATE-T1/T2/T3 reports.

## 6. Explicitly not implemented now

No Stage-2A RTL edits, Stage 2B, two-dimensional PE, P=64, complete DLRM RTL,
feature-interaction RTL, multi-layer MLP RTL, HBM/AXI/Vitis RTL, coalescer RTL,
or channel-scheduler RTL is authorized in the current software-analysis phase.
