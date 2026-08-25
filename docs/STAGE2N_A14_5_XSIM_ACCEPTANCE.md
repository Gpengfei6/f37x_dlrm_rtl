# Stage 2N-A14.5 Local XSim Acceptance

Acceptance date: 2026-08-25

## 1. Scope

This record accepts the local functional-simulation gate for the versioned
Stage 2N-A14.5 runtime table-base implementation. It covers the standalone
lookup block and its AXI4-Lite kernel wrapper under Vivado/XSim 2022.1.

It does not accept exact-VU37P XO metadata, Vitis link, xclbin generation, XRT
Host behavior, physical HBM access, FPGA programming, board execution,
performance, or integration with the frozen A13 pipeline.

## 2. Source and environment

| Item | Value |
|---|---|
| Branch | `work/stage2n-a13-cycle-counter` |
| Tested HEAD | `d428e8b34b042bdeb65472c0a6e6d2db65dc9919` |
| Tested commit | `fix(a14): bind lookup index width in XSim TB` |
| OS | Windows |
| Simulator | Vivado Simulator 2022.1, SW Build 3526262 |
| IP Build | 3524634 |
| Runner | `scripts/run_stage2n_a14_5_table_base_xsim_v1.ps1` |
| Result root | `results/stage2n_a14_5_table_base_xsim_v1` |

The runner records `NO_VPP_LINK=1`, `NO_XCLBIN=1`,
`NO_PHYSICAL_HBM_BINDING=1`, and `NO_FPGA_ACCESS=1`.

## 3. Attempt history

Attempt 1 at commit `29401e5` compiled and elaborated the standalone lookup but
failed its first result-index comparison. Vivado reported that the 32-bit TB
signals were connected to the DUT's default six-bit index ports. The upper
response bits were therefore `Z`.

The failed result root was preserved as:

```text
results/stage2n_a14_5_table_base_xsim_v1_attempt1_index_width_binding_fail
```

Commit `d428e8b` fixed only test infrastructure by explicitly binding
`.INDEX_WIDTH(32)` and by making the runner retain a machine-readable failure
status on future early exits. No A14.5 functional RTL changed.

## 4. Accepted lookup-block result

Required and observed marker:

```text
tb_dlrm_hbm_embedding_lookup_stage2n_a14_v2: PASS cases=67 valid=64 rejected=3 ar=64 r=64
```

Accepted checks:

- all 64 valid rows returned the deterministic 128-bit golden vector;
- table base `0x0000000123456000` exercised addresses above 4 GiB;
- every valid address equaled `TABLE_BASE + row*16`;
- exactly 64 AR and 64 R handshakes occurred;
- AR and response payloads were retained under backpressure;
- unaligned base, out-of-range index, and 64-bit addition overflow each
  returned a zero/error response without an AXI transaction;
- simulation completed at 6365 ns;
- the runner reported zero anchored error/fatal records.

## 5. Accepted wrapper result

Required and observed marker:

```text
tb_dlrm_f37x_rtl_kernel_stage2n_a14_v2: PASS cases=17 valid=14 rejected=3 ar=14 r=14
```

Accepted checks:

- 4 directed and 10 deterministic-random valid lookups passed;
- `TABLE_BASE_LO` and `TABLE_BASE_HI` programming/readback passed;
- valid bases above 4 GiB were exercised, including
  `0x123456789ABCD000`;
- the directed row-31 address was exactly `0x123456789ABCD1F0`;
- exactly 14 AR and 14 R handshakes occurred for 14 valid requests;
- unaligned base, index 64, and address overflow were rejected without an AXI
  transaction;
- all AXI write channels remained inactive;
- simulation completed at 6310 ns;
- the runner reported zero anchored error/fatal records.

## 6. Machine-readable status

The returned status included:

```text
STAGE2N_A14_5_TABLE_BASE_XSIM=PASS
HEAD=d428e8b34b042bdeb65472c0a6e6d2db65dc9919
LOOKUP_V2_CASES=67
LOOKUP_V2_VALID_READS=64
LOOKUP_V2_REJECTED_REQUESTS=3
WRAPPER_V2_CASES=17
WRAPPER_V2_VALID_READS=14
WRAPPER_V2_REJECTED_REQUESTS=3
UNALIGNED_BASE_GUARD=PASS
OUT_OF_RANGE_INDEX_GUARD=PASS
ADDRESS_OVERFLOW_GUARD=PASS
TABLE_BASE_READBACK=PASS
HIGH_ADDRESS_ABOVE_4GB=PASS
M_AXI_ADDR_WIDTH=64
M_AXI_DATA_WIDTH=128
LOOKUP_ERROR_FATAL_COUNT=0
WRAPPER_ERROR_FATAL_COUNT=0
```

The result root is ignored by Git and remains a user-local artifact. SHA256
values for these local logs were not returned by runner v1 and are therefore
not recorded or inferred here.

## 7. Acceptance decision

`STAGE2N_A14_5_LOCAL_XSIM=PASS`.

This closes the local functional-simulation gate only. The next gate is
XO-only packaging on the exact `xcvu37p-fsvh2892-2L-e` target with Vivado
2020.2. Acceptance of that gate requires generated kernel metadata to show:

- `m_axi_gmem` data width 128;
- address range `0xFFFFFFFFFFFFFFFF`;
- one 8-byte `TABLE_BASE` argument at `0x18`;
- `TABLE_BASE addressQualifier=1`;
- `TABLE_BASE port=m_axi_gmem`.

The target runner must stop after XO/metadata validation. It must not invoke
`v++`, generate an xclbin, bind physical HBM, or access an FPGA device.
