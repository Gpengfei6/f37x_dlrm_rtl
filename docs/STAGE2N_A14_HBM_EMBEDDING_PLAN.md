# Stage 2N-A14 HBM Embedding Architecture Freeze — Phase 1

## 1. Baseline and evidence boundary

Stage 2N-A14 starts from commit `63ae1c4` (`Stage 2N-A13 cycle-counter board validation`). A13 is frozen and remains the accepted functional baseline.

A13 has proved the following on one F37X/XCVU37P at 100 MHz:

- Bottom MLP, Feature Interaction, and Top MLP execute inside the FPGA;
- Bottom and Top time-share the same dense engine;
- one accepted START advances the three internal stages without a second Host start;
- 256 deterministic samples match the software reference;
- Bottom, Interaction, Top, and Total cycle counters report 322, 100, 744, and 1174 cycles.

Those results do **not** prove A14 HBM behavior. This first A14 phase creates only an architecture/data-layout contract and deterministic software-golden asset. It does not change or validate RTL, an HBM interface, an xclbin, or board execution.

## 2. A13 current limitation

A13 has no FPGA-side embedding lookup. The CPU resolves categorical IDs to four 8-element embedding vectors and then writes the resulting INT16 vectors into FPGA registers through the AXI4-Lite control path.

Consequently:

- the FPGA never receives a categorical row ID as a memory lookup request;
- the A13 kernel top has no `m_axi` HBM port;
- `config/stage2n_a13_v1.cfg` has no `connectivity.sp` HBM binding;
- the Host performs embedding lookup and fine-grained register programming before every inference;
- the measured 11.74 us remains the FPGA-internal START-accepted-to-first-final-result-visible interval and is not a CPU–FPGA end-to-end embedding lookup latency.

## 3. Why FPGA HBM embedding lookup is needed

Embedding tables are naturally row-addressed and can exceed practical on-chip storage. Retaining lookup on the CPU keeps the sparse-feature data path outside the FPGA and requires the Host to materialize and transfer every embedding vector before START.

A later A14 hardware phase is intended to let the FPGA consume a row ID, calculate the corresponding row address in HBM, read one complete embedding vector, and provide that vector to the existing Feature Interaction input path. This establishes an FPGA-resident embedding data path and reduces mandatory Host participation between row-ID preparation and internal inference. No latency, bandwidth, or speedup claim is made until the real HBM path is implemented and measured.

## 4. A14 target architecture

The frozen first target is deliberately narrow:

- one F37X card;
- one embedding table;
- one physical HBM bank selection: `HBM[0]`;
- 64 logical rows;
- 8 signed INT16 elements per row;
- one 128-bit vector per row;
- row-major, contiguous storage;
- direct lookup: one valid row ID selects exactly one row;
- in-order request/response behavior for the first implementation.

The A14 lookup payload is INT16 because the accepted A13 Feature Interaction input path consumes 8-element INT16 vectors. This A14 table does not modify the older phase-1 INT8 embedding specification and does not alter any A13 arithmetic or quantization behavior.

## 5. Phase-1 scope

This phase contains only:

1. this architecture freeze document;
2. a static A14 HBM data-layout configuration;
3. a deterministic 64-row JSON embedding table for software-golden validation;
4. address, packing, range, and future handshake verification criteria.

The configuration records the intended bank and layout but intentionally contains no `connectivity.sp` line because no A14 `m_axi` RTL port exists yet.

## 6. Non-goals

The following are explicitly outside this phase:

- modifying any A13 RTL, Host, testbench, XDC, Tcl, Vitis, or Vivado file;
- creating an `m_axi` port, AXI master, burst engine, clock-domain crossing, or HBM controller;
- selecting a platform-specific AXI address aperture;
- multi-bank mapping, striping, replication, scheduling, arbitration, caching, prefetching, duplicate-request coalescing, or pooling;
- XRT BO allocation, BO-to-bank placement, DMA input, batch input, or Host execution changes;
- synthesis, implementation, XO/xclbin generation, server work, board programming, or board testing;
- changing Bottom, Feature Interaction, Top, the A13 descriptor format, fixed-point arithmetic, expected results, or cycle-counter semantics;
- claiming HBM throughput, latency, resource reduction, or end-to-end speedup.

Any later phase that adds an HBM port or physical bank binding requires a separate interface review and explicit authorization.

## 7. Frozen data layout

