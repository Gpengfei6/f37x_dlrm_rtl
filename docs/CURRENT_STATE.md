# Current state

## Stage

Phase 1 is complete and GATE-1 is approved.  The conditionally approved Stage-2
architecture is frozen in commit
`748013312e9cb7dce106a8be4ea7a17aacbb87a7`.  The Stage-2A non-overlapped vector
PE baseline is implemented.  Stage 2C makes its activation and weight storage
synthesis-friendly.  Stage 2D adds elastic runtime-quantization and DSP-product
pipelines and closes the local 100 MHz Vivado 2022.1 OOC constraint.  Stage 2E
returns exact-source Vivado 2020.2 Python, XSim, synthesis, memory-inference,
and 100 MHz OOC timing evidence; the target-version reproduction now passes.
Stage 2F adds a reproducible Artix-7 OOC implementation flow.  Its local
Vivado 2022.1 post-route precheck passes, while exact Vivado 2020.2 post-route
reproduction remains pending.

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

Local Vivado 2022.1/XSim passes all six independent Stage 2A benches after the
Stage 2C memory changes, and Stage 2B passes all 20 deterministic cases with the
exact marker `valid=11 invalid=9 total=20`.  Returned exact-source Vivado 2020.2
evidence now independently passes the same six Stage 2A benches and all 20
Stage 2B cases.  The Phase 1, Stage 2A, and Stage 2B Python suites pass in both
reviewed environments.

The default Stage 2D `mlp_sequence_controller` completes 100 MHz Artix-7 OOC
synthesis with 4,550 LUT, 1,946 FF, 17 RAMB36E1, 32 RAMB18E1, 21 DSP, and no
latches.  The Stage 2C RAM mapping is unchanged.  Timing closes with WNS
+0.758 ns, TNS 0, and no failing setup endpoints.  The former 32-level
quantization-to-activation path is split into two elastic stages; the final
worst path is a met weight-request-address range-check path.  See
`docs/STAGE2D_TIMING_REVIEW.md`.

Stage 2E evidence identifies `/opt/Xilinx/Vivado/2020.2/bin/vivado`, Vivado
v2020.2 SW Build 3064766, branch `work/stage2e-vivado2020-repro`, and source
head `fff6bd8`.  OOC synthesis for `xc7a200tfbg484-2` at 10.000 ns exactly
matches the Vivado 2022.1 baseline: 4,550 LUT, 1,946 FF, 17 RAMB36E1,
32 RAMB18E1, 21 DSP, WNS +0.758 ns, TNS 0, zero failing endpoints, and zero
latches.  The 16 weight banks, one bias RAM, and 32 activation banks retain
their Stage 2C mappings.  The returned server status includes untracked
simulation products but no evidence of a tracked source modification.  See
`docs/STAGE2E_VIVADO2020_REPRO.md`.

The Stage 2F local Vivado 2022.1 OOC implementation completes synthesis, opt,
placement, physical optimization, and routing with 0 unrouted nets.  At
10.000 ns it reports setup WNS +0.597 ns/TNS 0 and hold WHS +0.098 ns/THS 0,
with zero setup or hold failing endpoints.  Post-route resources are 4,320 LUT,
1,946 FF, 17 RAMB36E1, 32 RAMB18E1, and 21 DSP; latch, anchored log error, and
anchored log critical-warning counts are all zero.  DRC has 0 errors and 44
ordinary OOC/pipeline warnings; methodology has 593 ordinary warnings and no
critical warnings.  No congestion window exceeds level 5.  The post-route
worst path remains a met weight-request range-check path.  See
`docs/STAGE2F_ARTIX7_POST_ROUTE_FEASIBILITY.md`.

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

1. place classic Criteo TSV data in a user-chosen local file/directory and run
   `python -m analysis.run_trace_feasibility --criteo-path <local-path>`.
2. the user runs the checked-in Stage 2F Tcl under authenticated Vivado 2020.2
   and returns the status and lightweight reports for version comparison.
3. when separately authorized, the user performs board-level implementation,
   F37X/VU37P compilation, `.xclbin` generation, and board validation.

An environment that already contains PyTorch may also rerun CPU and optional
CUDA tests; this repository will not install it or download data.

The Stage 2F local OOC result proves neither Vivado 2020.2 post-route behavior
nor board-level I/O timing, F37X/VU37P compilation, `.xclbin` generation, or
board execution, and does not authorize further Stage-2A arithmetic or latency
changes.  Stage 2B overlap remains optional and deferred.
Coalescing/scheduling RTL, complete DLRM RTL, feature interaction RTL, HBM, AXI,
and Vitis remain blocked until real traces pass GATE-T1/T2/T3 and a later
architecture review authorizes hardware.
