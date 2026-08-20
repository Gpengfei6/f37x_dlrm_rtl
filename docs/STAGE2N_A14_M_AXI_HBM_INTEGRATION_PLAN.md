# Stage 2N-A14.2 Vitis `m_axi` HBM Integration Architecture Freeze

## 1. Document status and evidence boundary

This document freezes the architecture for a future Vitis kernel wrapper that will connect the Stage 2N-A14.1 standalone embedding lookup prototype to one physical HBM bank through a logical AXI4 memory-mapped master interface. It is an architecture plan only and does not constitute an RTL implementation, Vitis link result, physical HBM access result, or board validation result.

The repository baseline for this work is commit `63ae1c4` (`Stage 2N-A13 cycle-counter board validation`). Stage 2N-A14.2 does not modify the accepted Stage 2N-A13 design.

Current evidence boundary:

- Stage 2N-A14.1 has validated address generation, a single-outstanding AXI4 read transaction, 128-bit embedding-vector packing, ready/valid backpressure behavior, and software-golden comparison in standalone XSim with a fake AXI memory.
- Stage 2N-A14.2 freezes the planned kernel boundary, register map, logical `m_axi` interface, address contract, and HBM binding principle.
- No Vitis kernel wrapper, `m_axi` top-level port, `connectivity.sp`, XO, xclbin, XRT buffer object, physical HBM transaction, or F37X board execution is produced in this stage.

## 2. Relationship between A14.1 and A14.2

Stage 2N-A14.1 provides an isolated embedding lookup IP prototype. Its request side accepts a row index through ready/valid handshaking. Its memory side issues one 128-bit, single-beat AXI4 read at a relative byte address equal to the row index multiplied by 16. Its response side returns one packed vector containing eight signed 16-bit elements.

Stage 2N-A14.2 defines how a future Vitis-compatible kernel wrapper will place that lookup IP between an AXI4-Lite control interface and a logical AXI4 memory interface:

```text
 Host / XRT
     |
     | AXI4-Lite control: index, table base, START, status, result
     v
+------------------------ Vitis kernel wrapper -------------------------+
|  AXI4-Lite register bank                                             |
|          | request                                      ^ result     |
|          v                                              |            |
|                  Embedding Lookup IP                                 |
|          | relative row address                         ^ vector     |
|          +--------------------+--------------------------+            |
|                               | logical AXI4 read master              |
+-------------------------------|---------------------------------------+
                                v
                          m_axi_gmem
                                |
                                | mapped later by connectivity.sp
                                v
                       One physical HBM bank
```

A future wrapper should preserve the verified A14.1 transaction semantics unless a separately reviewed change is required. A14.2 adds the kernel-facing control and address-base contract; it does not change the lookup row format or claim that physical HBM has already been accessed.

## 3. Target architecture

The target architecture contains three logical interfaces:

1. An AXI4-Lite slave control interface used by the Host to configure a lookup, start it, poll completion, and read the returned embedding vector.
2. The Embedding Lookup IP, derived from the A14.1 standalone prototype, which converts a row index into a 16-byte row request and returns one 128-bit vector.
3. A read-only AXI4 master interface named `m_axi_gmem`, exposed by the kernel wrapper and connected by the Vitis shell to one HBM bank.

The initial data path is deliberately serial: one accepted `START` produces at most one in-flight HBM read and one retained result. The wrapper does not accept another operation until the current result has been consumed or explicitly cleared according to the control-register protocol.

## 4. Kernel wrapper responsibilities

The future kernel wrapper shall be responsible for the following functions:

- Implement the AXI4-Lite slave register bank and handle independently arriving AXI write-address and write-data channels in a protocol-compliant manner.
- Validate the control state before accepting `START`; a request is accepted only while the kernel is idle, no uncleared result is pending, and no blocking error is active.
- Atomically snapshot `LOOKUP_INDEX` and the 64-bit table base address when `START` is accepted so that later Host writes cannot change an in-flight request.
- Convert the configured table base and the A14.1 relative row offset into the AXI4 byte address used on `m_axi_gmem`.
- Bridge the register-controlled request to the lookup IP ready/valid interface without losing or duplicating a request.
- Expose the lookup IP AXI4 read request through the logical `m_axi_gmem` interface while preserving single-outstanding, single-beat behavior.
- Latch the returned 128-bit vector into `RESULT_0` through `RESULT_3` and retain it while the Host is delayed.
- Maintain `BUSY`, `DONE`, and `ERROR` status. `DONE` becomes visible only after the complete 128-bit vector has been captured in the result registers.
- Keep platform-specific HBM bank selection outside the RTL. The wrapper exposes only the logical port name `m_axi_gmem`.

