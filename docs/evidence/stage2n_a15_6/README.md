# Stage 2N-A15.6 evidence boundary

This directory separates local preparation evidence from any future real-board
evidence.

- `local_preparation_v1/` contains only local source, deterministic golden,
  assembler, validator and Git checks. It proves no FPGA or physical-HBM
  behavior.
- A future successful protected run must create a new timestamped directory and
  retain its runner log, Host log, pre/post device queries, JSON evidence and
  offline validation log.
- The accepted 43 MB xclbin is referenced only by its fixed SHA256 and UUID; it
  is not copied here.
- No DCP, WDB, build directory, device reset log or unrelated-user state belongs
  in this evidence directory.

The JSON schema is represented by `A15_6_BOARD_EVIDENCE_TEMPLATE_V1.json`.
Placeholder values are not evidence and must never be changed to `PASS` without
a real protected execution and successful offline validation.
