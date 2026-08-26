# Stage 2N-A14.7 Protected Host/XRT + Physical HBM Single-Table Smoke Preparation V1

Date: 2026-08-26
Branch: `work/stage2n-a13-cycle-counter`
Local pre-A14.7 HEAD observed by the user: `3e9899519145`
Accepted A14.6 tested source HEAD: `b44855ed4bc8b469257cb3de80cf530e9d5039b9`

## 1. Stage objective and authorization boundary

Stage 2N-A14.7 prepares the first protected Host/XRT path that can exercise the
accepted A14.6 xclbin against **physical HBM[0]**.  The intended later board
smoke is deliberately narrow:

1. create one 1024-byte XRT BO in HBM[0];
2. DMA the canonical 64-row × 8-lane INT16 table into that BO;
3. obtain the BO's 64-bit device physical address;
4. program A14 `TABLE_BASE_LO/HI` and one `LOOKUP_INDEX`;
5. issue one START;
6. consume the read-to-clear DONE status correctly;
7. compare the returned 128-bit row with the canonical expected row;
8. release the BO; and
9. require HBM[0] to return to `0 Byte / 0 BO` before acceptance.

This source-preparation milestone **does not authorize or claim** server access,
FPGA programming, Host execution, physical HBM access, performance, power,
speedup, multi-table lookup, batch lookup, A13 integration, or full DLRM
inference.

```text
A14_7_LOCAL_SOURCE_PREPARATION=PASS
A14_7_CANONICAL_PAYLOAD_OFFLINE=PASS
A14_7_CPP11_STUB_COMPILE=PASS
A14_7_EVIDENCE_VALIDATOR_SELF_TEST=PASS
A14_7_TAMPER_REJECTION_SELF_TEST=PASS
A14_7_TARGET_XRT_BUILD=NOT_RUN
A14_7_HOST_EXECUTION=NOT_RUN
A14_7_PHYSICAL_HBM=NOT_RUN
A14_7_FPGA_PROGRAMMING=NOT_RUN
A14_7_FPGA_RESET=NOT_RUN
A14_7_FPGA_DEVICE_ACCESS=NONE
A14_7_READY_FOR_TARGET_HOST_BUILD=YES
A14_7_READY_FOR_BOARD=NO
```

## 2. Frozen input baseline

A14.7 consumes the accepted A14.6 link artifact without modifying A14 RTL or
rebuilding the xclbin.

| Item | Frozen value |
|---|---|
| Target FPGA | `xcvu37p-fsvh2892-2L-e` |
| Board | Inspur F37X |
| Platform | `inspur_f37x_xdma_201920_3` |
| Tool flow | Vitis/Vivado 2020.2, XRT 2020.2 |
| Expected XRT runtime version | `2.9.210507` |
| Kernel | `dlrm_f37x_rtl_kernel_stage2n_a14_v2` |
| Compute unit | `dlrm_a14_1` |
| Full IP name | `dlrm_f37x_rtl_kernel_stage2n_a14_v2:dlrm_a14_1` |
| Expected CU/IP index | `0` |
| Requested connectivity | `dlrm_a14_1.m_axi_gmem:HBM[0]` |
| HBM[0] memory-topology index | `0` |
| Accepted xclbin SHA256 | `9a7ce2518691e1d9a9ef55a0037d5d5345e3781f1e11eb7c2c7d19697144f573` |
| Accepted xclbin UUID | `6f29087c-9598-4e68-877a-cc4840d078b8` |
| Accepted xclbin tested source HEAD | `b44855ed4bc8b469257cb3de80cf530e9d5039b9` |
| Frozen clock | 100 MHz |

A14.6 established logical `m_axi_gmem -> HBM[0]` connectivity and routed timing
only.  It explicitly left XRT allocation, TABLE_BASE programming, Host
execution, physical HBM access, and returned-row correctness unvalidated.

## 3. Frozen A14 control ABI

The accepted A14 v2 wrapper exposes:

