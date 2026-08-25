# Stage 2N-A14.5 HBM Table-Base Address ABI

Snapshot date: 2026-08-25

## 1. Goal and authorization

This stage closes the address-ABI gap between the simulation-only A14 v1
lookup and a future XRT buffer allocated in physical HBM.  The user explicitly
authorized a new versioned A14 implementation after review of the returned
Vivado 2020.2 XO metadata.

The accepted A13 RTL and all A14 v1 files remain unchanged.  This stage does
not integrate A14 with A13 and does not authorize board execution.

## 2. Triggering evidence

The target server reproduced the A14 V3 package flow at commit `cd68a79` with
the exact part `xcvu37p-fsvh2892-2L-e`.  Returned metadata showed:

- RTL `m_axi_gmem_awaddr/araddr`: 64 bits;
- AXI `ADDR_WIDTH` bus parameter: 64;
- `C_M_AXI_GMEM_ADDR_WIDTH`: 64;
- IP-XACT master address space: `2^64` bytes;
- generated `kernel.xml` data width: 128 bits;
- generated `kernel.xml` address range: only `0xFFFFFFFF`;
- no `addressQualifier="1"` argument associated with `m_axi_gmem`.

Therefore the width parameters themselves were not the remaining design gap.
The A14 v1 ABI exposed only a row index and had no register through which a
Host/XRT flow could provide the base address of the table allocation.

This is target packaging evidence only.  V3 did not run `v++`, generate an
xclbin, access HBM, build or execute a Host, or touch an FPGA device.

## 3. Adopted ABI

The v2 lookup address is:

```text
row_offset = lookup_index * 16
read_address = TABLE_BASE + row_offset
```

`TABLE_BASE` is a 64-bit byte address captured together with `LOOKUP_INDEX` on
an accepted START.  The table retains the frozen 64-row, 8-lane signed-INT16,
128-bit, 16-byte-row layout.

### AXI4-Lite map

| Offset | Register | Width | Access | Meaning |
|---:|---|---:|:---:|---|
| `0x00` | `CONTROL` | 32 | RW | START and status |
| `0x10` | `LOOKUP_INDEX` | 32 | RW | row index |
| `0x18` | `TABLE_BASE_LO` | 32 | RW | table-base bits 31:0 |
| `0x1C` | `TABLE_BASE_HI` | 32 | RW | table-base bits 63:32 |
| `0x20` | `RESULT0` | 32 | RO | lanes 0–1 |
| `0x24` | `RESULT1` | 32 | RO | lanes 2–3 |
| `0x28` | `RESULT2` | 32 | RO | lanes 4–5 |
| `0x2C` | `RESULT3` | 32 | RO | lanes 6–7 |

The packaged IP represents the two physical table-base words as one 64-bit
register named `TABLE_BASE` at offset `0x18`.  Its register parameter
`ASSOCIATED_BUSIF=m_axi_gmem` is intended to produce this kernel argument:

```text
name=TABLE_BASE
offset=0x18
size=0x8
addressQualifier=1
port=m_axi_gmem
```

The exact generated XML remains a target verification requirement, not a
current PASS.

## 4. Error behavior

The v2 lookup issues no AXI read and returns a zero vector with error asserted
when any of these conditions occurs:

- the row index is outside `0..ROWS-1`;
- `TABLE_BASE` is not 16-byte aligned;
- adding the row offset overflows the 64-bit AXI address.

Valid requests retain the A14 v1 protocol:

- one outstanding read;
- one 128-bit beat;
- `ARLEN=0`, `ARSIZE=4`, `ARBURST=INCR`;
- stable AR payload under backpressure;
- stable lookup response under backpressure;
- inactive AXI write channels.

## 5. Versioned implementation

New RTL:

- `rtl/hbm/dlrm_hbm_embedding_lookup_stage2n_a14_v2.sv`;
- `rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a14_v2.sv`.

New self-checking testbenches:

- `tb/tb_dlrm_hbm_embedding_lookup_stage2n_a14_v2.sv`;
- `tb/tb_dlrm_f37x_rtl_kernel_stage2n_a14_v2.sv`.

