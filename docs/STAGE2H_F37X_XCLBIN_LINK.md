# Stage 2H — F37X Hardware XCLBIN Link

## Goal

Link the Stage 2G user-managed RTL kernel against the installed Inspur
F37X platform and generate a real hardware `.xclbin`.

## Inputs

- Kernel XO:
  `build/stage2g/package/dlrm_f37x_rtl_kernel.xo`
- Platform:
  `/opt/xilinx/platforms/inspur_f37x_xdma_201920_3/inspur_f37x_xdma_201920_3.xpfm`
- Toolchain: Vitis 2020.2
- First-link kernel frequency: 100 MHz
- Compute-unit name: `dlrm_f37x_rtl_kernel_1`

The 100 MHz first-link target is intentionally conservative. It matches the
frequency already used for the previous RTL timing feasibility work and avoids
claiming a higher F37X operating frequency before implementation evidence
exists.

## Run

```bash
cd /home/chaosuan/gpf/gpf_f37x_dlrm/f37x_dlrm_rtl_stage2e
source /opt/Xilinx/Vitis/2020.2/settings64.sh
bash scripts/run_stage2h_f37x_link.sh
```

A successful run ends with:

```text
STAGE2H_F37X_LINK_PASS
```

## Outputs

- `build/stage2h/hw/dlrm_f37x_rtl_kernel.xclbin`
- `results/stage2h/stage2h_f37x_link_status.txt`
- `results/stage2h/dlrm_f37x_rtl_kernel.xclbin.info`
- `logs/vpp_stage2h_f37x_link.log`

## Acceptance criteria

1. `v++ --link --target hw` exits with code zero.
2. The `.xclbin` exists and is non-empty.
3. XCLBIN metadata contains `dlrm_f37x_rtl_kernel`.
4. No anchored `ERROR:` or `CRITICAL WARNING:` appears in the Vitis link log.
5. A routed timing report is located and retained for review.

## Boundary

Passing Stage 2H proves F37X platform integration and hardware-bitstream
generation. It does not yet prove that the host can load the image, access the
kernel registers, or obtain numerically correct results on a physical card.
Those are board bring-up tasks for the following stage.
