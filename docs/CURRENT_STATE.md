# Current State

Snapshot date: 2026-08-31

## Repository State

- Repository: `D:\FpgaWork\f37x_dlrm_rtl`
- Branch: `work/stage2n-a15-hbm-pipeline-integration`
- A14.5 accepted target-XO tested HEAD:
  `4096614419170404d5dcb334432f5f322c4f92d5`
- A14.6 accepted link-only tested HEAD:
  `b44855ed4bc8b469257cb3de80cf530e9d5039b9`
- A14.7 local-source preparation base HEAD:
  `3e9899519145d9a3f71f32aee1d1580d388c008f`
- A14.5 target-attempt parent HEAD: `de9276ebe5c62f54cff5877bc9b11b66606d1549`
- A14.5 source-preparation commit: `29401e5`
- A14.5 XSim-fix commit: `d428e8b`
- A14.5 XSim-acceptance commit: `de9276e`
- A14 source integration commit: `a19d338`
- A14.7 final protected source baseline: `70179f66c6fab8a28c2305c024bec3fa43f9c508`
- A15.1 authorization and implementation baseline:
  `2020e4ccd2f802d69714d957e7b8baf8172a39fa`
- A15.3 authorization and parent baseline:
  `b3031d4f9d3c445a3f1eaa227ae2d28d35d78ae9`
- A15.4 authorization and implementation starting HEAD:
  `7d0c3519c29b2dd07e0615dc98ba7060d728bc4f`
- A15.5 target-preparation authorization baseline:
  `0c705a360a036785e4c949185fcb5cc1dcc4f07f`
- A15.5 source-build HEAD:
  `30cbf64e44fa99aa025f1a7456d739c8b5d4be6b`
- A15.5 validator/revalidation HEAD:
  `2ce2d443cd55d00b492e154aa57091f39d14934e`
- A15.6 local-preparation parent HEAD:
  `14cb37721b918e644c8cae689791628247a00eec`
- A15.6 accepted board-execution source HEAD:
  `85ac9d1c333d5e016341c57de722e222da991d97`
- A16.1 instrumentation parent HEAD:
  `6155ad8fe2fa9000ebc314536986c83581f8a940`
- A16.2 preparation HEAD:
  `a1fdc71097f9969c8e982926a1ce1615a0c3254e`
- Current engineering stage: **Stage 2N-A16.2 final acceptance PASS; A16.3 not
  started**
- Accepted and frozen physical-HBM functional baseline: **Stage 2N-A15.6**
- Accepted and frozen dense/compute arithmetic baseline: **Stage 2N-A13**

The branch contains the accepted A13/A14 history plus the versioned A15.1 local
integration wrapper, A15.2 end-to-end proof, A15.3 four-slot sequential lookup
proof, A15.4 versioned public AXI4-Lite plus `m_axi_gmem` kernel boundary, and
A15.5 versioned target package/link preparation with offline validators and a
versioned Vitis 2020.2 xclbin-layout compatibility fix. The fixed-SHA target
artifact passed non-rebuilding v2 revalidation. A15.6 then used that exact
artifact in a protected F37X run: one physical `HBM[0]` BO supplied four
sequential embedding lookups and all five independent board golden cases matched
  exactly. A16.1 now adds a separate versioned local top with lookup and FPGA
  end-to-end counters; it does not change that frozen RTL or xclbin. A16.2 then
  prepared the reviewed target-build and protected board-measurement flow. The
  compact original evidence has now been imported and validated locally. The
  exact-target build, requested 100 MHz gate, protected five-case board run and
  physical sequential latency baseline are accepted. Performance remains
  unclaimed, and A16.3 has not started.

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

### Stage 2N-A14.7
- Added a protected legacy-HAL Host for one canonical physical-HBM[0] lookup
  without changing A14 RTL or the accepted A14.6 xclbin.
- Added a byte-exact canonical-table builder: 1024 bytes, SHA256
  `023ad250824def6b538ac40a7f0a9bd457e571136100ab1c1e574769f9061b03`, FNV1a64 `40a53c3698b88325`.
