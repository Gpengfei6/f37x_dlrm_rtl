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

Current stage: **Stage 2N-A14.7 — target XRT build-only PASS; protected physical-HBM board gate is next; Host/device/physical-HBM NOT RUN**.

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
  worktree;
- exact-target V3 packaging evidence showing 128-bit AXI data and 64-bit
  component-side address metadata, but only a 32-bit kernel XML range and no
  global-memory argument in the v1 ABI;
- versioned A14.5 v2 source with a 64-bit `TABLE_BASE`, address rule
  `TABLE_BASE + (LOOKUP_INDEX << 4)`, independent testbenches, and new XSim and
  exact-target XO-only runners;
- a retained first local-XSim failure diagnosis: the standalone TB omitted the
  explicit 32-bit `INDEX_WIDTH` parameter, so Vivado connected its 32-bit
  signals to 6-bit DUT ports and the first response-index comparison saw upper
  `Z` bits. The TB binding and runner failure-status behavior are fixed in
  source;
- corrected local Vivado/XSim 2022.1 acceptance at `d428e8b`: standalone
  lookup 67/67 cases and wrapper 17/17 cases PASS, including three rejected
  requests per bench, high addresses above 4 GiB, table-base readback, exact
  AR/R counts, and zero anchored error/fatal records;
- user-returned exact-target attempt-1 evidence at `de9276e`: Vivado 2020.2
  generated an intact XO with the exact VU37P part; returned XML confirms an
  8-byte `TABLE_BASE` global pointer on `m_axi_gmem`, 128-bit AXI data,
  64-bit component address parameters and AWADDR/ARADDR ports, and a `2^64`
  IP-XACT address space;
- a diagnosed obsolete gate: Vivado 2020.2 retained
  `kernel.xml range=0xFFFFFFFF`, so the old range-only assertion stopped after
  package generation and the old `ERR` trap misclassified the status. A
  versioned cross-layer metadata validator and non-overwriting retry runner
  corrected both problems;
- accepted exact-target corrected retry at tested server HEAD `4096614`:
  Vivado 2020.2 generated a 12,951-byte XO for the exact VU37P part, the
  TABLE_BASE ABI and cross-layer 64-bit address evidence passed, the returned
  source/artifact hashes were retained, and the package log contained seven
  warnings, zero critical warnings, and zero errors.
- A14.6 link-only authorization and architecture freeze: consume only the
  accepted v2 XO, create one `dlrm_a14_1` compute unit, map
  `m_axi_gmem -> HBM[0]`, request 100 MHz, and stop before Host/device access.
- versioned A14.6 configuration, explicit-`yes` non-overwriting link-only
  runner, and offline xclbin/HBM[0] metadata validator; local static and
  synthetic-validator checks pass;
- user-returned A14.6 target evidence at tested HEAD `b44855e`: Vitis 2020.2
  linked the accepted XO into a non-empty F37X xclbin, the single
  `dlrm_a14_1.m_axi_gmem -> HBM[0]` metadata connection passed, and the exact
  VU37P routed design met 100 MHz with WNS/TNS `0.000 ns` and zero failing
  endpoints.

A14.7 local source preparation adds a legacy-HAL Host, canonical 1024-byte
HBM payload builder, target build-only XRT `2.9.210507` API/symbol gate,
protected board runner, and exact 64-line offline evidence validator.
User-returned target diagnostics then proved the payload, XRT symbol gate,
GCC 4.8.5 C++11 compile, and Host link PASS on the F37X after explicitly
defining `LD_LIBRARY_PATH` and `PYTHONPATH`. The versioned runner itself exposed
a nounset incompatibility in `/opt/xilinx/xrt/setup.sh`; a narrow source fix
must be formally rerun before target-build acceptance is frozen. All device
operations remain NOT RUN.

Pending beyond the A14.7 local-source-preparation boundary:

- physical `m_axi_gmem -> HBM[0]` BO/DMA transaction and returned-row validation;
- Host execution and board testing under the protected runner;
- integration of the lookup result into the accepted A13 Feature Interaction
  input path;
- any HBM latency, bandwidth, throughput, or performance-improvement claim.
Generated A14 XO and xclbin files are not tracked in Git. A14.6 consumed the
accepted server-side v2 XO only after its exact SHA256 and cross-layer metadata
passed. A14.5 structural review, local XSim, and exact-target XO-only
packaging/metadata are PASS. A14.6 link, xclbin, linked HBM[0] metadata, and
routed 100 MHz timing are also PASS within the link-only boundary. A14.7 local
Host/runner/payload/validator source preparation is PASS, and a target
compile/link diagnostic also passed under GCC 4.8.5 + XRT `2.9.210507` after an
environment workaround. The versioned build runner still requires a formal
post-fix rerun; Host execution, physical HBM, FPGA programming, board,
performance, and A13-integration claims remain NOT RUN or NOT VALIDATED. See
`docs/STAGE2N_A14_6_LINK_ONLY_ACCEPTANCE.md` and
`docs/STAGE2N_A14_7_HBM_SINGLE_TABLE_HOST_PREPARATION_V1.md`.
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

### Proven by local A14.5 XSim

- versioned 64-bit runtime `TABLE_BASE` RTL and control map;
- `TABLE_BASE + (LOOKUP_INDEX << 4)` addresses above 4 GiB against fake AXI
  memory;
