# Staged development plan

Each stage requires an explicit review gate and bit-accurate regression before
the next stage begins.

1. **Minimum fixed-point loop (current):** local embeddings, pooling, one dense
   layer, ReLU, deterministic Python/RTL vectors, and backpressure tests.
2. **Parameterized multilayer MLP:** layer descriptors, activation selection,
   weight loading, inter-layer buffering, and per-layer range analysis.
3. **Multiple embedding tables:** table metadata, independent row widths, pooling
   modes, bounds/error handling, and request context tags.
4. **Feature interaction:** dot/concat interaction variants with a matching
   Python oracle and dimension-independent tests.
5. **Complete simplified DLRM:** categorical and continuous paths, bottom/top MLP,
   interaction, batching, and end-to-end model export.
6. **Vitis RTL Kernel wrapper:** control/data AXI interfaces, packaging metadata,
   clock/reset boundaries, and a C++11 host skeleton.
7. **F37X HBM integration:** platform-specific bank mapping, burst/coalescing
   policy, outstanding reads, response reordering, and user-run board validation.
8. **Duplicate-ID merging:** batch-local detection, request merge, result fan-out,
   capacity/fallback policy, and hit-rate instrumentation.
9. **HBM channel balancing:** table/row placement, live channel load estimates,
   scheduler fairness, and synthetic/adversarial traffic.
10. **Dynamic micro-batch pipeline:** queue occupancy feedback, overlap of HBM and
    MLP work, deadlock proof, latency bounds, and scheduling baselines.
11. **CPU/GPU/FPGA experiments:** identical datasets/accuracy, latency percentiles,
    throughput, energy, resource use, and reproducible scripts.
12. **Patent/paper evidence:** ablations for merge, balance, and scheduling;
    sensitivity studies; diagrams; raw logs; and claims linked to measurements.

The next approved work should first run phase-1 RTL regressions in a supported
simulator and resolve any portability findings before adding stage 2 features.

