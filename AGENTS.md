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
