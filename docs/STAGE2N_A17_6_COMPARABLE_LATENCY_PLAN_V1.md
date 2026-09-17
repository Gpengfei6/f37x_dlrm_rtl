# Stage 2N-A17.6 — A16.2 / A17 comparable-latency plan V1

Date: 2026-09-10. Status: **PLAN CLOSED FOR N=11 COLLECTION. A17-N11 and
A16-N11 both accepted. Comparability reviewed; Class C still incomplete;
speedup not computed; A17 restore NOT authorized.**

Function re-check `20260910_122124` is closed. The A17 process-restart
campaign `20260910_141722` is accepted. This note does not program A16,
reset, rebuild, add A18, or claim speedup. Historical A16.2
`112/1174/1289/3` remains Class D. A17 lookup is a distribution (median 33;
measured tails 37/38/50/52/65; historical CASE4=55 kept). Class C still
needs a separately authorized A16 campaign. That campaign is now accepted
as `20260910_163902`. Side-by-side review:
`docs/STAGE2N_A16_A17_PROCESS_RESTART_COMPARABILITY_V1.md`. Class C is
still incomplete. Do not write a speedup.

## 0. Closed function / identity boundary

Accepted and frozen for this plan:

- A17 function, original archive, and this-run execution identity:
  `docs/evidence/stage2n_a17_6/identity_recheck_v1/ACCEPTANCE.txt`
- A17 run: `20260910_122124`
- No further function re-check or Host-identity investigation
- `20260910_102244` pre-exec hash stays missing; do not backfill
- `/proc` process-image hash is not required

New fact from that run: A17 lookup is **not** a single value `33`. CASE4
recorded `55/1174/1232/3`. Later work must keep a **distribution**. Do not
keep only one sample or the minimum. One CASE4=55 sample does not identify
data vs order vs runtime state. Do not drop it. Do not change RTL to chase
`33`.

## 1. Locked artifacts

Same five trained-model cases and goldens for both designs:

- model: `models/stage2n_a15_6/stage2n_a15_6_model_v1.bin`
- cases: `models/stage2n_a15_6/stage2n_a15_6_cases_v1.json`
- goldens: `-393, -392, -93, -689, -519`
- rows: 37, 38, 39, 40
- A13 regression: `322/100/744/1174` (delta 0 required)
- residual: `e2e - lookup - compute` (interval difference, not a stage)

| | A16.2 sequential (frozen) | A17.6 four-bank (accepted re-check) |
|---|---|---|
| Kernel / CU | `dlrm_f37x_rtl_kernel_stage2n_a16_v1` / `dlrm_a16_1` | `dlrm_f37x_rtl_kernel_stage2n_a17_v1` / `dlrm_a17_1` |
| xclbin SHA256 | `5f0d6fefab1549d2e1969df3d8775409bbfac33cb46d07e7abde99abdf04b8b4` | `b8d2034906451cc755b6c01a50c94a4b841998c3e2794c6e417dd1ab952e46ae` |
| UUID | `f18571de-4a43-46bd-8ab9-a89dd4b11f8e` | `622c839f-55f4-47c1-92e9-95ee5595ffa4` |
| Host ELF SHA256 | `de0abefc0b4dbadf74dd69e6875db9051a18ab34d8ab1a6a747073cb436d6f1b` | `9ba376589f56d99efca6e42328d347a6539ba1c40bba56d21ab690d87e7f20fc` |
| Host source SHA256 | `d2c4036bcaccba702d70fe772a436501568c593dd5b92bc08edb7d7502dafc99` | `7073b4d976e54f73887c21714a3a4d8bdf65cdf3a272e620fb54c09963ee55ce` |
| Mapping | one BO, `m_axi_gmem` → `HBM[0]` | four BOs, `m_axi_gmem0..3` → `HBM[0..3]` |
| Lookup work | four **sequential** reads, one master | four **parallel** engines, four masters |
| Counters | `0x30C` lookup, `0x310` e2e, A13 `0x218..0x224` | same offsets; A17 start = first AR on **any** of four masters |
| Requested clock | 100 MHz / 10.000 ns kernel | 100 MHz / 10.000 ns kernel |
| Historical one-shot | all five cases `112/1174/1289/3` | CASE0–3 and repeat `33/1174/1210/3`; CASE4 `55/1174/1232/3` |
| Process-restart N=11 | not collected in this slice | median lookup 33; tails 37/38/50/52/65; compute 1174 |

Do not run the A16 Host on the A17 xclbin, or the reverse. Do not deploy the
Windows third A17 Host source (`cffe9a6d…`). Do not rebuild either Host unless
a later authorization names a new labeled binary.

