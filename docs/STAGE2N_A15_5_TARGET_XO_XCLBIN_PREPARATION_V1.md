# Stage 2N-A15.5 Target XO/XCLBIN Preparation V1

Date: 2026-08-28
Branch: `work/stage2n-a15-hbm-pipeline-integration`
Authorization baseline: `0c705a360a036785e4c949185fcb5cc1dcc4f07f`
Accepted A15.4 implementation commit: `69f25fc`
Accepted public top: `dlrm_f37x_rtl_kernel_stage2n_a15_v1`

## 1. Purpose and status boundary

Stage 2N-A15.5 prepares a fail-closed, user-executed target XO and Vitis
link-only flow for the accepted A15.4 public kernel. This local stage creates
and tests package/link source files and offline validators. Codex does not run
the target flow, access the server, or access an FPGA.

| Gate | Status in this document |
|---|---|
| A15.4 local public-kernel XSim | PASS (inherited accepted evidence) |
| A15.5 local preparation/static gates | PASS |
| A15.5 target XO build | NOT RUN |
| A15.5 target XO metadata validation | NOT RUN |
| A15.5 Vitis hardware link | NOT RUN |
| A15.5 xclbin validation | NOT RUN |
| Target 100 MHz routed timing | NOT RUN |
| FPGA programming | NOT RUN |
| Host execution | NOT RUN |
| Board execution | NOT RUN |
| Performance | NOT CLAIMED |
| Physical HBM transaction | NOT VALIDATED |

The local `PASS` above applies only to the reviewed source and validator
self-tests described in Section 7. It is not an XO, xclbin, target timing, HBM,
or board result.

## 2. Accepted input and protected assets

The package top is the tracked A15.4 wrapper:

- `rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a15_v1.sv`;
- accepted SHA256 at preparation time:
  `c3da5be63d4cf195df124e572887b6aa96a464522883c6cdc95c4bd56ff4e8a1`.

A15.5 does not modify the accepted A13 RTL/ABI, A14 v2 lookup RTL, A14.7
Host/evidence, or A15.1 through A15.4 RTL, testbenches, runners, and retained
evidence. The package source closure contains the same 17 RTL sources compiled
by the accepted A15.4 local XSim flow, excluding its testbench.

Frozen RTL source closure (`17` files, in package order):

1. `rtl/common/rv_fifo.sv`
2. `rtl/common/runtime_relu_quant.sv`
3. `rtl/compute/mac_lane.sv`
4. `rtl/memory/banked_activation_buffer.sv`
5. `rtl/memory/local_weight_provider.sv`
6. `rtl/compute/vector_dot_product_core.sv`
7. `rtl/compute/dense_layer_engine.sv`
8. `rtl/control/mlp_sequence_controller.sv`
9. `rtl/top/dlrm_f37x_rtl_kernel.sv`
10. `rtl/interaction/dlrm_feature_interaction_engine.sv`
11. `rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a2.sv`
12. `rtl/control/mlp_sequence_controller_segmented.sv`
13. `rtl/pipeline/dlrm_internal_pipeline_controller.sv`
14. `rtl/pipeline/dlrm_internal_pipeline_controller_stage2n_a13_v1.sv`
15. `rtl/hbm/dlrm_hbm_embedding_lookup_stage2n_a14_v2.sv`
16. `rtl/pipeline/dlrm_hbm_pipeline_integration_stage2n_a15_v2.sv`
17. `rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a15_v1.sv`

## 3. Audited A15.4 public interface

The public kernel exposes:

- one `ap_clk` and active-low `ap_rst_n`;
- one 32-bit `s_axi_control` slave with a 12-bit address;
- exactly one `m_axi_gmem` master;
- `m_axi_gmem` address width 64 bits, data width 128 bits, and ID width 1;
- an AXI read path used by the accepted sequential A14 v2 lookup engine;
- permanently inactive AXI write address/data/response channels.

The complete accepted A13 raw AXI-Lite map remains unchanged. In particular,
the cycle counters remain at:

| Register | Offset |
|---|---:|
| Bottom cycles | `0x218` |
| Interaction cycles | `0x21C` |
| Top cycles | `0x220` |
| Total cycles | `0x224` |

A15.4 adds only:

| Register | Offset | Meaning |
|---|---:|---|
| A15 CONTROL/STATUS | `0x300` | START=`0x1`, CLEAR=`0x2`, status on read |
| TABLE_BASE low | `0x304` | staged address bits `[31:0]` |
| TABLE_BASE high | `0x308` | staged address bits `[63:32]` |

One accepted A15 START snapshots the configured state, issues four sequential
lookups for fixed rows 37, 38, 39, and 40 through one AXI read master, injects
the four vectors, and then starts the accepted A13 Bottom–Interaction–Top
pipeline. There is no second Host START between the embedding and dense stages.

## 4. Kernel metadata decision

The kernel uses `user_managed` AXI-Lite control. The full A13/A15 register map
is therefore accessed through raw AXI-Lite register reads and writes; it is not
misrepresented as dozens of independent Vitis scalar kernel arguments.

