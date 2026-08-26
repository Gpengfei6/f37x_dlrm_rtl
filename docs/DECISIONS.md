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

## D-026 - Adopt a strict Artix-7 OOC post-route feasibility flow

- **Status:** local Vivado 2022.1 precheck adopted; exact Vivado 2020.2
  reproduction pending.
- **Frozen input:** keep the Stage 2D RTL, `mlp_sequence_controller`,
  `xc7a200tfbg484-2`, the 10.000 ns Stage 2C XDC, and the Stage 2C/2D synthesis
  source order. No design, testbench, constraint, or expected-value change is
  part of this decision.
- **Flow:** run synthesis, opt, place, physical opt, and route in a clean
  repository-contained work directory. Emit four checkpoints, eight core
  post-route report classes plus a power report, and a machine-readable status
  file. Do not commit generated checkpoints, logs, or reports.
- **Acceptance:** require route completion, 0 unrouted nets, non-negative setup
  WNS and hold WHS, 0 setup/hold failing endpoints, 0 DRC errors, the complete
  artifact set, and 0 line-start Vivado errors. Source echoes are not errors.
- **Local evidence:** Vivado 2022.1 build 3526262 passes twice with setup WNS
  +0.597 ns/TNS 0, hold WHS +0.098 ns/THS 0, 4,320 LUT, 1,946 FF, 17 RAMB36,
  32 RAMB18, 21 DSP, 0 latches, 0 unrouted nets, and 0 anchored errors or
  critical warnings.
- **Review evidence:** retain 44 DRC warnings and 593 methodology warnings.
  No congestion window exceeds level 5. OOC missing-pin, I/O-delay, board
  voltage, and part-pin warnings are boundaries, not reasons to invent board
  constraints.
- **Boundary:** this decision does not close Vivado 2020.2 post-route
  reproduction and does not approve board-level implementation, F37X/VU37P,
  platform integration, `.xclbin`, board timing, execution, or measured power.

## D-027 - Write A14 AXI master width metadata explicitly

- **Status:** adopted for the Stage 2N-A14 V3 packaging retry; target execution
  remains pending.
- **Problem:** Vivado 2020.2 successfully packaged the exact VU37P XO but wrote
  the inferred `m_axi_gmem` defaults `dataWidth=32` and
  `range=0xFFFFFFFF`. The frozen RTL ports are 128-bit data and 64-bit address.
- **Adopted:** packaging V2 creates or updates the AXI bus parameters
  `DATA_WIDTH=128` and `ADDR_WIDTH=64` before saving the IP and invoking
  `package_xo`. The target runner requires both values in generated XML.
- **Not adopted:** changing A14 RTL widths, weakening the metadata validator,
  manually editing generated XML after packaging, or allowing `v++` to proceed
  with inconsistent metadata.
- **Reason:** AMD documents that `package_xo` derives kernel XML from packaged
  IP metadata, that the data-width default is 32, and that Vitis RTL-kernel AXI
  masters require 64-bit address support. Explicit bus parameters keep the
  metadata aligned with the already reviewed RTL interface.
- **Impact:** no functional RTL, register, clock, HBM mapping, A13, Host, or
  fixed-point behavior changes. The V3 target retry must still prove the XO,
  link, xclbin, HBM[0] link metadata, and routed timing; physical HBM and board
  behavior remain unvalidated.

## D-028 - Add a runtime 64-bit A14 table-base ABI before physical HBM work

- **Status:** accepted for the isolated A14.5 prototype. Corrected local XSim is
  PASS at `d428e8b`; the corrected exact-target XO-only gate is PASS at tested
  server HEAD `4096614` with retained logs and hashes.
- **Problem:** the V3 target retry proved that RTL ports, AXI bus parameters,
  model parameters, and the IP-XACT master address space are 64-bit, while
  `package_xo` still emitted `range=0xFFFFFFFF`. The generated kernel metadata
  contained no global-memory argument associated with `m_axi_gmem`, and the v1
  register map had no way to provide a future XRT BO/table allocation address.
