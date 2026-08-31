# Stage 2N History

This table is an AI-readable index of Stage 2N-A1 through A15.6. It does not turn
historical claims into current verification. Follow each evidence link and use
the status language exactly.

Before Stage 2N, Phase 1 established the fixed-point reference and GATE-1;
Stages 2A–2F established the parameterized dense engine, multilayer execution,
synthesizable memories, 100 MHz pipelining, Vivado 2020.2 reproduction, and
Artix-7 post-route feasibility. Stages 2G–2M added the F37X RTL-kernel path,
hardware-link flow, board regression utilities, trained-model packaging, and a
hybrid CPU-embedding/FPGA-dense inference path.

| Stage | Goal | Main achievement | Evidence | Status |
|---|---|---|---|---|
| Stage 2N-A1 | Implement Feature Interaction independently | Added fixed 5-vector by 8-element INT16 interaction RTL, lower-triangle dot products, quantization/saturation, backpressure, and self-checking XSim sources | Commits `89288a9`, `e68f692`; `rtl/interaction/dlrm_feature_interaction_engine.sv`; interaction TB/runner | Implemented; historical XSim milestone |
| Stage 2N-A2 | Expose interaction through the F37X control shell | Added an independent AXI4-Lite interaction register window while preserving the legacy MLP window | Commit `1643b49`; `rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a2.sv`; A2 TB and runner | Implemented and used by later stages |
| Stage 2N-A3 | Produce a target link flow for the combined control kernel | Added robust F37X hardware-link scripts and a Vitis-compatible compute-unit name | Commits `3c8730e`, `802573d`; A3 link scripts | Build-flow milestone; no current generated artifact in Git |
| Stage 2N-A4 | Validate legacy MLP plus standalone interaction on F37X | Board evidence recorded result 19 for MLP and exact 18-value interaction output, with protected device targeting and safe final state | Recovery chain commit `f8dbbd8`; `RECOVERY_BASELINE_PLAN.md` | Original board evidence accepted during recovery; historical baseline |
| Stage 2N-A5 | Connect Bottom, Interaction, and Top internally | Added one-START ordered internal pipeline, descriptor segmentation, shared dense engine, automatic Top-input transfer, and result backpressure; XSim recorded two runs and final result -60 | Commit `915a49b`; `docs/STAGE2N_A5_INTERNAL_PIPELINE.md` | XSim evidence accepted during recovery |
| Stage 2N-A6 | Close internal VU37P timing for the pipeline | Routed internal OOC block at 100 MHz; setup WNS +1.482 ns, internal hold WHS +0.024 ns, zero unrouted nets/latches/DRC errors | Commit `a73e045`; `docs/STAGE2N_A6_INTERNAL_TIMING_ACCEPTANCE.md`; machine-readable evidence under `docs/evidence/stage2n_a6/` | Trusted A6 recovery baseline; not a full shell result |
| Stage 2N-A7 | Control the automatic pipeline through AXI4-Lite | Added pipeline register window and one-command Bottom–Interaction–Top execution; retained old windows and final-result backpressure | Commit `2dabd8e`; `docs/STAGE2N_A7_KERNEL_PIPELINE_INTEGRATION.md`; `docs/PRE_A13_REVALIDATION_V1.md` | Local Vivado 2022.1 XSim revalidation PASS, two runs |
| Stage 2N-A8 | Package and link the A7 kernel | Restored canonical XO/link flow for the user-managed kernel and recorded the historical F37X link contract | Commit `6b2303d`; `docs/STAGE2N_A8_ACCEPTED_XO_XCLBIN.md` | Historical build record; generated XO/xclbin not retained in current source tree |
| Stage 2N-A9 | Run protected automatic-pipeline board smoke | Added device-guarded Host/runner/evidence flow for one-command execution and backpressure | Commit `3cc1997`; `docs/STAGE2N_A9_PROTECTED_BOARD_SMOKE.md` | Historical code/summary exists; recovery did not independently rerun its original board evidence |
| Stage 2N-A10 | Expand the automatic pipeline to the trained-model shape | Canonical v2 supports 8 descriptors, 2048 weights, 128 biases and `8->16->8`, `5x8->18`, `18->32->16->1`; local revalidation ran twice with final result 36 and backpressure | Commits `1c5fabb`, `2fa7e88`; `docs/STAGE2N_A10_CAPACITY_EXPANSION_V2.md`; `docs/PRE_A13_REVALIDATION_V1.md` | Canonical v2 local XSim PASS; old non-v2 files are not canonical |
| Stage 2N-A11 | Build and validate a trained-model batch asset | Corrected the `F37XPB1` magic contract; regenerated and parsed 256 samples with Bottom, Interaction, and Top software-golden exactness | Commit `59e3d23`; `docs/PRE_A13_REVALIDATION_V1.md`; A11 asset docs | Software-golden PASS for 256 samples; historical board regression was not independently rerun during recovery |
| Stage 2N-A12 | Measure Host-visible automatic-pipeline performance | Restored Host benchmark, runner, and evidence collector with separate programming/start/wait/result/retire timing boundaries | Commit `f629642`; A12 benchmark documents | Measurement flow present; do not reuse unretained historical performance numbers as current evidence |
| Stage 2N-A13 | Add observable hardware cycle counts without changing arithmetic | Added Bottom, Interaction, Top, and Total 32-bit saturating counters; completed target build, 100 MHz timing, xclbin, protected F37X board validation, and 256-sample exact regression | Commit `be33ba0`/main equivalent `63ae1c4`; `docs/STAGE2N_A13_FINAL_ACCEPTANCE.md`; `docs/A13_FINAL_STATUS.txt` | **FINAL PASS; accepted and frozen** |
| Stage 2N-A14 | Prototype FPGA-side embedding lookup | Added 64-row INT16 lookup asset, standalone single-outstanding AXI4 read master, AXI4-Lite kernel wrapper, self-checking lookup/wrapper XSim, packaging plan, and future single-bank link config | Commits `a19d338`, `50a97bc`; `docs/STAGE2N_A14_*.md`; A14 RTL/TBs/config/model | Simulation prototype PASS; exact-target V3 XO diagnosed the missing global-memory/table-base ABI; no Vitis link, xclbin, physical HBM, A13 integration, or board validation |
| Stage 2N-A14.5 | Add and validate a runtime HBM table-base ABI | Added versioned v2 lookup/wrapper with 64-bit `TABLE_BASE`, base-plus-row addressing, invalid-base/overflow guards, independent TBs, and XSim/XO-only validation runners | Commits `29401e5`, `d428e8b`, `de9276e`, tested target HEAD `4096614`; `docs/STAGE2N_A14_5_TARGET_XO_ACCEPTANCE.md`; retained evidence under `docs/evidence/stage2n_a14_5/` | **Local XSim PASS and exact-VU37P XO-only PASS**: lookup 67/67, wrapper 17/17, 12,951-byte target XO, TABLE_BASE ABI and cross-layer 64-bit metadata accepted. No v++, xclbin, Host, physical HBM, board, performance, or A13 integration |
| Stage 2N-A14.6 | Link the accepted v2 XO without device access | Linked the exact accepted XO as one CU to HBM[0], produced and validated a hardware xclbin, and completed exact-VU37P routing at 100 MHz | Tested target HEAD `b44855e`; `docs/STAGE2N_A14_6_LINK_ONLY_ACCEPTANCE.md`; A14.6 runner/validator; curated returned evidence under `docs/evidence/stage2n_a14_6/` | **LINK-ONLY PASS**: v++/xclbin/HBM[0] metadata/timing PASS; WNS/TNS 0.000 ns and zero failing endpoints. No Host, device access, physical HBM, board, performance, or A13 integration |