| Field | Frozen value |
|---|---:|
| HBM bank selector | `HBM[0]` |
| Lookup mode | `single_bank_direct` |
| Number of rows, R | 64 |
| Embedding dimension, D | 8 |
| Element type | signed INT16, two's complement |
| Element width, W | 16 bits |
| Vector width | 128 bits |
| Row stride | 16 bytes |
| Base byte address | 0 within the table image |
| Total table payload | 1024 bytes |
| Byte order | little-endian |
| Lane packing | lane 0 occupies bits [15:0] |

The base address is relative to the start of the future table allocation. It is not an F37X shell physical address and is not a `connectivity.sp` mapping.

## 8. Address calculation

Let:

- `r` be the row ID, where `0 <= r < R`;
- `d` be the element lane, where `0 <= d < D`;
- `A_base` be the byte address of the first table row;
- `W` be the element width in bits;
- `D` be the embedding dimension.

One vector occupies:

```text
B_vector = D * W / 8 = 8 * 16 / 8 = 16 bytes
```

The row base byte address is:

```text
A_row(r) = A_base + r * B_vector
         = A_base + 16r
```

The byte address of element `d` in row `r` is:

```text
A_element(r,d) = A_base + (r * D + d) * W / 8
               = A_base + 16r + 2d
```

For the phase-1 table, `A_base=0`. Row 0 starts at byte 0, row 63 starts at byte 1008, and the final INT16 element occupies bytes 1022–1023. There are no gaps between rows.

The 128-bit response vector is packed as:

```text
vector[16d +: 16] = table[r][d],  0 <= d < 8
```

Thus lane 0 occupies bits [15:0] and lane 7 occupies bits [127:112].

The deterministic test value is:

```text
table[r][d] = r * 8 + d - 256
```

The first row is `[-256, -255, ..., -249]`; the last row is `[248, 249, ..., 255]`. Every value is representable as signed INT16.

## 9. Lookup and error contract for the future RTL phase

The first hardware lookup implementation shall preserve these semantics:

- a request is accepted only on a request valid/ready handshake;
- each accepted in-range row ID produces exactly one 128-bit response in request order;
- response data and metadata remain stable while response valid is asserted and response ready is deasserted;
- same-edge response consumption and refill may be supported, but must not duplicate or drop a row;
- reset clears outstanding response-valid state;
- a row ID outside `0..63` must not generate an HBM read; the future interface review must provide an explicit invalid-ID status and a deterministic zero-vector response;
- the direct-lookup mode issues no coalescing, reordering, caching, or multi-bank scheduling.

These are verification requirements, not statements that an A14 RTL block currently exists.

## 10. Verification standard

### 10.1 Phase-1 static checks

Phase 1 passes only if all of the following are true:

- exactly 64 table entries exist and `row_id` is the sequence 0 through 63;
- every row contains exactly 8 JSON integers;
- every value lies in the signed INT16 interval `[-32768, 32767]`;
- every value equals `row_id * 8 + lane - 256`;
- `byte_address == row_id * 16` for every row;
- adjacent row addresses differ by exactly 16 bytes;
- the final payload extent is exactly 1024 bytes;
- packing and unpacking each row as eight little-endian signed INT16 lanes reproduces the JSON values;
- the configuration and JSON metadata agree on bank, row count, dimension, element width, vector width, stride, and lookup mode;
- Git shows only the three authorized A14 phase-1 files as additions.

### 10.2 Future RTL simulation gate

A later RTL phase must not be marked PASS until a self-checking testbench verifies:

- all 64 valid row IDs against the JSON software golden;
- sequential, reverse, and deterministic pseudo-random row order;
- consecutive full-rate lookup requests;
- request-side and response-side backpressure;
- stable response data under stall;
- same-edge consume/refill;
- reset with an outstanding request/response;
- no missing, duplicate, or reordered responses;
- first and last row boundaries;
- defined invalid-ID behavior;
- bit-exact 128-bit lane packing.

### 10.3 Future target gate

Synthesis, implementation, physical HBM binding, XRT BO placement, XO/xclbin generation, and F37X board validation are **not run** in this phase. They require later evidence that records the actual A14 `m_axi` port, `connectivity.sp` binding, bank allocation, timing, resources, HBM read behavior, and board results. Until then, `A14_HBM_LOOKUP=NOT_IMPLEMENTED`.

## 11. Phase-1 exit statement

The phase-1 deliverables freeze a deterministic single-bank address and data contract only. They provide a reproducible starting point for a separately authorized A14 RTL/interface phase while preserving the accepted A13 implementation unchanged.
