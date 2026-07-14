# Current state

## Stage

Phase 1 Vivado 2020.2 ready/valid simulation repair.  The minimum
embedding-sum/dense/ReLU pipeline is implemented; phase 2 remains blocked by
GATE-1.  The retry1 server payload matches local commit `66c9307` for all 17
RTL/testbench files by SHA-256, although the server-regenerated manifest records
its Git revision as `UNKNOWN`.

## Real validation status

- SERVER RETRY1 PASS: Python 24-vector regression, `xvlog`, all eight `xelab`
  runs, five of eight independent simulations, and the top-level 24-vector
  bit-for-bit comparison under Vivado 2020.2.
- SERVER RETRY1 FAIL: the FIFO, dot-product, and embedding-memory directed
  same-edge replacement tests stopped at their immediate ready assertions.
- ROOT CAUSE: all three fatal messages occurred at XSim `Iteration: 0`.  Each
  testbench changed a downstream ready input and read the resulting combinational
  upstream ready output in the same active-region evaluation, before a delta
  cycle.  The matching RTL already implements the specified elastic ready logic
  and state update behavior.
- POST-FIX LOCAL PASS: Python fixed-point/reference/packed checks and static
  guards preserving continuous replacement plus depth-one FIFO coverage.
- NOT EXECUTED LOCALLY: post-fix RTL simulation/lint, Vivado synthesis, `.xclbin`,
  and F37X execution.
- GATE-1 is not satisfied until retry2 produces eight real simulation passes.

## Readiness

Retry1 proves Vivado 2020.2 compilation/elaboration compatibility and most RTL
functionality.  The replacement assertions now sample after combinational
settling without changing their transfer edge or expected value; they also cover
consecutive replacements and a depth-one FIFO.  No RTL datapath or interface
change was justified.  The code is ready for retry2 but not phase 2.

## Highest-priority risks

1. Retry2 must confirm that the three repaired tests pass under XSim 2020.2.
2. The phase-1 integration controller remains intentionally single-transaction;
   it tests held valid and multi-cycle output backpressure, not one-request-per-
   cycle top-level throughput.
3. HBM timing/resource conclusions cannot be drawn from the local memory model.
4. The parallel phase-1 dot product has no final resource/timing evidence.

## Next action

Generate and run the retry2 stage-1 payload with the ordered XSim flow.  Review
all eight PASS markers and the top-level 24-vector comparison before changing
GATE-1, without entering phase 2.

## Most recent files

Recent changes retain all same-edge assertions, sample combinational ready after
one nanosecond within the existing half-cycle, exercise consecutive replacement
edges, instantiate a depth-one FIFO case, and add static regression guards.  The
three affected RTL modules are unchanged because their existing elastic logic is
already correct; interfaces, latency, and fixed-point behavior are unchanged.
