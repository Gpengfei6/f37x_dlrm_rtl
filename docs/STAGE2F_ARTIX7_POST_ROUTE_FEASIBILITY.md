# Stage 2F Artix-7 post-route feasibility

## Status

The reproducible Stage 2F flow is implemented and the local Vivado 2022.1
precheck passes. The exact Vivado 2020.2 post-route reproduction is still
pending and Stage 2F is therefore not closed for the target tool version.

No RTL, testbench, constraint, Python expected value, or test vector changed in
this stage. The implemented design remains the Stage 2D source at the Stage 2E
documentation head.

## Frozen configuration

- top: `mlp_sequence_controller`
- part: `xc7a200tfbg484-2`
- clock: 10.000 ns / 100 MHz
- implementation mode: out of context
- synthesis options: the same `out_of_context`, `flatten_hierarchy rebuilt`,
  and `Default` directive used by `scripts/run_synth_stage2c.tcl`
- constraint: `constraints/stage2c_mlp_clock.xdc`
- ordered RTL set: `rv_fifo.sv`, `runtime_relu_quant.sv`, `mac_lane.sv`,
  `banked_activation_buffer.sv`, `local_weight_provider.sv`,
  `vector_dot_product_core.sv`, `dense_layer_engine.sv`, and
  `mlp_sequence_controller.sv`

The Tcl driver runs `synth_design`, `opt_design`, `place_design`,
`phys_opt_design`, and `route_design`. It writes post-synthesis, post-opt,
post-place, and post-route checkpoints plus timing, utilization, route status,
DRC, methodology, clock utilization, high-fanout, congestion, and power
reports. Generated state is recreated under `work/stage2f` and
`results/stage2f`; checkpoints and reports are intentionally ignored by Git.

## Reproduction

Local Windows precheck with automatic Vivado discovery:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run_stage2f_post_route.ps1
```

An explicit local executable or repository-contained result directory can be
selected with `-VivadoExe` and `-ResultDir`. The wrapper rejects result paths
outside the repository, preserves the full Vivado console log, audits only
line-start `ERROR:` and `CRITICAL WARNING:` records, and requires the complete
checkpoint/report set and machine-readable acceptance status.

For the future server reproduction, the user can invoke the same Tcl under the
Stage 2E authenticated Vivado 2020.2 executable:

```text
/opt/Xilinx/Vivado/2020.2/bin/vivado -mode batch -nojournal \
  -log logs/vivado_stage2f_post_route.log \
  -source scripts/run_stage2f_post_route.tcl
```

This command is provided for user execution only. Codex did not access or run
the server.

## Local Vivado 2022.1 evidence

The final flow was run twice locally after the script audit. Both executions
returned the same acceptance metrics. The final reviewed run identifies:

- executable:
  `D:\vivado2022\vivado2022forwins\Vivado\2022.1\bin\vivado.bat`
- Vivado v2022.1 64-bit, SW Build 3526262, IP Build 3524634
- `SYNTH`, `OPT`, `PLACE`, `PHYS_OPT`, and `ROUTE`: `COMPLETE`
- route state: fully routed, 0 unrouted or partially routed nets
- setup: WNS +0.597 ns, TNS 0.000 ns, 0 failing endpoints
- hold: WHS +0.098 ns, THS 0.000 ns, 0 failing endpoints
- latch count: 0
- anchored log records: 0 errors, 0 critical warnings
- timing state: `TIMING_MET`
- power report: completed; vectorless estimate 0.157 W, not a measured board
  power result

The acceptance rule is deliberately strict: `TIMING_MET` is emitted only when
routing completes, the unrouted-net count is zero, both setup and hold have
zero failing endpoints, and WNS/WHS are non-negative. The PowerShell wrapper
also fails on a nonzero tool exit, missing status/artifacts, DRC errors, or
line-start Vivado errors.

### Resources and Stage 2E comparison

| Metric | Stage 2E post-synthesis OOC, Vivado 2020.2/2022.1 | Stage 2F post-route OOC, local Vivado 2022.1 | Change |
|---|---:|---:|---:|
| Total LUT | 4,550 | 4,320 | -230 |
| Logic LUT | 4,530 | 4,300 | -230 |
| LUTRAM | 20 | 20 | 0 |
| FF | 1,946 | 1,946 | 0 |
| RAMB36E1 | 17 | 17 | 0 |
| RAMB18E1 | 32 | 32 | 0 |
| DSP48E1 | 21 | 21 | 0 |
| Setup WNS | +0.758 ns | +0.597 ns | -0.161 ns |
| Setup TNS | 0 ns | 0 ns | 0 ns |
| Setup failing endpoints | 0 | 0 | 0 |

Post-route optimization removes 230 logic LUTs while preserving the Stage 2C
memory mapping and Stage 2D DSP count. The 17 RAMB36E1 and 32 RAMB18E1 totals
remain consistent with 16 weight banks, one bias RAM, and 32 activation banks.

### Worst path

The post-route setup worst path is from the DSP48E1
`u_dense_layer_engine/provider_weight_req_address` output to
`u_dense_layer_engine/u_weight_provider/weight_rsp_error_reg`. It is the same
weight-request range-check path class identified after Stage 2D synthesis, not
the retired runtime-quantization-to-activation path. The path has 9.360 ns data
delay, 13 logic levels, 6.133 ns logic delay, and 3.227 ns route delay.

### DRC, methodology, congestion, and fanout

- DRC: 0 errors, 0 critical warnings, 44 ordinary warnings. These are
  `CFGBVS-1` (1), `DPIP-1` (32), `DPOP-1` (5), `DPOP-2` (5), and `RTSTAT-10`
  (1).
- methodology: 0 critical warnings, 593 ordinary warnings. These are
  `SYNTH-6` (38), `SYNTH-11` (5), `SYNTH-12` (16), and `TIMING-18` (534).
- congestion: no placer or initial-router congestion window above level 5.
- highest reported non-clock fanout: 1,363 on a vector-dot control net;
  `rst` fanout is 624 and the descriptor input-buffer control fanout is 266.

The DSP/RAM pipelining warnings are retained as review evidence rather than
hidden. Timing still meets after route. `CFGBVS-1`, `TIMING-18`, and ordinary
`Route 35-198` messages arise from the deliberate OOC boundary: board voltage,
I/O delays, pins, and `HD.PARTPIN_LOCS` are not invented in this flow.

## Evidence boundary and next action

This result proves that the frozen MLP controller can be placed and internally
routed on `xc7a200tfbg484-2` by local Vivado 2022.1 with positive 100 MHz setup
and hold slack. Because OOC ports have no board pin/part-pin or I/O-delay model,
it does not establish accurate timing to or from the top-level ports.

Still not completed:

- the same Stage 2F post-route run under Vivado 2020.2;
- a board-level/full top implementation with real clock and I/O constraints;
- F37X/VU37P compilation or platform integration;
- `.xclbin` generation;
- F37X board execution, functional validation, timing, or power measurement.

The next Stage 2F action is user execution of the checked-in Tcl under the
authenticated Vivado 2020.2 environment and return of the status file and
lightweight reports for exact version comparison.
