# FPGA DLRM Project AI Context

This file is the repository entry point for AI assistants. It summarizes the
current engineering state; it does not replace `AGENTS.md`, the fixed-point
contract, source code, or stage evidence.

## 1. Project Overview

This repository develops a synthesizable SystemVerilog FPGA accelerator for
Deep Learning Recommendation Model (DLRM) inference. The implemented research
path combines a runtime-configurable fixed-point dense engine, Bottom MLP,
feature interaction, Top MLP, host control, and stage-level observability. The
current Stage 2N-A14 work explores moving embedding-row lookup from the CPU to a
standalone FPGA-side AXI/HBM path.

Target environment:

- FPGA: Xilinx Virtex UltraScale+ HBM `xcvu37p-fsvh2892-2L-e`;
- board: Inspur F37X;
- Vitis platform: `inspur_f37x_xdma_201920_3`;
- target kernel clock used by the accepted A13 implementation: 100 MHz;
- hardware implementation language: parameterized SystemVerilog-2012, not HLS.

Main research direction:

1. retain the accepted configurable Bottom–Interaction–Top inference pipeline;
2. replace CPU-resolved embedding-vector injection with a measured FPGA-side
   embedding lookup path;
3. validate a single HBM bank before considering integration, multiple banks,
   request coalescing, scheduling, or performance claims.

Important distinction: A13 is the accepted integrated DLRM pipeline baseline,
but its embedding lookup is performed by the CPU. A14 currently contains a
standalone lookup prototype and wrapper; it is not connected to the A13
Bottom–Interaction–Top pipeline.

## 2. AI Reading Order

Read the repository in this order before proposing or making changes:

1. `README.md`
2. `docs/AI_CONTEXT.md`
3. `docs/AI_CHANGE_POLICY.md`
4. `docs/CURRENT_STATE.md`
5. `docs/ARCHITECTURE.md`
6. `docs/STAGE_HISTORY.md`
7. the documents for the active stage, currently `docs/STAGE2N_A14_*.md`
8. the exact RTL, testbench, Host, configuration, and script files named by the
   active-stage documents

Also read `AGENTS.md` in full. Its rules are mandatory and cannot be replaced by
this summary.

Historical stages are evidence and context. Do not edit their accepted RTL or
reinterpret an old summary as a current PASS. When documents disagree, prefer:

1. later final-acceptance evidence;
2. retained machine-readable status/log/hash evidence;
3. self-checking testbench behavior and current source;
4. architecture or planning documents;
5. older status summaries.

For example, `docs/STAGE2N_A13_CYCLE_COUNTER_V1.md` records the earlier local
state in which target timing and board work were blocked. The later
`docs/STAGE2N_A13_FINAL_ACCEPTANCE.md` is the authoritative A13 final status.

## 3. Current Stage

Current stage: **Stage 2N-A14 — FPGA-side HBM embedding lookup prototype**.

Stage 2N-A13 is complete and frozen. Its accepted top remains the reference for
the integrated DLRM pipeline. Stage 2N-A14 is intentionally isolated so it can
validate the memory-facing architecture without changing A13.

Completed or present in the current source tree:

- A14 architecture and data-layout freeze;
- deterministic 64-row, 8-lane, signed-INT16 embedding table;
- A14.1 standalone AXI4 read-master lookup RTL;
- single outstanding, one-beat reads with `ARLEN=0`;
- byte-address rule `byte_addr = lookup_index << 4`;
- 128-bit embedding-vector response;
- self-checking lookup XSim record: 64/64 cases PASS;
- Vitis-style standalone kernel wrapper with AXI4-Lite control and logical
  `m_axi_gmem`;
- wrapper XSim record: 14/14 cases, 14 AR and 14 R handshakes PASS;
- XO packaging Tcl, kernel metadata plan, and future `HBM[0]` link
  configuration;
- a documented local Artix-7 proxy packaging result from the former A14
  worktree.

Pending or blocked:

- reproducible XO packaging with the exact VU37P target environment;
- availability of Vitis `v++` and the F37X `.xpfm` platform locally;
- `v++ --link`;
- A14 xclbin generation;
- physical `m_axi_gmem -> HBM[0]` connectivity validation;
- XRT buffer allocation, data transfer, Host execution, and board testing;
- integration of the lookup result into the accepted A13 Feature Interaction
  input path;
