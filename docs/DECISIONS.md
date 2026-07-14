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
