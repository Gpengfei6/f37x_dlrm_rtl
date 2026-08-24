# Stage 2N-A14 Target Build Runner V3 XO Metadata Fix

## 1. Purpose

This delivery records the second user-controlled target-server build attempt
for the standalone Stage 2N-A14 HBM embedding-lookup prototype and prepares a
minimal packaging correction for Vivado/Vitis 2020.2.

The V2 Git compatibility fix succeeded: the runner passed worktree collection,
entered Vivado, packaged the exact VU37P target, generated a non-empty XO, and
validated the XO archive. The attempt then stopped at the runner's generated
XML metadata gate, before `v++ --link`.

The correction is restricted to A14 packaging metadata and target-runner
validation. It does not modify A14 RTL, any testbench, the accepted A13
baseline, the register map, the HBM[0] connectivity request, or the 100 MHz
clock request.

## 2. Target attempt 2 context

```text
Server repository:
  /home/chaosuan/gpf/gpf_f37x_dlrm/
  f37x_dlrm_rtl_stage2n_a14_bundle_4d24272

Branch:
  work/stage2n-a13-cycle-counter

HEAD:
  e2aa046fa290ad352602cf5dd135b09a37dc80cc

Runner:
  scripts/build_stage2n_a14_target_v2.sh

Flow tag:
  STAGE2N_A14_TARGET_V2_GIT_COMPAT

Tool environment:
  Vivado 2020.2
  Vitis 2020.2

Target part:
  xcvu37p-fsvh2892-2L-e

Platform:
  inspur_f37x_xdma_201920_3
```

Attempt 1 remains retained separately under:

```text
build/stage2n_a14_attempt1_git_porcelain_block
results/stage2n_a14/target_build_v1_attempt1_git_porcelain_block
```

Its status remains a pre-Vivado old-Git compatibility failure and is not
relabelled as an XO failure.

## 3. Confirmed attempt 2 evidence

The V2 status file reported:

```text
A14_TARGET_BUILD_FLOW=STAGE2N_A14_TARGET_V2_GIT_COMPAT
A14_TARGET_RUNNER_VERSION=V2_GIT_PORCELAIN_COMPAT
A14_TARGET_XO_BUILD=FAIL
A14_VPP_LINK=BLOCKED_NOT_RUN
A14_XCLBIN_BUILD=BLOCKED_NOT_RUN
A14_HBM0_LINK_MAPPING=BLOCKED_NOT_RUN
A14_TARGET_VU37P_TIMING=BLOCKED_NOT_RUN
FAIL_REASON=A14 XO metadata validation failed
GIT_HEAD=e2aa046fa290ad352602cf5dd135b09a37dc80cc
A14_PHYSICAL_HBM_ACCESS=NOT_VALIDATED
A14_FPGA_DEVICE_ACCESS=NONE
A14_READY_FOR_BOARD=NO
```

The retained generated assets were non-empty:

| Asset | Recorded size |
|---|---:|
| Target XO | 12,325 bytes |
| Generated `kernel.xml` | approximately 1.4 KiB |
| Packaged-IP `component.xml` | approximately 75 KiB |

`unzip -t` checked every XO member and ended with no compressed-data errors.
The Vivado packaging log contained:

```text
TARGET_PART_USED=1
STAGE2N_A14_4_A_XO_PACKAGE=PASS
XO_SIZE_BYTES=12325
```

Therefore attempt 2 confirms exact-target XO generation and archive integrity,
but the runner correctly withheld `A14_TARGET_XO_BUILD=PASS` because the
generated interface metadata was inconsistent with the RTL contract.

## 4. Root cause

The generated `kernel.xml` described:

```text
m_axi_gmem mode       = master
m_axi_gmem dataWidth  = 32
m_axi_gmem range      = 0xFFFFFFFF
```

The frozen A14 wrapper declares:

```text
C_M_AXI_GMEM_DATA_WIDTH = 128
C_M_AXI_GMEM_ADDR_WIDTH = 64
```

The generated control metadata was otherwise correct:

- `hwControlProtocol=user_managed`;
- `s_axi_control` is a 32-bit slave;
- five arguments exist at offsets `0x10`, `0x20`, `0x24`, `0x28`, and `0x2C`;
- six component registers exist, including `CONTROL` at `0x00`;
- all register names, offsets, sizes, and access modes match the reviewed map.

Vivado 2020.2 inferred the AXI port bundle but retained the default 32-bit
values for both AXI bus parameters in the packaged metadata. This is a
packaging-metadata issue, not evidence that the synthesizable RTL ports became
32 bits.

The applicable AMD documentation states that `package_xo` generates
`kernel.xml` from the packaged IP `component.xml`, that the kernel XML
`dataWidth` default is 32 bits, and that RTL-kernel memory-mapped AXI master
interfaces require 64-bit address support. AMD's packaging tutorial shows
explicit `ipx::add_bus_parameter` plus `set_property value` for the AXI master
data width.

Primary references:

- [AMD UG1393 2020.2, RTL Kernel XML File](https://docs.amd.com/r/2020.2-English/ug1393-vitis-application-acceleration/RTL-Kernel-XML-File);
- [AMD UG1393 2020.2, Package the RTL Code as a Vivado IP](https://docs.amd.com/r/2020.2-English/ug1393-vitis-application-acceleration/Package-the-RTL-Code-as-a-Vivado-IP);
- [AMD Vitis Hardware Acceleration Tutorial, Associate AXI Master Port to
  Pointer Argument and Set Data Width](https://docs.amd.com/r/2024.1-English/Vitis-Tutorials-Hardware-Acceleration/4-Associate-AXI-Master-Port-to-Pointer-Argument-and-Set-Data-Width).

## 5. Corrective design

The new packaging entry is:

```text
scripts/package_stage2n_a14_rtl_kernel_v2.tcl
```

Before saving the packaged core or invoking `package_xo`, it explicitly creates
or updates exactly one bus parameter for each frozen interface property:

```text
m_axi_gmem DATA_WIDTH = 128
m_axi_gmem ADDR_WIDTH = 64
```

It then requires the generated XML to contain:

```text
dataWidth="128"
range="0xFFFFFFFFFFFFFFFF"
```

The common build implementation now accepts an A14 packaging-Tcl override while
retaining the V1 default. Its Python metadata gate also parses the AXI master
range and requires the full 64-bit value.

The new user-controlled target entry point is:

```text
scripts/build_stage2n_a14_target_v3.sh
```

It selects packaging V2 and records:

```text
A14_TARGET_BUILD_FLOW=STAGE2N_A14_TARGET_V3_XO_METADATA_FIX
A14_TARGET_RUNNER_VERSION=V3_EXPLICIT_AXI_METADATA
```

All later XO, `v++`, xclbin, HBM[0] connectivity, routed timing, and no-board
gates remain in the common runner.

## 6. Changed file set

```text
scripts/build_stage2n_a14_target_v1.sh
scripts/build_stage2n_a14_target_v3.sh
scripts/package_stage2n_a14_rtl_kernel_v2.tcl
docs/STAGE2N_A14_TARGET_BUILD_RUNNER_V3_XO_METADATA_FIX.md
docs/CURRENT_STATE.md
docs/DECISIONS.md
```

No file under `rtl/`, `tb/`, `host/`, `config/`, or the accepted A13 file set is
modified.

## 7. Local verification

Completed locally:

```text
V1_BASH_SYNTAX=PASS
V2_BASH_SYNTAX=PASS
V3_BASH_SYNTAX=PASS
EMBEDDED_PYTHON_1=PASS
EMBEDDED_PYTHON_2=PASS
TCL_EXPLICIT_DATA_WIDTH_STRUCTURE=PASS
TCL_EXPLICIT_ADDR_WIDTH_STRUCTURE=PASS
V3_EVIDENCE_TAGS=PASS
DIFF_CHECK=PASS
```

Unavailable locally:

```text
SHELLCHECK=NOT_RUN_MISSING_TOOL
TCL_PARSE=NOT_RUN_MISSING_TOOL
VIVADO_2020_2_PACKAGE=NOT_RUN_LOCAL_ENVIRONMENT
VPP_LINK=NOT_RUN_LOCAL_ENVIRONMENT
XCLBIN=NOT_RUN_LOCAL_ENVIRONMENT
TARGET_TIMING=NOT_RUN_LOCAL_ENVIRONMENT
PHYSICAL_HBM=NOT_VALIDATED
BOARD_EXECUTION=NOT_RUN
```

Static inspection does not prove that Vivado 2020.2 will emit the corrected
XML. Only the user-controlled V3 retry can promote target XO metadata, Vitis
link, xclbin, HBM[0] link metadata, or target timing to PASS.

## 8. Attempt 2 preservation and V3 retry

Before V3, attempt 2 must be retained without overwrite as:

```text
build/stage2n_a14
  -> build/stage2n_a14_attempt2_xo_metadata_block

results/stage2n_a14/target_build_v1
  -> results/stage2n_a14/target_build_v1_attempt2_xo_metadata_block
```

The intended user-controlled command is then:

```bash
bash scripts/build_stage2n_a14_target_v3.sh
```

The runner remains build-only. It does not open an XRT device, program or reset
an FPGA, run a Host application, or perform a physical HBM transaction.

## 9. V3 acceptance criteria

V3 may pass the XO gate only if all of the following hold:

1. Vivado exits successfully using the exact VU37P target part;
2. XO, `kernel.xml`, and `component.xml` exist and are non-empty;
3. the XO archive passes integrity checking;
4. the kernel name and `user_managed` protocol match;
5. the port set is exactly `s_axi_control` plus `m_axi_gmem`;
6. `m_axi_gmem` is master, 128-bit data, and 64-bit address range;
7. all five arguments and all six component registers match the reviewed map.

Only after that gate may `v++ --link` run. A linked xclbin and HBM[0]
connectivity metadata still do not prove physical HBM access or board function.

## 10. Status at this checkpoint

```text
A14_ATTEMPT1_GIT_COMPATIBILITY       = FAIL_CONFIRMED_AND_ARCHIVED
A14_ATTEMPT2_TARGET_XO_GENERATION    = CONFIRMED
A14_ATTEMPT2_TARGET_XO_INTEGRITY     = PASS
A14_ATTEMPT2_XO_METADATA             = FAIL_CONFIRMED
A14_ATTEMPT2_VPP_LINK                = BLOCKED_NOT_RUN
A14_ATTEMPT2_XCLBIN                  = BLOCKED_NOT_RUN
A14_V3_LOCAL_STATIC_CHECK            = PASS
A14_V3_TARGET_RETRY                  = NOT_RUN
A14_PHYSICAL_HBM_ACCESS              = NOT_VALIDATED
A14_FPGA_DEVICE_ACCESS               = NONE
A14_READY_FOR_BOARD                  = NO
```
