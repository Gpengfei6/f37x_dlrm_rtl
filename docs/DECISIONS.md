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

## D-038 - Sequence four canonical HBM rows through one engine before target expansion

- **Status:** accepted locally on 2026-08-27 by Stage 2N-A15.3 Vivado/XSim
  2022.1 evidence.
- **Decision:** add a new versioned controller-level wrapper because the
  accepted A15.1 wrapper intentionally fixes HBM ownership to slot 0 and cannot
  express four-slot sequencing without changing its accepted behavior. Reuse
  the accepted A14 v2 lookup engine and A13 cycle-counter pipeline unchanged.
- **Lookup structure:** use one lookup engine, one AXI read master, one
  outstanding transaction, and four sequential logical requests. Canonical
  rows 37, 38, 39, and 40 map in order to embedding slots 0, 1, 2, and 3.
- **Packing:** preserve lane 0 in bits `[15:0]` through lane 7 in bits
  `[127:112]`. The expected row vectors are `[40..47]`, `[48..55]`,
  `[56..63]`, and `[64..71]`; no lane reorder is inserted.
- **Commit rule:** retain each successful 128-bit response until the accepted
  A13 embedding-configuration handshake completes. Only that handshake writes
  the assigned slot and advances the sequence. Host embedding writes are
  consumed and explicitly rejected in this A15.3 path.
- **Failure rule:** an error stops the sequence, does not write or mark the
  failing slot, preserves earlier successful slots, and blocks automatic
  pipeline execution. Busy or repeated requests cannot replace active or
  retained state.
- **Golden:** independently derive the 18-value Interaction vector as
  `[1,2,3,4,5,6,7,8,1608,1896,17964,2184,20748,24556,2472,23532,27852,32172]`.
  The accepted sparse Top configuration still produces final result 36.
- **Result:** local XSim recorded exactly four logical requests, four AXI AR
  handshakes, four AXI R handshakes, and four successful slot injections. The
  mask reached `4'hF`, expected and actual results were both 36, and the
  accepted counters remained Bottom 322, Interaction 100, Top 744, Total 1174.
  `xvlog`, `xelab`, and `xsim` all exited zero with zero warnings and zero
  anchored error/fatal records.
- **Boundary:** this decision accepts only local fake-memory sequential lookup,
  slot injection, error/busy/backpressure behavior, and full-pipeline golden
  agreement. It does not accept a public target top, target build/link,
  XO/xclbin, FPGA or physical-HBM execution, multi-bank parallelism, or any
  performance result.

## D-039 - Add a disjoint public A15 kernel control window before target packaging

- **Status:** accepted locally on 2026-08-27 by Stage 2N-A15.4 Vivado/XSim
  2022.1 evidence.
- **Decision:** add a new versioned public F37X-style top around the unchanged
  A15.3 controller rather than modify the accepted A13, A14 v2, or A15.3 files.
  Preserve the complete A13 AXI4-Lite ABI and expose the accepted lookup through
  one 64-bit-address, 128-bit-data `m_axi_gmem` read master.
- **Control ABI:** add only the disjoint window `0x300` A15 CONTROL/STATUS,
  `0x304` TABLE_BASE low, and `0x308` TABLE_BASE high. Do not copy the conflicting
  standalone A14 control map and do not move A13 counters at
  `0x218/0x21C/0x220/0x224`.
- **Command policy:** one A15 START snapshots TABLE_BASE and accepted pipeline
  configuration, runs the accepted four-row load-all sequence, waits for mask
  `4'hF`, then starts accepted A13. Lookup or pipeline error prevents automatic
  continuation; repeated START cannot replace an active command; CLEAR performs
  explicit recovery.
- **Rows:** keep canonical rows 37–40 fixed. Programmable row registers are not
  required for this deterministic kernel-composition proof and would enlarge
  the ABI without new acceptance value.
- **Result:** public-port fake-memory XSim observed exact addresses and vectors,
  lookup/AR/R/injection counts `4/4/4/4`, loaded mask `0xF`, independent
  golden/actual `36/36`, and A13 counters `322/100/744/1174`. Tool return codes
  were `0/0/0`, with zero warning/error/fatal/assertion-failure records.
- **Boundary:** this decision accepts only local public-interface composition
  and functional behavior. It does not accept target build/link/timing, XO,
  xclbin, physical HBM, Host runtime, FPGA/board execution, multi-bank behavior,
  or any performance claim.

## D-040 - Model only TABLE_BASE as the A15.5 global-memory kernel argument

- **Status:** accepted for local source preparation on 2026-08-28; target
  execution remains `NOT_RUN`.
- **Decision:** package the accepted A15.4 top as a user-managed RTL kernel and
  declare exactly one global-memory argument: 64-bit TABLE_BASE at `0x304`,
  associated with the only `m_axi_gmem` master. Keep every other A13/A15
  control and status register in the existing raw AXI-Lite address space.
- **Reason:** TABLE_BASE is the only software value that must associate a
  pointer with the linker-visible memory port. Turning the full raw register
  map into independent kernel arguments would misrepresent the accepted ABI.
- **Rejected:** the obsolete A14 `LOOKUP_INDEX` and `RESULT0` through `RESULT3`
  argument signature, a second memory master, and multiple HBM mappings.
- **Target contract:** one kernel `dlrm_f37x_rtl_kernel_stage2n_a15_v1`, one CU
  `dlrm_a15_1`, one `dlrm_a15_1.m_axi_gmem:HBM[0]` mapping, exact VU37P part,
  reviewed F37X platform, and requested 100 MHz.
- **Local evidence:** source/metadata static gates and both validators' positive
  and negative fixtures pass. Bash syntax is `NOT_RUN` locally.
- **Boundary:** no target XO, Vitis link, xclbin, routed timing, device, Host,
  board, physical HBM, or performance result is accepted by this decision.

## D-041 - Identify A15.5 compute units by IP_KERNEL type, not total IP-layout count

- **Status:** accepted on 2026-08-28. The validator-only Vitis 2020.2
  compatibility correction passed local fixtures and fixed-SHA target
  revalidation.
- **Problem:** the v1 validator required all `IP_LAYOUT.m_ip_data` entries to
  total one. The user-reported Vitis 2020.2 layout contains one legal
  `IP_KERNEL` plus three DDR4 and 32 HBM shell entries, so the total-list test
  rejected a one-CU xclbin.
- **Decision:** require `m_count` consistency, filter entries whose
  `m_type == IP_KERNEL`, require exactly one exact `kernel:CU`, and require the
  sole connectivity record to reference that kernel index and an in-range,
  used `HBM[0]` memory index. Ignore unrelated shell IP entries.
- **Retained gates:** keep exact kernel/CU/platform/part/clock/config identity,
  TABLE_BASE-only metadata, one connection, one memory master, HBM[0], and
  rejection of stale A14 `LOOKUP_INDEX/RESULT0-3` arguments.
- **Revalidation:** use a non-overwriting v2 runner against the recorded XO and
  xclbin SHA256 values. The runner does not invoke `v++`; a target rebuild is
  not required for this metadata-only correction.
- **Result:** one `IP_KERNEL`, one TABLE_BASE/arg0 connection to used `HBM[0]`,
  and absence of stale A14 arguments are accepted for the fixed-SHA xclbin. No
  target rebuild was required.
- **Boundary:** this decision accepts metadata interpretation only. Physical
  HBM, FPGA/board execution, Host runtime, and performance still require their
  separately authorized gates.

## D-042 - Freeze the A15.5 target artifact before physical A15 validation

- **Status:** accepted on 2026-08-28 from the final target revalidation-v2
  status, metadata JSON, hash manifests, and routed-DCP metrics.
- **Decision:** freeze xclbin SHA256
  `23ee48c91b3dfb5b68b3372ac49fc6607f203cf01d3b9fcfe04b4ea42be02356`
  and UUID `1b555645-a9e2-4f5e-95af-6ce4adacbc3c` as the only A15.6 input
  artifact. Do not rebuild merely to begin device/Host planning.
