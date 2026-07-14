# F37X DLRM RTL accelerator — phase 0/1

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

The exact Python regression summary is saved in `logs/python_tests.log`.
Tool-availability evidence is saved in `logs/tool_availability.log`.

After running tests, detailed logs are written under `logs/`.  RTL output can be
checked independently with:

```bash
python3 python/compare_results.py \
  --rtl results/rtl_top_outputs.hex \
  --expected tests/expected/top_expected.json
```

## Directory map

- `docs/`: architecture, interfaces, fixed-point contract, and staged plan.
- `python/`: bit-accurate and floating reference code plus vector tooling.
- `rtl/`: parameterized synthesizable SystemVerilog cores and minimal pipeline.
- `tb/`: independent self-checking testbench for every RTL module.
- `tests/`: deterministic model images, inputs, and expected results.
- `scripts/`: tool-detecting Python, simulation, and lint entry points.
- `host/`: future C++11/XRT boundary description only.
