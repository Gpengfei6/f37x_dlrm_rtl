# Stage 2N-A15.5 Target XCLBIN Final Acceptance V1

Date: 2026-08-28

## 1. Final acceptance decision

Stage 2N-A15.5 is accepted as **TARGET XO/XCLBIN/TIMING PASS** for the exact
F37X target-build boundary documented below.

```text
STAGE2N_A15_5=PASS
A15_5_TARGET_XO_BUILD=PASS
A15_5_TARGET_XO_VALIDATION=PASS
A15_5_TARGET_LINK=PASS
A15_5_XCLBIN=PASS
A15_5_XCLBIN_VALIDATION=PASS
A15_5_TARGET_TIMING=PASS
A15_5_TARGET_REBUILD_REQUIRED=NO
FAIL_REASON=NONE
```

This acceptance proves exact-target packaging, Vitis link/xclbin generation,
the static TABLE_BASE-to-HBM[0] mapping, and 100 MHz routed timing. It does not
accept FPGA programming, Host execution, a physical HBM transaction, board
function, or performance.

## 2. A15.4 to A15.5 architecture relationship

Stage 2N-A15.4 locally proved the complete public-kernel composition:

```text
AXI4-Lite configuration and A15 START
                |
                v
one A14 v2 lookup engine + one m_axi_gmem read master
                |
      rows 37, 38, 39, 40 sequentially
                |
      A13 embedding slots 0, 1, 2, 3
                |
      Bottom -> Interaction -> Top
```

A15.5 does not change this datapath. It freezes the accepted A15.4 RTL source
closure, packages that public top as an RTL kernel, and links exactly one
compute unit to `HBM[0]`.

The accepted compute counters remain Bottom 322, Interaction 100, Top 744, and
Total 1174 cycles. Those counters start after the four sequential lookups and
therefore are not an all-HBM end-to-end latency measurement.

```text
TRUE_ALL_HBM_E2E_PERFORMANCE=NOT_YET_MEASURED
```

A future measurement boundary must include lookup 0 + lookup 1 + lookup 2 +
lookup 3 + Bottom + Interaction + Top.

## 3. Frozen provenance and target identity

| Item | Accepted value |
|---|---|
| Branch | `work/stage2n-a15-hbm-pipeline-integration` |
| Source-build HEAD | `30cbf64e44fa99aa025f1a7456d739c8b5d4be6b` |
| Validator/revalidation HEAD | `2ce2d443cd55d00b492e154aa57091f39d14934e` |
| Kernel | `dlrm_f37x_rtl_kernel_stage2n_a15_v1` |
| Compute unit | `dlrm_a15_1` |
| Platform | `inspur_f37x_xdma_201920_3` |
| Part | `xcvu37p-fsvh2892-2L-e` |
| Requested period | 10.000 ns |
| Requested frequency | 100 MHz |
| Vivado | 2020.2, SW build 3064766 |
| xclbinutil | 2020.2, XRT build 2.8.0 |
| Accepted A15.4 wrapper SHA256 | `c3da5be63d4cf195df124e572887b6aa96a464522883c6cdc95c4bd56ff4e8a1` |

The retained source manifest matches the local validator v2, target
configuration, v1 link runner, post-route report Tcl, and v2 revalidation
runner byte for byte.

## 4. Kernel interface and ABI

The linked kernel retains:

- one `s_axi_control` interface;
- one 64-bit-address, 128-bit-data `m_axi_gmem` interface;
- one global-memory argument, `TABLE_BASE`/arg0, at AXI-Lite offset `0x304`;
- the complete accepted A13 raw AXI-Lite programming ABI;
- the accepted cycle counters at `0x218`, `0x21C`, `0x220`, and `0x224`;
- A15 control/status and TABLE_BASE registers at `0x300/0x304/0x308`.

The obsolete A14 `LOOKUP_INDEX` and `RESULT0` through `RESULT3` kernel
arguments are absent. The final validator reports:

```text
TABLE_BASE_ONLY_ARGUMENT=PASS
STALE_A14_ARGUMENTS=ABSENT
```

