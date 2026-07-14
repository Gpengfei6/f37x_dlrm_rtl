# Architecture v0

## Goal and current boundary

The long-term goal is a single-card F37X/VU37P RTL accelerator for a large
recommendation network.  Phase 1 establishes only a bit-accurate, backpressure-
safe calculation loop.  It is a functional scaffold, not a performance result.

## Current minimum dataflow

```text
ready/valid IDs
      |
      v
[sequential lookup controller] --> [synchronous embedding memory]
      ^                                      |
      |                                      v
      +------------------------------- [element-wise sum]
                                               |
                                               v
                                  [one dot core, reused per output]
                                               |
                                               v
                                    [round/saturate + ReLU]
                                               |
                                               v
                                      ready/valid vector
```

One request is active at a time.  Every response and final result is retained
while downstream `ready` is low.

## Eventual simplified DLRM dataflow

```text
request parser
  +-> categorical IDs -> duplicate merge -> HBM channel scheduler
  |                                          -> multi-table embeddings
  |                                          -> pooling ---------+
  +-> continuous features -> bottom MLP --------------------------+
                                                                    v
                                                        feature interaction
                                                                    |
                                                                    v
                                                               top MLP
                                                                    |
                                                                    v
                                                               probability
```

A dynamic micro-batch scheduler will eventually coordinate the categorical
memory path and compute path.  None of those future blocks is implemented here.

## Responsibilities

- `rv_fifo`: ordered decoupling and backpressure primitive.
- `embedding_mem_model`: deterministic one-cycle local substitute for HBM.
- `minimal_recommendation_pipeline`: ID sequencing, response collection,
  aggregation, and dense-layer orchestration.
- `dot_product_core`: signed bias plus vector product accumulation.
- `dense_layer_core`: reuses the dot core across output neurons, then quantizes
  and applies ReLU.
- `saturating_round`: signed, symmetric nearest rounding and width saturation.
- `relu_quant`: quantizer plus activation wrapper.
- `dlrm_minimal_top`: simulation-oriented external stream boundary.
- Python reference: executable fixed-point contract, floating diagnostic,
  deterministic data generation, and output comparison.

## Replacement and insertion seams

1. Replace `embedding_mem_model` behind its request/response interface with an
   AXI/HBM adapter.  Keep the aggregator independent of memory protocol.
2. Insert duplicate-ID detection/merge between captured IDs and lookup requests;
   add a fan-out/replay table before aggregation.
3. Place request/context FIFOs around memory and compute, then insert the dynamic
   micro-batch scheduler above those queues.
4. Wrap `dlrm_minimal_top` with a separate Vitis RTL Kernel shell rather than
   introducing AXI behavior into arithmetic modules.

## Ready/valid behavior and latency

Transfers occur only on `valid && ready`.  Producers hold payload stable during
backpressure.  Embedding memory and dot-product responses each use a one-entry
elastic register.  Dense computation is sequential across output neurons.  The
exact contracts and no-stall latency formulae are in `interface_spec_v0.md`.

## Explicitly not implemented

Full DLRM, multilayer MLP, continuous-feature processing, feature interaction,
multiple embedding tables, real HBM/AXI, XRT host, RTL-kernel packaging,
duplicate merging, HBM balancing, dynamic micro-batches, multi-card operation,
and server-memory cooperation are outside phase 0/1.

## Risks

- RTL has not yet been compiled by Vivado/Vitis 2020.2 or run on F37X.
- Local simulator availability determines whether syntax/behavior can be tested
  in the current workspace; Python agreement alone cannot validate RTL.
- Packed-vector lane order must remain identical in host/kernel boundaries.
- INT32 wrap is intentional but may be undesirable for trained production models;
  range analysis may require a wider or saturating accumulator.
- The local memory and one-request controller do not predict HBM timing,
  outstanding-read behavior, routing pressure, or achievable clock frequency.
- Parallel multipliers inside the simple dot core favor clarity, not a final VU37P
  resource/performance trade-off.

