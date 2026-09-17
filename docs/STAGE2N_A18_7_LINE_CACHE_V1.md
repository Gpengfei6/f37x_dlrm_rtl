# Stage 2N-A18.7 — local one-line per-bank embedding cache

Date: 2026-09-17. Status: **LOCAL SOURCE + PYTHON CHECK PASS**.
XSim/Icarus: **NOT RUN**. `PERFORMANCE=NOT_CLAIMED`.
No program. No reset. Boarded A18 public kernel unchanged.

One-line cache in front of an accepted A14 v2 engine. A matching index
returns the stored 128-bit vector without an AXI AR. A miss forwards to
the engine and fills the line on a successful response. Hit/miss counts
saturate at `16'hFFFF`.

This is not a set-associative cache, not T>4 pooling, and not a board
result.

## Files

- `rtl/hbm/dlrm_hbm_bank_line_cache_stage2n_a18_7_v1.sv`
- `tb/tb_dlrm_hbm_bank_line_cache_stage2n_a18_7_v1.sv`
- `scripts/check/check_stage2n_a18_7_line_cache_v1.py`

```text
python scripts/check/check_stage2n_a18_7_line_cache_v1.py
```

## What this cannot prove

Physical HBM hit rate, bandwidth, latency improvement, or speedup.
The boarded A18 kernel does not instantiate this cache.
