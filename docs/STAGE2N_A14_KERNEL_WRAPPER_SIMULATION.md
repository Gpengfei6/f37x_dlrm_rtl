# Stage 2N-A14.3-A2 Kernel Wrapper Simulation Verification

## 1. Test objective

Stage 2N-A14.3-A2 verifies the standalone Vitis-style kernel wrapper introduced by Stage 2N-A14.3-A. The test is limited to local RTL simulation and checks the complete control-to-memory-to-result path:

```text
AXI4-Lite master model
  -> A14 kernel wrapper
  -> A14.1 embedding lookup IP
  -> fake m_axi_gmem memory
  -> result registers
```

The repository baseline is commit `63ae1c4` (`Stage 2N-A13 cycle-counter board validation`) on branch `work/stage2n-a14-hbm-embedding`. The accepted A13 RTL and the A14.1 lookup RTL were not modified for this verification.

## 2. Kernel wrapper structure under test

The design under test is:

- `rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a14_v1.sv`

It contains:

- a 32-bit AXI4-Lite slave control interface;
- the `START` and `LOOKUP_INDEX` control path;
- an instance of `dlrm_hbm_embedding_lookup_stage2n_a14_v1`;
- a complete logical AXI4 `m_axi_gmem` port bundle whose write channels remain inactive;
- one single-outstanding, single-beat 128-bit AXI4 read path;
- four 32-bit result registers that retain the returned 128-bit embedding vector.

The A14.1 lookup address remains the relative byte address `lookup_index << 4`. No physical HBM base address, bank binding, or platform connectivity is modeled in this test.

## 3. AXI4-Lite register flow

The self-checking testbench implements an AXI4-Lite master and accesses the following registers:

| Offset | Register | Test operation |
| ---: | --- | --- |
| `0x00` | `CONTROL` | Write bit 0 to issue `START`; poll done, idle, ready, and error bits. |
| `0x10` | `LOOKUP_INDEX` | Program the 32-bit lookup row index. |
| `0x20` | `RESULT0` | Read lanes 0 and 1. |
| `0x24` | `RESULT1` | Read lanes 2 and 3. |
| `0x28` | `RESULT2` | Read lanes 4 and 5. |
| `0x2C` | `RESULT3` | Read lanes 6 and 7. |

For each case, the testbench writes `LOOKUP_INDEX`, writes `START=1`, polls `CONTROL` until done is observed, reads all four result registers, reconstructs the 128-bit vector, and compares it with an independently generated golden row. The test also verifies that error remains zero and that the control state returns to idle and ready after the clear-on-read done event.

AXI4-Lite write and read transactions check the `BRESP` and `RRESP` values. A timeout converts a missing address, data, response, or done handshake into a simulation failure.

## 4. Fake `m_axi_gmem` memory model

The testbench contains a 64-row fake AXI memory. Each row has eight signed 16-bit elements packed into one 128-bit beat. The initialized value is:

```text
value[row][lane] = row * 8 + lane - 256
```

The memory accepts the row address:

```text
row_addr = lookup_index << 4
```

The model deliberately holds `ARREADY` low for two cycles after seeing `ARVALID`. This checks that the A14.1 lookup IP retains a stable AXI read request under address-channel backpressure. After one accepted address, the model returns one successful response with `RRESP=OKAY` and `RLAST=1`.

Every accepted read is checked for:

- `ARID=0`;
- `ARLEN=0`;
- `ARSIZE=4`, representing 16 bytes;
- `ARBURST=INCR` with only one beat;
- 16-byte alignment;
- address range `0` through `1008`;
- exact equality to the current expected `lookup_index << 4` address;
- no second outstanding transaction;
- inactive AXI write channels.

Separate counters require exactly one AR handshake and one R handshake for every lookup case.

## 5. Test cases

Four required directed indices were tested:

```text
0, 1, 31, 63
```

Ten deterministic pseudo-random indices were then generated and tested:

```text
52, 46, 53, 31, 5, 28, 10, 57, 10, 63
```

The test contains 14 total lookup cases. Repetition in the pseudo-random set is retained because each occurrence is a separate register-programming and AXI transaction test.

## 6. Simulation command and result

The local simulator was Vivado/XSim 2022.1, SW Build 3526262. The commands were run from an isolated temporary directory using the following equivalent command sequence:

```powershell
& 'D:\vivado2022\vivado2022forwins\Vivado\2022.1\bin\xvlog.bat' --sv `
  '..\rtl\hbm\dlrm_hbm_embedding_lookup_stage2n_a14_v1.sv' `
  '..\rtl\f37x\dlrm_f37x_rtl_kernel_stage2n_a14_v1.sv' `
  '..\tb\tb_dlrm_f37x_rtl_kernel_stage2n_a14_v1.sv'

& 'D:\vivado2022\vivado2022forwins\Vivado\2022.1\bin\xelab.bat' `
  tb_dlrm_f37x_rtl_kernel_stage2n_a14_v1 `
  -s tb_dlrm_f37x_rtl_kernel_stage2n_a14_v1_sim

& 'D:\vivado2022\vivado2022forwins\Vivado\2022.1\bin\xsim.bat' `
  tb_dlrm_f37x_rtl_kernel_stage2n_a14_v1_sim -runall
```

Observed result:

| Stage | Result | Exit code |
| --- | --- | ---: |
| `xvlog` compile | PASS | 0 |
| `xelab` elaboration | PASS | 0 |
| XSim run | PASS | 0 |

The final self-checking marker was:

```text
tb_dlrm_f37x_rtl_kernel_stage2n_a14_v1: PASS cases=14 ar=14 r=14
```

Simulation completed at 4010 ns. The generated `xvlog.log`, `xelab.log`, and `xsim.log` contained zero anchored warnings, zero critical warnings, and zero anchored errors or fatal messages. The temporary simulation directory and generated `xsim.dir` were not retained.

The verified items are:

- AXI4-Lite register writes and reads: PASS;
- `LOOKUP_INDEX` programming: PASS;
- `START` control and done polling: PASS;
- A14.1 lookup integration: PASS;
- `m_axi_gmem` AR handshakes: 14/14;
- `m_axi_gmem` R handshakes: 14/14;
- one read per accepted lookup: PASS;
- 128-bit result readback and golden comparison: 14/14 PASS;
- done behavior: PASS;
- error remained zero: PASS.

Therefore:

```text
STAGE2N_A14_3_A2_KERNEL_WRAPPER_SIMULATION = PASS
```

## 7. Limitations and evidence boundary

This result proves only the standalone AXI4-Lite control behavior, kernel-wrapper logic, A14.1 lookup-IP integration, logical `m_axi_gmem` transaction behavior, and fake-memory simulation correctness.

It does not prove:

- physical F37X HBM connectivity or bank binding;
- Vitis RTL-kernel packaging;
- XO generation;
- Vitis linking or xclbin generation;
- XRT buffer-object or Host execution;
- FPGA programming or board execution;
- physical HBM latency, bandwidth, or throughput;
- any latency or performance improvement;
- integration with the accepted A13 DLRM pipeline.
