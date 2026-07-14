# Risk register

| ID | Risk | Probability | Impact | Current evidence | Mitigation | Stop condition |
|---|---|---|---|---|---|---|
| R-001 | RTL elaboration defect | Low | High | Retry1: `xvlog` and 8/8 `xelab` PASS under Vivado 2020.2 | Retain uniform timescale, local Dense indices, and ordered retry2 flow | A new elaboration error appears on unchanged configuration |
| R-002 | Vivado 2020.2 SystemVerilog incompatibility | Low | High | Retry1 compiles and elaborates all eight designs | Preserve the proven source subset and XSim batch flow | Fix would require public-interface or fixed-point change |
| R-003 | Signed width/rounding mismatch | Low | High | Five RTL tests and top 24-vector bit comparison PASS; Python checks also PASS | Retain directed boundaries and retry2 full suite | Evidence shows the fixed-point format is not self-consistent |
| R-004 | Ready/valid loss or duplication | Medium | High | Three replacement tests stopped on same-time-slot ready sampling; no data mismatch was observed | Delta-safe assertions, consecutive replacements, depth-one FIFO, random backpressure | Retry2 reports real loss, duplication, overwrite, or unstable output |
| R-005 | Testbench scheduling race or false PASS | Medium | High | Retry1 fatal sites are all XSim `Iteration: 0` immediate combinational checks | Sample after `#1`, retain exact ready assertion and same rising-edge transfer, require PASS marker | Test still depends on active-region ordering or exits without PASS |
| R-006 | Source/log version mismatch | Low | High | Retry1 manifest revision is UNKNOWN, but all 17 RTL/TB SHA-256 values match local `66c9307` | Bind retry2 payload to the new Git HEAD and verify exact hashes | Returned logs lack both usable revision and matching manifest |
| R-007 | INT32 wrap harms trained accuracy | Medium | Medium-High | Contract intentionally wraps; only synthetic model used | Later trained-model range/accuracy study behind gate | Production model overflows materially and contract change is needed |
| R-008 | Phase-1 architecture mispredicts F37X resources/timing | High | Medium | Parallel dot and local memory are verification models | No performance claims; phase-2 PE/resource model after GATE-1 | Current architecture has no viable bounded-resource successor |
| R-009 | HBM behavior invalidates scheduling assumptions | High | High | No AXI/HBM is implemented | Defer to GATE-4 and require shell/platform evidence | Real HBM mapping/interface choice is required |
