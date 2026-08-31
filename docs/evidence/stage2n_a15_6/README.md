# Stage 2N-A15.6 evidence boundary

This directory separates local preparation evidence from accepted real-board
evidence.

- `local_preparation_v1/` contains only local source, deterministic golden,
  assembler, validator and Git checks. It proves no FPGA or physical-HBM
  behavior.
- `final_acceptance_v1/` contains the compact imported evidence from the
  successful protected F37X run at server result timestamp `20260831_102550`:
  exact runner/Host logs and board JSON, compact summaries derived from the
  pre/post device queries and xclbin information, server and local validator
  records, a compact status, and SHA256 manifest. The original query/info files
  remain byte-exact inside the retained `_local_recovery` archive.
- The accepted 43 MB xclbin is referenced only by its fixed SHA256 and UUID; it
  is not copied here.
- No DCP, WDB, build directory, device reset log or unrelated-user state belongs
  in this evidence directory.

The JSON schema is represented by `A15_6_BOARD_EVIDENCE_TEMPLATE_V1.json`.
Placeholder values are not evidence and must never be changed to `PASS` without
a real protected execution and successful offline validation.
