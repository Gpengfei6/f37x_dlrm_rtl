# Stage 2N-A14.1 HBM Lookup RTL Prototype Acceptance

## 1. Baseline commit

- Repository: `D:\FpgaWork\f37x_dlrm_rtl_a14_hbm`
- Branch: `work/stage2n-a14-hbm-embedding`
- Baseline commit: `63ae1c4c44a991012ec605a8355b2b90cbb0bc58`
- Baseline subject: `feat(f37x): complete Stage 2N-A13 cycle-counter board validation`
- Acceptance date: 2026-08-20

The accepted Stage 2N-A13 RTL, kernel top, Host, scripts, and A13 configuration
remain unchanged. A14.1 is an isolated prototype authorized by the
`Stage 2N-A14.1 HBM Lookup Prototype Authorization` section of `AGENTS.md`.

## 2. A14.1 objective

The objective of A14.1 is to validate the minimum standalone RTL behavior
needed for a future FPGA-side embedding lookup path:

1. accept one embedding row index through a ready/valid request interface;
2. calculate the relative byte address as `lookup_index << 4`;
3. issue one single-beat AXI4 read transaction;
4. return one packed 128-bit vector through a ready/valid response interface;
5. preserve the response and metadata under output backpressure;
6. compare all 64 valid rows against a deterministic simulation golden model.

A14.1 does not integrate the prototype into the A13 kernel and does not access
physical HBM.

## 3. RTL module description

Accepted RTL:

`rtl/hbm/dlrm_hbm_embedding_lookup_stage2n_a14_v1.sv`

SHA256:

`2b46687c8bd10450568f9a17f1bd58c9e4a2445159aa450a8dff4680c527d0cf`

The module contains one request register, one AXI address register, one
128-bit response register, response index/error metadata, and the following
four-state controller:

| State | Behavior |
|---|---|
| `IDLE` | Assert request ready and accept one row index. |
| `SEND_AR` | Hold AXI ARVALID and address attributes until ARREADY. |
| `WAIT_R` | Assert RREADY and accept exactly one AXI read-data beat. |
| `RESP` | Hold response data, index, and error stable until response ready. |

The state sequence permits only one outstanding read. No new request is
accepted until the previous lookup response has been consumed.

For a valid default index, the registered address is:

```text
byte_addr = lookup_index << 4
```

For a non-power-of-two `ROWS` parameter, an out-of-range index is rejected
without issuing AXI traffic and produces a deterministic zero response with
the error flag set. With the accepted default `ROWS=64`, every six-bit index
encoding is valid.

## 4. AXI interface description

The prototype exposes a standalone AXI4 read master subset.

### Read-address channel

| Signal group | Accepted behavior |
|---|---|
| `ARID` | Fixed to zero. |
| `ARADDR` | Registered relative byte address, `index << 4`. |
| `ARLEN` | `0`, requesting one transfer only. |
| `ARSIZE` | `4`, representing 16 bytes per transfer. |
| `ARBURST` | `INCR`; with `ARLEN=0` this remains a single-beat transaction. |
| `ARLOCK/ARCACHE/ARPROT/ARQOS` | Fixed protocol attributes. |
| `ARVALID/ARREADY` | Address transfers only when both are asserted; ARADDR remains stable while stalled. |

### Read-data channel

| Signal group | Accepted behavior |
|---|---|
| `RID` | Expected to match fixed ID zero. |
| `RDATA` | One 128-bit embedding vector. |
| `RRESP` | Expected to be AXI OKAY. |
| `RLAST` | Required on the accepted beat. |
| `RVALID/RREADY` | Data transfers only in `WAIT_R` when both are asserted. |

An AXI response error, missing `RLAST`, or nonzero response ID is reported by
`lookup_rsp_error`. The module implements no AXI write channel, multi-beat
burst, multiple outstanding request, or response reordering.

## 5. Parameter configuration

