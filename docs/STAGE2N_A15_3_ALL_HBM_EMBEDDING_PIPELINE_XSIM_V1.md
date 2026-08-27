# Stage 2N-A15.3 All-HBM-Embedding Pipeline XSim V1

Date: 2026-08-27

Status: **LOCAL XSIM PASS**

## 1. Stage objective and baseline

Stage 2N-A15.3 proves a local controller-level sequence in which one accepted
A14 v2 lookup engine fetches four embedding rows and commits them to all four
accepted A13 embedding slots before the existing A13 pipeline START. It then
executes the complete Bottom MLP, Feature Interaction, and Top MLP and compares
the final result against an independently derived fixed-point golden.

- Branch: `work/stage2n-a15-hbm-pipeline-integration`
- Authorization and parent HEAD:
  `b3031d4f9d3c445a3f1eaa227ae2d28d35d78ae9`
- Closure commit: the local commit containing this document, with subject
  `feat(stage2n): complete A15.3 all-HBM pipeline XSim`
- Accepted A15.1 wrapper: reused as an audited predecessor, not modified
- Accepted A15.2 end-to-end sample: reused, not modified
- Accepted A13 controller/counter RTL: instantiated unchanged
- Accepted A14 v2 lookup RTL: instantiated unchanged

## 2. Why a new v2 integration wrapper is required

The accepted A15.1 v1 wrapper fixes every successful HBM response to A13 slot
0 and forwards Host configuration to slots 1 through 3. That ownership rule
cannot express four sequential HBM-owned slots without changing an accepted
file. A15.3 therefore adds one versioned orchestration wrapper and continues to
instantiate the accepted A13 and A14 modules directly.

No A13 or A14 arithmetic, storage, lookup, or counter implementation is copied
into the new wrapper.

## 3. Architecture

```text
one load-all request
        |
        v
one A14 v2 lookup engine / one AXI read master
        |
        +-- row37 response -- A13 embedding_cfg slot0 handshake
        +-- row38 response -- A13 embedding_cfg slot1 handshake
        +-- row39 response -- A13 embedding_cfg slot2 handshake
        +-- row40 response -- A13 embedding_cfg slot3 handshake
                                      |
                                      v
                         embedding_loaded_mask == 4'hF
                                      |
                                      v
          accepted A13 START -> Bottom -> Interaction -> Top -> result
```

“All HBM embeddings” in this stage means one logical engine, one AXI master,
four sequential logical reads, and four A13 embedding slots. It does not mean
four HBM banks, four parallel engines, parallel access, bursts, or multiple
outstanding transactions.

## 4. Canonical source audit

The tracked source of truth is
`models/stage2n_a14_embedding_table.json`. Its schema is
`stage2n_a14_embedding_table_v1`, with 64 rows, eight signed INT16 lanes per
row, 16 bytes per row, and `lane_0_in_bits_15_0` packing. The tracked payload
builder independently enforces the formula
`value[row][lane] = row*8 + lane - 256`.

- Model JSON SHA256:
  `af29d60e3dce8ebcbe87e1363665869851ee87942471aacadeacd47642e73122`
- Payload builder SHA256:
  `ab34fd6ef33563e30b52a5d811143c84fc6cc028e08e22376edfbb463d18570c`

The selected rows are tracked, valid, consecutive canonical rows:

| A13 slot | Lookup index | Byte offset | Expected signed lanes 0..7 | Packed 128-bit value |
|---:|---:|---:|---|---|
| 0 | 37 | 592 | `[40,41,42,43,44,45,46,47]` | `0x002f002e002d002c002b002a00290028` |
| 1 | 38 | 608 | `[48,49,50,51,52,53,54,55]` | `0x00370036003500340033003200310030` |
| 2 | 39 | 624 | `[56,57,58,59,60,61,62,63]` | `0x003f003e003d003c003b003a00390038` |
| 3 | 40 | 640 | `[64,65,66,67,68,69,70,71]` | `0x00470046004500440043004200410040` |

Machine-readable index names:

```text
LOOKUP_SLOT0_INDEX=37
LOOKUP_SLOT1_INDEX=38
LOOKUP_SLOT2_INDEX=39
LOOKUP_SLOT3_INDEX=40
```

## 5. Exact lane packing

The A14 response is connected bit-exactly to the A13 embedding data port:

| Bits | Lane |
|---|---:|
| `[15:0]` | 0 |
| `[31:16]` | 1 |
| `[47:32]` | 2 |
| `[63:48]` | 3 |
| `[79:64]` | 4 |
| `[95:80]` | 5 |
| `[111:96]` | 6 |
| `[127:112]` | 7 |

