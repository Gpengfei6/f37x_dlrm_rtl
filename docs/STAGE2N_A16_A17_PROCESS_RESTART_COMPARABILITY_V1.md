# A16-N11 / A17-N11 process-restart comparability V1

Date: 2026-09-10. Status: **REVIEW. Both campaigns accepted.
PERFORMANCE=NOT_CLAIMED. A16_A17_SPEEDUP=NOT_COMPUTED.
CLASS_C_COMPARABLE=NOT_COMPLETE. A17 restore NOT authorized.**

Archives:

- A16: `docs/evidence/stage2n_a16_2/repeatability_v1/ACCEPTANCE.txt`
  campaign `20260910_163902`
- A17: `docs/evidence/stage2n_a17_6/repeatability_v1/ACCEPTANCE.txt`
  campaign `20260910_141722`

This note places the two process-restart CASE0–CASE4 n=11 series next to
each other. It does not compute a speedup, does not fill paper Results,
and does not authorize programming A17 back onto the card.

## 1. Same-task facts that do match

Both campaigns:

- same trained-model cases and goldens `-393, -392, -93, -689, -519`
- same rows 37, 38, 39, 40
- same A13 compute `322/100/744/1174` (delta 0)
- same residual algebra `e2e - lookup - compute = 3` on every printed case
- same requested 100 MHz kernel clock
- same device index `2`, BDF `0000:9b:00.1`, render `/dev/dri/renderD129`
- same kind: 1 warmup + 11 measured **process restarts**, order CASE0–CASE4
- warmup kept on disk and excluded from min/median/max
- every valid lookup kept, including tails
- `PERFORMANCE=NOT_CLAIMED`

Counter events used for both:

```text
S = START write at 0x300
A = first real AXI AR after S
D = registered fourth-slot injection complete
C = accepted A13 compute START
F = first final result valid && last

e2e    = F - S + 1
lookup = D - A + 1
compute = F - C + 1   (always 1174 here)
residual = e2e - lookup - compute   (always 3 here)
```

When compute and residual match, any e2e difference equals the lookup
difference. That is interval arithmetic, not a speedup.

## 2. Condition differences that stay in the record

Do not hide these when writing later text:

| Item | A16.2 | A17.6 |
|---|---|---|
| Lookup organization | four sequential reads, one `m_axi_gmem` | four parallel engines, four masters |
| Lookup start A | first AR on the single master | first AR on **any** of four masters |
| BO init | one `HBM[0]` BO; reload the full image each case | four BOs; restore baseline then mutate the owned slot |
| In-process `REPEAT_BASELINE` | **absent** on the frozen A16 Host | present; summarized as a **separate** series, not merged into CASE0 |
| Log keys | `CASE0_HBM_LOOKUP_CYCLES` | `CASE0_HBM_LOOKUP_CYCLES_ACTUAL` |
| Programming in the campaign | warmup programmed A17→A16 once | none (`SKIPPED_ALREADY_LOADED`) |

These differences are why Class C remains incomplete. The two series are
the same **task** (four embeddings + Bottom–Interaction–Top) under the
same **process-restart protocol**, not the same BO/host experiment.

## 3. Measured lookup min/median/max (warmup excluded)

| Series | A16 lookup | A17 lookup | A16 e2e | A17 e2e |
|---|---|---|---|---|
| CASE0 | 112/114/141 | 33/33/33 | 1289/1291/1318 | 1210/1210/1210 |
| CASE1 | 112/112/140 | 33/33/65 | 1289/1289/1317 | 1210/1210/1242 |
| CASE2 | 112/112/140 | 33/33/52 | 1289/1289/1317 | 1210/1210/1229 |
| CASE3 | 112/132/141 | 33/33/38 | 1289/1309/1318 | 1210/1210/1215 |
| CASE4 | 112/112/138 | 33/33/50 | 1289/1289/1315 | 1210/1210/1227 |
| REPEAT_BASELINE | absent | 33/33/33 | absent | 1210/1210/1210 |

Compute is 1174/1174/1174 on every series of both campaigns.

A16 floor/mode is 112. Historical one-shot `20260831_182443` all-five
`112/1174/1289/3` sits on that floor; it is not the whole A16
distribution. A16 CASE3 median is 132.

A17 median is 33. Keep A17 tails 37/38/50/52/65 and historical
`20260910_122124` CASE4=55.

Do not treat 112 or 33 as the only lookup value. Do not change RTL to
chase either number.

## 4. What this review does **not** conclude

- Not Class C comparable performance.
- Not a speedup. Do not write `112/33` or `1289/1210` as acceleration.
- Not steady-state. Each round is a new process and a new BO fill.
- Not a paper Results cell.
- Not an A17 restore.

A later Class C claim would still need: a named decision that the BO-init
and REPEAT_BASELINE differences are acceptable for the claim being made,
and that n=11 process-restart is the intended protocol. This review does
not make that decision.

## 5. Board state after A16-N11

Resident image after the campaign is A16 UUID
`f18571de-4a43-46bd-8ab9-a89dd4b11f8e`. Returning to A17 UUID
`622c839f-55f4-47c1-92e9-95ee5595ffa4` needs a separate user sentence
and `xbutil program`. It is not authorized here.