- **Accepted target result:** exact VU37P/F37X platform, one CU, TABLE_BASE-only
  global argument, one `m_axi_gmem -> HBM[0]` connection, 100 MHz routed timing,
  WNS/TNS `0.000/0.000 ns`, zero failing endpoints, zero DRC errors/critical
  warnings, zero methodology errors, and 55 retained methodology critical
  warnings.
- **Margin rule:** WNS `0.000 ns` means the requested timing gate passes with no
  reported positive setup margin. The worst path is in the platform static PCIe
  hierarchy and does not establish an independent kernel timing margin.
- **Performance rule:** the accepted Bottom/Interaction/Top/Total counters
  `322/100/744/1174` exclude the four sequential HBM lookups. Do not report
  1174 cycles as all-HBM end-to-end latency. A later boundary must span all four
  lookups plus Bottom, Interaction, and Top.
- **Next gate:** A15.6 requires separate explicit yes/no device authorization
  before programming, Host/XRT, physical HBM[0], four-slot injection, or board
  execution.
- **Boundary:** A15.5 does not accept FPGA programming, Host execution, physical
  HBM correctness, board function, latency, bandwidth, throughput, power,
  speedup, or performance.

## D-043 - Use trained-model slot sensitivity for A15.6 functional validation

- **Status:** accepted for local preparation on 2026-08-28; target Host/device
  execution remains `NOT_RUN`.
- **Problem:** the sparse A15.4 XSim smoke model returns 36 but its Top weights
  use only the first eight Interaction outputs. That result cannot independently
  prove that every physical HBM-derived embedding slot affects the final output.
- **Decision:** reuse the accepted trained-model fixed-point reference and one
  accepted sample. Generate one baseline physical table and four variants in
  which only lane 0 of row 37, 38, 39, or 40 changes by +2048. Preserve the
  existing 64-row, eight-lane, little-endian INT16, 16-byte-row layout and the
  A15.4 fixed row-to-slot mapping.
- **Golden contract:** baseline final result is `-393`; the slot0, slot1, slot2,
  and slot3 sensitivity results are `-392`, `-93`, `-689`, and `-519`.
  All four differ from the baseline and are pairwise distinct.
- **Protection rule:** consume only the frozen A15.5 xclbin SHA256
  `23ee48c91b3dfb5b68b3372ac49fc6607f203cf01d3b9fcfe04b4ea42be02356`
  and UUID `1b555645-a9e2-4f5e-95af-6ce4adacbc3c`. Require explicit device/BDF,
  firewall, CU, owner, HBM-use, artifact-identity, and literal-`yes` gates before
  any separately authorized device operation. Never reset or globally clean.
- **Local evidence:** deterministic asset generation, frozen-source checks,
  positive evidence assembly/validation, and eight negative tamper/malformed
  fixtures pass. Bash syntax and target XRT Host compilation are `NOT_RUN` in
  the Windows preparation environment.
- **Performance boundary:** functional preparation does not establish HBM
  latency, bandwidth, throughput, power, speedup, or all-HBM end-to-end timing.
  The accepted 1174-cycle compute counter excludes the four HBM lookups.
- **Next gate:** a separately authorized user-controlled target execution must
  run all five cases, verify exact results and cleanup, and return a complete
  evidence package before A15.6 board acceptance can be considered.

## D-044 - Separate A15.6 target preflight from protected board execution

- **Status:** accepted for local source preparation on 2026-08-31. At this
  decision point the target preflight had not yet run; D-045 records the later
  completed protected-board acceptance.
- **Decision:** add one versioned target-preflight entry that validates Git,
  the XRT 2020.2 Host build, the already-built fixed-SHA xclbin and HBM[0]
  metadata, deterministic golden assets, the frozen ABI, and the protected
  runner. Keep device discovery/programming/Host execution in the later
  protected board runner.
- **Target repository:** fast-forward the existing
  `/home/chaosuan/gpf/gpf_f37x_dlrm/f37x_dlrm_rtl_stage2n_a15_5_buildonly`
  repository from a verified Git bundle. Preserve all untracked build/results/
  logs/.ipcache outputs and the accepted xclbin.
- **Safety rule:** the preflight may not query or open an FPGA, allocate a BO,
  execute the Host, program/reset a device, invoke `v++` or Vivado, or rebuild
  XO/xclbin. It records `FPGA_DEVICE_ACCESS=NONE` and all board states as
  `NOT_RUN`/`NOT_VALIDATED`.
- **Reason:** compiler/artifact/golden readiness should fail before any separate
  board authorization or device-changing action. A preflight PASS is not a
  physical-HBM or board PASS.
- **Local evidence:** Python syntax and static validation of the preflight,
  legacy XRT API/build convention, exact ABI, five-case golden contract,
  fixed-artifact gates, and prohibited-command absence pass. Bash syntax and
  the target preflight itself remain `NOT_RUN` on Windows.
- **Historical next gate:** transfer, fast-forward-only import and device-free
  preflight preceded separately authorized protected execution. That gate is
  complete; use D-045 for the accepted state.

## D-045 - Freeze A15.6 as the physical single-bank sequential baseline

- **Status:** accepted from returned real-board evidence on 2026-08-31.
- **Decision:** freeze the A15.6 architecture consisting of one physical
  `HBM[0]` bank, one AXI read master and four sequential logical lookups as the
  functional board baseline before latency instrumentation or multi-bank
  parallelization.
- **Artifact identity:** retain A15.4 RTL SHA256
  `c3da5be63d4cf195df124e572887b6aa96a464522883c6cdc95c4bd56ff4e8a1`
  and A15.5 xclbin SHA256
  `23ee48c91b3dfb5b68b3372ac49fc6607f203cf01d3b9fcfe04b4ea42be02356`,
  UUID `1b555645-a9e2-4f5e-95af-6ce4adacbc3c`, kernel
  `dlrm_f37x_rtl_kernel_stage2n_a15_v1` and CU `dlrm_a15_1`.
- **Functional evidence:** on device index 2/BDF `0000:9b:00.1`, a 4096-byte
  BO in `HBM[0]` at valid physical address zero supplied all four embedding
  slots. The five expected/actual results match exactly; every loaded mask is
  `0xF`, every compute-counter set is `322/100/744/1174`, and cleanup passes.
- **Safety:** the prior resident design was idle and was replaced only after
  explicit allowlist checks and literal user confirmation. FPGA reset was not
  run and no other device was accessed.
- **Evidence:** archive SHA256
  `e903865a26153c5121ab84fe9f5735faa73df4bd73522cf079d1c9d0ae4a0c18`;
  board JSON SHA256
  `a6d228b78ff1889ccb7a532e22997a6f6f669a024f802e0798271c625b7fe7da`;
  imported JSON passes the existing offline evidence validator.
- **Performance boundary:** `1174` cycles covers the accepted compute interval
  only. It excludes the four HBM lookups, Host orchestration and BO transfer.
  A15.6 makes no latency, bandwidth, throughput, speedup, power or performance
  claim.
- **Next gate:** A16 should first define lookup and complete-inference timing,
  measure the sequential baseline and then evaluate multi-bank/parallel lookup
  against the frozen A15.6 function and golden results.

## D-046 - Instrument latency decomposition before parallel HBM changes

- **Status:** accepted for local A16.1 XSim on 2026-08-31; physical timing is
  `NOT_VALIDATED`.
- **Decision:** preserve every accepted A13 counter and the frozen A15.4 kernel,
  and add a new versioned A16 top with two read-only 32-bit saturating counters.
  Address `0x30C` measures first AXI read-address handshake through successful
  fourth-slot injection; address `0x310` measures accepted A15 START through
  first final-result visibility.
- **Counting semantics:** an accepted start edge is cycle 1, the terminal edge
  is included, overflow saturates at all ones, reset clears the counters, and a
  completed value is retained until the next accepted START. Result retirement,
  DONE/ERROR clearing and readback do not clear either counter.
- **Compatibility:** the existing A13 Bottom, Interaction, Top and compute-Total
  counters at `0x218`, `0x21C`, `0x220` and `0x224` retain their original
  meanings. The accepted A15.4 RTL SHA256 and A15.5 xclbin remain unchanged.
