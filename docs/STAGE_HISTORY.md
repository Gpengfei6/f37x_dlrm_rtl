# Stage 2N History

This table is an AI-readable index of Stage 2N-A1 through A14. It does not turn
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
| Stage 2N-A14.6 | Link the accepted v2 XO without device access | Freeze an exact-XO, one-CU, `m_axi_gmem -> HBM[0]`, 100 MHz F37X link-only flow with non-overwriting evidence gates | `docs/STAGE2N_A14_6_LINK_ONLY_PLAN.md`; A14.6 authorization in `AGENTS.md` | **Planning/authorization PASS; implementation pending**. No v++, xclbin, timing, Host, device, physical HBM, board, performance, or A13 integration result yet |

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
- A14.6 authorizes only a separately versioned link-only flow. Until returned
  target evidence is reviewed, its v++, xclbin, HBM[0] link metadata, and
  timing statuses remain NOT RUN.

## Superseded and Historical Files

The working tree intentionally retains old, duplicate, recovery, and patent
materials. Stage-specific documents identify canonical versions, especially
for A8–A12. Do not delete those files, do not run `git clean`, and do not select
a file merely because it has the highest-looking suffix. Start from the source
map in `docs/ARCHITECTURE.md` and the active-stage documents.
