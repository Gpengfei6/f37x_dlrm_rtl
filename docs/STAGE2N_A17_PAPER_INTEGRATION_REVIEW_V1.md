# A17 Paper Integration Review V1

Date: 2026-09-08. Revision: tightened after GPT review of the first
integration pass. Status: **paper-structure review only**.

This document does not rewrite RTL, Host, `config/`, or evidence. Completing
a writing draft (V3) is not experiment closure and not paper-evidence
closure.

## File identity (point 4)

The earlier convention “V1 = engineering record, V2 = methodology chapter”
was a **plan**, not a guarantee that the V1 path stayed untouched.

| Path | What it actually is |
|---|---|
| `STAGE2N_A17_PAPER_CHAPTER_MULTIBANK_LOOKUP_V1.md` | **Overwritten in place.** Current text is a later academic refinement, not Cursor’s first engineering draft. |
| `STAGE2N_A17_PAPER_CHAPTER_MULTIBANK_LOOKUP_V2.md` | **Independent Cursor file.** Created as a new path; it did not replace V1. Still present. |
| `STAGE2N_A17_PAPER_CHAPTER_MULTIBANK_LOOKUP_V1_ENGINEERING_SNAPSHOT.md` | Recovered first Cursor engineering draft. Never committed; restored after the overwrite was discovered. |
| `STAGE2N_A17_PAPER_CHAPTER_MULTIBANK_LOOKUP_V3.md` | Paper-integrated writing draft. Writing only. |

Do not claim that the original V1 working-tree text was fully preserved in
the V1 path. It was not. V2 was saved independently. None of these paper
files is in git until the user commits.

## Claim boundary (point 3)

### Follow-up source audit

V1, V2, the engineering snapshot, and V3 were confirmed as separate local
files. The snapshot body from Motivation through the milestone record
matches the first V1 text previously read in this task, after line-ending
normalization. This is a content comparison, not proof of a byte-identical
historical file: its heading and recovery notice are later additions, and
the original was never committed.

The five review boundaries above and below are retained in V3. A follow-up
edit also corrects HBM wording, replaces the unsupported inference that a
scalable architecture is necessary with a bounded research question, and
adds inclusive counter definitions, conditional-bound assumptions, and
links to existing acceptance records. The residual is algebraically
derived; it is not an independently measured control stage.

V2 remains an independent earlier draft. Its phrase “control not attributed
to lookup or compute” and its necessity/scalability language should not be
copied into later prose without the corrections in V1's academic text and
V3. The historical engineering snapshot is preserved without content edits.

That source-audit follow-up revised only V3 and this integration review;
it added no literature survey, experiment, engineering change, or commit.
The subsequently authorized writing continuation adds a first selected-source
Related Work review directly to V3 Section II. Four works have relevant
full-text sections reviewed; FleetRec is limited to its published abstract
and author artifact overview. Coverage is not exhaustive and novelty remains
unestablished. No new paper version or engineering experiment is introduced.

Allowed:

- describe a **multi-bank-capable architecture design**;
- describe a **verification framework** on a validated DLRM FPGA baseline;
- report A16.2 as measured single-bank evidence.

Forbidden as a **measured result**:

- physical four-bank HBM operation on F37X;
- achieved multi-bank acceleration, latency reduction, bandwidth,
  throughput, or speedup.

A later mapping PASS still needs a comparable measurement before any
performance claim. “禁止多 Bank 加速器” applies to **measured outcomes**,
not to describing the intended architecture.

## Verdict (points 1–2, 5)

A16.2 + A17 methodology + the evaluation plan can form a **complete Method
chapter in writing**. They cannot form a **complete empirical paper**, and
they do **not** mean “method effectiveness is fully verified.”

| Paper part | Ready now? | Bound |
|---|---|---|
| I. Introduction | **partial** | baseline scoped; selected-source positioning added; exclusive novelty unestablished |
| II. Related Work | **first pass** | five selected works in V3; FleetRec full text and wider coverage pending |
| III. Methodology | **yes as writing** | architecture and verification *method* can be written; A17 is not fully hardware-validated |
| IV. Evaluation | **scaffold** | 4.1 measured A16.2; 4.2 simulated A17 with bound; 4.3–4.4 empty. **No 4.5 thought experiment** |
| V. Discussion | **analytical bounds** | ≈1.07× / ≈1.10× belong here, not in Results. Not observed bottleneck migration |
| V3 writing draft | **done** | not evidence closure |

A17 XSim (sample 36) does **not** replace A16.2’s five board cases and does
not prove physical four-bank performance.

Literature work has started independently of the A17.6 hardware wait.
The first comparison does not establish an exclusive academic contribution.
See V3 Section II for source-specific facts, reading depth, and remaining
coverage; no experimental state is promoted by this literature pass.

## Research storyline

```text
DLRM recommendation inference
        → embedding access
        → FPGA HBM opportunity
        → measured sequential baseline (A16.2): compute already dominates
        → multi-bank-capable architecture design (A17)
        → verification framework (sim ≠ map ≠ measure)
        → future storage–compute co-design (A18)
```

Do not write that A17 caused bottleneck migration. A16.2 was already
compute-dominated (1174/1289).

## Proposed structure (Results without analytical rows)

### III. Method

- 3.1 Baseline and bottleneck analysis → A16.2 **measured**
- 3.2 Multi-bank-capable architecture → A17 **designed**
- 3.3 RTL and dataflow → A17 **designed**
- 3.4 Verification methodology → framework; sim ≠ hardware
- 3.5 Limitations

### IV. Evaluation

- 4.1 Platform and baseline → A16.2
- 4.2 Functional verification → A17 XSim, bounded
- 4.3 Physical HBM mapping → pending A17.6
- 4.4 Latency analysis → A16.2 filled; A17 physical empty

### V. Discussion

- Analytical bounds under fixed compute / residual / clock
- Compute already dominates; A18 as future work

## Two-track status

```text
Engineering
========
A16.2 physical baseline
        |
A17 local architecture + verification framework
        |
WAITING F37X access (A17.6)

Paper
========
V1 path: academic refinement (overwrote first draft)
V2: independent methodology chapter
V3: writing integration (done; not evidence closure)
Related Work: selected-source first pass in V3; coverage incomplete
```

```text
A17_INTEGRATION_REVIEW_STATUS
Structure:          DONE (tightened)
Claim boundary:     CHECKED (measured vs design)
File identity:      CHECKED (V1 overwritten; V2 independent; snapshot restored)
Engineering:        UNCHANGED
V3 writing:         DONE
Evidence closure:   NO
```