- The Host allocates one HBM[0] BO, obtains its 64-bit `paddr`, programs
  `TABLE_BASE_LO/HI`, executes one row lookup, handles read-to-clear DONE,
  checks all eight INT16 lanes, and releases the BO.
- Added a target build-only XRT `2.9.210507` API/symbol gate, protected board runner,
  and exact 64-line offline evidence validator with tamper rejection.
- Local source checks PASS: canonical payload reconstruction, Python syntax,
  C++11 declaration-only XRT stub compile, Bash syntax, valid evidence fixture,
  and tampered-result rejection.
- The first target build attempt diagnosed the XRT vendor `setup.sh` nounset
  incompatibility. Commit `82a6e46` hardened the tracked runner by suspending
  `nounset` only while sourcing the vendor environment and removed the redundant
  GCC 4.8 aggregate-initializer warning.
- The formal user-controlled rerun at server HEAD
  `82a6e4627bcaa0e9c7bab6daf8ca6bcc095d7cc6`, with `LD_LIBRARY_PATH`,
  `PYTHONPATH`, and `XILINX_XRT` explicitly unset before execution, is **PASS**:
  canonical payload PASS, XRT `2.9.210507` API/symbol probe PASS, GCC 4.8.5
  `gnu++11` compile/link PASS, and a 44 KiB x86-64 ELF Host binary was produced.
- Formal Host binary SHA256 is
  `f5bfbd50562fcf31a45105a32f7edb414fc4886d007c8ab588f8032c3afc0946`;
  payload SHA256 remains
  `023ad250824def6b538ac40a7f0a9bd457e571136100ab1c1e574769f9061b03`.
- The build-only record was subsequently superseded by the final A14.7
  acceptance below: one protected physical HBM[0] lookup completed with exact
  row-37 software-golden agreement, then the BO was released and HBM[0]
  returned to zero usage.

### Stage 2N-A15.1

- Added a versioned controller-level wrapper that instantiates, without editing,
  the accepted A14 v2 lookup and accepted A13 cycle-counter pipeline.
- A successful A14 128-bit response is retained until A13 accepts it as
  embedding slot 0. No lane reorder is performed.
- Embedding slot 0 is HBM-owned; Host writes to slot 0 are explicitly rejected.
  Slots 1 through 3 preserve the A13 Host-configured handshake and data.
- Pending HBM injection has configuration-port priority. Lookup errors never
  write slot 0, and busy/repeated requests cannot replace retained state.
- Local Vivado/XSim 2022.1 compile, elaboration, and simulation are **PASS** with
  all nine behavioral/ABI markers, zero warnings, and zero anchored
  error/fatal records.
- This is a fake-memory controller-level proof. There is no A15 target build,
  xclbin, public kernel-top integration, FPGA execution, or physical HBM result.

### Stage 2N-A15.2

- Reused the frozen A15.1 v1 wrapper; no new or modified RTL was required.
- Reused the accepted A13 deterministic sample: Bottom `8->16->8`, Interaction
  `5x8->18`, Top `18->32->16->1`, dense input `[1..8]`, zero embeddings, and
  independently derived final golden 36.
- Replaced only the source of slot 0: local fake-memory row 37 returned the same
  all-zero vector previously written by the Host. Slots 1 through 3 remained
  Host-configured.
- The self-checking bench observed the real A13 Interaction load handshakes and
  proved vector0 was the Bottom output and vector1 was the HBM-owned slot 0;
  vectors2 through 4 were the Host-owned slots.
- Complete Bottom, Feature Interaction, and Top execution passed with final
  result 36 and exact cycle counts `322/100/744/1174`, including eight controller
  overhead cycles.
- Local `xvlog`, `xelab`, and `xsim` exit codes were all zero, with zero warnings
  and zero anchored error/fatal records.
- This remains fake-memory local XSim. A15 target build, xclbin, FPGA execution,
  physical HBM integration, board validation, and performance are not proven.

### Stage 2N-A15.3

- Added a versioned orchestration wrapper because accepted A15.1 fixes HBM
  ownership to slot 0 and cannot express four HBM-owned slots without changing
  accepted behavior.
