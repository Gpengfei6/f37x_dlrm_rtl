# Risk register

| ID | Risk | Probability | Impact | Current evidence | Mitigation | Stop condition |
|---|---|---|---|---|---|---|
| R-001 | RTL elaboration defect | High | High | Retry0: `xvlog` PASS; 8/8 `xelab` FAIL. Earliest causes are missing timescale and Dense shared procedural index | Uniform source timescale, process-local Dense indices, retry1 ordered XSim flow | Same root cause remains after three repair loops |
| R-002 | Vivado 2020.2 SystemVerilog incompatibility | Medium | High | Retry0 proves parsing succeeds but elaboration stopped before simulation | Source compatibility patches plus `xelab --timescale 1ns/1ps`; review retry1 earliest error | Fix would require public-interface or fixed-point change |
| R-003 | Signed width/rounding mismatch | Low-Medium | High | Python tests pass; RTL is not simulated | Independent derivation, directed boundaries, top bit comparison | Evidence shows the fixed-point format is not self-consistent |
| R-004 | Ready/valid loss or duplication | Medium | High | Retry0 never reached functional simulation | Timeout-protected backpressure, simultaneous transfer, and hold tests | Repeated unexplained data loss after three fixes |
| R-005 | Testbench false PASS/hang | Low-Medium | High | Retry0 reached only elaboration; no PASS markers are valid yet | XSim checks both exit code and PASS marker | Tool exits zero without PASS or test cannot be made deterministic |
| R-006 | Source/log version mismatch | Low | High | Retry0 Git revision was UNKNOWN, but all 17 RTL/TB SHA-256 values match local `e5fffc8` | Retry1 payload records new Git HEAD and exact SHA-256 manifest | Returned logs lack both usable revision and matching manifest |
| R-007 | INT32 wrap harms trained accuracy | Medium | Medium-High | Contract intentionally wraps; only synthetic model used | Later trained-model range/accuracy study behind gate | Production model overflows materially and contract change is needed |
| R-008 | Phase-1 architecture mispredicts F37X resources/timing | High | Medium | Parallel dot and local memory are verification models | No performance claims; phase-2 PE/resource model after GATE-1 | Current architecture has no viable bounded-resource successor |
| R-009 | HBM behavior invalidates scheduling assumptions | High | High | No AXI/HBM is implemented | Defer to GATE-4 and require shell/platform evidence | Real HBM mapping/interface choice is required |
