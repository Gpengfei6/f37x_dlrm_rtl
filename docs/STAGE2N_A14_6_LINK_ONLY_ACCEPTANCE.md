# Stage 2N-A14.6 Exact-Target Link-Only Acceptance

Date: 2026-08-25

## 1. Acceptance decision

Stage 2N-A14.6 is accepted as **LINK-ONLY PASS** at tested server HEAD
`b44855ed4bc8b469257cb3de80cf530e9d5039b9`.

The accepted A14.5 runtime-table-base XO linked successfully against the
reviewed F37X platform, produced a non-empty hardware xclbin, retained the
requested single-CU `m_axi_gmem -> HBM[0]` connection, and completed routed
timing at the frozen 100 MHz request.

```text
A14_6_INPUT_XO=PASS
A14_6_TABLE_BASE_ABI=PASS
A14_6_VPP_LINK=PASS
A14_6_XCLBIN=PASS
A14_6_HBM0_LINK_MAPPING=PASS
A14_6_TARGET_TIMING=PASS
FAIL_REASON=NONE
```

This result closes only the authorized link-only milestone. It is not a Host,
board, physical-HBM, performance, or A13-integration acceptance.

## 2. Frozen provenance

| Item | Accepted value |
|---|---|
| Git branch | `work/stage2n-a13-cycle-counter` |
| Tested source HEAD | `b44855ed4bc8b469257cb3de80cf530e9d5039b9` |
| Tool flow | Vitis/Vivado 2020.2 |
| Target part | `xcvu37p-fsvh2892-2L-e` |
| Platform | `inspur_f37x_xdma_201920_3` |
| Kernel | `dlrm_f37x_rtl_kernel_stage2n_a14_v2` |
| Compute unit | `dlrm_a14_1` |
| Requested connectivity | `dlrm_a14_1.m_axi_gmem:HBM[0]` |
| Requested kernel clock | 100 MHz |
| Input XO SHA256 | `7c05895b4ef7f3b3e1169d722f88a4ea5103ae9d5cb5283fd0372e7bc3e43dea` |

The runner revalidated the 8-byte `TABLE_BASE` global pointer at offset
`0x18`, its `m_axi_gmem` association, the 128-bit data path, the 64-bit
RTL/component address path, and the `2^64` IP-XACT address space before link.
Vivado 2020.2's `kernel.xml range=0xFFFFFFFF` remains descriptive and was not
used as the sole address-width proof.

## 3. Linked artifact and connectivity

| Item | Returned evidence |
|---|---|
| xclbin size | approximately 43 MiB |
| xclbin SHA256 | `9a7ce2518691e1d9a9ef55a0037d5d5345e3781f1e11eb7c2c7d19697144f573` |
| xclbin UUID | `6f29087c-9598-4e68-877a-cc4840d078b8` |
| Connectivity records | 1 |
| A14 CU index | 0 |
| HBM[0] memory index | 0 |
| CU-to-HBM[0] validation | PASS |
| HBM[0] used flag | PASS |

The xclbin metadata validator found the reviewed kernel, CU, platform, and one
connection from the A14 CU to used `HBM[0]`. This proves the linked artifact's
logical platform mapping. It does not prove a physical HBM transaction.

## 4. Routed timing and implementation

| Metric | Returned value |
|---|---:|
| Requested period | 10.000 ns |
| Requested frequency | 100 MHz |
| WNS | 0.000 ns |
| TNS | 0.000 ns |
| Failing endpoints | 0 |
| DRC errors | 0 |
| DRC critical warnings | 0 |
| Methodology errors | 0 |
| Methodology critical warnings | 55 |

The non-negative-WNS acceptance gate passed. However, WNS is exactly zero, so
this result has no reported positive setup margin and must not be described as
robust frequency headroom. The reported worst setup path is in the platform's
static PCIe region rather than the A14 kernel hierarchy.

Whole linked-design utilization, including the platform shell, was:

| Resource | Count |
|---|---:|
| LUT | 119,293 |
| FF | 151,833 |
| RAMB36 | 198 |
| RAMB18 | 8 |
| BRAM tile equivalent | 202.0 |
| URAM | 0 |
| DSP | 4 |
| Latch | 0 |

These counts are not kernel-only utilization and must not be used to infer the
incremental cost of the A14 lookup.

## 5. Warning disposition

The `v++` link log had zero line-start `ERROR:` and zero line-start
`CRITICAL WARNING:` records. The post-route methodology report retained 55
critical warnings:

| Check | Count | Summary |
|---|---:|---|
| `TIMING-1` | 1 | invalid clock waveform on clock-modifying block |
| `TIMING-3` | 36 | invalid primary clock on clock-modifying block |
| `TIMING-4` | 4 | primary-clock redefinition on a clock tree |
| `TIMING-14` | 6 | LUT on a clock tree |
| `TIMING-27` | 4 | invalid primary clock on a hierarchical pin |
| `TIMING-54` | 4 | scoped false-path or clock-group constraint |

They are retained as platform/static-clock methodology debt. They do not
invalidate this narrow link-only result because the frozen gates report zero
DRC errors, zero methodology errors, zero failing endpoints, and non-negative
setup slack. They remain unresolved for any board or broader physical signoff.

When the routed DCP was reopened to collect reports, Vivado also emitted two
`Board 49-67` critical warnings because the custom
`inspur.com:f37x:part0:1.3` board-part repository was not configured in that
reporting session. These are retained as report-session environment warnings;
they are not counted as `v++` link critical warnings or routed DRC failures.

## 6. Attempt history

1. Attempt 1 ran interactively over SSH. The client connection reset during
   placement. Server-side implementation initially continued, but the process
   was later absent and no final xclbin/status was produced. Its partial build
   and result roots were archived as
   `link_v1_attempt1_interrupted_during_placement`.
2. Attempt 2 used `nohup` with piped input. The runner deliberately stopped
   before `v++` because non-interactive confirmation requires
   `A14_6_CONFIRM=yes`. No link output roots were created.
3. Attempt 3 used `nohup env A14_6_CONFIRM=yes ...` and completed the accepted
   link, xclbin metadata validation, and post-route reporting flow.

The failed confirmation attempt is an invocation error, not an RTL, XO, link,
or implementation failure.

## 7. Explicit non-claims

The authoritative remaining boundary is:

```text
A14_6_PHYSICAL_HBM=NOT_VALIDATED
A14_6_HOST_BUILD=NOT_RUN
A14_6_HOST_EXECUTION=NOT_RUN
A14_6_FPGA_PROGRAMMING=NOT_RUN
A14_6_FPGA_RESET=NOT_RUN
A14_6_FPGA_DEVICE_ACCESS=NONE
A14_6_READY_FOR_BOARD=NO
```

No physical HBM read, XRT buffer allocation, `TABLE_BASE` programming, Host
result, FPGA programming/reset, embedding-row correctness, latency, bandwidth,
throughput, power, speedup, or A13 Feature Interaction integration is accepted.

## 8. Evidence boundary

The decision above is based on user-returned target console output and the
machine-readable evidence retained by the server runner. A curated summary is
tracked under `docs/evidence/stage2n_a14_6/`. Large generated artifacts,
including the xclbin, routed DCP, and full timing report, remain outside Git and
are identified by paths and hashes where available.