- **Adopted:** retain A14 v1 unchanged and add v2 RTL with one 64-bit
  `TABLE_BASE` at AXI-Lite offset `0x18`. Capture the base on START and issue
  `TABLE_BASE + (LOOKUP_INDEX << 4)`. Package the 64-bit register with
  `ASSOCIATED_BUSIF=m_axi_gmem`, requiring `addressQualifier=1` in generated
  kernel XML.
- **Safety behavior:** reject unaligned bases and 64-bit address overflow with
  a deterministic zero-vector error response and no AXI read.
- **Not adopted:** hand-edit or re-zip generated XO metadata, accept a truly
  32-bit RTL/component address path, assume an XRT BO is allocated at address
  zero, overwrite A14 v1, modify A13, or proceed directly to v++/board work.
- **Reason:** physical-bank selection and table-allocation address are distinct.
  `connectivity.sp` selects HBM[0], while the runtime base selects the actual
  table location within the connected address space.
- **Impact:** the A14 control ABI gains two 32-bit words at `0x18/0x1C`; the
  existing result offsets `0x20..0x2C`, INT16 row layout, one-beat protocol,
  A13 design, and fixed-point behavior remain unchanged. Physical HBM, Host,
  xclbin, timing, and performance remain unvalidated.

## D-029 - Validate A14.5 AXI address width across RTL and IP-XACT layers

- **Status:** adopted and accepted. The versioned, non-overwriting exact-target
  retry passed at tested server HEAD `4096614`.
- **Observed evidence:** Vivado 2020.2 generated an intact exact-VU37P A14.5
  XO. Its `kernel.xml` reports `m_axi_gmem dataWidth=128`, an 8-byte `void*`
  TABLE_BASE with `addressQualifier=1`, and `range=0xFFFFFFFF`. Its packaged
  component simultaneously reports AXI `ADDR_WIDTH=64`,
  `C_M_AXI_GMEM_ADDR_WIDTH=64`, `AWADDR[63:0]`, `ARADDR[63:0]`, and an IP-XACT
  address space of `16777216T` (`2^64` bytes).
- **Interpretation:** the Vivado 2020.2 kernel port `range` field is retained as
  generated metadata but is not a sufficient sole proof of physical AXI
  address width. The more specific source and packaged-component fields prove
  the actual interface width.
- **Adopted gate:** require exact target part, intact XO, identical standalone
  and in-XO XML, 128-bit data, an 8-byte TABLE_BASE global pointer associated
  with `m_axi_gmem`, RTL/component 64-bit address ports and parameters, and a
  `2^64` IP-XACT address space. Accept only the observed kernel range values
  `0xFFFFFFFF` or `0xFFFFFFFFFFFFFFFF`, record the exact value, and reject any
  inconsistent RTL/component evidence.
- **Runner correction:** temporarily disable the Bash `ERR` trap only while
  capturing the Vivado pipeline return code. A packaging failure must be
  recorded as `FAIL`, not left as `BLOCKED_NOT_RUN`.
- **Not adopted:** editing generated XML/XO, overwriting attempt-1 outputs,
  treating the range field as proof of physical HBM, relaxing data/address
  interface checks, running `v++`, or accessing the device.
- **Accepted evidence:** target part used, 12,951-byte XO, matching standalone
  and in-XO XML hashes, TABLE_BASE ABI PASS, 128-bit data, 64-bit
  RTL/component address ports and parameters, `2^64` IP-XACT address space,
  five matching source hashes, seven reviewed warnings, zero critical warnings,
  and zero errors.
- **Impact:** no RTL, A13, A14 v1, fixed-point, register-map, or protocol change.
  The retry writes to new `xo_v3` and `target_xo_v2` roots. The XO-only gate is
  closed; xclbin, Host, physical HBM, board behavior, and performance remain
  unvalidated.

## D-030 - Accept the A14.5 exact-target XO-only gate without promoting board claims