- explicit zero/error rejection of unaligned bases, out-of-range indices, and
  64-bit address overflow without issuing AXI reads;
- AXI-Lite table-base programming/readback and exact AR/R transaction counts.

The first user-controlled XSim attempt failed on a diagnosed testbench
parameter binding before wrapper simulation. The corrected retry at `d428e8b`
passed both testbenches.

### Proven by returned exact-target A14.5 corrected retry

- Vivado 2020.2 generated and validated a 12,951-byte XO with the exact VU37P
  part at tested server HEAD `4096614`;
- `TABLE_BASE` is an 8-byte `addressQualifier=1` global-memory argument on
  `m_axi_gmem` at offset `0x18`;
- packaged AXI bus/model/user address parameters and AWADDR/ARADDR ports are
  64-bit, the IP-XACT address space is `2^64` bytes, and data width is 128;
- `kernel.xml` still records port `range=0xFFFFFFFF`; this observed field is
  retained as descriptive metadata rather than used as the sole width proof;
- standalone and in-XO kernel/component XML hashes match, all five source
  hashes match the tracked inputs, and the retained validator reports
  `RTL_COMPONENT_IPXACT_POINTER_CONSISTENT`;
- the package log has seven reviewed warnings, zero critical warnings, and zero
  errors.

### Proven by returned exact-target A14.6 link-only evidence

- Vitis 2020.2 linked the accepted A14.5 v2 XO into the accepted A14.6 xclbin;
- xclbin SHA256 `9a7ce2518691e1d9a9ef55a0037d5d5345e3781f1e11eb7c2c7d19697144f573` and UUID `6f29087c-9598-4e68-877a-cc4840d078b8` are retained;
- extracted metadata contains exactly one reviewed
  `dlrm_a14_1.m_axi_gmem -> HBM[0]` connection;
- exact-VU37P routing at 100 MHz passed with WNS/TNS `0.000 ns` and zero failing
  endpoints within the accepted link-only timing boundary.

This does not prove a physical HBM transaction.

### Proven by local A14.7 source preparation

- canonical table reconstruction to exactly 1024 little-endian bytes with
  SHA256 `023ad250824def6b538ac40a7f0a9bd457e571136100ab1c1e574769f9061b03` and FNV1a64 `40a53c3698b88325`;
- C++11 source/API-shape compile against a declaration-only legacy XRT stub;
- Bash/Python syntax checks for the build-only gate, protected runner, asset
  builder, and evidence validator;
- valid exact-64-line synthetic evidence acceptance and tampered-result
  rejection.

These are local/offline source checks only.

### Not proven by A14.7

- formal target-build acceptance from the versioned nounset-hardened A14.7 runner under F37X XRT `2.9.210507`;
- Host execution or XRT BO/DMA behavior on the F37X;
- physical F37X HBM[0] access or returned-row correctness;
- A14.7 FPGA programming result, board smoke result, or post-run HBM0 cleanup;
- physical HBM bandwidth, latency, throughput, power, or speedup;
- multi-bank mapping, burst optimization, multiple outstanding reads,
  coalescing, caching, prefetching, or scheduling;
- complete FPGA-resident sparse-plus-dense DLRM execution;
- integration of A14 lookup output with A13 Feature Interaction.

Use `docs/CURRENT_STATE.md` for the exact current branch, HEAD, blockers, and
next actions.

## Stage 2N-A14.7 handoff context

A14.7 is formally accepted.

Final functional proof:
- physical F37X HBM[0] lookup completed successfully;
- lookup index `37`;
- returned INT16 lanes `[40,41,42,43,44,45,46,47]`;
- exact software-golden match;
- BO released after lookup;
- HBM[0] returned to `0 Byte / 0 BO`;
- DMA activity was observed;
- no FPGA reset or automatic rollback occurred.

Successful functional board run:
- timestamp: `20260826_163749`
- tested HEAD: `74301a458ef8f6ad7d59dafc80ff30bbae9961d3`
- evidence SHA256: `644155ffc1c4e40456a52a2a8ca3a84765b1ce685b9d377138bdd25b6871d2d2`
- log SHA256: `cecce17484def1645938b14df8f9b1744e13bf67ea9e4af3ab3ab25dbef54ca5`

Final source/protection baseline:
- HEAD: `70179f66c6fab8a28c2305c024bec3fa43f9c508`
- Host binary SHA256: `f5bfbd50562fcf31a45105a32f7edb414fc4886d007c8ab588f8032c3afc0946`
- runner SHA256: `03838a0e0a3d85f8a0df622efa35c3a81cf69f58a56bc07792ec16965e48e47e`
- final guard log SHA256: `9c7db499b84444d278c3be195439fa0984b144cb4586930112f2a2ba7755e368`

Important failure history:
the first protected board attempt found that the formal Host executable had become a 0-byte executable file while the old build-status SHA remained present. That attempt successfully loaded the accepted A14.6 xclbin but did not execute the real C++ Host/HBM path. Commit `70179f6` added runtime Host non-empty and SHA identity enforcement.

Do not repeat A14.7 physical lookup merely to reconfirm it.

The next engineering direction is A13/A14 integration:
`physical HBM embedding -> Interaction -> Top MLP -> final result`.

First priority is functional equivalence with the software golden model. Multi-table, multi-bank, cache and performance optimization should follow only after this integration path is correct.
