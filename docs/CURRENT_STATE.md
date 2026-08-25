# Current State

Snapshot date: 2026-08-25

## Repository State

- Repository: `D:\FpgaWork\f37x_dlrm_rtl`
- Branch: `work/stage2n-a13-cycle-counter`
- A14.5 XSim-evidence parent HEAD: `d428e8b34b042bdeb65472c0a6e6d2db65dc9919`
- A14.5 source-preparation commit: `29401e5`
- A14.5 XSim-fix commit: `d428e8b`
- A14 source integration commit: `a19d338`
- Current engineering stage: **Stage 2N-A14.5**
- Accepted and frozen functional baseline: **Stage 2N-A13**

The branch name still refers to A13 even though A14 prototype files are now
present. Do not infer stage status from the branch name alone.

The primary Windows worktree may contain pre-existing untracked recovery,
historical evidence, patent, source, and helper files. Preserve them. Never use
`git clean`, bulk deletion, or `git add .`.

## Completed

### Stage 2N-A13

- Added four 32-bit saturating cycle counters: Bottom, Interaction, Top, Total.
- Preserved the A10 v2 arithmetic, model shape, descriptor semantics, and
  ready/valid behavior.
- Completed local XSim validation, real XRT Host build, XO packaging, F37X
  xclbin generation, target VU37P timing closure, authorized board programming,
  and board functional validation according to the final acceptance record.
- Accepted model shape:
  - Bottom MLP: `8 -> 16 -> 8`;
  - Feature Interaction: five 8-element vectors to 18 outputs;
  - Top MLP: `18 -> 32 -> 16 -> 1`.
- Accepted capacity: 8 descriptors, 2048 weights, 128 biases.
- Accepted implementation parameters include 16 PEs, INT16 activation/result,
  INT8 weight, INT24 bias, and INT48 accumulation.
- A13 is frozen. Embedding lookup remains CPU-side.

### Stage 2N-A14

- Architecture/data-layout freeze for one table and one future HBM bank.
- 64 rows, 8 signed INT16 elements per row, 128 bits/16 bytes per row.
- Deterministic JSON software-golden table committed.
- Standalone AXI4 read-master lookup RTL committed.
- Vitis-style AXI4-Lite plus `m_axi_gmem` wrapper committed.
- Independent self-checking lookup and wrapper testbenches committed.
- XO packaging Tcl and future `m_axi_gmem -> HBM[0]` configuration committed.
- Link architecture and environment-block documentation committed.
- A target-build runner, shortened-CU target configuration, and routed-report
  script are prepared in the current stage and have passed local syntax and
  structural checks.
- The first target-server runner attempt stopped before Vivado because the
  older server Git rejects `git status --porcelain=v1`; its evidence is retained.
- The V2 compatibility entry passed that gate and generated an intact XO with
  the exact VU37P target. Its post-package metadata gate correctly stopped
  before `v++` because Vivado 2020.2 recorded `m_axi_gmem` as 32-bit data and a
  32-bit address range instead of the RTL's 128-bit data and 64-bit address.
- The V3 target retry at commit `cd68a79` generated an intact exact-VU37P XO.
  The generated kernel XML correctly reports 128-bit data, while the packaged
  component reports 64-bit AXI address ports, parameters, and address space.
  Kernel XML nevertheless retains `range=0xFFFFFFFF` because the v1 ABI has no
  global-memory/table-base argument associated with `m_axi_gmem`.

### Stage 2N-A14.5

- Added a versioned A14 v2 lookup and wrapper; A13 and A14 v1 remain unchanged.
- Added a runtime 64-bit `TABLE_BASE` ABI at AXI-Lite offsets `0x18/0x1C`.
- The v2 read address is `TABLE_BASE + (LOOKUP_INDEX << 4)`.
- Unaligned table bases, out-of-range row IDs, and 64-bit address overflow
  return a zero/error response without issuing an AXI read.
- Added independent v2 lookup/wrapper self-checking testbenches, a local XSim
  runner, and an exact-target XO-only package/metadata runner.
