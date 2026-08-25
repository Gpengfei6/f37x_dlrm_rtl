# Stage 2N-A14.6 User-Returned Link Evidence Summary

Evidence date: 2026-08-25

This file is a curated transcription of target evidence returned by the user.
It is not a replacement for, or a fabricated copy of, the server-generated
logs and reports.

## Identity and result

```text
GIT_HEAD=b44855ed4bc8b469257cb3de80cf530e9d5039b9
TARGET_PART=xcvu37p-fsvh2892-2L-e
PLATFORM_VBNV=inspur_f37x_xdma_201920_3
KERNEL=dlrm_f37x_rtl_kernel_stage2n_a14_v2
COMPUTE_UNIT=dlrm_a14_1
REQUESTED_HBM_MAPPING=m_axi_gmem_TO_HBM_0
REQUESTED_CLOCK_MHZ=100
ACCEPTED_XO_SHA256=7c05895b4ef7f3b3e1169d722f88a4ea5103ae9d5cb5283fd0372e7bc3e43dea
XCLBIN_SHA256=9a7ce2518691e1d9a9ef55a0037d5d5345e3781f1e11eb7c2c7d19697144f573
XCLBIN_UUID=6f29087c-9598-4e68-877a-cc4840d078b8
```

```text
A14_6_INPUT_XO=PASS
A14_6_TABLE_BASE_ABI=PASS
A14_6_VPP_LINK=PASS
A14_6_XCLBIN=PASS
A14_6_HBM0_LINK_MAPPING=PASS
A14_6_TARGET_TIMING=PASS
FAIL_REASON=NONE
```

## Timing, DRC, and utilization

```text
WNS_NS=0.000
TNS_NS=0.000
FAILING_ENDPOINTS=0
VPP_ERROR_COUNT=0
VPP_CRITICAL_WARNING_COUNT=0
DRC_ERROR_COUNT=0
DRC_CRITICAL_WARNING_COUNT=0
METHODOLOGY_ERROR_COUNT=0
METHODOLOGY_CRITICAL_WARNING_COUNT=55
LUT=119293
FF=151833
RAMB36=198
RAMB18=8
BRAM_TILE_EQUIVALENT=202.0
URAM=0
DSP=4
LATCH=0
```

Methodology categories returned by the user: `TIMING-1` (1), `TIMING-3`
(36), `TIMING-4` (4), `TIMING-14` (6), `TIMING-27` (4), and `TIMING-54`
(4). The reporting session additionally emitted two `Board 49-67` warnings
for the unavailable custom board-part definition.

## Server-retained evidence

The runner reported these principal records under
`results/stage2n_a14_6/link_v1/`:

- `a14_6_link_v1_status.txt`
- `a14_6_link_v1_sources.sha256`
- `a14_6_link_v1_artifacts.sha256`
- `dlrm_f37x_rtl_kernel_stage2n_a14_v2.xclbin.info`
- `git_status_porcelain.txt`
- `logs/tool_versions.log`
- `logs/vpp_link.log`
- `logs/xo_metadata_validation.log`
- `logs/xclbin_metadata_validation.log`
- `logs/vivado_post_route_report.log`
- `xclbin_connectivity.json`
- `xclbin_mem_topology.json`
- `xclbin_ip_layout.json`
- `post_route/post_route_metrics.txt`
- post-route timing, clock, DRC, methodology, utilization, RAM-utilization,
  high-fanout, and worst-setup-path reports.

The full timing summary was approximately 75 MB and the xclbin approximately
43 MB. They are generated evidence and are not embedded in this source
repository. Build-time Git status contained only generated/untracked paths:
`.ipcache/`, `build/`, the v++ log, `xcd.log`, and `xrc.log`.

## Non-claims

```text
A14_6_PHYSICAL_HBM=NOT_VALIDATED
A14_6_HOST_BUILD=NOT_RUN
A14_6_HOST_EXECUTION=NOT_RUN
A14_6_FPGA_PROGRAMMING=NOT_RUN
A14_6_FPGA_RESET=NOT_RUN
A14_6_FPGA_DEVICE_ACCESS=NONE
A14_6_READY_FOR_BOARD=NO
```
