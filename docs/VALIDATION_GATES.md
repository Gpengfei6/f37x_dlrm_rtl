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

Status: **IN PROGRESS; not approved**.

The architecture review conditionally approved Scheme B and Stage 2A.  The
non-overlapped Stage-2A baseline is locally implemented with P=4/8/16/32,
ACC32/48, runtime dimensions, banked ping-pong activation buffers, an abstract
local provider, runtime quantization metadata, and ready/valid boundaries.
Python tests pass, but all local RTL tools are absent, so RTL evidence is
SKIPPED and Stage 2A awaits real Vivado 2020.2/XSim logs.

A successful Stage-2A server run can close the bounded parameterized-compute
baseline after log review.  Stage 2B double-partial-sum overlap is now an
optional later performance optimization, not a GATE-2 prerequisite.  Full MLP
RTL and HBM remain outside this gate.

## GATE-T1/T2/T3 — Trace feasibility

Not started on real data.  GATE-T1 measures coalescing read reduction versus
added mean/P99 wait; GATE-T2 measures channel imbalance and lightweight
scheduler improvement; GATE-T3 compares their combined predicted end-to-end
value.  Synthetic traces validate tools only and cannot pass these gates.

## GATE-3 — Complete simplified-DLRM architecture

Blocked.  Requires an architecture review of multiple embedding tables,
continuous features, bottom/top MLP, interaction, parameter storage, buffering,
reuse, and throughput/resource model before global dataflow changes.

## GATE-4 — F37X/HBM

Blocked.  Real HBM, AXI, Vitis RTL Kernel, and F37X work require explicit user
approval plus an existing kernel shell, platform-interface data, and real logs.