- One unchanged A14 v2 lookup engine sequentially fetches canonical rows
  37, 38, 39, and 40 and commits them to A13 slots 0 through 3 only on the
  accepted embedding configuration handshake.
- Expected and actual vectors are `[40..47]`, `[48..55]`, `[56..63]`, and
  `[64..71]`; all 32 signed INT16 lanes and all four packed 128-bit values match.
- The self-checking bench proves mask transitions `0->1->3->7->F`, delayed AXI
  request/response and A13-ready retention, slot-2 error preservation, busy and
  repeated-request rejection, Host writes rejected for all four slots, and the
  existing A13 START gate.
- Complete Bottom `8->16->8`, Interaction `5x8->18`, and Top `18->32->16->1`
  execution matches the independently calculated result 36. Cycle counts remain
  `322/100/744/1174`; the four lookup preloads occur before A13 START.
- Final Vivado/XSim 2022.1 `xvlog/xelab/xsim` return codes are `0/0/0`, with
  zero warnings, errors, and fatals. Successful transaction counts are four
  logical lookups, four AR handshakes, four R handshakes, and four injections.
- This remains local fake-memory evidence. It is not a public target top,
  target build/link, xclbin, FPGA execution, physical HBM, multi-bank, or
  performance result.

### Stage 2N-A15.4

- Added a new versioned public F37X-style top with the complete accepted A13
  AXI4-Lite map, one 64-bit-address/128-bit-data `m_axi_gmem` read master, and a
  disjoint A15.4 control window at `0x300/0x304/0x308`.
- One A15 START snapshots TABLE_BASE and model-segment configuration, invokes
  the unchanged A15.3 four-row sequence, waits for loaded mask `4'hF`, and then
  automatically starts the unchanged A13 Bottom–Interaction–Top pipeline.
- Canonical rows 37–40 produced exact vectors `[40..47]`, `[48..55]`,
  `[56..63]`, and `[64..71]` at addresses `0x0000000123456250` through
  `0x0000000123456280` for TABLE_BASE `0x0000000123456000`.
- Local public-port XSim passed exactly four lookup/AR/R/injection handshakes,
  final mask `0xF`, independent golden/actual result `36/36`, and unchanged A13
  counters `322/100/744/1174`.
- Reset, slot0 and slot2 error handling, repeated START, delayed ARREADY/RVALID,
  Host embedding rejection, START gating, and accepted ABI guards passed.
- `xvlog/xelab/xsim` returned `0/0/0`; retained logs contain zero warnings,
  errors, fatals, and assertion-failure records.
- This is still local fake-memory evidence. Target build/link, XO/xclbin,
  physical HBM, FPGA/board behavior, and performance are not validated.

### Stage 2N-A15.5

- Froze the accepted A15.4 top as
  `dlrm_f37x_rtl_kernel_stage2n_a15_v1`, with accepted wrapper SHA256
  `c3da5be63d4cf195df124e572887b6aa96a464522883c6cdc95c4bd56ff4e8a1`.
- Prepared a non-overwriting exact-VU37P XO-only runner and a separate Vitis
  link-only runner for one CU `dlrm_a15_1` and one
  `dlrm_a15_1.m_axi_gmem:HBM[0]` mapping at a requested 100 MHz.
- Kernel metadata exposes exactly one global pointer, 64-bit TABLE_BASE at
  `0x304`; the complete A13/A15 ABI remains raw user-managed AXI-Lite. The
  stale A14 `LOOKUP_INDEX/RESULT0-3` signature is rejected.
- Local static validation and both validators' positive/negative self-tests
  passed. Bash syntax is `NOT_RUN` because Bash is unavailable locally.
- The fixed-source target XO and completed Vitis 2020.2 link are accepted, with
  XO SHA256 `a88fd4bba7a534f7068cff838448c5ba7f330e5bec27c8c2697525c9dedee019`,
  xclbin SHA256
  `23ee48c91b3dfb5b68b3372ac49fc6607f203cf01d3b9fcfe04b4ea42be02356`,
  and xclbin UUID `1b555645-a9e2-4f5e-95af-6ce4adacbc3c`.
