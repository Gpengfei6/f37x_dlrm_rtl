# Backlog

## Stage 2A server-validation gate

Local implementation, Python regression, static checks, and payload generation
are complete.  Remaining Stage-2A work is deliberately external/audit-only:

1. Run the exact payload under server Vivado 2020.2.
2. Return Stage-1 and Stage-2A `xvlog`/`xelab`/XSim logs and status files.
3. Match every source SHA-256 record to the Stage-2A code commit.
4. Require all explicit testbench PASS markers; audit fatal/error/timeout/severe
   warning text and the 24-vector compatibility evidence.
5. Fix only demonstrated Stage-2A root causes if the server run fails.

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
