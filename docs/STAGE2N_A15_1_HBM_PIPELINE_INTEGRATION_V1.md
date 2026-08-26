# Stage 2N-A15.1 HBM-to-Pipeline Integration V1

Date: 2026-08-26

Status: **LOCAL XSIM PASS**

## 1. Stage objective

Stage 2N-A15.1 establishes the minimum controller-level path from the accepted
A14 v2 128-bit embedding lookup response to embedding slot 0 of the accepted
A13 internal DLRM pipeline. Embedding slots 1 through 3 retain their existing
Host-configured behavior. This stage is a local RTL/XSim integration proof; it
does not create a public F37X kernel top or run a physical HBM transaction.

## 2. Baseline HEAD

The implementation and local simulation started from branch
`work/stage2n-a15-hbm-pipeline-integration` at
`2020e4ccd2f802d69714d957e7b8baf8172a39fa`.

## 3. Authorization

The governing AGENTS authorization is commit
`2020e4ccd2f802d69714d957e7b8baf8172a39fa`, which authorizes versioned A15.1
RTL, an independent testbench, local XSim runners, local documentation, and a
local exact-file commit. It prohibits network, server, target-build, xclbin,
FPGA-device, and board operations.

## 4. A13 audit used as a frozen input

The accepted A13 controller provides four 128-bit embedding stores,
`embedding_mem[0:3]`, and a four-bit loaded mask. Its configuration port accepts
data only while the controller permits configuration. Pipeline START remains
subject to the existing `embedding_loaded == 4'hF` gate. A15.1 instantiates the
accepted A13 cycle-counter wrapper without modifying it.

## 5. A14 audit used as a frozen input

The accepted A14 v2 lookup performs one outstanding, one-beat AXI4 read at
`TABLE_BASE + (LOOKUP_INDEX << 4)`. It returns one 128-bit row and an error
indication. Its lane packing already matches A13, so A15.1 connects the response
directly and performs no lane reorder.

## 6. Feature Interaction vector order

The retained A13 ordering is:

1. vector 0: Bottom MLP 8-element output;
2. vector 1: embedding slot 0, supplied by A14 v2 through A15.1;
3. vector 2: Host-configured embedding slot 1;
4. vector 3: Host-configured embedding slot 2;
5. vector 4: Host-configured embedding slot 3.

## 7. Exact 128-bit lane packing

The direct response mapping is little-lane-first:

| Bits | A13/A14 lane |
|---|---|
| `[15:0]` | lane 0 |
| `[31:16]` | lane 1 |
| `[47:32]` | lane 2 |
| `[63:48]` | lane 3 |
| `[79:64]` | lane 4 |
| `[95:80]` | lane 5 |
| `[111:96]` | lane 6 |
| `[127:112]` | lane 7 |

The accepted row-37 test vector is `[40,41,42,43,44,45,46,47]`.

## 8. Slot ownership

- Slot 0 is HBM-owned in A15.1. A Host attempt to write slot 0 is consumed with
  an explicit rejection pulse and is never forwarded to A13.
- Slots 1 through 3 remain Host-owned and use the original A13 configuration
  handshake.

## 9. Injection arbitration

A successful lookup response is copied into a retained pending register. While
that register is valid, it owns the A13 embedding configuration port with index
0 and has priority over Host configuration. Host slots 1 through 3 resume after
the pending HBM write completes. A simultaneous new lookup request takes
priority over pipeline START so the job cannot start with the previous slot-0
value while a replacement lookup is beginning.

## 10. Delayed-ready behavior

The integration wrapper holds `hbm_inject_pending`, the 128-bit data, and the
slot-0 index stable until A13 asserts `embedding_cfg_ready` and the injection
handshake occurs. The testbench closes the A13 configuration window, receives a
successful lookup, checks four retained cycles, reopens the window, and then
observes exactly one injection-complete pulse.

## 11. Lookup-error behavior

An A14 error is retained on a separate error channel and never asserts the A13
embedding configuration valid. An error before the first valid slot-0 load does
not set loaded bit 0. An error after a valid slot-0 load preserves both the
stored vector and the loaded bit.