| Offset | Register | A14.7 use |
|---:|---|---|
| `0x00` | CONTROL | START write; pending/DONE/idle/ready/error read |
| `0x10` | LOOKUP_INDEX | one row ID in `[0,63]` |
| `0x18` | TABLE_BASE_LO | BO physical address bits `[31:0]` |
| `0x1C` | TABLE_BASE_HI | BO physical address bits `[63:32]` |
| `0x20` | RESULT0 | lanes 0/1 |
| `0x24` | RESULT1 | lanes 2/3 |
| `0x28` | RESULT2 | lanes 4/5 |
| `0x2C` | RESULT3 | lanes 6/7 |

The important protocol constraint is that reading CONTROL clears the latched
DONE bit.  The Host therefore treats the **first CONTROL word that contains
DONE as authoritative** and never polls for DONE again after that read.  A
stale DONE from an earlier run is consumed once before the new smoke and then a
clean idle+ready word is required.

## 4. Canonical HBM table and byte-exact transport payload

The source of truth remains
`models/stage2n_a14_embedding_table.json`:

```text
schema               = stage2n_a14_embedding_table_v1
HBM bank             = HBM[0]
rows                 = 64
embedding dimension  = 8
value type            = signed INT16
row width             = 128 bits / 16 bytes
byte order            = little endian
value[row][lane]      = row * 8 + lane - 256
```

The new offline builder validates every JSON field, row ID, byte offset, lane
count, and lane value before emitting the transport binary.  The resulting
payload is frozen as:

```text
PAYLOAD_BYTES=1024
PAYLOAD_SHA256=023ad250824def6b538ac40a7f0a9bd457e571136100ab1c1e574769f9061b03
PAYLOAD_FNV1A64=40a53c3698b88325
```

The default protected smoke uses row 37, whose expected signed INT16 lanes are:

```text
40, 41, 42, 43, 44, 45, 46, 47
```

The expected result words are therefore:

```text
RESULT0=0x00290028
RESULT1=0x002b002a
RESULT2=0x002d002c
RESULT3=0x002f002e
```

The runner permits another row only through `A14_7_LOOKUP_INDEX=0..63`; the
Host and offline validator independently derive the expected row from the
frozen formula.

## 5. Host/XRT design

### 5.1 Why legacy HAL is retained

A14.7 follows the already accepted A13 Host access pattern instead of adding a
new high-level runtime dependency.  It uses the XRT 2020.2 legacy/experimental
HAL APIs:

- `xclOpen`
- `xclIPName2Index`
- `xclOpenContext` / `xclCloseContext`
- `xclRegRead` / `xclRegWrite`
- `xclAllocBO` / `xclFreeBO`
- `xclMapBO` / `xclUnmapBO`
- `xclSyncBO`
- `xclGetBOProperties`

The target build-only gate checks that these symbols are exported by the
installed XRT and then compiles/links the Host in `-std=gnu++11` mode.

### 5.2 Physical HBM BO lifecycle

The Host is frozen to target device index 2 and HBM memory index 0.  It calls:

```text
xclAllocBO(handle, 1024, 0, 0)
```

The final `0` is the linked memory-topology index for HBM[0], not an assumption
that the device address is zero.  The Host immediately retrieves
`xclBOProperties`, verifies the returned memory-index bits, requires at least
1024 bytes, and checks 16-byte device-address alignment and 64-bit range safety.

The canonical bytes are copied into the mapped BO and synchronized with
`XCL_BO_SYNC_BO_TO_DEVICE`.  `xclBOProperties.paddr` is then split into:

```text
TABLE_BASE_LO = paddr[31:0]
TABLE_BASE_HI = paddr[63:32]
```

The Host reads the three programmed registers back before START.  On every
normal and exception path the BO is unmapped/freed; the protected runner adds
an external post-process `xbutil query` gate that HBM[0] returns to zero BO
usage.

## 6. Protected board runner boundary

The board runner is intentionally stricter than the Host.  It locks:

