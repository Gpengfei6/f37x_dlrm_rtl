# Stage 2N-A8 Accepted XO and F37X xclbin

## Accepted result

Stage 2N-A8 packages the Stage 2N-A7 automatic DLRM pipeline as a
user-managed Vitis RTL kernel and links it against the installed Inspur F37X
platform.

Accepted kernel:

- top: `dlrm_f37x_rtl_kernel_stage2n_a7`;
- compute unit: `dlrm_a7_1`;
- platform: `inspur_f37x_xdma_201920_3`;
- requested kernel frequency: 100 MHz;
- xclbin UUID: `5d4ac982-14e3-40fb-afaa-f04ba82dce61`;
- xclbin size: 43,550,638 bytes.

## XO result

The accepted XO is:

```text
build/stage2n_a8/package_v3/
dlrm_f37x_rtl_kernel_stage2n_a7.xo
```

Its metadata has two valid views:

- `component.xml`: 77 IP-XACT registers;
- `kernel.xml`: 74 host arguments.

Vivado 2020.2 omits the three low control registers
`CONTROL_STATUS`, `VERSION`, and `RESULT_COUNT` from the
`kernel.xml` argument list for this user-managed kernel. They remain present
in `component.xml`. The MLP, standalone interaction, and automatic pipeline
windows are all present.

## F37X link result

The accepted xclbin is:

```text
build/stage2n_a8/link_v3/hw/
dlrm_f37x_rtl_kernel_stage2n_a7.xclbin
```

The build completed:

- system linking;
- F37X block-design creation;
- kernel and platform synthesis;
- logic optimization;
- placement;
- routing;
- timing analysis;
- bitstream and xclbin assembly.

The final routed timing report states:

```text
WNS = 0.000 ns
TNS = 0.000 ns
setup failing endpoints = 0
WHS = 0.000 ns
THS = 0.000 ns
hold failing endpoints = 0
All user specified timing constraints are met.
```

The displayed timing margin is zero at report precision, so A8 is accepted as
timing-closed but without visible margin. Hardware smoke testing remains
necessary.

## Empty connectivity section

The xclbin reports an empty `CONNECTIVITY` section. This is expected because
the current kernel is AXI4-Lite control-only and has no external `m_axi`
HBM/DDR data port.

## Canonical source and validation files

- `tcl/package_stage2n_a8_a7_xo_v3.tcl`
- `scripts/accept_stage2n_a8_xo_package_v3_artifact_v1.sh`
- `scripts/link_stage2n_a8_f37x_xclbin_v3.sh`
- `scripts/accept_stage2n_a8_f37x_link_v3_artifact_v1.sh`

The failed v1/v2 packaging experiments and the v3 packaging runner with the
obsolete `kernel.xml` post-check are not canonical acceptance files.

## Boundary

Stage 2N-A8 does not prove physical-board execution. It does not program or
reset any FPGA and does not open a render node.

The following stage requires explicit authorization and must target only:

- device index `2`;
- BDF `0000:9b:00.1`;
- render node `/dev/dri/renderD129`.
