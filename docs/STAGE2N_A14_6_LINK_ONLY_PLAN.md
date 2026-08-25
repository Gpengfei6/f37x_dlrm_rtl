# Stage 2N-A14.6 Exact-Target Link-Only Plan

## 1. Objective

Stage 2N-A14.6 consumes the exact-target A14.5 runtime-table-base XO accepted
at tested server HEAD `4096614` and performs one F37X Vitis hardware link. The
stage is deliberately limited to xclbin construction, linked metadata, and
routed timing evidence.

```text
accepted A14.5 v2 XO
  dlrm_f37x_rtl_kernel_stage2n_a14_v2
                 |
                 | v++ --target hw --link
                 | one CU: dlrm_a14_1
                 | m_axi_gmem -> HBM[0]
                 | 100 MHz
                 v
       A14.6 F37X xclbin + reports
```

This is not a Host or board stage. It does not allocate an XRT buffer, program
`TABLE_BASE`, open a device, program/reset the FPGA, or issue an HBM read.

## 2. Frozen input identity

The only accepted link input is:

```text
build/stage2n_a14/xo_v3/
  dlrm_f37x_rtl_kernel_stage2n_a14_v2.xo
```

Required identity:

```text
XO_SIZE_BYTES=12951
XO_SHA256=7c05895b4ef7f3b3e1169d722f88a4ea5103ae9d5cb5283fd0372e7bc3e43dea
KERNEL_XML_SHA256=c256715325344a6ee75dd1be5739cc6d5c2f5813452df7689f0272e1a67c9df3
COMPONENT_XML_SHA256=4971079d0b71d6ed848a581770bd204ea339bcc9d4dd63c8de85f483ed8d4b79
```

Before `v++`, the runner must require a readable, non-empty XO with the exact
accepted SHA256 and rerun the tracked A14.5 cross-layer metadata validator on
the generated XML and wrapper RTL. A missing or different artifact is a stop
condition, not permission to rebuild or substitute another XO.

## 3. Frozen target and connectivity

```text
Target part:       xcvu37p-fsvh2892-2L-e
Platform VBNV:     inspur_f37x_xdma_201920_3
Platform path:     /opt/xilinx/platforms/inspur_f37x_xdma_201920_3/
                   inspur_f37x_xdma_201920_3.xpfm
Vitis/Vivado:      2020.2
Kernel:            dlrm_f37x_rtl_kernel_stage2n_a14_v2
Compute unit:      dlrm_a14_1
Kernel clock:      100 MHz
Logical port:      m_axi_gmem
Requested bank:    HBM[0]
```

The versioned configuration must contain exactly:

```ini
[connectivity]
nk=dlrm_f37x_rtl_kernel_stage2n_a14_v2:1:dlrm_a14_1
sp=dlrm_a14_1.m_axi_gmem:HBM[0]
```

`dlrm_f37x_rtl_kernel_stage2n_a14_v2:dlrm_a14_1` is 46 characters,
within the Vitis 2020.2 64-character kernel/CU limit.

## 4. Versioned, non-overwriting outputs

The new flow must use only:

```text
build/stage2n_a14_6/link_v1/
results/stage2n_a14_6/link_v1/
```

It must refuse to start when either root already exists. It must not delete,
move, rename, or overwrite A13, A14 v1, A14.5 XO, earlier build attempts, or
returned evidence.

## 5. Required link evidence

The runner must retain:

- branch and exact source HEAD;
- Vitis, Vivado, and xclbinutil versions;
- platform path and VBNV;
- input XO/kernel/component SHA256 values;
- reviewed configuration SHA256 and exact `nk`/`sp` entries;
- complete `v++ --link` command log and exit code;
- xclbin path, size, SHA256, UUID, kernel, and CU;
- extracted `CONNECTIVITY`, `MEM_TOPOLOGY`, and `IP_LAYOUT` JSON;
- exactly one A14 CU connection to a used `HBM[0]` entry;
- routed checkpoint identity and exact target part;
- setup WNS/TNS/failing endpoints at 100 MHz;
- DRC/methodology error and critical-warning counts;
- source and generated-artifact SHA256 manifests.

## 6. Acceptance criteria

A14.6 may be accepted as link-only PASS only if all of the following hold:

1. the accepted XO and XML hashes match before link;
2. the cross-layer `TABLE_BASE`/64-bit AXI metadata validator passes;
3. `v++ --target hw --link` exits zero;
4. the v++ log has zero line-start `ERROR:` and zero line-start
   `CRITICAL WARNING:` records;
5. the xclbin is non-empty and has a parsed UUID and SHA256;
6. xclbin metadata contains the reviewed kernel, CU, and F37X platform;
7. extracted metadata records exactly one `dlrm_a14_1` connection to used
   `HBM[0]`;
8. the routed checkpoint targets `xcvu37p-fsvh2892-2L-e`;
9. setup WNS is non-negative, TNS is zero, and failing endpoints are zero at
   the frozen 100 MHz request;
10. returned evidence and hashes pass a separate offline review before the
    repository status is promoted.

## 7. Explicit non-claims

Even if every A14.6 link gate passes, the correct status remains:

```text
A14_6_PHYSICAL_HBM=NOT_VALIDATED
A14_6_HOST_BUILD=NOT_RUN
A14_6_HOST_EXECUTION=NOT_RUN
A14_6_FPGA_PROGRAMMING=NOT_RUN
A14_6_FPGA_RESET=NOT_RUN
A14_6_FPGA_DEVICE_ACCESS=NONE
A14_6_READY_FOR_BOARD=NO
```

An xclbin connection record proves the requested platform wiring in the linked
artifact. It does not prove that a physical transaction reached HBM or that the
returned 128-bit row matches the software golden. Those require a separately
authorized Host/board stage.

## 8. Source-preparation status

At this planning checkpoint:

```text
A14_6_AUTHORIZATION=APPROVED
A14_6_LINK_ARCHITECTURE=FROZEN
A14_6_LINK_RUNNER=NOT_YET_ADDED
A14_6_VPP_LINK=NOT_RUN
A14_6_XCLBIN=NOT_GENERATED
A14_6_TARGET_TIMING=NOT_RUN
A14_6_PHYSICAL_HBM=NOT_VALIDATED
A14_6_FPGA_DEVICE_ACCESS=NONE
```
