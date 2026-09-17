# Stage 2N-A18.8 — T=8 mapped lookup with per-bank one-line cache

Date: 2026-09-17. Status: **LOCAL SOURCE + PYTHON GOLDEN PASS**.
XSim/Icarus: **NOT RUN**. `PERFORMANCE=NOT_CLAIMED`.
No program. No reset. Boarded A18 public kernel unchanged.

Self-answer after GPT was unavailable: extra-run stays NOT_RUN (cannot
SSH; chasing lookup 33 is not T>4). “Into the kernel” remains the
kernel-side datapath, not a new xclbin. Frozen A13 stays four slots;
pooling is not this slice. The next slice is wiring the A18.7 line
cache in front of the four A14 v2 engines inside a versioned T=8
controller.

## Behavior

- Instantiates A18.5 mapper, four A18.7 caches, four A14 v2 engines.
- Cold unique indexes: AR count equals occupancy.
- Ident tables 0 and 4 both index 7: bank 0 AR count is 1 (second is hit).
- OOB index 64 issues no ARVALID.
- Cache lines persist across groups until rst; occupancy tests pulse rst.

## Files

- `rtl/hbm/dlrm_hbm_t8_cached_lookup_stage2n_a18_8_v1.sv`
- `tb/tb_dlrm_hbm_t8_cached_lookup_stage2n_a18_8_v1.sv`
- `scripts/check/check_stage2n_a18_8_cached_lookup_v1.py`

```text
python scripts/check/check_stage2n_a18_8_cached_lookup_v1.py
```

Python golden `SAME_LINE_BANK0_AR=1,2,2,2` and `HIT=1,0,0,0`.

## What this cannot prove

Physical hit rate, bandwidth, complete T=8 DLRM, XO/xclbin, extra-run,
or speedup. Do not instantiate this controller in
`dlrm_f37x_rtl_kernel_stage2n_a18_v1` without a later program grant.
