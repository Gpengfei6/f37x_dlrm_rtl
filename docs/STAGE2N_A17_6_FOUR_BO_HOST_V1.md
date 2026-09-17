# Stage 2N-A17.6 — four-BO Host and protected prepare flow

Date: 2026-09-10. Status: **FUNCTION CLOSED / 122124 EXECUTION IDENTITY PASS_THIS_RUN_ONLY / PERFORMANCE=NOT_CLAIMED**.
Fixed four-slot four-bank physical function is closed. Identity-gated
`20260910_122124` is the execution-identity run. No further function
re-check. CASE4 lookup 55 is recorded. Comparable latency is plan-only:
`docs/STAGE2N_A17_6_COMPARABLE_LATENCY_PLAN_V1.md`.

This is not a copy of the A16 Host with four allocations. Single-bank, single
address, single BO sync, and single release assumptions are replaced by a
metadata map and four independent BO objects.

## 1. GPT review adopted here

- Five functional cases, four fixed rows 37–40. Not “five rows”.
- Board goldens are the accepted A16.2/A15.6 values `-393,-392,-93,-689,-519`,
  locked from `models/stage2n_a15_6/stage2n_a15_6_cases_v1.json` and
  `docs/evidence/stage2n_a16_2/final_acceptance_v1/physical_latency_v1/20260831_182443/host.log`.
  Local XSim result 36 is a different fixture and is rejected as a board golden.
- Development complete ≠ allow program. Default runner action is `prepare`.
- A13 `322/100/744/1174` is a same-config regression expectation. The Host
  prints actual values and deltas; it does not print those numbers as if they
  were measured A17 lookup/e2e. A17 lookup/e2e/residual must be remeasured and
  are not required to match A16.2 `112/1289/3`.
- “Same 55 methodology warnings” is not equivalence. Content diff is prepared;
  it is `NOT_RUN` until the link_004 methodology report is supplied.
- Paper implementation cells may later cite xo_002/link_004. Physical four-bank
  reads, BO ownership, latency, and speedup stay empty. Patent remains paused.

## 2. Delivered files

| File | Role |
|---|---|
| `host/stage2n_a17_6_four_bo_host_v1.cpp` | Independent A17 Host |
| `scripts/parse_stage2n_a17_6_xclbin_map_v1.py` | CONNECTIVITY/MEM_TOPOLOGY → mem map |
| `scripts/build_stage2n_a17_6_host_v1.sh` | Target XRT 2020.2 compile only |
| `scripts/run_stage2n_a17_6_protected_board_v1.sh` | Default `prepare`; `execute` triple-gated |
| `scripts/check/check_stage2n_a17_6_host_prep_v1.py` | Local golden/source gate |
| `scripts/test_stage2n_a17_6_host_v1.py` | Map fixtures and Host audits |
| `scripts/diff_stage2n_a17_6_methodology_v1.py` | Warning content diff |
| `docs/STAGE2N_A17_6_LUTLP_HANDSHAKE_COVERAGE_V1.md` | LUTLP TB coverage |
| `docs/evidence/stage2n_a17_6/stale_artifacts_v1.txt` | xo_001 superseded |

Unchanged: accepted A13/A14/A16 RTL and Host, A17 public kernel file, A15.6
model assets, A16.2 evidence.

## 3. Host behavior

HAL remains `xclOpen` / `xclIPName2Index` / `xclOpenContext` /
`xclRegWrite` / `xclRegRead`. CU is
`dlrm_f37x_rtl_kernel_stage2n_a17_v1:dlrm_a17_1`. Version `0x00024E17`.
A16 CU/xclbin identity is rejected.

Memory indices are parsed from dumped xclbin JSON by tag `HBM[0..3]`. They are
not assumed to be 0–3. Each argument gets its own BO, fill, `xclSyncBO`,
paddr, BASE write, and BASE readback:

```
BO0 → BASE0 0x304/0x308 → m_axi_gmem0 → HBM[0]
BO1 → BASE1 0x318/0x31C → m_axi_gmem1 → HBM[1]
BO2 → BASE2 0x320/0x324 → m_axi_gmem2 → HBM[2]
BO3 → BASE3 0x328/0x32C → m_axi_gmem3 → HBM[3]
```

`paddr==0` is legal if 16-byte aligned. Requested size 1024 and
`properties.size` are both printed. START is issued only after all four syncs
and all four BASE readbacks. CLEAR is required between cases; baseline is
repeated after the five functional cases.

Per-BO layout: every case first restores the baseline image onto all four
BOs. Baseline may keep the same table on every bank. Slot-i sensitivity then
overlays the mutated table onto **BO i only**; BOs `j != i` remain baseline.
Port i reads row 37+i from BO i, so mutating BO i’s row 37+i is the only
legal sensitivity write. CLEAR plus a full restore happens before every case
and before the repeated baseline, so a prior case cannot remain on another
bank. Goldens stay A15.6/A16.2 `-393,-392,-93,-689,-519`. This is not a
storage-optimization claim.