## 5. Accepted xclbin identity and HBM mapping

| Item | Accepted value |
|---|---|
| XO SHA256 | `a88fd4bba7a534f7068cff838448c5ba7f330e5bec27c8c2697525c9dedee019` |
| xclbin SHA256 | `23ee48c91b3dfb5b68b3372ac49fc6607f203cf01d3b9fcfe04b4ea42be02356` |
| xclbin UUID | `1b555645-a9e2-4f5e-95af-6ce4adacbc3c` |
| Kernel IP-layout index | 0 |
| Connectivity records | 1 |
| Connectivity argument | arg0 / TABLE_BASE |
| Connected memory index | 0 |
| Connected memory tag | `HBM[0]` |
| Connected memory used | 1 |

The accepted static mapping is:

```text
TABLE_BASE / arg0
  -> dlrm_f37x_rtl_kernel_stage2n_a15_v1:dlrm_a15_1
  -> m_axi_gmem
  -> MEM_TOPOLOGY[0]
  -> HBM[0], used=1
```

This proves linked metadata connectivity only. It does not prove that the FPGA
issued a physical HBM transaction or returned an embedding vector.

## 6. Target-link history

### Attempt 1

- synthesis, placement, routing, and post-route timing reached completion;
- WNS/TNS/WHS/THS were recorded as `0/0/0/0`;
- the SSH/session was interrupted before the full orchestration chain closed;
- an operator command accidentally truncated the attempt-1 aggregate
  `vpp_link.log`;
- that log is partial and non-pristine and is not the final acceptance chain;
- the isolated attempt-1 history remains retained and was not deleted.

Attempt 1 is not classified as an RTL, connectivity, mapping, or timing
failure. Its evidence integrity was insufficient for final acceptance.

### Controlled retry

- the retry used `nohup` and Vitis/Vivado 2020.2;
- the exact F37X platform and 100 MHz request were retained;
- Vitis completed synthesis, implementation, placement, routing, bitstream,
  and xclbin generation;
- elapsed link time was approximately `1h 13m 47s`;
- the resulting xclbin SHA256 was frozen as
  `23ee48c91b3dfb5b68b3372ac49fc6607f203cf01d3b9fcfe04b4ea42be02356`;
- the v1 metadata validator then produced a false negative.

## 7. Validator v1 false negative and v2 correction

The v1 validator incorrectly used the total number of
`IP_LAYOUT.m_ip_data` entries as the compute-unit count. The Vitis 2020.2 F37X
xclbin contains:

| IP-layout type | Count |
|---|---:|
| `IP_KERNEL` | 1 |
| `IP_MEM_DDR4` shell entries | 3 |
| `IP_MEM_HBM` shell entries | 32 |
| Total | 36 |

The v1 message `IP_LAYOUT must contain exactly one compute unit` was therefore
a validator bug, not an RTL bug, connectivity bug, HBM-mapping bug, or target
implementation failure.

Validator v2 filters `m_type == IP_KERNEL`, requires exactly one exact
kernel/CU entry, then dereferences the one connectivity record into
`MEM_TOPOLOGY`. Its acceptance requires the referenced entry to be used
`HBM[0]`.

Validation results:

- local Vitis-2020.2-shaped positive fixture: PASS;
- local mutation/rejection fixtures: 12/12 PASS;
- fixed-SHA target xclbin revalidation: PASS;
- target rebuild required: NO.

## 8. Routed timing and implementation

| Metric | Accepted result |
|---|---:|
| Requested clock | 100 MHz / 10.000 ns |
| WNS | 0.000 ns |
| TNS | 0.000 ns |
| Failing endpoints | 0 |
| LUT | 135,114 |
| FF | 161,768 |
| RAMB36 | 215 |
| RAMB18 | 89 |
| URAM | 0 |
| DSP | 43 |
| Latch | 0 |
| DRC errors | 0 |
| DRC critical warnings | 0 |
| Methodology errors | 0 |
| Methodology critical warnings | 55 |