- **Local evidence:** two complete Vivado/XSim 2022.1 invocations pass. Each
  invocation executes two identical no-reset runs with lookup `73`, compute
  Total `1174`, FPGA end-to-end `1285` and pipeline/control overhead `38`
  cycles, satisfying `1285 = 73 + 1174 + 38` exactly.
- **Reason:** a separately observable lookup interval and complete FPGA interval
  are required before evaluating any future multi-bank or parallel-lookup
  design. Redefining the accepted compute Total or using Host wall-clock timing
  would destroy the comparison boundary.
- **Evidence boundary:** the `73`-cycle interval is generated by the local
  fake-AXI memory model and is not physical HBM latency. A16.1 makes no latency-
  improvement, bandwidth, throughput, speedup, power or performance claim.
- **Next gate:** A16.2 requires separate authorization before any target build,
  physical measurement or board operation.

## D-047 - Establish the real F37X sequential-HBM latency baseline before any multi-bank comparison

- **Status:** accepted for local A16.2 preparation on 2026-08-31; target build,
  link and physical latency are `NOT_RUN`/`NOT_VALIDATED`.
- **Decision:** before any multi-HBM-bank speedup comparison, first establish a
  real F37X sequential-latency baseline using the accepted A16.1 counters
  (`0x30C` HBM_LOOKUP_CYCLES, `0x310` FPGA_END_TO_END_CYCLES) through a reviewed
  target build and protected board run. A16.2 prepares this flow locally and
  claims nothing beyond local preparation.
- **Target identity:** kernel `dlrm_f37x_rtl_kernel_stage2n_a16_v1`, CU
  `dlrm_a16_1`, `s_axi_control` plus exactly one 64-bit-address/128-bit-data
  `m_axi_gmem` master, `dlrm_a16_1.m_axi_gmem:HBM[0]`, part
  `xcvu37p-fsvh2892-2L-e`, platform `inspur_f37x_xdma_201920_3`, 100 MHz.
- **Metadata boundary:** only `TABLE_BASE` (`0x304`, size 8, `void*`,
  addressQualifier 1, `m_axi_gmem`) is a Vitis kernel argument; `0x30C`/`0x310`
  are custom AXI4-Lite registers; the obsolete A14 `LOOKUP_INDEX`/`RESULT0..3`
  signature is rejected. The xclbin validator filters `m_type == IP_KERNEL`
  rather than requiring a single total IP-layout entry (Vitis 2020.2 xclbins
  contain shell/platform IPs), and requires one connection with `arg_index==0`
  to used `HBM[0]`.
- **Host accounting:** per case, `PIPELINE_OVERHEAD_CYCLES =
  FPGA_END_TO_END_CYCLES - HBM_LOOKUP_CYCLES - COMPUTE_TOTAL_CYCLES`; the Host
  verifies `end_to_end >= lookup + compute` before subtraction and computes in
  signed 64-bit so an invalid result cannot underflow to a huge unsigned value.
- **Protection:** the board runner requires explicit target index/BDF/render/
  xclbin/SHA/UUID, never defaults to historical device 2/`9b`/`renderD129`,
  checks firewall/render/HBM[0]/identity, requires an allowlist when the
  resident UUID differs, and requires a literal `yes` authorization before
  programming; it never resets the FPGA.
- **Reason:** the accepted 1174-cycle compute interval and the XSim 73/1285
  values are not physical HBM or end-to-end latency. Any later multi-bank or
  parallel design must be compared against an equivalently instrumented real
  sequential target baseline, not a fake-AXI value.
- **Evidence boundary:** A16.2 local preparation proves only local source/ABI/
  protection gates and validator self-tests. It does not prove XO/xclbin
  validity, target timing, physical HBM behavior, FPGA or board execution, Host
  runtime behavior, bandwidth, latency, throughput, power, energy, speedup or
  any performance improvement.
- **Next gate:** separate authorization for the target XO build, link, Host
  build and protected board run; then acceptance review of returned evidence.

## D-048 - Reconcile inclusive latency intervals and require raw evidence before A16.2 acceptance

- **Status:** source reconciliation accepted on 2026-08-31; its raw-evidence
  gate was subsequently satisfied by D-049.
- **Reported result at this decision point:** the user reported target
  XO/link/timing and protected
  five-case board PASS with lookup/compute/e2e/residual values
  `112/1174/1289/3`. The compact original status/log/metadata/post-route files
  are not present in this checkout, so the report is not yet promoted to an
  accepted physical baseline.
- **Interval algebra:** with `S` accepted A15 START, `A` first AR handshake,
  `D` fourth-slot injection, `C` accepted compute START and `F` first result
  visibility, the inclusive counters are `F-S+1`, `D-A+1` and `F-C+1`.
  Therefore the Host residual is `(A-S)+(C-D)-1`; it is not an independently
  instrumented pipeline stage.
- **Reconciliation:** A16.1 XSim deliberately places AXI-Lite status/mask
  reads, a four-edge ARREADY stall and repeated-START/error handling before its
  first AR handshake. Those cycles increase XSim end-to-end but not lookup.
  The target Host does not reproduce that testbench-only stress sequence, while
  the real shell/interconnect/HBM service lies inside the lookup interval. Thus
  lookup `+39`, residual `-35`, compute `0` and e2e `+4` are consistent; no
  counter semantic bug is identified.
- **Terminology:** retain the emitted `PIPELINE_OVERHEAD_CYCLES` marker for ABI
  compatibility, but describe it in analysis as an accounting residual.
- **Evidence gate:** use the non-overwriting local importer and offline
  validator; import only compact original evidence, never XO/xclbin/DCP or
  build trees. Until it passes, `READY_FOR_A16_3_ARCHITECTURE=NO`.
- **Performance boundary:** the reported physical cycle values are not a
  bandwidth, throughput, speedup, power, energy or performance claim.

## D-049 - Accept A16.2 as the physical sequential-latency comparison baseline

- **Status:** accepted on 2026-08-31 after compact raw-evidence import and
  offline validation.
- **Decision:** accept the exact A16 target build, requested 100 MHz timing gate,
  protected five-case F37X run, and lookup/compute/complete-FPGA/residual values
  `112/1174/1289/3` as the sequential comparison baseline under the frozen A16.1
  event definitions.
- **Artifact identity:** XO SHA256 `ea0fe950339ada07eaacd181c495dcb1f07251ed20e7d1cef44479bc36cec94a`;
  xclbin SHA256 `5f0d6fefab1549d2e1969df3d8775409bbfac33cb46d07e7abde99abdf04b8b4`;
  UUID `f18571de-4a43-46bd-8ab9-a89dd4b11f8e`; kernel/CU
  `dlrm_f37x_rtl_kernel_stage2n_a16_v1:dlrm_a16_1`; one
  `m_axi_gmem -> HBM[0]` connection.
- **Evidence:** 30 compact raw files were imported without XO/xclbin/DCP or
  build trees. The SHA256 manifest contains 31 validated entries under
  `docs/evidence/stage2n_a16_2/final_acceptance_v1/`; the marker parser uses
  fail-closed last-occurrence semantics for progressive runner logs.
- **Timing and function:** WNS/TNS `0.000/0.000 ns`, zero failing endpoints;
  all five expected results `-393/-392/-93/-689/-519`, mask `0xF`, counters,
  cleanup and protected-runner safety markers pass.
- **Evidence boundary:** this accepts the observed sequential physical lookup
  and complete-FPGA intervals for the fixed workload. It does not accept a
  bandwidth, throughput, latency-improvement, speedup, power, energy or general
  performance claim.
- **Next gate:** A16.3 remains not started and requires a separate architecture
  boundary and explicit authorization before multi-bank or parallel work.

## D-050 - Use independent four-port gather before ordered A13 injection

- **Status:** accepted as the Stage 2N-A17.1 local architecture on 2026-09-08.
- **Decision:** instantiate four unchanged A14 v2 single-outstanding read
  engines. Snapshot four bases and indexes on one load handshake, launch each
  request independently, retain all responses, and inject slots 0–3 through the
  unchanged single A13 configuration port only after all four succeed.