Exactly one kernel argument is declared:

| Argument | Offset | Size | Qualifier | Port |
|---|---:|---:|---:|---|
| `TABLE_BASE` | `0x304` | 8 bytes | global pointer (`1`) | `m_axi_gmem` |

The 64-bit argument spans the accepted low/high registers at `0x304/0x308`.
This association gives the linker the logical memory port required for
`HBM[0]` connectivity without changing the RTL ABI.

The obsolete A14 single-lookup signature is forbidden. A15.5 must not expose
`LOOKUP_INDEX` or `RESULT0` through `RESULT3` as kernel arguments. A15 CONTROL
at `0x300` is a raw user-managed register, not a global-memory argument.

## 5. Frozen target identity and connectivity

| Item | Frozen value |
|---|---|
| Target part | `xcvu37p-fsvh2892-2L-e` |
| Platform VBNV | `inspur_f37x_xdma_201920_3` |
| Reviewed platform path | `/opt/xilinx/platforms/inspur_f37x_xdma_201920_3/inspur_f37x_xdma_201920_3.xpfm` |
| Kernel | `dlrm_f37x_rtl_kernel_stage2n_a15_v1` |
| Compute unit | `dlrm_a15_1` |
| Requested clock | 100 MHz (10 ns) |
| Logical memory port | `m_axi_gmem` |
| Connectivity | `dlrm_a15_1.m_axi_gmem:HBM[0]` |
| Kernel/CU count | one / one |
| AXI memory-master count | one |

No second HBM mapping, bank, table, AXI master, parallel lookup engine, burst,
or multiple-outstanding transaction is part of A15.5.

## 6. Prepared files and non-overwriting outputs

| File | Role |
|---|---|
| `scripts/package_stage2n_a15_5_rtl_kernel_v1.tcl` | Exact-source Vivado RTL-kernel package definition |
| `config/stage2n_a15_5_target_v1.cfg` | One-CU and one-`HBM[0]` Vitis connectivity |
| `scripts/build_stage2n_a15_5_target_xo_v1.sh` | User-executed exact-target XO-only runner |
| `scripts/link_stage2n_a15_5_target_v1.sh` | User-executed validated-XO link-only runner |
| `scripts/report_stage2n_a15_5_vitis_post_route_v1.tcl` | Read-only routed checkpoint reports |
| `scripts/validate_stage2n_a15_5_xo_v1.py` | Cross-layer XO/kernel/component/RTL/package validator |
| `scripts/validate_stage2n_a15_5_xclbin_v1.py` | Link-contract and xclbin metadata validator |
| `scripts/run_stage2n_a15_5_local_preparation_v1.ps1` | Local static and validator self-test runner |

The target runners refuse to overwrite these versioned roots:

- XO: `build/stage2n_a15_5/xo_v1/`;
- XO evidence: `results/stage2n_a15_5/target_xo_v1/`;
- link: `build/stage2n_a15_5/link_v1/`;
- link evidence: `results/stage2n_a15_5/target_link_v1/`.

The link runner accepts only an XO whose status records both build and metadata
validation `PASS`, and whose recalculated SHA256 matches that status. It does
not rebuild or silently replace the XO.

## 7. Local static acceptance

The local preparation runner checked:

- branch and authorization-baseline ancestry;
- the exact accepted A15.4 wrapper SHA256;
- exact package top, target part, 17-source closure, 64-bit address, 128-bit
  data, and `TABLE_BASE` metadata;
- exact one-CU/one-`HBM[0]` configuration;
- absence of device/server/network commands in active shell code;
- Python syntax for both validators;
- a valid synthetic XO metadata fixture and rejection of wrong kernel, second
  master, stale A14 arguments, wrong widths, wrong TABLE_BASE offset, and wrong
  target part;
- a valid synthetic xclbin metadata fixture and rejection of wrong kernel,
  wrong CU, wrong bank, second mapping/master, stale A14 arguments, wrong
  clock, wrong platform, and wrong target part.

Local retained status:

```text
A15_5_LOCAL_PREPARATION=PASS
A15_5_PYTHON_SYNTAX=PASS
A15_5_XO_VALIDATOR_SELF_TEST=PASS
A15_5_XCLBIN_VALIDATOR_SELF_TEST=PASS
A15_5_BASH_SYNTAX=NOT_RUN
A15_5_TARGET_XO_BUILD=NOT_RUN
A15_5_TARGET_XO_VALIDATION=NOT_RUN
A15_5_TARGET_LINK=NOT_RUN
A15_5_XCLBIN=NOT_RUN
A15_5_TARGET_TIMING=NOT_RUN
A15_5_FPGA_PROGRAMMING=NOT_RUN
A15_5_HOST_EXECUTION=NOT_RUN
A15_5_BOARD=NOT_RUN
A15_5_PERFORMANCE=NOT_CLAIMED
A15_5_PHYSICAL_HBM=NOT_VALIDATED
A15_5_FPGA_DEVICE_ACCESS=NONE
NETWORK_ACCESS=NONE
SERVER_ACCESS=NONE
```