- **Status:** accepted on 2026-08-25.
- **Evidence:** user-returned status, Vivado package log, standalone and in-XO
  XML, cross-layer validator output, source/artifact SHA256 manifests, and tool
  version record for tested server HEAD `4096614`.
- **Decision:** record `A14_5_TARGET_XO_BUILD=PASS`,
  `A14_5_TABLE_BASE_ABI=PASS`, and
  `A14_5_AXI_ADDR_WIDTH_EVIDENCE=PASS`. Retain
  `KERNEL_XML_PORT_RANGE=0xFFFFFFFF` exactly and interpret it only together with
  the consistent 64-bit RTL/component/IP-XACT/global-pointer evidence.
- **Warning disposition:** seven package warnings are retained and classified;
  final clock/reset associations and IP integrity are present, CPU emulation is
  outside scope, and no critical warning or error occurred.
- **Not adopted:** claiming Vitis link, xclbin, routed timing, HBM[0], XRT BO,
  Host, FPGA programming, physical HBM data, performance, A13 integration, or
  complete DLRM from XO metadata.
- **Impact:** A14.5 is closed at its authorized XO-only boundary. Any link,
  Host, device, or physical-memory work requires a separately reviewed stage.

## D-031 - Separate A14.6 link-only validation from Host and physical HBM work

- **Status:** adopted and source-prepared as the next isolated engineering
  stage. Target execution was NOT RUN at this decision point; D-032 records
  the later accepted target result.
- **Input:** consume only the accepted 12,951-byte A14.5 v2 XO with SHA256
  `7c05895b4ef7f3b3e1169d722f88a4ea5103ae9d5cb5283fd0372e7bc3e43dea`.
  The link runner must fail before `v++` if this identity or the cross-layer
  TABLE_BASE/64-bit address metadata does not match.
- **Connectivity:** instantiate one `dlrm_a14_1` CU from
  `dlrm_f37x_rtl_kernel_stage2n_a14_v2`, map only its `m_axi_gmem` port to
  `HBM[0]`, and request 100 MHz on `inspur_f37x_xdma_201920_3`.
- **Flow:** use new A14.6 build/result roots, generate a hardware xclbin, retain
  xclbin sections and hashes, and extract exact-VU37P routed timing evidence.
  Never rebuild the input XO or overwrite earlier A14 artifacts in this flow.
- **Reason:** the previous target runner is hard-coded to A14 v1 and would not
  validate the accepted runtime TABLE_BASE ABI. A dedicated v2 link-only flow
  preserves provenance and prevents an old kernel from being mistaken for the
  current design.
- **Boundary:** linked `HBM[0]` metadata is not a physical-memory PASS. No Host,
  XRT buffer, render node, programming/reset, FPGA transaction, lookup result,
  latency, bandwidth, throughput, power, speedup, or A13 integration is
  authorized or accepted by A14.6.
- **Prepared implementation:** the versioned config, explicit-`yes`,
  non-overwriting link runner, and standalone xclbin JSON validator passed
  local syntax/structure and synthetic-metadata tests. This is not a target
  link or xclbin result.

## D-032 - Accept A14.6 at the exact-target link-only boundary

- **Status:** accepted on 2026-08-25 from user-returned target evidence at
  tested server HEAD `b44855ed4bc8b469257cb3de80cf530e9d5039b9`.
- **Decision:** record the accepted XO, TABLE_BASE ABI, Vitis hardware link,
  non-empty xclbin, one-CU-to-used-HBM[0] metadata mapping, and exact-VU37P
  100 MHz routed timing as PASS.
- **Artifact identity:** retain input XO SHA256
  `7c05895b4ef7f3b3e1169d722f88a4ea5103ae9d5cb5283fd0372e7bc3e43dea`,
  xclbin SHA256
  `9a7ce2518691e1d9a9ef55a0037d5d5345e3781f1e11eb7c2c7d19697144f573`,
  and xclbin UUID `6f29087c-9598-4e68-877a-cc4840d078b8`.
