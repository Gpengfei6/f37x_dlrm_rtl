# Stage 2N-A18.3 — local non-default index Host preparation

Date: 2026-09-17. Status: **local preparation**. No new xclbin, no board
execute, no edit of the accepted A18.2 Host.

`A18_3_TARGET_XO=NOT_RUN` (reuse A18.2 xclbin if a later board run is
authorized). `A18_3_BOARD=NOT_RUN`. `PERFORMANCE=NOT_CLAIMED`.

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
- `scripts/check/check_stage2n_a18_3_local_prep_v1.py` — static gates:
  extras JSON present, A18.2 Host lock intact, A18 kernel still has
  `0x330-0x33C`, no A18.2 Host edit.
- AGENTS.md A18.3 authorization.

The C++ Host itself is **not** in this increment. Implementing it is the
next local coding step after this GitHub snapshot. Board execute of those
tuples needs a later user sentence plus a versioned runner; it is not
implied by A18.2 PASS.

## Restrictions

- Do not modify A13, A14 v2, A16, A17 originals, or the A18.2 Host/xclbin
  identities.
- Do not run `v++`, program, or reset from the agent environment.
- Do not reuse slot-sensitivity tables with non-default indexes.
- Do not claim board PASS from software goldens.
- T>4, mapping algorithms, and cache stay out of scope.