| Stage 2N-A14.7 | Validate one protected physical-HBM lookup | Added legacy-HAL BO/paddr/TABLE_BASE Host, canonical 1024-byte payload, protected runner and evidence validator; completed one F37X HBM[0] row-37 lookup and cleanup | `docs/STAGE2N_A14_7_HBM_SINGLE_TABLE_HOST_PREPARATION_V1.md`; final A14.7 acceptance in `docs/CURRENT_STATE.md`; retained evidence hashes | **FINAL PASS** for the standalone physical lookup: lanes `[40,41,42,43,44,45,46,47]` exact, BO released and HBM[0] returned to zero usage. No A13 integration or performance claim |
| Stage 2N-A15.1 | Connect the accepted HBM lookup result to the A13 pipeline locally | Added a versioned controller-level wrapper: A14 v2 response owns A13 slot0, Host retains slots1-3, successful data is retained until ready, and error/busy/ownership guards preserve state | Authorization/baseline `2020e4c`; `docs/STAGE2N_A15_1_HBM_PIPELINE_INTEGRATION_V1.md`; local XSim status/logs | **LOCAL XSIM PASS**: nine behavioral/ABI markers, zero warnings and zero anchored error/fatal records. No public target top, target build/link, xclbin, FPGA access, physical A15 HBM, full prediction golden, or performance claim |
| Stage 2N-A15.2 | Execute one complete inference using the HBM-owned slot0 path | Reused the A15.1 wrapper and accepted A13 sample; fetched a fake-memory row into slot0, observed the exact Interaction vector loads, ran Bottom/Interaction/Top, and compared against an independent golden | Baseline `876046c`; `docs/STAGE2N_A15_2_END_TO_END_PIPELINE_XSIM_V1.md`; local XSim status/logs | **LOCAL XSIM PASS**: expected/actual result 36, cycles 322/100/744/1174, all 11 markers and zero warnings/errors/fatals. No new RTL, public target top, target build/xclbin, FPGA/physical HBM, board, or performance claim |
| Stage 2N-A15.3 | Supply all four A13 embedding slots through one sequential lookup engine | Added a versioned controller wrapper that requests canonical rows 37–40, retains each response until A13 accepts it, injects slots 0–3, rejects Host embedding writes, and runs the accepted full pipeline after the mask reaches `4'hF` | Baseline `b3031d4`; `docs/STAGE2N_A15_3_ALL_HBM_EMBEDDING_PIPELINE_XSIM_V1.md`; retained local status/logs | **LOCAL XSIM PASS**: 4 logical requests/AR/R/injections, all four exact vectors, independent 18-value Interaction golden, result 36, cycles 322/100/744/1174, and zero warnings/errors/fatals. No target build/link, xclbin, FPGA/physical HBM, multi-bank, board, or performance claim |
| Stage 2N-A15.4 | Expose the accepted all-HBM local pipeline through a public F37X-style kernel boundary | Added a versioned AXI4-Lite plus one `m_axi_gmem` top, preserved the entire A13 ABI, added disjoint `0x300/0x304/0x308` control, and automatically chained the accepted A15.3 load-all sequence into accepted A13 START | Starting/authorization HEAD `7d0c351`; `docs/STAGE2N_A15_4_F37X_KERNEL_ALL_HBM_PIPELINE_XSIM_V1.md`; retained local status/logs | **LOCAL XSIM PASS**: exact TABLE_BASE+rows37–40 addresses/vectors, 4/4/4/4 lookup/AR/R/injections, mask `0xF`, result 36, counters 322/100/744/1174, zero warning/error/fatal/assertion records. No target build/link, XO/xclbin, FPGA/physical HBM, board, or performance claim |
| Stage 2N-A15.5 | Package and link the accepted A15.4 public kernel for the exact F37X target and correct Vitis 2020.2 offline validation | Built/validated the exact-target XO, linked one CU to HBM[0], generated the fixed-SHA xclbin, corrected the v1 shell-IP false negative, and revalidated metadata/timing without rebuild | Source-build commit `30cbf64`; validator/revalidation commit `2ce2d44`; `docs/STAGE2N_A15_5_TARGET_XCLBIN_FINAL_ACCEPTANCE_V1.md`; curated raw evidence under `docs/evidence/stage2n_a15_5/` | **FINAL TARGET XO/XCLBIN/TIMING PASS**: unique kernel/CU, TABLE_BASE/arg0 to used HBM[0], xclbin SHA/UUID frozen, 100 MHz WNS/TNS 0.000/0.000 ns, zero failing endpoints. No Host, physical A15 HBM, FPGA/board, or performance result |
| Stage 2N-A15.6 | Prepare protected physical-HBM full-pipeline functional validation using the frozen A15.5 artifact | Added a low-level XRT Host, guarded one-device/HBM[0] runner, five deterministic trained-model payloads, fail-closed evidence validation, and a separate device-free target preflight | Preparation `ee3dcaa`; `docs/STAGE2N_A15_6_PROTECTED_ALL_HBM_BOARD_VALIDATION_PREPARATION_V1.md`; target-preflight preparation document; local evidence under `docs/evidence/stage2n_a15_6/` | **LOCAL AND TARGET-PREFLIGHT SOURCE PREPARATION PASS**: source/assets, five golden cases, evidence fixtures, XRT/ABI/artifact/preflight static gates pass. Target preflight, Host compilation, FPGA programming, physical HBM, board function and performance are NOT RUN/NOT CLAIMED |