Device for both: index `2`, BDF `0000:9b:00.1`, render `/dev/dri/renderD129`,
XRT `2.9.210507`, one F37X card.

## 2. Counter boundaries (defined separately)

Do not say that all hardware counters start at START.

```text
S = accepted A15 START write at 0x300
A = first real AXI AR handshake after S
    A16: single m_axi_gmem
    A17: first AR on any of m_axi_gmem0..3
D = registered fourth-slot injection complete
C = accepted A13 compute START
F = first final result valid && last

e2e     starts at S, stops at F:  F - S + 1
lookup  starts at A, stops at D:  D - A + 1
compute starts at C, stops at F:  F - C + 1   (A13 total; expected 1174)
residual = e2e - lookup - compute
```

**Outside** lookup / e2e / compute:

- BO allocate, fill, `xclSyncBO` (and, in this slice, a new process each round)
- TABLE_BASE / BASE0–3 writes and readback
- descriptor / weight / bias / dense configuration
- start-ready poll before START
- Host poll for result after F, POP, CLEAR
- xclbin UUID check; programming is not part of this A17 slice

Host-visible wall time, if later added, is a separate column. It is not FPGA
e2e.

Comparison basis is an **equivalent task**, not “the counters have the same
name”: both designs read the same four embedding vectors (rows 37–40) and
run the same Bottom–Interaction–Top inference. Organization differs
(one sequential master vs four parallel masters). Named-counter values may
be placed side by side only after a later review confirms the S/A/D/C/F
boundaries still mean the same events on both tops. This A17-only slice
does not perform that cross-design check and does not compute a speedup.

Before each campaign, record from `xbutil query`: UUID, CU IDLE, firewall
GOOD, kernel clock if printed, and HBM occupancy. A17 needs `HBM[0..3]` empty;
A16.2 needs `HBM[0]` empty. Do not reset the card to clear occupancy.

## 3. Warmup, repeats, order

Pre-declared (not chosen after seeing numbers):

| Item | Value |
|---|---|
| Warmup | 1 full five-case sweep, logged as `WARMUP`, excluded from summary **by this rule** |
| Measured repeats | **N = 11** five-case sweeps per design |
| Case order A (default) | CASE0, CASE1, CASE2, CASE3, CASE4 |
| CLEAR | existing Host CLEAR between cases (already required) |
| Keep | every raw lookup, compute, e2e, residual, golden, mask |
| Drop | none, except the pre-declared warmup label |
| Summary | per case: n, min, median, max, and the full list |

Host-visible time, if later added, is summarized the same way and stored in
other columns.

Authorized first slice: 12 **process invocations** of the accepted A17 Host
(1 pre-declared warmup + 11 measured). Each invocation is a new process:
BO allocate / fill / sync happen again. This is **process-restart
repeatability**, not a continuously running steady-state measurement.
N=11 is enough for a first distribution look. It is **not** automatic
full performance acceptance.

Each Host run prints five formal cases plus a trailing `REPEAT_BASELINE`.
Summaries:

- CASE0..CASE4: 11 measured values each (warmup excluded)
- `REPEAT_BASELINE`: 11 measured values in a **separate** series
- Do **not** merge `REPEAT_BASELINE` into CASE0 (that would be 22 baseline
  samples)

Keep every valid observation, including lookup 55. Do not filter by value.
If function, identity, or cleanup fails, stop; keep the failed round; do
not extra-run to force n=11. Counter movement alone is not a failure.

## 4. Slot3 / 55-cycle follow-up (A17 only)

After order-A repeats, still on A17, without prejudging cause:

1. **Order B:** 1 warmup + 11 sweeps of CASE4, CASE0, CASE1, CASE2, CASE3
   (requires a versioned argument order or five single-case Host wraps;
   if only the current Host exists, approximate by 11 extra Host runs and
   **read CASE4 as the last case of order A**, plus 11 runs that execute
   **only** CASE4 if a later Host allows it).
2. Until a versioned Host exists, the authorized first slice is:
   - 12 full current-Host runs (order A, CASE4 last)
   - then, if a one-case mode is not available, **do not invent CASE4-only
     by editing the accepted ELF**; wait for a labeled Host
3. Report whether 55 **reappears**, the CASE4 list, and whether it follows
   CASE3. Do not name a root cause from one pattern. Do not delete 55.

A16.2 CASE4 historically was 112 with no repeats; the A16 campaign uses the
same N=11 so A16 also has a CASE4 distribution.

## 5. Two conclusion classes

**Class D — descriptive contrast (already allowed as history, not a
comparable result):**

