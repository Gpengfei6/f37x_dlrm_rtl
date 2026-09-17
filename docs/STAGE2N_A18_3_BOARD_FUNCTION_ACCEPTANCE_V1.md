# Stage 2N-A18.3 — five locked index tuples, board function accepted

Date: 2026-09-17.
Status: **BOARD FUNCTION PASS** for the five locked tuples on the
accepted A18 xclbin. Originals archived under
`docs/evidence/stage2n_a18_3/function_pass_v1/20260917_202130/`.

`A18_3_ORIGINAL_EVIDENCE_ARCHIVE=PASS`.
`PERFORMANCE=NOT_CLAIMED`. Do not write an A16/A17/A18 speedup.

## What passed

One protected Host execute `20260917_202130` on device index 2 /
BDF `0000:9b:00.1` / `renderD129`. The card already held UUID
`32a9c911-af15-47fc-90c8-0bfe3894a3ef`, so program was
`SKIPPED_ALREADY_LOADED`. The A18.2 five-case Host was not used.
All four BOs received the baseline 1024-byte table.

| Tuple | Indexes | Result |
|---|---|---|
| 0 | 37,38,39,40 | -393 |
| 1 | 1,2,3,4 | -61 |
| 2 | 0,0,0,0 | -60 |
| 3 | 0,63,37,40 | -162 |
| 4 | 63,62,61,60 | -185 |

Compute stayed `322/100/744/1174`. Mask `0xF`. PIPE_VERSION
`0x00024e18`. Recorded lookup 33 / e2e 1210 / overhead 3 on all
five tuples; that is not a speedup.

Host ELF `011a0b8f…`, source `f5168960…`, xclbin SHA `bbb0fa1f…`.
Indexes remain MMIO `0x330-0x33C`, not kernel arguments.

## What this does not prove

OOB index 64, T>4, placement algorithms, cache, A17 restore,
extra-run, Host process hash, bandwidth, latency improvement, or
Class C comparable performance.

Do not extra-run. Do not program. Do not reset.
