# Repository working rules

## Scope

- Work locally in this repository only.
- Never use network access, SSH, SCP, SFTP, rsync, remote desktop, remote shells,
  remote execution, or access `172.17.8.254`.
- Never access or modify `/home/chaosuan`, `/opt/Xilinx`, or `/opt/xilinx`.
- Never request credentials or install/upgrade server software, drivers,
  firmware, FPGA platforms, or tools.
- The user alone performs future F37X compile, `.xclbin` generation, and board
  execution.  Do not claim F37X success without user-supplied logs.
- Server commands and validation packages may be generated locally, but Codex
  never executes them.  The target remains one F37X card; do not add multi-card
  behavior.

## Design constraints

- FPGA compute cores use parameterized synthesizable SystemVerilog-2012; no HLS.
- Maintain Python 3, C++11, and Vivado/Vitis 2020.2 compatibility.
- Core RTL must not use `real`, delay-based logic, or vendor algorithm IP.
- Every RTL module needs an independent self-checking testbench and bit-level
  agreement with the Python fixed-point contract.
- Ready/valid interfaces must retain data under backpressure.
- Record latency, throughput, rounding, saturation, and overflow explicitly.
- Prefer small reviewable changes.  Preserve unrelated or existing files.

## Current boundary

Only phase 0/1 is implemented: local embedding lookup, aggregation, one dense
layer, quantization, ReLU, and output.  Do not add full DLRM, multilayer MLP,
feature interaction, AXI/HBM, XRT host, duplicate merging, dynamic micro-batch
scheduling, or multi-card support without explicit approval.

## Verification language

- A tool being invokable is not a passing test.
- If a simulator/linter is missing, report the test as not run; never install it.
- Report created/modified files, key diff, commands run, passes, skips, and risk.

## Autonomous workflow and gates

- At the start of work, read this file, `README.md`, the architecture and
  fixed-point specifications, and `docs/CURRENT_STATE.md` when present.
- Select the highest-priority unblocked stage-1 task, make a small change, run
  every locally available test, review the diff, and update state/risk records.
- Record material design decisions in `docs/DECISIONS.md`.
- Do not enter phase 2 until `docs/VALIDATION_GATES.md` records real compiler and
  simulation logs satisfying GATE-1.  Python-only checks never satisfy GATE-1.
- Stop before changing the fixed-point contract, public top-level interface,
  model direction, real HBM mapping, or paper/patent innovation.

