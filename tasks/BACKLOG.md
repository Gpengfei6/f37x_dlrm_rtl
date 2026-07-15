# Backlog

## Active local software work

1. Implement a configuration-driven PyTorch DLRM with Bottom MLP, multiple
   embedding tables, DLRM dot-product interaction, Top MLP, intermediates,
   save/reload, parameter counts, and CPU/optional CUDA execution.
2. Add deterministic synthetic datasets and a strict user-path-only Criteo
   loader with no download behavior.
3. Add training, inference, and benchmark CLIs with AUC/LogLoss, warmup,
   end-to-end versus forward-only latency, percentiles, throughput, device and
   per-stage timing in JSON/CSV.
4. Export logical embedding accesses as JSONL, CSV, and NPY; compute frequency,
   hotspot, duplicate, window, distance, and table statistics.
5. Simulate no/count/time/dual/adaptive bounded coalescing and report read
   reduction, added latency, occupancy, fan-out and state requirements.
6. Simulate modulo/static-table mapping and FIFO/round-robin/queue-aware/age-
   assisted scheduling for 4/8/16/32 channels.
7. Generate deterministic high/low-duplicate, balanced/skewed and hotspot-shift
   validation traces plus `trace_feasibility_summary.json` and the report.
8. Run all locally possible tests; mark missing PyTorch/CUDA separately as
   SKIPPED and never infer a model PASS from NumPy-only evidence.

## External/manual gates

1. User runs the frozen Stage-2A payload under Vivado 2020.2 and returns logs.
2. User manually prepares local Criteo data according to the documented schema.
3. Run GATE-T1/T2/T3 on real traces and review whether coalescing/scheduling
   benefits justify corresponding hardware.

## Hardware work blocked now

- Any Stage-2A RTL edit without server logs.
- Stage 2B, P=64, or two-dimensional PE work.
- Multi-layer MLP, feature-interaction, complete DLRM, HBM, coalescer, broadcast,
  or channel-scheduler RTL.
- AXI, Vitis RTL Kernel, XRT, `.xclbin`, or F37X board work.

## Explicit exclusions

DLRMv3, full DCN V2, transformer recommender, multi-FPGA, GPU-FPGA cluster,
server-memory hierarchy, reinforcement learning, global co-occurrence graphs,
complex dynamic precision, online training, and training acceleration.