```text
xbutil index = 2
BDF          = 0000:9b:00.1
render node  = /dev/dri/renderD129
platform     = inspur_f37x_xdma_201920_3
xclbin SHA   = 9a7ce251...7144f573
xclbin UUID  = 6f29087c-9598-4e68-877a-cc4840d078b8
CU           = dlrm_f37x_rtl_kernel_stage2n_a14_v2:dlrm_a14_1
HBM index    = 0
```

Before any write it requires:

- index/BDF/platform mapping match;
- render-node-to-BDF mapping match;
- firewall `GOOD`;
- expected/source CU IDLE;
- no open render-node handle;
- HBM[0] = `0 Byte / 0 BO`;
- two read-only samples with unchanged UUID, CU state, and DMA counters.

If the accepted A14.6 UUID is already loaded, programming is skipped.  If a
different image is loaded, A14.7 **does not guess** whether it is safe to
replace.  The user must first review that source and provide both:

```text
A14_7_ALLOWED_SOURCE_UUID=<reviewed current UUID>
A14_7_ALLOWED_SOURCE_CU=<reviewed current full CU name>
```

Only an exact match can reach the programming gate.  A protected run always
requires a simple `yes/no` authorization (or `A14_7_CONFIRM=yes` for an
already-reviewed non-interactive invocation) **before the first write action**.
If programming is needed, that one authorization covers programming the exact
accepted A14.6 xclbin and then one lookup; if A14.6 is already loaded, the
authorization occurs immediately before the one physical-HBM Host lookup.  No
reset and no automatic rollback are ever performed.

After Host exit, the runner requires the accepted UUID/CU to remain present and
idle, the firewall to remain GOOD, the render handle to be closed, HBM[0] to
return to zero, and the DMA counters to differ from the final pre-Host sample.
The expected DMA change is caused by the Host-to-device BO synchronization and
is not incorrectly treated as post-run interference.

## 7. Evidence contract

A successful protected board run creates an **exactly 64-line** `KEY=VALUE`
evidence file.  The offline validator rejects duplicate/missing/extra keys and
checks:

- accepted A14.6 xclbin identity;
- target device/BDF/render/platform identity;
- XRT version and CU/HBM indices;
- canonical payload size/SHA256/FNV1a64;
- TABLE_BASE reconstruction from the returned 64-bit BO paddr;
- 16-byte alignment and 64-bit range safety;
- pre-start idle/ready state;
- authoritative DONE word contains DONE and no response error;
- the next CONTROL read proves DONE was cleared and the CU returned idle/ready;
- lookup index range;
- canonical expected lane formula;
- RESULT0..3 packing;
- ACTUAL_LANE0..7 equals EXPECTED_LANE0..7;
- BO release, post-release HBM0 zero, and DMA-activity PASS markers.

The validator includes a local self-test with a valid synthetic 64-line fixture
and a tampered RESULT0 fixture.  The valid fixture must pass and the tampered
fixture must be rejected.

## 8. New files

```text
host/stage2n_a14_7_hbm_single_table_board_smoke_v1.cpp
python/build_stage2n_a14_7_hbm_table_asset_v1.py
python/verify_stage2n_a14_7_evidence_v1.py
scripts/build_stage2n_a14_7_host_v1.sh
scripts/program_and_run_stage2n_a14_7_hbm_smoke_v1.sh
docs/STAGE2N_A14_7_HBM_SINGLE_TABLE_HOST_PREPARATION_V1.md
docs/evidence/stage2n_a14_7/local_source_preparation_v1.txt
```

A D-033 decision entry must also be appended to `docs/DECISIONS.md` when these
files are imported into the repository.

## 9. Local validation completed in this preparation round

No server or FPGA was accessed.  The following local/offline checks passed:

1. canonical table bytes independently reconstructed from the frozen formula;
2. payload size = 1024 bytes;
3. payload SHA256 =
   `023ad250824def6b538ac40a7f0a9bd457e571136100ab1c1e574769f9061b03`;
4. payload FNV1a64 = `40a53c3698b88325`;
5. Python asset builder syntax check PASS;
6. asset builder synthetic canonical-JSON fixture PASS;
7. Host C++11 syntax compile PASS against a local declaration-only XRT 2020.2
   API stub; no link and no device access;
