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

## D-012 — Approve GATE-1 from retry2 Vivado/XSim evidence

- **Problem:** phase 1 may close only when real compiler, elaborator, simulator,
  bit-comparison, and source-traceability evidence all agree.
- **Adopted:** approve GATE-1 for source commit
  `44a1b256f0e50cef0a54dbe88d23fb4be353e911`.  Retry2 provides Python PASS,
  `xvlog` PASS, 8/8 `xelab` PASS, 8/8 explicit XSim PASS markers, and 24/24
  top-level packed-output matches, with 18 PASS and no failed/skipped tests.
- **Source identity:** the server manifest's `UNKNOWN` Git revision reflects the
  deliberate absence of `.git` from the validation payload.  All 64 manifest
  byte counts and SHA-256 hashes match tracked files in the named commit,
  including all 17 RTL/testbench files.
- **Not adopted:** infer approval from exit codes alone, ignore missing PASS
  markers, treat `UNKNOWN` as sufficient without hash verification, or begin
  phase 2 automatically.
- **Reason:** the complete evidence chain is internally consistent and contains
  no timeout, fatal, error, warning, output mismatch, or source mismatch.
- **Impact:** phase 1 is formally validated.  Parameterized PE-array work remains
  paused until its architecture is reviewed and explicitly authorized.

## D-013 — Approve Scheme B for the first reusable PE engine

- **Status:** conditionally approved for the independent Stage-2A baseline.
- **Problem:** large dense layers cannot fully expand every input multiplier, but
  a serial-only engine gives poor scaling and a two-dimensional array creates an
  immediate weight-bandwidth/routing problem.
- **Adopted:** one output-neuron lane with parameterized input parallelism P,
  P lane-local partial sums, a registered reduction tree, and one existing
  quantize/saturate/ReLU path.  Runtime dimensions reuse the same compile-time
  bounded array for different layers.
- **Not recommended first:** Scheme A as the only performance engine, or Scheme C
  with multiple output-neuron lanes.
- **Reason:** Scheme B has bounded multiplier count, explicit tail handling,
  moderate local-memory width, and a verification hierarchy that scales from
  P=4 to P=32.
- **Impact:** Scheme A remains a configuration/golden baseline;
  Scheme C becomes a later, separately gated enhancement.

## D-014 — Adopt P=16 as the development default

- **Status:** approved for Stage 2A; final paper configuration remains open.
- **Adopted:** default `NUM_PE=16`; mandatory verification at P=4/8/16/32.
  Use P=4 or P=8 for the phase-1 8→4 compatibility configuration.
- **Reason:** P=16 uses 16 logical multipliers, a 128-bit INT8 weight word, and a
  256-bit INT16 activation read.  The model gives 2,688 cycles for 256→128 and
  9,472 for 512→256.  P=32 doubles arithmetic/bandwidth but gives less than 2×
  modeled speedup after registered reduction overhead.
- **Impact:** 250 MHz, DSP mapping, BRAM banking, and F37X percentages remain
  unproven until the four configurations are synthesized on the exact target.

## D-015 — Keep the PE core behind an abstract local weight provider

- **Status:** approved for Stage 2A.
- **Adopted:** the PE requests logical weight chunks and biases over ready/valid
  channels.  Stage 2A uses a test-loadable abstract local provider, not a
  committed whole-layer on-chip cache.  Two complete, `NUM_PE`-banked activation
  buffers use `bank=i%NUM_PE`, `address=i/NUM_PE`; default dimension maxima are
  1024/1024.
- **Not recommended:** expose AXI/HBM addresses, bursts, IDs, or channels inside
  the arithmetic core; use only a FIFO without a reusable layer-result buffer.
- **Reason:** local provider stalls can be verified independently, and a future
  HBM adapter can replace the provider without changing PE arithmetic/control.
- **Impact:** real HBM remains outside the current stage and GATE-4.

## D-016 — Parameterize ACC32 compatibility and ACC48 safe accumulation

- **Status:** approved as a Stage-2 candidate contract; v0 remains unchanged.
- **Evidence:** exact signed endpoint analysis requires 25/30/31/32/33 bits for
  the reviewed 8→4, 64→32, 128→64, 256→128, and 512→256 layers respectively.
  Therefore full-range 512-input INT16×INT8 accumulation can overflow INT32.
- **Adopted capability:** `ACC_WIDTH` defaults to 48 in Stage 2 and is 32 for
  phase-1 compatibility.  Both retain the same eight fractional bits and
  unchanged bias/round/saturate/ReLU order.  Python must model both modes.
- **Not adopted:** modifying `fixed_point_spec_v0.md`, silently replacing INT32
  wrap, or choosing per-layer shifts without trained-model evidence.
- **Reason:** wider internal arithmetic changes outputs only in overflow cases,
  which is still a model-level contract decision.
- **Impact:** RTL must support explicit `compat_int32_wrap` and `wide_int48`
  tests.  ACC48 coverage is a mathematical statement, not a DSP mapping claim;
  trained-model adoption and synthesis remain human decisions.