## Current Milestone Interpretation

- A13 is the last accepted integrated and board-validated DLRM pipeline.
- A14/A14.5 are newer source work but have a narrower scope: standalone
  embedding lookup and its runtime table-base ABI.
- A14 does not supersede A13 as an integrated inference top.
- The presence of `m_axi_gmem` in the A14 wrapper proves a logical interface and
  simulation behavior only.
- A physical HBM or performance claim requires target link and board evidence.
- A14.5 XSim and corrected exact-target XO-only metadata gates are accepted.
  They do not make Vitis link, xclbin, physical HBM, Host, board execution, or
  performance PASS.
- A14.6 link-only target evidence is accepted: v++, xclbin, HBM[0] link
  metadata, and 100 MHz timing are PASS within that narrow boundary. Physical
  HBM, Host, board, performance, and A13 integration remain unvalidated.

- A14.7 is accepted for one protected standalone physical HBM[0] lookup and
  cleanup. It does not prove A13 integration or performance.
- A15.1 is accepted only as a local controller-level XSim integration: A14 v2
  response data reaches A13 embedding slot0, while slots1-3 retain Host
  ownership. It does not yet establish a public target top, physical A15 HBM,
  a complete prediction golden, or performance.
- A15.2 is accepted as one complete local deterministic inference using that
  slot0 path. It proves functional consumption by Bottom–Interaction–Top, but
  does not promote A15 to a target, xclbin, physical-HBM, board, or performance
  result.