- **Failure rule:** a failed group performs no A13 writes. Consume all four
  engine responses before exposing the retained error; acknowledge the error
  before admitting another group. Missing RLAST is only detected as a
  single-beat protocol fault; this design does not recover an unrestricted
  malformed multi-beat stream.
- **Freshness rule:** each successful group grants exactly one compute START.
  New load acceptance clears that token, so the retained A13 loaded mask cannot
  authorize a stale rerun.
- **Evidence:** local Vivado/XSim 2022.1 passes 73 controller cases and two full
  A13 computations with result 36 and counters 322/100/744/1174. All six tool
  return codes are zero, both warning counts are zero, and frozen executable
  assets match starting HEAD `ec062ba6`.
- **Boundary:** packed local port arrays do not prove four packaged Vitis AXI
  masters or four physical HBM banks. Target build, timing, physical latency,
  throughput, bandwidth, speedup, power and energy remain unvalidated or
  unclaimed.
- **Next:** A17.2/A17.3 later added a separately versioned public four-master
  kernel and public-port XSim regression. Target packaging remains a later
  user-controlled step.

## D-051 - Expose A17.1 through four public AXI masters and regress in XSim

- **Status:** accepted as the Stage 2N-A17.2/A17.3 local public-kernel baseline
  on 2026-09-08.
- **Decision:** add a versioned public top
  `dlrm_f37x_rtl_kernel_stage2n_a17_v1` with `s_axi_control` plus four
  independent 64-bit/128-bit read masters `m_axi_gmem0..3`. Preserve the A13
  map through `0x224`, A15 control at `0x300`, port-0 base at `0x304/0x308`,
  A16 counters at `0x30C/0x310`, and add bases 1–3 at `0x318/0x31C`,
  `0x320/0x324` and `0x328/0x32C`. Instantiate the unchanged A17.1 integration
  rather than the sequential A15 controller.
- **Regression:** local Vivado/XSim 2022.1 compile, elaboration and public-port
  simulation pass. Coverage includes simultaneous four-port `ARVALID`, R order
  2/0/3/1, an independent channel stall, `RRESP` error drain plus CLEAR, and a
  no-reset START/DONE restart. Result 36 and A13 counters 322/100/744/1174 are
  preserved.
- **Boundary:** four public AXI ports are a packaging prerequisite, not four
  physical HBM banks. Target build, xclbin, board execution, bandwidth,
  latency, throughput, speedup, power and energy remain unvalidated or
  unclaimed.
- **Next:** user-controlled A17 target packaging/link remains unauthorized
  until A17.5 source preparation. Do not enter A18 from A17.3 XSim evidence.

## D-052 - Record an identity four-bank mapping before A17 packaging

- **Status:** accepted as the Stage 2N-A17.4 local mapping proposal on
  2026-09-08.
- **Decision:** keep A16.2 as `dlrm_a16_1.m_axi_gmem -> HBM[0]`. Treat A17
  public masters `m_axi_gmem0..3` as currently unmapped. Propose one future CU
  `dlrm_a17_1` with `gmemi -> HBM[i]` and four Host BOs whose paddrs program
  BASE0–BASE3 through the frozen AXI-Lite map. Runtime remains user-managed
  `xclRegWrite`; future XO metadata still needs four `TABLE_BASE*` pointer
  arguments for `v++`.
- **Evidence:** local source audit, imported A16.2 CONNECTIVITY/MEM_TOPOLOGY
  dumps, and `scripts/check/check_stage2n_a17_4_hbm_mapping_prep_v1.py`
  `A17_4_MAPPING_PREP_CHECK=PASS`.
- **Boundary:** this is not an XO, xclbin, physical four-bank result, or
  performance claim. No live `config/stage2n_a17*.cfg` is added in A17.4.
- **Next:** see D-053 for the A17.5A packaging audit. Live `config/`, Host,
  and board work remain later stages.

## D-053 - Keep A17 connectivity out of live Vitis config until packaging exists

- **Status:** accepted as Stage 2N-A17.5A local packaging audit on 2026-09-08.
- **Decision:** document the accepted A16.2 XO/`package_xo`/`v++ --link` path
  without executing it. Store
  `analysis/stage2n_a17_5/connectivity_a17_multibank_proposal.cfg` with
  `PROPOSAL ONLY / NOT FOR v++ / UNVALIDATED`. Proposed CU `dlrm_a17_1` maps
  `m_axi_gmemi` to `HBM[i]`. Host BO0–BO3 to BASE0–BASE3 remains AXI-Lite
  `xclRegWrite` documentation only.
- **Not adopted:** copying the proposal into `config/`, writing an A17 package
  Tcl in this stage, modifying Host, or claiming multi-bank acceleration.
- **Evidence:** `docs/STAGE2N_A17_5A_TARGET_PACKAGING_AUDIT_V1.md` and
  `scripts/check/check_stage2n_a17_5a_packaging_prep_v1.py`
  `A17_5A_PACKAGING_PREP_CHECK=PASS`.
- **Next:** see D-054 for A17.5B physical-validation preparation. A17.5C
  remains unauthorized.

## D-054 - Prepare four-BO Host/evidence structure without opening a device

- **Status:** accepted as Stage 2N-A17.5B local physical-validation
  preparation on 2026-09-08.
- **Decision:** keep the A16.2 Host as the single-BO baseline. Document the
  future A17 chain BO handle → mem/group index → HBM tag → paddr → BASE
  readback for BO0–BO3. Store unpopulated evidence templates under
  `docs/evidence/stage2n_a17_5/`. Do not implement Host, do not forge
  mapping or latency values, and do not claim acceleration.
- **Evidence:** `docs/STAGE2N_A17_5B_PHYSICAL_VALIDATION_PREP_V1.md`,
  `docs/STAGE2N_A17_5B_HOST_VALIDATION_PREP_V1.md`, and
  `scripts/check/check_stage2n_a17_5b_physical_prep_v1.py`
  `A17_5B_PHYSICAL_PREP_CHECK=PASS`.
- **Next:** see D-055. Physical A17.5C execution remains unauthorized.

## D-055 - Keep A17.5C behind an explicit execution gate

- **Status:** accepted as Stage 2N-A17.5C checklist-only preparation on
  2026-09-08.
- **Decision:** write build, runtime, mapping, and success criteria before any
  target run. Physical multi-bank validation may be announced only when xclbin,
  device, BO mapping, kernel run, and latency measurement are all PASS on
  user-returned evidence. Latency not decreasing, or compute remaining the
  bottleneck, does not by itself prove a mapping failure.
- **Not adopted:** adding A17 Host/runners, live `config/`, `v++`, XRT, or
  board access in this stage.
- **Evidence:** `docs/STAGE2N_A17_5C_EXECUTION_GATE_V1.md`,
  `analysis/stage2n_a17_5/a17_5c_risk_register.md`, and
  `scripts/check/check_stage2n_a17_5c_execution_gate_v1.py`
  `A17_5C_EXECUTION_GATE_CHECK=PASS`.
- **Next:** A17 implementation is paused. See D-056. Do not expand A17.5C.

## D-056 - Pause A17 implementation and freeze the evaluation plan

- **Status:** accepted on 2026-09-08.
- **Decision:** stop adding A17 RTL, Host, live `config/`, checkers, or
  packaging scripts until an authorized F37X run is requested. Record the
  paper experiment design in `docs/STAGE2N_A17_EVALUATION_PLAN_V1.md` with
  empty A17 physical Results cells. GPT’s A17.6 physical-validation name is
  the pending board comparison, not a local PASS.
- **Allowed claim:** multi-bank-capable architecture and verification
  framework versus A16.2. **Forbidden claim:** multi-bank HBM acceleration.
- **Next:** see D-057 (V1 draft) and D-058 (V2 methodology rewrite). A17.6
  remains unauthorized.

## D-057 - Draft the A17 paper section without claiming acceleration

- **Status:** accepted on 2026-09-08.
- **Decision:** write `docs/STAGE2N_A17_PAPER_CHAPTER_MULTIBANK_LOOKUP_V1.md`
  covering motivation, design, RTL structure, layered verification,
  limitations, and the compute-bound discussion that motivates future A18
  storage–compute co-design. Do not implement A18. Do not start A17.6.