WNS `0.000 ns` satisfies the frozen 100 MHz gate but provides no reported
positive setup margin. The reported worst path begins and ends in the platform
static PCIe hierarchy. It must not be used to infer an independent timing margin
for the A15 kernel.

The resource counts cover the whole linked design, including the F37X platform
shell. They are not kernel-only incremental utilization.

## 9. Methodology-warning disposition

The 55 methodology critical warnings are retained exactly; they are not
reported as zero:

| Check | Count |
|---|---:|
| `TIMING-1` | 1 |
| `TIMING-3` | 36 |
| `TIMING-4` | 4 |
| `TIMING-14` | 6 |
| `TIMING-27` | 4 |
| `TIMING-54` | 4 |

They were not treated as an A15.5 target-build acceptance blocker because the
frozen result has zero methodology errors, zero DRC errors/critical warnings,
zero failing setup endpoints, and non-negative setup slack. They remain
methodology debt for broader physical signoff and board-stage review.

## 10. Verification chain

The final acceptance chain is:

1. accepted A15.4 public-port XSim and bit-exact full-pipeline result;
2. A15.5 local source/metadata preparation and positive/negative validators;
3. exact-target XO build and metadata validation;
4. controlled Vitis 2020.2 retry producing the fixed-SHA xclbin;
5. validator-v1 false-negative diagnosis;
6. validator-v2 local positive and 12 negative tests;
7. non-rebuilding revalidation of the fixed-SHA XO/xclbin;
8. read-only xclbin metadata and routed-DCP report extraction;
9. final status with `FAIL_REASON=NONE`.

No XO or xclbin was rebuilt for the v2 acceptance review.

## 11. Imported evidence

Curated raw evidence is tracked under:

`docs/evidence/stage2n_a15_5/target_xclbin_revalidation_v2/`

It contains the final status, source/artifact manifests, xclbin info, link
contract, tool versions, validator-v2 log, CONNECTIVITY/MEM_TOPOLOGY/IP_LAYOUT
JSON, routed metrics, check-timing, utilization, DRC, methodology, and an
imported-evidence SHA256 manifest.

The raw `.rpt` and `.xclbin.info` files retain the tool-generated bytes,
including formatting spaces. Narrow `.gitattributes` entries disable text
normalization/diff only for those evidence paths so source/document whitespace
checks remain strict without rewriting the evidence.

The approximately 43 MB xclbin, routed DCP, full build tree, 75 MB timing
summary, caches, and temporary archives are intentionally not committed.

## 12. Explicit remaining boundary

```text
A15_5_FPGA_PROGRAMMING=NOT_RUN
A15_5_HOST_EXECUTION=NOT_RUN
A15_5_PHYSICAL_HBM=NOT_VALIDATED
A15_5_BOARD=NOT_RUN
A15_5_PERFORMANCE=NOT_CLAIMED
FPGA_DEVICE_ACCESS=NONE
TRUE_ALL_HBM_E2E_PERFORMANCE=NOT_YET_MEASURED
```

A15.5 PASS must not be rewritten as board PASS, physical-HBM PASS, Host PASS,
or performance PASS.

## 13. Frozen baseline and next stage

The accepted artifact baseline for future work is:

```text
XCLBIN_SHA256=23ee48c91b3dfb5b68b3372ac49fc6607f203cf01d3b9fcfe04b4ea42be02356
XCLBIN_UUID=1b555645-a9e2-4f5e-95af-6ce4adacbc3c
TARGET_REBUILD_REQUIRED=NO
```

Stage 2N-A15.6 may be planned separately to perform protected FPGA
programming, Host/XRT execution, one physical `HBM[0]` allocation, four
sequential embedding lookups, slots 0 through 3 injection, and complete DLRM
functional board validation using exactly this artifact. A15.6 requires an
independent explicit yes/no device-authorization gate. No A15.6 implementation
or device action is part of this acceptance commit.

```text
A15_5_FINAL_ACCEPTANCE=PASS
TARGET_REBUILD_REQUIRED=NO
FROZEN_RTL_MODIFIED=NO
XCLBIN_REBUILT=NO
READY_FOR_A15_6_PREPARATION=YES
```
