# FPGA DLRM Architecture

This document describes the current accepted A13 architecture and the isolated
A14 lookup direction. It intentionally distinguishes implemented integration
from planned integration.

## 1. A13 Baseline

### 1.1 System boundary

A13 is the accepted integrated inference baseline. The Host configures the
model and input through AXI4-Lite, resolves categorical embedding IDs on the
CPU, writes four embedding vectors to the FPGA, and issues one START.

```text
Host / CPU
  |-- descriptors, weights, biases
  |-- dense input activations
  |-- four CPU-resolved INT16x8 embedding vectors
  `-- START
          |
          v
  AXI4-Lite control adapter
          |
          v
  Bottom MLP: 8 -> 16 -> 8
          |
          | Bottom output becomes interaction vector 0
          v
  Feature Interaction: 5 x 8 -> 18
          |
          | two activation chunks: 16 + 2
          v
  Top MLP: 18 -> 32 -> 16 -> 1
          |
          v
  INT16 result + index + last + descriptor tag
```

The internal controller automatically advances Bottom, Interaction, and Top
after one accepted START. This is an ordered segmented pipeline; it does not
mean that different samples overlap in all three stages.

### 1.2 Shared dense engine and activation storage

Bottom and Top are runtime descriptor segments executed at different times by
the same dense engine. Layer descriptors select dimensions, weight/bias
indices, output shift, and activation behavior. Ping-pong activation buffers
alternate read and write ownership between dense layers.

```text
descriptor_base + local layer index
                |
                v
       shared dense engine
       /                 \
activation buffer A   activation buffer B
       read/write ownership alternates by layer
```

The accepted A13 capacity is:

- 8 descriptors;
- 2048 signed INT8 weights;
- 128 signed INT24 biases;
- 16 processing elements;
- signed INT16 activations and results;
- signed INT48 accumulation.

The current trained-model instance uses five descriptors, 1360 weights, and 73
biases.

### 1.3 Feature Interaction

The A13 interaction input contains:

- vector 0: the eight-element Bottom output;
- vectors 1–4: four CPU-resolved eight-element embedding vectors.

The engine preserves vector 0 and appends the ten lower-triangle pairwise dot
products, producing 18 Top-input values. Runtime shift, fixed-point rounding,
and saturation follow the repository contract and RTL.

### 1.4 Cycle observation

A13 observes, but does not alter, the A10 v2 arithmetic path. Four unsigned
32-bit saturating counters report:

- Bottom cycles;
- Interaction cycles;
- Top cycles;
- Total cycles.

An accepted START restarts measurement. Counting freezes when the first final
`result_valid && result_last` is visible, so later Host polling, result
backpressure, POP, and done clearing are excluded. The accepted measurements at
100 MHz are 322, 100, 744, and 1174 cycles respectively.

### 1.5 A13 interface boundary

The A13 kernel top exposes AXI4-Lite control only. It has no `m_axi` memory
master. Embedding lookup and vector preparation therefore remain on the CPU.
The 11.74 microsecond total count is internal FPGA pipeline latency, not full
Host-to-FPGA latency.

## 2. A14 Direction

### 2.1 Intended data path

The desired sparse-side direction is:

```text
Embedding row ID
       |
       v
FPGA HBM lookup
       |
       v
INT16x8 embedding vector
       |
       v
Feature Interaction
```

A14 implements only the lookup portion as a separate top-level prototype. The
simulation-accepted v1 path uses a relative row offset. The A14.5 v2 source
adds a runtime table allocation base, passed local XSim at `d428e8b`, and
passed the exact-target XO-only packaging/metadata gate at tested server HEAD
`4096614`:

```text
AXI4-Lite
  |-- LOOKUP_INDEX
  |-- TABLE_BASE (A14.5 v2)
  `-- START
        |
        v
A14 kernel wrapper
        |
        v
A14.1 lookup FSM
  IDLE -> SEND_AR -> WAIT_R -> RESP
        |
        v
logical 128-bit m_axi_gmem read
        |
        v
RESULT0..RESULT3
```

### 2.2 Frozen A14.1 lookup contract

- rows: 64;
- embedding dimension: 8;
- element type: signed INT16;
- vector width: 128 bits;
- row stride: 16 bytes;
- address: `byte_addr = lookup_index << 4`;
- one outstanding read;
- one beat per request;
- `ARLEN=0`;
- no burst optimization;
- in-order request/response;
- complete ready/valid response retention under backpressure.