- **Claim boundary:** A16.2 is the completed physical baseline. A17.1–A17.5C
  complete the local architecture and verification framework. A17.6 physical
  four-bank validation waits authorization.
- **Next:** see D-058 for the thesis-style V2 rewrite. A17.6 remains
  unauthorized.

## D-058 - Rewrite the A17 chapter as a methodology section

- **Status:** accepted on 2026-09-08.
- **Decision:** keep V1 as the engineering-summary source and write
  `docs/STAGE2N_A17_PAPER_CHAPTER_MULTIBANK_LOOKUP_V2.md` as a thesis-style
  methodology chapter. Convert motivation into a research question, design
  into memory-side scalability (not “four AXI ports”), RTL into A13+A14+A17
  layering, verification into an evidence hierarchy, limitations into an
  explicit end-to-end compute bound, and discussion into bottleneck
  migration toward future storage–compute co-design.
- **Correction:** D-060 records that the V1 path was later overwritten and
  is no longer an untouched engineering record. V2 remains an independent
  file. The first engineering draft was recovered only as a snapshot.
- **Unchanged:** A16.2 `112/1174/1289`; no RTL, Host, config, or evidence
  edits; no A17.6 or A18 implementation.
- **Next:** see D-059 then D-060.

## D-059 - Review A16.2 + A17 as a paper outline, not a new experiment

- **Status:** accepted on 2026-09-08.
- **Decision:** write `docs/STAGE2N_A17_PAPER_INTEGRATION_REVIEW_V1.md`.
  Map A16.2 to Method 3.1 / Results 4.1, A17 V2 to Method 3.2–3.5, and the
  evaluation plan to empty Results 4.3–4.4. Keep the paper claim as a
  multi-bank-capable architecture and verification framework. Do not
  implement A17.6 or A18, and do not invent Related Work gaps.
- **Finding:** Method *chapter* is writable; method *effectiveness* is not
  fully hardware-verified. Related Work is missing; 4.3–4.4 wait for A17.6.
- **Next:** see D-060. The first V3 request is executed there.

## D-060 - Tighten claims, restore file identity, write V3 as writing-only

- **Status:** accepted on 2026-09-08.
- **Decision:** apply the five review constraints. (1) Move ≈1.07× / ≈1.10×
  to Discussion / analytical bounds; do not call this observed bottleneck
  migration. (2) “Complete Method” means the chapter can be written, not
  that A17 is fully verified; XSim sample 36 does not replace A16.2’s five
  board cases. (3) Forbid measured four-bank operation and speedup; allow
  describing a multi-bank-capable design. (4) Record that the V1 path was
  overwritten; V2 is an independent file; restore the first engineering
  draft only as
  `docs/STAGE2N_A17_PAPER_CHAPTER_MULTIBANK_LOOKUP_V1_ENGINEERING_SNAPSHOT.md`.
  (5) Separate literature gap from A17.6 hardware gap.
- **V3:** `docs/STAGE2N_A17_PAPER_CHAPTER_MULTIBANK_LOOKUP_V3.md` is writing
  integration only. It is not experiment or evidence closure.
- **Next:** literature review can start without F37X. Commit remains
  deferred unless the user asks. A17.6 waits authorization.


## D-061 — Resume engineering with the A17.6 executable target-build handoff

- Date: 2026-09-09. User asked to defer patents and advance engineering.
- Scope: new A17.6 package Tcl, four-bank config, manifest, executable Python
  XO/link entry point and artifact contract regression. No accepted RTL/Host/
  model/evidence edits, no commit, no server or device access.
- Replace proposal-only packaging with actual build files. First user-controlled
  action is XO-only, followed by metadata review and then link-only. Exact
  target results remain NOT_RUN; four-BO Host is the following increment.
- Preserve A16.2 112/1174/1289/3 and reuse its frozen post-route report helper.
  A17 adds setup/hold/pulse and actual kernel-clock checks on those reports.
- Transfer a self-contained source ZIP with SHA256 manifest; unrelated dirty
  writing files do not require a commit or replacement of the accepted checkout.
- Mapping intent or link metadata never proves physical HBM execution or speedup.

## D-062 - Break the A17 START/load LUT loop without waiving bitstream DRC

- **Status:** local RTL fix after user-returned A17.6 link 003 on 2026-09-09.
- **Observation:** `a17_6_link_003` completed synth/opt/place/route and failed
  `write_bitstream` with LUTLP-1. The named net was A13
  `mlp_act_load_valid`; the loop also included `u_hbm_lookup/fresh_group`.
- **Decision:** do not set `ALLOW_COMBINATORIAL_LOOPS`. Do not edit A13/A14/A16
  or the A17 public kernel file. In
  `dlrm_hbm_pipeline_integration_stage2n_a17_v1.sv` only: (1) share one
  registered idle/fresh-group gate between START valid and ready, matching A15
  so valid does not AND A13 ready; (2) register `compute_idle` before gating
  lookup `load_valid` and `load_all_req_ready`.
- **Stale artifacts:** target XO `a17_6_xo_001` (SHA `1bd10d1f…`) and link
  directories 001–003 must not be reused.
- **Follow-up:** user-returned `a17_6_xo_002` / `a17_6_link_004` closed this
  bitstream gap. See D-063.

## D-063 - Accept A17.6 xo_002 / link_004 as target build PASS only

- **Status:** accepted as user-returned target XO and link evidence on
  2026-09-09. Not a board or performance result.
- **Identities:** XO SHA `15ded79f…`; xclbin SHA `b8d20349…`; UUID
  `622c839f-55f4-47c1-92e9-95ee5595ffa4`; kernel
  `dlrm_f37x_rtl_kernel_stage2n_a17_v1`; CU `dlrm_a17_1`; arguments 0–3 to
  memory indices 0–3 / `HBM[0..3]` by tag; part `xcvu37p-fsvh2892-2L-e`;
  platform `inspur_f37x_xdma_201920_3`; requested 100 MHz; actual kernel clock
  `clk_out1_pfm_top_clkwiz_kernel_0` 10 ns; WNS/TNS 0.000; failing endpoints 0;
  DRC/methodology errors 0; methodology critical warnings 55 retained.
- **Not accepted:** programming, XRT Host, physical four-bank reads, latency,
  bandwidth, throughput, speedup, power, or any comparison with A16.2 112/1174/1289/3
  as a multi-bank acceleration result.
- **Next:** a separately authorized four-BO Host and protected board run. Do
  not use the A16 single-BO Host on this xclbin.

## D-064 - Four-BO Host is prepare-only; lock A16.2 goldens, not XSim 36

- Date: 2026-09-09. User authorized local four-BO Host implementation and
  split “development complete” from “allow program”.
- Board goldens are locked from accepted A15.6 assets and the A16.2 host.log:
  `-393,-392,-93,-689,-519`. Local XSim result 36 is rejected as a board
  golden. Five functional cases, four fixed rows 37–40.
- Host parses CONNECTIVITY/MEM_TOPOLOGY tags rather than copying A16 and
  changing BO count. Each BO is filled, synced, addressed, and released on
  its own. `paddr==0` remains legal.
- A13 `322/100/744/1174` is a regression expectation with printed actuals and
  deltas. A17 lookup/e2e/residual are recorded and are not required to match
  A16.2 `112/1289/3`.
- Default protected action is `prepare`. `execute` requires
  `A17_6_BOARD_EXECUTION_AUTHORIZED=yes`, `A17_6_ALLOW_PROGRAM=yes`, and
  `A17_6_CONFIRM=yes`. This increment does not set those variables.
- Per-BO layout: restore baseline onto all four BOs before every case; slot-i
  sensitivity mutates only BO i. Goldens remain A15.6/A16.2, not XSim 36.
- Methodology warnings require a content diff versus A16.2; equal count 55 is
  not equivalence. The diff is NOT_RUN until the link_004 report is supplied.
- Paper implementation results may cite xo_002/link_004. Physical four-bank
  reads, BO ownership, latency, and speedup stay unwritten. Patent paused.

## D-065 - Pre-board review: compile guidance, START-hold XSim, FSM window

- Date: 2026-09-09. User asked for compile and pre-board review only: no
  program, no Host execution.
