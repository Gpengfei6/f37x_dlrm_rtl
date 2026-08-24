# AI Change Policy

This policy defines the minimum review boundary for any AI assistant that
proposes or makes changes in this repository. It supplements, but never
replaces, `AGENTS.md`. A planning or policy document is not itself authorization
to modify RTL, run remote tools, generate an xclbin, or access a board.

## 1. Protected Assets

The following are protected, previously validated engineering assets:

- the accepted Stage 2N-A13 RTL baseline;
- code covered by completed F37X board validation;
- the accepted Host validation flow and its register/data contracts;
- the fixed-point arithmetic contract, including widths, rounding, saturation,
  overflow, and ready/valid behavior;
- retained experiment, acceptance, recovery, patent, log, hash, and result
  evidence.

Without explicit user authorization for a precisely defined stage and file
set, an AI assistant must not refactor, optimize, replace, delete, rename, or
bulk-format these assets. Historical and untracked files must be preserved even
when they are not part of the active design.

## 2. Current Development Area

The current engineering area is **Stage 2N-A14**, an isolated FPGA-side HBM
embedding-lookup prototype. Subject to the exact authorization in `AGENTS.md`
and the user's current request, A14 work may include:

- an HBM lookup prototype;
- new, standalone RTL modules;
- new, independent self-checking testbenches;
- new validation and architecture documentation.

This list describes the development direction; it does not grant blanket
permission to add or modify code. Every file must be within the current
stage-specific authorization. A14 work must not alter the accepted A13 RTL,
fixed-point behavior, Host contract, or verified Bottom–Interaction–Top
pipeline.

The current A14 source validates a standalone lookup and wrapper in simulation.
It is not yet integrated into the A13 Feature Interaction input path and is not
a complete FPGA-resident sparse-plus-dense DLRM system.

## 3. Evidence Rules

Use the following status vocabulary consistently:

- **CONFIRMED**: the claimed behavior is supported by reviewed, applicable
  source plus retained test, build, timing, or board evidence.
- **BLOCKED**: a required environment, tool, artifact, authorization, or
  physical condition is unavailable, so the intended validation cannot run.
- **NOT VALIDATED**: the implementation or plan may exist, but the required
  evidence has not been produced and reviewed.

Also distinguish `PASS`, `FAIL`, and `NOT RUN` exactly as recorded by the
relevant validation flow. A script being present or a tool being invokable is
not a PASS. A planning document, proxy target, fake AXI memory, XO metadata, or
logical `m_axi_gmem` port is not physical HBM evidence.

Without applicable board results, do not claim:

- physical HBM bandwidth improvement;
- latency, throughput, or end-to-end performance improvement;
- actual acceleration or speedup;
- successful physical HBM connectivity, xclbin execution, or complete DLRM
  sparse-plus-dense integration.

When reporting historical evidence, name the stage and evidence source. Do not
present a historical result as a current rerun, and do not promote `BLOCKED` or
`NOT VALIDATED` to PASS.

## 4. Before Making Code Changes

Before changing any RTL, testbench, Host code, script, configuration, model, or
other executable artifact, the AI assistant must state:

1. the exact modification target and intended file set;
2. why the change is needed;
3. whether it can affect an accepted or previously validated behavior;
4. how the change will be verified, including unavailable checks and evidence
   boundaries.

It must then confirm that the request is authorized by both the user and the
applicable `AGENTS.md` section. If authorization is missing or the proposed
change crosses the A13 boundary, stop before editing code.

## 5. Repository Reading Order

Start with [`docs/AI_CONTEXT.md`](AI_CONTEXT.md). Follow its repository reading
order, then read this policy, `AGENTS.md`, `docs/CURRENT_STATE.md`, the active
stage documents, and the exact source/evidence files involved in the proposed
change.

Do not select a file only because it has the newest-looking suffix or stage
number. Accepted evidence and the canonical source map take precedence over
older summaries and retained duplicate files.
