# Stage 2N-A18.10 — folded T=8 inject handshake and software A13 goldens

Local slice only. **Python goldens PASS. Local Vivado 2022.1 XSim PASS.**
Not 2020.2. Not FPGA. Not extra-run. `PERFORMANCE=NOT_CLAIMED`.

## What this proves

1. Pairwise INT16 sat-add fold of eight baseline-table rows, then the
   frozen A15.6 A13 numeric path, as software goldens. Those finals are
   **not** A18.3 board goldens. T=4 rows 37–40 on the same assets remain
   `-393`. Fold of `(37,38,39,40,0,0,0,0)` is `-223`.
2. Versioned injector `dlrm_hbm_t8_folded_inject_stage2n_a18_10_v1`
   wraps A18.9 and presents an A13-style `cfg_valid/cfg_ready/cfg_index/cfg_data`
   handshake for the four folded slots. Backpressure holds slot 0.
   OOB issues no CFG write.
3. The boarded public kernel `dlrm_f37x_rtl_kernel_stage2n_a18_v1` is
   **not** instantiated and **not** edited.

## What this does not prove

- Complete T=8 DLRM in RTL (A13 is not instantiated here).
- Physical HBM, XO, xclbin, extra-run, 2020.2, bandwidth, or speedup.

## Evidence

| Check | Marker | Status |
|---|---|---|
| software goldens | `A18_10_T8_FOLD_A13_GOLDEN=PASS` | PASS |
| source checker | `A18_10_FOLDED_INJECT_CHECK=PASS` | PASS |
| XSim inject | `TB_A18_10_FOLDED_INJECT=PASS` | PASS `20260917_215414_769` |

Locked software finals (baseline table, fold then A13):

| name | indexes | final |
|---|---|---|
| unique_0_7 | 0..7 | -333 |
| default_ext_37_44 | 37..44 | -480 |
| doubled_37_40 | 37..40 twice | -774 |
| zeros | eight zeros | -318 |
| mixed_1_4_10_13 | 1,2,3,4,10,11,12,13 | -289 |
| high_63_56 | 63..56 | -299 |
| default_plus_zeros | 37..40 plus zeros | -223 |

JSON: `analysis/stage2n_a18_10/t8_fold_a13_goldens_v1.json`.

## Files

- `rtl/hbm/dlrm_hbm_t8_folded_inject_stage2n_a18_10_v1.sv`
- `tb/tb_dlrm_hbm_t8_folded_inject_stage2n_a18_10_v1.sv`
- `python/eval_stage2n_a18_10_t8_fold_golden_v1.py`
- `scripts/check/check_stage2n_a18_10_folded_inject_v1.py`
- `scripts/run_stage2n_a18_10_local_xsim_v1.ps1`
- `scripts/run_stage2n_a18_10_local_xsim_v1.tcl`

## Commands

```
python scripts/check/check_stage2n_a18_10_folded_inject_v1.py
powershell -File scripts/run_stage2n_a18_10_local_xsim_v1.ps1
```