- The v1 xclbin validator falsely counted 35 shell IP entries as additional
  compute units. The versioned v2 validator filters `m_type=IP_KERNEL`, requires
  the unique kernel/CU, and dereferences the sole connection to used `HBM[0]`.
- The v2 local positive fixture and 12 negative fixtures pass. The fixed-SHA
  xclbin then passed target v2 revalidation without rebuild. Metadata proves
  one `IP_KERNEL`, one connection from TABLE_BASE/arg0 to used `HBM[0]`, and no
  stale A14 arguments.
- Exact-target routed timing passes at 100 MHz with WNS/TNS `0.000/0.000 ns`
  and zero failing endpoints. There is no positive setup margin. DRC errors and
  critical warnings are zero; methodology errors are zero and 55 methodology
  critical warnings remain recorded.
- Physical HBM, Host, FPGA/board execution, and performance remain
  `NOT_VALIDATED`, `NOT_RUN`, or `NOT_CLAIMED`.

### Stage 2N-A15.6

- Froze the accepted A15.5 xclbin SHA256
  `23ee48c91b3dfb5b68b3372ac49fc6607f203cf01d3b9fcfe04b4ea42be02356`
  and UUID `1b555645-a9e2-4f5e-95af-6ce4adacbc3c`; no XO/xclbin rebuild occurred.
- Added a versioned low-level XRT 2020.2 Host and protected runner for one
  explicit F37X BDF and one BO in linked `HBM[0]`. The runner is
  fail-closed and requires exact artifact identity, device mapping, idle/owner/
  firewall/HBM-use guards, and a literal `yes` before any device-changing step.
- Added one baseline and four slot-sensitivity table payloads. The independent
  fixed-point golden results are `-393`, `-392`, `-93`, `-689`, and `-519`, so
  every HBM-derived slot affects the final result and the four perturbation
  results are pairwise distinct.
- Local source/asset validation, evidence assembly, the positive evidence
  fixture, and eight negative/rejection fixtures pass. The target XRT 2020.2
  Host build/API probe and protected execution subsequently passed.
- The real run selected device index 2, BDF `0000:9b:00.1`, render node
  `/dev/dri/renderD129`, allocated a 4096-byte BO in `HBM[0]` at valid physical
  address `0x0`, programmed the frozen xclbin, transferred each payload and
  released the BO/device cleanly without reset or other-device access.
- All five results match: `-393`, `-392`, `-93`, `-689`, and `-519`; every case
  has loaded mask `0xF` and counters `322/100/744/1174`.
- `A15_6_PHYSICAL_HBM=PASS`, `A15_6_BOARD_FUNCTIONAL=PASS`, and
  `A15_6_FINAL_ACCEPTANCE=PASS`. `A15_6_PERFORMANCE=NOT_CLAIMED` because the
  1174-cycle interval excludes the four HBM lookups and Host/BO activity.
- Added a separate device-free target-preflight entry and validator. The
  user-controlled target checks reached xclbin metadata extraction and XRT Host
  build/API PASS before the protected execution. Old-Git, deterministic path
  and post-XRT `BASH_SOURCE` compatibility fixes changed no frozen artifact.

### Stage 2N-A16.1

- Added a versioned A16 top; accepted A15.4 RTL SHA256
  `c3da5be63d4cf195df124e572887b6aa96a464522883c6cdc95c4bd56ff4e8a1`
  remains unchanged and the A15.5 xclbin was not rebuilt.
- Added read-only 32-bit saturating counters at `0x30C` for first-AR-handshake
  through fourth-slot injection and `0x310` for accepted A15 START through
  first final-result visibility. The accepted A13 `0x218`–`0x224` semantics
  remain unchanged.
- Two complete XSim invocations pass; each includes two identical no-reset
  restart runs, directed saturation, error/busy/backpressure/clear checks, four
  ordered slots, final result 36 and old counters `322/100/744/1174`.
- Local fake-AXI values are lookup `73`, FPGA end-to-end `1285`, and internal
  overhead `38` cycles, satisfying `1285 = 73 + 1174 + 38`.
- Physical HBM latency is `NOT_VALIDATED` and performance is `NOT_CLAIMED`.

### Stage 2N-A16.2