The A14.1 v1 byte address is relative to the beginning of the connected memory
space. It has no Host/XRT buffer-allocation address and must not be used as a
physical-HBM ABI.

The deterministic row formula used by the software and fake-memory golden is:

```text
value[row][lane] = row * 8 + lane - 256
```

### 2.3 A14.5 runtime table-base ABI

A14.5 v2 retains the row format and single-outstanding protocol but uses:

```text
read_address = TABLE_BASE + (lookup_index << 4)
```

`TABLE_BASE` is captured atomically with the index when START is accepted. A
misaligned base, invalid row, or 64-bit addition overflow produces a zero/error
response without an AXI read. Packaging represents the two control words as a
single 64-bit global-memory argument associated with `m_axi_gmem`.

This ABI is implemented in source and its local functional XSim gate is PASS.
The corrected exact-target retry generated a 12,951-byte XO whose returned
`kernel.xml` contains the intended 8-byte global pointer and whose
`component.xml` proves a 64-bit AXI address interface. The retained
`kernel.xml range=0xFFFFFFFF` is descriptive rather than the sole width proof;
the versioned validator requires consistent RTL, component, IP-XACT, and
pointer evidence and passed that complete gate.

For Vivado 2020.2, address width is accepted only when these layers agree:

```text
RTL C_M_AXI_GMEM_ADDR_WIDTH=64 and AWADDR/ARADDR[63:0]
        +
IP-XACT ADDR_WIDTH/model/user parameters=64
        +
IP-XACT address space=2^64 bytes
        +
TABLE_BASE size=8, addressQualifier=1, port=m_axi_gmem
```

The generated kernel port `range` is recorded but is not the sole width proof.
A real 32-bit RTL/component path still fails the combined gate.

### 2.4 A14.6 link-only boundary

A14.6 does not change the v2 RTL or ABI. It consumes the accepted exact-target
XO and applies platform connectivity during Vitis link:

```text
dlrm_f37x_rtl_kernel_stage2n_a14_v2.xo
                    |
                    | nk=...a14_v2:1:dlrm_a14_1
                    | sp=dlrm_a14_1.m_axi_gmem:HBM[0]
                    | target=hw, clock=100 MHz
                    v
                 xclbin
```

The link output may establish platform integration, the requested logical
CU-to-bank metadata, exact VU37P implementation, and routed timing. It cannot
establish XRT allocation semantics, physical HBM reads, row-data correctness,
or end-to-end DLRM behavior because no Host or FPGA access exists in A14.6.

### 2.5 Wrapper register boundary

The standalone A14 wrapper exposes:

| Offset | Register | Role |
|---:|---|---|
| `0x00` | `CONTROL` | START and status |
| `0x10` | `LOOKUP_INDEX` | row ID |
| `0x18` | `TABLE_BASE_LO` | v2 table-base bits 31:0; absent from v1 |
| `0x1C` | `TABLE_BASE_HI` | v2 table-base bits 63:32; absent from v1 |
| `0x20` | `RESULT0` | lanes 0–1 |
| `0x24` | `RESULT1` | lanes 2–3 |
| `0x28` | `RESULT2` | lanes 4–5 |
| `0x2C` | `RESULT3` | lanes 6–7 |

The wrapper exposes a logical `m_axi_gmem` read master. AXI write channels are
inactive. Future link configuration proposes:

```text
dlrm_f37x_rtl_kernel_stage2n_a14_v1_1.m_axi_gmem -> HBM[0]
```

That configuration is a plan, not proof of a physical connection.

## 3. A13 and A14 Relationship

| Property | A13 accepted baseline | A14/A14.5 standalone prototype |
|---|---|---|
| Top-level purpose | Complete ordered Bottom–Interaction–Top execution | One embedding-row lookup |
| Embedding source | CPU-resolved vectors over AXI4-Lite | Logical AXI4 memory read |
| Memory master | None | `m_axi_gmem`, read-only prototype |
| Address model | No HBM address | v1 relative row offset; v2 runtime 64-bit base |
| Physical HBM | Not used | Not yet validated |
| Board evidence | Accepted F37X functional evidence | None |
| Integration with dense pipeline | Yes | No |

Do not combine the two columns into a claim that the current FPGA executes a
complete HBM-resident DLRM. A future separately authorized integration stage is
required.

## 4. Verification Architecture

### A13

- self-checking XSim for cycle counts, restart, backpressure, and result
  metadata;
