# Completed work

- Established phase-0 repository structure and design documents.
- Implemented phase-1 Python fixed/floating reference and deterministic vectors.
- Implemented local embedding lookup, aggregation, one dense layer, quantization,
  ReLU, ready/valid control, and eight independent testbenches.
- Passed 24-case Python regression and packed-output self-comparison locally.
- Froze pre-hardening phase-1 baseline at Git commit `22d35f4`.
- Established autonomous workflow, decision, risk, gate, backlog, and server
  handoff records.
- Completed a per-file RTL/fixed-point static review without changing the public
  interface or fixed-point contract.
- Added global timeout protection and stronger continuous/backpressure coverage
  to all eight testbenches.
- Added tool detection, unified PASS/FAIL/SKIPPED reporting, ordered XSim flow,
  SHA-256 manifests, and a credential-free stage-1 validation payload.
- Analyzed retry0 Vivado 2020.2 logs and verified both earliest elaboration root
  causes against an exact 17-file SHA-256 source match.
- Applied uniform module/testbench timescale and process-local Dense loop-index
  fixes without changing RTL interfaces, arithmetic, or cycle behavior.
- Analyzed retry1 Vivado 2020.2 evidence: `xvlog` and 8/8 elaborations passed,
  5/8 simulations and the top-level 24-vector comparison passed, and all 17
  RTL/testbench hashes matched commit `66c9307`.
- Identified three `Iteration: 0` testbench sampling races, retained their exact
  ready assertions, and added consecutive replacement and depth-one FIFO checks.
- Audited retry2 Vivado 2020.2 evidence against commit `44a1b25`: 64/64 manifest
  hashes match, Python and `xvlog` pass, 8/8 elaborations and simulations have
  explicit PASS evidence, and all 24 top-level outputs match bit for bit.
- Formally approved GATE-1 with 18 PASS, 0 FAIL, and 0 SKIPPED; stopped before
  parameterized PE-array architecture or any phase-2 implementation.
- Conditionally approved Scheme B, P=16 development default, ACC32/ACC48 modes,
  P-banked 1024/1024 ping-pong buffers, runtime descriptors, and the abstract
  provider boundary in architecture commit `7480133`.
- Implemented the independent Stage-2A baseline: six new SystemVerilog modules,
  six explicit-marker testbenches, a bit-accurate Python oracle, P=4/8/16/32
  estimator/coverage, and separate Vivado 2020.2/XSim scripts.
- Ran the unified local workflow with 6 PASS, 0 FAIL, and 5 SKIPPED.  Python
  Stage-1/Stage-2A/model/estimator/packing checks passed; all absent RTL tools
  remained explicitly SKIPPED.
- Prepared a credential-free Stage-2A server validation handoff and stopped
  before Stage 2B, full MLP, HBM, AXI, or Vitis Kernel work.
- Aligned the repository with the final thesis scope in design commit `70ff279`:
  bounded embedding-request coalescing/broadcast is primary, lightweight
  post-coalescing channel scheduling is secondary, and Stage 2A is foundational.
- Implemented the configurable PyTorch DLRM path plus a deterministic NumPy
  oracle, strict local-only Criteo loader, synthetic data, training/inference,
  intermediate outputs, save/reload, metrics, and JSON/CSV benchmark reporting.
- Implemented JSONL/CSV/NPY embedding traces, 1/2/4/8/16/32/64-request
  statistics, five bounded coalescing policies, and 4/8/16/32-channel abstract
  mapping/scheduling comparisons including the GATE-T3 four-way model.
- Passed 12 software feasibility checks with 0 failures; kept PyTorch CPU/CUDA
  as two explicit SKIPPED results and all real-data trace gates INCONCLUSIVE.