- `prepare` plus `A17_6_BUILD_HOST=yes` is file check and `g++` only. The
  build script records compiler exit code, ELF magic, and source/ELF SHA256
  and does not call `xbutil` or open a device. Target compile remains NOT_RUN
  until user logs arrive.
- Local START-hold XSim of the existing A17.1 integration bench is PASS.
  Identifier `before` was renamed because it is a SystemVerilog keyword.
- The `compute_idle_q` lag cycle can still show `load_all_req_ready` at the
  wrapper ports. The public kernel never asserts `load_all_req_valid` then:
  `load_all_req_valid` is `A15_LOAD_REQUEST` only, compute START is
  `A15_PIPE_START` only, and `PIPE_CMD_START` is blocked by
  `command_pending_any`. Proof is that FSM, not Host usage. No RTL change.
- Methodology content review stays NOT_RUN until the link_004 report is
  copied. First board execute waits for GPT review after this package.

## D-066 - Target Host compile PASS; methodology content equivalent to A16.2

- Date: 2026-09-10. User overlayed the Host zip and ran `prepare` plus
  `A17_6_BUILD_HOST=yes` on the existing build-only tree.
- Compile PASS: `COMPILER_EXIT_CODE=0`, ELF 84552 bytes, magic PASS, source
  SHA256 `2ef3a5a6…` matches local, ELF SHA256 `520d78ef…`. Prepare did not
  invoke xbutil, open a device, load an xclbin, or execute the Host.
- Methodology content PASS versus frozen A16.2: 55/55 critical bodies match
  after stripping Vivado constraint-position indices. Zero criticals name
  A17 RTL. Five `clkwiz_kernel` items are platform preexisting. Equal count
  55 was recorded but not used as the pass.
- First board execute still waits for GPT review. Do not program.

## D-067 - Close A17.6 local prep; freeze identities; execute not authorized

- Date: 2026-09-10. GPT accepted the five pre-board checks and closed the
  local prep stage. Do not add document versions or repeat those checks.
- Frozen: Host source SHA256-LF `2ef3a5a6…`, Host ELF `520d78ef…` (84552
  bytes), xo_002 `15ded79f…`, link_004 xclbin `b8d20349…`, UUID
  `622c839f-55f4-47c1-92e9-95ee5595ffa4`. Do not rebuild or replace them.
  Do not change RTL. Do not commit.
- First board execute remains unauthorized. Pre-board PASS does not skip the
  live device identity, occupancy, fingerprint, and UUID checks already in
  the protected entry. Failure stops; no bypass; no automatic reset.
- Authorized first run, when later granted, is four-slot physical function
  only: this xclbin, this ELF, four BO/BASE proofs, five goldens plus
  repeated baseline, actual A13 deltas and A17 lookup/e2e/residual, full
  log and cleanup. No throughput, bandwidth, power, model expansion, or
  acceleration claim. Keep the first failure scene. Latency repeats wait
  for a later evidence review.

## D-068 - Close A17.6 four-slot four-bank physical function as PASS

- Date: 2026-09-10. Closed from the returned log summary of
  `results/stage2n_a17_6/protected_v1/20260910_102244`. Codex did not access
  the server. No new target operations.
- The project moved from “four-way architecture can be built” to “four HBM
  paths actually take part in complete DLRM inference.”
- Support: four independent BOs on `HBM[0..3]`; five goldens match and each
  sensitivity case mutates only its BO; repeated baseline is correct; four
  slots load (`0xF`) and BOs release; A13 measured counts stay
  `322/100/744/1174`.
- Observed this-run board counters `lookup/compute/e2e/residual =
  33/1174/1210/3`. These are measured observations from the function run.
  residual=3 is the counter-interval difference `e2e - lookup - compute`,
  not an independently measured control overhead. Comparable A16.2
  performance acceptance is not done. Do not compute or claim speedup.
  `PERFORMANCE=NOT_CLAIMED`.
- Three layers remain: function PASS; original-evidence archive PASS;
  comparable performance not started.
- This execute programming is `SKIPPED_ALREADY_LOADED`. The banner is an
  allowed-action description and does not prove that program ran.
- Keep the server directory unchanged. Original-evidence archive and
  acceptance are PASS under
  `docs/evidence/stage2n_a17_6/function_pass_v1/`. Execution-artifact
  identity remains `NOT_FULLY_ACCEPTED`. Next: Host ELF identity gate,
  then a locked function re-check. Comparable latency waits. Do not
  overwrite the historical `520d78ef…` freeze. Do not program, reset,
  rebuild, start A18, write a speedup, or commit.

## D-069 - Host ELF identity gap; gate execute before program

- Date: 2026-09-10. Accept the identity investigation. Five-case function
  results stand. `9ba37658…` is the compile record for the successful run,
  not a runtime-verified process hash. Do not promote log archive PASS to
  execution-artifact identity PASS. A later hash of a file on the server
  cannot fabricate the missing pre-exec record.
- Identities: `520d78ef…` is the pre-fix freeze and did not complete the
  four-bank function path. Current Windows Host source is a third state
  and must not impersonate `7073b4d9…`.
- Protected execute now requires explicit
  `A17_6_EXPECTED_HOST_ELF_SHA256` and `A17_6_EXPECTED_HOST_SOURCE_SHA256`.
  Expected SHA, on-disk ELF SHA, and build-record BINARY_SHA256 must
  match before any program. Execute does not rebuild. Logs record path,
  SHA, size, source SHA, and Host exit code.
- Retrieval 2026-09-10: current target ELF/source match `9ba37658…` /
  `7073b4d9…` (`REUSE_CANDIDATE=YES`). Host is not rebuilt. That later
  hash does not reconstruct the missing 102244 pre-exec record.
  `host_build.log` being 0 bytes does not mean compile failure.
  `20260910_100942`: log reports `xbutil program succeeded`; status fields
  also print `FPGA_PROGRAMMING=NOT_RUN`. Record defect; do not call it
  "did not program"; do not re-program to repair the field.
  `A17_6_HOST_START`, `BO0_HANDLE`, and `CASE0_NAME` are absent.
- Identity-gated re-check `20260910_122124`: FUNCTION=PASS;
  EXECUTION_ARTIFACT_IDENTITY=PASS_THIS_RUN_ONLY. Trio logged before Host;
  `HOST_EXIT_CODE=0`; `SKIPPED_ALREADY_LOADED`; no `xbutil program`.
  CASE4 lookup/e2e `55/1232` recorded; goldens and A13 deltas passed.
  Does not backfill 102244.

## D-070 - Close A17.6 function re-check; comparable-latency plan only

- Date: 2026-09-10. Accept `20260910_122124` function, original archive, and
  this-run execution identity. Stop further function re-checks and Host
  identity probes. Keep `20260910_102244` pre-exec gap. Do not require a
  `/proc` hash.
- Lookup is not a single 33-cycle value. CASE4 `55/1174/1232/3` stays in
  the record. Later campaigns must keep distributions. Do not drop that
  sample or change RTL to chase 33.
- Comparable A16.2 vs A17 work is plan-only:
  `docs/STAGE2N_A17_6_COMPARABLE_LATENCY_PLAN_V1.md`. Historical 112 vs
  33/55 is descriptive only. Same-condition repeats (N=11) plus an
  explicit A16 program authorization are required before a comparable
  performance conclusion. Prior `FORCE_NO_PROGRAM` does not cover
  switching to UUID `f18571de-…`.
- A17-only process-restart slice was authorized: 12 existing-Host
  executes, `FORCE_NO_PROGRAM`, UUID `622c839f-…`. Warmup out of summary;
  REPEAT_BASELINE not merged into CASE0. Not steady-state; not a speedup;
  A16 program still unauthorized.

## D-071 - Accept A17 process-restart N=11; Class C still incomplete

- Date: 2026-09-10. Campaign `20260910_141722` is accepted as
  `PASS_PROCESS_RESTART_SLICE`. Originals:
  `docs/evidence/stage2n_a17_6/repeatability_v1/ACCEPTANCE.txt`.
