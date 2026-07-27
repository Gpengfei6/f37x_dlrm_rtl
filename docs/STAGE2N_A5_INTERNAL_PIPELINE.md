# Stage 2N-A5 internal DLRM pipeline contract

## Scope

Stage 2N-A5 adds an RTL-internal orchestration path for:

```text
Bottom MLP -> Feature Interaction -> Top MLP
```

The arithmetic blocks are not redesigned. The implementation reuses one
`dense_layer_engine`, one activation-buffer pair, the existing weight/bias
provider, and the verified `dlrm_feature_interaction_engine`.

Stage 2N-A5 is a simulation-stage core. It does not yet add a new AXI-Lite
register map, XO, xclbin, or FPGA programming flow.

## Descriptor segmentation

`mlp_sequence_controller_segmented` adds `descriptor_base` to the existing MLP
start request. The physical descriptor used for local layer `i` is:

```text
physical_descriptor = descriptor_base + i
```

The selected range must satisfy:

```text
1 <= layer_count
0 <= descriptor_base
 descriptor_base + layer_count <= MAX_LAYERS
```

The controller still owns one dense engine and alternates the same two
activation buffers across layers.

## Pipeline request

Before `pipeline_start_valid && pipeline_start_ready`, software or a future
AXI-Lite wrapper must configure:

1. all Bottom and Top descriptors;
2. all referenced INT8 weights and INT24 biases;
3. the Bottom input activation vector;
4. four signed INT16x8 embedding vectors;
5. Bottom descriptor base/count;
6. Top descriptor base/count;
7. Bottom initial activation buffer;
8. Top interaction-input activation buffer;
9. interaction right shift.

One accepted pipeline start then performs all internal handoffs. The host does
not separately start the interaction engine or Top MLP.

## Fixed interaction shape

The Stage 2N interaction remains fixed at:

```text
Bottom output dimension = 8
Embedding vectors        = 4 x INT16[8]
Interaction vectors      = 5 x INT16[8]
Interaction output       = INT16[18]
```

The 18 interaction values are packed into the Top input activation buffer as:

```text
chunk 0: lanes 0..15, mask 0xFFFF
chunk 1: lanes 0..1,  mask 0x0003
```

## Result semantics

Only the Top-MLP final-layer stream is externally visible. It preserves the
existing ready/valid contract. Data, index, last, and tag remain stable while
`result_valid=1 && result_ready=0`.

`done` is a one-cycle pulse after the complete Top result stream has been
accepted and the shared MLP controller has drained its result FIFO.

## Validation target

The v1 test uses:

```text
Bottom:      descriptor 0, 4 -> 8
Interaction: verified 5x8 -> 18 ordering
Top:         descriptor 1, 18 -> 1
Expected Top result: -60
```

It runs the pipeline twice and applies 12 cycles of final-result backpressure on
the second run. Passing the test establishes internal stage sequencing and data
handoff in RTL simulation; it is not yet board evidence.