- **Timing disposition:** accept WNS `0.000 ns`, TNS `0.000 ns`, and zero
  failing endpoints against the frozen non-negative-slack gate. Do not claim
  positive timing margin or frequency headroom.
- **Warning disposition:** zero v++ errors/critical warnings, zero routed DRC
  errors/critical warnings, and zero methodology errors passed. Retain 55
  methodology critical warnings (`TIMING-1/3/4/14/27/54`) as
  platform/static-clock constraint debt. Retain the two report-session
  `Board 49-67` messages separately; the custom board repository was absent
  when reopening the routed DCP.
- **Scope:** whole-design resource counts include the static platform shell and
  are not accepted as kernel-only utilization.
- **Not adopted:** physical HBM access, XRT allocation, TABLE_BASE programming,
  Host build/execution, FPGA programming/reset, returned-row correctness,
  board readiness, performance, power, speedup, or A13 integration.
- **Impact:** A14.6 is closed as LINK-ONLY PASS. Any Host/device/physical-HBM
  work requires a separately reviewed and authorized stage.
## D-033 - Separate A14.7 protected physical-HBM single-table validation from broader DLRM integration
- **Status:** adopted for local source preparation on 2026-08-26; target Host
  build and all device/physical-HBM actions remain **NOT RUN** at this decision
  point.
- **Input:** consume only the accepted A14.6 xclbin with SHA256
  `9a7ce2518691e1d9a9ef55a0037d5d5345e3781f1e11eb7c2c7d19697144f573`, UUID `6f29087c-9598-4e68-877a-cc4840d078b8`, one
  `dlrm_f37x_rtl_kernel_stage2n_a14_v2:dlrm_a14_1` CU, and linked HBM[0]
  memory-topology index 0.
- **Target runtime:** retain the previously board-accepted F37X XRT runtime
  `2.9.210507`; A13 final acceptance is the provenance for this target version.
- **Canonical payload:** retain `models/stage2n_a14_embedding_table.json` as the
  source of truth and generate exactly 1024 little-endian bytes with SHA256
  `023ad250824def6b538ac40a7f0a9bd457e571136100ab1c1e574769f9061b03` and FNV1a64 `40a53c3698b88325`.
- **Host:** use the accepted A13-style legacy HAL access model. Allocate one XRT
  BO in HBM[0], obtain `xclBOProperties.paddr`, program both 32-bit halves of
  `TABLE_BASE`, issue exactly one lookup, preserve the first read-to-clear DONE
  word, compare all eight INT16 lanes, and release the BO on success and error
  paths.
- **Safety runner:** lock xbutil index 2, BDF `0000:9b:00.1`, render node
  `/dev/dri/renderD129`, platform, xclbin identity, CU, and an empty HBM[0]
  allocation state. If A14.6 is already loaded, skip programming. A different
  source image is blocked unless its UUID and CU are explicitly allowlisted
  after review. A simple yes/no authorization is required before the first
  write action. Never reset or automatically roll back the FPGA.
- **Evidence:** produce exactly 64 ordered `KEY=VALUE` lines and validate them
  offline. The validator checks xclbin/payload identity, BO paddr to TABLE_BASE
  reconstruction, read-to-clear CONTROL semantics, packed result words, all
  eight signed lanes, BO release, HBM0 zero, and DMA-activity markers. A valid
  synthetic fixture and a tampered-result fixture are mandatory local tests.
- **Not adopted:** unmanaged absolute DMA, assuming device address zero, adding
  a JSON parser to the C++ Host, changing A14 RTL/xclbin, multi-table or batch
  lookup, performance measurement, A13 integration, automatic source
  selection, reset, or rollback.
- **Boundary:** local source/stub/offline-validator PASS does not imply target
  XRT build, Host execution, FPGA programming, physical HBM, returned-row
  hardware correctness, performance, or complete DLRM acceptance. Those claims
  require separately returned target evidence.

