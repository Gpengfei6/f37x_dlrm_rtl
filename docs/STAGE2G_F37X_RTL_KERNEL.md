# Stage 2G — F37X Vitis RTL Kernel Packaging

## Purpose

Stage 2G adds a platform wrapper around the already verified
`mlp_sequence_controller`. The calculation core is not rewritten.

The wrapper is stored with the other top-level RTL modules under `rtl/top` and exposes one user-managed AXI4-Lite control interface so that
the DLRM core can be packaged as a Vitis RTL kernel (`.xo`) for the installed
Inspur F37X platform.

## Fixed platform

- Vitis/Vivado: 2020.2
- Packaging part: `xcvu37p-fsvh2892-2L-e`
- F37X platform:
  `/opt/xilinx/platforms/inspur_f37x_xdma_201920_3/inspur_f37x_xdma_201920_3.xpfm`
- Kernel name: `dlrm_f37x_rtl_kernel`
- Control protocol: `user_managed`

The final F37X link uses the `.xpfm`; it must not use
`xc7a200tfbg484-2`.

## Stage boundary

Stage 2G proves:

1. The AXI4-Lite wrapper can configure and run the existing MLP core.
2. A real F37X-compatible Vitis RTL-kernel `.xo` can be generated.

Stage 2G does not yet prove:

- `.xclbin` link completion;
- host execution;
- board numerical correctness;
- high-throughput memory transfer;
- performance.

Those belong to later stages.

## Commands

Run simulation first:

```bash
cd /home/chaosuan/gpf/gpf_f37x_dlrm/f37x_dlrm_rtl_stage2e
bash scripts/run_stage2g_kernel_xsim.sh
```

Then package the kernel:

```bash
bash scripts/run_stage2g_xo.sh
```

Expected markers:

```text
STAGE2G_KERNEL_XSIM_PASS
STAGE2G_XO_PACKAGE_PASS
```

## AXI4-Lite command register

Write exactly one command value to address `0x000`:

| Value | Command |
|---:|---|
| `0x01` | Start MLP |
| `0x02` | Commit descriptor staging registers |
| `0x04` | Commit activation staging registers |
| `0x08` | Commit weight staging registers |
| `0x10` | Commit bias staging registers |
| `0x20` | Accept/pop the current result |
| `0x40` | Acknowledge core/wrapper error |
| `0x80` | Clear latched done |

Do not combine command bits.

## Status register

Reading `0x000` returns:

| Bits | Meaning |
|---:|---|
| 0 | Core busy |
| 1 | Done latched |
| 2 | Result valid |
| 3 | Result last |
| 4 | Core error valid |
| 5 | Wrapper error valid |
| 6 | Final activation-buffer selector |
| 7 | A command is pending |
| 8 | Core start ready |
| 9 | Descriptor ready |
| 10 | Activation ready |
| 11 | Weight ready |
| 12 | Bias ready |
| 23:16 | Result layer tag |
| 27:24 | Core error code |
| 31:28 | Wrapper error code |

## Register map

| Offset | Register |
|---:|---|
| `0x000` | Command / status |
| `0x004` | Interface version |
| `0x008` | Accepted result count |
| `0x010` | Layer count |
| `0x014` | Initial buffer selector |
| `0x020` | Descriptor index |
| `0x024` | Descriptor bits 31:0 |
| `0x028` | Descriptor bits 63:32 |
| `0x02C` | Descriptor bits 95:64 |
| `0x040` | Activation buffer selector |
| `0x044` | Activation chunk index |
| `0x048` | Activation lane mask |
| `0x050–0x06C` | 256-bit activation payload |
| `0x080` | Weight address |
| `0x084` | INT8 weight data |
| `0x090` | Bias address |
| `0x094` | Signed 24-bit bias data |
| `0x0A0` | Sign-extended result data |
| `0x0A4` | Result index |
| `0x0A8` | Result valid/last/tag |

## Performance boundary

AXI4-Lite loading is intentionally used only for the first board bring-up.
It is simple and auditable but not a final high-throughput DLRM data path.

After `.xo`, `.xclbin`, and board correctness are proven, weights and
activations should move through an AXI master or streaming interface.
