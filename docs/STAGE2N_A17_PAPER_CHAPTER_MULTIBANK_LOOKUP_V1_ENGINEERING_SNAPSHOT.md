# Multi-bank-capable Embedding Lookup Architecture

Draft date: 2026-09-08. Status: **engineering-summary snapshot**.

This file recovers Cursor’s first paper-chapter draft after the path
`docs/STAGE2N_A17_PAPER_CHAPTER_MULTIBANK_LOOKUP_V1.md` was later overwritten
by an academic refinement. It is **not** the current V1 working text. It was
never committed. Use it only as a historical engineering record.

Current files:

- V1 working text (academic refinement):
  `docs/STAGE2N_A17_PAPER_CHAPTER_MULTIBANK_LOOKUP_V1.md`
- V2 methodology chapter (independent Cursor file):
  `docs/STAGE2N_A17_PAPER_CHAPTER_MULTIBANK_LOOKUP_V2.md`
- V3 paper-integrated draft:
  `docs/STAGE2N_A17_PAPER_CHAPTER_MULTIBANK_LOOKUP_V3.md`

---

# Original Cursor V1 (engineering summary)

Draft date: 2026-09-08. Status: **paper chapter draft**. Not a physical
multi-bank result and not an A18 implementation.

This draft is meant to drop into a thesis or paper as an Architecture /
Verification section. Numbers that are accepted on F37X are labeled as such.
Empty physical A17 cells stay empty.

Allowed claim: A17 establishes a multi-bank-capable FPGA embedding-lookup
architecture and a layered verification framework against an accepted
single-bank sequential baseline.

Forbidden claim until an authorized A17.6 board run meets the execution gate:
multi-bank HBM acceleration.

## 1. Motivation

Recommendation inference on DLRM splits into two coupled costs. Sparse
embedding lookup is memory-oriented: several short vectors must be read from
HBM before Feature Interaction and Top MLP can start. Dense Bottom / Top MLP
is compute-oriented: the accepted A13 engine still dominates the FPGA-visible
interval.

The accepted Stage 2N-A16.2 physical baseline makes that split quantitative on
one F37X card, one AXI master, and one `HBM[0]` bank at 100 MHz:

- lookup (first AR through four-slot injection) = 112 cycles;
- compute (A13 Bottom + Interaction + Top) = 1174 cycles;
- FPGA end-to-end (accepted START through first result) = 1289 cycles;
- residual = 3 cycles.

Lookup is about 8.7% of FPGA e2e; compute is about 91%. A sequential four-row
read through one master therefore cannot be the whole performance story, but
it *is* the part that a multi-bank datapath can attack without changing the
frozen dense arithmetic.

A17’s engineering goal is therefore narrower than “make DLRM faster.” It is
to expose four independent AXI read masters, gather four embedding rows
without a single-port sequential schedule, and keep A13 bit-exact. Whether
that mapping reduces wall-clock e2e is a later, separately gated measurement
(A17.6). Whether the remaining compute bound should be co-designed with table
placement is later still (A18).

## 2. Design

A16.2 remains the comparison baseline: one compute unit, one `m_axi_gmem`,
`HBM[0]`, four sequential lookups of canonical rows 37–40, then the unchanged
A13 pipeline.

A17 adds a versioned public top `dlrm_f37x_rtl_kernel_stage2n_a17_v1` that:

1. snapshots four 64-bit table bases on one accepted START;
2. issues one single-beat read per port (`ARLEN=0`, 128-bit data, at most one
   outstanding request per master);
3. retains responses that may return in any order;
4. injects slots 0–3 through the existing single A13 embedding configuration
   port only after all four rows succeed;
5. starts A13 Bottom–Interaction–Top only from a fresh completed group.

Identity mapping for a future link, not yet live in `config/`, is port *i* to
`HBM[i]`. Runtime programming stays user-managed AXI-Lite (`xclRegWrite` of
BASE0–BASE3). Four kernel pointer arguments would exist only for Vitis
association; they are not an OpenCL `setArg` ABI change.

Error handling is group-scoped: any fault forbids all four A13 commits for
that job, drains issued single-beat responses, and returns to IDLE through
CLEAR. Busy or repeated START cannot overwrite an in-flight group.

The first physical fixture, when authorized, may copy the same 1024-byte
canonical table into four BOs so that port *i* still reads logical row
`37+i`. That is a concurrency fixture, not four production tables and not a
placement optimizer.

## 3. RTL structure

