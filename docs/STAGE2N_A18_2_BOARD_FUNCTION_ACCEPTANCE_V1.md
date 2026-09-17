# Stage 2N-A18.2 — first board function acceptance (default indexes)

Date: 2026-09-17. Status: **BOARD FUNCTION PASS on default indexes 37–40**.
Original logs archived. `PERFORMANCE=NOT_CLAIMED`. Not a speedup versus A17.6.
Non-default MMIO indexes are out of scope for this A18.2 Host; they were
later boarded by A18.3 (`docs/STAGE2N_A18_3_BOARD_FUNCTION_ACCEPTANCE_V1.md`).

This document is the narrative acceptance record. Machine tokens and SHA256
digests of the copied originals are in
`docs/evidence/stage2n_a18_2/function_pass_v1/ACCEPTANCE.txt`.

## Why this run existed

A18.1 proved programmable indexes only in local Vivado 2022.1 XSim. A18.2
packaged the same public kernel for Vitis 2020.2 with four masters mapped to
`HBM[0..3]`, identical geometry to A17.6, and a Host that writes
`0x330-0x33C` before START. The first board execute had to answer one
question only: does the A18 kernel, with reset-default rows 37–40, still
produce the locked A15.6/A16.2 complete-DLRM goldens on four physical BOs?

It does **not** answer: other row tuples, T>4, placement, cache, bandwidth,
or any A17 speedup.

## What was programmed

| Item | Value |
|---|---|
| Device | index 2, BDF `0000:9b:00.1`, `/dev/dri/renderD129` |
| Pre-program UUID | `3a4ebb31-933a-45c2-9ce4-04adce88615c` |
| Programmed UUID | `32a9c911-af15-47fc-90c8-0bfe3894a3ef` |
| xclbin SHA256 | `bbb0fa1fcb5c39aea2a307eb8c8324eb406c51711b8ba2ae7830bc5fe3a36ec0` |
| Kernel / CU | `dlrm_f37x_rtl_kernel_stage2n_a18_v1` / `dlrm_a18_1` |
| Host ELF SHA256 | `89644eb255bc0fb265f186ab76615f8a63b3dea0d8d117b265e681f5f7a75a32` |
| Host source SHA256 | `0a00e8ab7eab7be90b53905b3e4114921e365e681ecc0aef4a73e9f4565c521f` |
| PIPE_VERSION | `0x00024e18` |
| Pointer args | `TABLE_BASE0..3` only |
| Lookup indexes | MMIO 37, 38, 39, 40 |

`xbutil program` succeeded. `FPGA_RESET=NOT_RUN`. `OTHER_DEVICE_ACCESS=NONE`.
The Host does not program; the protected runner programs when authorized.

## Functional result

Five sensitivity cases plus in-process repeat baseline, all on the locked
goldens, all `COMPLETE_DLRM_RESULT=PASS`, mask `0xF`, compute
`322/100/744/1174` with delta 0:

| Case | Expected | Actual | BO image mutated |
|---|---|---|---|
| CASE0 baseline | -393 | -393 | none (all baseline) |
| CASE1 slot0 | -392 | -392 | BO0 only |
| CASE2 slot1 | -93 | -93 | BO1 only |
| CASE3 slot2 | -689 | -689 | BO2 only |
| CASE4 slot3 | -519 | -519 | BO3 only |
| REPEAT_BASELINE | -393 | -393 | none |

BO physical addresses `0x0 / 0x10000000 / 0x20000000 / 0x30000000` for
`HBM[0..3]`. Memory indices by argument `0,1,2,3` (by tag, not assumed).

Observed counters on every case including repeat: lookup **33**, e2e **1210**,
overhead **3**. The same 33/1210/3 pattern appears on A17.6 first function.
Record it; do not convert it into a speedup. XSim identity 36 was not used.

`HOST_RUNTIME_PROCESS_HASH=NOT_CLAIMED`. ELF identity was checked before
program (`HOST_IDENTITY_CHECKED_BEFORE_PROGRAM=YES`).

## Evidence locations

Copied originals (do not overwrite):

`docs/evidence/stage2n_a18_2/function_pass_v1/20260917_171608/`

Server original (user side, unchanged):

`.../f37x_dlrm_rtl_stage2n_a18_2_buildonly/results/stage2n_a18_2/protected_v1/20260917_171608`

XO/link reviews: `docs/evidence/stage2n_a18_2/xo_001/`,
`docs/evidence/stage2n_a18_2/link_001/`. The full
`post_route_timing_summary.rpt` is kept off GitHub (~76 MB). Timing gate
WNS 0.000 / kernel clock 10.000 ns remains in metrics and the link
acceptance summary.

## What this does not close

- Non-default `0x330-0x33C` values **in this A18.2 Host**. The A18.2 Host
  refuses them even if `A18_2_ALLOW_NONDEFAULT_INDEXES=yes`, because the
  five-case payload still mutates row `37+i`. A18.3 boarded five locked
  tuples with a new Host and the same xclbin
  (`docs/STAGE2N_A18_3_BOARD_FUNCTION_ACCEPTANCE_V1.md`).
- Repeatability / Class C / comparable A16 vs A18 latency.
- Physical HBM bandwidth, throughput, power, energy.
- Official A17.2 frozen-tree XSim (`e4ce2ab`); this zip tree has LUTLP A17.

Do not program again and do not reset unless the user writes a new
authorization that names the destination UUID.