No lane reorder, byte swap, or width conversion exists in the v2 wrapper. The
final XSim observed all four actual vectors equal to the expected rows above.

## 6. Sequential controller

The wrapper uses these states:

- `SEQ_IDLE`: accept one load-all request;
- `SEQ_REQUEST`: hold the current lookup request/index until A14 accepts it;
- `SEQ_WAIT_RESPONSE`: wait for and consume one A14 response;
- `SEQ_INJECT`: retain response data and slot index until A13 accepts the
  embedding configuration;
- `SEQ_ALL_LOADED`: report successful completion and permit the existing A13
  START path;
- `SEQ_ERROR`: retain failing slot/index until explicit error acknowledgement.

One two-bit current-slot register selects parameterized indexes 37 through 40.
The slot advances only on
`a13_embedding_cfg_valid && a13_embedding_cfg_ready`. Therefore the next AXI
request cannot begin before the preceding row is committed.

The observed mask sequence is exactly:

```text
0000 -> 0001 -> 0011 -> 0111 -> 1111
```

## 7. Request, response, and injection rules

- Lookup request valid and index remain stable until A14 request ready.
- A successful response is copied once into retained data/index registers.
- While A13 configuration ready is low, injection valid, data, and slot remain
  stable and no later lookup is issued.
- A slot is counted as injected only on the A13 configuration handshake.
- Load-all ready is low during request, response wait, injection, and error.
- Repeated requests during AXI request stall and retained-response/configuration
  stall are rejected and do not alter request count, data, slot, or mask.

## 8. Error semantics

The fake memory returns an AXI error for row 39 in the error test. Rows 37 and
38 first commit to slots 0 and 1. The row-39 failure then produces:

- explicit sequence error slot 2, index 39;
- preserved slot0 and slot1 data;
- unchanged slot2 and slot3 data;
- loaded mask `4'h3`, not `4'hF`;
- three logical requests, three AR handshakes, and three R handshakes;
- no slot3 request;
- no automatic pipeline start or result.

The sequence remains in `SEQ_ERROR` until explicit acknowledgement.

## 9. Host ownership rule

All four A15.3 embedding slots are HBM-owned. The new wrapper keeps a Host
configuration-shaped input only for controller-level compatibility, consumes
each attempted write with an explicit rejection pulse, and never forwards it
to A13. XSim attempts writes to slots 0 through 3 after successful loading and
confirms that all four rows and the loaded mask remain unchanged.

## 10. Independent end-to-end golden

The accepted A15.2 network configuration is unchanged:

- Bottom: `8 -> 16 -> 8`;
- Feature Interaction: five 8-lane vectors -> 18 outputs;
- Top: `18 -> 32 -> 16 -> 1`;
- dense input: `[1,2,3,4,5,6,7,8]`;
- all descriptor shifts: zero;
- ReLU enabled on the first four layers and disabled on the final layer;
- biases: zero;
- sparse weights copy the first eight values through both Bottom layers and
  the first two Top layers, then sum those eight values in the final Top layer.

The testbench independently computes every Feature Interaction result from the
dense vector and four canonical rows. The resulting 18-element vector is:

```text
[1,2,3,4,5,6,7,8,
 1608,1896,17964,2184,20748,24556,2472,23532,27852,32172]
```

The accepted Top weights use the first eight values and produce:

```text
GOLDEN_RESULT = 1+2+3+4+5+6+7+8 = 36
```

This calculation is completed before observing the RTL result. Final XSim
reported expected 36 and actual 36.

## 11. A13 ABI and cycle counters

The accepted A13 START gate remains `embedding_loaded == 4'hF`. A pre-load
START attempt does not enter inference and returns the accepted missing-
embedding error. After four successful injection handshakes, the unchanged
A13 pipeline accepts START.

The source and testbench guards preserve these read-only offsets:

- Bottom: `0x218`;
- Interaction: `0x21C`;
- Top: `0x220`;
- Total: `0x224`.

Final XSim values are:

| Counter | Cycles |
|---|---:|
| Bottom | 322 |
| Interaction | 100 |
| Top | 744 |
| Total | 1174 |
| Controller overhead | 8 |

The four HBM-preload lookups occur before accepted A13 START and are not
included in these counters. This does not mean real HBM overhead is zero and is
not a latency or performance claim.

## 12. Self-checking scenarios and PASS markers

The final log contains each required marker exactly once:

- `A15_3_SLOT0_HBM_LOOKUP=PASS`
- `A15_3_SLOT1_HBM_LOOKUP=PASS`
- `A15_3_SLOT2_HBM_LOOKUP=PASS`
- `A15_3_SLOT3_HBM_LOOKUP=PASS`
- `A15_3_SLOT0_LANE_ORDER=PASS`
- `A15_3_SLOT1_LANE_ORDER=PASS`
- `A15_3_SLOT2_LANE_ORDER=PASS`
- `A15_3_SLOT3_LANE_ORDER=PASS`
- `A15_3_ALL_FOUR_HBM_EMBEDDINGS=PASS`
- `A15_3_EMBEDDING_LOADED_MASK=PASS`
- `A15_3_DELAYED_REQUEST_READY=PASS`
- `A15_3_DELAYED_RESPONSE=PASS`
- `A15_3_DELAYED_EMBEDDING_READY=PASS`
- `A15_3_LOOKUP_ERROR_PROTECTION=PASS`
- `A15_3_ERROR_FAILING_SLOT_NOT_LOADED=PASS`
- `A15_3_BUSY_REQUEST_PROTECTION=PASS`
- `A15_3_RESPONSE_HOLD=PASS`
- `A15_3_HOST_EMBEDDING_WRITE_REJECT=PASS`
- `A15_3_PIPELINE_START_GUARD=PASS`
- `A15_3_A13_PIPELINE_ABI_UNCHANGED=PASS`
- `A15_3_A13_CYCLE_COUNTER_ABI_UNCHANGED=PASS`
- `A15_3_END_TO_END_PIPELINE=PASS`
- `A15_3_END_TO_END_RESULT_MATCH=PASS`
- `STAGE2N_A15_3_ALL_HBM_EMBEDDING_PIPELINE_XSIM_V1_PASS`

## 13. XSim method and result

Command:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File scripts\run_stage2n_a15_3_integration_xsim_v1.ps1
```

Final evidence directory: `results/stage2n_a15_3/`.

| Item | Result |
|---|---:|
| Vivado/XSim | 2022.1, SW Build 3526262 |
| Compiled sources | 15 |
| `xvlog` RC | 0 |
| `xelab` RC | 0 |
| `xsim` RC | 0 |
| Warnings | 0 |
| Errors | 0 |
| Fatals | 0 |
| Logical lookup requests | 4 |
| AXI AR handshakes | 4 |
| AXI R handshakes | 4 |
| Successful slot injections | 4 |
| Simulation completion time | 42,615 ns |

The retained pre-acceptance `attempt1` stopped at elaboration because a new TB
loop variable was shared by two procedural blocks. The correction introduced a
dedicated monitor variable; it did not modify or implicate functional RTL or
any accepted file. The corrected attempt and final evidence both pass.

## 14. Files created and context updated

Created:

- `rtl/pipeline/dlrm_hbm_pipeline_integration_stage2n_a15_v2.sv`
- `tb/tb_dlrm_hbm_pipeline_integration_stage2n_a15_v3.sv`
- `scripts/run_stage2n_a15_3_integration_xsim_v1.ps1`
- `scripts/run_stage2n_a15_3_integration_xsim_v1.tcl`
- `docs/STAGE2N_A15_3_ALL_HBM_EMBEDDING_PIPELINE_XSIM_V1.md`

Updated only after final XSim PASS:

- `docs/CURRENT_STATE.md`
- `docs/AI_CONTEXT.md`
- `docs/DECISIONS.md`
- `docs/STAGE_HISTORY.md`

Accepted A13, A14, A15.1, and A15.2 RTL, testbenches, runners, documents, and
retained evidence were intentionally left unchanged.

## 15. Limitations and evidence boundary

A15.3 proves only local fake-memory behavior:

- one A14 v2 lookup engine and one AXI master;
- four sequential canonical row reads;
- four bit-exact A13 slot injections;
- request/response/injection hold and error/busy/Host guards;
- complete accepted A13 inference with an independent golden match;
- unchanged A13 pipeline and cycle-counter ABIs.

It does not prove physical HBM, multi-bank behavior, target synthesis or
implementation, XO/xclbin validity, Vitis link, FPGA execution, board behavior,
HBM bandwidth or latency, throughput, power, energy, or speedup. No network,
server, or FPGA-device access occurred.

## 16. Next-stage recommendation

The next separately authorized milestone may be **A15.4 protected target
packaging/build preparation**. It should preserve the accepted A15.3 functional
contract and first establish a versioned public control/kernel boundary. This
stage does not authorize or execute target build/link, XO/xclbin generation,
server access, device programming, physical HBM validation, or performance
work.