## D-034 - Treat XRT 2020.2 vendor setup as nounset-unsafe third-party environment code
- **Status:** adopted after the first A14.7 target build-only attempt on
  2026-08-26; the post-fix formal rerun at `82a6e46` subsequently passed.
- **Observed target behavior:** the tracked build runner starts with
  `set -Eeuo pipefail`, while `/opt/xilinx/xrt/setup.sh` directly expands
  `$LD_LIBRARY_PATH` and `$PYTHONPATH`. On the F37X login shell both variables
  were unset, so sourcing the vendor setup under `set -u` stopped first at line
  37 (`LD_LIBRARY_PATH`) and then at line 39 (`PYTHONPATH`).
- **Diagnostic proof:** with both variables explicitly defined as empty only for
  the diagnostic subprocess, the same tracked Host source passed canonical
  payload validation, the required XRT symbol probe, GCC 4.8.5 `gnu++11`
  compile/link, and produced an x86-64 ELF Host binary. Binary SHA256 was
  `af743c77ec380fc31e2cf79a07e328f7831eb16d0e4f8459846dd99f3e6b532a`;
  payload SHA256 remained
  `023ad250824def6b538ac40a7f0a9bd457e571136100ab1c1e574769f9061b03`.
- **Adopted fix:** temporarily disable Bash `nounset` only while sourcing the
  trusted XRT vendor setup, then immediately restore `set -u`. Keep `errexit`
  and `pipefail` active. Do not hard-code empty runtime library/Python paths as
  project policy.
- **Compiler-warning cleanup:** remove the redundant aggregate initializer on
  `xclBOProperties`; the constructor already zeroes the structure with
  `std::memset` before its first use. This avoids GCC 4.8
  `-Wmissing-field-initializers` noise without changing Host behavior.
- **Boundary:** the diagnostic target build does not authorize or prove Host
  execution, FPGA programming, XRT BO allocation on hardware, physical HBM,
  returned-row correctness, board safety, performance, or A13 integration.
  Target-build acceptance requires one clean rerun of the versioned fixed
  runner with no environment workaround.

## D-035 - Accept A14.7 at the target XRT build-only boundary
- **Status:** accepted on 2026-08-26 from user-returned formal target evidence at
  server HEAD `82a6e4627bcaa0e9c7bab6daf8ca6bcc095d7cc6`.
- **Environment:** F37X Linux target, XRT `2.9.210507`, GCC 4.8.5, `gnu++11`;
  caller `LD_LIBRARY_PATH`, `PYTHONPATH`, and `XILINX_XRT` were explicitly unset.
- **Result:** canonical payload PASS, required XRT symbol/API probe PASS, Host
  compile/link PASS, zero-byte `host_build.log`, and a 44 KiB x86-64 ELF Host
  binary was produced.
- **Decision:** `A14_7_TARGET_XRT_BUILD=PASS` and
  `A14_7_READY_FOR_BOARD=YES`. READY_FOR_BOARD is permission to enter the
  protected board gate, not a board PASS.
- **Still not proven:** Host execution, FPGA programming, device BO allocation,
  TABLE_BASE programming on hardware, physical HBM data movement, returned-row
  correctness, cleanup, performance, or A13 integration.

## Decision — Close A14.7 after accepted physical-HBM proof

Date: 2026-08-26

Decision:
Stage 2N-A14.7 is accepted and closed after one valid physical HBM[0] single-table lookup with exact software-golden agreement.

Rationale:
A14.7 was intended to establish the minimum physical-HBM capability rather than performance, multi-table scaling or full DLRM integration. The accepted run proves the complete path:

`Host -> XRT BO -> physical HBM[0] -> TABLE_BASE -> RTL AXI master -> result registers -> software comparison`

The successful result for lookup index `37` was:

`[40, 41, 42, 43, 44, 45, 46, 47]`

matching the software golden vector exactly.

The first protected physical attempt is retained as an engineering failure record, not as an HBM functional failure. Its runtime Host artifact had been truncated to zero bytes, so the actual C++ physical-HBM Host path did not execute. The runtime guard was therefore hardened to bind execution to a non-empty, SHA256-verified Host ELF.