## D-017 — Separate Stage 2A baseline from Stage 2B neuron overlap

- **Status:** cycle-model boundary retained; its former GATE-2 requirement is
  superseded by D-020.
- **Adopted:** Stage 2A implements one non-overlapped output context with
  `C_layer=O*(K+R+Q)`.  Stage 2B must add two lane-partial-sum banks so MAC work
  for output `o+1` overlaps reduction of output `o`, targeting
  `C_layer~=O*K+R+Q`.
- **Not adopted in Stage 2A:** double-psum banks, multilayer scheduling, or any
  throughput claim based on the overlap formula.
- **Reason:** the baseline provides a bounded verification target; overlap adds
  tagging, capacity, ordering, and control hazards needing separate evidence.
- **Impact:** Stage 2B is an optional later performance optimization and is not
  a prerequisite for the software trace-feasibility work or the final thesis
  contribution path.

## D-018 — Capture runtime layer metadata in an immutable descriptor

- **Status:** approved for Stage 2A.
- **Adopted fields:** `in_dim`, `out_dim`, input/output buffer selectors,
  weight/bias offsets, `output_shift`, and `relu_enable`.
- **Validation:** the engine copies a descriptor on handshake and explicitly
  errors on zero/oversize dimensions, conflicting buffer selection, or an
  unsupported shift without producing partial results.
- **Not adopted:** HBM addresses, AXI IDs/bursts/channels, or physical memory
  topology in the PE descriptor.

## D-019 — Implement Stage 2A as an independent non-overlapped hierarchy

- **Status:** locally implemented; real RTL validation pending.
- **Adopted modules:** signed MAC lane, runtime round/saturate/ReLU, P-bank
  activation buffer, abstract local weight/bias provider, multi-cycle vector dot
  core, and dense-layer job engine.
- **Control:** one output-neuron dot context at a time; elastic result FIFO may
  hold completed indexed results, but there are no double-psum overlap banks.
- **Compatibility:** phase-1 modules and top interface are unchanged.  ACC32
  and shift-four/ReLU provide the compatibility configuration; ACC48 is the
  Stage-2 default.
- **Verification:** every new module has an explicit-marker self-checking
  testbench; local Python passes while RTL compile/elaboration/simulation/lint
  remain SKIPPED because tools are absent.
- **Boundary:** stop for returned Vivado 2020.2/XSim evidence; do not begin
  Stage 2B, full MLP, HBM, AXI, or Vitis Kernel work.

## D-020 — Align the project with the final master's thesis scope

- **Status:** adopted.
- **Primary contribution:** bounded-window duplicate embedding-request
  coalescing and one-read/multi-consumer response broadcast.
- **Secondary contribution:** lightweight post-coalescing HBM-channel-aware
  scheduling, only if traces show imbalance and useful improvement.
- **System optimization:** embedding/MLP double buffering.
- **Foundation:** Stage-2A vector PE is retained but is not the thesis's main
  contribution; Stage 2B is downgraded to an optional later optimization.
- **Evidence rule:** software trace analysis precedes innovation RTL.  Synthetic
  traces validate tools only; real Criteo traces are required for GATE-T1/T2/T3.
- **Boundary:** no Stage-2A edits, complete DLRM RTL, HBM RTL, coalescer RTL, or
  scheduler RTL are authorized by this decision.

## D-021 — Keep software datasets local and evaluation claims qualified

- **Status:** adopted.
- **Data:** deterministic synthetic data is generated locally.  The Criteo
  loader accepts only a user-provided local file/directory and never downloads.
- **Model:** configurable PyTorch DLRM is the intended reference; CPU is required,
  CUDA is optional and explicitly SKIPPED when unavailable.
- **Metrics:** export AUC, LogLoss, throughput, latency percentiles, device and
  stage timing to JSON/CSV, separating end-to-end from forward-only time.
- **Claim boundary:** synthetic random weights/data do not establish meaningful
  AUC, performance baselines, or thesis novelty.

## D-022 — Accept software feasibility tooling without approving trace gates

- **Status:** implemented and locally validated.
- **Model path:** retain the standard configurable PyTorch DLRM as the intended
  software reference.  Because the current runtime has no PyTorch, record both
  CPU and CUDA as SKIPPED and use a deterministic NumPy implementation only as
  an independent structure/tool oracle.
- **Trace path:** use a common logical lookup record for JSONL/CSV/NPY, scan
  1/2/4/8/16/32/64-request windows and wait limits, and compare bounded
  none/count/time/dual/adaptive policies.  Every policy has explicit request,
  wait, unique-tag, fan-out and state bounds.
- **Channel path:** compare simple mapping/FIFO policies with lightweight
  queue/age-aware choices, but label the two-candidate placement and fixed
  service time as abstract feasibility assumptions rather than F37X facts.
- **Evidence:** 12 tests pass and two PyTorch-dependent tests skip.  Synthetic
  balanced/low-duplicate cases show small negative scheduler results, while
  deliberately duplicated/skewed cases show larger modeled value.