## 4. Physical acceptance from `20260910_102244`

The pasted Host log meets this function rule. Evidence summary:
`docs/evidence/stage2n_a17_6/first_function_host_pass_v1.txt`.

“A17 fixed four-slot four-bank physical function PASS” requires all of:

1. Loaded artifact is xo_002 → link_004 (SHA
   `b8d2034906451cc755b6c01a50c94a4b841998c3e2794c6e417dd1ab952e46ae`, UUID
   `622c839f-55f4-47c1-92e9-95ee5595ffa4`) on the guarded device.
2. Four distinct BOs, four distinct metadata memory indices, tags HBM[0..3].
3. BASE0–3 readback equals each BO paddr; sync completed before START.
4. Five results match the locked goldens; each slot-sensitivity case differs
   from baseline, proving all four data paths participate.
5. Repeat baseline after CLEAR does not reuse a stale result, address, or
   payload.
6. A13 counters are read and reported; mismatch versus 322/100/744/1174 fails.
   A17 lookup/e2e/residual are recorded, not compared to 112/1289/3.

BO allocation or BASE readback alone is not physical-read success.

## 5. Protected runner

```
bash scripts/run_stage2n_a17_6_protected_board_v1.sh prepare
```

Prepare checks sources and goldens. Optional `A17_6_BUILD_HOST=yes` compiles
the Host and still sets `HOST_EXECUTION=NOT_RUN`. `execute` requires all of
`A17_6_BOARD_EXECUTION_AUTHORIZED=yes`, `A17_6_ALLOW_PROGRAM=yes`, and
`A17_6_CONFIRM=yes`. This increment does not set those variables.

Stale XO `a17_6_xo_001` SHA `1bd10d1f…` is labelled
`SUPERSEDED_NOT_FOR_EXECUTION`.

## 6. Local commands and target compile (no program)

Local:

```
python3 scripts/check/check_stage2n_a17_6_host_prep_v1.py
python3 scripts/test_stage2n_a17_6_host_v1.py
python3 scripts/diff_stage2n_a17_6_methodology_v1.py --self-test
```

`prepare` plus `A17_6_BUILD_HOST=yes` is file checks and `g++` only. It does
not execute the Host, does not call `xbutil`, does not open a device, and
does not load an xclbin. Unset `A17_6_XCLBIN` for this compile.

The existing target tree `f37x_dlrm_rtl_stage2n_a17_6_buildonly` is the
XO/link source closure. It does **not** contain the four-BO Host or the
prepare/compile scripts. Overlay
`handoff/stage2n_a17_6_host_overlay_v1.zip` (SHA256
`a3f6a43f3572a97c0c27e47f8d43678b17e0540859b238af2e01113e7138b551`)
into that tree first, then:

```bash
cd /home/chaosuan/gpf/gpf_f37x_dlrm/f37x_dlrm_rtl_stage2n_a17_6_buildonly
source /opt/xilinx/xrt/setup.sh
export A17_6_ALLOW_HOST_REBUILD=yes
export A17_6_BUILD_HOST=yes
unset A17_6_XCLBIN A17_6_BOARD_EXECUTION_AUTHORIZED A17_6_ALLOW_PROGRAM A17_6_CONFIRM
bash scripts/run_stage2n_a17_6_protected_board_v1.sh prepare
```

If the overlay lacks A16.2 evidence, compile-only is still valid:

```bash
A17_6_ALLOW_HOST_REBUILD=yes bash scripts/build_stage2n_a17_6_host_v1.sh
```

Return `host_build.log`, `compiler_version.log`, `xrt_version.log`,
`host_build_status.txt`, and the ELF. PASS requires compiler exit 0, ELF
magic, non-zero size, and recorded SHA256 of source and ELF. File existence
alone is not PASS.

The methodology report is in the link run directory on the target, not under
`docs/evidence` there. After overlay, optional on-target check:

```bash
ls -l runs/a17_6_link_004/post_route/post_route_methodology.rpt
python3 scripts/diff_stage2n_a17_6_methodology_v1.py \
  --candidate runs/a17_6_link_004/post_route/post_route_methodology.rpt \
  --output docs/evidence/stage2n_a17_6/methodology_diff_status.txt
```

Copy the `.rpt` back to the Windows worktree as
`docs/evidence/stage2n_a17_6/link_004_post_route_methodology.rpt` so the
same diff can be re-run locally. Equal count 55 is not equivalence.

## 7. Explicitly not done

- A18 table layout, cache, prefetch, INT8, multi-card
- model-size change or A13 compute-path edit
- redefining timing boundaries to chase numbers
- Class C comparable A16/A17 repeats, four-bank acceleration, or treating
  33 vs 112 as a paper performance number. A17 process-restart N=11 is a
  separate accepted slice, not Class C.
