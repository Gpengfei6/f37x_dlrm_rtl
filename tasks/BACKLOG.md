# Backlog

## Completed local software milestone

The configurable PyTorch path, independent NumPy oracle, synthetic/local-Criteo
data adapters, inference/training interfaces, metrics, trace formats/statistics,
five bounded coalescers, and five abstract channel policies are implemented.
The software suite is 12 PASS/0 FAIL/2 SKIPPED; PyTorch CPU/CUDA are the skips.
Synthetic GATE-T tooling is complete, but no trace gate is approved.

## Next evidence work

1. On a machine already containing PyTorch, run the CPU path and, if present,
   the explicitly synchronized CUDA path; preserve JSON/CSV outputs.
2. With user-supplied classic Criteo TSV files, validate loader cardinalities
   and generate the real trace statistics.
3. Review the GATE-T1 request/wait sweep against latency constraints and the
   internal 10%-15% engineering line.
4. Replace the two-candidate abstract channel-placement assumption with an
   explicitly reviewed HBM table/address mapping before GATE-T2/T3 conclusions.
5. Decide manually whether the real coalescing and scheduling benefits justify
   corresponding RTL; a small or negative benefit stops that hardware path.

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
