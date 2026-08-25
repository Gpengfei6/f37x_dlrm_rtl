# Stage 2N-A14.5 Exact-Target XO Acceptance

Acceptance date: 2026-08-25

## 1. Decision

`STAGE2N_A14_5_EXACT_TARGET_XO=PASS`.

The user-controlled Vivado 2020.2 retry generated and validated the versioned
A14.5 runtime-table-base XO for the exact target part
`xcvu37p-fsvh2892-2L-e`. The returned status, package log, generated XML,
cross-layer validator output, and SHA256 manifests are mutually consistent.

This decision closes only the exact-target **XO packaging and metadata** gate.
It is not a Vitis link, xclbin, physical HBM, XRT Host, FPGA programming,
board-function, timing, bandwidth, latency, throughput, or complete-DLRM PASS.

## 2. Tested revision and environment

| Item | Accepted value |
|---|---|
| Branch | `work/stage2n-a13-cycle-counter` |
| Tested server HEAD | `4096614419170404d5dcb334432f5f322c4f92d5` |
| Tested commit | `fix(a14): validate target XO address ABI` |
| Target part | `xcvu37p-fsvh2892-2L-e` |
| Tool | Vivado 2020.2, SW Build 3064766 |
| IP Build | 3064653 |
| Kernel | `dlrm_f37x_rtl_kernel_stage2n_a14_v2` |
| Runner | `scripts/build_stage2n_a14_5_target_xo_v2.sh` |
| Package Tcl | `scripts/package_stage2n_a14_rtl_kernel_v4.tcl` |
| Metadata validator | `scripts/validate_stage2n_a14_5_xo_v2.py` |
| Build root | `build/stage2n_a14/xo_v3` |
| Result root | `results/stage2n_a14_5/target_xo_v2` |

The retry used new, non-overwriting roots. The earlier attempt-1 result and
diagnosis remain preserved.

## 3. Machine-readable result

The returned status records:

```text
A14_5_TARGET_XO_BUILD=PASS
A14_5_TABLE_BASE_ABI=PASS
A14_5_AXI_ADDR_WIDTH_EVIDENCE=PASS
KERNEL_XML_PORT_RANGE=0xFFFFFFFF
A14_5_VPP_LINK=NOT_RUN
A14_5_XCLBIN=NOT_GENERATED
A14_5_PHYSICAL_HBM=NOT_VALIDATED
A14_5_HOST_BUILD=NOT_RUN
A14_5_HOST_EXECUTION=NOT_RUN
A14_5_FPGA_PROGRAMMING=NOT_RUN
A14_5_FPGA_RESET=NOT_RUN
A14_5_FPGA_DEVICE_ACCESS=NONE
A14_5_READY_FOR_BOARD=NO
FAIL_REASON=NONE
```

`READY_FOR_BOARD=NO` is expected. This runner intentionally ends before Vitis,
XRT, HBM binding, or device access.

## 4. Accepted XO and ABI evidence

The generated XO is non-empty and has size 12,951 bytes. The standalone XML
and the copies extracted from the XO have identical hashes.

Accepted kernel metadata:

- six kernel arguments;
- `m_axi_gmem` is a 128-bit addressable master port;
- `TABLE_BASE` is argument ID 1;
- `TABLE_BASE offset=0x18`;
- `TABLE_BASE size=0x8` and `hostSize=0x8`;
- `TABLE_BASE type=void*`;
- `TABLE_BASE addressQualifier=1`;
- `TABLE_BASE port=m_axi_gmem`.

Accepted component/IP-XACT metadata:

- seven AXI4-Lite registers;
- `TABLE_BASE` is a 64-bit read-write register at `0x18`;
- `TABLE_BASE ASSOCIATED_BUSIF=m_axi_gmem`;
- `m_axi_gmem DATA_WIDTH=128`;
- `m_axi_gmem ADDR_WIDTH=64`;
- model/user address-width parameters are 64;
- `m_axi_gmem_awaddr[63:0]` and `m_axi_gmem_araddr[63:0]`;
- IP-XACT address space is `16777216T`, equal to
  `18446744073709551616` bytes (`2^64`);
- `ap_clk ASSOCIATED_BUSIF=s_axi_control:m_axi_gmem`;
- `ap_clk ASSOCIATED_RESET=ap_rst_n`;
- `ap_rst_n POLARITY=ACTIVE_LOW`.

The validator therefore reports:

```text
AXI_ADDRESS_WIDTH_EVIDENCE=RTL_COMPONENT_IPXACT_POINTER_CONSISTENT
```

## 5. Interpretation of `kernel.xml range`

Vivado 2020.2 emitted:

```text
KERNEL_XML_PORT_RANGE=0xFFFFFFFF
```

This value is retained exactly and is not rewritten. In this accepted flow it
is a descriptive kernel-port field, not the sole proof of physical RTL address
width. The 64-bit width decision requires the consistent RTL port declarations,
component bus/model/user parameters, AWADDR/ARADDR vectors, `2^64` IP-XACT
address space, and 8-byte global pointer listed above.

This interpretation does not prove physical HBM accessibility. Only a later
Vitis link and board transaction can establish that.

## 6. SHA256 evidence

### Source identity