- Local structural checks and Bash syntax pass in the Codex environment.
- The first user-controlled Vivado/XSim 2022.1 attempt at `29401e5` compiled
  and elaborated the standalone lookup, then failed its first result-index
  comparison. Vivado reported a 32-bit actual versus 6-bit formal connection
  for both lookup index ports; the unbound DUT default truncated the request
  and left the observed upper response-index bits as `Z`.
- The test-infrastructure fix at `d428e8b` binds `INDEX_WIDTH=32` explicitly
  and makes the runner retain `status.txt` on failures. The corrected local
  Vivado/XSim 2022.1 retry is **PASS**:
  - lookup: 67 cases, 64 valid, 3 rejected, 64 AR and 64 R handshakes;
  - wrapper: 17 cases, 14 valid, 3 rejected, 14 AR and 14 R handshakes;
  - table-base readback, addresses above 4 GiB, unaligned-base guard,
    out-of-range-index guard, and address-overflow guard all passed;
  - both error/fatal counts are zero.
- Exact-target XO v2 packaging remains **NOT RUN**. No v++ link, xclbin, Host,
  FPGA programming, or physical HBM operation is part of this milestone.

## Verification Summary

| Area | Result | Evidence boundary |
|---|---|---|
| A13 local XSim | PASS | Two complete jobs; exact 322/100/744/1174 cycle counts |
| A13 target timing | PASS | 100 MHz VU37P kernel clock, WNS +1.456 ns, TNS 0, zero failing endpoints |
| A13 board function | PASS | User-controlled F37X run; 256/256 exact output and metadata checks |
| A13 cycle counters | PASS | Board counters matched XSim for all 256 samples |
| A14.1 lookup XSim | PASS | 64/64 rows against fake AXI memory |
| A14 wrapper XSim | PASS | 14/14 lookups; 14 AR and 14 R handshakes |
| A14 local proxy XO packaging | Documented PASS | Artix-7 packaging-structure proxy only; generated artifact is not in the current worktree |
| A14 target runner static checks | PASS | Bash syntax, two embedded Python blocks, and Tcl structural completeness only; ShellCheck unavailable |
| A14 target attempt 1 | BLOCKED/NOT RUN | V1 stopped at old-Git worktree-status collection before Vivado; no XO or link attempt |
| A14 V2 Git compatibility static | PASS | V1/V2 Bash, embedded Python, evidence tags, and valueless `--porcelain` checks |
| A14 V2 target retry | STOPPED/REVIEWED | Exact VU37P XO generated and archive integrity passed; XML metadata gate failed before `v++` |
| A14 exact VU37P XO generation | CONFIRMED | Vivado log: `TARGET_PART_USED=1`, package PASS, XO size 12,325 bytes |
| A14 exact VU37P XO metadata | PARTIAL/STOPPED | V3 generated data width 128 and component-side 64-bit addressing, but kernel XML range remained 32-bit and no global-memory argument existed |
| A14 V3 explicit AXI metadata retry | REVIEWED | Exact VU37P XO generated at `cd68a79`; diagnosis above; no `v++` or device operation |
| A14.5 table-base source | PRESENT | New versioned RTL/TBs/package runners; A13 and A14 v1 untouched |
| A14.5 local structural checks | PASS | Required address, ABI, guard, metadata, and no-`v++` invariants only |
| A14.5 XSim attempt 1 | FAIL/DIAGNOSED | Lookup compile/elaboration completed; 32-bit TB index was connected to the DUT's unoverridden 6-bit default; first comparison observed upper `Z`; wrapper not run |
| A14.5 XSim corrected retry | PASS | At `d428e8b`: lookup 67/67 and wrapper 17/17; 78 valid reads total; six rejected-request checks; both error/fatal counts zero |
| A14.5 exact VU37P XO v2 | NOT RUN | User-controlled Vivado 2020.2 server gate required |
| A14 Vitis link | BLOCKED | Local `v++` and F37X platform metadata unavailable |
| A14 xclbin | NOT GENERATED | No A14 xclbin exists in the current build tree |
| A14 physical HBM | NOT VALIDATED | No board access or physical HBM transaction has been run |

Primary evidence:

