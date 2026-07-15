# Current state

## Stage

Phase 1 is complete and GATE-1 is approved.  The conditionally approved Stage-2
architecture is frozen in commit
`748013312e9cb7dce106a8be4ea7a17aacbb87a7`.  The Stage-2A non-overlapped vector
PE baseline is implemented locally and has reached the server RTL-validation
stop point.  Stage-2A RTL is **not yet passed** because this machine has no RTL
compiler, simulator, or linter.

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

The unified local result is 6 PASS, 0 FAIL, and 5 SKIPPED.  The SKIPPED items
are Icarus, Verilator, Verible, Stage-1 XSim, and Stage-2A XSim.  They remain
SKIPPED by policy and cannot satisfy a real RTL gate.

## Next action

Run the generated Stage-2A payload under server Vivado 2020.2/XSim, return the
exact manifest/status/log archive, and audit every explicit PASS marker.  Stop
there.  Stage 2B output-neuron MAC/reduction overlap, full MLP, HBM, AXI, and
Vitis work remain prohibited.