| Parameter | Accepted value | Meaning |
|---|---:|---|
| `ROWS` | 64 | Number of valid embedding rows. |
| `DIM` | 8 | Number of elements in one vector. |
| `ELEMENT_WIDTH` | 16 | Width of each raw signed two's-complement element. |
| `DATA_WIDTH` | 128 | AXI and lookup response width. |
| `AXI_ADDR_WIDTH` | 64 default; 32 in TB | Byte-address width. |
| `AXI_ID_WIDTH` | 1 | Fixed-zero AXI ID width. |
| `INDEX_WIDTH` | 6 | Derived from `ROWS=64`. |

The accepted configuration has an embedding row size of 16 bytes and requires
`DIM * ELEMENT_WIDTH == DATA_WIDTH`.

Packing is:

```text
lookup_rsp_data[16*lane +: 16] = table[row][lane]
```

Lane 0 occupies bits `[15:0]`; lane 7 occupies bits `[127:112]`.

## 6. XSim verification result

Testbench:

`tb/tb_dlrm_hbm_embedding_lookup_stage2n_a14_v1.sv`

SHA256:

`1e70b31b7e74435f3cda84a9cf0b21f595ebdbbdad24d849c3ef2d713f17f58b`

The frozen RTL and testbench were re-run for this acceptance on 2026-08-20
using Vivado Simulator 2022.1, SW Build 3526262.

| Step | Result |
|---|---|
| `xvlog -sv` compile | PASS, exit code 0 |
| `xelab` elaboration | PASS, exit code 0 |
| `xsim -runall` | PASS, exit code 0 |
| Test cases | 64/64 |
| AR handshakes | 64 |
| R handshakes | 64 |
| Simulation completion time | 6245 ns |
| Fatal errors | 0 |

Final simulation marker:

```text
tb_dlrm_hbm_embedding_lookup_stage2n_a14_v1: PASS cases=64
```

## 7. PASS evidence

The self-checking fake AXI memory contains 64 rows. Each row is generated as:

```text
value[row][lane] = row*8 + lane - 256
row_addr = row*16
```

The testbench verifies:

- all indices from 0 through 63;
- addresses from byte 0 through byte 1008 in exact 16-byte steps;
- 16-byte address alignment;
- `ARLEN=0`, `ARSIZE=4`, INCR transaction type, and AXI ID zero;
- exactly one AR and one R handshake for every accepted lookup;
- exact 128-bit output against an independently generated expected vector;
- returned request index and clear response-error flag;
- stable ARADDR while the fake memory stalls ARREADY;
- stable response data, index, and error under deterministic output
  backpressure;
- return to `IDLE` after the 64th response.

Design documentation:

`docs/STAGE2N_A14_HBM_LOOKUP_RTL_DESIGN.md`

SHA256 at acceptance:

`461dc7bf1eeddb9d8f0f650e4e53e9d2aa7899a795ed8046714bd3445557cfd3`

Acceptance status:

```text
STAGE2N_A14_A1_ACCEPTANCE=PASS
A14_A1_XVLOG=PASS
A14_A1_XELAB=PASS
A14_A1_XSIM=PASS
A14_A1_CASES=64/64
A14_A1_PHYSICAL_HBM_VALIDATION=NOT_RUN
```

## 8. Limitations

- This is an isolated protocol RTL prototype, not an A13 kernel modification.
- The prototype is not instantiated by an F37X kernel top.
- No Vitis `m_axi` kernel interface or `connectivity.sp` HBM binding exists.
- The fake AXI memory is not a physical HBM controller or timing model.
- No synthesis, implementation, timing closure, XO, xclbin, XRT BO, DMA, or
  board operation was performed for A14.1.
- The design supports one table, one single-beat lookup, one outstanding read,
  and in-order response only.
- It does not implement multi-bank mapping, burst reads, multiple outstanding
  transactions, caching, prefetching, duplicate coalescing, pooling,
  scheduling, or request reordering.
- The 6245 ns value is the total testbench simulation completion time and must
  not be described as lookup latency or hardware performance.
- A14.1 PASS validates address generation, AXI transaction behavior, vector
  packing, response stability, and software-golden comparison only. It does not
  validate F37X physical HBM connectivity, bandwidth, latency, or performance
  improvement.
