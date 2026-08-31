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
| Stage 2N-A15.6 | Validate the complete all-HBM pipeline on a real F37X using the frozen A15.5 artifact | Added a low-level XRT Host, guarded one-device/HBM[0] runner, five deterministic trained-model payloads and fail-closed evidence validation; then ran the protected flow on device index 2 | Board-execution source `85ac9d1`; `docs/STAGE2N_A15_6_ALL_HBM_BOARD_FINAL_ACCEPTANCE_V1.md`; compact returned evidence under `docs/evidence/stage2n_a15_6/final_acceptance_v1/` | **FINAL PHYSICAL-HBM BOARD FUNCTION PASS**: frozen xclbin programmed; one 4096-byte HBM[0] BO at valid paddr 0; four sequential lookups; five exact complete-DLRM results; masks/counters/cleanup PASS. Performance NOT CLAIMED |

## Current Milestone Interpretation

- A15.6 is the latest accepted integrated physical-HBM board-functional DLRM
  baseline; A13 remains the frozen dense/compute arithmetic baseline.
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
- A15.6 is the accepted real-board functional baseline for one `HBM[0]` bank,
  one AXI read master and four sequential lookups. The frozen xclbin, physical
  BO/TABLE_BASE path, all five complete-DLRM cases and cleanup pass. The
  1174-cycle interval remains compute-only; multi-bank, parallel lookup and all
  performance claims remain unaccepted.

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
At that preparation point, Bash syntax and the target preflight had not yet run;
the subsequent Final Acceptance below supersedes that preparation status.

## Stage 2N-A15.6 — All-HBM board Final Acceptance

Date: 2026-08-31

Result: `FINAL PASS`

The user-controlled target flow completed on F37X device index 2, BDF
`0000:9b:00.1`, render node `/dev/dri/renderD129`, platform
`inspur_f37x_xdma_201920_3` and XRT `2.9.210507`. It consumed the frozen xclbin
SHA256 `23ee48c91b3dfb5b68b3372ac49fc6607f203cf01d3b9fcfe04b4ea42be02356`
and UUID `1b555645-a9e2-4f5e-95af-6ce4adacbc3c` without rebuild.

One 4096-byte BO was allocated in physical `HBM[0]` at valid paddr `0x0`.
Payload transfer, TABLE_BASE programming/readback, four sequential lookups,
slots 0–3, Bottom, Interaction and Top all completed. Expected/actual results
were `-393/-393`, `-392/-392`, `-93/-93`, `-689/-689`, and `-519/-519`.
Every mask was `0xF` and every counter set was `322/100/744/1174`. BO release
and device close passed; FPGA reset and other-device access did not occur.

The locally recalculated archive SHA256 is
`e903865a26153c5121ab84fe9f5735faa73df4bd73522cf079d1c9d0ae4a0c18`;
the board JSON SHA256 is
`a6d228b78ff1889ccb7a532e22997a6f6f669a024f802e0798271c625b7fe7da`.
The imported JSON passes the existing offline validator.

Next:
preserve this single-bank/single-master/sequential functional baseline. A16 may
separately define lookup and end-to-end timing, measure the sequential baseline
and only then consider multi-bank or parallel lookup. No performance claim is
accepted by A15.6.

## Stage 2N-A16.1 — Sequential HBM lookup latency instrumentation

Date: 2026-08-31

Result: `LOCAL XSIM PASS`

A16.1 adds a versioned local kernel top while leaving the accepted A15.4 RTL
SHA256 and A15.5 xclbin unchanged. Two read-only 32-bit saturating counters are
added: `0x30C` measures first AXI AR handshake through fourth-slot injection,
and `0x310` measures accepted A15 START through first final-result visibility.
The accepted A13 Bottom/Interaction/Top/compute-Total counters at
`0x218/0x21C/0x220/0x224` retain their original meanings.

Two complete Vivado/XSim 2022.1 invocations pass, each with two identical
no-reset restart runs. The deterministic local fake-AXI result is lookup 73,
compute Total 1174, FPGA end-to-end 1285 and pipeline/control overhead 38
cycles, with exact accounting `1285 = 73 + 1174 + 38`. Final result 36,
four-slot ordering, error/busy/backpressure/clear behavior, ABI preservation
and a directed same-RTL saturation test all pass with zero reported warnings,
errors, fatals or assertion failures.

Next:
separately authorize A16.2 before any target build or physical measurement.
The 73-cycle local lookup interval is not physical HBM latency, and A16.1 makes
no latency-improvement, bandwidth, throughput, speedup, power or performance
claim. Multi-bank and parallel lookup remain unimplemented.

## Stage 2N-A16.2 — Target build and physical sequential-latency preparation

Date: 2026-08-31

Result: `LOCAL PREPARATION PASS`

A16.2 prepares, entirely locally, the reviewed target-build and protected
board-measurement flow for the future physical sequential-HBM latency baseline.
It reuses the accepted A15.5 XO/link packaging and the A15.6 XRT Host/protected
board-runner model, plus the frozen A16.1 RTL (`a6eec09c...`) and counter ABI.
The A16 target is `dlrm_f37x_rtl_kernel_stage2n_a16_v1`, CU `dlrm_a16_1`, one
64-bit-address/128-bit-data `m_axi_gmem` master mapped to `HBM[0]`, and only
`TABLE_BASE` (`0x304`) as the kernel pointer argument; the obsolete A14
`LOOKUP_INDEX`/`RESULT0..3` signature is rejected. `0x30C`/`0x310` are custom
AXI4-Lite registers, not Vitis kernel arguments.

The local preparation entry
(`scripts/run_stage2n_a16_2_local_preparation_v1.ps1`) passed: source
validation, ABI validation, protection gate, XO validator self-test (1 positive
+ 9 negative), xclbin validator self-test (Vitis 2020.2 36-entry layout, 1
IP_KERNEL + 35 shell, + 12 negative), board-log validator self-test (1 positive
+ 6 negative), old-Git compatibility scan of the four target shell scripts, and
a manual `bash -n` of those scripts via Git Bash. The protected board runner
requires explicit target index/BDF/render/xclbin/SHA/UUID, checks firewall/
render/HBM[0]/identity, uses an allowlist when the resident UUID differs, and
requires a literal `yes` authorization before programming; it never resets the
FPGA.

`TARGET_XO_BUILD=NOT_RUN_TARGET_REQUIRED`,
`TARGET_XCLBIN_LINK=NOT_RUN_TARGET_REQUIRED`,
`TARGET_TIMING=NOT_RUN_TARGET_REQUIRED`,
`A16_2_PHYSICAL_HBM_LATENCY=NOT_VALIDATED`, and
`A16_2_PERFORMANCE=NOT_CLAIMED`. The frozen A15.4 RTL, A16.1 RTL and A15.5
xclbin are unchanged.

Next:
the user may transfer the reviewed A16.2 files to the controlled target
environment after separate authorization and run, in order, the XO-only build,
the link-only build, the Host XRT 2020.2 build, and the protected board runner,
returning retained status/log/evidence for acceptance review. Establish the
real sequential-HBM latency baseline before evaluating any multi-bank or
parallel design. No physical latency or performance claim is made by A16.2.
