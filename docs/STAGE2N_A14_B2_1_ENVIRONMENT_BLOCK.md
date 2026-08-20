# Stage 2N-A14.4-B2.1 Vitis Link Environment Block

## 1. Current stage objective

The intended Stage 2N-A14.4-B link path is:

```text
A14 RTL-kernel XO
        |
        | v++ --link with the F37X platform and connectivity configuration
        v
      xclbin
```

Stage 2N-A14.4-B2.1 performs environment validation only. It does not execute the link path.

## 2. Checks that passed

### 2.1 XO existence

The expected XO exists and is non-empty:

```text
build/stage2n_a14/xo_v1/dlrm_f37x_rtl_kernel_stage2n_a14_v1.xo
SIZE_BYTES=12300
```

### 2.2 XO SHA256

The calculated XO SHA256 matches the frozen A14.4-A value:

```text
d93b2e038653fed4913d9c845c7cbc530bc9830408445b61b1aaa7c1a3ba4a60
```

Result:

```text
A14_B2_1_XO_SHA256_CHECK=PASS
```

### 2.3 `kernel.xml` metadata

The kernel name was read from `/root/kernel/@name` in the generated `kernel.xml`; it was not inferred from a filename:

```text
KERNEL_NAME=dlrm_f37x_rtl_kernel_stage2n_a14_v1
HW_CONTROL_PROTOCOL=user_managed
```

The metadata also contains:

```text
s_axi_control: slave, 32-bit
m_axi_gmem: master, 128-bit
```

Result:

```text
A14_B2_1_KERNEL_XML_CHECK=PASS
```

### 2.4 Connectivity configuration

The following configuration exists:

```text
config/stage2n_a14_v1.cfg
```

Its logical-to-physical binding is:

```ini
[connectivity]
sp=dlrm_f37x_rtl_kernel_stage2n_a14_v1_1.m_axi_gmem:HBM[0]
```

The kernel prefix and `m_axi_gmem` port agree with the generated kernel metadata.

Result:

```text
A14_B2_1_CFG_CHECK=PASS
```

### 2.5 Vivado environment

The locally installed Vivado executable is callable through its explicit path and reports:

```text
Vivado v2022.1 (64-bit)
SW Build 3526262
IP Build 3524634
```

Result:

```text
A14_B2_1_VIVADO_CHECK=PASS
```

## 3. Current blockers

The current Windows environment cannot enter `v++ --link` because all of the following link prerequisites are absent:

1. The Vitis installation root and the `v++` linker executable are not present or discoverable.
2. The F37X platform metadata file for `inspur_f37x_xdma_201920_3` is not present in the checked local installation paths.
3. `PLATFORM_REPO_PATHS` and `XILINX_PLATFORM_REPO_PATHS` are not set.

The presence of a `Vitis_HLS 2022.1` directory does not provide the missing Vitis linker, XRT environment, or F37X `.xpfm` platform.

Environment classification:

```text
A14_B2_1_VITIS_LINK_ENV=BLOCKED
READY_FOR_VPP_LINK=NO
```

This is an environment block rather than an XO, kernel-metadata, configuration, or RTL failure.

## 4. Actions explicitly not performed

Stage 2N-A14.4-B2.1 did not perform any of the following:

- no `v++` command was executed;
- no `v++ --link` command was executed;
- no xclbin was generated;
- no FPGA was programmed or reset;
- no Host application or board test was run;
- no physical HBM connection or access was attempted.

The number of xclbin files under the current A14 build directory remains zero.

## 5. Source preservation

The environment check and this evidence record do not modify:

- accepted Stage 2N-A13 RTL;
- the Stage 2N-A14.1 embedding lookup RTL;
- the Stage 2N-A14 kernel wrapper RTL;
- any A13 or A14 testbench;
- Host source code.

No link attempt may be relabeled as PASS until a separately authorized environment provides the actual Vitis linker and the reviewed F37X platform metadata.
