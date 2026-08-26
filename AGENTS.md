# Repository working rules

## Scope

- Work locally in this repository only.
- Never use network access, SSH, SCP, SFTP, rsync, remote desktop, remote shells,
  remote execution, or access `172.17.8.254`.
- Never access or modify `/home/chaosuan`, `/opt/Xilinx`, or `/opt/xilinx`.
- Never request credentials or install/upgrade server software, drivers,
  firmware, FPGA platforms, or tools.
- The user alone performs future F37X compile, `.xclbin` generation, and board
  execution.  Do not claim F37X success without user-supplied logs.
- Server commands and validation packages may be generated locally, but Codex
  never executes them.  The target remains one F37X card; do not add multi-card
  behavior.

## Design constraints

- FPGA compute cores use parameterized synthesizable SystemVerilog-2012; no HLS.
- Maintain Python 3, C++11, and Vivado/Vitis 2020.2 compatibility.
- Core RTL must not use `real`, delay-based logic, or vendor algorithm IP.
- Every RTL module needs an independent self-checking testbench and bit-level
  agreement with the Python fixed-point contract.
- Ready/valid interfaces must retain data under backpressure.
- Record latency, throughput, rounding, saturation, and overflow explicitly.
- Prefer small reviewable changes.  Preserve unrelated or existing files.

## Current boundary

GATE-1 is approved and the Stage-2A vector-PE baseline exists but is frozen
until user-provided Vivado 2020.2 logs arrive.  Local software work is authorized
for a configurable DLRM reference, embedding trace extraction, bounded request-
coalescing simulation, and abstract channel scheduling.  This authorization does
not include Stage-2A edits, Stage 2B, multilayer/interaction/full-DLRM RTL,
coalescer/scheduler RTL, AXI/HBM, XRT, or multi-card support.  Synthetic traces
validate tools only; corresponding RTL requires user-supplied real traces and
GATE-T1/T2/T3 review.

## Verification language

- A tool being invokable is not a passing test.
- If a simulator/linter is missing, report the test as not run; never install it.
- Report created/modified files, key diff, commands run, passes, skips, and risk.

## Autonomous workflow and gates

- At the start of work, read this file, `README.md`, the architecture and
  fixed-point specifications, and `docs/CURRENT_STATE.md` when present.
- Select the highest-priority unblocked stage-1 task, make a small change, run
  every locally available test, review the diff, and update state/risk records.
- Record material design decisions in `docs/DECISIONS.md`.
- Do not enter phase 2 until `docs/VALIDATION_GATES.md` records real compiler and
  simulation logs satisfying GATE-1.  Python-only checks never satisfy GATE-1.
- Stop before changing the fixed-point contract, public top-level interface,
  model direction, real HBM mapping, or paper/patent innovation.

## Stage 2N-A14.1 HBM Lookup Prototype Authorization

Purpose:
Allow isolated prototype development for validating FPGA-side embedding lookup architecture.

Authorized:
1. Add new standalone AXI4 read-master RTL prototype:
   `rtl/hbm/dlrm_hbm_embedding_lookup_stage2n_a14_v1.sv`

2. Add independent simulation testbench:
   `tb/tb_dlrm_hbm_embedding_lookup_stage2n_a14_v1.sv`

3. Add A14 RTL design documentation:
   `docs/STAGE2N_A14_HBM_LOOKUP_RTL_DESIGN.md`

Restrictions:
1. Do not modify any Stage 2N-A13 accepted RTL.
2. Do not modify existing kernel top.
3. Do not add Vitis `m_axi` kernel interface.
4. Do not add `connectivity.sp` HBM mapping.
5. Do not generate xclbin.
6. Do not perform board programming.
7. Do not claim physical HBM access validation.

Evidence boundary:
A14.1 only validates:
- address generation logic
- AXI4 read transaction behavior
- embedding vector packing
- simulation golden comparison

It does not validate:
- F37X physical HBM connectivity
- bandwidth
- latency
- performance improvement.