- Prepared, entirely locally, the reviewed target-build and protected
  board-measurement flow later used for the reported physical sequential-HBM
  latency run,
  reusing the accepted A15.5 XO/link packaging, A15.6 XRT Host/protected board
  runner, and the frozen A16.1 RTL/counter ABI.
- Added versioned A16.2 assets: target config, XO package Tcl, XO/link/Host
  build runners, protected board runner, post-route report Tcl, Host source,
  four validators, and a local preparation entry
  (`scripts/run_stage2n_a16_2_local_preparation_v1.ps1`).
- The A16 target is `dlrm_f37x_rtl_kernel_stage2n_a16_v1`, CU `dlrm_a16_1`,
  `s_axi_control` plus exactly one 64-bit-address/128-bit-data `m_axi_gmem`
  master, `dlrm_a16_1.m_axi_gmem:HBM[0]`, and only `TABLE_BASE` as the kernel
  pointer argument at `0x304`. The obsolete A14 `LOOKUP_INDEX`/`RESULT0..3`
  signature is rejected.
- A16 counters `0x30C`/`0x310` are custom AXI4-Lite registers, not Vitis kernel
  arguments.
- Local preparation entry PASS: source validation, ABI validation, protection
  gate, XO validator self-test (1 positive + 9 negative), xclbin validator
  self-test (Vitis 2020.2 36-entry layout + 12 negative), board-log validator
  self-test (1 positive + 6 negative), old-Git compatibility scan, and manual
  `bash -n` of the four target shell scripts (Git Bash).
- A16.1 RTL SHA256 `a6eec09c...` and A15.4 RTL SHA256 `c3da5be63...` unchanged;
  A15.5 xclbin not rebuilt.
- The original local-preparation record retains its historical target
  `NOT_RUN_TARGET_REQUIRED` markers; the separately imported final evidence now
  validates the target and board execution.
- Accepted imported evidence: XO SHA `ea0fe950...`, xclbin SHA `5f0d6fef...`, UUID
  `f18571de-4a43-46bd-8ab9-a89dd4b11f8e`, one `dlrm_a16_1.m_axi_gmem ->
  HBM[0]` connection, 100 MHz WNS/TNS `0.000/0.000 ns`, zero failing
  endpoints, and 55 methodology critical warnings.
- Accepted five-case board values: exact results
  `-393/-392/-93/-689/-519`, compute `322/100/744/1174`, lookup `112`, FPGA
  end-to-end `1289`, accounting residual `3` for every case.
- Source reconciliation is `EXPLAINED`: XSim deliberately inserts control and
  ARREADY stress before its first AR handshake, so its 38-cycle residual is not
  comparable to the physical Host's 3-cycle residual as a standalone stage.
- Compact raw target/board evidence is curated under
  `docs/evidence/stage2n_a16_2/final_acceptance_v1/`; the offline validator
  reports 31 valid manifest entries. Therefore
  `A16_2_FINAL_ACCEPTANCE=PASS` and
  `READY_FOR_A16_3_ARCHITECTURE=YES_ACCEPTED_SEQUENTIAL_BASELINE`.