Final functional evidence and final protection baseline are deliberately separated:
- functional board-tested HEAD: `74301a4`
- final protected source HEAD: `70179f6`

No additional physical lookup was performed solely to retest the hardened guard. The hardened runner was instead executed to the final authorization boundary and intentionally cancelled.

Next decision:
move to physical-HBM embedding integration with the A13 Interaction/Top-MLP pipeline before introducing multi-table or multi-bank scaling.

## D-036 - Integrate one HBM-owned embedding slot before public-top expansion

- **Status:** accepted locally on 2026-08-26 by Stage 2N-A15.1 Vivado/XSim
  2022.1 evidence.
- **Decision:** prove the minimum A14-to-A13 handoff in a new controller-level
  wrapper. A14 v2 owns embedding slot 0; the existing Host path retains slots 1
  through 3. Do not copy or modify the accepted A13 or A14 v2 modules.
- **Packing:** connect the 128-bit A14 response directly. Both sides use lane 0
  in bits `[15:0]` through lane 7 in bits `[127:112]`; lane reordering would add
  logic and violate the audited contract.
- **Elasticity:** retain a successful lookup response until the A13 embedding
  configuration port is ready. Pending HBM injection has arbitration priority
  over Host configuration.
- **Guards:** Host slot-0 writes are explicitly rejected; lookup errors never
  inject data; busy/repeated lookup requests cannot replace active or retained
  state; an error after a valid load preserves slot 0 and its loaded bit.
- **A13 compatibility:** retain the original `embedding_loaded == 4'hF` START
  gate and cycle-counter offsets Bottom `0x218`, Interaction `0x21C`, Top
  `0x220`, and Total `0x224`.
- **Evidence:** local XSim passed all nine behavioral/ABI markers with two AXI AR
  and two AXI R fake-memory handshakes, zero warnings, and zero anchored
  error/fatal records.
- **Boundary:** this decision does not accept a public F37X top, complete A15
  prediction golden, target build/link, xclbin, FPGA execution, physical A15
  HBM access, multi-bank/table behavior, or any performance claim.

## D-037 - Reuse the accepted A13 sample for the first A15 end-to-end proof

- **Status:** accepted locally on 2026-08-26 by Stage 2N-A15.2 Vivado/XSim
  2022.1 evidence.
- **Decision:** do not add an A15 v2 RTL wrapper. The accepted A15.1 v1 wrapper
  already exposes all A13 model/input/configuration, START, result, phase/count,
  counter, and error signals needed for one full inference.
- **Sample:** reuse the accepted A13 `8->16->8`, `5x8->18`,
  `18->32->16->1` deterministic sample. Replace only the source of its all-zero
  slot0 vector with fake AXI row 37; retain Host ownership of zero-valued slots
  1 through 3.
- **Golden:** derive 36 independently from the configured copy/sum network:
  zero embeddings preserve dense values 1 through 8 as the first Interaction
  outputs, and the final Top layer sums them.
- **Consumption proof:** observe the accepted A13 Interaction load handshake so
  final-result agreement is not the sole evidence. Vector0 must be the Bottom
  output, vector1 the HBM-owned slot0, and vectors2 through 4 the Host-owned
  slots.
- **Counter rule:** retain the accepted A13 counter definition and exact sample
  values Bottom 322, Interaction 100, Top 744, Total 1174, with eight ordered-
  controller overhead cycles. Treat them as observability, not performance.
- **Result:** expected and actual final result are both 36; all 11 A15.2 markers
  passed; `xvlog`, `xelab`, and `xsim` exited zero with zero warnings and zero
  anchored error/fatal records.
- **Boundary:** the memory is a local fake AXI model. This decision does not
  accept public F37X top integration, target build/link, XO/xclbin, FPGA access,
  physical A15 HBM, board validation, multi-bank/table work, or performance.
