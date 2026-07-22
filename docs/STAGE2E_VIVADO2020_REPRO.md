# Stage 2E Vivado 2020.2 reproduction review

## Status and evidence boundary

The exact Vivado 2020.2 Stage 2E run is **NOT RUN** on this local workstation.
Local read-only detection found no `vivado` command, no `XILINX_VIVADO`
environment, no Vivado installation registration, and no executable at the
known local 2020.2 paths. The only executable discovered by this bounded probe
is Vivado 2022.1 at
`D:\vivado2022\vivado2022forwins\Vivado\2022.1\bin\vivado.bat`; its own
`-version` output identifies `Vivado v2022.1`.

Repository policy prohibits network, SSH, remote execution, and server access.
Therefore no server-side Vivado path was searched or executed, no tool was
installed, and no 2022.1 result is relabeled as 2020.2 evidence. Stage 2E is
blocked at target-version execution, not failed at RTL compile, RAM inference,
DSP mapping, quantization timing, or constraints.

The reviewed source base is Stage 2D commit
`f566b838deddfce87f69cc34bf36ed0b614c6900`. Stage 2E changes only local
reproduction/reporting scripts and documentation; `rtl/`, `tb/`, expected
outputs, dimensions, memory capacities, and the 10.000 ns constraint are
unchanged.

## Regression status

The three tool-independent regressions were rerun on the Stage 2D source:

| Suite | Stage 2E local result |
|---|---|
| Phase 1 Python | PASS, 24 deterministic cases |
| Stage 2A Python | PASS |
| Stage 2B Python | PASS, 11 valid and 9 invalid cases |
| Vivado 2020.2 Stage 2A XSim | NOT RUN; target tool unavailable |
| Vivado 2020.2 Stage 2B XSim | NOT RUN; target tool unavailable |
| Vivado 2020.2 OOC synthesis | NOT RUN; target tool unavailable |

The current ignored workspace reports from the final Stage 2D run are at the
same `f566b83` source and still show Vivado 2022.1 Stage 2A XSim 6/6 PASS and
Stage 2B XSim PASS with the exact marker
`valid=11 invalid=9 total=20`. They are retained as the comparison baseline,
not target-version evidence.

## Version comparison

| Metric | Vivado 2020.2 | Vivado 2022.1 baseline | Difference |
|---|---:|---:|---:|
| LUT | NOT RUN | 4,550 | unknown |
| FF | NOT RUN | 1,946 | unknown |
| RAMB36E1 | NOT RUN | 17 | unknown |
| RAMB18E1 | NOT RUN | 32 | unknown |
| DSP | NOT RUN | 21 | unknown |
| WNS at 10.000 ns | NOT RUN | +0.758 ns | unknown |
| TNS | NOT RUN | 0.000 ns | unknown |
| Failing setup endpoints | NOT RUN | 0 | unknown |
| Latches | NOT RUN | 0 | unknown |
| DRC violations | NOT RUN | 43 warnings | unknown |
| Methodology violations | NOT RUN | 548 warnings | unknown |

The 2022.1 report parser independently confirms 16 unique `4096x8` weight
banks and one `1024x24` bias RAM in 17 RAMB36E1 blocks, plus 32 unique `64x16`
activation banks in RAMB18E1 blocks. The top resources are 4,550 LUT, 1,946 FF,
17 RAMB36E1, 32 RAMB18E1, and 21 DSP.

At 10.000 ns, the 2022.1 reports contain WNS +0.758 ns, TNS 0, and no failing
setup endpoint. The worst path remains
`provider_weight_req_address/CLK` to `weight_rsp_error_reg/D`. `check_timing`
has zero internal clock, unconstrained-endpoint, multiple-clock, loop,
partial-delay, or latch-loop issues; its 482 missing input delays and 44 missing
output delays are the expected clock-only OOC boundary.

The 43 DRC warnings are CFGBVS-1 (1), DPIP-1 (32), DPOP-1 (5), and DPOP-2 (5).
The 548 methodology warnings are SYNTH-6 (12), SYNTH-11 (2), and TIMING-18
(534). The highest-fanout net is a vector-dot state decode with fanout 1,363.
These are synthesized OOC observations, not implementation or board results.

## Reproduction entry

`scripts/run_stage2e_repro.ps1` accepts an explicit local Vivado executable or
checks `XILINX_VIVADO`, `PATH`, and bounded known local paths. It queries
`vivado -version` first and refuses to run if the executable is not exactly
Vivado 2020.2. A valid run executes, in order:

1. Phase 1, Stage 2A, and Stage 2B Python regressions;
2. Stage 2A XSim and all six explicit PASS markers;
3. Stage 2B XSim and the exact `valid=11 invalid=9 total=20` marker;
4. the existing Stage 2C/2D OOC synthesis at 10.000 ns;
5. report extraction and structural/timing checks.

Example for a workstation that already has the target tool:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File scripts/run_stage2e_repro.ps1 `
  -VivadoExe 'C:\Xilinx\Vivado\2020.2\bin\vivado.bat'
```

The generated logs, DCP, XSim products, reports, and JSON summaries remain
ignored. `scripts/summarize_stage2e_reports.py` extracts the lightweight
comparison data and rejects a report whose embedded Vivado version does not
match the requested version.

## Remaining evidence

- Vivado 2020.2 compile, XSim, resource, RAM-inference, timing, DRC,
  methodology, and high-fanout results remain unavailable.
- No compatibility RTL change is justified without a real 2020.2 failure.
- Full place-and-route implementation has not been run under either version.
- F37X/VU37P compilation and board execution have not been run.
- No `.xclbin` has been generated.