`bash -n` is `NOT_RUN` because this local Windows environment has no Bash
executable. Structured static checks did run for both shell files. This does
not promote shell syntax or target execution to `PASS`.

Retained local evidence:

| Evidence | SHA256 |
|---|---|
| `results/stage2n_a15_5/local_preparation_v1/a15_5_local_preparation_v1_status.txt` | `376527ca9f39df4a4f48f207bfd4c914fb8faeb78225a128a05d70de4f317c05` |
| `results/stage2n_a15_5/local_preparation_v1/command_transcript.log` | `93ce199a05188e84ee4dd6dbd7e3c61ec6a621d77fcfbd14cb0bbdb95cbd21cf` |
| `results/stage2n_a15_5/local_preparation_v1/xo_validator_self_test.log` | `3d66d3be8cfaceccfc82d13696bbd350c38fbd786c4ff32e2d1f9f434bf24d6d` |
| `results/stage2n_a15_5/local_preparation_v1/xclbin_validator_self_test.log` | `c914f7f78710b1d8b32a07332ed88d9078ece5ada64d6926fe99dddeab66dcbf` |

The status file was produced by the local runner at parent HEAD `0c705a3`.
The target timing, programming, Host, board, and performance classifications
shown above are closure-level non-claims derived from the absence of any target
execution; they are not target artifacts.

## 8. Minimal Host programming order for the accepted ABI

A later Host must retain the accepted raw-register sequence. The minimum order
is:

1. confirm reset/idle and clear stale status as required;
2. program the five layer descriptors through the accepted descriptor staging
   registers and descriptor-commit command;
3. program the accepted weight and bias memories;
4. program the dense input activation vector;
5. program Bottom, Top, and pipeline configuration registers;
6. write TABLE_BASE low/high at `0x304/0x308` while the A15 wrapper is idle;
7. write A15 START (`0x1`) at `0x300` exactly once;
8. poll A15/A13 status, then read the accepted result and cycle-counter
   registers;
9. retire/pop the result and clear status using the accepted commands.

The A15.3/A15.4 path owns all four embedding slots. A Host must not write the
legacy embedding-slot staging window in this path. Rows 37–40 are selected
internally, and the table content/base allocation remains a Host
responsibility. This document does not provide or claim an XRT Host build.

## 9. User-executed target sequence

Only the user may transfer and run the reviewed files in the controlled target
environment. After committing the reviewed preparation files, the intended
commands are:

```bash
export A15_5_XO_CONFIRM=yes
bash scripts/build_stage2n_a15_5_target_xo_v1.sh

export A15_5_LINK_CONFIRM=yes
bash scripts/link_stage2n_a15_5_target_v1.sh
```

The second command is permitted only after the first runner has recorded a
validated XO and its SHA256. Target evidence must be returned for a separate
acceptance review before any project-state document claims target `PASS`.

## 10. Required returned evidence

The acceptance review needs at least:

- Git branch/HEAD and dirty-status capture;
- exact Vivado/Vitis/xclbinutil versions;
- XO, kernel XML, component XML, xclbin, and source SHA256 records;
- XO package log and validator log;
- link log, xclbin info, CONNECTIVITY, MEM_TOPOLOGY, and IP_LAYOUT dumps;
- exact kernel, CU, platform, part, frequency, and `HBM[0]` mapping;
- routed timing summary, WNS, TNS, failing endpoints, resource counts, latch,
  DRC, methodology, and worst-path identity;
- explicit confirmation that no FPGA device was opened, programmed, or reset.

## 11. Evidence boundary and next gate

A15.5 local preparation proves that the accepted A15.4 source has a coherent,
fail-closed package/link description and that the validators reject specified
metadata regressions. It does not prove that Vivado packages the XO, Vitis
links the xclbin, the target meets timing, XRT can allocate HBM, physical HBM
returns the expected vectors, or the FPGA executes the full pipeline.

There is no bandwidth, latency, throughput, power, energy, speedup, or GPU
comparison claim. Physical HBM/board execution remains a separately authorized
future gate after target artifacts and evidence have been reviewed.

## 12. 2026-08-28 validator-only compatibility note

The user later reported that the fixed-source target XO and Vitis link produced
an xclbin, but the v1 offline xclbin validator stopped on a Vitis 2020.2
`IP_LAYOUT` compatibility assumption. The actual reported layout has 36 IP
entries: one `IP_KERNEL`, three DDR4 shell entries, and 32 HBM shell entries.
The v1 validator incorrectly required the complete IP-entry list to have length
one instead of filtering for the unique `IP_KERNEL` entry.

The versioned correction is documented in
`docs/STAGE2N_A15_5_XCLBIN_VALIDATOR_V2_COMPATIBILITY.md`. It does not change
this preparation record, any frozen RTL, the v1 validator/runner, or an existing
target artifact. Target XO/link/xclbin/timing facts remain user-reported and
pending read-only v2 revalidation plus returned raw-evidence review. No rebuild
or relink is required for the compatibility fix.