8. both Bash runners `bash -n` PASS;
9. evidence validator Python syntax check PASS;
10. valid 64-line synthetic evidence PASS;
11. tampered RESULT0 evidence rejection PASS;
12. board-runner evidence here-document statically confirmed at exactly 64
    lines;
13. a machine-readable local-source evidence summary is retained at
    `docs/evidence/stage2n_a14_7/local_source_preparation_v1.txt`.

The declaration-only stub compile is a **local source/API-shape check**, not a
claim that the target server's XRT installation links successfully.  The real
symbol/compile/link gate remains `A14_7_TARGET_XRT_BUILD=NOT_RUN`.

## 10. Known limitations and non-claims

A14.7 phase 1 does not establish:

- that the target server currently contains the accepted A14.6 xclbin;
- that the target XRT installation exports all required symbols;
- that physical HBM[0] allocation succeeds;
- that `paddr` is usable by this platform until the protected smoke returns it;
- any multi-row, multi-table, batched, random, or concurrent lookup behavior;
- latency, throughput, bandwidth, power, energy efficiency, or speedup;
- integration of HBM lookup into the accepted A13 DLRM pipeline;
- full DLRM inference or accuracy impact.

The first physical board run must therefore remain a single deterministic row
lookup, with no performance claims.

## 11. Key engineering decisions / pitfalls recovered from the interrupted Work run

1. **TABLE_BASE and HBM bank selection are different concerns.**  The linked
   `sp=...:HBM[0]` chooses the bank; the runtime BO `paddr` chooses the actual
   table address inside that bank.
2. **Never assume TABLE_BASE=0.**  Obtain the real 64-bit address through
   `xclGetBOProperties` and program both halves.
3. **CONTROL.done is destructive on read.**  Preserve the first word that sees
   DONE and stop polling immediately.
4. **A stale prior DONE can suppress READY.**  Consume stale DONE once, then
   require a second clean idle+ready CONTROL word before the new START.
5. **Post-run DMA change is expected.**  The payload `xclSyncBO(TO_DEVICE)` is a
   Host-to-card transfer; safety guards require DMA counters to be stable before
   Host execution but require an observed change across the Host run.
6. **BO lifetime is externally verified.**  Host cleanup is necessary but not
   sufficient; the runner requires HBM[0] to report `0 Byte / 0 BO` after the
   process exits.
7. **Do not infer a safe source image.**  A non-A14.6 current UUID is blocked
   until its UUID and CU are explicitly allowlisted after review.
8. **No reset/rollback automation.**  A failure after programming leaves the
   reviewed A14.6 image loaded and records failure evidence; the script does not
   attempt recovery actions on its own.

## 12. Frozen next step and acceptance gate

The immediate next stage is **target build-only validation**, still with no
board access:

```text
bash scripts/build_stage2n_a14_7_host_v1.sh
```

Acceptance requires:

```text
A14_7_HOST_XRT_BUILD=PASS
A14_7_XRT2020_2_API_PROBE=PASS
A14_7_CANONICAL_PAYLOAD=PASS
HOST_EXECUTION=NOT_RUN
FPGA_DEVICE_ACCESS=NONE
```

Only after those target build-only results are returned and reviewed may the
protected physical-HBM smoke be authorized.  A successful board smoke must end
with a validator-accepted 64-line evidence file and, at minimum:

```text
A14_7_HOST_EXECUTION=PASS
A14_7_PHYSICAL_HBM=PASS
A14_7_SINGLE_TABLE_LOOKUP=PASS
A14_7_RESULT_MATCH=PASS
A14_7_BO_RELEASED=PASS
A14_7_HBM0_POST_RELEASE_ZERO=PASS
A14_7_DMA_ACTIVITY_OBSERVED=PASS
A14_7_FPGA_RESET=NOT_RUN
A14_7_OTHER_DEVICE_ACCESS=NONE
FAIL_REASON=NONE
```

Until that physical run is returned and reviewed, the authoritative boundary
remains `A14_7_READY_FOR_BOARD=NO`.
