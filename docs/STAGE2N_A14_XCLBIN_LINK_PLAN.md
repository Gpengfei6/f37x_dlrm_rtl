# Stage 2N-A14.4-B1 XCLBIN Link Architecture Freeze

## 1. Scope and evidence boundary

Stage 2N-A14.4-B1 freezes the future Vitis link inputs, kernel-name discovery method, logical memory-port binding, and evidence requirements. It is a design-document stage only.

No `v++` command is executed in this stage. No xclbin is generated, no platform is opened, no physical HBM is accessed, and no FPGA board state is changed.

Current status:

```text
STAGE2N_A14_4_B1_LINK_ARCHITECTURE_FREEZE = PASS
A14_VPP_LINK                              = NOT_RUN
A14_XCLBIN                                = NOT_GENERATED
A14_PHYSICAL_HBM                          = NOT_VALIDATED
A14_BOARD_EXECUTION                       = NOT_RUN
```

## 2. Relationship between A14.4-A XO and A14.4-B link

Stage 2N-A14.4-A packages the verified A14 wrapper and A14.1 lookup IP into an RTL-kernel XO. The XO contains the logical AXI4-Lite control port, the logical AXI4 master port, the packaged RTL sources, `component.xml`, and `kernel.xml`.

Stage 2N-A14.4-B will later consume that XO in a Vitis link operation. Link is responsible for combining the packaged kernel with a selected platform shell and applying the logical-to-physical memory connectivity configuration.

The boundary is:

```text
A14 wrapper RTL + A14.1 lookup RTL
                  |
                  | package_xo, completed in A14.4-A
                  v
        A14 RTL-kernel XO
                  |
                  | future v++ --link, not run in B1
                  v
              xclbin
```

`package_xo` success does not imply that `v++ --link` will succeed. The future link must independently validate platform availability, kernel metadata, HBM connectivity, implementation, timing, and generated artifact integrity.

## 3. Frozen input XO

The frozen link input is:

```text
build/stage2n_a14/xo_v1/
  dlrm_f37x_rtl_kernel_stage2n_a14_v1.xo
```

Current local artifact properties:

```text
SIZE_BYTES=12300
SHA256=d93b2e038653fed4913d9c845c7cbc530bc9830408445b61b1aaa7c1a3ba4a60
```

Before any future link, the runner must verify that the XO exists, is non-empty, is a readable archive, and matches the recorded SHA256 or an explicitly reviewed replacement artifact. The generated `kernel.xml` and packaged RTL files must also be present inside the XO.

The current XO was structurally packaged in local Vivado 2022.1 using an installed Artix-7 packaging proxy because the local installation does not contain the VU37P device database. Therefore, the XO is suitable for link-flow preparation, but target-part reproduction for `xcvu37p-fsvh2892-2L-e` remains a separate evidence requirement.

## 4. Kernel-name confirmation method

The kernel name must be read from generated metadata and must not be guessed from the filename, module filename, directory name, or stage name.

The authoritative metadata path is:

```text
build/stage2n_a14/xo_v1/kernel.xml
```

The name is read from the `/root/kernel/@name` XML attribute. An equivalent PowerShell check is:

```powershell
[xml]$kernelXml = Get-Content -Raw `
  'build\stage2n_a14\xo_v1\kernel.xml'
$kernelName = [string]$kernelXml.root.kernel.name
if ([string]::IsNullOrWhiteSpace($kernelName)) {
  throw 'kernel.xml does not contain /root/kernel/@name'
}
```

The current metadata reports:

```text
KERNEL_NAME=dlrm_f37x_rtl_kernel_stage2n_a14_v1
HW_CONTROL_PROTOCOL=user_managed
```

The same metadata reports `s_axi_control` as a 32-bit slave port and `m_axi_gmem` as a 128-bit master port. A future link runner must stop if the XML name or required ports differ from the expected reviewed metadata.

## 5. `m_axi_gmem` binding strategy

The logical AXI master port is:

```text
m_axi_gmem
```

The future initial physical binding is:

```text
m_axi_gmem -> HBM[0]
```

The binding is recorded separately from the RTL and XO in:

```text
config/stage2n_a14_v1.cfg
```

Its intended connectivity entry is:

```ini
[connectivity]
sp=dlrm_f37x_rtl_kernel_stage2n_a14_v1_1.m_axi_gmem:HBM[0]
```

The link runner must first obtain the kernel name from `kernel.xml`, then verify that the compute-unit prefix used by the `sp` entry refers to that kernel. The logical port name must exactly match the `m_axi_gmem` master port reported by `kernel.xml`; otherwise link must stop instead of silently selecting another memory port.

Physical bank selection remains link configuration rather than RTL logic. A14.4-B uses one logical port and one HBM bank only. Multi-bank scheduling, several memory ports, port striping, and bandwidth optimization are outside this architecture freeze.

## 6. Frozen future link flow

The planned data flow is:

```text
dlrm_f37x_rtl_kernel_stage2n_a14_v1.xo
                    |
                    | kernel name and ports verified from kernel.xml
                    | connectivity: m_axi_gmem -> HBM[0]
                    v
                 v++ --link
                    |
                    | synthesis, implementation and platform integration
                    v
                  xclbin
```

The future command shape is documented but not executed:

```powershell
v++ --link `
  --platform inspur_f37x_xdma_201920_3 `
  --config config/stage2n_a14_v1.cfg `
  --output build/stage2n_a14/link_v1/dlrm_f37x_stage2n_a14_v1.xclbin `
  build/stage2n_a14/xo_v1/dlrm_f37x_rtl_kernel_stage2n_a14_v1.xo
```

Before execution in a separately authorized stage, the exact platform identifier or `.xpfm` path must be confirmed from the actual Vitis environment. The future runner must use a new A14 link directory and must not overwrite A10, A11, A12, or A13 artifacts.

The link stage must record at least:

- Vitis and Vivado versions;
- resolved platform path and platform identifier;
- input XO path and SHA256;
- kernel name read from `kernel.xml`;
- compute-unit name;
- resolved `m_axi_gmem` to `HBM[0]` mapping;
- `v++ --link` command and exit code;
- anchored error and critical-warning counts;
- implementation and timing status;
- output xclbin path, size, UUID, and SHA256.

## 7. Explicit limitations and non-goals

Stage 2N-A14.4-B1 does not authorize or claim:

- execution of `v++`, including `v++ --link`;
- generation or acceptance of an xclbin;
- FPGA board programming, reset, or Host execution;
- physical HBM connectivity or successful access to `HBM[0]`;
- HBM bandwidth, latency, throughput, or performance improvement;
- integration of the A14 lookup kernel into the A13 Bottom/Interaction/Top DLRM pipeline;
- modification of any accepted A13 RTL, Host source, script, or configuration;
- modification of the A14 wrapper, A14.1 lookup RTL, or their testbenches;
- multi-bank HBM mapping, DMA optimization, burst optimization, or multiple outstanding reads.

The current A14 XO and this architecture freeze establish only the inputs and rules for a later separately authorized link attempt.
