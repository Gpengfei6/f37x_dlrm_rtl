# Interface specification v0

## Common ready/valid rule

A transfer occurs on a rising clock edge only when `valid && ready` is true.
The producer holds `valid` and its complete payload stable until transfer.  A
consumer may deassert `ready` for any number of cycles.  Reset is synchronous,
active high, and clears in-flight transactions.  IDs and vectors are packed with
element zero in the least-significant slice: element `i` occupies
`[i*WIDTH +: WIDTH]`.

## Module contracts

### `rv_fifo`

- Input: `in_valid`, `in_ready`, `in_data[DATA_WIDTH-1:0]`.
- Output: `out_valid`, `out_ready`, `out_data[DATA_WIDTH-1:0]`.
- Status: `full`, `empty`, `count`.
- Fall-through data is not provided when empty.  When full, a simultaneous pop
  permits a push in the same cycle.  Ordered data is retained under backpressure.

### `saturating_round`

- Combinational signed `in_data[IN_WIDTH-1:0]` to signed
  `out_data[OUT_WIDTH-1:0]`.
- Applies the exact rule in `fixed_point_spec_v0.md`; it has no handshake or
  sequential latency.

### `relu_quant`

- Combinational wrapper around `saturating_round`, followed by ReLU.
- It has no handshake or sequential latency.

### `dot_product_core`

- One transaction contains packed `in_data`, packed `weight_data`, and `bias_data`.
- One registered result is produced.  Latency is one rising edge from accepted
  input to asserted `out_valid`; the result register holds under backpressure.
- A consumed result and a new input may transfer on the same edge, so peak
  throughput is one dot product per cycle in this verification-oriented parallel
  implementation.

### `dense_layer_core`

- Accepts one packed aggregate vector, then evaluates output neurons sequentially
  using one `dot_product_core` instance.
- Weights and biases are local arrays optionally initialized by `$readmemh` files.
- The packed output is held stable until accepted.
- Accepted-input-to-`out_valid` latency is `2*DENSE_OUT_DIM` cycles when
  downstream is ready (8 cycles for 4 outputs).  Because the phase-1 controller
  returns to idle after output acceptance, the initiation interval is 9 cycles
  for the default configuration; phase 1 prioritizes verification over rate.

### `embedding_mem_model`

- Request: `req_valid/req_ready` plus one ID.
- Response: `rsp_valid/rsp_ready` plus one packed row.
- One-entry response buffer; one-cycle request-to-response latency.  Response data
  is stable under backpressure.  It can consume a response and accept a new
  request on the same edge.

### `minimal_recommendation_pipeline`

- Input transaction: `NUM_LOOKUPS` packed IDs.
- Output transaction: one packed dense/ReLU vector.
- IDs are read sequentially; returned rows are summed, then sent to the dense
  layer.  Only one recommendation request is in flight in phase 1.
- From input acceptance to asserted output valid, no-stall latency is
  `2*NUM_LOOKUPS + 1 + 2*DENSE_OUT_DIM` cycles (17 cycles by default).
  Backpressure can extend it without changing data.

### `dlrm_minimal_top`

- Direct simulation wrapper around `minimal_recommendation_pipeline`.
- Exposes only clock/reset and the input/output ready-valid streams.
- It is not a Vitis RTL Kernel interface and has no AXI/HBM signals.

## Planned seam interfaces

The current packed-ID input is the insertion point for a future duplicate-ID
merge/fan-out block.  The `embedding_mem_model` request/response contract is the
replacement seam for HBM/AXI and channel scheduling.  Queues may later be placed
between embedding responses, aggregation, and dense computation so a dynamic
micro-batch scheduler can overlap memory and compute without changing arithmetic
module contracts.
