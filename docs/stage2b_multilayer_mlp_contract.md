# Stage 2B sequential multilayer MLP contract

## 1. Status and scope

This document freezes the Stage 2B-1 software-visible contract for a sequential
multilayer MLP controller.  Stage 2B reuses the validated Stage-2A
`dense_layer_engine` without changing its arithmetic, state machine, activation
buffers, local weight provider, fixed-point behavior, or external Stage-2A
interface.  Stage 2B-1 contains only this contract, descriptor validation, a
bit-accurate Python model, and deterministic vector infrastructure.  It does
not contain controller RTL or an RTL testbench.

The first implementation supports one through `MAX_LAYERS` dense layers;
`MAX_LAYERS` defaults to four.  `NUM_PE` and `ACC_WIDTH` remain compile-time
parameters.  Required PE configurations remain 4, 8, 16, and 32.  ACC32 keeps
the Stage-1-compatible wrap behavior, while ACC48 keeps the Stage-2A wide
accumulation behavior.

## 2. Request and configuration ownership

Only one MLP request may be active.  Before `start_valid && start_ready`, the
external producer must:

1. configure every descriptor used by the request;
2. preload all referenced local weights and biases;
3. completely write the initial signed-INT16 activation vector into the A or B
   buffer named by `start_input_buffer_select`.

The first hardware implementation does not count loaded activation elements
and cannot prove that the initial vector is complete.  Completeness, lane masks,
and agreement with the first descriptor's `in_dim` are external obligations.

After a start handshake, `busy` remains asserted until successful completion or
until runtime-error handling completes.  While `busy=1`, activation loads,
weight configuration, bias configuration, and descriptor writes are forbidden
and their ready signals must be low.  A start presented while busy is rejected
with `start_ready=0`; it does not create an error and does not change state.

## 3. Layer descriptor

Each loaded layer descriptor contains:

| Field | Meaning |
|---|---|
| `in_dim` | Number of signed-INT16 input activations |
| `out_dim` | Number of signed-INT16 quantized outputs |
| `weight_base` | Base of the row-major `[out_dim][in_dim]` weight matrix |
| `bias_base` | Base of the contiguous `out_dim` bias vector |
| `output_shift` | Runtime ties-away arithmetic right shift |
| `relu_enable` | Apply ReLU after signed saturation |

Buffer selectors are not descriptor fields.  For initial buffer `S` and
zero-based layer index `i`:

```text
input_buffer(i)  = S XOR (i mod 2)
output_buffer(i) = NOT input_buffer(i)
final_buffer     = S XOR (layer_count mod 2)
```

Thus layer zero reads the externally loaded buffer, every intermediate result
is preserved in the opposite activation buffer, and the buffers automatically
exchange ownership between layers.

## 4. Pre-dispatch descriptor validation

The controller must validate the complete request before starting any dense
job.  A failure produces no dense job and no output.  Checks are ordered as:

1. `1 <= layer_count <= MAX_LAYERS`;
2. all descriptor slots `0 .. layer_count-1` are loaded;
3. every `in_dim` and `out_dim` is nonzero and within its compile-time maximum;
4. `out_dim[i] == in_dim[i+1]` for every adjacent pair;
5. `0 <= output_shift <= ACC_WIDTH`;
6. `weight_base + in_dim*out_dim <= MAX_WEIGHT_VALUES`;
7. `bias_base + out_dim <= MAX_BIAS_VALUES`.

Address-range calculations use mathematical extended precision.  Hardware must
extend the base and product before addition and compare the exclusive end
address without first truncating it to `WEIGHT_ADDR_WIDTH` or
`BIAS_ADDR_WIDTH`.  Negative software addresses are invalid.  Overlap between
otherwise in-range layer regions is permitted by this contract because weight
sharing is not inherently erroneous.

The frozen software error names are:

```text
BAD_LAYER_COUNT
MISSING_DESCRIPTOR
BAD_DIMENSION
DIMENSION_MISMATCH
BAD_SHIFT
WEIGHT_RANGE
BIAS_RANGE
```

## 5. Sequential execution and result routing

The controller issues one existing dense job per validated descriptor.  It
waits for the dense job handshake, keeps all descriptor values stable through
that handshake, and never issues two dense jobs concurrently.

Results from non-final layers are consumed automatically by asserting the
internal result ready signal.  They are discarded only from the result stream;
the same quantized values remain in the selected activation buffer and become
the next layer's signed-INT16 inputs.  High-precision accumulators never bypass
the per-layer quantizer.

The final layer is routed to the external ready/valid stream:

```text
output_valid, output_ready,
output_data, output_index, output_last, output_tag
```

When `output_valid=1 && output_ready=0`, data, index, last, tag, and valid must
remain stable.  Backpressure may stall the final layer through the existing
Stage-2A result FIFO.

The dense engine's `job_done` means its final scalar write and FIFO insertion
were committed; it does not prove that the external result was consumed or that
the FIFO is empty.  Stage 2B `done` is a one-cycle pulse only after:

1. every final output, including `output_last`, was accepted;
2. the result FIFO was drained; and
3. the wrapped dense engine again asserted `job_ready`.

Only then may `busy` clear and a new request start.

## 6. Error semantics and deferred capabilities

Configuration errors are detected before layer zero, so they produce no partial
result.  A runtime dense/provider/protocol error aborts all later layers and is
reported with its layer index.  Stage 2B does not promise to retract final-layer
values that were already accepted before a runtime error.

The first implementation provides no random read port for an activation buffer
after `done`; final results are available only through the ordered ready/valid
stream.  HBM, AXI, Vitis kernels, embeddings, feature interaction, concurrent
requests, and layer overlap are outside this contract.

## 7. Stage 2B-1 deterministic vector layout

The checked-in vector framework uses the default maxima and widths:

```text
MAX_LAYERS       = 4
MAX_IN_DIM       = 1024
MAX_OUT_DIM      = 1024
INPUT_WIDTH      = 16
OUTPUT_WIDTH     = 16
WEIGHT_WIDTH     = 8
BIAS_WIDTH       = 24
WEIGHT_ADDR_WIDTH= 32
BIAS_ADDR_WIDTH  = 32
SHIFT_WIDTH      = 6
```

`stage2b_inputs.hex` and `stage2b_final_outputs.hex` contain one fixed-width
1024-lane row per deterministic case.  Lane zero occupies the least-significant
16 bits; unused high lanes are zero.  Each row is exactly 4096 hexadecimal
characters.

`stage2b_weights.hex` and `stage2b_biases.hex` are flat scalar memory images,
one signed INT8 or INT24 value per line.  Descriptor bases index these files.

`stage2b_descriptors.hex` contains four 96-bit rows per case, one slot per
possible layer.  The meaningful low 93 bits are:

```text
bits  10:0   in_dim
bits  21:11  out_dim
bits  53:22  weight_base
bits  85:54  bias_base
bits  91:86  output_shift
bit      92  relu_enable
bits  95:93  zero
```

An unloaded or unused slot is encoded as zero; the authoritative loaded mask,
layer count, expected validation result, per-layer accumulator values,
quantized intermediate outputs, and buffer selections are recorded in
`stage2b_expected.json`.  These files are a software/test-vector contract, not
evidence that Stage 2B RTL exists or passes simulation.
