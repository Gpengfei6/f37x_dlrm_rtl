# A17 LUTLP handshake coverage (no new verification framework)

Date: 2026-09-09. Bitstream success after the registered-idle / A15-style START
split proves the LUT loop is gone. It does not by itself prove handshake
semantics. This note maps the three requested properties onto existing tests
and the small TB additions in this increment. A17 public kernel, A13, and A14
RTL were not modified.

LUTLP source: `rtl/pipeline/dlrm_hbm_pipeline_integration_stage2n_a17_v1.sv`
(handshake only). Live XO `a17_6_xo_002` SHA
`15ded79ff75e7a12c464a8b1d65cc863cc6535ead673ba0ba445bb5e69a56be6`.
Current integration-RTL SHA256
`13a12c6ec893ccd2c527304bb16f52210cc92cac129cf94d0fba2073aec9736e`.
Stale XO `a17_6_xo_001` SHA `1bd10d1f…` is superseded and not for execution.

## Requested properties

### 1. START held until ready, accepted once

Covered.

- `tb/tb_dlrm_hbm_pipeline_integration_stage2n_a17_v1.sv` `start_pipeline`
  asserts `pipeline_start_valid` while waiting for ready, then keeps valid
  high for six extra cycles and requires `start_count == start_count_before+1`.
- End of the same bench: `start_count === 2` for two computes.
- `tb/tb_dlrm_f37x_rtl_kernel_stage2n_a17_v1.sv` `A17_2_RESTART` issues
  CLEAR then a second START; counters remain frozen across CLEAR.

Local XSim of this exact TB increment is **PASS**:
`results/stage2n_a17_6/xsim_start_hold_v1/20260909_195952_613/`,
Vivado/XSim 2022.1, xvlog/xelab/xsim RC 0. Markers:
`A17_LUTLP_START_HELD_ONCE=PASS`, `A17_LUTLP_LOAD_DURING_COMPUTE=PASS`,
`A17_LUTLP_STALE_FRESH_GROUP=PASS`, `A17_1_PIPELINE_INTEGRATION_TEST=PASS`.
Local fixture result remains 36; that is not a board golden. TB-only fix:
`before` is a SystemVerilog keyword and was renamed to `start_count_before`.
No RTL change.

### 2. Registered idle lag versus busy / double START

Public kernel source, not Host calling convention.

`a15_state` is a single enum (`A15_IDLE` … `A15_RECOVER`) in
`rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a17_v1.sv`. The integration ports are:

- `load_all_req_valid = (a15_state == A15_LOAD_REQUEST)` (port map ~line 2119)
- `a15_auto_start_valid = (a15_state == A15_PIPE_START)` (line 1091)
- `core_pipeline_start_valid = start_pending || a15_auto_start_valid` (1092–1093)

Those two state equalities cannot both be true.

Sequence after AXI-Lite `A15_CMD_START` (1245–1290):
`IDLE → LOAD_REQUEST → LOAD_WAIT → PIPE_START → PIPE_WAIT → DONE`.
Load is requested only in `LOAD_REQUEST`. Compute START is requested only in
`PIPE_START`, after `hbm_all_loaded`. The idle_q lag cycle is the cycle after
the `PIPE_START` handshake, when the FSM is already `PIPE_WAIT` and
`load_all_req_valid` is 0. A later load requires `CLEAR` to `IDLE` and a new
`A15_CMD_START`. `a15_start_ready` includes `!core_busy`, `!start_pending`,
and `load_all_req_ready` (1073–1089), so the next group cannot start until
compute is idle and `compute_idle_q` is 1.

Direct A13 `PIPE_CMD_START` cannot fill `start_pending` during that window:
`command_pending_any` is true whenever `a15_state != A15_IDLE` (1095–1103),
and `PIPE_CMD_START` faults with `WRAPPER_ERROR_PENDING` if
`command_pending_any` (1558–1562). `A15_CMD_START` also requires
`a15_start_ready`, which includes `!start_pending`, so `LOAD_REQUEST` cannot
begin while `start_pending` is set.

Therefore the packaged kernel never presents `load_all_req_valid` together
with `core_pipeline_start_valid`, and never presents a new load on the
idle_q lag cycle after compute START. This is the kernel sequencer, not a
Host usage note.

The integration TB still drives wrapper ports directly, so it prints
`A17_LUTLP_IDLE_Q_LAG_WINDOW=KERNEL_SEQUENCED_NOT_DRIVEN`. That line means
the TB does not inject the unreachable public-kernel combo; it is not a
Host-usage disclaimer. After START the same bench holds load for four cycles
and requires `!load_all_req_ready && busy`. Holding START valid after the
first ready checks a second compute START is not accepted on lagged idle.
No RTL change in this increment.

### 3. Complete, CLEAR, error drain, next group, stale `fresh_group`

Covered.

- After result hold, START on the old all-loaded bits is rejected
  (`reused stale load token`).
- Error on bank 2: no START, no inject of the failed slot, ACK does not
  expose a stale token; a new load is required before the second compute.
- Public kernel TB: CLEAR, then restart, A16 counters unchanged after CLEAR.

## What bitstream PASS does not prove

`a17_6_link_004` write_bitstream PASS is not a substitute for the tests
above. It only shows the LUTLP-1 net no longer blocks bitstream.

## Evidence boundary

START-hold / once-accept is now a local XSim PASS of the existing A17.1
integration bench. The idle_q lag combo is closed by the public kernel FSM
encoding, not by a new verification framework and not by Host calling
convention. This is still not physical HBM, board, or performance evidence.