- 1 warmup + 11 measured Host processes; `FORCE_NO_PROGRAM`; no
  `xbutil program`; ELF `9ba37658…` / source `7073b4d9…` / UUID
  `622c839f-…`. All goldens and A13 `1174` matched. Compute min/median/max
  are 1174/1174/1174 on every series.
- Lookup is a distribution. Measured min/median/max:
  CASE0 `33/33/33`, CASE1 `33/33/65`, CASE2 `33/33/52`, CASE3 `33/33/38`,
  CASE4 `33/33/50`, REPEAT_BASELINE `33/33/33`. Keep 37, 38, 50, 52, 65.
  Keep historical 122124 CASE4=55 even though it did not reappear here.
  Do not merge REPEAT_BASELINE into CASE0.
- This slice is not steady-state, not Class C, not an A16/A17 speedup.
  Programming A16 UUID `f18571de-…` still needs a separate user sentence.

## D-072 - Prepare A16.2 same-caliber process-restart; do not program

- Date: 2026-09-10. A17-N11 remains frozen. Prepare A16-N11 on frozen
  artifacts only: ELF `de0abefc…`, source `d2c4036b…`, xclbin `5f0d6fef…`,
  UUID `f18571de-…`. Same warmup + 11 process restarts, CASE0–CASE4 order A.
- Host differences recorded, not patched: A16 has no in-process
  `REPEAT_BASELINE`; log keys omit `_ACTUAL`; one `HBM[0]` BO vs four BOs;
  lookup start A is first AR on one master vs any of four.
- Do not rebuild Host or edit RTL to add a sixth A16 case or to chase 65.
  Do not run A16 Host from the A17 overlay. Program remains unauthorized
  until the user names destination UUID `f18571de-…`.
- After a future A16-N11, evaluate comparability. Not now. No speedup.

## D-073 - A16-N11 protected execute wrapper; user programs once

- Date: 2026-09-10. User named destination UUID
  `f18571de-4a43-46bd-8ab9-a89dd4b11f8e`. The campaign wrapper calls the
  frozen A16 runner
  `scripts/program_and_run_stage2n_a16_2_physical_latency_v1.sh`
  (SHA256 `8370ec2f6128243a5f15e7a83a8c0c432b2cde6bf959504769d71323dc31c3ba`)
  and does not issue `xbutil program` itself. Frozen Host/RTL/xclbin are
  not edited or rebuilt.
- Pre-program checks: execute SHA, Host ELF
  `de0abefc0b4dbadf74dd69e6875db9051a18ab34d8ab1a6a747073cb436d6f1b`,
  source `d2c4036bcaccba702d70fe772a436501568c593dd5b92bc08edb7d7502dafc99`,
  xclbin `5f0d6fefab1549d2e1969df3d8775409bbfac33cb46d07e7abde99abdf04b8b4`,
  and matching Host build-record hashes.
- Allowlisted source image for one switch: UUID
  `622c839f-55f4-47c1-92e9-95ee5595ffa4`, CU
  `dlrm_f37x_rtl_kernel_stage2n_a17_v1:dlrm_a17_1`.
- 1 warmup + 11 measured; CASE0–CASE4 only; no A16 `REPEAT_BASELINE`.
  BO condition: one `HBM[0]` full-image reload. Fail-stop. No reset. No
  extra-run. A17 restore program is outside this authorization.
- Cursor does not SSH. Local gates:
  `scripts/check/check_stage2n_a16_2_repeatability_execute_v1.py`.

## D-074 - A16-N11 accepted; comparability reviewed; no speedup

- Date: 2026-09-10. Campaign `20260910_163902` is accepted as
  `PASS_PROCESS_RESTART_SLICE`. Archive:
  `docs/evidence/stage2n_a16_2/repeatability_v1/ACCEPTANCE.txt`.
- Warmup programmed A17→A16 once; rounds 1–11 skipped program. Goldens
  matched. Compute 1174. Residual 3. No A16 `REPEAT_BASELINE`. Lookup is
  a distribution: CASE0 `112/114/141`, CASE1 `112/112/140`, CASE2
  `112/112/140`, CASE3 `112/132/141`, CASE4 `112/112/138`. Keep tails.
  Historical one-shot all-112 remains Class D, not the whole A16 list.
- Comparability versus A17-N11 `20260910_141722`: same task, same
  process-restart protocol, same compute/residual. Remaining differences:
  sequential vs parallel lookup, one `HBM[0]` full-image reload vs four
  BOs, A16 has no `REPEAT_BASELINE`, lookup start A is one master vs any
  of four. See
  `docs/STAGE2N_A16_A17_PROCESS_RESTART_COMPARABILITY_V1.md`.
- Class C remains incomplete. Do not write an A16/A17 speedup. Do not
  extra-run. A17 restore is not authorized. Board now holds A16 UUID
  `f18571de-4a43-46bd-8ab9-a89dd4b11f8e`.

## D-075 - A18.1 local four-slot runtime indexes; A17 CLEAR kept

- Date: 2026-09-17. Local RTL/XSim only. No commit, XO, xclbin, or board.
- A18 public kernel is generated from
  `rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a17_v1.sv`. Do not reconstruct
  AXI-Lite decode. Leftover
  `rtl/f37x/dlrm_internal_pipeline_axi_lite_decode_stage2n_a18_v1.sv` is
  not instantiated.
- Indexes `0x330-0x33C` reset to 37–40, latch with bases on accepted START.
  Busy index writes are ignored (no PENDING). Busy BASE still raises `4'd1`.
  CLEAR remains A17: legal only DONE→IDLE and ERROR→RECOVER. Mid-sequence
  CLEAR is `4'd3`. OOB index `>= 64` issues no ARVALID.
- Official A17.2 runner stays `NOT_RUN` on this zip tree (frozen `e4ce2ab`
  vs LUTLP working tree). Do not revert zip A17. Current-tree A17
  public-kernel XSim `COMPILE/ELAB/SIM=PASS` is not that runner's PASS.
- A18 Vivado Simulator v2022.1: `COMPILE/ELAB/SIM=PASS`, identity golden 36,
  A13 counters 322/100/744/1174, cases A–H. A 2022.1 result is never a
  2020.2 pass. `PERFORMANCE=NOT_CLAIMED`.

## D-076 - A18.2 local XO/Host preparation; stop before server v++

- Date: 2026-09-17. Local only. No commit, v++, xclbin, or board.
- Package `dlrm_f37x_rtl_kernel_stage2n_a18_v1` / CU `dlrm_a18_1` /
  `m_axi_gmem0..3 -> HBM[0..3]` at 100 MHz. Four `TABLE_BASE` pointer
  arguments only. Lookup indexes stay AXI-Lite MMIO `0x330-0x33C`.
- Host writes those indexes, defaults 37–40, keeps locked goldens
  `-393/-392/-93/-689/-519`, rejects A16/A17 CU names. Non-default indexes
  are refused in this five-case Host.
- Software goldens from frozen A15.6 assets: default 37–40 match those
  locked values; extras such as rows 1–4 → `-61` are not board results.
- `A18_2_LOCAL_PREP_CHECK=PASS`. `A18_2_TARGET_XO=NOT_RUN`. A Windows
  Store `python3` `xo` invocation is not target evidence. Transfer
  `handoff/stage2n_a18_2_build_v1.zip` to a new empty 2020.2 extract,
  then `check` and `xo --confirm-build`. Do not overlay A17.6. Do not
  run the A17 Host against an A18 xclbin.

## D-077 - A18.2 target XO/link accepted; Host/board still closed

- Date: 2026-09-17. User-returned 2020.2 artifacts, locally reviewed.
- XO `a18_2_xo_001` SHA `8d3f920aed2e4349…`. Link `a18_2_link_001`
  xclbin SHA `bbb0fa1f…`, UUID `32a9c911-af15-47fc-90c8-0bfe3894a3ef`.
  CU `dlrm_a18_1`, `HBM[0..3]` by tag, 100 MHz, WNS 0.000. Pointer args
  remain `TABLE_BASE0..3`. Lookup indexes stay MMIO.
- Next user-controlled step is a separately authorized board execute.
  Programming would replace the A16 UUID currently on the card. Do not
  treat Host g++ as physical HBM or a performance result.

