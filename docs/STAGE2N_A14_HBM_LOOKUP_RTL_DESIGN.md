# Stage 2N-A14.1 HBM Lookup RTL Prototype Design

## 1. Scope and evidence boundary

This document describes the isolated RTL prototype authorized by the
`Stage 2N-A14.1 HBM Lookup Prototype Authorization` section of `AGENTS.md`.

The prototype validates only:

- row-index-to-byte-address generation;
- a single-outstanding AXI4 read transaction;
- 128-bit embedding-vector transfer and lane packing;
- ready/valid behavior and simulation comparison with deterministic fake memory.

It is not connected to the accepted A13 kernel, does not add an F37X kernel
`m_axi` port, does not bind a Vitis port to HBM, and does not prove physical
HBM connectivity, bandwidth, latency, or performance improvement.

## 2. Module architecture

The standalone module is:

`rtl/hbm/dlrm_hbm_embedding_lookup_stage2n_a14_v1.sv`

The data path is:

```text
lookup request (row index)
        |
        v
 index register -- index << 4 --> AXI AR address register
                                      |
                                      v
                              one AXI read beat
                                      |
                                      v
                        128-bit response register
                                      |
                                      v
                         lookup response interface
```

Default parameters are:

| Parameter | Value | Meaning |
|---|---:|---|
| `ROWS` | 64 | valid row count |
| `DIM` | 8 | elements per embedding vector |
| `ELEMENT_WIDTH` | 16 | signed element width |
| `DATA_WIDTH` | 128 | one complete vector per AXI beat |
| `AXI_ADDR_WIDTH` | 64 | standalone AXI byte-address width |
| `AXI_ID_WIDTH` | 1 | fixed ID-zero channel width |

Elaboration checks require `DIM*ELEMENT_WIDTH == DATA_WIDTH`, a 128-bit
16-byte row, and sufficient AXI address width.

## 3. Lookup interface

| Signal | Direction | Width | Description |
|---|---|---:|---|
| `clk` | input | 1 | rising-edge clock |
| `rst` | input | 1 | synchronous active-high reset |
| `lookup_req_valid` | input | 1 | request is present |
| `lookup_req_ready` | output | 1 | module can accept a request |
| `lookup_req_index` | input | `INDEX_WIDTH` | embedding row index |
| `lookup_rsp_valid` | output | 1 | response and metadata are valid |
| `lookup_rsp_ready` | input | 1 | consumer accepts the response |
| `lookup_rsp_data` | output | 128 | eight packed INT16 elements |
| `lookup_rsp_index` | output | `INDEX_WIDTH` | original request index |
| `lookup_rsp_error` | output | 1 | invalid ID or AXI/protocol error |

A request transfers only when `lookup_req_valid && lookup_req_ready`.
A response transfers only when `lookup_rsp_valid && lookup_rsp_ready`.
During response backpressure, data, index, and error remain in registers and
therefore remain stable.

For the default `ROWS=64`, all six-bit index encodings are valid. The generic
range check prevents an AXI request for an out-of-range index if `ROWS` is
changed to a non-power-of-two value.

## 4. AXI4 read-master interface

The module exposes only the AXI4 read address and read data channels required by
the standalone prototype.

### Read address channel

- `m_axi_arid`: fixed to zero;
- `m_axi_araddr`: registered byte address;
- `m_axi_arlen=0`: exactly one transfer;
- `m_axi_arsize=4`: 16 bytes per transfer;
- `m_axi_arburst=INCR`;
- `m_axi_arvalid` remains asserted in `SEND_AR` until `m_axi_arready`.

The frozen address relation is:

```text
byte_addr = lookup_index << 4
```

Therefore rows 0 through 63 map to byte addresses 0 through 1008 in 16-byte
steps. The address is relative to a future table allocation, not a physical
F37X HBM address.

### Read data channel

- `m_axi_rready` is asserted only in `WAIT_R`;
- one accepted `m_axi_rvalid` beat is captured into the response register;
- `RRESP` must be OKAY, `RLAST` must be asserted, and `RID` must be zero;
- any violation sets `lookup_rsp_error`;
- no second AR request can be issued until the current lookup response is
  consumed.

No write channel, burst, multiple outstanding transaction, reordering, or
physical memory controller is implemented.

## 5. FSM

| State | Function | Exit condition |
|---|---|---|
| `IDLE` | assert request ready and accept one lookup index | valid in-range index → `SEND_AR`; invalid index → `RESP` |
| `SEND_AR` | hold ARVALID, address, and attributes stable | `ARVALID && ARREADY` → `WAIT_R` |
| `WAIT_R` | assert RREADY and wait for one read beat | `RVALID && RREADY` → capture data/status and enter `RESP` |
| `RESP` | hold response data/index/error stable | `lookup_rsp_valid && lookup_rsp_ready` → `IDLE` |

The four states structurally enforce one outstanding read.

## 6. Embedding vector packing

The response follows the A14 phase-1 contract:

```text
lookup_rsp_data[16*lane +: 16] = table[row][lane]
```

Lane 0 occupies bits [15:0] and lane 7 occupies bits [127:112]. Values are raw
signed two's-complement INT16 payloads; the lookup module does not perform
rounding, saturation, ReLU, pooling, or any other numeric transformation.

## 7. Simulation verification method

The independent self-checking testbench is:

`tb/tb_dlrm_hbm_embedding_lookup_stage2n_a14_v1.sv`

It implements a 64-row fake AXI memory. Each row is initialized as:

```text
value[row][lane] = row*8 + lane - 256
```

The test performs all 64 lookups, index 0 through 63, and checks:

- exact address `row*16`;
- 16-byte alignment;
- `ARLEN=0`, `ARSIZE=4`, INCR burst, and AXI ID zero;
- exactly 64 AR handshakes and 64 R handshakes;
- exact 128-bit output against an independently generated expected vector;
- returned index and clear error status;
- AR address stability while ARREADY is stalled;
- response data/index/error stability under deterministic output backpressure;
- return to `IDLE` after the final response.

The required acceptance marker is:

```text
tb_dlrm_hbm_embedding_lookup_stage2n_a14_v1: PASS cases=64
```

## 8. Limitations

- The prototype is not instantiated by any A13 or F37X kernel top.
- It has no Vitis kernel `m_axi` interface declaration.
- It has no `connectivity.sp` HBM bank mapping.
- It does not allocate an XRT BO, execute DMA, generate an XO/xclbin, or access a
  board.
- It supports one table, one direct lookup at a time, one 128-bit beat, and one
  outstanding transaction.
- It does not implement bursts, multiple outstanding reads, caching,
  coalescing, pooling, scheduling, multi-bank mapping, or request reordering.
- The testbench is a protocol-level fake memory, not a physical HBM model.
- Simulation success proves functional protocol behavior only; it does not prove
  F37X HBM connectivity, timing, bandwidth, latency, or speedup.

## 9. Local simulation result

The standalone RTL and testbench were compiled and run locally with Vivado
2022.1 XSim on 2026-08-20:

- `xvlog -sv`: PASS;
- `xelab`: PASS;
- `xsim -runall`: PASS;
- simulated rows: 64/64;
- AR handshakes: 64;
- R handshakes: 64;
- final simulation time: 6245 ns;
- fatal errors: 0.

Final marker:

```text
tb_dlrm_hbm_embedding_lookup_stage2n_a14_v1: PASS cases=64
```

This result is local protocol simulation only and does not change the physical
HBM evidence boundary stated above.
