# Risk register

| ID | Risk | Probability | Impact | Current evidence | Mitigation | Stop condition |
|---|---|---|---|---|---|---|
| R-001 | RTL syntax/elaboration defect | Medium | High | No RTL compiler log exists | Static review; ordered XSim/Icarus/Verilator flows | Three repair loops fail on the same root cause |
| R-002 | Vivado 2020.2 SystemVerilog incompatibility | Medium | High | Code uses SV-2012 arrays, generate, and file parameters but is uncompiled | XSim 2020.2 batch validation and minimal compatibility patches | Fix would require public-interface or fixed-point change |
| R-003 | Signed width/rounding mismatch | Low-Medium | High | Python tests pass; RTL is not simulated | Independent derivation, directed boundaries, top bit comparison | Evidence shows the fixed-point format is not self-consistent |
| R-004 | Ready/valid loss or duplication | Medium | High | Logic review only; FIFO randomized test not executed | Timeout-protected backpressure, simultaneous transfer, and hold tests | Repeated unexplained data loss after three fixes |
| R-005 | Testbench false PASS/hang | Low-Medium | High | All eight benches now have global timeout, `$fatal`, and explicit PASS; not yet simulated | XSim checks both exit code and PASS marker | Tool exits zero without PASS or test cannot be made deterministic |
| R-006 | Source/log version mismatch | Low | High | Baseline now exists at `22d35f4` | Record Git HEAD/diff and SHA-256 manifest in bundles | Returned logs lack source revision/manifest |
| R-007 | INT32 wrap harms trained accuracy | Medium | Medium-High | Contract intentionally wraps; only synthetic model used | Later trained-model range/accuracy study behind gate | Production model overflows materially and contract change is needed |
| R-008 | Phase-1 architecture mispredicts F37X resources/timing | High | Medium | Parallel dot and local memory are verification models | No performance claims; phase-2 PE/resource model after GATE-1 | Current architecture has no viable bounded-resource successor |
| R-009 | HBM behavior invalidates scheduling assumptions | High | High | No AXI/HBM is implemented | Defer to GATE-4 and require shell/platform evidence | Real HBM mapping/interface choice is required |
