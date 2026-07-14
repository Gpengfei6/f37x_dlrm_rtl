# Current state

## Stage

Phase 1 Vivado 2020.2 elaboration compatibility repair.  The minimum
embedding-sum/dense/ReLU pipeline is implemented; phase 2 remains blocked by
GATE-1.  The retry0 server payload matches local commit `e5fffc8` for all 17
RTL/testbench files by SHA-256, although that server manifest recorded its Git
revision as `UNKNOWN`.

## Real validation status

- SERVER RETRY0 PASS: Python 24-vector regression and `xvlog` compilation under
  Vivado 2020.2.
- SERVER RETRY0 FAIL: all eight testbenches failed during `xelab`; five exposed
  missing module timescales and three Dense-containing designs exposed the shared
  procedural loop variable in `dense_layer_core.sv`.
- POST-FIX LOCAL PASS: Python fixed-point/reference/packed checks plus explicit
  source guards for uniform timescale and process-local Dense loop indices.
- NOT EXECUTED: post-fix RTL elaboration/simulation, RTL lint, Vivado synthesis,
  `.xclbin`, and F37X execution.
- GATE-1 is not satisfied.  Python results do not substitute for RTL logs.

## Readiness

The two verified retry0 elaboration root causes have minimal source fixes and are
ready for retry1 server validation.  No RTL functionality has yet been simulated,
and the code is not approved for phase 2.

## Highest-priority risks

1. Retry1 may reveal a later elaboration error hidden by the two retry0 failures.
2. No testbench has produced a valid functional XSim result yet.
3. HBM timing/resource conclusions cannot be drawn from the local memory model.
4. The parallel phase-1 dot product has no final resource/timing evidence.

## Next action

Use the generated retry1 payload to rerun Python and the ordered XSim Tcl flow
with the minimal commands in `SERVER_HANDOFF.md`.  Codex reviews the new earliest
result without entering phase 2.

## Most recent files

Recent changes add `1ns/1ps` to all eight module files, split Dense procedural
loop variables by process, add an `xelab --timescale` fallback, strengthen Python
source-contract checks, and update state/risk/decision/handoff records.  No
external interface, state sequence, latency, or fixed-point behavior changed.