- A15.3 is accepted as a local sequential four-row proof through one A14 v2
  engine and one fake AXI memory. It supplies all four A13 embedding slots and
  proves full-pipeline golden agreement, but it does not prove a target top,
  physical HBM, multi-bank parallelism, board execution, or performance.
- A15.4 is accepted as a public local kernel-composition proof. It preserves A13
  and exposes one `m_axi_gmem`, but it has not been synthesized, packaged,
  linked, or executed for F37X and does not prove physical HBM or performance.
- A15.5 is accepted for the exact-target XO, Vitis link/xclbin, static HBM[0]
  mapping, and 100 MHz routed timing. The validator-v1 failure was a shell-IP
  counting false negative; fixed-SHA v2 revalidation passed without rebuild.
  Host, physical A15 HBM, FPGA/board function, and performance remain unproven.
- A15.6 is accepted only as local protected-board preparation. Its five golden
  cases distinguish all four HBM-derived slots and its safety/evidence fixtures
  pass. A separate device-free target-preflight source is also locally accepted,
  but its target run, Host binary, device action, physical HBM transaction,
  board function, cleanup, and performance remain unaccepted.

## Superseded and Historical Files

The working tree intentionally retains old, duplicate, recovery, and patent
materials. Stage-specific documents identify canonical versions, especially
for A8–A12. Do not delete those files, do not run `git clean`, and do not select
a file merely because it has the highest-looking suffix. Start from the source
map in `docs/ARCHITECTURE.md` and the active-stage documents.