## D-078 - A18.2 first board function PASS on default indexes 37–40

- Date: 2026-09-17. User-returned protected execute `20260917_171608`.
- Programmed UUID `32a9c911-af15-47fc-90c8-0bfe3894a3ef` onto index 2 /
  BDF `0000:9b:00.1`. Pre-program UUID was `3a4ebb31-933a-45c2-9ce4-04adce88615c`.
- Five cases plus repeat baseline matched `-393/-392/-93/-689/-519`.
  MMIO indexes 37–40, PIPE_VERSION `0x00024e18`, four BOs on `HBM[0..3]`,
  compute `322/100/744/1174`, lookup 33 / e2e 1210 / overhead 3.
- This does not board non-default indexes. Do not write a speedup versus
  A17.6. `PERFORMANCE=NOT_CLAIMED`.
- Copied originals under
  `docs/evidence/stage2n_a18_2/function_pass_v1/20260917_171608/`
  match the pasted execute log. `A18_2_ORIGINAL_EVIDENCE_ARCHIVE=PASS`.
  `HOST_RUNTIME_PROCESS_HASH=NOT_CLAIMED`.

## D-079 - GitHub snapshot for new windows; A18.3 Host not created yet

- Date: 2026-09-17. User asked to push GitHub with detailed markdown so a
  new model or chat can resume without reconstructing chat history.
- Entry document: `docs/NEW_WINDOW_HANDOFF_V1.md`. Board narrative:
  `docs/STAGE2N_A18_2_BOARD_FUNCTION_ACCEPTANCE_V1.md`.
- A18.3 is local preparation only: extras goldens stay software-only;
  A18.2 Host lock stays; no A18.3 C++ Host **in that snapshot**. Host
  source arrived in D-080. No board.
- Do not `git add .`. Omit patents, extract trees, and the 76 MB
  `post_route_timing_summary.rpt`.
- `PERFORMANCE=NOT_CLAIMED`.

## D-080 - A18.3 index-tuple Host source; board still NOT_RUN

- Date: 2026-09-17. GitHub snapshot `40a36e7540ef170240b1628098377db4f56794ba`
  on `work/stage2n-a16-multibank-parallel` is the user-confirmed remote.
- New Host `host/stage2n_a18_3_index_tuple_host_v1.cpp` programs locked
  tuples `(37,38,39,40)->-393`, `(1,2,3,4)->-61`, `(0,0,0,0)->-60`,
  `(0,63,37,40)->-162`, `(63,62,61,60)->-185` with baseline tables only.
- Do not edit the A18.2 Host. Do not treat this source as board PASS.
  User-returned `A18_3_HOST_XRT_BUILD=PASS`: ELF
  `011a0b8f1630b9cadbba49150f3f28ebfd042cc5c77af840bcc00d27a403187f`,
  source `f516896068f6664060cd392b954795f7fb877bdec66935f3163b8e38694dbaa9`,
  79632 bytes, g++ 4.8.5. `HOST_EXECUTION=NOT_RUN`. `BOARD=NOT_RUN`.
  `PERFORMANCE=NOT_CLAIMED`.

## D-081 - A18.3 five-tuple board execute authorized; logs not yet returned

- Date: 2026-09-17. User sentence: 授权.
- One protected execute of the A18.3 Host on the accepted A18 xclbin
  UUID `32a9c911-af15-47fc-90c8-0bfe3894a3ef`. Baseline table on all
  four BOs. Locked goldens -393/-61/-60/-162/-185.
- If CURRENT_UUID already matches, skip `xbutil program`. Program is
  allowed only of this A18 image when UUID differs. No reset. No
  extra-run. Do not use the A18.2 five-case Host.
- `A18_3_BOARD=NOT_RUN` until originals are copied and reviewed.
  `PERFORMANCE=NOT_CLAIMED`.

## D-082 - A18.3 five-tuple board originals accepted

- Date: 2026-09-17. Copied run `20260917_202130`. Program
  `SKIPPED_ALREADY_LOADED`. Host ELF `011a0b8f…` on xclbin UUID
  `32a9c911-…`. Goldens `-393/-61/-60/-162/-185`. Compute
  `322/100/744/1174`. Lookup 33 / e2e 1210 recorded, not a speedup.
- `A18_3_ORIGINAL_EVIDENCE_ARCHIVE=PASS`.
  `A18_3_BOARD_FUNCTION=PASS_FIVE_LOCKED_TUPLES`.
- Does not prove OOB 64, T>4, extra-run, process hash, or Class C.
  `PERFORMANCE=NOT_CLAIMED`. Do not extra-run. Do not reset.

## D-083 - GitHub snapshot of accepted A18.3 five-tuple board function

- Date: 2026-09-17. User asked to keep uploading git on major changes.
- This snapshot is the A18.3 Host, protected runner, compile originals,
  and board originals `20260917_202130`. Do not `git add .`. Omit
  patents, extract trees, overlay zips, and the 76 MB timing report.
- `PERFORMANCE=NOT_CLAIMED`. Commit `bcd3f86`.

## D-084 - A18.4 local L1 E2/E4/E5 geometry lock

- Date: 2026-09-17. After A18.3 silicon variable-index PASS, lock the
  documented L1 occupancy cells. Stripe T=8 is `[2,2,2,2]`; T=16 is
  `[4,4,4,4]`; forced tables 0/1 on bank 0 is `[3,1,2,2]`.
- E4 is same-row-index on ident stripe, not a co-occurrence mapper.
- `PHYSICAL_HBM=NOT_MODELED`. `PERFORMANCE=NOT_CLAIMED`.

## D-085 - A18.5 local T=8 / B=4 bank mapper

- Date: 2026-09-17. Combinational ident / coacc-split / force-01 mapper.
  Occupancy `[2,2,2,2]`, `[1,2,3,2]`, `[3,1,2,2]`.
- Not instantiated in the boarded A18 kernel. XSim NOT RUN.
- `PERFORMANCE=NOT_CLAIMED`.

## D-086 - A18.6 local T=8 mapped lookup

- Date: 2026-09-17. Mapper is inside a four-engine T=8 lookup controller.
  Frozen A13 slot count remains 4. Boarded A18 kernel unchanged.
- `PERFORMANCE=NOT_CLAIMED`.

## D-087 - A18.3 extra-run runner, no program, no reset

- Date: 2026-09-17. User-executed extra-run of the locked five tuples on
  UUID `32a9c911-…` only. Runner contains no `xbutil program` / reset.
- Board extra-run remains `NOT_RUN` until originals are reviewed.
- Extra-run is not T>4 and not a speedup.

## D-088 - A18.7 local one-line bank cache

- Date: 2026-09-17. One stored index/vector; hit skips AXI AR.
- Not instantiated in the boarded A18 kernel. XSim NOT RUN.
- `PERFORMANCE=NOT_CLAIMED`.

## D-089 - Self-directed next slice after GPT unavailable

- Date: 2026-09-17. User asked for self-answers and execution without
  further questions.
- `NEXT_SLICE=C` as versioned A18.8 (cache in front of T=8 lookup).
- `INTO_KERNEL_DEFINITION=A18.6/A18.8 datapath is enough` until a later
  program grant; do not copy the boarded public kernel.
- `EXTRA_RUN_NOW=no`: Agent cannot SSH; extra-run does not prove T>4;
  do not chase lookup 33.
- `T8_VS_A13=lookup-only this increment`; pooling would change the
  frozen A13 slot contract and is not this slice.
- `CACHE_NEXT=wire into A18.8`; keep one line per bank.
- `SUCCESS_CRITERIA`: Python golden PASS; boarded A18 unwired; no
  program/reset; `PERFORMANCE=NOT_CLAIMED`.

## D-090 - A18.9 four-line cache, pair fold, local 2022.1 XSim

- Date: 2026-09-17. User asked to keep advancing without requests.
- Four-line FIFO cache; warm ident replay AR=0. Pairwise sat-add fold
  is not an A13 golden.
- Local XSim mapper/fold/cache4/folded PASS on Vivado 2022.1 only.
- Extra-run still NOT_RUN. No program. No reset.