## 12. Repeated/busy request behavior

Lookup request ready is low while the A14 lookup is active, while a successful
response is pending injection, or while an unacknowledged lookup error is
retained. The testbench presents a second index while the first AXI response is
delayed and confirms that the second request is not accepted and cannot replace
the first result.

## 13. Files created

- `rtl/pipeline/dlrm_hbm_pipeline_integration_stage2n_a15_v1.sv`
- `tb/tb_dlrm_hbm_pipeline_integration_stage2n_a15_v1.sv`
- `scripts/run_stage2n_a15_integration_xsim_v1.ps1`
- `scripts/run_stage2n_a15_integration_xsim_v1.tcl`
- `docs/STAGE2N_A15_1_HBM_PIPELINE_INTEGRATION_V1.md`

The accepted A13 and A14 v2 RTL files were instantiated, not edited.

## 14. XSim command

The accepted local run used Vivado/XSim 2022.1:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File scripts\run_stage2n_a15_integration_xsim_v1.ps1 `
  -ResultDir results\stage2n_a15_1\integration_xsim_v1_retry2
```

The versioned PowerShell runner compiles 15 exact source files, elaborates the
A15.1 testbench, runs the versioned Tcl command file, audits every required PASS
marker, rejects anchored error/fatal records, and writes a status file.

## 15. XSim result

- `xvlog`: PASS, exit code 0;
- `xelab`: PASS, exit code 0;
- `xsim`: PASS, exit code 0;
- accepted lookup requests observed: 4, including two locally rejected invalid
  requests and two physical fake-memory reads;
- AXI AR handshakes: 2;
- AXI R handshakes: 2;
- warning count: 0;
- anchored error/fatal count: 0.

Two retained pre-acceptance attempts document test infrastructure corrections:
the first found a multiply-driven timeout counter in the new testbench, and the
second found Windows backslash escaping in the XSim Tcl path. Neither failure
modified or implicated accepted A13/A14 RTL.

## 16. PASS markers

The accepted log contains each marker exactly once:

- `A15_1_HBM_SLOT0_INJECTION=PASS`
- `A15_1_LANE_ORDER=PASS`
- `A15_1_HOST_SLOT123_PRESERVED=PASS`
- `A15_1_LOADED_MASK=PASS`
- `A15_1_DELAYED_READY=PASS`
- `A15_1_LOOKUP_ERROR_GUARD=PASS`
- `A15_1_BUSY_GUARD=PASS`
- `A15_1_HOST_SLOT0_GUARD=PASS`
- `A15_1_A13_ABI_PRESERVED=PASS`
- `STAGE2N_A15_1_HBM_PIPELINE_INTEGRATION_V1_PASS`

The structural ABI guard also checks that the accepted A13 cycle-counter offsets
remain Bottom `0x218`, Interaction `0x21C`, Top `0x220`, and Total `0x224`.

## 17. Limitations

- The proof is controller-level, not a public AXI4-Lite/Vitis kernel-top merge.
- It uses a fake AXI memory model in local XSim.
- It injects one HBM-owned slot; slots 1 through 3 remain Host-configured.
- It does not execute a complete A15 prediction golden test.
- It does not add multiple tables, multiple HBM banks, bursts, multiple
  outstanding reads, caching, prefetching, coalescing, INT8 embeddings, or
  performance instrumentation.

## 18. Physical-HBM evidence boundary

Physical HBM validation for A15.1 is **NOT RUN**. The earlier accepted A14.7
single-row physical-HBM result is historical evidence for the standalone A14
path and must not be re-labelled as physical A15 integration evidence.

## 19. Performance evidence boundary

No A15.1 target timing, latency, bandwidth, throughput, power, speedup, CPU/GPU
comparison, or board-performance measurement was performed. Performance is
**NOT CLAIMED**.

## 20. Next stage

The next stage requires separate authorization. It may design the public
kernel/control integration and a complete functional-golden regression while
preserving the accepted A13 ABI and all A13/A14 assets. Target build/link,
xclbin generation, and any board run remain separately gated operations.
