# Validation gates

## GATE-1 — Real RTL validation

Status: **PASS**.

Required evidence:

- all RTL parsed by a SystemVerilog compiler;
- eight independent testbenches report explicit PASS;
- top testbench matches all 24 Python vectors bit-for-bit;
- FIFO randomized backpressure passes without loss/duplication;
- elaboration/lint shows no multiple drivers, combinational loops, or severe
  width errors;
- logs identify the matching Git revision and source manifest.

Retry2 real evidence from validated source commit
`44a1b256f0e50cef0a54dbe88d23fb4be353e911` records Python 24-vector PASS,
`xvlog` PASS, 8/8 `xelab` PASS, 8/8 XSim PASS with explicit testbench markers,
and top-level 24-vector bit agreement.  The summary contains 18 PASS, 0 FAIL,
and 0 SKIPPED; the audited logs contain no timeout, fatal, error, or warning.

The server manifest says `git_revision: UNKNOWN` only because the credential-free
payload contains no `.git` directory.  Its 64 byte-count/SHA-256 records all
match tracked files in the validated commit, including all 17 RTL/testbench
files, so source traceability is complete.

GATE-1 approval completes phase 1 but does not authorize automatic phase-2
implementation.  The parameterized PE-array architecture must be reviewed first.

## GATE-2 — Parameterized compute architecture

Not started.  Its GATE-1 prerequisite is satisfied, but the parameterized
PE-array architecture requires explicit review before implementation.  GATE-2
will cover a bounded PE array, configurable parallelism, multicycle dot products,
multilayer MLP, per-layer Python agreement, resource estimates, and at least two
layer sizes.  Completion stops before HBM.

## GATE-3 — Complete simplified-DLRM architecture

Blocked.  Requires an architecture review of multiple embedding tables,
continuous features, bottom/top MLP, interaction, parameter storage, buffering,
reuse, and throughput/resource model before global dataflow changes.

## GATE-4 — F37X/HBM

Blocked.  Real HBM, AXI, Vitis RTL Kernel, and F37X work require explicit user
approval plus an existing kernel shell, platform-interface data, and real logs.