- `A16_2_PERFORMANCE=NOT_CLAIMED`; A16.3 remains `NOT_STARTED`.

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
| A14.7 local Host/HBM source preparation | **PASS** | Legacy-HAL Host, canonical builder, build-only gate, protected runner, and 64-line validator prepared locally |
| A14.7 canonical payload | **PASS** | 1024 bytes; SHA256 `023ad250824def6b538ac40a7f0a9bd457e571136100ab1c1e574769f9061b03`; FNV1a64 `40a53c3698b88325` |
| A14.7 local static/offline validation | **PASS** | C++11 declaration-only XRT stub compile, Bash/Python syntax, valid 64-line fixture, tampered-result rejection |
| A14.7 target XRT Host build | **PASS** | Formal rerun at `82a6e46` with caller XRT variables explicitly unset; XRT `2.9.210507` symbol/API probe and GCC 4.8.5 `gnu++11` compile/link PASS; binary SHA256 `f5bfbd50562fcf31a45105a32f7edb414fc4886d007c8ab588f8032c3afc0946` |
| A14.7 physical HBM | **PASS** | One protected HBM[0] row-37 lookup returned `[40,41,42,43,44,45,46,47]` exactly; BO release and zero post-use HBM[0] state recorded |
| A15.1 local HBM-to-pipeline integration | **PASS** | Controller-level XSim: slot-0 injection, exact lane order, Host slot1-3 preservation, delayed ready, error/busy/Host-slot0 guards, loaded mask and A13 ABI all passed; fake AXI memory only |
| A15.1 physical HBM / target execution | NOT RUN | No public target top, target build/link, xclbin programming, FPGA access, or board run |
| A15.2 local end-to-end pipeline | **PASS** | Fake-memory row37 -> slot0 -> Bottom/Interaction/Top -> final result 36; actual Interaction load ordering observed; exact 322/100/744/1174 counters |
| A15.2 target/xclbin/physical HBM | NOT RUN | Local controller-level XSim only; no public target top, target build/link, xclbin, device, or board access |
| A15.3 local four-slot sequential lookup pipeline | **PASS** | One A14 v2 engine; rows 37-40 -> slots 0-3 -> Bottom/Interaction/Top; exact final 36; four logical/AR/R/injection handshakes; ready/error/busy/Host guards PASS |
| A15.3 target/xclbin/physical HBM/performance | NOT RUN / NOT CLAIMED | Local fake-memory XSim only; no target build/link, XO/xclbin, device, physical HBM, multi-bank, board, or performance evidence |
| A15.4 public F37X kernel integration | **LOCAL XSIM PASS** | Public AXI4-Lite and one `m_axi_gmem`; TABLE_BASE plus rows 37-40; four lookup/AR/R/injection handshakes; mask `0xF`; result 36; counters and A13 ABI preserved |
| A15.4 target/XO/xclbin/physical HBM/board/performance | NOT RUN / NOT CLAIMED | No target packaging, Vitis link, generated artifact, device access, physical transaction, or performance evidence |
| A15.5 local target preparation | **PASS** | Exact source/ABI/connectivity static gates and XO/xclbin validator positive/negative self-tests; no target tool execution |
| A15.5 validator v2 compatibility | **LOCAL PASS** | Vitis 2020.2 36-entry IP-layout positive fixture and 12 mutation/rejection fixtures pass; Bash syntax NOT RUN |
| A15.5 target XO/link/xclbin/timing | **FINAL PASS** | Fixed-SHA XO/xclbin, one TABLE_BASE/arg0-to-used-HBM[0] mapping, validator v2, and 100 MHz routed timing accepted; WNS/TNS 0.000/0.000 ns, zero failing endpoints, no rebuild |
| A15.5 physical HBM/board/performance | NOT VALIDATED / NOT RUN / NOT CLAIMED | No device access or performance activity occurred |
| A15.6 local protected-board preparation | **PASS** | Frozen-artifact/source/asset gates, five independent golden cases, positive evidence assembly/validation, and eight negative fixtures pass; frozen RTL unchanged and xclbin not rebuilt |
| A15.6 target-preflight source preparation | **LOCAL PASS** | Versioned device-free preflight and static validator prepared; no device query/open, BO, Host run, FPGA programming, v++, Vivado, or xclbin rebuild command |
| A15.6 target preflight | **TARGET PASS** | User-controlled target checks completed xclbin CONNECTIVITY/MEM_TOPOLOGY/IP_LAYOUT extraction plus XRT 2020.2 Host build/API probe; compatibility fixes did not change RTL/xclbin |
| A15.6 Host build and protected execution | **PASS** | Exact device/BDF/render and frozen xclbin guards passed; literal user authorization preceded programming |
| A15.6 physical HBM and complete board function | **FINAL PASS** | One 4096-byte HBM[0] BO at valid paddr 0; four sequential lookups; five exact full-DLRM results; masks/counters/cleanup PASS |
| A15.6 performance | NOT CLAIMED | 1174 cycles is compute-only and excludes lookup, Host and BO-transfer intervals |
| A16.1 local sequential-latency instrumentation | **XSIM PASS** | Two full invocations, two deterministic runs each; lookup/compute/e2e/overhead = 73/1174/1285/38 with fake AXI memory |
| A16.1 physical HBM latency / target / performance | NOT VALIDATED / NOT RUN / NOT CLAIMED | New RTL has not been target-built or run on F37X; local lookup cycles are not physical-HBM latency |
| A16.2 local source preparation | **PASS** | Source closure, one-CU/HBM[0] config, package tokens, stale A14 rejection, old-Git-safe target scripts, no network/device commands, Host ABI tokens, protected-runner tokens, authorization-before-programming |
| A16.2 XO validator self-test | **PASS** | 1 positive + 9 negative fixtures; wrong kernel/second master/stale A14 args/wrong widths/offset/counter/part all rejected |
| A16.2 xclbin validator self-test | **PASS** | Vitis 2020.2 36-entry layout (1 IP_KERNEL + 35 shell) positive; 12 negative fixtures |
| A16.2 board-log validator self-test | **PASS** | 1 positive + 6 negative fixtures; missing/zero/negative/mismatched latency accounting and compute-ABI change rejected |
| A16.2 protection gate | **PASS** | Explicit target index/BDF/render/xclbin/SHA/UUID required; firewall/render/HBM[0] checks; allowlist; yes/no authorization before programming; no FPGA reset |
| A16.2 target XO/link/timing/board | **FINAL PASS** | Imported compact evidence validates fixed artifacts, one CU/HBM[0], requested 100 MHz timing, Host identity and five exact protected physical cases |
| A16.2 latency accounting | **EXPLAINED** | Inclusive-edge algebra and RTL/TB/Host source audit explain 73/1174/1285/38 simulation versus accepted 112/1174/1289/3 physical partitioning; no counter bug found |

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
- `docs/STAGE2N_A14_7_HBM_SINGLE_TABLE_HOST_PREPARATION_V1.md`
- `docs/STAGE2N_A15_1_HBM_PIPELINE_INTEGRATION_V1.md`
- `docs/STAGE2N_A15_2_END_TO_END_PIPELINE_XSIM_V1.md`
- `docs/STAGE2N_A15_3_ALL_HBM_EMBEDDING_PIPELINE_XSIM_V1.md`
- `docs/STAGE2N_A15_4_F37X_KERNEL_ALL_HBM_PIPELINE_XSIM_V1.md`
- `docs/STAGE2N_A15_5_TARGET_XO_XCLBIN_PREPARATION_V1.md`
- `docs/STAGE2N_A15_5_XCLBIN_VALIDATOR_V2_COMPATIBILITY.md`
- `docs/STAGE2N_A15_5_TARGET_XCLBIN_FINAL_ACCEPTANCE_V1.md`
- `docs/evidence/stage2n_a15_5/target_xclbin_revalidation_v2/`
- `docs/STAGE2N_A15_6_PROTECTED_ALL_HBM_BOARD_VALIDATION_PREPARATION_V1.md`
- `docs/STAGE2N_A15_6_TARGET_PREFLIGHT_PREPARATION_V1.md`
- `docs/evidence/stage2n_a15_6/local_preparation_v1/`
- `docs/STAGE2N_A15_6_ALL_HBM_BOARD_FINAL_ACCEPTANCE_V1.md`
- `docs/evidence/stage2n_a15_6/final_acceptance_v1/`
- `docs/STAGE2N_A16_1_SEQUENTIAL_HBM_LATENCY_INSTRUMENTATION_V1.md`
- `docs/evidence/stage2n_a16_1/`
- `docs/STAGE2N_A16_2_TARGET_AND_PHYSICAL_LATENCY_PREPARATION_V1.md`
- `docs/STAGE2N_A16_2_FINAL_ACCEPTANCE_V1.md`
- `docs/evidence/stage2n_a16_2/`
- `docs/evidence/stage2n_a14_7/local_source_preparation_v1.txt`
- `docs/STAGE2N_A15_1_HBM_PIPELINE_INTEGRATION_V1.md`
- `docs/STAGE2N_A15_2_END_TO_END_PIPELINE_XSIM_V1.md`

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
5. The large fixed-SHA XO/xclbin and routed DCP remain outside Git; their small
   final metadata/status/hash/report evidence is curated under `docs/evidence`.
