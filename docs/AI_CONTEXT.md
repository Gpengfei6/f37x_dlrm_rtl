# FPGA DLRM Project AI Context

This file is the repository entry point for AI assistants. It summarizes the
current engineering state; it does not replace `AGENTS.md`, the fixed-point
contract, source code, or stage evidence.

## 1. Project Overview

This repository develops a synthesizable SystemVerilog FPGA accelerator for
Deep Learning Recommendation Model (DLRM) inference. The implemented research
path combines a runtime-configurable fixed-point dense engine, Bottom MLP,
feature interaction, Top MLP, host control, and stage-level observability. The
Stage 2N-A15.4 proves the same complete local inference through a
versioned public AXI4-Lite plus `m_axi_gmem` kernel boundary after one accepted
A14 v2 lookup engine sequentially supplies all four accepted A13 embedding
slots from canonical fake-memory rows. Current Stage 2N-A15.5 includes the
accepted exact-target XO/xclbin flow and a validator-only Vitis 2020.2
compatibility fix. The fixed-SHA artifact has passed non-rebuilding v2 metadata
and routed-timing revalidation. FPGA programming, Host execution, physical HBM,
board function, and performance remain outside A15.5.

Target environment:

- FPGA: Xilinx Virtex UltraScale+ HBM `xcvu37p-fsvh2892-2L-e`;
- board: Inspur F37X;
- Vitis platform: `inspur_f37x_xdma_201920_3`;
- target kernel clock used by the accepted A13 implementation: 100 MHz;
- hardware implementation language: parameterized SystemVerilog-2012, not HLS.

Main research direction:

1. retain the accepted configurable Bottom–Interaction–Top inference pipeline;
2. integrate four sequential logical embedding lookups without changing the
   accepted A13 arithmetic, START gate, or cycle-counter ABI;
3. establish functional equivalence before considering multiple banks, request
   coalescing, scheduling, or performance claims.

Important distinction: A13 is the accepted integrated DLRM pipeline baseline,
whose embedding lookup is performed by the CPU. A14.7 separately proved one
physical HBM[0] lookup. A15.1 proves the local controller-level data handoff,
A15.2 proves complete Bottom–Interaction–Top execution using one HBM-owned
slot, A15.3 locally proves four sequential HBM-owned slots and the complete
pipeline, and A15.4 exposes that composition at a public kernel boundary. None
of these local A15 results is a physical integrated A15 target.

## 2. AI Reading Order

Read the repository in this order before proposing or making changes:

1. `README.md`
2. `docs/AI_CONTEXT.md`
3. `docs/AI_CHANGE_POLICY.md`
4. `docs/CURRENT_STATE.md`
5. `docs/ARCHITECTURE.md`
6. `docs/STAGE_HISTORY.md`
7. the active-stage document,
   `docs/STAGE2N_A15_5_TARGET_XCLBIN_FINAL_ACCEPTANCE_V1.md`
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

Current stage: **Stage 2N-A15.5 — final target XO/xclbin/timing PASS; physical
HBM, Host, FPGA/board execution, and performance remain unvalidated**.

Stage 2N-A13 remains the accepted and frozen integrated DLRM baseline. A14.5
added the runtime 64-bit table-base ABI, A14.6 completed the accepted link-only
F37X build, and A14.7 completed one protected physical HBM[0] lookup with exact
software-golden agreement. Those stages remain separate evidence boundaries.

A15.1 adds one new versioned wrapper. It instantiates the accepted A14 v2 lookup
and accepted A13 cycle-counter controller without editing either file. Its
minimum ownership and data path are:

- A14 v2 successful 128-bit response -> A13 embedding slot 0;
- Host configuration -> A13 embedding slots 1 through 3;
- Host slot-0 writes -> explicit rejection;
- lookup error -> retained error indication and no slot-0 write;
- pending HBM injection -> retained until A13 configuration ready and given
  priority over Host configuration.

Local Vivado/XSim 2022.1 proves slot-0 injection, exact lane order, preservation
of Host slots 1 through 3, delayed-ready retention, lookup-error and busy guards,
the loaded-mask transition to `4'hF`, Host slot-0 rejection, and preservation of
the A13 cycle-counter ABI. Compile, elaboration, and simulation exit codes are
zero; the accepted log has zero warnings and zero anchored error/fatal records.

A15.2 reuses that wrapper and the accepted A13 deterministic model without any
RTL change. A fake AXI row supplies the same zero slot-0 value as the accepted
sample; the bench then executes Bottom `8->16->8`, Interaction `5x8->18`, and
Top `18->32->16->1`. It observes the real Interaction vector-load handshakes,
matches the independently derived final result 36, and reproduces the accepted
cycle counts `322/100/744/1174` with eight controller-overhead cycles.

