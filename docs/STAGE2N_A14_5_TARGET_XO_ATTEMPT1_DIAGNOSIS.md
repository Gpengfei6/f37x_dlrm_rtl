# Stage 2N-A14.5 Exact-Target XO Attempt 1 Diagnosis

Snapshot date: 2026-08-25

## 1. Scope

This record reviews the user-controlled Vivado 2020.2 run of
`scripts/build_stage2n_a14_5_target_xo_v1.sh` at commit `de9276e`. The run used
the exact target part `xcvu37p-fsvh2892-2L-e` and stopped during the XO metadata
gate. It did not invoke `v++`, link an xclbin, access XRT, bind physical HBM, or
touch an FPGA device.

The failed gate does not invalidate the accepted local XSim result. It also
does not constitute physical-HBM or board evidence.

## 2. Observed outcome

Vivado successfully produced these non-empty generated artifacts in the
user-controlled server worktree:

- A14.5 v2 XO: approximately 13 KiB;
- standalone `kernel.xml`: approximately 1.6 KiB;
- packaged `component.xml`: approximately 76 KiB.

`unzip -t` reported no compressed-data errors. The standalone and in-XO
`kernel.xml` content returned by the user are identical. The package log also
reached `package_xo`, passed IP integrity checking, and used the exact VU37P
part.

The v1 runner nevertheless stopped because the generated kernel port was:

```xml
<port name="m_axi_gmem" mode="master" range="0xFFFFFFFF"
      dataWidth="128" portType="addressable" base="0x0"/>
```

The v1 gate required `range="0xFFFFFFFFFFFFFFFF"` and therefore reported an
error after artifact generation.

## 3. Returned 64-bit address evidence

The following independent fields all describe a 64-bit AXI address path:

| Layer | Returned evidence |
|---|---|
| Source RTL | `C_M_AXI_GMEM_ADDR_WIDTH=64` |
| Source RTL ports | `m_axi_gmem_awaddr/araddr[C_M_AXI_GMEM_ADDR_WIDTH-1:0]` |
| Packaged AXI bus parameter | `ADDR_WIDTH=64` |
| Packaged model parameter | `C_M_AXI_GMEM_ADDR_WIDTH=64` |
| Packaged user parameter | `C_M_AXI_GMEM_ADDR_WIDTH=64` |
| Packaged physical ports | `AWADDR[63:0]`, `ARADDR[63:0]` |
| IP-XACT address space | `16777216T`, equal to `2^64` bytes |
| Kernel argument | `TABLE_BASE`, size/hostSize 8 bytes, `void*` |
| Kernel binding | `addressQualifier=1`, `port=m_axi_gmem` |
| Component register | `TABLE_BASE`, offset `0x18`, width 64, RW |
| Register association | `ASSOCIATED_BUSIF=m_axi_gmem` |

The 128-bit data path is also consistent across `kernel.xml`, the AXI bus
parameter, model/user parameters, and the IP-XACT address-space width.

Therefore `kernel.xml` port `range=0xFFFFFFFF` is not sufficient evidence that
this generated XO has a 32-bit physical AXI address port. In this Vivado 2020.2
output it conflicts with the more specific packaged component and RTL fields.
It must be recorded, but it must not be used as the sole address-width gate.

## 4. Status-file defect

The retained v1 status says:

```text
A14_5_TARGET_XO_BUILD=BLOCKED_NOT_RUN
FAIL_REASON=unexpected command failure at line 135
```

That status is not an accurate description of the executed build. The XO was
actually generated before the metadata assertion failed. The cause is runner
control flow: `set +e` does not suppress an active Bash `ERR` trap for a failed
pipeline when `pipefail` is enabled. The trap ran before the script could store
the Vivado return code and set the intended `FAIL` state.

Attempt 1 should therefore be described as:

```text
XO generation: CONFIRMED
XO archive integrity: PASS
TABLE_BASE/global-pointer metadata: CONFIRMED by returned inspection
Old range-only metadata gate: FAIL/DIAGNOSED
v++/xclbin/Host/HBM/FPGA: NOT RUN
```

The original generated files, logs, and status remain historical evidence and
must not be overwritten or relabeled in place.

## 5. Corrected acceptance rule

The versioned retry must require all of the following:

1. exact target part and an intact, non-empty XO;
2. identical standalone and in-XO `kernel.xml` and `component.xml`;
3. 128-bit `m_axi_gmem` data metadata;
4. 64-bit RTL address parameter and AWADDR/ARADDR ports;
5. 64-bit packaged AXI bus, model, and user parameters;
6. `AWADDR[63:0]` and `ARADDR[63:0]` in `component.xml`;
7. a `2^64`-byte IP-XACT address space;
8. an 8-byte `TABLE_BASE` global-memory argument at `0x18`, associated with
   `m_axi_gmem`;
9. the observed `kernel.xml` port range recorded as either
   `0xFFFFFFFF` or `0xFFFFFFFFFFFFFFFF`;
10. retained source/artifact hashes, tool version, validation log, and status.

This is not a weakened gate. It replaces one ambiguous generated field with a
cross-layer consistency proof while still rejecting a truly 32-bit RTL or
packaged address interface.

## 6. Versioned retry assets

The corrected, non-overwriting flow is prepared in:

- `scripts/package_stage2n_a14_rtl_kernel_v4.tcl`;
- `scripts/validate_stage2n_a14_5_xo_v2.py`;
- `scripts/build_stage2n_a14_5_target_xo_v2.sh`.

It writes only to new roots:

```text
build/stage2n_a14/xo_v3
results/stage2n_a14_5/target_xo_v2
```

The retry is **NOT RUN** until the user executes it in the controlled target
environment and returns its status, validation log, package log, and artifact
hashes. No A14.5 XO PASS is claimed by preparing these files.
