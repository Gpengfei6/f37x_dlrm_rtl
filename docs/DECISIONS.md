# Design decisions

## D-001 — Freeze the phase-1 fixed-point contract

- **Problem:** independent review must not silently change arithmetic behavior.
- **Adopted:** retain INT8 Q3.4 embeddings/weights, INT24 Q15.8 bias, INT32 Q*.8
  wrapping accumulator, shift-four ties-away rounding, INT16 saturation, then
  ReLU.
- **Not adopted:** convergent rounding, truncation, saturating accumulation, or a
  different binary point.
- **Reason:** the existing Python/RTL/test-vector contract is internally
  consistent and changing it requires a human gate.
- **Impact:** exact behavior is stable; production accuracy/range analysis remains
  future work.

## D-002 — Use magnitude-domain signed rounding

- **Problem:** arithmetic right shift alone rounds negative values toward minus
  infinity and does not implement symmetric ties-away behavior.
- **Adopted:** extend by one sign bit, round the absolute magnitude, then restore
  sign and saturate.
- **Not adopted:** add a positive half-LSB followed directly by `>>>` for both
  signs.
- **Reason:** the adopted form handles negative half ties and `INT_MIN` exactly.
- **Impact:** a small amount of combinational logic is used; Python and RTL remain
  bit-identical.

## D-003 — Keep the phase-1 dot product verification-oriented

- **Problem:** the current dot core expands all vector products combinationally.
- **Adopted:** retain it only for phase-1 correctness validation.
- **Not adopted:** begin PE-array or multicycle optimization before GATE-1.
- **Reason:** optimization would obscure compiler/simulation root causes and is a
  phase-2 task.
- **Impact:** clear one-cycle dot behavior, but no resource/performance claim.

## D-004 — Local Git baseline and portable line endings

- **Problem:** logs and source must correspond to a reproducible version, and
  Windows checkout rules can corrupt Linux shell scripts with CRLF.
- **Adopted:** initialize local Git, freeze commit `22d35f4`, and enforce LF for
  shell/Tcl/SystemVerilog/Python/data files with `.gitattributes`.
- **Not adopted:** depend on global Git configuration or an unversioned directory.
- **Reason:** repository-local behavior is reviewable and does not alter global
  user settings.
- **Impact:** future bundles can report a commit/diff; PowerShell remains CRLF.

## D-005 — Validation summaries are status-explicit

- **Problem:** unavailable tools must not appear as successful tests.
- **Adopted:** every command records `PASS`, `FAIL`, or `SKIPPED`, exit code, and
  log path in `results/validation_summary.json`.
- **Not adopted:** a single boolean success flag or treating absence as success.
- **Reason:** GATE-1 depends on auditable real RTL evidence.
- **Impact:** local Python-only runs complete successfully but keep GATE-1 false.

## D-006 — Seed randomized FIFO traffic once

- **Problem:** repeated `$urandom(seed)` calls can restart or otherwise vary the
  random stream across simulators, weakening backpressure coverage.
- **Adopted:** seed once, then use `$urandom()` while holding source valid/data
  whenever ready is low.
- **Not adopted:** change data every cycle or repeatedly pass the same seed.
- **Reason:** the producer now obeys ready/valid and remains deterministic enough
  for regression while exercising a continuous pseudo-random stream.
- **Impact:** stronger FIFO loss/duplication evidence without changing RTL.

## D-007 — Keep generated validation outputs out of Git

- **Problem:** timestamps, local paths, logs, and reconstructed results make the
  source tree appear dirty and cannot be a stable source revision.
- **Adopted:** track `logs/.gitkeep` and `results/.gitkeep`, ignore generated
  contents, and carry evidence in validation zip files plus SHA-256 manifests.
- **Not adopted:** commit every local/server log or discard logs after a run.
- **Reason:** source commits stay reproducible while evidence remains available
  as explicit artifacts tied to exact file hashes.
- **Impact:** baseline logs remain in the initial commit; later runs regenerate
  them locally and include them in the handoff log bundle.

## D-008 — Declare a uniform source timescale

- **Problem:** retry0 `xelab` reported `XSIM 43-4099` because testbenches had a
  timescale while instantiated module files did not.
- **Adopted:** place `` `timescale 1ns/1ps `` first in every independently
  compiled module file and retain the identical declaration in all testbenches;
  the package remains timescale-independent.  Add `xelab --timescale 1ns/1ps` as
  secondary protection.
- **Not adopted:** delete testbench delays, add timescale only to reported files,
  or rely only on an elaborator option.
- **Reason:** source-level consistency is explicit and Vivado 2020.2-compatible;
  the option protects future units without masking the primary contract.
- **Impact:** simulation units are defined consistently; synthesizable logic,
  interfaces, timing cycles, and fixed-point values are unchanged.

## D-009 — Scope Dense loop indices to their procedural owners

- **Problem:** retry0 `xelab` reported `VRFC 10-3818` because module-level
  `integer index` was assigned by both `initial` and `always_ff` processes.
- **Adopted:** use block-local `init_index`, `pack_index`, and `reset_index` in
  memory initialization, parameter selection, and reset respectively; retain the
  existing generate `genvar`.
- **Not adopted:** remove initialization/reset loops, change memories, or alter
  the Dense state machine.
- **Reason:** Vivado's single-driver rule is satisfied without behavioral change.
- **Impact:** no interface, calculation order, latency, storage contents, or
  resource intent changes.  Other RTL loop variables were reviewed and each is
  confined to one process.

## D-010 — Sample combinational ready after it settles

- **Problem:** retry1 XSim failed three same-edge replacement tests at
  `Iteration: 0`; each test changed downstream ready and immediately read the
  combinational upstream ready in the same active-region process.
- **Adopted:** keep the original ready assertion and the same following rising
  edge, but insert `#1` after the negative-edge stimulus.  Extend the directed
  tests to consecutive replacement cycles and add a depth-one FIFO instance.
- **Not adopted:** remove or weaken an assertion, delay the transfer to a later
  clock, or change already-correct RTL merely to influence simulator scheduling.
- **Reason:** `rv_fifo`, `dot_product_core`, and `embedding_mem_model` already
  implement elastic acceptance and preserve occupied output registers under
  backpressure.  Combinational propagation requires a delta cycle before a
  deterministic observation.
- **Impact:** test scheduling becomes portable while the checked handshake edge,
  RTL interfaces, state updates, latency, and arithmetic remain unchanged.

## D-011 — Retain the phase-1 single-transaction integration contract

- **Problem:** passing integration tests must not be mistaken for sustained
  top-level one-request-per-cycle throughput evidence.
- **Adopted:** retain the documented one-active-request controller.  Its tests
  hold the next input valid for multiple cycles while the old output is blocked,
  verify output stability, and vary output stalls across the 24 vectors.
- **Not adopted:** add top-level elastic replacement or pipeline concurrency as
  part of this retry2 repair.
- **Reason:** such a throughput change would alter the published phase-1 cycle
  contract and belongs after GATE-1.
- **Impact:** integration backpressure evidence is real but bounded; no phase-2
  architecture or performance claim is introduced.
