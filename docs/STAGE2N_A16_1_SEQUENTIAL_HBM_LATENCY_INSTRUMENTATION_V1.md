# Stage 2N-A16.1 Sequential HBM Lookup Latency Instrumentation V1

Date: 2026-08-31

Branch: `work/stage2n-a15-hbm-pipeline-integration`

Parent baseline: `6155ad8fe2fa9000ebc314536986c83581f8a940`

## 1. Result

`A16_1_XSIM=PASS`

`A16_1_FUNCTIONAL_REGRESSION=PASS`

`A16_1_COUNTER_SEMANTICS=PASS`

`A16_1_LATENCY_ACCOUNTING=PASS`

Stage 2N-A16.1 adds a versioned local RTL top with two read-only 32-bit
saturating counters. It does not modify the accepted A15.4 RTL or rebuild the
accepted A15.5 xclbin. Both complete local XSim invocations passed; each
invocation performed two identical inferences without a DUT reset between
them.

## 2. Frozen event audit

The implementation uses the following existing A15/A13 events.

| Boundary | Source-level event | Meaning |
|---|---|---|
| A. first lookup start | first `m_axi_gmem_arvalid && m_axi_gmem_arready` after an accepted A15 START | first AXI read transaction actually starts |
| B. fourth lookup complete | accepted A15.3 `hbm_sequence_done` pulse | slot 3 has passed the A13 embedding-configuration handshake; all four rows are available to the pipeline |
| C. compute start | `a15_auto_start_valid && core_start_ready` | accepted A13 Bottom–Interaction–Top START; this is the existing compute-counter start |
| D. final result visible | `core_result_valid && core_result_last` | first final DLRM result is visible, before Host POP |
| E. A15 START accepted | AXI-Lite write-fire at `0x300`, command `0x0001`, while `a15_start_ready` | starts one four-lookup plus inference command |
| F. retirement/clear | A13 result POP retires the held result; A15 command `0x0002` returns DONE/ERROR to IDLE | neither operation clears completed A16 counters; the next accepted START restarts them |

Reading status or counter addresses has no clear side effect. A repeated START
while busy remains rejected by the accepted wrapper-error mechanism and does
not restart either counter. For an unsuccessful command, the corresponding
lookup or core error terminates and freezes the active interval for diagnosis;
only a successful final-result interval is used for the accepted latency
decomposition below.

## 3. Counter definitions

### HBM_LOOKUP_CYCLES

- read-only address: `0x30C`;
- width: 32 bits;
- start: first real AXI AR handshake;
- stop: registered fourth-slot injection completion;
- includes four sequential read transactions, AXI waits, response capture,
  response-to-slot handoff and inter-request sequencing;
- excludes the A13 compute interval and Host/BO activity;
- a lookup-sequence error terminates the unsuccessful interval without marking
  it as a successful fourth-slot measurement;
- saturates at `0xffffffff`.

### FPGA_END_TO_END_CYCLES

- read-only address: `0x310`;
- width: 32 bits;
- start: accepted A15 START write;
- stop: first final `valid && last` result visibility;
- includes A15 command transition, sequential lookup, slot injection,
  automatic compute START, Bottom, Interaction, Top and internal transitions;
- excludes Host polling, result retirement and BO transfer;
- a lookup or core error terminates the unsuccessful interval for diagnostic
  readback;
- saturates at `0xffffffff`.

Both counters count their start edge as cycle one and include the edge on which
their stop event is observed. Reset clears them. A completed value remains
stable through result backpressure, POP, A13 CLEAR_DONE and A15 CLEAR. A later
accepted A15 START restarts the interval.

## 4. ABI preservation

| Address | Meaning | A16.1 disposition |
|---|---|---|
| `0x218` | Bottom cycles | unchanged |
| `0x21C` | Interaction cycles | unchanged |
| `0x220` | Top cycles | unchanged |
| `0x224` | compute Total cycles | unchanged |
| `0x300` | A15 CONTROL/STATUS | unchanged |
| `0x304` | TABLE_BASE low | unchanged |
| `0x308` | TABLE_BASE high | unchanged |
| `0x30C` | HBM lookup cycles | new, read-only |
| `0x310` | FPGA end-to-end cycles | new, read-only |

The existing compute Total remains `1174` cycles and still starts only when the
A13 pipeline accepts its automatic START. It is not redefined as an all-HBM
end-to-end counter.

## 5. Local XSim result

Vivado/XSim 2022.1 compiled 18 RTL/testbench sources. `xvlog`, `xelab` and
`xsim` returned `0/0/0`; anchored warning, error, fatal and assertion-failure
counts were all zero.

| Measurement | XSim value |
|---|---:|
| HBM lookup | 73 cycles |
| Bottom | 322 cycles |
| Interaction | 100 cycles |
| Top | 744 cycles |
| compute Total | 1174 cycles |
| FPGA end-to-end | 1285 cycles |
| pipeline/control overhead | 38 cycles |

The decomposition is exact for this testbench stimulus:

`1285 = 73 + 1174 + 38`.

The final result remains `36`, all four canonical rows map to slots 0 through
3 in order, the loaded mask reaches `0xF`, and logical lookup/AXI AR/AXI
R/injection counts remain `4/4/4/4`. Two identical runs in each simulation
produced identical six-counter values. A short-width instance of the same
saturating counter RTL reached and held its all-ones value, providing a
practical overflow test without simulating 2^32 cycles.

The first local attempt deliberately retained the A15.4 repeated-START check
only in run 1, so the two end-to-end stimuli were not identical and the
determinism assertion correctly failed. The test was corrected to apply the
same repeated-START/backpressure stimulus to both runs. The failed attempt is
retained under `results/stage2n_a16_1/`; it is not acceptance evidence.

## 6. Source and evidence identity

- frozen A15.4 RTL SHA256:
  `c3da5be63d4cf195df124e572887b6aa96a464522883c6cdc95c4bd56ff4e8a1`;
- A16.1 RTL SHA256:
  `a6eec09c4ebfe358751f7dfc31c2e77d509cd55d4fc8953f465a2227c3e7f7a5`;
- A16.1 testbench SHA256:
  `439815ab86c52ec5d7d3d2df0a0250d2799158952a418de094cf4d9aa1d7dddc`;
- compact evidence: `docs/evidence/stage2n_a16_1/`.

Local command:

```powershell
.\scripts\run_stage2n_a16_1_latency_xsim_v1.ps1 `
  -ResultDir .\results\stage2n_a16_1_attempt2
```

The same command with result directory `results/stage2n_a16_1_repeat` produced
the same accepted counter values.

## 7. Evidence boundary

The 73-cycle lookup value is produced by the local fake-AXI timing model. It is
not physical F37X HBM latency. A16.1 did not run target synthesis,
implementation, XO packaging, Vitis link, xclbin generation, Host execution,
FPGA programming or board execution. It makes no bandwidth, throughput,
latency-improvement, speedup, power or performance claim.

`A16_1_PHYSICAL_HBM_LATENCY=NOT_VALIDATED`

`A16_1_PERFORMANCE=NOT_CLAIMED`

`FROZEN_A15_RTL_MODIFIED=NO`

`A15_XCLBIN_REBUILT=NO`

`NETWORK_ACCESS=NONE`

`SERVER_ACCESS=NONE`

`FPGA_DEVICE_ACCESS=NONE`

`READY_FOR_A16_2_PREPARATION=YES`
