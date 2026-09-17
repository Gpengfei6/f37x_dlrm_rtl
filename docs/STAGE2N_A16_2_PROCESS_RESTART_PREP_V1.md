# Stage 2N-A16.2 — process-restart repeatability preparation V1

Date: 2026-09-10. Status: **A16-N11 ACCEPTED as PASS_PROCESS_RESTART_SLICE.
See `docs/evidence/stage2n_a16_2/repeatability_v1/ACCEPTANCE.txt`.
A17 restore remains NOT authorized.**

A17 process-restart campaign `20260910_141722` is frozen. This note prepares
the same-caliber A16.2 measurement. It does not program the card, rebuild a
Host, edit frozen RTL, or compute an A16/A17 speedup.

## 0. Locked A17 result (do not reopen)

`docs/evidence/stage2n_a17_6/repeatability_v1/ACCEPTANCE.txt`

- five main cases: lookup median 33; measured tails 37–65
- compute 1174 on every sample; e2e moved with lookup; residual 3
- fluctuation is not CASE4-only
- n=11 is for raw lists and min/median/max, not a high percentile
- do not change RTL to chase 65

## 1. Frozen A16.2 artifacts (reuse, do not rebuild)

| Item | Frozen value |
|---|---|
| Kernel / CU | `dlrm_f37x_rtl_kernel_stage2n_a16_v1` / `dlrm_a16_1` |
| xclbin SHA256 | `5f0d6fefab1549d2e1969df3d8775409bbfac33cb46d07e7abde99abdf04b8b4` |
| UUID | `f18571de-4a43-46bd-8ab9-a89dd4b11f8e` |
| Host ELF SHA256 | `de0abefc0b4dbadf74dd69e6875db9051a18ab34d8ab1a6a747073cb436d6f1b` |
| Host source SHA256 | `d2c4036bcaccba702d70fe772a436501568c593dd5b92bc08edb7d7502dafc99` |
| Target Host tree | `/home/chaosuan/gpf/gpf_f37x_dlrm/f37x_dlrm_rtl_stage2n_a16_2_buildonly` |
| Protected execute | `scripts/program_and_run_stage2n_a16_2_physical_latency_v1.sh` |
| Device | index `2`, BDF `0000:9b:00.1`, render `/dev/dri/renderD129` |

Do not run the A16 Host on the A17 xclbin. Do not run this campaign from the
A17.6 overlay tree.

## 2. Case-order and Host-print audit

Same five trained-model cases, same order A, same goldens:

`baseline`, `slot0_sensitivity`, `slot1_sensitivity`, `slot2_sensitivity`,
`slot3_sensitivity` → `-393, -392, -93, -689, -519`.

Rows 37–40. A13 regression 322/100/744/1174. CLEAR after each case. START at
`0x300`.

Recorded differences (do not edit the frozen A16 Host to hide them):

| Item | Frozen A16.2 Host | Accepted A17.6 Host |
|---|---|---|
| Formal cases | CASE0–CASE4 only | CASE0–CASE4 |
| In-process sixth baseline | **absent** | `REPEAT_BASELINE` after CASE4 |
| BO / image | one `HBM[0]` BO; reload full 1024-byte image each case | four BOs; restore baseline, mutate owned slot only |
| Log lookup key | `CASE0_HBM_LOOKUP_CYCLES` | `CASE0_HBM_LOOKUP_CYCLES_ACTUAL` |
| Log compute/e2e keys | `COMPUTE_TOTAL_CYCLES` / `FPGA_END_TO_END_CYCLES` | same names plus `_ACTUAL` |
| PIPE_VERSION | `0x00024E13` | `0x00024E17` |

Comparable series after both campaigns: **CASE0–CASE4, n=11 each**. Do not
invent an A16 `REPEAT_BASELINE` by editing the frozen ELF. A17
`REPEAT_BASELINE` stays an A17-only extra column.

## 3. Counter-boundary audit

Inclusive algebra is the same on both tops:

```text
S = accepted A15 START write at 0x300
A = first real AXI AR handshake after S
D = registered fourth-slot injection complete
C = accepted A13 compute START
F = first final result valid && last

e2e     = F - S + 1     (0x310)
lookup  = D - A + 1     (0x30C)
compute = F - C + 1     (A13 0x224, expected 1174)
residual = e2e - lookup - compute
```

Recorded difference at **A** only:

- A16: `m_axi_gmem_arvalid && m_axi_gmem_arready` (one sequential master)
- A17: first AR on **any** of `m_axi_gmem0..3`

S, C, F, and “D = fourth-slot injection” are the same named events. Named
counters may be placed side by side only after the later comparability
review. This preparation does not declare them equivalent and does not
compute a speedup.

## 4. Same-caliber campaign rules

- 1 warmup + 11 measured **process** invocations of the frozen A16 Host
- warmup excluded from min/median/max by this rule
- CASE0–CASE4 summarized separately; no A16 REPEAT_BASELINE column
- keep every valid lookup/e2e value; do not filter
- function / identity / cleanup fail → stop; keep the failed round; do not
  extra-run to force n=11
- not steady-state; n=11 is a first distribution look, not a high percentile

Switching images **requires** `xbutil program` of UUID `f18571de-…`. Resident
image after A17 work is `622c839f-…`. Prior A17 `FORCE_NO_PROGRAM` does not
cover this. Occupancy needed: `HBM[0]` empty. No FPGA reset.

## 5. Protected execute (user-operated; Cursor does not connect)

User authorization 2026-09-10 names destination UUID
`f18571de-4a43-46bd-8ab9-a89dd4b11f8e` and allows one necessary program of
that frozen A16.2 xclbin. Returning to A17 is **not** authorized.

The campaign wrapper calls the frozen runner
`scripts/program_and_run_stage2n_a16_2_physical_latency_v1.sh`
(SHA256 `8370ec2f6128243a5f15e7a83a8c0c432b2cde6bf959504769d71323dc31c3ba`).
It does not call `xbutil program` itself. Identity trio plus the frozen
execute SHA are checked before the first inner call. Host is not rebuilt.

Comparable series: CASE0–CASE4, n=11. No A16 `REPEAT_BASELINE`. BO
condition remains: one `HBM[0]` BO, full image reload each case.

Fail-stop: identity, function, or cleanup failure keeps the failed round.
No reset, no extra-run, no A17 restore program.

Codex does not SSH. The user runs copy and execute from the A16.2
buildonly tree. After originals return, review A16 distribution and then
comparability versus A17-N11. No speedup until that review.

Windows copy and Linux execute stay in separate terminals. Do not paste
`powershell` into the SSH session. The frozen xclbin is
`build/stage2n_a16_2/link_v1/hw/dlrm_f37x_rtl_kernel_stage2n_a16_v1.xclbin`;
do not export `build/stage2n_a16_v1/hw/...`. The wrapper treats the frozen
execute as present when the file exists and SHA256 matches
`8370ec2f6128243a5f15e7a83a8c0c432b2cde6bf959504769d71323dc31c3ba`; it
invokes that file with `bash` and does not require the execute bit. If
that file is absent on the A16 overlay, recopy from Windows with
`handoff/copy_a16_2_repeatability_runner.ps1`; do not chmod or patch the
frozen runner.
