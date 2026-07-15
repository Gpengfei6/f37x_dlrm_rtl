# F37X DLRM RTL accelerator — GATE-1 plus Stage-2A baseline

This repository is a local, simulation-first prototype for a recommendation
inference accelerator.  The implemented scope is deliberately small:

```text
NUM_LOOKUPS embedding IDs
  -> synchronous local embedding memory
  -> element-wise embedding sum
  -> one fixed-point dense layer
  -> quantization + ReLU
  -> output vector
```

Stage 2A adds an independent parameterized, multi-cycle vector-PE dense engine
with P-banked ping-pong activations and an abstract local weight/bias provider.
It is **not** a complete DLRM and does not contain AXI, HBM, an XRT host,
duplicate-ID merging, dynamic micro-batching, an RTL-kernel shell, or an
`.xclbin`.  No claim is made that the design has been compiled or run on F37X.

## Default configuration

The source of truth is `config/model_config.json`.  The default model uses 32
embedding rows, 4 lookups, an embedding/dense input dimension of 8, and 4 dense
outputs.  Embeddings and weights are signed INT8 Q3.4 values.  Bias is signed
INT24 Q15.8.  The dense accumulator is signed INT32 Q*.8.  Quantization rounds
an arithmetic right shift by four bits to nearest, with ties away from zero,
saturates to signed INT16 Q*.4, and then applies ReLU.

See `docs/fixed_point_spec_v0.md` for exact overflow and bit-level rules.

## Local workflow

Run the unified Windows-local validation entry.  It probes every tool, records
exit codes, and emits `results/validation_summary.json` without installing
anything:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File scripts/run_all_local.ps1 [-PythonExe <python.exe>]
```

Generate deterministic data and run Python checks (no third-party package is
required):

```bash
python3 scripts/run_python_tests.py
```

Run all RTL testbenches when Icarus Verilog is available:

```bash
bash scripts/run_rtl_tests.sh
```

Run optional lint (Verible, then Verilator fallback):

```bash
bash scripts/lint_rtl.sh
```

Scripts detect missing commands and never install software.  Run them from the
repository root.  Generated vectors are deterministic and checked in so an RTL
simulation does not depend on invoking Python first.

When Vivado/XSim is locally configured, the ordered standalone entry is:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run_xsim_stage1.ps1
```

The separate Stage-2A server entry is:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/run_xsim_stage2a.ps1
```

Its dependency-free Python oracle is:

```bash
python3 scripts/run_stage2a_python_tests.py
```

## Verification status

This section records only commands actually run in the current local workspace.

- Python reference/tests: **passed locally on 2026-07-14** using the bundled
  Python 3.12 runtime.  `scripts/run_python_tests.py` passed 24 deterministic
  cases and its packed-output self-comparison; `python/reference_model.py`
  completed all 24 cases.  Python `compileall` also completed with exit code 0.
- RTL simulation: not run; local Icarus/Verilator was not found during initial
  inspection.
- RTL lint: not run; local Verible/Verilator was not found during initial
  inspection.
- F37X compile, `.xclbin`, and board run: not run and intentionally out of scope.

Server retry2 under Vivado 2020.2 produced Python PASS, `xvlog` PASS, 8/8
`xelab` PASS, 8/8 explicit XSim PASS markers, and top-level 24-vector bit-for-bit
agreement.  All 64 manifest hashes match source commit `44a1b25`; GATE-1 is
approved.  Work remains stopped before parameterized PE-array architecture and
phase-2 implementation.

The phase-1 hardening run of `scripts/run_all_local.ps1` reported 4 PASS, 0 FAIL,
and 4 SKIPPED: Python regression/reference/packed comparison and bundle creation
passed; Icarus, Verilator, Verible, and XSim suites were skipped because those
tools are absent.  PowerShell parsing and payload/hash structural checks also
passed outside that summary.  Those local skips did not provide GATE evidence;
the later retry2 server run now provides the required RTL evidence.

The exact Python regression summary is saved in `logs/python_tests.log`.
Tool-availability evidence is saved in `logs/tool_availability.log`.

The Stage-2A local workflow currently records RTL compile/simulation/lint as
SKIPPED because Vivado, Icarus, Verilator, and Verible are absent.  It does not
claim Stage-2A RTL PASS; use the generated server payload and return real logs.

After running tests, detailed logs are written under `logs/`.  RTL output can be
checked independently with:

```bash
python3 python/compare_results.py \
  --rtl results/rtl_top_outputs.hex \
  --expected tests/expected/top_expected.json
```

## Directory map

- `docs/`: architecture, interfaces, fixed-point contract, and staged plan.
- `tasks/`: prioritized backlog and completed work.
- `python/`: bit-accurate and floating reference code plus vector tooling.
- `rtl/`: parameterized synthesizable SystemVerilog cores and minimal pipeline.
- `tb/`: independent self-checking testbench for every RTL module.
- `tests/`: deterministic model images, inputs, and expected results.
- `scripts/`: tool-detecting Python, simulation, and lint entry points.
- `handoff/stage1_validation/`: credential-free manual server validation package.
- `host/`: future C++11/XRT boundary description only.

Generated logs/results are retained locally and in validation bundles but are
ignored by Git; exact source correspondence is provided by SHA-256 manifests.
