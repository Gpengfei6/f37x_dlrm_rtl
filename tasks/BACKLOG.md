# Backlog

## Authorized Stage 2A implementation

1. Add a Python Stage-2 arithmetic/schedule oracle with ACC32 wrap and ACC48
   safe modes, runtime shifts, optional ReLU, tails, and invalid descriptors.
2. Implement and independently test a signed, parameterized MAC lane.
3. Implement and independently test runtime round/saturate/ReLU without changing
   the v0 quantization order.
4. Implement and independently test a P-bank activation buffer with default
   1024 dimension capacity, tails, scalar result writes, and elastic reads.
5. Implement and independently test the abstract local P-weight/bias provider;
   keep HBM/AXI details outside.
6. Implement and independently test the multi-cycle vector dot core with P lane
   sums, registered reduction, bias, ACC32/48, and full backpressure.
7. Implement the runtime dense-layer engine with immutable descriptors,
   ping-pong ownership, one output neuron at a time, result FIFO, and errors.
8. Cover P=4/8/16/32, 8->4, 64->32, 13->7, 65->17, D<P, tails,
   extrema, shifts, ReLU, stalls, same-edge replacement, continuous jobs, and
   invalid dimensions.
9. Preserve and rerun all GATE-1 Python checks; enumerate all new sources in
   Vivado 2020.2 validation scripts and exact source manifests.
10. Generate the Stage-2A server validation payload, record local RTL tests as
    SKIPPED, and stop for user-run XSim evidence.

## Blocked after Stage 2A

1. Audit returned Vivado 2020.2 `xvlog`/`xelab`/XSim logs and exact hashes.
2. Stage 2B: add two lane-partial-sum banks and overlap output `o` reduction
   with output `o+1` MAC work; verify tags, ordering, stalls, and target cycles.
3. Only after Stage-2B real validation, review GATE-2.
4. Synthesize P=4/8/16/32 and ACC32/48 on the exact VU37P target; compare timing,
   DSP/LUT/FF/RAM use, routing, and power proxies before selecting final P.
5. Approve trained-model layer shifts, activation policy, and ACC48 adoption.

## Explicitly deferred

- Two-dimensional input/output PE array (Scheme C).
- Multilayer MLP controller, complete Bottom/Top MLP, feature interaction, or
  full DLRM dataflow.
- Dynamic microbatching or concurrent sample contexts.
- Provider-side weight caching policy, real HBM, AXI, Vitis RTL Kernel, XRT,
  `.xclbin`, or F37X execution.
- Embedding multi-table expansion, duplicate-ID merge, and HBM balancing.

## Current stop point

Stage 2A implementation is authorized only through local code, Python tests,
static review, and validation-package generation.  Stop before Stage 2B and
before claiming RTL PASS without returned server evidence.