Frozen blocks are instantiated, not edited: four copies of the accepted A14
v2 lookup engine, the accepted A13 pipeline and cycle counters, and the A16
inclusive interval counters at `0x300`’s neighboring window (`0x30C`,
`0x310`).

New versioned files only:

- `rtl/hbm/dlrm_hbm_parallel_lookup_stage2n_a17_v1.sv` — four engines and
  independent AR/R gather;
- `rtl/pipeline/dlrm_hbm_pipeline_integration_stage2n_a17_v1.sv` — group
  commit, ordered inject, error drain;
- `rtl/f37x/dlrm_f37x_rtl_kernel_stage2n_a17_v1.sv` — public `s_axi_control`
  plus `m_axi_gmem0..3`.

Internal packed AXI arrays between the kernel top and the integration wrapper
are not a fifth Vitis master. Public names are `m_axi_gmem0` through
`m_axi_gmem3`. The A13 map through `0x224` is unchanged. BASE0 remains
`0x304/0x308`; BASE1–BASE3 occupy `0x318` through `0x32C`.

## 4. Verification

Verification is layered so that a later reviewer cannot confuse XSim with
HBM.

| Layer | Evidence | Bound |
|---|---|---|
| A16.2 | Physical single-bank PASS | `112/1174/1289/3`; five exact cases |
| A17.1 | Local controller XSim | 73 cases including 24 response orders |
| A17.2/A17.3 | Public-kernel XSim | four AR, reorder 2/0/3/1, stall, SLVERR drain, restart; result 36; A13 `322/100/744/1174` |
| A17.4–A17.5C | Mapping, packaging, Host, and execution-gate documents | no XO, no xclbin, no device |
| A17.6 | Authorized F37X four-bank run | `WAITING AUTHORIZATION` |

A17.3 fake-memory lookup cycles are not comparable to A16.2’s 112. Mapping
PASS and e2e reduction are different predicates: unique `HBM[0..3]` can hold
while e2e stays near 1289 cycles.

## 5. Limitations

- Four AXI ports are a packaging prerequisite, not four physical banks until
  A17.6 CONNECTIVITY and BO metadata say so.
- Each engine remains single-beat, one-outstanding. There is no burst,
  cache, or coalescer.
- Gather-then-inject pays a join wait and then a serial A13 configuration
  port. Parallel HBM reads do not parallelize MLP.
- The four-BO copied table is not multi-table placement.
- A16.2 timing already sits at WNS 0.000 ns; four SI may fail the 100 MHz
  gate.
- Interconnect sharing can hide bank-level concurrency even with four `used`
  bits.
- Host programming and result polling sit outside the FPGA e2e counter.

## 6. Discussion: why embedding reduction is not enough

Suppose, as a thought experiment only, that four-bank lookup collapsed the
112-cycle interval by four to 28 cycles and that compute 1174 and residual 3
did not move. FPGA e2e would become about 1205 cycles, a factor of
`1289/1205 ≈ 1.07`. If lookup vanished entirely, the bound would still be
about `1289/1177 ≈ 1.10`. Neither figure is a prediction or an acceptance
threshold. They only show that this workload’s FPGA-visible time is
MLP-dominated.

That is the intended experimental reading of A16.2 versus A17:

- Embedding lookup is the memory-bound slice. A17 is the architecture that
  can put four short reads on four HBM tags.
- Bottom / Interaction / Top remain compute-bound on the accepted dense
  engine. A17 does not change PE count, datatype, or layer schedule.

A successful A17.6 run should therefore be reported as (i) whether the
four-bank map is real, and (ii) how lookup and e2e moved, not as a blanket
accelerator speedup. If lookup falls and e2e barely moves, the result still
supports the co-design claim rather than contradicting A17.

## 7. Outlook: A18 storage–compute co-design

A18 is not authorized in this draft. It is the logical next research
question once A17.6 exists:

- table and bank placement under capacity and co-access;
- whether embedding traffic and dense occupancy can be overlapped;
- ablation against round-robin or capacity-only maps.

A17 only supplies the controllable four-master substrate and the A16.2
instrumented baseline. A18 would have to change *what is stored where* or
*when compute starts relative to outstanding reads*. Until A17.6 logs exist,
A18 stays future work.

## Milestone record

| Stage | Status |
|---|---|
| Stage 2N-A16.2 | Physical single-HBM baseline completed (`112/1174/1289`) |
| Stage 2N-A17.1–A17.5C | Architecture and verification framework completed locally |
| Stage 2N-A17.6 | Physical four-bank experiment, **WAITING AUTHORIZATION** |
| Stage 2N-A18 | Storage–compute co-design, not started |