- A16.2 board log `20260831_182443`: all five `112/1174/1289/3`
- A17 `20260910_122124`: CASE0–3 `33/1174/1210/3`, CASE4 `55/1174/1232/3`
- A17 process-restart `20260910_141722`: median lookup 33; measured tails
  CASE1=65, CASE2=52, CASE3=38, CASE4=37 and 50; REPEAT_BASELINE all 33.
  Historical CASE4=55 did not reappear in this CASE4 list and is still kept.

- A16 process-restart `20260910_163902`: lookup floor 112; CASE0 median
  114; CASE3 median 132; tails to 141; compute 1174. Historical all-112
  one-shot remains Class D and is not the whole A16 list.

This may be written as “historical one-shot values differed, and A17 lookup
is not a single 33.” It is **not** a same-condition performance conclusion
and **not** a speedup.

**Class C — comparable performance:**

The A16-N11 campaign now exists (`20260910_163902`) and a boundary
review is in
`docs/STAGE2N_A16_A17_PROCESS_RESTART_COMPARABILITY_V1.md`.
Class C is **still incomplete**: process-restart is not steady-state;
BO init differs; A16 has no `REPEAT_BASELINE`; n=11 is a first
distribution look. Do not write an A16/A17 speedup. Compute stayed 1174
on every passing case; lookup/e2e moved.

## 6. Program / xclbin switch

Resident image after `20260910_122124` was A17 UUID `622c839f-…`.
A16.2 UUID is `f18571de-…`. **They are different bitstreams.**

| Step | Program? |
|---|---|
| A17 distribution while UUID is still `622c839f-…` | No. Reuse `A17_6_FORCE_NO_PROGRAM=yes`. If UUID is not A17, **stop**. |
| A16.2 distribution | **Yes, `xbutil program` of the frozen A16.2 xclbin.** Allowlist the then-resident UUID (expected A17 `622c839f-…`) as the source image. Occupancy: `HBM[0]` empty. |
| Return to A17 after A16 | **Yes, another program** of link_004. Previous A17 `FORCE_NO_PROGRAM` does **not** cover this. |

`A17_6_FORCE_NO_PROGRAM=yes` from the function re-check does **not** authorize
an A16 program, an A17 re-program, or a reset. Each program needs a separate
user sentence naming the destination UUID.

Suggested order after authorization:

1. **A17-N11** on the currently loaded A17 image (no program if UUID matches).
2. Stop and review A17 distribution, including CASE4.
3. Separate authorization: program A16.2, **A16-N11**.
4. Separate authorization if A17 must be restored: program A17, optional
   A17-N11 repeat.

Steps 1–3 are done. Step 4 (A17 restore) is **not** authorized. The card
now holds A16 UUID `f18571de-4a43-46bd-8ab9-a89dd4b11f8e`.

Do not FPGA reset. Do not global HBM cleanup. Do not touch another device.

## 7. Out of scope

- model-size change, A18, bandwidth, power, energy, multi-card
- new verification frameworks or paper Results cells filled from Class D
- editing frozen A16.2 / accepted A17 RTL
- commit
- treating `33` vs `112` or `55` vs `33` as acceleration

## 8. Authorized A17 process-restart slice (this increment)

User-authorized, A17 only:

- 12 calls of the accepted Host through the identity-gated execute entry
- round 0 = warmup (logs kept, not in min/median/max)
- rounds 1–11 = measured
- ELF / source from
  `docs/evidence/stage2n_a17_6/identity_recheck_v1/ACCEPTANCE.txt`
- resident UUID must be `622c839f-55f4-47c1-92e9-95ee5595ffa4`
- `A17_6_FORCE_NO_PROGRAM=yes`; no program, reset, rebuild, or A16

A16 program and any later return to A17 remain unauthorized.

Accepted A17-N11 result:
`docs/evidence/stage2n_a17_6/repeatability_v1/ACCEPTANCE.txt`.
Do not extra-run this slice to chase 33. Do not merge REPEAT_BASELINE
into CASE0. Do not drop 55 from the 122124 record.

A16-N11 local preparation (executed and accepted):
`docs/STAGE2N_A16_2_PROCESS_RESTART_PREP_V1.md`.
Accepted A16-N11 result:
`docs/evidence/stage2n_a16_2/repeatability_v1/ACCEPTANCE.txt`.
Frozen A16 Host has no `REPEAT_BASELINE`. Lookup start A is first AR on
the single `m_axi_gmem`. Comparability review:
`docs/STAGE2N_A16_A17_PROCESS_RESTART_COMPARABILITY_V1.md`.
Do not compute speedup. A17 restore is not authorized.