New validation/build entries:

- `scripts/run_stage2n_a14_5_table_base_xsim_v1.ps1`;
- `scripts/package_stage2n_a14_rtl_kernel_v3.tcl`;
- `scripts/build_stage2n_a14_5_target_xo_v1.sh`;
- `scripts/package_stage2n_a14_rtl_kernel_v4.tcl`;
- `scripts/validate_stage2n_a14_5_xo_v2.py`;
- `scripts/build_stage2n_a14_5_target_xo_v2.sh`.

No A13 file and no A14 v1 source, testbench, package script, result, or
historical document is replaced.

## 6. Simulation gate

The standalone lookup testbench covers:

- all 64 valid rows;
- a non-zero table base above 4 GiB;
- exact `TABLE_BASE + row*16` address generation;
- AR backpressure and response backpressure;
- 64 AR and 64 R handshakes;
- one unaligned-base, one out-of-range-index, and one address-overflow case;
  each returns an error and zero vector with no AXI read.

Required marker:

```text
tb_dlrm_hbm_embedding_lookup_stage2n_a14_v2: PASS cases=67 valid=64 rejected=3 ar=64 r=64
```

The wrapper testbench covers:

- TABLE_BASE low/high programming and readback;
- several non-zero 64-bit bases above 4 GiB;
- 14 valid directed/random lookups;
- exact 128-bit result reconstruction;
- unaligned-base, out-of-range-index, and address-overflow cases with no
  physical AXI transaction;
- inactive write channels and single-outstanding behavior.

Required marker:

```text
tb_dlrm_f37x_rtl_kernel_stage2n_a14_v2: PASS cases=17 valid=14 rejected=3 ar=14 r=14
```

Vivado/XSim is unavailable in the Codex environment. The first
user-controlled Vivado/XSim 2022.1 attempt at commit `29401e5` compiled and
elaborated the standalone lookup, then failed the first result-index check:

```text
actual bit length 32 differs from formal bit length 6
lookup index mismatch expected=0 actual=Z
```

The cause was testbench-only: the TB declared 32-bit index signals so it could
exercise the out-of-range guard, but omitted `.INDEX_WIDTH(INDEX_WIDTH)` on the
DUT instance. The DUT therefore retained its six-bit default. The fix binds
the 32-bit parameter explicitly. The RTL address/data implementation is not
changed by this fix. The corrected simulation at `d428e8b` is **PASS**.

The XSim runner now also creates a `RUNNING` status before simulation and
rewrites it as `FAIL` with the active case and failure reason when a future run
stops early. Attempt 1 predated that improvement, so its absent `status.txt` is
expected; its compile/elaboration/XSim logs remain the evidence.

The corrected retry produced both required markers:

```text
tb_dlrm_hbm_embedding_lookup_stage2n_a14_v2: PASS cases=67 valid=64 rejected=3 ar=64 r=64
tb_dlrm_f37x_rtl_kernel_stage2n_a14_v2: PASS cases=17 valid=14 rejected=3 ar=14 r=14
```

The machine-readable status reports all three guards, table-base readback, and
addresses above 4 GiB as PASS, with zero lookup/wrapper error/fatal records.
See `docs/STAGE2N_A14_5_XSIM_ACCEPTANCE.md` for the acceptance boundary.

## 7. Exact-target XO-only gate

The first user-controlled server entry was:

```bash
bash scripts/build_stage2n_a14_5_target_xo_v1.sh
```

At commit `de9276e`, Vivado 2020.2 used the exact VU37P part and successfully
generated an intact, non-empty XO. The returned generated metadata confirms:

- `TABLE_BASE` at `0x18`, size and host size 8 bytes;
- `TABLE_BASE addressQualifier=1`, `type=void*`, and `port=m_axi_gmem`;
- component register `TABLE_BASE` at `0x18`, size 64 bits, RW, with
  `ASSOCIATED_BUSIF=m_axi_gmem`;
- AXI bus/model/user address-width parameters equal to 64;
- component `AWADDR[63:0]` and `ARADDR[63:0]`;
- IP-XACT address space equal to `2^64` bytes and data width equal to 128.