| Source | SHA256 |
|---|---|
| `rtl/hbm/dlrm_hbm_embedding_lookup_stage2n_a14_v2.sv` | `47eca811affac4c7c6e0c40007da92b40ab79df095ff0ef912bea6f05f35fed6` |
| `rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a14_v2.sv` | `587098181d525dbba954b4d281faea7fa5e8eb653a7185d82b88411cd7f96033` |
| `scripts/package_stage2n_a14_rtl_kernel_v4.tcl` | `75930b4d8fdae00bb9e63f2b54419a6f68994dd1ebfabb479604329665f04086` |
| `scripts/validate_stage2n_a14_5_xo_v2.py` | `23c9dd8f0d7e7fa58666423b11098554cf93e058299a893a610a73ecfa1cb8f0` |
| `scripts/build_stage2n_a14_5_target_xo_v2.sh` | `42fdb3408bcfc79d38ce3dd181156823e485cf02534861d6228310eb9f009392` |

All five returned source hashes match the imported tracked files byte for byte.
The returned porcelain status contained only `?? build/`; no tracked source
modification was reported in the tested server worktree after generation.

### Generated artifacts

| Artifact | SHA256 |
|---|---|
| `dlrm_f37x_rtl_kernel_stage2n_a14_v2.xo` | `7c05895b4ef7f3b3e1169d722f88a4ea5103ae9d5cb5283fd0372e7bc3e43dea` |
| standalone `kernel.xml` | `c256715325344a6ee75dd1be5739cc6d5c2f5813452df7689f0272e1a67c9df3` |
| `kernel.xml` extracted from XO | `c256715325344a6ee75dd1be5739cc6d5c2f5813452df7689f0272e1a67c9df3` |
| standalone `component.xml` | `4971079d0b71d6ed848a581770bd204ea339bcc9d4dd63c8de85f483ed8d4b79` |
| `component.xml` extracted from XO | `4971079d0b71d6ed848a581770bd204ea339bcc9d4dd63c8de85f483ed8d4b79` |

The transferred full-history Bundle was also verified on the server and
Windows with SHA256
`5cd62928333fde3dd33f4060d5b1bef25b355016876704be80cc0b19c1a4d273`.

### Returned evidence-file hashes

| Evidence file | SHA256 |
|---|---|
| target status | `c73a6325980fc53e8a5ee0450e1b0be128d0c511921d64563c78bc567645d517` |
| metadata validation log | `43a6867d5413b6c28180c1c17cd4dc66d5bd5d0ddb679d0e05caa777b8efd032` |
| Vivado package log | `29b4301057c8b4487750a0656ce2def8823a97d5756cff651bb3ca2b73106ad3` |
| source manifest | `448e9546a3aaa1b4e1d742f3b9e6187d95e5bce9291cce2d69414a0f1a1c6cf6` |
| artifact manifest | `70d3f52f6e1ec6bc4e5ae8ef1a8d3ebf9aa1fbc38ed09f0c4550fa57bc6e54d8` |
| tool-version log | `119c9dc4f6b742a3a490fa2887bd2e3b70fe847ddd3d7f20498fbbae8475ccdb` |

## 7. Warning review

The returned Vivado package log contains seven `WARNING` records, zero
`CRITICAL WARNING` records, and zero `ERROR` records.

| Warning | Count | Review |
|---|---:|---|
| `IP_Flow 19-5101` SystemVerilog top packaging support | 1 | Non-blocking for this generated XO; `ipx::check_integrity` passed |
| `IP_Flow 19-3158` missing `FREQ_HZ` before association | 2 | Emitted during initial inference; final component associates both AXI buses with `ap_clk` |
| `IP_Flow 19-3157` reset-name/polarity heuristic | 2 | `ap_rst_n` metadata consistently records `ACTIVE_LOW` and is associated with `ap_clk` |
| `IP_Flow 19-5661` no bus associated with clock | 1 | Emitted before explicit associations; final component has `s_axi_control:m_axi_gmem` |
| `Vivado 12-4404` no C model for CPU emulation | 1 | CPU emulation is outside this RTL XO-only gate |

These warnings do not invalidate the accepted packaging/metadata result. They
must not be reinterpreted as evidence for a later Vitis link, timing closure,
physical memory connection, or board execution.

## 8. Independent review performed after evidence return

The returned XML was reviewed outside the server run using the tracked
`validate_stage2n_a14_5_xo_v2.py` and the matching wrapper RTL. The validator
reproduced the same PASS marker and all metadata counts/widths. `bash -n` passed
for the runner, Python AST parsing passed for the validator, and the five local
source hashes matched the returned source manifest.

These checks review retained evidence; they are not a second Vivado build.

## 9. Preserved boundaries and next gate

The following remain explicitly unvalidated:

- Vitis `v++ --link`;
- A14 xclbin generation;
- `m_axi_gmem -> HBM[0]` link metadata;
- routed target timing;
- XRT BO allocation and 64-bit table-base programming from a real allocation;
- Host compilation or execution;
- FPGA programming/reset;
- physical HBM reads and returned embedding values;
- latency, bandwidth, throughput, speedup, power, or energy efficiency;
- integration with the frozen A13 Bottom-Interaction-Top pipeline;
- complete FPGA-resident DLRM inference.

The next engineering step requires a separately reviewed authorization and
must retain these distinctions. The A13 accepted baseline and every A14 v1
asset remain unchanged.
