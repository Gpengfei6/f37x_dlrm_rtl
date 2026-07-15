# Stage-2A interface draft

## 1. Status

This interface is approved for the independent Stage-2A baseline hierarchy.  It
does not modify the GATE-1 top-level interface and is not an HBM, AXI, or Vitis
Kernel contract.  Payloads are sampled only on `valid && ready`; producers hold
valid and payload stable under backpressure.

## 2. Compile-time parameters

| Parameter | Default | Constraint/purpose |
|---|---:|---|
| `MAX_IN_DIM` | 1024 | Maximum accepted runtime input dimension |
| `MAX_OUT_DIM` | 1024 | Maximum accepted runtime output dimension |
| `NUM_PE` | 16 | Required configurations 4, 8, 16, 32 |
| `INPUT_WIDTH` | 16 | Signed activation element width |
| `WEIGHT_WIDTH` | 8 | Signed weight width |
| `BIAS_WIDTH` | 24 | Signed bias width |
| `ACC_WIDTH` | 48 | 32 selects phase-1 wrap compatibility |
| `OUTPUT_WIDTH` | 16 | Signed result width |
| `WEIGHT_ADDR_WIDTH` | implementation parameter | Logical provider offset width |
| `BIAS_ADDR_WIDTH` | implementation parameter | Logical provider offset width |
| `RESULT_FIFO_DEPTH` | 2 or greater | Elastic completed-result capacity |

`NUM_PE` must be a positive power of two in Stage 2A so the registered reduction
depth is exactly `ceil(log2(NUM_PE))`.  Elaboration-time checks reject unsupported
values; runtime checks reject invalid dimensions.

## 3. Job descriptor ready/valid

| Signal | Direction | Meaning |
|---|---|---|
| `job_valid`, `job_ready` | in, out | Descriptor transfer |
| `job_in_dim` | in | `1..MAX_IN_DIM` |
| `job_out_dim` | in | `1..MAX_OUT_DIM` |
| `job_input_buffer_select` | in | Ping-pong source buffer |
| `job_output_buffer_select` | in | Distinct ping-pong destination buffer |
| `job_weight_offset` | in | Provider base for `[output][input]` weights |
| `job_bias_offset` | in | Provider base for per-output bias |
| `job_output_shift` | in | Per-layer arithmetic-right-shift amount |
| `job_relu_enable` | in | Apply ReLU after signed saturation |
| `job_tag` | in | Opaque result correlation tag, if implemented |

The engine copies all accepted fields.  Source descriptor pins may change on the
next cycle without affecting the active job.  The descriptor contains no HBM
address topology, AXI ID, burst size, or channel selection.

Invalid descriptors have one defined outcome: an explicit error response with
no activation/provider request and no partial result.  At minimum these are
invalid: zero dimension, dimension above its compile-time maximum, equal
input/output buffer selection, and shift outside the quantizer's supported
range.

## 4. Activation-buffer interfaces

### External load port

The configuration/load side writes one P-lane word:

| Signal | Meaning |
|---|---|
| `act_load_valid`, `act_load_ready` | Load transfer |
| `act_load_buffer_select` | Target A/B buffer |
| `act_load_chunk_index` | Physical word address |
| `act_load_lane_mask[NUM_PE-1:0]` | Valid lanes |
| `act_load_data[NUM_PE*INPUT_WIDTH-1:0]` | Lane-packed signed values |

The engine stalls/rejects loading a buffer currently owned by an active job.
The final short word and `IN_DIM<NUM_PE` use low-lane masks.

### Internal chunk-read port

| Signal | Meaning |
|---|---|
| `act_req_valid`, `act_req_ready` | Request accepted chunk address |
| `act_req_chunk_index` | Address `floor(feature_index/NUM_PE)` |
| `act_rsp_valid`, `act_rsp_ready` | Elastic one-cycle response |
| `act_rsp_data` | P packed signed values |

Scalar output writes map output index i to `bank=i%NUM_PE` and
`address=i/NUM_PE`.  The write is committed before the job-complete event.

## 5. Abstract weight/bias provider

