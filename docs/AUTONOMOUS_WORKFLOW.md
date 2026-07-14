# Autonomous workflow

## Permanent boundary

Work is limited to this local repository.  Network access, remote sessions,
SSH-family tools, `172.17.8.254`, `/home/chaosuan`, `/opt/Xilinx`, and
`/opt/xilinx` are forbidden.  Codex must not request credentials, install tools,
change server software, execute server commands, or claim RTL/Vivado/F37X
success without corresponding real logs.  FPGA compute and scheduling remain
SystemVerilog, and the target remains one F37X card.

## Normal work cycle

1. Read `AGENTS.md`, `README.md`, architecture, fixed-point contract, and
   `CURRENT_STATE.md`.
2. Inspect source, tests, current Git diff, backlog, and open risks.
3. Select the highest-priority unblocked task within the current gate.
4. State a short plan and make a conservative, reviewable patch.
5. Run `scripts/run_all_local.ps1` with every available local tool.
6. Review arithmetic widths, signedness, handshakes, reset, portability, tests,
   generated artifacts, and Git diff.
7. Fix a discovered root cause and repeat validation, up to three iterations for
   the same problem.
8. Update decisions, state, risk register, backlog/completed work, and handoff.
9. Stop only at a defined human gate or after three unsuccessful repair loops.

PASS, FAIL, and SKIPPED are disjoint.  Missing tools produce SKIPPED, never PASS.
Generated summaries must retain the command exit code and log path.

## Human gates

- **GATE-1:** real SystemVerilog compilation and all eight testbenches, including
  24 top-level vectors and random FIFO backpressure, must pass with versioned
  logs.  Until then, remain in phase 1.
- **GATE-2:** parameterized PE/multicycle/multilayer compute is reviewed after
  GATE-1.  Do not enter HBM work from this gate.
- **GATE-3:** review the complete simplified-DLRM architecture before changing
  the global dataflow, fixed-point contract, or PE architecture.
- **GATE-4:** stop before AXI/HBM, Vitis RTL Kernel, or real F37X integration and
  wait for the user's shell/interface information and hardware logs.