6. A15.6 physical-board function, A16.1 local instrumentation and A16.2 final
   target/physical-latency acceptance pass. A16.2 is the accepted real F37X
   sequential-latency comparison baseline. A16.3 has not started.

These local tool absences do not invalidate the accepted A15.5 artifact or the
returned A15.6 physical-board evidence.

## Next Actions
1. Preserve the A15.6 single-bank/single-master/four-sequential-lookup
   functional baseline and the accepted A16.1 counter semantics.
2. Preserve the accepted A16.2 fixed artifact identities, counter boundaries,
   five-case workload and 112/1174/1289/3 sequential baseline.
3. Do not start A16.3 without a separate architecture boundary and explicit
   authorization.
4. Compare any later multi-bank or parallel design against an equivalently
   instrumented sequential target, not the local fake-AXI value.
5. Require functional equivalence and comparable target evidence before any
   speedup, bandwidth, throughput, power or performance claim.
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

## Stage 2N-A14.7 — Final Acceptance

Status: `PASS`

Stage 2N-A14.7 has completed protected Host/XRT + physical HBM[0] single-table lookup validation on the authorized F37X target.

Accepted functional board evidence:
- Functional tested HEAD: `74301a458ef8f6ad7d59dafc80ff30bbae9961d3`
- Target BDF: `0000:9b:00.1`
- XRT: `2.9.210507`
- XCLBIN UUID: `6f29087c-9598-4e68-877a-cc4840d078b8`
- XCLBIN SHA256: `9a7ce2518691e1d9a9ef55a0037d5d5345e3781f1e11eb7c2c7d19697144f573`
- HBM bank: `HBM[0]`
- Lookup index: `37`
- Expected lanes: `[40, 41, 42, 43, 44, 45, 46, 47]`
- Actual lanes: `[40, 41, 42, 43, 44, 45, 46, 47]`
- `A14_7_RESULT_MATCH=PASS`
- `A14_7_BO_RELEASED=PASS`
- `A14_7_HBM0_POST_RELEASE_ZERO=PASS`
- `A14_7_DMA_ACTIVITY_OBSERVED=PASS`
- FPGA reset: `NOT_RUN`
- automatic rollback: `NOT_RUN`