### Weight chunk

| Signal | Direction | Meaning |
|---|---|---|
| `weight_req_valid`, `weight_req_ready` | engine, provider | Request transfer |
| `weight_req_offset` | engine | `weight_offset + output_index*in_dim + chunk*NUM_PE` |
| `weight_req_lane_mask` | engine | Tail mask; provider must not expose invalid values as valid lanes |
| `weight_rsp_valid`, `weight_rsp_ready` | provider, engine | Response transfer |
| `weight_rsp_data` | provider | `NUM_PE*WEIGHT_WIDTH` signed lanes |
| `weight_rsp_error` | provider | Explicit local-provider failure |

### Bias

| Signal | Direction | Meaning |
|---|---|---|
| `bias_req_valid`, `bias_req_ready` | engine, provider | Bias request transfer |
| `bias_req_offset` | engine | `bias_offset + output_index` |
| `bias_rsp_valid`, `bias_rsp_ready` | provider, engine | Response transfer |
| `bias_rsp_data` | provider | Signed `BIAS_WIDTH` value |
| `bias_rsp_error` | provider | Explicit local-provider failure |

Stage 2A uses an abstract local provider that can be loaded by a testbench.  It
is not an architectural whole-layer cache.  Future HBM replaces only the
provider's outer/storage-facing side; the interfaces above stay logical.

## 6. Vector-dot command and chunk interface

The internal vector core accepts a per-output command containing runtime
`in_dim` and aligned bias.  It then accepts exactly `ceil(in_dim/NUM_PE)` joined
activation/weight chunks.  Each chunk carries a lane mask and `last` flag.
Counters and partial sums advance only on a chunk transfer.

The accumulator output is an elastic signed `ACC_WIDTH` value.  It holds stable
until accepted.  The core rejects a new command while its non-overlapped Stage
2A context remains live.

## 7. Result and completion

| Signal | Direction | Meaning |
|---|---|---|
| `result_valid`, `result_ready` | out, in | Completed neuron transfer |
| `result_data` | out | Signed `OUTPUT_WIDTH` quantized value |
| `result_index` | out | Output-neuron index |
| `result_last` | out | Final result of the job |
| `result_tag` | out | Copied job tag if enabled |
| `job_done` | out | Pulse/event only after all results are committed |
| `error_valid`, `error_ready` | out, in | Explicit error transfer |
| `error_code` | out | Invalid descriptor/provider/protocol category |

Result payload and `result_valid` remain stable under backpressure.  A completed
old result may be consumed on the same edge that a new result is inserted if
FIFO capacity accounting permits.  Job completion does not authorize a new
layer to read the output buffer until all scalar writes are committed.

## 8. Stage-2A controller sequence

```text
IDLE
  -> COPY_AND_VALIDATE_DESCRIPTOR
  -> REQUEST_BIAS(output=0)
  -> START_VECTOR_DOT
  -> REQUEST/JOIN_ACTIVATION_AND_WEIGHT(chunk=0..K-1)
  -> REDUCE(R registered levels)
  -> QUANTIZE_AND_ENQUEUE(Q=1)
  -> next output or COMPLETE
  -> IDLE
```

Stage 2A starts no MAC work for output o+1 until output o has left the vector
core.  Stage 2B will define the separate double-partial-sum overlap protocol.

## 9. Fixed-point configurations

| Mode | `ACC_WIDTH` | Required behavior |
|---|---:|---|
| `compat_int32_wrap` | 32 | Signed two's-complement wrap after every addition |
| `wide_int48` | 48 | Sign-extended accumulation without truncation for reviewed dimensions |

Both modes use the descriptor shift, ties-away rounding, signed saturation, and
optional ReLU.  Phase-1 8-to-4 compatibility uses its existing widths, shift
four, and ReLU enabled.

## 10. Deferred interface decisions

Physical HBM topology, AXI signaling, provider-side caching/tiling, multilayer
descriptor queues, dynamic batching, Stage-2B psum-bank tags, and full DLRM
control are deliberately absent.  Adding them requires later review and may not
change this logical arithmetic contract without explicit approval.