- C++11/XRT Host checks on the authorized F37X device;
- bit-exact comparison against 256 deterministic trained-model samples;
- target VU37P implementation and timing evidence.

### A14

- standalone fake AXI memory covering all 64 rows;
- directed and randomized wrapper cases;
- explicit AR/R handshake counts;
- address alignment, single-outstanding, response error, and backpressure
  assertions;
- future target packaging, Vitis link, and board evidence remain separate
  gates.

### A14.5 local XSim evidence

- all 64 rows passed at a non-zero base above 4 GiB;
- exact `TABLE_BASE + row*16` AR address checks passed;
- unaligned-base, out-of-range-index, and overflow zero/error behavior passed
  without AXI reads;
- wrapper table-base low/high programming and capture-on-START behavior passed;
- lookup 67/67 and wrapper 17/17 cases passed with exact AR/R counts.

### A14.5 exact-target XO evidence

- attempt 1 at `de9276e` generated an intact exact-VU37P XO;
- returned inspection confirms 128-bit data, an 8-byte `TABLE_BASE`
  global-memory argument on `m_axi_gmem`, 64-bit component address ports and
  parameters, and a `2^64` IP-XACT address space;
- Vivado 2020.2 retained `kernel.xml range=0xFFFFFFFF`; the old range-only gate
  stopped and its `ERR` trap produced an inaccurate `BLOCKED_NOT_RUN` status;
- the versioned retry records that range while requiring the complete
  cross-layer 64-bit evidence;
- the corrected retry at tested server HEAD `4096614` passed: XO size 12,951
  bytes, TABLE_BASE ABI PASS, address-width evidence PASS, matching standalone
  and in-XO XML hashes, seven reviewed warnings, zero critical warnings, and
  zero errors;
- no Vitis link, xclbin, physical HBM, Host, or FPGA operation occurred.

## 5. Source Map

Accepted A13 implementation:

- `rtl/pipeline/dlrm_internal_pipeline_controller_stage2n_a13_v1.sv`
- `rtl/f37x/dlrm_internal_pipeline_axi_lite_adapter_stage2n_a13_v1.sv`
- `rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a13_v1.sv`
- `tb/tb_dlrm_f37x_rtl_kernel_stage2n_a13_cycle_counter_v1.sv`
- `host/stage2n_a13_cycle_counter_board_v1.cpp`
- `docs/STAGE2N_A13_FINAL_ACCEPTANCE.md`

A14 prototype:

- `rtl/hbm/dlrm_hbm_embedding_lookup_stage2n_a14_v1.sv`
- `rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a14_v1.sv`
- `tb/tb_dlrm_hbm_embedding_lookup_stage2n_a14_v1.sv`
- `tb/tb_dlrm_f37x_rtl_kernel_stage2n_a14_v1.sv`
- `models/stage2n_a14_embedding_table.json`
- `config/stage2n_a14_hbm_v1.cfg`
- `config/stage2n_a14_v1.cfg`
- `scripts/package_stage2n_a14_rtl_kernel_v1.tcl`

A14.5 versioned table-base source:

- `rtl/hbm/dlrm_hbm_embedding_lookup_stage2n_a14_v2.sv`
- `rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a14_v2.sv`
- `tb/tb_dlrm_hbm_embedding_lookup_stage2n_a14_v2.sv`
- `tb/tb_dlrm_f37x_rtl_kernel_stage2n_a14_v2.sv`
- `scripts/run_stage2n_a14_5_table_base_xsim_v1.ps1`
- `scripts/package_stage2n_a14_rtl_kernel_v3.tcl`
- `scripts/build_stage2n_a14_5_target_xo_v1.sh`
- `scripts/package_stage2n_a14_rtl_kernel_v4.tcl`
- `scripts/validate_stage2n_a14_5_xo_v2.py`
- `scripts/build_stage2n_a14_5_target_xo_v2.sh`
- `docs/STAGE2N_A14_5_HBM_TABLE_BASE_ABI.md`
- `docs/STAGE2N_A14_5_XSIM_ACCEPTANCE.md`
- `docs/STAGE2N_A14_5_TARGET_XO_ATTEMPT1_DIAGNOSIS.md`
- `docs/STAGE2N_A14_5_TARGET_XO_ACCEPTANCE.md`
- `docs/evidence/stage2n_a14_5/`

Arithmetic details remain governed by `docs/fixed_point_spec_v0.md`, later
stage-specific contracts, and the exact RTL. Do not infer a new numerical
contract from this architecture summary.
