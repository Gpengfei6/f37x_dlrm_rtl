# Repository working rules

## Scope

- Work locally in this repository only.
- Never use SSH, SCP, SFTP, rsync, remote execution, or access `172.17.8.254`.
- Never access or modify `/home/chaosuan`, `/opt/Xilinx`, or `/opt/xilinx`.
- Never request credentials or install/upgrade server software, drivers,
  firmware, FPGA platforms, or tools.
- The user alone performs future F37X compile, `.xclbin` generation, and board
  execution.  Do not claim F37X success without user-supplied logs.

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

