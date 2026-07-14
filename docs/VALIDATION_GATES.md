# Validation gates

## GATE-1 — Real RTL validation

Status: **NOT MET**.

Required evidence:

- all RTL parsed by a SystemVerilog compiler;
- eight independent testbenches report explicit PASS;
- top testbench matches all 24 Python vectors bit-for-bit;
- FIFO randomized backpressure passes without loss/duplication;
- elaboration/lint shows no multiple drivers, combinational loops, or severe
  width errors;
- logs identify the matching Git revision and source manifest.

Current evidence is Python-only, so phase 2 is forbidden.
The ordered validation flow and credential-free payload are ready under
`handoff/stage1_validation/`; readiness of scripts is not gate evidence.

## GATE-2 — Parameterized compute architecture

Blocked by GATE-1.  When unblocked it covers a bounded PE array, configurable
parallelism, multicycle dot products, multilayer MLP, per-layer Python agreement,
resource estimates, and at least two layer sizes.  Completion stops before HBM.

## GATE-3 — Complete simplified-DLRM architecture

Blocked.  Requires an architecture review of multiple embedding tables,
continuous features, bottom/top MLP, interaction, parameter storage, buffering,
reuse, and throughput/resource model before global dataflow changes.

## GATE-4 — F37X/HBM

Blocked.  Real HBM, AXI, Vitis RTL Kernel, and F37X work require explicit user
approval plus an existing kernel shell, platform-interface data, and real logs.
