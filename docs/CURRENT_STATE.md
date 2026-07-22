# Current state

## Stage

Phase 1 is complete and GATE-1 is approved.  The conditionally approved Stage-2
architecture is frozen in commit
`748013312e9cb7dce106a8be4ea7a17aacbb87a7`.  The Stage-2A non-overlapped vector
PE baseline is implemented.  The Stage 2C branch makes its activation and weight
storage synthesis-friendly and adds local Vivado 2022.1 XSim/OOC synthesis
evidence.  Stage-2A RTL is still **not target-version passed** because exact
Vivado 2020.2 evidence has not been returned.

The final thesis scope is frozen.  Stage 2A remains the compute foundation.
The first software-only DLRM and embedding-access feasibility tool set is now
implemented.  No `rtl/` or `tb/` file changed during that work.

## GATE-1 evidence

- Python fixed-point regression: 24 deterministic vectors PASS.
- Vivado 2020.2 `xvlog`: PASS.
- Vivado 2020.2 `xelab`: 8/8 testbenches PASS.
- XSim: 8/8 testbenches PASS, each with its own explicit PASS marker.
- Top-level: `tb_dlrm_minimal_top: PASS cases=24`; all 24 emitted packed outputs
  match `tests/expected/top_outputs.hex` bit for bit.
- Validation summary: 18 PASS, 0 FAIL, 0 SKIPPED.
- Log audit: no timeout, fatal, error, critical warning, ordinary warning, or
  source-hash mismatch.

## Source traceability

The server-regenerated `results/source_manifest_sha256.json` reports
`git_revision: UNKNOWN` because the validation payload intentionally excludes
the `.git` directory.  This is not an untraceable source state: all 64 manifest
records match tracked files in commit `44a1b25` by byte count and SHA-256, and
all 17 RTL/testbench files match individually.

## Readiness and boundary

GATE-1 proves the phase-1 fixed-point RTL compiles, elaborates, and passes its
defined functional/backpressure tests under Vivado 2020.2/XSim.  Stage 2A adds
six independent modules and six self-checking testbenches without replacing a
phase-1 module.  Local Python evidence is:

- phase-1 24-vector regression and packed comparison PASS;
- Stage-2A P=4/8/16/32 schedule/mask checks PASS;
- 96 phase-1-compatible ACC32 checks PASS;
- 256 named layer/shift/ReLU/ACC32/ACC48 checks PASS;
- 200 deterministic random dot-product checks PASS;
- estimator self-check PASS.

Local Vivado 2022.1/XSim now passes all six independent Stage 2A benches after
the Stage 2C memory changes.  Stage 2B also passes all 20 deterministic cases
with the exact marker `valid=11 invalid=9 total=20`.  The phase-1, Stage 2A, and
Stage 2B Python suites pass.  These are real local tool runs but do not substitute
for the required Vivado 2020.2 source-matched evidence.

The default Stage 2C `mlp_sequence_controller` completes 100 MHz Artix-7 OOC
synthesis with 5,313 LUT, 1,819 FF, 17 RAMB36E1, 32 RAMB18E1, 21 DSP, and no
latches.  The two activation buffers consume the 32 RAMB18 blocks; the 16
weight banks and one bias RAM consume the 17 RAMB36 blocks.  Timing does not
close: WNS is -2.460 ns, TNS is -1371.656 ns, and 861 setup endpoints fail.  The
worst path is the 32-level runtime quantization/saturation path into activation
BRAM write data, not weight-bank rotation.  See `docs/STAGE2C_SYNTHESIS_REVIEW.md`.

The software feasibility regression is separately 12 PASS, 0 FAIL, and 2
SKIPPED.  Config/model dimensions, deterministic NumPy oracle forward and exact
save/reload, known dot interaction, guarded local Criteo loading, AUC/LogLoss,
JSON/CSV timing, three trace formats, window statistics, five bounded
coalescers, and the 4/8/16/32-channel scheduler grid pass.  PyTorch CPU and CUDA
are both SKIPPED because this local Python 3.12 runtime has no `torch`; the
NumPy result is not relabeled as a PyTorch PASS or formal CPU baseline.

Six synthetic trace classes pass tool validation.  At an eight-request/eight-
cycle dual bound, modeled read reduction ranges from 0% for low-duplicate and
balanced traces to 57.62% for the intentionally high-duplicate trace.  The
abstract queue-aware model slightly degrades the balanced/low-duplicate
eight-channel cases, so the results do not manufacture a universal scheduling
benefit.  GATE-T1, GATE-T2, and GATE-T3 all remain **INCONCLUSIVE** because no
real user-supplied Criteo data is present.

## Next action

Three independent follow-up tracks remain:

1. wait for the user to run the frozen Stage-2A payload under Vivado 2020.2;
2. review a separate quantization/activation-write pipeline change before any
   100 MHz timing-closure claim, then rerun latency and functional contracts;
3. place classic Criteo TSV data in a user-chosen local file/directory and run
   `python -m analysis.run_trace_feasibility --criteo-path <local-path>`.

An environment that already contains PyTorch may also rerun CPU and optional
CUDA tests; this repository will not install it or download data.

The Stage 2C storage review does not authorize further Stage-2A arithmetic or
latency changes.  Stage 2B overlap remains optional and deferred.
Coalescing/scheduling RTL, complete DLRM RTL, feature interaction RTL, HBM, AXI,
and Vitis remain blocked until real traces pass GATE-T1/T2/T3 and a later
architecture review authorizes hardware.