Raw evidence:
- 64-line evidence SHA256: `644155ffc1c4e40456a52a2a8ca3a84765b1ce685b9d377138bdd25b6871d2d2`
- successful board log SHA256: `cecce17484def1645938b14df8f9b1744e13bf67ea9e4af3ab3ab25dbef54ca5`

Final protected source baseline:
- HEAD: `70179f66c6fab8a28c2305c024bec3fa43f9c508`
- protected runner SHA256: `03838a0e0a3d85f8a0df622efa35c3a81cf69f58a56bc07792ec16965e48e47e`
- accepted Host ELF SHA256: `f5bfbd50562fcf31a45105a32f7edb414fc4886d007c8ab588f8032c3afc0946`
- final hardened guard log SHA256: `9c7db499b84444d278c3be195439fa0984b144cb4586930112f2a2ba7755e368`

The first protected attempt exposed a zero-byte runtime Host artifact. The physical A14.6 programming operation succeeded, but the real C++ Host/HBM path did not execute. The protected runner was subsequently hardened to require a non-empty Host ELF plus recorded and actual SHA256 equality before any physical execution.

A14.7 is now frozen. No further single-table HBM smoke is required merely for confirmation.

The local A13/A14 integration path is now functionally proven through A15.4 at
a public AXI4-Lite plus `m_axi_gmem` boundary for four sequential fake-memory
rows and a complete golden-matched inference. This
does not convert the standalone A14.7 physical result into physical A15 proof.

A16.1 has completed the separately versioned local instrumentation step.
A16.2 local preparation and final target/board evidence validation pass. The
latency-accounting difference is source-reconciled without an RTL change, and
the accepted physical sequential baseline is 112/1174/1289/3 cycles.
The accepted A15.6 single-bank, one-master, four-sequential-lookup functional
baseline remains frozen. Multi-table and multi-HBM-bank parallelism remain
future work and have no accepted speedup claim.
