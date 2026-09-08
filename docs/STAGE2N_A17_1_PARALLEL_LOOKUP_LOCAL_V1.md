# Stage 2N-A17.1 — Local parallel lookup and A13 integration

Date: 2026-09-08

Status: **LOCAL XSIM PASS**. RTL compile, elaboration and both independent
self-checking simulations pass. Target build, physical HBM and performance are
not validated.

## Scope and authority

The user requested continuation after reviewing
`STAGE2N_A17_MULTIBANK_ARCHITECTURE_REVIEW_V1.md`, including delegated work.
This stage implements the proposed first local work unit: four independent
read engines and their integration with the accepted A13 pipeline. Historical
single-bank-only stage restrictions are superseded only for these new A17 local
files. Accepted RTL, Host, runners, model contracts and evidence remain frozen.
No public F37X kernel, Host, connectivity, XO, xclbin or board run is added here.

Starting HEAD is `ec062ba6c8a0a22c29b28abc73e0b94668e03fd7`, on existing branch
`work/stage2n-a16-multibank-parallel`. Historical untracked files are preserved.
The A17 name follows the user's handoff; A16.3 remains an unused historical
next-stage label, not a newly accepted milestone.

## Implementation

`rtl/hbm/dlrm_hbm_parallel_lookup_stage2n_a17_v1.sv` instantiates four unmodified
A14 v2 engines. The local module interface uses packed four-port arrays;
these are not yet four packaged Vitis master interfaces. Each engine has a
64-bit address, a 128-bit row, a one-bit ID, ARLEN=0 and ARSIZE=4, and at most
one outstanding read. Rows are eight signed INT16 elements; no rounding,
saturation or arithmetic conversion is introduced. Lane 0 remains bits 15:0.
Address alignment, range and overflow rejection reuse the accepted A14 block.

One load handshake snapshots all four bases and row indexes. Independent
issued/received masks prevent duplicate requests. Per-slot response registers
retain all four results, including simultaneous responses. Only after all four
successful responses are consumed are slots 0–3 sent through one ready/valid
configuration port. Data and slot remain stable under backpressure. The
committed mask is cleared for every new group and set only by configuration
handshakes; done is a single pulse after the final injection.

All four requests are allowed to finish even if one fails. Every engine's
response is consumed before the retained error state becomes acknowledgeable.
A failed group performs no injections. The error mask records all failed
slots. Error acknowledgement allows a new group; it does not cancel AXI
transactions. A peer that never responds intentionally keeps the group busy;
there is no timeout-based silent reuse of an outstanding transaction. Missing
RLAST is detected as a single-beat protocol fault, not repaired as a burst.

`rtl/pipeline/dlrm_hbm_pipeline_integration_stage2n_a17_v1.sv` connects that
controller to the unchanged A13 pipeline, with fixed indexes 37–40. It rejects
Host writes to HBM-owned embedding slots, requires a completed fresh group
before computation, consumes that permission at START, and prevents a new
load from overwriting data during computation or a pending result/error.
Loading takes precedence over START. Model arithmetic and compute counters
are unchanged.

## Tests and reproducibility

Two independent module benches are added:

- `tb/tb_dlrm_hbm_parallel_lookup_stage2n_a17_v1.sv`: public-port fake-memory
  scoreboard, lane-by-lane golden, all response permutations, simultaneous
  returns, independent AR delays, retained output, capture-on-load,
  no-reset restart, invalid addresses and response errors with delayed peers.
- `tb/tb_dlrm_hbm_pipeline_integration_stage2n_a17_v1.sv`: actual A13 compute
  integration, original deterministic network, fresh-group START gating,
  ordered injection and failure/restart behavior.

The runner `scripts/run_stage2n_a17_1_multibank_xsim_v1.ps1` uses the local
Vivado/XSim 2022.1 installation, creates a new result directory, records every
tool return code and source SHA256, requires explicit final PASS markers,
rejects tool errors/fatals/assertion failures, reports warnings, validates the
canonical 64-row table, and checks all 242 baseline executable/model assets
against the frozen commit before and after the run. It never deletes old
results or downloads tools. Pass an explicit unused `-ResultDir` to choose
another output location.

The accepted complete run is retained at
`results/stage2n_a17_1/final_v2/`. Its final status records six zero tool return
codes, zero warnings for both benches,
`FROZEN_EXECUTABLE_ASSETS_UNCHANGED=PASS`, and `A17_1_LOCAL_XSIM=PASS`.
The compact tracked acceptance summary is
`docs/evidence/stage2n_a17_1/local_xsim_v1/acceptance_summary.txt`.
The run produced:

```text
A17_1_PARALLEL_LOOKUP_CASES=73
A17_1_RESPONSE_PERMUTATIONS=24
A17_1_SIMULTANEOUS_RESPONSE_CASES=1
A17_1_ADDRESS_ERROR_CASES=12
A17_1_RESPONSE_ERROR_CASES=12
A17_1_PARALLEL_LOOKUP_TEST=PASS

A17_1_GOLDEN_FINAL_RESULT=36
A17_1_ACTUAL_FINAL_RESULT=36
BOTTOM_CYCLES=322
INTERACTION_CYCLES=100
TOP_CYCLES=744
TOTAL_CYCLES=1174
PIPELINE_RUN_COUNT=2
A17_1_PIPELINE_INTEGRATION_TEST=PASS
```

Evidence identities are:

```text
status.txt SHA256 = ab7cc44dc7f62980a20baf83f2c5cf2c12a869cfdf02bb5b3c60ec6244a69047
source_sha256.txt SHA256 = d751795202403d3d4a7c7bff1f5c84f90f088ea4ddf47bc4103e1f365518b12a
parallel xsim.stdout.log SHA256 = 6c2b8f685ac2b97e11c34233274c12b6fc9182f4cffcd47bf080e4cd823d25a3
integration xsim.stdout.log SHA256 = 226f9812ff98854b78fccb87f62180528246b7dbcdbcaf701181985ab206c4e3
```

An earlier runner attempt exposed a log-file name collision. Another run then
correctly rejected a testbench assertion caused by sampling the accepted A13
counters one rising edge too early. The final test waits for the counter freeze
edge and uses case inequality so unknown values cannot pass golden checks.
Those failed attempts are diagnostic history, not acceptance evidence.

The pipeline sample's expected result 36 is an independently established
analytic golden (1+2+...+8), not the trained board sample. The sample primarily
validates dense-path preservation; explicit slot data comparisons check the
embedding transfer. Passing it cannot replace the five trained-model
slot-sensitivity tests required at the later A17 kernel/board stage.

## Measurement and evidence boundary

A17.1 adds no FPGA latency register or public AXI-Lite ABI. Testbench cycles
depend on fake-memory delays and are not a physical latency/speedup result.
There is one whole group in flight; subsequent computation/load overlap and
steady-state throughput optimization are outside this stage.

The accepted A16.2 112/1174/1289-cycle physical baseline remains unchanged.
Before later comparisons, the A17 public kernel must implement equivalent
inclusive START/first-AR/final-injection/compute-START/result event boundaries.
Local XSim 2022.1 is not target Vivado/Vitis 2020.2 acceptance.

Next work unit: versioned public A17 kernel, register capture and counters,
followed by trained-model public-port regression. Target packaging and physical
HBM[0..3] mapping remain separate evidence steps performed in the established
user-controlled target workflow.
