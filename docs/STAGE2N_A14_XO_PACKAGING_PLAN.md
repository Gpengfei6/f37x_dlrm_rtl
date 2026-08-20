# Stage 2N-A14.4-A RTL Kernel XO Packaging Preparation

## 1. Relationship between A14.3-A2 and A14.4-A

Stage 2N-A14.3-A2 proves the standalone wrapper path in Vivado/XSim:

```text
AXI4-Lite control
  -> A14 kernel wrapper
  -> A14.1 embedding lookup IP
  -> logical m_axi_gmem transaction
  -> RESULT0 through RESULT3
```

That simulation completed 14/14 lookup cases with 14 AR handshakes and 14 R handshakes. Stage 2N-A14.4-A does not change or revalidate the RTL behavior. It packages the same wrapper and A14.1 lookup source into a user-managed Vitis RTL-kernel XO and freezes the future logical HBM binding file.

No accepted A13 RTL, A14.1 lookup RTL, A14 wrapper RTL, Host source, or A13 configuration is modified by this stage.

## 2. XO objective

The packaging top is:

```text
dlrm_f37x_rtl_kernel_stage2n_a14_v1
```

The XO must contain:

- `rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a14_v1.sv`;
- `rtl/hbm/dlrm_hbm_embedding_lookup_stage2n_a14_v1.sv`;
- one user-managed AXI4-Lite slave interface named `s_axi_control`;
- one 128-bit AXI4 master interface named `m_axi_gmem`;
- the six AXI4-Lite register descriptions used by the wrapper;
- generated `component.xml` and `kernel.xml` metadata.

The generated XO is an RTL packaging artifact. It is not an xclbin and does not prove synthesis, implementation, timing closure, Vitis link compatibility with the F37X platform, physical HBM connectivity, or board execution.

## 3. `package_xo` flow

The packaging script is:

```text
scripts/package_stage2n_a14_rtl_kernel_v1.tcl
```

It performs the following operations:

1. Resolves and checks the two required A14 RTL source files.
2. Selects `xcvu37p-fsvh2892-2L-e` as the default target packaging part.
3. Creates an isolated Vivado project under `build/stage2n_a14/xo_v1/`.
4. Sets `dlrm_f37x_rtl_kernel_stage2n_a14_v1` as the top module.
5. Packages the project as `user.org:user:dlrm_f37x_rtl_kernel_stage2n_a14_v1:2.14`.
6. Requires `s_axi_control` to be inferred as an AXI slave and `m_axi_gmem` as an AXI master.
7. Associates both interfaces with `ap_clk` and associates the active-low reset `ap_rst_n`.
8. Adds the six wrapper registers to the AXI4-Lite memory map.
9. Runs IP integrity checking and `package_xo` with `user_managed` control.
10. Checks that the XO and generated `kernel.xml` are non-empty and that both AXI interfaces appear in `kernel.xml`.

The intended target command is:

```powershell
& 'D:\vivado2022\vivado2022forwins\Vivado\2022.1\bin\vivado.bat' `
  -mode batch -nolog -nojournal `
  -source 'scripts\package_stage2n_a14_rtl_kernel_v1.tcl'
```

The optional single Tcl argument overrides only the temporary Vivado packaging project part. It exists so the part-independent IP/XO structure can be checked in a local Vivado installation that lacks the VU37P device database:

```powershell
& 'D:\vivado2022\vivado2022forwins\Vivado\2022.1\bin\vivado.bat' `
  -mode batch -nolog -nojournal `
  -source 'scripts\package_stage2n_a14_rtl_kernel_v1.tcl' `
  -tclargs xc7a200tfbg484-2