A15.3 adds one versioned orchestration wrapper because A15.1 cannot route a
single lookup engine to slots 1 through 3. The unchanged A14 v2 engine reads
canonical rows 37 through 40 sequentially, and each response is retained until
the unchanged A13 configuration port commits it to the corresponding slot.
Local XSim observes exact vectors `[40..47]`, `[48..55]`, `[56..63]`, and
`[64..71]`, mask `4'hF`, complete inference result 36, and unchanged
`322/100/744/1174` A13 cycle counts. Error, busy/repeated-request,
ready-retention, Host-write rejection, START gate, and ABI checks all pass.

A15.4 adds a new versioned public top without modifying A15.3. It preserves the
accepted A13 register map, adds only `0x300` A15 control/status and
`0x304/0x308` TABLE_BASE, and exposes one 64-bit-address/128-bit-data
`m_axi_gmem` read master. Public-port XSim observes exact addresses and vectors,
four lookup/AR/R/injection handshakes, mask `0xF`, final result 36, and unchanged
`322/100/744/1174` counters.

A15.5 freezes that accepted top, exposes only the 64-bit TABLE_BASE pointer at
`0x304` as a global-memory kernel argument, and keeps the full A13/A15 control
plane in the raw user-managed AXI-Lite map. It prepares one CU `dlrm_a15_1`,
one `m_axi_gmem -> HBM[0]` mapping, and fail-closed XO/xclbin validators. Local
static and validator fixture tests pass. The versioned v2 xclbin validator
accepts the legal Vitis 2020.2 shell layout only after filtering for exactly one
`IP_KERNEL`, and it still requires the sole connection to reference that kernel
and used `HBM[0]`. Its positive fixture and 12 negative fixtures pass. Bash
syntax remains `NOT_RUN` locally.

The accepted XO SHA256 is
`a88fd4bba7a534f7068cff838448c5ba7f330e5bec27c8c2697525c9dedee019`
and the accepted xclbin SHA256 is
`23ee48c91b3dfb5b68b3372ac49fc6607f203cf01d3b9fcfe04b4ea42be02356`,
with UUID `1b555645-a9e2-4f5e-95af-6ce4adacbc3c`. Target v2 revalidation proves
one kernel, one TABLE_BASE/arg0 connection to used `HBM[0]`, absence of stale
A14 arguments, and 100 MHz routed timing with WNS/TNS `0.000/0.000 ns` and zero
failing endpoints. Fifty-five methodology critical warnings remain recorded;
the validator-only fix required no target rebuild.

Pending beyond local A15.5 preparation:

- broader multi-sample A15 software-golden regression;
- A15 FPGA-device execution or physical HBM validation;
- A15 Host/XRT and complete functional board validation;
- any A15 latency, bandwidth, throughput, power, or performance claim;
- multi-table, multi-bank, burst, cache, coalescing, scheduling, or INT8 work.

See `docs/STAGE2N_A15_5_TARGET_XCLBIN_FINAL_ACCEPTANCE_V1.md` for the accepted
artifact identity and boundary, the compatibility document for the v1-to-v2
root cause, and the preparation V1 document for the frozen package/link
contract. Use the A15.4 document for the underlying local functional result.

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

### Proven by accepted A14.7 evidence

- canonical table reconstruction to exactly 1024 little-endian bytes;
- XRT `2.9.210507` Host build and protected runner controls;
- one protected physical F37X HBM[0] lookup at index 37;
- exact returned lanes `[40,41,42,43,44,45,46,47]`;
- BO release and zero HBM[0] use after cleanup.

### Proven by local A15.1 XSim

- direct A14 v2 128-bit response injection into A13 embedding slot 0;
- exact lane0-at-LSB packing with no reorder;
- preservation of Host-configured slots 1 through 3;
- retained response data across delayed A13 configuration readiness;
- lookup error, busy/repeated request, and Host slot-0 ownership guards;
- loaded mask reaches `4'hF` and the existing A13 START readiness becomes true;
- A13 cycle-counter offsets remain `0x218/0x21C/0x220/0x224`.

### Not proven by A15.1

- public F37X kernel/control-top integration;
- complete A15 prediction software-golden equivalence;
- A15 target synthesis, implementation, link, xclbin, or timing;
- A15 FPGA programming or physical HBM transaction;
- physical HBM bandwidth, latency, throughput, power, or speedup;
- multi-bank mapping, burst optimization, multiple outstanding reads,
  coalescing, caching, prefetching, or scheduling;
- complete FPGA-resident sparse-plus-dense DLRM execution.

### Proven by local A15.2 XSim

- one fake-memory A14 v2 lookup and successful A13 slot-0 injection;
- complete Bottom, Feature Interaction, and Top execution with no bypass;
- observed Interaction vector ordering: Bottom output, HBM slot0, then Host
  slots1 through 3;