The old gate stopped because Vivado 2020.2 emitted
`kernel.xml range=0xFFFFFFFF`, not because the packaged address ports were
32-bit. Its status also incorrectly remained `BLOCKED_NOT_RUN` because the
active Bash `ERR` trap intercepted the expected Vivado return-code capture.
See `docs/STAGE2N_A14_5_TARGET_XO_ATTEMPT1_DIAGNOSIS.md`.

The versioned retry entry is:

```bash
bash scripts/build_stage2n_a14_5_target_xo_v2.sh
```

It writes to new `xo_v3` and `results/stage2n_a14_5/target_xo_v2` roots and
refuses to overwrite either. It deliberately stops after XO/metadata
validation. It also disables the `ERR` trap only while capturing Vivado's
expected return code so a real failure is recorded as `FAIL`.

Acceptance requires:

- `TARGET_PART_USED=1`;
- intact, non-empty XO;
- identical standalone and in-XO `kernel.xml` and `component.xml`;
- `m_axi_gmem` data width 128;
- `kernel.xml` port range recorded as either the Vivado 2020.2 value
  `0xFFFFFFFF` or the full value `0xFFFFFFFFFFFFFFFF`;
- `m_axi_gmem` address width 64 proven independently by RTL, AXI bus/model/user
  parameters, `AWADDR[63:0]`/`ARADDR[63:0]`, and a `2^64` IP-XACT address
  space;
- `TABLE_BASE` at `0x18`, size 8 bytes;
- `TABLE_BASE addressQualifier=1`;
- `TABLE_BASE port=m_axi_gmem`;
- component register `TABLE_BASE` at `0x18`, size 64 bits;
- retained source/artifact SHA256 manifests.

The runner contains no `v++` call and performs no FPGA access. The v2 retry is
prepared but has not yet run.

## 8. Current verification status

| Item | Status | Evidence boundary |
|---|---|---|
| A14.5 RTL/TB implementation | PRESENT | Source review only |
| Bash syntax | PASS | `bash -n`; not functional RTL evidence |
| Structural source checks | PASS | Required fields, mappings and guards present |
| Vivado/XSim attempt 1 | FAIL/DIAGNOSED | Standalone TB 32-bit signals connected to default 6-bit DUT index ports; wrapper not run |
| Vivado/XSim fixed retry | PASS | At `d428e8b`: lookup 67/67, wrapper 17/17, exact AR/R counts, guards PASS, zero error/fatal records |
| Exact VU37P XO attempt 1 | STOPPED/DIAGNOSED | Exact-part XO generated and archive intact; TABLE_BASE and 64-bit component evidence confirmed; obsolete range-only assertion stopped the old gate; no v++ or device access |
| Exact VU37P corrected retry | NOT RUN | Versioned range-compatible cross-layer metadata gate requires user server Vivado 2020.2 |
| Vitis link/xclbin | NOT RUN | Deliberately outside this small stage |
| XRT BO/Host | NOT IMPLEMENTED | Later stage |
| Physical HBM | NOT VALIDATED | No board transaction |
| A13 integration | NOT IMPLEMENTED | A13 remains frozen |

## 9. Exit and next-stage rule

The versioned source-preparation and corrected local-XSim milestones are
accepted. Attempt 1 confirms that the target tool can generate the A14.5 XO and
that its inspected TABLE_BASE/component metadata has the intended shape, but
the complete reproducible XO gate remains pending because the old automated
assertion stopped. A14.5 itself is accepted only after the versioned
exact-target XO metadata gate passes with retained logs and hashes. At that
point this document,
`CURRENT_STATE.md`, `ARCHITECTURE.md`, `STAGE_HISTORY.md`, and `DECISIONS.md`
must be updated again with the actual evidence in a separate commit.

Only after A14.5 acceptance may a separately reviewed stage add the v2 link
configuration, XRT BO preparation, Host execution, or physical HBM access.  No
latency, bandwidth, throughput, speedup, complete-DLRM, or board-success claim
is authorized by this stage.