- `docs/STAGE2N_A13_FINAL_ACCEPTANCE.md`
- `docs/STAGE2N_A14_A1_ACCEPTANCE.md`
- `docs/STAGE2N_A14_KERNEL_WRAPPER_SIMULATION.md`
- `docs/STAGE2N_A14_XO_PACKAGING_PLAN.md`
- `docs/STAGE2N_A14_B2_1_ENVIRONMENT_BLOCK.md`
- `docs/STAGE2N_A14_TARGET_BUILD_RUNNER_V1.md`
- `docs/STAGE2N_A14_TARGET_BUILD_RUNNER_V2_GIT_COMPAT.md`
- `docs/STAGE2N_A14_TARGET_BUILD_RUNNER_V3_XO_METADATA_FIX.md`
- `docs/STAGE2N_A14_5_HBM_TABLE_BASE_ABI.md`
- `docs/STAGE2N_A14_5_XSIM_ACCEPTANCE.md`

## Current Local Environment

- Windows local development host.
- Vivado/XSim 2022.1 is installed at
  `D:\vivado2022\vivado2022forwins\Vivado\2022.1\bin`.
- Current main-worktree A14 XO: absent.
- Current main-worktree A14 `kernel.xml`: absent.
- Current main-worktree A14 xclbin count: zero.
- `v++`: not available in the current command environment.
- `PLATFORM_REPO_PATHS`: unset.
- `XILINX_PLATFORM_REPO_PATHS`: unset.

Historical target environment recorded by accepted evidence:

- Linux;
- Vivado 2020.2;
- Vitis 2020.2;
- Inspur platform `inspur_f37x_xdma_201920_3`;
- target part `xcvu37p-fsvh2892-2L-e`.

## Current Blockers

1. The exact VU37P device database and target packaging environment are absent
   from the local Vivado installation.
2. The local environment has no Vitis `v++` linker.
3. The F37X `.xpfm` platform is not available through local platform-repository
   paths.
4. The previously documented proxy XO was a generated worktree artifact and is
   not present in this main working tree.
5. The V3 exact-target XO confirms 128-bit AXI data and 64-bit component-side
   addressing, but the v1 kernel ABI has no `m_axi_gmem` table-base argument;
   generated kernel XML therefore retains a 32-bit range.
6. A14.5 local XSim now passes after the diagnosed testbench-only binding fix.
7. The exact-target XO metadata gate has not yet run.
8. A14 has no xclbin, physical HBM access evidence, XRT BO/DMA Host, or board
   result.
9. A14 lookup output is not connected to A13 Feature Interaction; the two tops
   are independent.

These are environment and integration blockers, not failures of the completed
A14 XSim tests.

## Next Actions

1. Commit and push the A14.5 local-XSim acceptance record.
2. Transfer the resulting committed revision to the clean user-controlled
   server and run
   `scripts/build_stage2n_a14_5_target_xo_v1.sh`.
3. Accept the XO-only gate only if generated kernel XML reports 128-bit data,
   64-bit range, and `TABLE_BASE` as an 8-byte `addressQualifier=1` argument on
   `m_axi_gmem`; retain XML, logs, status, size, and SHA256.
4. Update current-state/evidence documents and commit the actual XO result.
5. Only after the A14.5 gates pass, review a separate link/Host stage. Do not
   run v++, generate an xclbin, or access the FPGA as part of A14.5.
6. Only after standalone physical lookup validation, design a separate stage to
   connect embedding vectors to the frozen A13 Feature Interaction input.

## Non-Goals of the Current Stage

- modifying accepted A13 RTL;
- changing fixed-point arithmetic or the trained-model golden outputs;
- multi-bank HBM mapping;
- burst or multiple-outstanding optimization;
- coalescing, caching, prefetching, or scheduling RTL;
- performance or speedup claims;
- autonomous server, xclbin, or board operations by an AI agent.

## Status Rule

Do not promote `BLOCKED`, `NOT RUN`, a planning document, or a missing generated
artifact to PASS. Do not demote the final A13 acceptance based on the earlier
local-only A13 design report. For current work, this file and the later final
acceptance documents take precedence over older summaries.