- any HBM latency, bandwidth, throughput, or performance-improvement claim.

The generated A14 XO described by historical A14 documents is not tracked in
Git and is not currently present in this main working tree. Treat packaging as
a reproducibility task, not as an available source artifact.

## 4. Hardware Environment

### Local development environment

- OS: Windows;
- local RTL simulator/tool: Vivado/XSim 2022.1, SW Build 3526262;
- known executable root:
  `D:\vivado2022\vivado2022forwins\Vivado\2022.1\bin`;
- the current local environment does not expose `v++`;
- the F37X platform repository variables are not set;
- the local Vivado installation does not contain the exact VU37P part database
  required by the default A14 packaging target.

### Server/target build environment

Historical accepted evidence identifies:

- OS: Linux;
- Vivado 2020.2;
- Vitis 2020.2;
- platform: `inspur_f37x_xdma_201920_3`;
- target: Inspur F37X with `xcvu37p-fsvh2892-2L-e`.

AI agents must not access the server or board. The user performs target builds,
xclbin generation, programming, and board execution and returns evidence.

## 5. Engineering Rules

The full rules are in `AGENTS.md`. The minimum working summary is:

- work locally in this repository only;
- do not use network, remote execution, server access, or board access;
- do not modify accepted A13 RTL;
- do not change the fixed-point contract without an explicit new authorization;
- preserve ready/valid backpressure semantics;
- do not delete historical source, evidence, logs, recovery files, or patent
  materials;
- do not use `git add .`, `git clean`, destructive reset, or bulk replacement
  on the dirty historical working tree;
- do not claim a test passed merely because a tool or script exists;
- do not claim physical HBM behavior, bandwidth, latency, or performance from a
  fake-memory XSim result;
- do not claim an XO, xclbin, target implementation, or board result unless the
  corresponding artifact and evidence are present and reviewed;
- maintain Python 3, C++11, and Vivado/Vitis 2020.2 compatibility.

## 6. Evidence Boundary

### Proven for the accepted A13 baseline

According to `docs/STAGE2N_A13_FINAL_ACCEPTANCE.md`:

- Bottom MLP, Feature Interaction, and Top MLP execute as one internally
  sequenced FPGA pipeline;
- one START triggers the complete internal sequence;
- Bottom and Top time-share the dense engine;
- local XSim cycle-counter regression passed;
- Host XRT build, XO, F37X xclbin, target timing, board programming, and board
  functional validation passed in the user-controlled environment;
- 256/256 FPGA logits, predictions, result indices, result tags, Bottom counts,
  Interaction counts, and cycle-counter checks matched;
- Bottom, Interaction, Top, and Total counters measured 322, 100, 744, and 1174
  cycles at 100 MHz;
- 11.74 microseconds is FPGA-internal START-accepted-to-first-final-result-
  visible latency, not CPU-to-FPGA end-to-end latency.

### Proven for the isolated A14 prototype

- address generation and row alignment for 64 rows;
- ready/valid response retention under backpressure;
- one outstanding, one-beat AXI4 read behavior against a fake memory;
- 64/64 standalone lookup golden comparisons;
- AXI4-Lite register programming and result readback in the wrapper;
- 14/14 wrapper cases with one AR and one R handshake per lookup;
- logical wrapper integration between AXI4-Lite control, the lookup IP, and
  `m_axi_gmem` in XSim.

### Not proven by A14

- physical F37X HBM connectivity or `HBM[0]` access;
- target VU37P packaging or implementation in the current main worktree;
- Vitis link or A14 xclbin generation;
- XRT BO/DMA behavior;
- physical HBM bandwidth, latency, throughput, or speedup;
- multi-bank mapping, burst optimization, multiple outstanding reads,
  coalescing, caching, prefetching, or scheduling;
- complete FPGA-resident sparse-plus-dense DLRM execution;
- integration of A14 lookup output with A13 Feature Interaction.

Use `docs/CURRENT_STATE.md` for the exact current branch, HEAD, blockers, and
next actions.
