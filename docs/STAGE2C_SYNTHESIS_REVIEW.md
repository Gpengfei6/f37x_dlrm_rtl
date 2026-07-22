# Stage 2C multilayer MLP synthesis review

## Status and evidence boundary

The default `mlp_sequence_controller` configuration now synthesizes out of
context under local Vivado 2022.1.  Functional XSim regression passes, memory
inference is explicit, and no latch is inferred.  The 100 MHz synthesis timing
constraint is **not met**.

This is local structural evidence for `xc7a200tfbg484-2`, not an F37X resource,
timing, implementation, or board result.  It also does not replace the required
Vivado 2020.2 rerun.  Generated DCP, reports, logs, and work directories remain
ignored; `scripts/run_synth_stage2c.tcl` regenerates them locally.

## Reviewed default configuration

- `MAX_LAYERS=4`, `MAX_IN_DIM=MAX_OUT_DIM=1024`;
- `NUM_PE=16`, signed INT16 activation, signed INT8 weight;
- signed INT24 bias, signed INT48 accumulator, signed INT16 result;
- `MAX_WEIGHT_VALUES=65536`, `MAX_BIAS_VALUES=1024`;
- two ping-pong activation buffers and a two-entry result FIFO.

## Storage implementation

`banked_activation_buffer` uses one generated memory per activation bank.  Each
bank selects one mutually exclusive write tuple (`enable`, `address`, `data`)
from vector load or scalar result write, with scalar writes retaining priority.
The registered read response remains one cycle, supports same-edge elastic
replacement, and remains stable under backpressure.

For the default dimensions, Vivado infers both activation buffers as 32 total
RAMB18E1 blocks: 16 independent `64x16` simple-dual-port banks per buffer.  Each
bank uses only 1,024 of 18,432 primitive bits because P=16 requires 16
simultaneous lanes.  This 5.56% per-block bit efficiency is a deliberate
bandwidth/resource tradeoff, not a capacity optimization.

`local_weight_provider` maps global weight address `a` to
`bank=a%NUM_PE`, `row=a/NUM_PE`.  A request may start at any address; registered
lane mask/base-bank metadata rotates the bank outputs back into logical lane
order and reads across a row boundary without another cycle.  Range checking is
performed per enabled lane.  Backpressure holds response data/error stable and
same-edge replacement remains supported.

Vivado infers 16 independent `4096x8` simple-dual-port weight RAMs as 16
RAMB36E1 blocks and the `1024x24` bias RAM as one RAMB36E1 block.  The weight
banks use 88.89% of each RAMB36 and the bias RAM uses 66.67%.

## Functional verification

The final RTL was tested with local Vivado 2022.1/XSim:

| Suite | Result |
|---|---|
| Stage 2A compile/elaborate/simulate | PASS, 6/6 independent benches |
| `tb_banked_activation_buffer` | PASS: partial row, highest scalar index, invalid chunk/index, continuous reads, backpressure, same-edge replacement |
| `tb_local_weight_provider` | PASS: aligned/unaligned/cross-row reads, final row/highest address, enabled-lane overflow, masks, continuous reads, backpressure |
| Stage 2B multilayer XSim | PASS, `valid=11 invalid=9 total=20` |
| Phase-1 Python fixed-point regression | PASS, 24 deterministic cases |
| Stage 2A Python contract | PASS |
| Stage 2B Python contract | PASS, 11 valid and 9 invalid deterministic cases |

The Stage 2B bench also has a two-millisecond global timeout in addition to its
per-case guards.  Exit code alone was not used as evidence; exact PASS markers
and status files were checked.

## Synthesis resources

Final post-synthesis hierarchical utilization is:

| Resource | Final | Initial distributed-activation run |
|---|---:|---:|
| Total LUT | 5,313 | 6,717 |
| Logic LUT | 5,293 | 5,289 |
| LUTRAM | 20 | 1,428 |
| FF | 1,819 | 2,363 |
| RAMB36E1 | 17 | 17 |
| RAMB18E1 | 32 | 0 |
| DSP | 21 | 21 |

The remaining 20 LUTRAMs belong to the result FIFO.  Synthesis reports zero
latches.  The Vivado log contains zero errors and zero critical warnings.  The
eight ordinary warnings are six notices for unused reserved descriptor bits
`[95:93]` (reported twice), one parallel-synthesis notice, and one expected OOC
`HD.CLK_SRC` notice.  The former 100 infeasible `ram_style="block"` warnings are
eliminated.

## Timing and report audit

At a 10.000 ns constraint:

- WNS is `-2.460 ns`;
- TNS is `-1371.656 ns`;
- 861 of 5,862 setup endpoints fail;
- pulse-width slack is positive and there are no pulse-width failures.

The worst path starts at
`u_dense_layer_engine/descriptor_output_shift_reg[5]` and ends at activation
buffer 0 bank 0 RAMB18 write data.  It contains 32 logic levels (22 CARRY4 plus
LUT logic) and has 12.172 ns data delay: 5.770 ns logic and 6.402 ns estimated
route.  This is the runtime round/saturate/ReLU result path, not the weight-bank
address or lane-rotation path.

`check_timing` reports zero unclocked registers, constant clocks, unconstrained
internal endpoints, multiple clocks, generated-clock problems, combinational
loops, partial delays, or latch loops.  The 482 inputs and 44 outputs without
I/O delays are expected for this clock-only OOC boundary and must be constrained
when a real shell/top-level interface exists.

Post-synthesis DRC contains 75 warnings: one board-level configuration-voltage
property warning and 74 DSP pipelining recommendations.  Methodology contains
1,129 warnings: 48 RAM output-register recommendations, 3 unregistered DSP
output notices, 16 combinational-multiplier notices, 528 large setup violations,
and 534 missing OOC I/O delays.  The largest reported fanouts are vector-dot
`core_reset` at 1,266, top reset at 639, descriptor input-buffer select at 265,
and a reduction-work net at 192.

## Decision and remaining risk

No quantization pipeline stage is added in Stage 2C.  Such a register would
change the dense-engine cycle contract and require coordinated state, FIFO, and
multilayer sequencing changes.  The current RTL is synthesis-legal and
functionally tested, but 100 MHz timing remains failed and must not be described
as timing closure.

A separately reviewed timing task should pipeline the runtime quantization and
activation-write boundary, then rerun all fixed-point, latency, backpressure,
Stage 2A, Stage 2B, and synthesis checks.  The user must still run exact-source
Vivado 2020.2 and target/F37X validation before any target success claim.

## Commands run

```powershell
python scripts/run_python_tests.py
python scripts/run_stage2a_python_tests.py
python scripts/run_stage2b_python_tests.py
& 'D:\vivado2022\vivado2022forwins\Vivado\2022.1\bin\vivado.bat' -mode tcl -nolog -nojournal -source scripts/run_xsim_stage2a.tcl
& 'D:\vivado2022\vivado2022forwins\Vivado\2022.1\bin\vivado.bat' -mode tcl -nolog -nojournal -source scripts/run_xsim_stage2b.tcl
& 'D:\vivado2022\vivado2022forwins\Vivado\2022.1\bin\vivado.bat' -mode tcl -log logs/vivado_stage2c.log -nojournal -source scripts/run_synth_stage2c.tcl
```
