# Stage 2N-A18.4 — L1 E2/E4/E5 geometry lock

Date: 2026-09-17. Status: **LOCAL GEOMETRY LOCK**. Not FPGA. Not a
placement algorithm. `PERFORMANCE=NOT_CLAIMED`.

After A18.3 boarded five T=4 MMIO index tuples, the documented next
local step is L1 collision/occupancy counting for E2/E4/E5. This lock
records those summaries from
`analysis/stage2n_a18_l1/workload_analyzer.py`. Occupancy is **by
construction** from `T`, `B=4`, and `table_id % 4`.

## Locked cells

| Id | Matrix | Result (geometry) |
|---|---|---|
| E2_T8_STRIPE_UNIFORM | E2 T=8 | occupancy `[2,2,2,2]`; conflict_sum `32` over 8 rounds |
| E2_T16_STRIPE_UNIFORM | E2 T=16 | occupancy `[4,4,4,4]` |
| E4_T8_STRIPE_SAME_ROW_INDEX | E4 stand-in | same numeric row index on pairs `(0,4)` and `(1,5)`; occupancy still `[2,2,2,2]` |
| E5_T8_FORCE_01_BANK0 | E5 | occupancy `[3,1,2,2]`; no idle channel |

`ident` and `rr` remain the same stripe. There is **no** co-occurrence
mapping implementation; E4 here is the existing same-row-index pattern.

## How to refresh

```text
python scripts/run_stage2n_a18_4_l1_geometry_lock_v1.py --write
python scripts/run_stage2n_a18_4_l1_geometry_lock_v1.py
```

The second command fails if the JSON drifted.

## What this cannot prove

Physical HBM, AXI interconnect, T>4 RTL, cache, speedup, or that a
mapping algorithm should enter the FPGA. Silicon remains T=4 with
MMIO indexes on the accepted A18 xclbin.