- independent accepted-sample golden 36 equals final RTL result 36;
- exact accepted cycle counts Bottom 322, Interaction 100, Top 744, Total 1174;
- final result and counters remain stable under eight cycles of backpressure.

### Not proven by A15.2

- public F37X AXI4-Lite/kernel-top integration;
- target synthesis, implementation, Vitis link, XO/xclbin, or target timing;
- A15 FPGA programming, board execution, or physical HBM transaction;
- multiple samples, multiple HBM-resident embedding slots, tables, or banks;
- A15 latency, bandwidth, throughput, power, speedup, or performance benefit.

### Proven by local A15.3 XSim

- one accepted A14 v2 engine issues four sequential logical lookups through one
  AXI read master;
- canonical rows 37 through 40 are committed bit-exactly to A13 slots 0 through
  3 with lane 0 in bits `[15:0]`;
- the loaded mask transitions `0->1->3->7->F` only after A13 configuration
  handshakes;
- delayed request ready, delayed response, retained injection, lookup error,
  busy/repeated request, and Host-write rejection preserve state;
- complete Bottom, Feature Interaction, and Top execution matches independent
  golden 36;
- logical lookup/AR/R/injection counts are `4/4/4/4`;
- A13 counters remain `322/100/744/1174` and ABI offsets remain
  `0x218/0x21C/0x220/0x224`;
- `xvlog`, `xelab`, and `xsim` exit zero with zero warnings, errors, and fatals.

### Not proven by A15.3

- public F37X AXI4-Lite/kernel-top integration;
- target synthesis, implementation, Vitis link, XO/xclbin, or target timing;
- FPGA programming, board execution, or a physical A15 HBM transaction;
- parallel or multi-bank HBM behavior, bursts, or multiple outstanding reads;
- HBM latency/bandwidth, throughput, power, speedup, or performance benefit;
- broader multi-sample functional coverage.

### Proven by local A15.4 XSim

- a public F37X-style AXI4-Lite plus `m_axi_gmem` boundary around unchanged
  A15.3/A14 v2/A13 modules;
- a disjoint A15 register window at `0x300/0x304/0x308`, with every accepted A13
  address and counter offset preserved;
- TABLE_BASE `0x0000000123456000` and exact row37–40 addresses ending in
  `0x6250/0x6260/0x6270/0x6280`;
- exact vectors `[40..47]`, `[48..55]`, `[56..63]`, `[64..71]`, exactly four
  lookup/AR/R/injection handshakes, and final mask `0xF`;
- complete Bottom–Interaction–Top result 36 and unchanged accepted A13 counters
  `322/100/744/1174`;
- public-port reset/error/busy/delayed-AXI/Host-ownership/ABI checks with
  `xvlog/xelab/xsim` return codes `0/0/0` and zero warning/error/fatal/assertion
  records.

### Not proven by A15.4

- exact-target synthesis, implementation, timing, packaging, or Vitis link;
- XO/xclbin generation or validity;
- physical HBM access or FPGA/F37X execution;
- Host-runtime integration, multiple samples/tables/banks, performance, power,
  latency, bandwidth, throughput, or speedup.

### Proven by A15.5 final target acceptance

- exact accepted A15.4 kernel/source identity and 17-file RTL package closure;
- one TABLE_BASE global pointer at `0x304`, one `m_axi_gmem`, one CU, and one
  `HBM[0]` connectivity contract;
- positive validator fixtures and rejection of wrong identity, width, offset,
  clock, platform, bank, extra master/mapping, and stale A14 arguments.
- exact-target XO build/metadata validation and Vitis 2020.2 link/xclbin;
- fixed xclbin SHA256/UUID and exactly one TABLE_BASE/arg0 connection to used
  `HBM[0]`;
- 100 MHz routed timing with WNS/TNS `0.000/0.000 ns`, zero failing endpoints,
  zero DRC errors/critical warnings, zero methodology errors, and 55 retained
  methodology critical warnings.

### Not proven by A15.5

- Bash syntax in the current Windows environment;
- Host execution, physical A15 HBM access, FPGA/board functional execution, or
  any performance result;
- true all-HBM end-to-end latency: the four sequential lookups occur before the
  accepted 1174-cycle compute-counter interval.

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

The local A13/A14 handoff and one complete deterministic inference using all
four sequential HBM-owned slots are proven through the A15.4 public local
kernel boundary, and A15.5 now accepts the exact-target XO/xclbin/timing
artifact. The next engineering direction is separately authorized A15.6
protected device/Host/physical-HBM functional validation using that frozen
artifact; performance remains a later gate.

First priority is functional equivalence with the software golden model. Multi-table, multi-bank, cache and performance optimization should follow only after this integration path is correct.
