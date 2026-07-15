# Stage-2 vector-PE resource and cycle model v1

## 1. Assumptions and formulas

This is a pre-synthesis count model.  It does not predict placed timing or
guarantee RAM/DSP mapping.  The estimate point is 250 MHz, INT8 weights, INT24
bias, one output neuron active at a time, and `Q=1` quantize/enqueue cycle.

```text
D = input dimension, O = output dimension, P = NUM_PE
K = ceil(D/P)
R = ceil(log2(P))
C_output_baseline = K + R + Q
C_layer_baseline  = O*(K+R+Q)
C_layer_overlap   ~= O*K + R + Q       // Stage 2B target only
C_isolated        = ceil(D/P) + C_layer // includes one P-wide input load
```

The no-stall formulas exclude provider starvation and output backpressure.
Every stalled accepted boundary adds visible cycles; no arithmetic state may
advance without the corresponding transfer.

## 2. Five-layer cycle estimates

| Layer | P | K | R | Baseline cycles/output | Baseline layer cycles | Stage-2B overlap target | Baseline layers/s @250 MHz |
|---|---:|---:|---:|---:|---:|---:|---:|
| 8->4 | 4 | 2 | 2 | 5 | 20 | 11 | 12,500,000 |
| 8->4 | 8 | 1 | 3 | 5 | 20 | 8 | 12,500,000 |
| 8->4 | 16 | 1 | 4 | 6 | 24 | 9 | 10,416,667 |
| 8->4 | 32 | 1 | 5 | 7 | 28 | 10 | 8,928,571 |
| 64->32 | 4 | 16 | 2 | 19 | 608 | 515 | 411,184 |
| 64->32 | 8 | 8 | 3 | 12 | 384 | 260 | 651,042 |
| 64->32 | 16 | 4 | 4 | 9 | 288 | 133 | 868,056 |
| 64->32 | 32 | 2 | 5 | 8 | 256 | 70 | 976,562 |
| 128->64 | 4 | 32 | 2 | 35 | 2,240 | 2,051 | 111,607 |
| 128->64 | 8 | 16 | 3 | 20 | 1,280 | 1,028 | 195,312 |
| 128->64 | 16 | 8 | 4 | 13 | 832 | 517 | 300,481 |
| 128->64 | 32 | 4 | 5 | 10 | 640 | 262 | 390,625 |
| 256->128 | 4 | 64 | 2 | 67 | 8,576 | 8,195 | 29,151 |
| 256->128 | 8 | 32 | 3 | 36 | 4,608 | 4,100 | 54,253 |
| 256->128 | 16 | 16 | 4 | 21 | 2,688 | 2,053 | 93,006 |
| 256->128 | 32 | 8 | 5 | 14 | 1,792 | 1,030 | 139,509 |
| 512->256 | 4 | 128 | 2 | 131 | 33,536 | 32,771 | 7,455 |
| 512->256 | 8 | 64 | 3 | 68 | 17,408 | 16,388 | 14,361 |
| 512->256 | 16 | 32 | 4 | 37 | 9,472 | 8,197 | 26,394 |
| 512->256 | 32 | 16 | 5 | 22 | 5,632 | 4,102 | 44,389 |

Stage 2A is measured only against the baseline column.  The overlap column is a
Stage 2B design target and is not an implementation or throughput claim.

## 3. Logical compute and bandwidth resources

| P | Logical multipliers | Lane accumulators | Final accumulator | ACC32 register bits | ACC48 register bits | Weight bits/cycle | Weight rate @250 MHz | INT16 activation bits/cycle |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 4 | 4 | 4 | 1 | 160 | 240 | 32 | 1 GB/s | 64 |
| 8 | 8 | 8 | 1 | 288 | 432 | 64 | 2 GB/s | 128 |
| 16 | 16 | 16 | 1 | 544 | 816 | 128 | 4 GB/s | 256 |
| 32 | 32 | 32 | 1 | 1,056 | 1,584 | 256 | 8 GB/s | 512 |

The register-bit columns count `(P+1)*ACC_WIDTH` only; reduction pipeline and
control registers add implementation-dependent state.  Multiplier counts are
logical upper budgets.  Vivado may use DSPs, LUTs, multiple primitives, or
packing depending on exact widths and constraints.  ACC48 is therefore not
described as a one-DSP accumulator.

## 4. Activation cache

