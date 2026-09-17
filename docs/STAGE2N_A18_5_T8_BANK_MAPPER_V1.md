# Stage 2N-A18.5 — local T=8 / B=4 kernel-side bank mapper

Date: 2026-09-17. Status: **LOCAL SOURCE + PYTHON CHECK PASS**.
XSim/Icarus: **NOT RUN** (no simulator on this Windows path).
`PERFORMANCE=NOT_CLAIMED`. No program. No reset. No extra-run. No cache.

User authorized T>4 RTL, placement/co-access into kernel-side logic,
extra-run, and cache, with **no FPGA reset and no reprogramming**.
This increment is only the first slice: a combinational mapper. The
boarded A18 kernel is unchanged. Cache and extra-run are not in this
slice. Extra-run of A18.3 would not exercise T>4.

## Frozen compute boundary

A13 still has four embedding slots. T>4 here means **eight logical
tables mapped onto four HBM banks**, not eight embeddings into the
frozen MLP. Complete T=8 DLRM arithmetic is not claimed.

## Mappings

| `mapping_sel` | Banks `t0..t7` | Occupancy |
|---|---|---|
| 0 ident | 0,1,2,3,0,1,2,3 | `[2,2,2,2]` |
| 1 coacc-split | 0,1,2,3,1,2,2,3 | `[1,2,3,2]` |
| 2 force 0/1→bank0 | 0,0,2,3,0,1,2,3 | `[3,1,2,2]` (A18.4 E5) |

Ident keeps co-occurring pairs `(0,4)` and `(1,5)` on the same bank.
Coacc-split moves the pair seconds to `bank+1`. That is a kernel-side
split mapper, not the L1 same-row-index pattern.

## Files

- `rtl/hbm/dlrm_table_bank_mapper_stage2n_a18_5_v1.sv`
- `tb/tb_dlrm_table_bank_mapper_stage2n_a18_5_v1.sv`
- `scripts/check/check_stage2n_a18_5_mapper_v1.py`

```text
python scripts/check/check_stage2n_a18_5_mapper_v1.py
```

## What this cannot prove

Physical HBM, AXI waves, A13 numeric change, cache, extra-run,
XO/xclbin, or speedup. Do not instantiate this mapper in the boarded
A18 top without a new versioned kernel and a later program
authorization.
