# Stage 2N-A18.2 — local target packaging and Host ABI preparation

Date: 2026-09-17. Status: **local source preparation**.
`A18_2_LOCAL_PREP_CHECK` may become PASS after the static gates below.
`A18_2_TARGET_XO=NOT_RUN`, `A18_2_TARGET_LINK=NOT_RUN`,
`A18_2_XCLBIN=NOT_RUN`, `A18_2_BOARD=NOT_RUN`.
`PERFORMANCE=NOT_CLAIMED`.

This increment does not run `v++`, Vivado batch packaging, XRT, `xbutil`, or
any FPGA. The user alone may later transfer the reviewed tree and execute
the versioned build runner in the controlled 2020.2 environment.

## Why this step exists

A18.1 proved programmable four-slot indexes in local 2022.1 XSim. Board use
still needs:

1. a versioned XO/link package of `dlrm_f37x_rtl_kernel_stage2n_a18_v1`;
2. a Host that writes `0x330-0x33C` before START;
3. software goldens for non-default rows, so `-393` is not reused by accident.

T>4, placement, cache, and co-access mapping remain out of scope. Four
masters still map `m_axi_gmem0..3 -> HBM[0..3]` at 100 MHz, same geometry as
A17.6.

## Kernel / CU / connectivity

| Item | Value |
|---|---|
| Kernel | `dlrm_f37x_rtl_kernel_stage2n_a18_v1` |
| CU | `dlrm_a18_1` |
| Part | `xcvu37p-fsvh2892-2L-e` |
| Platform | `inspur_f37x_xdma_201920_3` |
| Clock | requested 100 MHz |
| Masters | four, 64-bit address / 128-bit data |
| Pointer args | `TABLE_BASE0..3` at `0x304/0x318/0x320/0x328` |
| Lookup indexes | AXI-Lite MMIO `0x330-0x33C`, **not** XO kernel arguments |

Packaging Tcl still rejects a stale A14 `LOOKUP_INDEX` pointer argument.
Indexes are programmed with `xclRegWrite`, like START at `0x300`.

The package RTL list matches the A18.1 XSim closure (19 files). It does not
instantiate leftover
`rtl/f37x/dlrm_internal_pipeline_axi_lite_decode_stage2n_a18_v1.sv`.
Accepted A13/A14/A16/A17 originals are reused, not edited.

## Host

`host/stage2n_a18_2_four_bo_host_v1.cpp` is a versioned copy of the A17.6
four-BO Host:

- CU `dlrm_f37x_rtl_kernel_stage2n_a18_v1:dlrm_a18_1`;
- pipeline version `0x00024E18`;
- rejects A16 and A17 CU names;
- writes and readbacks four lookup indexes before START;
- default indexes `37,38,39,40`, so the locked A15.6/A16.2 board goldens
  `-393/-392/-93/-689/-519` remain valid;
- `A18_2_LOOKUP_INDEXES` other than 37–40 is refused in this five-case Host.

Sensitivity cases still mutate row `37+i` on BO `i` only. That is legal only
while the programmed indexes stay 37–40.

## Software goldens for other rows

`python/eval_stage2n_a18_2_index_golden_v1.py` reconstructs the A11 v2
Bottom–Interaction–Top path from the frozen A15.6 `model.bin` and a 1024-byte
table. Self-test requires default rows 37–40 to match the locked five-case
board goldens, rejects OOB 64, and writes extra tuples under
`models/stage2n_a18_2/index_goldens_v1.json`. Those extras are **not** board
results.

## Local commands (Windows worktree)

```
python scripts/check/check_stage2n_a18_2_local_prep_v1.py
python scripts/test_stage2n_a18_2_build_v1.py
python scripts/test_stage2n_a18_2_host_v1.py
python python/eval_stage2n_a18_2_index_golden_v1.py --self-test
python scripts/run_stage2n_a18_2_build_v1.py check
```

`check` is source integrity only. `xo` / `link` require `--confirm-build` and
Vitis/Vivado **2020.2** on the user-controlled server. A local 2022.1 XSim
pass is not that build.

## Later server actions (do not run here)

After the user copies this tree:

```
python3 scripts/run_stage2n_a18_2_build_v1.py check
python3 scripts/run_stage2n_a18_2_build_v1.py xo --output runs/a18_2_xo_001 --confirm-build
```

Link only after that XO is reviewed:

```
python3 scripts/run_stage2n_a18_2_build_v1.py link --xo-run runs/a18_2_xo_001 --output runs/a18_2_link_001 --platform /opt/xilinx/platforms/inspur_f37x_xdma_201920_3/inspur_f37x_xdma_201920_3.xpfm --jobs 8 --confirm-build
```

Host compile (still no device):

```
A18_2_ALLOW_HOST_REBUILD=yes bash scripts/build_stage2n_a18_2_host_v1.sh
```

Do not program a card, do not reuse the A17 Host or A17 xclbin, and do not
treat software extras as physical goldens.

## Evidence boundary

Local preparation can prove source closure, Host ABI tokens, map-parser
fixtures, and A15.6 software-golden self-test. It cannot prove XO validity,
xclbin mapping, 100 MHz routed timing, physical HBM, FPGA execution, or any
performance number.
