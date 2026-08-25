# Current State

Snapshot date: 2026-08-25

## Repository State

- Repository: `D:\FpgaWork\f37x_dlrm_rtl`
- Branch: `work/stage2n-a13-cycle-counter`
- A14.5 accepted target-XO tested HEAD:
  `4096614419170404d5dcb334432f5f322c4f92d5`
- A14.6 accepted link-only tested HEAD:
  `b44855ed4bc8b469257cb3de80cf530e9d5039b9`
- A14.5 target-attempt parent HEAD: `de9276ebe5c62f54cff5877bc9b11b66606d1549`
- A14.5 source-preparation commit: `29401e5`
- A14.5 XSim-fix commit: `d428e8b`
- A14.5 XSim-acceptance commit: `de9276e`
- A14 source integration commit: `a19d338`
- Current engineering stage: **Stage 2N-A14.6 link-only accepted**
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
- The first exact-target XO attempt at `de9276e` used Vivado 2020.2 and the
  exact VU37P part. It generated an intact, non-empty XO and the returned
  metadata confirms the 8-byte global-memory `TABLE_BASE`, 128-bit data path,
  64-bit AXI bus/model/user parameters, 64-bit AWADDR/ARADDR ports, and a
  `2^64` IP-XACT address space.
- The old automated gate stopped because Vivado 2020.2 retained
  `kernel.xml range=0xFFFFFFFF`. That field conflicts with the specific
  64-bit component/RTL evidence and is not used as the sole width proof in the
  versioned retry. The old runner also misclassified the post-package stop as
  `BLOCKED_NOT_RUN` because its `ERR` trap fired during expected return-code
  capture; the v2 runner corrects this.
- New versioned package/validator/runner files preserve attempt 1 and write to
  `xo_v3` and `target_xo_v2`.
- The corrected exact-target retry at server HEAD `4096614` is **PASS**:
  - exact part `xcvu37p-fsvh2892-2L-e` and Vivado 2020.2;
  - 12,951-byte XO;
  - 8-byte `TABLE_BASE` global pointer at `0x18` on `m_axi_gmem`;
  - 128-bit data path, 64-bit RTL/component address path, and `2^64` IP-XACT
    address space;
  - standalone and in-XO XML hashes match;
  - source and artifact SHA256 manifests retained;
  - seven reviewed warnings, zero critical warnings, and zero errors.
- No v++ link, xclbin, Host, FPGA programming, or physical HBM operation is
  part of this milestone.

### Stage 2N-A14.6

- Link-only authorization and architecture are frozen, and the reviewed target
  link has completed successfully.
- The accepted input is the exact-target A14.5 v2 XO with SHA256
  `7c05895b4ef7f3b3e1169d722f88a4ea5103ae9d5cb5283fd0372e7bc3e43dea`.
- The frozen target is one `dlrm_a14_1` compute unit at 100 MHz with
  `m_axi_gmem -> HBM[0]` on `inspur_f37x_xdma_201920_3`.
- The flow must be link-only and non-overwriting; it may not rebuild the XO,
  add a Host, open a device, program/reset the FPGA, or access physical HBM.
- The versioned configuration, explicit-`yes` link-only runner, and offline
  xclbin validator are present and locally syntax/structure tested.
- The accepted attempt 3 used Vitis/Vivado 2020.2 and produced a 43 MiB
  xclbin with SHA256
  `9a7ce2518691e1d9a9ef55a0037d5d5345e3781f1e11eb7c2c7d19697144f573`
  and UUID `6f29087c-9598-4e68-877a-cc4840d078b8`.
- The xclbin validator found exactly one reviewed CU-to-used-HBM[0]
  connection. Routed timing at 100 MHz passed with WNS/TNS `0.000 ns` and
  zero failing endpoints.
- The 55 methodology critical warnings are retained as platform/static-clock
  methodology debt. WNS has no positive margin, so no frequency-headroom or
  broad physical-signoff claim is made.
- No Host, FPGA programming/reset, physical-HBM transaction, board result, or
  A13 integration exists.

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
| A14.5 exact VU37P XO attempt 1 | STOPPED/DIAGNOSED | At `de9276e`: exact-part XO generated and archive intact; returned inspection confirms TABLE_BASE/global-pointer ABI and 64-bit component address evidence; obsolete range-only assertion stopped the old automated gate |
| A14.5 exact VU37P corrected retry | **PASS** | At tested server HEAD `4096614`: XO 12,951 bytes; TABLE_BASE ABI and RTL/component/IP-XACT 64-bit address evidence PASS; seven warnings, zero critical warnings/errors; no v++ or device access |
| A14.6 link-only architecture | FROZEN | Accepted XO identity, one-CU HBM[0] mapping, 100 MHz request, evidence and non-claim gates documented |
| A14.6 link-only source preparation | PASS | Versioned config/runner/validator; Bash/Python syntax and synthetic metadata validation |
| A14 Vitis link | **PASS** | Vitis 2020.2, accepted XO, exact reviewed platform and connectivity; zero v++ errors/critical warnings |
| A14 xclbin | **PASS** | Non-empty 43 MiB artifact; SHA256 and UUID retained; generated artifact remains outside Git |
| A14 linked HBM[0] metadata | **PASS** | Exactly one `dlrm_a14_1` connection to used HBM[0] in extracted xclbin metadata |
| A14 target timing | **PASS** | Exact VU37P route at 100 MHz; WNS/TNS 0.000 ns, zero failing endpoints; no positive setup margin |
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
- `docs/STAGE2N_A14_5_TARGET_XO_ATTEMPT1_DIAGNOSIS.md`
- `docs/STAGE2N_A14_5_TARGET_XO_ACCEPTANCE.md`
- `docs/evidence/stage2n_a14_5/`
- `docs/STAGE2N_A14_6_LINK_ONLY_ACCEPTANCE.md`
- `docs/evidence/stage2n_a14_6/`

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
5. A14 has an accepted generated link-only xclbin, but no physical HBM access
   evidence, XRT BO/DMA Host, or board result.
6. A14 lookup output is not connected to A13 Feature Interaction; the two tops
   are independent.

These are environment and integration blockers, not failures of the completed
A14 XSim tests.

## Next Actions

1. Commit and push the A14.6 link-only acceptance record without committing
   the generated xclbin, routed DCP, or large reports.
2. Preserve the accepted XO and xclbin identities and the returned evidence;
   do not rerun or overwrite the accepted roots merely to reproduce them.
3. Keep Host/XRT/device/physical-HBM work outside A14.6.
4. Review and authorize a separate stage before any Host or device operation.
5. Only after standalone physical lookup validation, design a separate stage to
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
