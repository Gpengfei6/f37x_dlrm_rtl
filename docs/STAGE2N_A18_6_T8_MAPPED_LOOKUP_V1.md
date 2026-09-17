# Stage 2N-A18.6 — local T=8 mapped lookup (mapper in the datapath)

Date: 2026-09-17. Status: **LOCAL SOURCE + PYTHON CHECK PASS**.
XSim/Icarus: **NOT RUN**. `PERFORMANCE=NOT_CLAIMED`.
No program. No reset. Boarded A18 public kernel unchanged.

This is the kernel-side placement slice: the A18.5 mapper is instantiated
inside a versioned T=8 lookup controller. Eight logical tables share the
four accepted A14 v2 engines according to `mapping_sel`. Frozen A13 still
has four embedding slots, so this controller does **not** run complete
T=8 DLRM arithmetic and is **not** wired into
`dlrm_f37x_rtl_kernel_stage2n_a18_v1`.

## Behavior

- Ident / coacc-split / force-01 occupancy matches A18.5.
- One outstanding transaction per bank (A14 v2). Occupancy 3 means three
  sequential reads on that master.
- Address remains `BASE[bank] + (index << 4)`.
- Any index `>= 64` raises error and issues no ARVALID.
- Independent TB cases IDENT, COACC_SPLIT, FORCE_01, and OOB.

## Files

- `rtl/hbm/dlrm_hbm_t8_mapped_lookup_stage2n_a18_6_v1.sv`
- `tb/tb_dlrm_hbm_t8_mapped_lookup_stage2n_a18_6_v1.sv`
- `scripts/check/check_stage2n_a18_6_t8_lookup_v1.py`

```text
python scripts/check/check_stage2n_a18_6_t8_lookup_v1.py
```

## What this cannot prove

Physical HBM, XO/xclbin, A13 numeric change, cache integration, extra-run,
or speedup. Do not instantiate this controller in the boarded A18 top
without a new versioned kernel and a later program authorization.
