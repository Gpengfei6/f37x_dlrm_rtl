# Stage 2E Vivado 2020.2 reproduction review

## Status and evidence boundary

Stage 2E exact-source reproduction is complete and passes under Vivado 2020.2.
The returned server evidence covers the Phase 1, Stage 2A, and Stage 2B Python
regressions, Stage 2A and Stage 2B XSim, and 10.000 ns out-of-context synthesis
of `mlp_sequence_controller` for `xc7a200tfbg484-2`.

The evidence archive `stage2e_vivado2020_evidence.tar.gz` has SHA-256
`6819538778D5E25B702188503C5042F28A01D0ACC9C157475D4F646884584DE4`.
Its extracted copy under `local_results/stage2e_vivado2020/` was audited as a
read-only local input and remains untracked. No server or network access was
used during this audit.

This is compile, simulation, and post-synthesis OOC evidence. It is not a full
implementation or place-and-route result, not a VU37P/F37X target compile, not
an `.xclbin`, and not board-execution evidence.

## Tool and source identity

The server evidence records:

- executable: `/opt/Xilinx/Vivado/2020.2/bin/vivado`;
- version: Vivado v2020.2, SW Build 3064766, IP Build 3064653;
- Python: 3.10.12;
- repository: `/home/chaosuan/gpf/gpf_f37x_dlrm/f37x_dlrm_rtl_stage2e`;
- branch: `work/stage2e-vivado2020-repro`;
- source head: `fff6bd8 docs: record Stage 2E reproduction boundary`.

The recorded source chain continues through `8a4e8ca`, `f566b83`, `1e3bbf7`,
and `539b406`. The Stage 2D RTL base is therefore source-matched to the local
review. No evidence indicates a tracked source modification on the server.
The server status was not completely clean: it contained untracked XSim WDBs,
`webtalk*.log`, `xelab.log`, `xsim*.log`, and `xvlog.log`. These are generated
simulation artifacts and were not added to this repository.

## Audited evidence

The audit cross-checked the following returned files:

- `STAGE2E_SERVER_SUMMARY.txt`;
- `python/phase1_python.txt`, `python/stage2a_python.txt`, and
  `python/stage2b_python.txt`;
- `results/xsim_stage2a_status.txt` and
  `results/xsim_stage2b_status.txt`;
- `logs/xsim_stage2b.log` and `logs/vivado_stage2e_2020_2.log`;
- `results/stage2c/stage2c_synth_status.txt`;
- the Stage 2C utilization, RAM utilization, timing summary, `check_timing`,
  high-fanout, methodology, and DRC reports.

Every synthesis report identifies Vivado v2020.2 build 3064766. The raw reports
and the version-aware Stage 2E parser agree on all resource, timing, RAM, DRC,
methodology, and high-fanout values.

## Functional regression

| Suite | Vivado 2020.2 server result |
|---|---|
| Phase 1 Python | PASS, 24 deterministic cases |
| Stage 2A Python | PASS |
| Stage 2B Python | PASS, 11 valid and 9 invalid cases |
| Stage 2A XSim compile | PASS |
| Stage 2A XSim elaborate/simulate | PASS, 6/6 benches |
| Stage 2B XSim compile/elaborate/simulate | PASS |
| Stage 2B exact result | PASS, `valid=11 invalid=9 total=20` |
| OOC synthesis | PASS, `STAGE2C_SYNTH_COMPLETE` |
| Line-start error / critical warning | 0 / 0 |

## OOC synthesis and RAM inference

Synthesis reports `STAGE2C_SYNTH_COMPLETE` for
`mlp_sequence_controller`, part `xc7a200tfbg484-2`, at 10.000 ns. Resource and
RAM inference are:

- 4,550 total LUT, including 4,530 logic LUT and 20 LUTRAM; zero SRL;
- 1,946 FF, 17 RAMB36E1, 32 RAMB18E1, and 21 DSP;
- 16 independent `4096x8` weight banks in 16 RAMB36E1 blocks;
- one `1024x24` bias RAM in one RAMB36E1 block;
- two activation buffers containing 32 total `64x16` banks in 32 RAMB18E1
  blocks;
- zero inferred latches.

The Stage 2C bank mapping is therefore preserved exactly under Vivado 2020.2.

## Timing and report audit

At 10.000 ns, WNS is +0.758 ns, TNS is 0.000 ns, and zero of 7,008 setup
endpoints fail. Vivado states that all user-specified timing constraints are
met. The worst path remains the met
`provider_weight_req_address/CLK` to `weight_rsp_error_reg/D` path.

`check_timing` reports zero no-clock, constant-clock, unconstrained-internal,
multiple-clock, generated-clock, loop, partial-delay, and latch-loop issues.
The 482 inputs and 44 outputs without I/O delays remain the expected clock-only
OOC boundary.

DRC reports 43 warnings: CFGBVS-1 (1), DPIP-1 (32), DPOP-1 (5), and DPOP-2
(5). Methodology reports 548 warnings: SYNTH-6 (12), SYNTH-11 (2), and
TIMING-18 (534). The highest-fanout net is the vector-dot state decode at 1,363
loads. These OOC warnings do not establish implementation or board closure.

The 908-line Vivado execution log contains zero lines beginning with `ERROR:`
and zero lines beginning with `CRITICAL WARNING:`. Its single occurrence of
`run_synth_stage2c: FAIL` is a Tcl procedure body echoed at source line 40, not
an execution failure. The actual execution ends with the
`run_synth_stage2c: COMPLETE` marker, `TIMING_MET`, worst slack 0.758 ns, and
latch count zero.

## Vivado version comparison

| Metric | Vivado 2020.2 | Vivado 2022.1 | Difference |
|---|---:|---:|---:|
| Total LUT | 4,550 | 4,550 | 0 |
| Logic LUT | 4,530 | 4,530 | 0 |
| LUTRAM | 20 | 20 | 0 |
| SRL | 0 | 0 | 0 |
| FF | 1,946 | 1,946 | 0 |
| RAMB36E1 | 17 | 17 | 0 |
| RAMB18E1 | 32 | 32 | 0 |
| DSP | 21 | 21 | 0 |
| WNS at 10.000 ns | +0.758 ns | +0.758 ns | 0.000 ns |
| TNS | 0.000 ns | 0.000 ns | 0.000 ns |
| Failing setup endpoints | 0 | 0 | 0 |
| Latches | 0 | 0 | 0 |

Vivado 2020.2 and 2022.1 therefore produce identical resources, RAM mapping,
and post-synthesis OOC timing for this reviewed configuration.

## Remaining evidence

- Full implementation and place-and-route have not been run or reviewed.
- Post-route timing has not been established.
- F37X/VU37P target compilation has not been run.
- No `.xclbin` has been generated.
- Board execution has not been validated.
- This result must not be described as F37X board success.