## Stage 2N-A14.7 — Protected physical-HBM single-table lookup

Date: 2026-08-26

Result: `PASS`

A14.7 completed the first accepted physical F37X HBM embedding lookup in Stage 2N.

Key milestones:
1. prepared target-compatible low-level XRT Host;
2. generated and verified canonical 1024-byte table payload;
3. built Host successfully against XRT `2.9.210507` / GCC `4.8.5`;
4. protected target index `2`, BDF `0000:9b:00.1`, renderD129, UUID, CU and HBM[0];
5. loaded the accepted A14.6 xclbin during the first protected attempt;
6. identified a zero-byte Host artifact before any valid physical lookup completed;
7. rebuilt the formal Host ELF and recovered the accepted SHA256;
8. performed one valid physical HBM[0] lookup;
9. obtained exact 8-lane software-golden agreement;
10. released the BO and confirmed HBM[0] returned to zero usage;
11. hardened the protected runner with runtime Host artifact SHA binding;
12. validated the hardened guard to the authorization boundary without performing another physical lookup.

Accepted functional result:
- lookup index: `37`
- actual: `[40,41,42,43,44,45,46,47]`
- expected: `[40,41,42,43,44,45,46,47]`
- result match: `PASS`

Evidence:
- functional evidence SHA256: `644155ffc1c4e40456a52a2a8ca3a84765b1ce685b9d377138bdd25b6871d2d2`
- board PASS log SHA256: `cecce17484def1645938b14df8f9b1744e13bf67ea9e4af3ab3ab25dbef54ca5`
- final guard log SHA256: `9c7db499b84444d278c3be195439fa0984b144cb4586930112f2a2ba7755e368`

Final source baseline before A14.7 documentation closure:
`70179f66c6fab8a28c2305c024bec3fa43f9c508`

Next at A14.7 closure:
begin the separately authorized A13/A14 integration stage. The resulting local
controller-level outcome is recorded below as A15.1.

## Stage 2N-A15.1 — Local HBM-to-pipeline controller integration

Date: 2026-08-26

Result: `LOCAL XSIM PASS`

A15.1 added a new versioned controller-level wrapper while preserving the
accepted A13 and A14 v2 RTL. Successful lookup data is retained and injected as
A13 embedding slot0; Host configuration continues to own slots1 through 3.
The fake-memory XSim verifies exact row-37 lane order, loaded mask `4'hF`,
delayed-ready retention, lookup error preservation, busy-request rejection,
Host slot0 rejection, and unchanged cycle-counter ABI offsets.

Accepted marker:
`STAGE2N_A15_1_HBM_PIPELINE_INTEGRATION_V1_PASS`.

Next:
separately authorize public kernel/control integration and complete functional-
golden verification. Do not infer A15 target, xclbin, board, physical HBM, or
performance validation from this local result.

## Stage 2N-A15.2 — Local HBM-backed end-to-end inference

Date: 2026-08-26

Result: `LOCAL XSIM PASS`

A15.2 reused the A15.1 wrapper and accepted A13 cycle-counter sample without
modifying RTL. Local fake-memory row 37 replaced the old Host source for the
same all-zero slot0 vector. The bench observed vector0 `[1..8]` from Bottom,
vector1 from HBM-owned slot0, and vectors2 through 4 from Host slots1 through 3,
then completed Interaction and Top.

Accepted result:
- expected/final: `36/36`;
- Bottom/Interaction/Top/Total: `322/100/744/1174` cycles;
- controller overhead: 8 cycles;
- final marker: `STAGE2N_A15_2_END_TO_END_PIPELINE_XSIM_V1_PASS`.

Next:
broaden functional-golden coverage and separately authorize public target-top
integration. Target build/link, xclbin, device/physical HBM, board, and
performance remain outside this local milestone.

## Stage 2N-A15.3 — Local all-HBM-embedding pipeline integration