The wrapper is not responsible for DLRM control sequencing, Bottom/Interaction/Top execution, A13 register behavior, multi-bank scheduling, bandwidth optimization, or Host-side Embedding-table management in this architecture-freeze stage.

## 5. AXI4-Lite register map

The following register map is frozen as the proposed software-visible contract. All offsets are byte offsets from the kernel AXI4-Lite control base. Registers are 32 bits wide. Reserved bits read as zero and shall be written as zero.

| Offset | Register | Access | Bit definition | Purpose |
| ---: | --- | :---: | --- | --- |
| `0x00` | `CONTROL` | W | bit 0 `START`; bit 1 `CLEAR_DONE`; bit 2 `ERROR_ACK`; bits 31:3 reserved | Write-one command pulses. Commands are not retained as level-sensitive requests. |
| `0x04` | `STATUS` | R | bit 0 `BUSY`; bit 1 `DONE`; bit 2 `ERROR`; bit 3 `LOOKUP_READY`; bits 31:4 reserved | Current wrapper state and result availability. |
| `0x08` | `LOOKUP_INDEX` | R/W | bits 5:0 row index; bits 31:6 reserved | Selects one of the 64 rows in the A14 test configuration. |
| `0x0C` | `TABLE_BASE_LO` | R/W | bits 31:0 | Low 32 bits of the embedding-table device byte address. |
| `0x10` | `TABLE_BASE_HI` | R/W | bits 31:0 | High 32 bits of the embedding-table device byte address. |
| `0x14` | `RESULT_INDEX` | R | bits 5:0 completed row index; bits 31:6 reserved | Identifies the request associated with the retained result. |
| `0x18` | `ERROR_CODE` | R | implementation-defined code; zero means no error | Reports a wrapper-detected configuration or AXI read error. Exact codes require a later implementation review. |
| `0x1C` | `RESERVED` | - | - | Reserved for alignment and future compatible extension. |
| `0x20` | `RESULT_0` | R | bits 15:0 lane 0; bits 31:16 lane 1 | First 32 bits of the packed embedding vector. |
| `0x24` | `RESULT_1` | R | bits 15:0 lane 2; bits 31:16 lane 3 | Second 32 bits of the packed embedding vector. |
| `0x28` | `RESULT_2` | R | bits 15:0 lane 4; bits 31:16 lane 5 | Third 32 bits of the packed embedding vector. |
| `0x2C` | `RESULT_3` | R | bits 15:0 lane 6; bits 31:16 lane 7 | Final 32 bits of the packed embedding vector. |

### 5.1 Control semantics

- `START` is accepted only when `STATUS.BUSY=0`, `STATUS.DONE=0`, and `STATUS.ERROR=0`. An unaccepted `START` shall not create a memory transaction.
- On an accepted `START`, the wrapper snapshots `LOOKUP_INDEX`, `TABLE_BASE_LO`, and `TABLE_BASE_HI`, then asserts `BUSY` until the lookup response is captured or an error terminates the operation.
- After a successful read, all four result registers and `RESULT_INDEX` are updated together, `BUSY` is cleared, and `DONE` is asserted.
- Result registers remain stable while `DONE=1`. `CLEAR_DONE` clears `DONE` and permits the next request; it does not erase the result bits.
- `ERROR_ACK` clears a latched error only when no transaction is outstanding. The exact error-code enumeration belongs to the later RTL design specification.
- A software driver shall not change the table base or lookup index for an operation after issuing `START`; the wrapper snapshot nevertheless prevents such writes from corrupting the current transaction.

## 6. Address and data contract

The A14 test table contains 64 rows. Each row contains eight signed 16-bit elements and therefore occupies 16 bytes. The A14.1 prototype produces a relative row offset:

```text
row_offset = lookup_index << 4
```

The future wrapper shall form the absolute AXI4 byte address as:

```text
m_axi_byte_addr = table_base + (lookup_index << 4)
```

`table_base` is the 64-bit value formed by `{TABLE_BASE_HI, TABLE_BASE_LO}` and must be aligned to 16 bytes. For the initial `ROWS=64` configuration, valid indices are 0 through 63 and the table occupies 1024 consecutive bytes.

