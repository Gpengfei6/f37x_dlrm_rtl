# Current state

## Stage

Phase 1 hardening.  The minimum embedding-sum/dense/ReLU pipeline is implemented;
phase 2 is blocked by GATE-1.  The pre-hardening baseline is Git commit
`22d35f4` on branch `main`.

## Real validation status

- PASS: Python fixed-point regression, 24 deterministic vectors, reference model,
  packed-output self-comparison, independent arithmetic/hex/endian checks,
  PowerShell parsing, validation-summary schema, and handoff payload/hash checks.
- NOT EXECUTED: SystemVerilog compilation, all RTL testbenches, XSim, RTL lint,
  Vivado synthesis, `.xclbin`, and F37X execution.
- GATE-1 is not satisfied.  Python results do not substitute for RTL logs.

## Readiness

The code is suitable for stage-1 compiler/simulator validation after the current
hardening patch is complete.  It is not approved for phase 2.

## Highest-priority risks

1. No real SystemVerilog parser/elaboration/simulation evidence exists.
2. Vivado/XSim 2020.2 portability is unconfirmed.
3. HBM timing/resource conclusions cannot be drawn from the local memory model.
4. The parallel phase-1 dot product has no final resource/timing evidence.

## Next action

The user runs only the commands in `SERVER_HANDOFF.md` and returns the requested
compiler/elaboration/simulation logs.  Codex then repairs the earliest root cause
without entering phase 2.

## Most recent files

Recent changes cover `.gitattributes`, `.gitignore`, `AGENTS.md`, README,
workflow/state/decision/risk/gate/handoff/static-review documents, task records,
PowerShell/Tcl/Python validation scripts, all eight testbenches, fixed-point
regression checks, and `handoff/stage1_validation/`.