Date: 2026-08-27

Result: `LOCAL XSIM PASS`

A15.3 added a versioned orchestration wrapper around the unchanged accepted
A14 v2 lookup engine and A13 cycle-counter pipeline. One lookup engine issued
four sequential requests for canonical rows 37, 38, 39, and 40. Each response
was retained until the accepted A13 embedding configuration handshake wrote it
to slot 0, 1, 2, or 3 respectively. The loaded mask reached `4'hF` before the
accepted START gate admitted the full Bottom–Interaction–Top inference.

Accepted embedding vectors:
- slot 0: `[40,41,42,43,44,45,46,47]`;
- slot 1: `[48,49,50,51,52,53,54,55]`;
- slot 2: `[56,57,58,59,60,61,62,63]`;
- slot 3: `[64,65,66,67,68,69,70,71]`.

Accepted functional result:
- independent Interaction golden:
  `[1,2,3,4,5,6,7,8,1608,1896,17964,2184,20748,24556,2472,23532,27852,32172]`;
- expected/final result: `36/36`;
- Bottom/Interaction/Top/Total: `322/100/744/1174` cycles;
- logical requests/AXI AR/AXI R/injections: `4/4/4/4`;
- final marker:
  `STAGE2N_A15_3_ALL_HBM_EMBEDDING_PIPELINE_XSIM_V1_PASS`.

The retained local XSim also covers response retention under backpressure,
busy/repeated request rejection, error preservation, Host embedding-write
rejection, the pre-`4'hF` START guard, unchanged pipeline behavior, and the
cycle-counter offsets `0x218`, `0x21C`, `0x220`, and `0x224`. `xvlog`, `xelab`,
and `xsim` exited zero with zero warnings and zero anchored error/fatal records.

Next:
separately authorize A15.4 public target-top and build preparation. A15.3 does
not prove target build/link, XO/xclbin, physical HBM, FPGA/board behavior,
multi-bank parallelism, or performance.

## Stage 2N-A15.4 — Public F37X kernel all-HBM pipeline integration

Date: 2026-08-27

Result: `LOCAL XSIM PASS`

A15.4 adds a new versioned public AXI4-Lite plus `m_axi_gmem` top around the
unchanged accepted A15.3 composition. It keeps the complete A13 register map and
counter offsets and adds only A15 control/status at `0x300` plus 64-bit
TABLE_BASE at `0x304/0x308`. One A15 START performs four sequential reads,
injects slots0–3, waits for loaded mask `4'hF`, then starts the accepted A13
Bottom–Interaction–Top pipeline.

Accepted local result:

- TABLE_BASE: `0x0000000123456000`;
- rows/addresses: 37/`0x...6250`, 38/`0x...6260`, 39/`0x...6270`,
  40/`0x...6280`;
- lookup/AR/R/injections: `4/4/4/4`;
- exact slot vectors: `[40..47]`, `[48..55]`, `[56..63]`, `[64..71]`;
- final mask: `0xF`;
- expected/actual result: `36/36`;
- Bottom/Interaction/Top/Total: `322/100/744/1174`;
- final marker:
  `STAGE2N_A15_4_F37X_KERNEL_ALL_HBM_PIPELINE_XSIM_V1_PASS`.

The public-port bench also covers reset, early and mid-sequence read errors,
repeated START, delayed ARREADY/RVALID, Host embedding rejection, START gating,
and A13 ABI preservation. Tool return codes are `0/0/0` with zero warnings,
errors, fatals, or assertion-failure records.

Next:
separately authorize A15.5 target packaging/link preparation. A15.4 does not
prove target build/timing/link, XO/xclbin, device or physical HBM access, board
execution, multiple banks, Host runtime, or performance.

## Stage 2N-A15.5 — Final target XO/xclbin acceptance

Date: 2026-08-28

Result: `FINAL TARGET XO/XCLBIN/TIMING PASS`