```

The script refuses to overwrite an existing A14 XO build directory. It contains no `v++` invocation and does not read the future HBM binding configuration.

## 4. AXI4-Lite control metadata

The packaged control interface is `s_axi_control`, 32 bits wide, with the following register metadata:

| Offset | Register | Access |
| ---: | --- | :---: |
| `0x00` | `CONTROL` / `START` and status | Read/write |
| `0x10` | `LOOKUP_INDEX` | Read/write |
| `0x20` | `RESULT0` | Read-only |
| `0x24` | `RESULT1` | Read-only |
| `0x28` | `RESULT2` | Read-only |
| `0x2C` | `RESULT3` | Read-only |

The generated local `kernel.xml` exposes `LOOKUP_INDEX` and `RESULT0` through `RESULT3` as kernel arguments. `CONTROL` remains the user-managed control/status register at offset `0x00`.

## 5. `m_axi_gmem` interface

The logical memory port retained in the XO is:

```text
m_axi_gmem
```

The packaged metadata identifies it as an AXI master with 128-bit data width. The RTL behavior remains the A14.1 behavior already tested in A14.3-A2:

- read transactions only;
- one outstanding transaction;
- one 128-bit beat per request;
- `ARLEN=0`;
- no burst optimization;
- byte address `lookup_index << 4`;
- inactive AXI write channels.

Packaging the port does not connect it to an actual HBM controller.

## 6. Future HBM binding principle

The future link configuration is stored separately in:

```text
config/stage2n_a14_v1.cfg
```

It records one intended logical-to-physical mapping:

```ini
[connectivity]
sp=dlrm_f37x_rtl_kernel_stage2n_a14_v1_1.m_axi_gmem:HBM[0]
```

The RTL and XO retain only the logical port name. The physical `HBM[0]` mapping is applied later by `v++ --link`; that operation is explicitly not run in A14.4-A. The mapping must be rechecked against the actual `inspur_f37x_xdma_201920_3` platform metadata before any future link.

## 7. Local packaging result

Vivado 2022.1 SW Build 3526262 was used locally.

The default target-part attempt stopped before project creation because the local Vivado installation does not contain the device database for:

```text
xcvu37p-fsvh2892-2L-e
```

Therefore, target-part XO packaging remains blocked locally. The same script was then run with the installed `xc7a200tfbg484-2` part solely to validate the part-independent IP/XO packaging structure. That local proxy run completed successfully:

```text
STAGE2N_A14_4_A_XO_PACKAGE=PASS
TARGET_PART=xcvu37p-fsvh2892-2L-e
PACKAGING_PART=xc7a200tfbg484-2
TARGET_PART_USED=0
CONTROL_INTERFACE=s_axi_control
MEMORY_INTERFACE=m_axi_gmem
REGISTER_COUNT=6
NO_VPP_LINK=1
NO_XCLBIN=1
NO_PHYSICAL_HBM_BINDING=1
NO_FPGA_ACCESS=1
```

Generated local artifact:

```text
build/stage2n_a14/xo_v1/dlrm_f37x_rtl_kernel_stage2n_a14_v1.xo
```

Artifact checks:

| Item | Result |
| --- | --- |
| `package_xo` exit code | 0 |
| IP integrity check | PASS |
| XO archive size | 12,300 bytes |
| XO archive entries | 8 |
| `kernel.xml` kernel name | Correct |
| `s_axi_control` in `kernel.xml` | Present, slave, 32-bit |
| `m_axi_gmem` in `kernel.xml` | Present, master, 128-bit |
| A14 wrapper RTL in XO | Present |
| A14.1 lookup RTL in XO | Present |
| xclbin generated | No |

SHA256 values:

```text
XO:
d93b2e038653fed4913d9c845c7cbc530bc9830408445b61b1aaa7c1a3ba4a60

kernel.xml:
d32c76fff3f40d6dc9e47bfe1f7adbec1f4c23d27b3c26b67e4b5ed7de1075bd

component.xml:
d65569e9d846a9cc62e79b4ec00193c378a4626f3f15add142be96bd509f8f08
```

Vivado emitted ordinary packaging warnings about a SystemVerilog top file, missing C-model files for CPU emulation, and reset-interface naming. `package_xo` and IP integrity checking nevertheless completed. These warnings do not constitute VU37P or F37X validation.

## 8. Current limitations and evidence boundary

The result is classified as:

```text
A14_XO_PACKAGE_LOCAL_PROXY = PASS
A14_XO_PACKAGE_TARGET_VU37P = BLOCKED
A14_VPP_LINK = NOT_RUN
A14_XCLBIN = NOT_GENERATED
A14_PHYSICAL_HBM = NOT_VALIDATED
A14_BOARD_TEST = NOT_RUN
```

This stage does not prove:

- XO reproduction using the actual VU37P device database;
- compatibility with the `inspur_f37x_xdma_201920_3` platform link flow;
- physical `HBM[0]` connectivity;
- XRT buffer allocation or Host execution;
- synthesis, implementation, timing, bandwidth, latency, or performance;
- integration of the A14 lookup path with the accepted A13 DLRM pipeline;
- FPGA programming or board execution.