The approved default maxima are `MAX_IN_DIM=1024` and `MAX_OUT_DIM=1024`.
Two whole-vector buffers each contain
`max(MAX_IN_DIM,MAX_OUT_DIM)*INPUT_WIDTH` bits.  At INT16:

| P | Banks | Depth/bank at 1024 | Bits/bank | One buffer | Ping-pong pair |
|---:|---:|---:|---:|---:|---:|
| 4 | 4 | 256 | 4,096 | 2,048 B | 4,096 B |
| 8 | 8 | 128 | 2,048 | 2,048 B | 4,096 B |
| 16 | 16 | 64 | 1,024 | 2,048 B | 4,096 B |
| 32 | 32 | 32 | 512 | 2,048 B | 4,096 B |

Physical BRAM/LUTRAM use depends strongly on bank depth and primitive packing;
the table is logical capacity only.  The same modulo/divide banking supports
chunk reads and scalar result writes.

For the five reviewed layers the live input capacity is:

| Layer | Input width | One logical input | Ping-pong logical input | Provider weight traffic/sample | Bias traffic/sample |
|---|---:|---:|---:|---:|---:|
| 8->4 | 10 | 10 B | 20 B | 32 B | 12 B |
| 64->32 | 16 | 128 B | 256 B | 2 KiB | 96 B |
| 128->64 | 16 | 256 B | 512 B | 8 KiB | 192 B |
| 256->128 | 16 | 512 B | 1 KiB | 32 KiB | 384 B |
| 512->256 | 16 | 1 KiB | 2 KiB | 128 KiB | 768 B |

Weights are not committed to a whole-layer on-chip cache.  The bytes above are
logical provider traffic for one sample.  A future HBM/cache implementation may
reuse or tile them outside the PE boundary.

## 5. Accumulator range

For signed widths `W_X`, `W_W`, and `W_B`, evaluate all four endpoint products:

```text
p_min = min(x_min*w_min, x_min*w_max, x_max*w_min, x_max*w_max)
p_max = max(x_min*w_min, x_min*w_max, x_max*w_min, x_max*w_max)
sum_min = D*p_min + bias_min
sum_max = D*p_max + bias_max
```

| Layer | Input width | Safe signed width | ACC32 mode | ACC48 mode |
|---|---:|---:|---|---|
| 8->4 | 10 | 25 | exact bound covered | exact bound covered |
| 64->32 | 16 | 30 | exact bound covered | exact bound covered |
| 128->64 | 16 | 31 | exact bound covered | exact bound covered |
| 256->128 | 16 | 32 | exact endpoint bound covered | exact bound covered |
| 512->256 | 16 | 33 | two's-complement wrap possible | exact bound covered |

ACC32 is required for phase-1 compatibility and wraps after every addition.
ACC48 is the Stage-2 default and covers the reviewed endpoint bounds while
retaining the same eight fractional bits.  It does not alter external formats,
bias alignment, shift, rounding, saturation, or ReLU ordering.

## 6. Controller and FIFO state

Minimum logical state includes P lane sums, R reduction stages, chunk/output
counters sized from the compile-time maxima, a copied descriptor, provider
request/response payload holding registers, output index/tag state, an elastic
result FIFO, explicit error status, and ping-pong ownership bits.  Stage 2B adds
another `P*ACC_WIDTH` partial-sum bank and its tags.

Likely critical paths are signed multiply/add into a lane accumulator, a
reduction-tree adder level, wide runtime round/saturation compare, P-bank read
routing, and provider ready/valid fanout.  The reduction tree must be registered;
no P-input combinational adder chain is allowed.

## 7. Batch effect

For the Stage-2A one-job scheduler and no whole-layer weight cache:

```text
C_batch_baseline(B) = B*(ceil(D/P) + C_layer_baseline)
provider_weight_bytes(B) = B*D*O*WEIGHT_WIDTH/8
```

Thus B=1/4/8 has the same ideal steady-state samples/s; batching merely scales
latency and traffic.  Any later weight-reuse improvement belongs to the provider
and requires a separate storage/bandwidth model.

## 8. Reproduction

`python/estimate_pe_architecture.py` emits both cycle models, all P values, all
five layers, logical cache/provider counts, and ACC32/ACC48 coverage.  Its
`--self-check` mode verifies the table's core identities.  Generated numbers are
architecture estimates until Vivado synthesis supplies real device evidence.