A15.5 freezes the accepted A15.4 public top and its 17-file RTL source closure.
Its user-managed metadata declares only 64-bit TABLE_BASE at `0x304` as a
global pointer associated with the single 64-bit-address/128-bit-data
`m_axi_gmem`. The complete accepted A13/A15 raw register map remains unchanged,
including counters `0x218/0x21C/0x220/0x224` and A15 control
`0x300/0x304/0x308`.

The prepared target contract is one kernel
`dlrm_f37x_rtl_kernel_stage2n_a15_v1`, one CU `dlrm_a15_1`, one mapping
`dlrm_a15_1.m_axi_gmem:HBM[0]`, exact part `xcvu37p-fsvh2892-2L-e`, reviewed
platform `inspur_f37x_xdma_201920_3`, and requested 100 MHz. Local positive and
negative validator fixtures pass. Bash is unavailable on the local Windows
host, so local `bash -n` remains `NOT_RUN`; the controlled target-side runner
itself completed successfully.

The controlled target flow produced accepted XO/xclbin SHA256 values
`a88fd4b...ee019` and `23ee48c...2356`, with xclbin UUID
`1b555645-a9e2-4f5e-95af-6ce4adacbc3c`. The fixed artifact passed v2 metadata
revalidation and 100 MHz routed timing with WNS/TNS `0.000/0.000 ns` and zero
failing endpoints. Fifty-five methodology critical warnings remain recorded.

Next:
the fixed-SHA xclbin passed non-rebuilding v2 revalidation. The v1 false
negative counted shell IP entries as compute units; v2 requires one filtered
`IP_KERNEL` and the sole TABLE_BASE/arg0 connection to used `HBM[0]`. Stage
A15.6 may be prepared separately for protected FPGA programming, Host/XRT,
physical HBM[0], four sequential lookups, and full DLRM functional board
validation. Performance remains unclaimed because the 1174-cycle counters do
not include the four HBM lookups.

## Stage 2N-A15.6 — Protected all-HBM board validation preparation

Date: 2026-08-28

Result: `LOCAL PREPARATION PASS`

A15.6 consumes, but does not rebuild, the frozen xclbin SHA256
`23ee48c91b3dfb5b68b3372ac49fc6607f203cf01d3b9fcfe04b4ea42be02356`
and UUID `1b555645-a9e2-4f5e-95af-6ce4adacbc3c`. The accepted A15.4 wrapper
SHA256 remains
`c3da5be63d4cf195df124e572887b6aa96a464522883c6cdc95c4bd56ff4e8a1`.

The prepared flow uses one explicit F37X device/BDF, one 1,024-byte BO in
linked `HBM[0]`, the accepted TABLE_BASE ABI, rows 37 through 40, and the
accepted A13 model/result/counter ABI. The runner checks exact artifact and
device identity, firewall/CU/owner/HBM-use state, and requires a literal `yes`
before any device-changing action. It neither resets the FPGA nor performs
global cleanup or another-device access.

The software reference produces one baseline result `-393` and four
slot-sensitivity results `-392`, `-93`, `-689`, and `-519`. Each perturbation
changes only one HBM row/embedding slot, and the five expected results are
distinguishable. Local deterministic generation, source validation, positive
evidence assembly/validation, and eight negative fixtures pass.

Next:
under separate explicit authorization, the user may compile the Host and run
the protected five-case flow in the controlled target environment, then return
the complete evidence package for a separate review. Until that happens,
FPGA programming, Host execution, physical HBM, board function, cleanup, and
performance remain `NOT_RUN`, `NOT_VALIDATED`, or `NOT_CLAIMED`.

Target-preflight update, 2026-08-31:
a separate versioned, device-free preflight and static validator are prepared.
They validate Git ancestry/clean tracked state, frozen RTL, XRT 2020.2 Host
build readiness, fixed xclbin SHA/UUID/kernel/CU/HBM[0] metadata, all seven
tracked model/table/manifest assets, the A15/A13 ABI, and the protected runner.
Local source validation passes. Bash syntax and the target preflight remain
`NOT_RUN`; the next action is a user-controlled Git-bundle fast-forward and
preflight run, not board execution.
