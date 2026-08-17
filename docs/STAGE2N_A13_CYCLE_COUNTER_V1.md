# Stage 2N-A13 Hardware Cycle Counters V1

## Status

- Date: 2026-08-17
- Branch: `work/stage2n-a13-cycle-counter`
- Frozen starting commit: `592720922a7e770f678e6370d07d65c13afdb1b2`
- `A13_XSIM=PASS`
- `A13_LOCAL_ARTIX7_PROXY_TIMING=FAIL`
- `A13_TARGET_VU37P_TIMING=BLOCKED`
- `A13_TIMING=BLOCKED`
- `A13_READY_FOR_BOARD=NO`

The target VU37P timing gate is not closed. The exact target part is absent
from the local Vivado installation, and the full A10/A13 integration top does
not meet 100 MHz in the available Artix-7 proxy synthesis. No board operation,
FPGA reset, XO packaging, xclbin generation, or server access was performed.

## Scope and compatibility boundary

A13 adds observation only. The frozen A10 v2 controller, MLP arithmetic,
interaction arithmetic, descriptors, fixed-point behavior, model shape, and
ready/valid datapaths are not edited. A new wrapper observes the canonical
controller's accepted START, phase, result, and error signals.

The integrated A13 register window retains all A10 v2 addresses through
`0x214`. The pipeline version changes from `0x00024E11` to `0x00024E13` so that
Host software cannot silently use the old map.

## Counter contract

All four counters are unsigned, 32-bit, and saturating. They remain at
`0xFFFFFFFF` instead of wrapping.

### Reset and restart

- Reset clears all counters and the internal counting-active state.
- An accepted `pipeline_start_valid && pipeline_start_ready` starts a new
  measurement.
- On that accepted START edge, the three stage counters are set to zero and
  Total is set to one. Thus the accepted START edge is Total cycle 1.
- A later accepted START replaces the previous completed values; values are
  not cumulative across jobs.

### Stop event and backpressure

Total and the active stage counter include the edge on which the final result
is first visible as `result_valid && result_last`. Counting then freezes.
Consequently Host polling latency, result FIFO backpressure after final-result
visibility, `RESULT_POP`, done polling, and `CLEAR_DONE` are excluded. The
latched counters remain stable through both result retirement and done clear.

An observed pipeline error also freezes the active measurement. This prevents
an errored job from accumulating arbitrary Host acknowledgement time.

### Stage definitions

The counters follow the canonical controller phase encoding:

| Counter | Counted phases | Included boundary |
| --- | --- | --- |
| Bottom | `START_BOTTOM`, `RUN_BOTTOM` | dispatch/accept and done-observe |
| Interaction | `START_INTERACTION`, `RUN_INTERACTION`, `WAIT_INTERACTION_DONE` | dispatch and done-observe |
| Top | `START_TOP`, `RUN_TOP` | dispatch through first final-result visibility |
| Total | every active cycle | accepted START through first final-result visibility |

Total can therefore exceed the sum of the stage counters. The difference is
ordered controller overhead such as load/transition phases; the XSim vector
measured eight such cycles.

## AXI-Lite register extension

| Address | Name | Access | Meaning |
| --- | --- | --- | --- |
| `0x218` | `BOTTOM_CYCLES` | RO | most recent Bottom phase cycles |
| `0x21C` | `INTERACTION_CYCLES` | RO | most recent Interaction phase cycles |
| `0x220` | `TOP_CYCLES` | RO | most recent Top phase cycles |
| `0x224` | `TOTAL_CYCLES` | RO | accepted START through final-result visibility |

The four words are ordinary AXI-Lite read data. They introduce no new write
command and do not alter existing A10 v2 command semantics.

## XSim verification

