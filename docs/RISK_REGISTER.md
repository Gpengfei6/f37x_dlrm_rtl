# Risk register

| ID | Risk | Probability | Impact | Current evidence | Mitigation | Stop condition |
|---|---|---|---|---|---|---|
| R-001 | RTL elaboration defect | Low | High | Retry2: `xvlog` and 8/8 `xelab` PASS under Vivado 2020.2 | Preserve the proven source subset and ordered validation flow | A new elaboration error appears after a source change |
| R-002 | Vivado 2020.2 SystemVerilog incompatibility | Low | High | Retry2 compiles, elaborates, and simulates all eight designs | Continue Vivado 2020.2 regression after RTL changes | A required change cannot be represented in the supported subset |
| R-003 | Signed width/rounding mismatch | Low | High | Python 24-vector and XSim top 24-vector bit comparisons PASS | Retain fixed-point contract and directed boundary vectors | New evidence disagrees with the frozen fixed-point specification |
| R-004 | Ready/valid loss or duplication | Low | High | FIFO replacement/depth-one/random tests, dot/embedding consecutive replacement, and integration backpressure all PASS | Retain all explicit PASS/timeout/data-stability checks | Regression reports loss, duplication, overwrite, or unstable output |
| R-005 | Testbench scheduling race or false PASS | Low | High | Retry2 has 8/8 explicit PASS markers; no fatal/timeout/error/warning | Require PASS marker plus exit/status/log audit on every run | A tool exits zero without the expected marker or scheduling becomes nondeterministic |
| R-006 | Source/log version mismatch | Low | High | Server Git is UNKNOWN, but all 64 manifest hashes, including 17 RTL/TB files, match commit `44a1b25` | Keep payload SHA manifest and audit against an explicitly named commit | Returned evidence lacks a complete matching source manifest |
| R-007 | INT32 wrap harms trained accuracy | Medium | Medium-High | Contract intentionally wraps; only synthetic model used | Later trained-model range/accuracy study behind gate | Production model overflows materially and contract change is needed |
| R-008 | Parameterized PE architecture may not meet F37X resources/timing | High | High | GATE-1 validates function only; no synthesis/resource/timing evidence exists | Review PE cycle/resource model before phase-2 implementation | Proposed architecture lacks a viable bounded-resource mapping |
| R-009 | HBM behavior invalidates scheduling assumptions | High | High | No AXI/HBM is implemented | Defer to GATE-4 and require shell/platform evidence | Real HBM mapping/interface choice is required |