The 128-bit read data is retained without lane reordering. Bits `[15:0]` contain lane 0, bits `[31:16]` contain lane 1, and so on through lane 7 in bits `[127:112]`. `RESULT_0` through `RESULT_3` expose consecutive 32-bit slices of that vector as defined in the register map.

## 7. Logical `m_axi_gmem` interface

The future kernel wrapper shall expose a logical AXI4 read-master port named `m_axi_gmem` with the following initial contract:

| Property | Frozen value |
| --- | --- |
| Direction | Read only (`AR` and `R` channels used) |
| Address width | 64 bits |
| Data width | 128 bits |
| ID width | Minimum implementation-supported width; one logical ID is used |
| Outstanding transactions | One |
| Beats per transaction | One |
| `ARLEN` | `0` |
| `ARSIZE` | `4` (16 bytes per beat) |
| `ARBURST` | `INCR`; with one beat, no burst optimization is implied |
| Ordering | In order; no response reordering |
| Write channels | Not used for this lookup-only prototype |

The wrapper must hold the `AR` payload stable while `ARVALID=1` and `ARREADY=0`. It must keep `RREADY` asserted only when it can accept the complete response, and it must retain the result internally if the Host has not yet cleared the previous completion state. AXI response errors shall set `STATUS.ERROR`; their exact encoding is deferred to implementation.

This initial interface intentionally excludes multi-beat reads, several outstanding transactions, request coalescing, caching, prefetching, and burst optimization.

## 8. HBM binding principle

The kernel RTL and its packaging metadata shall refer only to the logical memory port `m_axi_gmem`. No physical HBM bank number, platform memory topology identifier, or F37X-specific placement shall be hard-coded into the lookup IP.

Physical binding will be supplied later at the Vitis link stage through a separate `connectivity.sp` entry. The intended form is illustrated below; it is not generated or executed by this stage:

```ini
sp=<kernel_compute_unit>.m_axi_gmem:HBM[0]
```

The exact kernel instance name and physical bank identifier must be confirmed against the actual `inspur_f37x_xdma_201920_3` platform metadata before a future link. The initial integration uses one logical port and one physical HBM bank. A future Host implementation must allocate the embedding-table buffer in memory compatible with that same binding and program its device address through the table-base registers. No XRT buffer-object or DMA implementation is included in A14.2.

## 9. Planned verification gates for a later implementation

The architecture freeze defines, but does not execute, the following future gates:

1. AXI4-Lite register test: command pulse behavior, snapshot semantics, result retention, clear behavior, and illegal-command handling.
2. Address test: verify `table_base + (index << 4)` for indices 0 and 63, alignment checks, and no request for an invalid index.
3. AXI4 protocol test: single outstanding read, stable `AR` under backpressure, one response per accepted request, and read-error propagation.
4. Wrapper integration XSim: confirm all 64 embedding rows against the same software golden values used by A14.1.
5. Vitis packaging and link: confirm logical port recognition and explicit one-bank mapping from `connectivity.sp`.
6. Physical target validation, only after separate authorization: confirm the actual F37X HBM contents, lookup results, and error handling without making performance claims from simulation alone.

Passing A14.1 standalone XSim does not satisfy gates 4 through 6.

## 10. Explicit non-goals

Stage 2N-A14.2 does not authorize or claim any of the following:

- modification of any Stage 2N-A13 accepted RTL, Host code, scripts, register map, or board evidence;
- integration of the embedding lookup into the DLRM Bottom/Interaction/Top data path;
- implementation of the Vitis kernel wrapper or a top-level `m_axi` interface;
- creation of `connectivity.sp` or binding to a physical HBM bank;
- implementation of XRT buffer objects, DMA transfers, or Host execution;
- multi-bank HBM lookup, bank scheduling, multiple outstanding reads, or burst optimization;
- XO or xclbin generation, FPGA programming, or board execution;
- physical HBM connectivity, latency, bandwidth, throughput, resource, timing, or performance validation;
- any performance-improvement claim.

## 11. Freeze result

The A14.2 architecture is frozen at the interface-contract level only:

```text
STAGE2N_A14_2_ARCHITECTURE_FREEZE = PASS
A14_2_RTL_IMPLEMENTED             = NO
A14_2_M_AXI_KERNEL_INTERFACE      = NOT_IMPLEMENTED
A14_2_CONNECTIVITY_SP             = NOT_CREATED
A14_2_PHYSICAL_HBM_VALIDATION     = NOT_RUN
```

Any later RTL, Host, script, platform-mapping, Vitis-build, or board work requires a separate authorization and its own verification evidence.
