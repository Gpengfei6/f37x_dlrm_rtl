# Current State

Snapshot date: 2026-08-24

## Repository State

- Repository: `D:\FpgaWork\f37x_dlrm_rtl`
- Branch: `work/stage2n-a13-cycle-counter`
- HEAD: `4d24272a9788a3b7006cc37667aefda33c83878e`
- HEAD subject: `build(a14): add target xclbin validation runner`
- A14 source integration commit: `a19d338`
- Current engineering stage: **Stage 2N-A14**
- Accepted and frozen functional baseline: **Stage 2N-A13**

The branch name still refers to A13 even though A14 prototype files are now
present. Do not infer stage status from the branch name alone.

The working tree contains pre-existing untracked recovery, historical evidence,
patent, source, and helper files. Preserve them. Never use `git clean`, bulk
deletion, or `git add .`.

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
  older server Git rejects `git status --porcelain=v1`. A V2 compatibility
  entry is prepared; the target retry has not yet run.

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
| A14 V2 target retry | NOT RUN | Compatibility fix prepared; server execution pending |
| A14 exact VU37P XO | BLOCKED/PENDING | Exact target database/environment not available locally |
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
5. The first server runner attempt was blocked by old-Git CLI compatibility
   before any Vivado/Vitis build command; the V2 retry is pending.
6. A14 has no xclbin, physical HBM access evidence, XRT BO/DMA Host, or board
   result.
7. A14 lookup output is not connected to A13 Feature Interaction; the two tops
   are independent.

These are environment and integration blockers, not failures of the completed
A14 XSim tests.

## Next Actions

1. Preserve the first server-attempt build and result roots under the names in
   `docs/STAGE2N_A14_TARGET_BUILD_RUNNER_V2_GIT_COMPAT.md`.
2. Apply the V2 compatibility fix to the clean server repository and run
   `scripts/build_stage2n_a14_target_v2.sh`.
3. Retain the XO packaging command, exit status, `kernel.xml`, size, and SHA256.
4. Confirm the kernel name and `m_axi_gmem` port from generated metadata rather
   than filenames.
5. In the user-controlled Vitis 2020.2/F37X environment, link the XO using
   `config/stage2n_a14_target_v1.cfg` and record the resolved
   `m_axi_gmem -> HBM[0]` connection, timing, UUID, and xclbin SHA256.
6. Stop before board execution and request separate authorization.
7. Validate one physical HBM bank with categorical row IDs and bit-exact
   embedding vectors before measuring performance.
8. Only after standalone physical lookup validation, design a separate stage to
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