- **Decision:** accept the tools and reproducibility evidence; do not approve
  GATE-T1/T2/T3, coalescing RTL, scheduler RTL, or HBM RTL without real local
  Criteo traces, reviewed physical mapping, and a separate human decision.

## D-023 - Bank Stage 2C memories and defer quantization pipelining

- **Status:** adopted for the local Stage 2C synthesis-review branch.
- **Problem:** module-level multidimensional memories did not give reviewable
  synthesis inference, and separate activation write expressions made the
  requested block-RAM style infeasible.  The resulting runtime quantization
  path also fails the initial 100 MHz OOC constraint.
- **Adopted storage:** generate one activation memory per PE bank and select one
  mutually exclusive write tuple before the RAM process.  Generate one weight
  memory per PE with `bank=address%NUM_PE`, `row=address/NUM_PE`, and rotate
  registered bank outputs for arbitrary request alignment.  Keep one-cycle
  elastic responses and scalar-write priority unchanged.
- **Evidence:** local Vivado 2022.1 infers 32 RAMB18 for the two activation
  buffers, 16 RAMB36 for weights, and one RAMB36 for biases.  Six Stage 2A
  benches and the 20-case Stage 2B bench pass.  Synthesis reports no errors,
  critical warnings, or latches.
- **Timing decision:** record, but do not repair, the 100 MHz failure in this
  change.  WNS is -2.460 ns and the 32-level worst path is runtime quantization
  into activation BRAM write data.  Adding a register would change latency and
  coordinated controller behavior, so it requires a separate review.
- **Boundary:** these Artix-7 OOC results are not F37X or Vivado 2020.2 evidence;
  no target timing/resource/board claim is approved.

## D-024 - Pipeline runtime quantization and preserve Stage 2C memories

- **Status:** adopted for the local Stage 2D timing-review branch.
- **Quantization:** use a two-entry elastic pipeline split after magnitude
  rounding. Preserve signed shift, round-away-from-zero, saturation, ReLU,
  result index/last/tag, and ping-pong ownership.
- **Commit rule:** advance the dense output index and assert `job_done` only
  when the quantized value is atomically accepted by both result FIFO and the
  selected activation buffer. Permit same-edge consume/refill and clear all
  pipeline valid state on reset.
- **Additional timing:** register each MAC DSP product and add one explicit
  vector-dot drain cycle before reduction. Keep the accumulator in fabric and
  keep the default design at 21 DSP. Register per-lane provider validity so a
  RAM read is not gated by the long range-comparison path.
- **Latency:** add two clocks per output for quantization and one clock per
  output for MAC drain; an unstalled serial dense layer therefore adds exactly
  `3*out_dim` clocks relative to Stage 2C.
- **Evidence:** local Vivado 2022.1 Stage 2A XSim passes 6/6; Stage 2B passes
  `valid=11 invalid=9 total=20`; all three Python suites pass. Artix-7 OOC at
  10.000 ns reports WNS +0.758 ns, TNS 0, 0 failing endpoints, 0 latches, and
  4,550 LUT / 1,946 FF / 17 RAMB36 / 32 RAMB18 / 21 DSP.
- **Boundary:** this does not prove Vivado 2020.2, implemented F37X timing,
  `.xclbin` generation, or board execution. No false path, relaxed clock, RAM
  demotion, dimension reduction, or expected-output change is adopted.

## D-025 - Accept the authenticated Vivado 2020.2 Stage 2E reproduction

- **Status:** adopted; exact-source target-version reproduction passes.
- **Tool identity:** returned evidence identifies
  `/opt/Xilinx/Vivado/2020.2/bin/vivado`, Vivado v2020.2 SW Build 3064766,
  branch `work/stage2e-vivado2020-repro`, and source head `fff6bd8`.
- **Functional evidence:** Phase 1, Stage 2A, and Stage 2B Python pass; all six
  Stage 2A XSim benches pass compile, elaborate, and simulate; Stage 2B passes
  all 20 cases with `valid=11 invalid=9 total=20`.
- **Synthesis evidence:** `xc7a200tfbg484-2` OOC synthesis at 10.000 ns passes
  with 4,550 LUT, 1,946 FF, 17 RAMB36, 32 RAMB18, 21 DSP, WNS +0.758 ns,
  TNS 0, zero failing endpoints, and zero latches. The 16+1+32 RAM mapping is
  preserved.
- **Version comparison:** Vivado 2020.2 and 2022.1 produce identical resources,
  RAM inference, WNS, TNS, and latch count for the reviewed OOC configuration.
- **Log interpretation:** accept only true line-start error records. The Tcl
  source echo containing `run_synth_stage2c: FAIL` is not an execution failure;
  the execution log has zero line-start errors or critical warnings and ends
  with `COMPLETE` and `TIMING_MET`.
- **Source-state qualification:** no evidence shows a tracked server source
  modification, but the server was not completely clean because XSim WDBs and
  tool logs remained untracked.
- **Boundary:** this decision accepts compile, XSim, and post-synthesis OOC
  evidence only. It does not approve implementation, post-route timing,
  F37X/VU37P compilation, `.xclbin` generation, or board execution.
