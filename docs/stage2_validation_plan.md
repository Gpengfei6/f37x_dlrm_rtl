# Stage-2A validation plan

## 1. Gate language and stopping point

Stage 2A ends at a real Vivado 2020.2/XSim server-validation gate.  Local Python
PASS is arithmetic/model evidence only.  Because the local machine has no
Vivado, Icarus, Verilator, or Verible, RTL compile/elaboration/simulation/lint
must be recorded as **SKIPPED**, never PASS.  No Stage 2B work starts until the
returned server logs are audited.

Every new RTL module needs an independent self-checking testbench with an
explicit `: PASS` marker.  Exit code zero alone is insufficient.  Existing
GATE-1 testbenches run unchanged in the combined regression.

## 2. Python oracle

The Stage-2 Python reference exposes two explicit modes:

- `compat_int32_wrap`: wrap every multiply/add contribution to signed 32 bits;
- `wide_int48`: wrap/sign-normalize at 48 bits, which must retain the exact
  reviewed mathematical sums.

It reuses the existing bias alignment, runtime shift, ties-away rounding,
signed saturation, and optional post-saturation ReLU order.  Required Python
groups are:

1. P=4/8/16/32 schedule identities and lane masks.
2. 8-to-4 phase-1-compatible vectors.
3. 64-to-32 deterministic and random vectors.
4. Non-divisible 13-to-7 and 65-to-17 vectors.
5. `IN_DIM<NUM_PE`, including D=1 and D=P-1.
6. Maximum positive/negative products and biases.
7. A vector that distinguishes ACC32 wrap from ACC48 accumulation.
8. Multiple output shifts, including zero and four.
9. ReLU enabled and disabled on negative saturated outputs.
10. Invalid dimensions and buffer-selector validation.
11. Baseline and Stage-2B-target cycle-model self-checks.
12. Random D/O/P cases with a deterministic seed.

Python compares each layer result bit for bit, not within a numeric tolerance.

## 3. RTL testbench hierarchy

### L1 — MAC lane

- signed extrema, zero, alternating signs, bias seed;
- consecutive enables and arbitrary hold gaps;
- reset and ACC32 wrap boundary;
- ACC48 result for the same overflowing sequence.

### L2 — runtime round/saturate/ReLU

- shift zero and several positive shifts;
- positive and negative below/at/above half-LSB ties;
- positive/negative saturation;
- ReLU on/off;
- stable output under downstream backpressure when wrapped elastically.

### L3 — banked activation buffer

- P=4/8/16/32 banking identity;
- D<P and D%P nonzero tail writes/reads;
- scalar output write mapping;
- one-cycle synchronous response;
- response backpressure and same-edge response replacement;
- ping-pong ownership: active source cannot be overwritten.

### L4 — abstract local provider

- P packed weight lanes and independent signed bias response;
- logical offsets at zero, row transitions, and configured maximum;
- deterministic and randomized response stalls;
- response backpressure and same-edge replacement;
- masked tail lanes do not affect arithmetic;
- explicit out-of-range/error behavior.

### L5 — vector dot product

- P=4/8/16/32;
- D=1, D<P, D=P, D=P+1, and non-divisible D;
- registered reduction depth `ceil(log2(P))`;
- bias exactly once;
- ACC32 wrap and ACC48 safe modes;
- input-chunk stalls and result backpressure;
- result consume/new-command boundary and continuous commands;
- no change to result while `valid&&!ready`.

### L6 — dense layer engine

- 8-to-4 phase-1 compatibility;
- 64-to-32;
- 13-to-7 and 65-to-17;
- a D<P job;
- output index/order/last and output-buffer bank contents;
- positive/negative bias boundaries, shifts, ReLU on/off;
- independent activation, provider, and result backpressure;
- continuous jobs, including same-edge final-result consumption/new-job offer;
- invalid zero/oversize dimensions and equal buffer selectors;
- descriptor pins changed after handshake to prove the internal copy;
- no Stage-2B output-neuron overlap.

### L7 — phase-1 preservation

All eight GATE-1 testbenches and their 24 top-level vectors execute unchanged.
No Stage-2A source replaces a phase-1 module or top-level port.

## 4. Required parameter matrix

| Axis | Mandatory values |
|---|---|
| `NUM_PE` | 4, 8, 16, 32 |
| Named layers | 8->4, 64->32, 13->7, 65->17 |
| Additional D | 1, P-1, P, P+1, 1024 boundary |
| Accumulator | 32 wrap compatibility; 48 safe mode |
| Shift | 0, 1, 4, and a large legal value |
| ReLU | disabled, enabled |
| Bias | minimum, -1, 0, +1, maximum |
| Stalls | none, alternating, bursts, deterministic random |

The resource-model five layers and P=4/8/16/32 must at least pass the Python
schedule model.  Full RTL data simulation uses the named Stage-2A layers to keep
runtime bounded without deleting random and boundary tests.

## 5. Assertions and scoreboards

Protocol assertions/checks:

- payload and valid stable under backpressure;
- transfer only on `valid&&ready`;
- same-edge consume/replace loses no item;
- FIFO occupancy within bounds;
- reset produces no spurious transfer.

Control assertions/checks:

- accepted descriptor remains internally stable;
- exactly K accepted chunks and O results per valid job;
- final lane mask equals runtime D;
- chunk/output indices remain in range;
- partial sums change only on an accepted joined chunk;
- bias contributes exactly once;
- input/read and output/write buffer ownership cannot overlap;
- invalid jobs produce no provider request or result;
- useful MAC count is exactly D*O.

The scoreboard is independent of internal partial sums.  It records accepted
activations, weights, bias, descriptor metadata, result indices, and tags, then
compares against Python-generated or independent behavioral expected bits.

## 6. Cycle checks

In no-stall tests:

```text
K = ceil(D/P)
R = ceil(log2(P))
C_output_baseline = K+R+1
C_layer_baseline  = O*C_output_baseline
C_layer_overlap_target = O*K+R+1
```

Stage 2A is required to match/document the baseline.  The overlap target is
checked only in the estimator and reserved for Stage 2B.  Under stalls, provider
starvation and result-capacity stalls are counted separately from useful MAC
cycles.

## 7. Static review

Before packaging, inspect:

- signed casts and product/bias extension;
- ACC32 wrap and ACC48 width at every add/reduction stage;
- local procedural loop variables and uniform `` `timescale 1ns/1ps``;
- no latch inference or multi-process variable drive;
- no unregistered P-input reduction chain;
- parameter widths at value 1 and exact maximum;
- ready/valid combinational loops;
- memory ownership and simultaneous read/write semantics;
- Vivado 2020.2 SystemVerilog compatibility;
- source manifest and validation-script enumeration.

## 8. Server acceptance criteria

The Stage-2A validation package is accepted only when returned evidence shows:

1. exact source commit/hash manifest match;
2. Python Stage-1 and Stage-2A suites PASS;
3. `xvlog` PASS for all enumerated Stage-2A and Stage-1 sources;
4. every testbench `xelab` PASS;
5. every testbench XSim log contains its exact PASS marker;
6. no timeout, fatal, error, critical warning, or unexplained severe warning;
7. required ACC32/ACC48, P, tail, backpressure, invalid-job, and compatibility
   cases are present in the logs;
8. RTL tests are not inferred from exit code zero alone.

Until those logs are returned and audited, Stage 2A RTL status is SKIPPED and
GATE-2 is not approved.  Stage 2B, HBM, AXI, and full MLP work remain blocked.
