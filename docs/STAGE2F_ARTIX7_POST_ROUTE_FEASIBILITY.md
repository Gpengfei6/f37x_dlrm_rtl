# Stage 2F — Artix-7 OOC Post-Route Implementation Feasibility

## Status

**Flow prepared; actual Stage 2F post-route result is pending execution and evidence review.**

This stage starts from commit `334753d`, after closing the Vivado 2020.2
Stage 2E reproduction.

## Fixed scope

- Top module: `mlp_sequence_controller`
- Part: `xc7a200tfbg484-2`
- Clock: 10.000 ns / 100 MHz
- Implementation mode: out-of-context
- Primary server tool: Vivado 2020.2
- Optional local reproduction tool: Vivado 2022.1

Stage 2F reuses the Stage 2C source set and
`constraints/stage2c_mlp_clock.xdc`. It must not change the RTL,
multilayer contract, INT8 quantization, rounding, saturation, ReLU, or
configuration validation semantics.

## Flow

The implementation flow is:

1. Read the Stage 2C RTL sources and 100 MHz XDC.
2. Run `synth_design -mode out_of_context`.
3. Run `opt_design`.
4. Run `place_design`.
5. Run `phys_opt_design`.
6. Run `route_design`.
7. Save post-synthesis, post-optimization, post-placement,
   post-physical-optimization, and post-route checkpoints.
8. Generate post-route timing, utilization, route-status, DRC,
   methodology, clock-utilization, high-fanout, congestion, and power
   reports.
9. Generate `stage2f_post_route_status.txt`.

## Acceptance conditions

Stage 2F can be called post-route PASS only when all of the following
are evidenced:

- `ROUTE_STATE=ROUTE_COMPLETE`
- `UNROUTED_NETS=0`
- setup WNS is non-negative
- setup failing endpoints are zero
- hold WHS is non-negative
- hold failing endpoints are zero
- `TIMING_STATE=TIMING_MET`
- post-route checkpoint exists
- anchored Vivado `ERROR:` count is zero
- any anchored `CRITICAL WARNING:` lines have been reviewed
- no latches are inferred

## Commands

Local Windows execution:

```powershell
Set-Location "D:\FpgaWork\f37x_dlrm_rtl"

powershell `
  -ExecutionPolicy Bypass `
  -File ".\scripts\run_stage2f_post_route.ps1"
```

Server Vivado 2020.2 execution:

```bash
cd /home/chaosuan/gpf/gpf_f37x_dlrm/f37x_dlrm_rtl_stage2e

bash scripts/run_stage2f_post_route.sh
```

The server directory name may remain `f37x_dlrm_rtl_stage2e`; the Git
branch and commit identify the Stage 2F source revision.

## Evidence to record after execution

- Vivado version and build
- Git branch and commit
- post-route route state
- unrouted-net count
- setup WNS, TNS, failing endpoints, and total endpoints
- hold WHS, THS, failing endpoints, and total endpoints
- Total LUTs, Logic LUTs, LUTRAMs, FFs, RAMB36, RAMB18, and DSP blocks
- latch count
- DRC and methodology findings
- congestion and high-fanout observations
- anchored error and critical-warning counts
- checkpoint and report paths

## Boundary

This stage is an Artix-7 OOC implementation feasibility check. It does
not include:

- a VU37P/F37X target build
- PCIe, DDR, HBM, shell, or board-clock integration
- `.xclbin` generation
- full platform implementation
- board programming or runtime validation

A successful Stage 2F result must not be described as F37X board
success.
