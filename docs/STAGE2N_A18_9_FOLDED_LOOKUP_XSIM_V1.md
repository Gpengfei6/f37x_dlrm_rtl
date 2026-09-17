# Stage 2N-A18.9 — four-line cache, pairwise fold, local XSim

Date: 2026-09-17. Status: **LOCAL PYTHON GOLDEN PASS** and **local Vivado
2022.1 XSim PASS** for mapper / fold / 4-line cache / folded lookup.
Not 2020.2. Not FPGA. `PERFORMANCE=NOT_CLAIMED`.
No program. No reset. Boarded A18 kernel unchanged.

This slice does the work that does not need the user on the card:

1. Four-line FIFO cache (A18.7 was one line). After a cold ident group
   of unique rows 10–17, a second identical group issues **zero** extra
   ARs (`IDENT_WARM`).
2. Pairwise saturating INT16 fold: `slot[i] = sat_add(vec[i], vec[i+4])`.
   This is **not** an A13 numeric contract and is not a complete T=8 DLRM.
3. Local XSim at
   `D:\vivado2022\vivado2022forwins\Vivado\2022.1`.

## XSim (2022.1 only)

Runner: `scripts/run_stage2n_a18_9_local_xsim_v1.ps1`

| Test | Marker | Result |
|---|---|---|
| mapper | `TB_A18_5_MAPPER=PASS` | PASS `20260917_212709_334` |
| fold | `TB_A18_9_PAIR_FOLD=PASS` | PASS `20260917_212748_572` |
| cache4 | `TB_A18_9_LINE_CACHE=PASS` | PASS `20260917_212857_287` |
| folded | `TB_A18_9_FOLDED_LOOKUP=PASS` | PASS `20260917_213239_838` |

Folded cases: IDENT_COLD, IDENT_FOLD, IDENT_WARM, COACC_COLD, FORCE_COLD,
SAME_LINE_BANK0, OOB.

## Files

- `rtl/hbm/dlrm_hbm_bank_line_cache_stage2n_a18_9_v1.sv`
- `rtl/hbm/dlrm_t8_pair_fold_stage2n_a18_9_v1.sv`
- `rtl/hbm/dlrm_hbm_t8_folded_lookup_stage2n_a18_9_v1.sv`
- `tb/tb_dlrm_hbm_bank_line_cache_stage2n_a18_9_v1.sv`
- `tb/tb_dlrm_t8_pair_fold_stage2n_a18_9_v1.sv`
- `tb/tb_dlrm_hbm_t8_folded_lookup_stage2n_a18_9_v1.sv`
- `scripts/check/check_stage2n_a18_9_folded_lookup_v1.py`
- `scripts/run_stage2n_a18_9_local_xsim_v1.ps1`
- `scripts/run_stage2n_a18_9_local_xsim_v1.tcl`

## What this cannot prove

Physical HBM, 2020.2, XO/xclbin, extra-run, A13 DLRM goldens, or speedup.
Do not instantiate these modules in
`dlrm_f37x_rtl_kernel_stage2n_a18_v1` without a later program grant.

User-only remaining: extra-run on UUID `32a9c911-…` with the existing
no-program runner; any future xclbin/program.
