# Stage 2N-A18.3 — local non-default index Host preparation

Date: 2026-09-17. Status: **Host g++ PASS**. Board function of those
tuples is separately accepted in
`docs/STAGE2N_A18_3_BOARD_FUNCTION_ACCEPTANCE_V1.md`.

`A18_3_HOST_XRT_BUILD=PASS` (user-returned).
`A18_3_BOARD_FUNCTION=PASS_FIVE_LOCKED_TUPLES`.
`PERFORMANCE=NOT_CLAIMED`.

## Why A18.2 cannot be “unlocked”

A18.2 first function PASS used MMIO 37–40 and the A15.6 five-case tables.
Sensitivity still writes a mutated **row 37+i** on BO `i` only. That is
true only while the programmed indexes stay 37–40.

The A18.2 Host therefore double-locks non-default indexes: missing
`A18_2_ALLOW_NONDEFAULT_INDEXES=yes` fails, and even with that env it
still throws. Do not patch `host/stage2n_a18_2_four_bo_host_v1.cpp`.
Its source/ELF SHA256 are part of the boarded identity.

## What A18.3 must do instead

Add a **new** versioned Host, for example
`host/stage2n_a18_3_index_tuple_host_v1.cpp`, that:

1. Reuses kernel `dlrm_f37x_rtl_kernel_stage2n_a18_v1:dlrm_a18_1` and
   PIPE_VERSION `0x00024E18`.
2. Loads the **baseline** 1024-byte table onto all four BOs for every
   tuple. No slot-sensitivity images.
3. Writes four MMIO indexes from a locked list, START, compares the
   complete-DLRM result to the software golden in
   `models/stage2n_a18_2/index_goldens_v1.json`.
4. Still programs indexes with `xclRegWrite`, not kernel arguments.
5. Does not call `xbutil program`.
6. Keeps A13 counters 322/100/744/1174 as a check, not as a speedup.

Locked extra tuples (software only until a board run is reviewed):

| Indexes | Expected |
|---|---|
| 37,38,39,40 | -393 (regression; same as CASE0) |
| 1,2,3,4 | -61 |
| 0,0,0,0 | -60 |
| 0,63,37,40 | -162 |
| 63,62,61,60 | -185 |

OOB 64 must not be sent as a passing tuple. The RTL issues no AR for
`index >= 64`; that is an error path, not a golden.

## This increment’s files

- This document.
- `host/stage2n_a18_3_index_tuple_host_v1.cpp`
- `scripts/build_stage2n_a18_3_host_v1.sh` (g++ only; never runs Host)
- `scripts/check/check_stage2n_a18_3_local_prep_v1.py`
- `scripts/test_stage2n_a18_3_host_v1.py`

The Host reuses the A18.2 xclbin map header `A18_2_MEM_MAP_V1` and CU
`dlrm_a18_1`. Usage:

```text
stage2n_a18_3_index_tuple_host_v1 \
  <device-index> <bdf> <uuid> <model.bin> <mem-map.txt> <baseline.bin>
```

Board execute of those tuples was later reviewed as
`A18_3_BOARD_FUNCTION=PASS_FIVE_LOCKED_TUPLES` in
`docs/STAGE2N_A18_3_BOARD_FUNCTION_ACCEPTANCE_V1.md`. That is not implied
by A18.2 PASS or by Host compile PASS alone.

The A18.2 Linux extract does not contain these files until the overlay is
copied. From Windows PowerShell (not SSH):

```powershell
powershell -NoProfile -File handoff\copy_a18_3_host_overlay_v1.ps1
```

Then on Linux, compile only:

```bash
bash scripts/build_stage2n_a18_3_host_v1.sh
```

## Restrictions

- Do not modify A13, A14 v2, A16, A17 originals, or the A18.2 Host/xclbin
  identities.
- Do not run `v++`, program, or reset from the agent environment.
- Do not reuse slot-sensitivity tables with non-default indexes.
- Do not claim board PASS from software goldens.
- T>4, mapping algorithms, and cache stay out of scope.