## Stage 2N-A14.3-A2 Kernel Wrapper Simulation Authorization

Purpose:
Allow standalone simulation verification of the A14 Vitis-style kernel wrapper.

Authorized:

1. Add standalone kernel wrapper simulation testbench:

   `tb/tb_dlrm_f37x_rtl_kernel_stage2n_a14_v1.sv`

2. Verify:

   - AXI4-Lite register access
   - START control behavior
   - LOOKUP_INDEX programming
   - lookup engine integration
   - m_axi_gmem read transaction
   - RESULT register readback

Restrictions:

- Do not modify existing A13 RTL.
- Do not modify existing A14.1 lookup RTL.
- Do not generate XO.
- Do not generate xclbin.
- Do not perform Vitis linking.
- Do not perform physical HBM validation.
- Do not make performance claims.

Evidence boundary:

This phase only proves:

- AXI-Lite control
- Kernel wrapper logic
- Lookup IP integration
- Simulation correctness

It does not prove:

- physical HBM connectivity
- FPGA board execution
- bandwidth
- latency improvement

## Stage 2N-A14.5 Runtime Table-Base ABI Authorization

Purpose:
Close the address-ABI gap identified by the exact-target A14 V3 XO metadata
without modifying accepted A13 or historical A14 v1 assets.

Authorized:

1. Add versioned A14 v2 lookup and kernel-wrapper RTL with a 64-bit runtime
   `TABLE_BASE` and `TABLE_BASE + (LOOKUP_INDEX << 4)` addressing.
2. Add independent v2 self-checking testbenches and a local XSim runner.
3. Add a versioned XO package Tcl and an exact-target XO-only metadata runner.
4. Update current-state, architecture, history, decision, and A14.5 design
   documentation with explicit evidence boundaries.

Restrictions:

- Do not modify A13 or A14 v1 RTL, testbenches, scripts, or accepted evidence.
- Do not run Vitis `v++`, generate an xclbin, build/execute an XRT Host, access
  the FPGA, or claim physical HBM behavior in this stage.
- Do not hand-edit generated XO/kernel XML or weaken the 64-bit metadata gate.
- Vivado/XSim and exact-target XO results remain NOT RUN until returned and
  reviewed from the user-controlled environments.

Evidence boundary:

This source-preparation stage can prove only source structure, syntax checks
available locally, and preservation of protected files. Functional XSim and
target XO acceptance require their separate retained logs and status records.

## Stage 2N-A14.6 Exact-Target Link-Only Authorization

Purpose:
Consume the accepted A14.5 exact-target v2 XO in a separately versioned F37X
Vitis hardware-link flow and validate the resulting xclbin metadata and routed
timing without accessing an FPGA device.

Authorized:

1. Add a versioned A14.6 connectivity configuration for exactly one compute
   unit and `m_axi_gmem -> HBM[0]`.
2. Add a non-overwriting link-only runner and offline xclbin metadata validator
   compatible with Vitis/Vivado 2020.2 and Python 3.
3. The user may run that reviewed runner in the established server environment
   after an explicit `yes` confirmation and return its evidence.
4. Update current-state, architecture, history, decision, and A14.6 stage
   documentation with exact evidence boundaries.

Restrictions:

- Do not modify A13 RTL or any A14 v1/v2 RTL, testbench, XO package script, or
  accepted evidence.
- Do not rebuild or silently replace the accepted A14.5 XO inside the link-only
  runner; require its recorded SHA256 before invoking `v++`.
- Do not add or run an XRT Host, open a render node, program/reset an FPGA, or
  perform a physical HBM transaction.
- Do not claim physical `HBM[0]` access, lookup correctness on hardware,
  latency, bandwidth, throughput, power, energy, speedup, or A13 integration.
- Codex does not connect to or execute on the server; the user performs the
  target run and returns evidence for a separate acceptance review.

Evidence boundary:

A successful A14.6 link-only result can prove only that the accepted v2 XO
links for the reviewed F37X platform, produces a non-empty xclbin, records the
requested CU-to-HBM[0] connectivity, targets the VU37P, and meets the frozen
100 MHz routed timing gate. It cannot prove that an XRT allocation, physical
HBM read, returned embedding vector, or board execution works.

## Stage 2N-A15.1 Local HBM-to-Pipeline Integration Authorization

Purpose:
Allow local integration proof on branch
`work/stage2n-a15-hbm-pipeline-integration` without modifying the accepted A13,
A14 v2, or A14.7 assets.

Authorized:

1. Add versioned A15 integration RTL, including as needed:

   - `rtl/pipeline/dlrm_hbm_pipeline_integration_stage2n_a15_v1.sv`
   - `rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a15_v1.sv`

2. Add an independent A15 self-checking testbench, including as needed:

   - `tb/tb_dlrm_hbm_pipeline_integration_stage2n_a15_v1.sv`
   - `tb/tb_dlrm_f37x_rtl_kernel_stage2n_a15_v1.sv`

3. Add local XSim runners:

   - `scripts/run_stage2n_a15_integration_xsim_v1.ps1`
   - `scripts/run_stage2n_a15_integration_xsim_v1.tcl`

4. Add the A15.1 stage document:

   `docs/STAGE2N_A15_1_HBM_PIPELINE_INTEGRATION_V1.md`

5. After reviewable local acceptance evidence exists, update:

   - `docs/CURRENT_STATE.md`
   - `docs/AI_CONTEXT.md`
   - `docs/DECISIONS.md`
   - `docs/STAGE_HISTORY.md`

6. Reuse, but do not directly modify:

   - accepted A13 RTL;
   - accepted A13 cycle-counter RTL;
   - accepted A14 v2 HBM lookup RTL;
   - accepted A14.7 Host, runner, and evidence.

Technical objective:

In local RTL/XSim, use the A14 v2 128-bit HBM embedding lookup result as the
data source for A13 embedding slot 0 while preserving the existing
Host-configured semantics of slots 1 through 3 and preserving the A13 pipeline
and cycle-counter ABIs.

Authorized validation scope:

- local source audit;
- local RTL changes limited to new versioned A15 files;
- local self-checking testbenches;
- local XSim;
- local documentation;
- a local Git commit containing only the reviewed A15.1 files.

Restrictions:

- No network access, Git push, SSH, SCP, server access, or access to
  `/home/chaosuan`.
- No `xbutil`, FPGA device access, xclbin programming, target build, target
  link, or board execution.
- Do not modify accepted A13 RTL, A13 cycle-counter RTL, A14 v2 RTL, or A14.7
  Host, runner, and evidence.
- Do not add multiple HBM banks, multiple tables, caching, INT8 embeddings,
  performance optimization, power testing, GPU comparison, or a model-size
  change.
- Do not claim physical A15 HBM operation, bandwidth, latency, throughput,
  performance improvement, or board validation from local XSim.

Git safety boundary:

- Preserve all historical untracked files.
- Do not run `git clean` or `git reset --hard`.
- Do not use `git add .`.
- Stage only the exact files created or updated for A15.1.

First local acceptance criteria:

- A successful HBM lookup result is injected into embedding slot 0.
- The 128-bit lane order is bit-exact from lane 0 through lane 7.
- Slot 0 loaded state is asserted only after a successful lookup injection.
- Host-configured slots 1 through 3 are unchanged.
- `embedding_loaded_mask` can reach `4'hF`.
- A lookup error does not set slot 0 loaded.
- A repeated or busy lookup does not corrupt existing embedding state.
- The A13 pipeline ABI is unchanged.
- The A13 cycle-counter ABI remains unchanged at `0x218`, `0x21C`, `0x220`,
  and `0x224`.

Evidence boundary:

A15.1 can prove only the local RTL/XSim integration behavior listed above. It
does not re-run A14.7, access physical HBM, validate an A15 target build or
xclbin, prove that all four embeddings come from HBM, or establish any
performance result.