Command:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\run_stage2n_a13_cycle_counter_xsim_v1.ps1
```

Tool: local Vivado/XSim 2022.1, build 3526262.

The self-checking test uses the capacity-expanded canonical model shape:

- Bottom MLP: `8 -> 16 -> 8`
- Interaction: five 8-element vectors producing 18 outputs
- Top MLP: `18 -> 32 -> 16 -> 1`
- 5 descriptors, 1360 programmed weights, and 73 programmed biases
- pipeline capacities: 8 descriptors, 2048 weights, and 128 biases

Results:

| Item | Result |
| --- | ---: |
| Complete identical jobs | 2 |
| Arithmetic result | 36 |
| Result index / last / tag | 0 / 1 / 4 |
| Bottom cycles | 322 |
| Interaction cycles | 100 |
| Top cycles | 744 |
| Total cycles | 1174 |
| Controller overhead | 8 |
| Final-result backpressure iterations | 12 |
| Compile/elaboration/simulation warnings | 0 |
| Compile/elaboration/simulation errors or fatal messages | 0 |

The test checks reset-to-zero, nonzero completed values, Total greater than or
equal to the ordered stage sum, result stability, counter stability during
Host backpressure, stability after `RESULT_POP`, stability after `CLEAR_DONE`,
counter replacement on the second accepted START, and exact equality between
the two completed measurements.

Evidence is retained under
`results/stage2n_a13_cycle_counter_xsim_v1/`. The PASS marker is:

```text
tb_dlrm_f37x_rtl_kernel_stage2n_a13_cycle_counter_v1: PASS runs=2 final=36 descriptors=5 weights=1360 biases=73
```

## Host support and its validation boundary

`host/stage2n_a13_cycle_counter_board_v1.cpp`:

- requires the kernel clock in MHz and xclbin UUID as command-line inputs;
- checks pipeline version `0x00024E13`;
- reads all four counters while the final result is valid, before POP;
- rejects zero counters or Total smaller than the stage sum;
- checks that POP and `CLEAR_DONE` do not change the captured values;
- writes raw cycles and clock-derived microseconds to CSV;
- does not hard-code 100 MHz for cycle-to-time conversion.

The local machine has a C++11 compiler but no XRT headers. A real compile was
attempted and is `BLOCKED_MISSING_LOCAL_XRT_HEADERS`. A syntax-only compile
with temporary declarations passed. That proves C++11 syntax only; it does not
prove XRT API compatibility, link compatibility, the runtime UUID/IP binding,
xclbin compatibility, or board behavior.

## OOC synthesis and timing review

### Exact target attempt

The requested target is `xcvu37p-fsvh2892-2L-e`. Local Vivado 2022.1 reported
`No parts matched 'xcvu37p-fsvh2892-2L-e'`, so synthesis did not start. The
exact VU37P/F37X A13 OOC timing result is therefore `BLOCKED`, not PASS or
FAIL. The failed-at-part-selection log is retained under
`results/stage2n_a13_cycle_counter_ooc_v1/`.

### Local proxy comparison

The frozen A10 v2 full AXI-Lite integration top and A13 full AXI-Lite
integration top were synthesized independently with identical settings:

- Vivado 2022.1 build 3526262
- part `xc7a200tfbg484-2`
- out-of-context synthesis
- 10.000 ns clock and 0.200 ns uncertainty
- 2.000 ns maximum input/output interface budget
- no false paths and no relaxed clock

Evidence is retained under
`results/stage2n_a13_cycle_counter_ooc_artix7_v3/`.

| Metric | Frozen A10 v2 | A13 v1 | Delta |
| --- | ---: | ---: | ---: |
| LUT | 15915 | 16049 | +134 |
| FF | 10043 | 10173 | +130 |
| RAMB36E1 | 17 | 17 | 0 |
| RAMB18E1 | 81 | 81 | 0 |
| DSP48E1 | 39 | 39 | 0 |
| Latch | 0 | 0 | 0 |
| WNS | -8.458 ns | -8.458 ns | 0.000 ns |
| TNS | -327.364 ns | -327.364 ns | 0.000 ns |
| Failing setup endpoints | 68 | 68 | 0 |
| DRC error / critical / warning | 0 / 0 / 83 | 0 / 0 / 83 | 0 |
| Methodology error / critical / warning | 0 / 0 / 137 | 0 / 0 / 137 | 0 |

Both designs synthesized with zero synthesis errors and zero synthesis
critical warnings. `check_timing` reports zero unclocked registers, zero
unconstrained internal endpoints, zero missing input/output delays, zero
multiple-clock endpoints, zero combinational loops, and zero latch loops.

The 83 DRC warnings comprise the OOC/board-property warning `CFGBVS-1` and
existing DSP pipelining recommendations (`DPIP-1`, `DPOP-1`, `DPOP-2`). The
137 methodology warnings comprise shallow A10 activation BRAM observations,
RAM output-register recommendations, DSP output-register recommendations, and
the 68 known setup violations. There are no DRC or methodology errors or
critical warnings.

The maximum reported fanout is an existing reset net at 7288 loads with
`+6.481 ns` slack. No A13 cycle-counter net appears in the top-50 high-fanout
list.

### Worst path attribution

The baseline and A13 worst path are identical:

```text
u_stage2n_a2/u_feature_interaction_engine/pair_index_reg_reg[3]/C
  -> u_stage2n_a2/u_feature_interaction_engine/result_data_reg_reg[6]/D
```

It has 39 logic levels and an 18.212 ns data-path delay in the Artix-7
post-synthesis estimate. It is inside the pre-existing legacy A2 standalone
feature-interaction datapath, not the A13 wrapper, counter incrementers, new
AXI-Lite read mux entries, or the capacity-expanded internal pipeline. The
identical WNS, TNS, failing-endpoint count, and endpoints establish that A13 did
not create or worsen the proxy critical path.

This does not convert the timing result into a PASS. It only attributes the
local proxy failure correctly.

## Files added for A13

- `rtl/pipeline/dlrm_internal_pipeline_controller_stage2n_a13_v1.sv`
- `rtl/f37x/dlrm_internal_pipeline_axi_lite_adapter_stage2n_a13_v1.sv`
- `rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a13_v1.sv`
- `tb/tb_dlrm_f37x_rtl_kernel_stage2n_a13_cycle_counter_v1.sv`
- `host/stage2n_a13_cycle_counter_board_v1.cpp`
- `constraints/stage2n_a13_cycle_counter_100mhz_v1.xdc`
- `scripts/run_stage2n_a13_cycle_counter_xsim_v1.ps1`
- `scripts/run_stage2n_a13_cycle_counter_ooc_v1.tcl`
- `scripts/run_stage2n_a13_cycle_counter_ooc_v1.ps1`
- `docs/STAGE2N_A13_CYCLE_COUNTER_V1.md`

## Remaining gates

A13 is not ready for a board run. Before that claim can change, at minimum:

1. synthesize and close timing for the A13 integration on the exact VU37P
   target with the intended shell boundary;
2. compile the Host with the actual Vivado/Vitis 2020.2 XRT headers and
   libraries;
3. package and link an A13 XO/xclbin and verify the runtime IP name/UUID;
4. run the user-controlled F37X board test and compare hardware cycles with
   wall-clock timing.

No full implementation/place-and-route, A13 XO, A13 xclbin, XRT execution, or
F37X board validation was completed in this local stage.
