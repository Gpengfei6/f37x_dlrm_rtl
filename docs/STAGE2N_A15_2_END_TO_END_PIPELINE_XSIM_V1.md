# Stage 2N-A15.2 End-to-End Pipeline XSim V1

Date: 2026-08-26

Status: **LOCAL XSIM PASS**

## Baseline and accepted inputs

- Branch: `work/stage2n-a15-hbm-pipeline-integration`
- Baseline HEAD: `876046c3b27e2c88b36e394d990fff683bda3ad5`
- Accepted A15.1 marker:
  `STAGE2N_A15_1_HBM_PIPELINE_INTEGRATION_V1_PASS`
- Reused accepted A15.1 wrapper:
  `rtl/pipeline/dlrm_hbm_pipeline_integration_stage2n_a15_v1.sv`
- Reused accepted A13 cycle-counter controller:
  `rtl/pipeline/dlrm_internal_pipeline_controller_stage2n_a13_v1.sv`
- Reused accepted A14 v2 lookup:
  `rtl/hbm/dlrm_hbm_embedding_lookup_stage2n_a14_v2.sv`

No accepted A13, A14, or A15.1 RTL was modified. The A15.1 wrapper already
exposed every controller-level configuration, START, result, phase/count,
cycle-counter, error, lookup, and AXI AR/R signal required by A15.2, so no A15
v2 RTL wrapper was needed.

## Objective and architecture

A15.2 proves one complete local inference in which the embedding value returned
through the A14 v2 lookup is actually consumed as A13 embedding slot 0:

```text
fake AXI memory row 37 -> A14 v2 lookup -> A15.1 retained injection
                                             |
                                             v
                                   A13 embedding slot 0

dense input -> Bottom MLP -> Interaction vector 0
slot 0      ----------------> Interaction vector 1
Host slot 1 ----------------> Interaction vector 2
Host slot 2 ----------------> Interaction vector 3
Host slot 3 ----------------> Interaction vector 4
                                  |
                                  v
                       Feature Interaction -> Top MLP -> final result
```

The testbench observes the accepted A13 controller's real Interaction vector
load handshake. It confirms that vector 0 is the Bottom output and vectors 1
through 4 are the four stored embeddings. The HBM row is not bypassed into the
Top MLP.

## Exact deterministic sample

The sample is the accepted A13 cycle-counter test network:

- Bottom descriptors: `8 -> 16 -> 8`;
- Feature Interaction: five 8-element vectors -> 18 outputs;
- Top descriptors: `18 -> 32 -> 16 -> 1`;
- descriptor count: 5;
- configured weight capacity used: addresses 0 through 1359;
- configured biases: addresses 0 through 72, all zero;
- descriptor shift: zero for all five layers;
- ReLU: enabled for the first four layers and disabled for the final layer;
- dense input: `[1,2,3,4,5,6,7,8]`;
- `interaction_shift = 0`.

The sparse unit weights copy the first eight values through both Bottom layers,
copy the first eight Interaction outputs through the first two Top layers, and
sum those eight values in the final Top layer.

## Embedding source substitution

The accepted A13 sample previously configured all four embeddings as zero by
the Host. A15.2 changes only the source of slot 0:

- local fake-memory row: 37;
- row address: `TABLE_BASE + (37 << 4)`;
- slot 0, from A14 v2: `[0,0,0,0,0,0,0,0]`;
- slot 1, from Host: `[0,0,0,0,0,0,0,0]`;
- slot 2, from Host: `[0,0,0,0,0,0,0,0]`;
- slot 3, from Host: `[0,0,0,0,0,0,0,0]`.

The local fake row is intentionally bit-identical to the accepted sample's old
Host slot-0 vector. It is testbench data and must not be confused with the
separate canonical A14.7 physical-table row 37, whose accepted value was
`[40,41,42,43,44,45,46,47]`.

## Independent golden calculation

The golden is derived before observing the RTL result. Because all embeddings
are zero, the first eight Interaction outputs are the Bottom vector and every
pairwise dot product is zero. The configured Top layers copy those first eight
values and the final layer computes:

```text
EXPECTED_RESULT = 1 + 2 + 3 + 4 + 5 + 6 + 7 + 8 = 36
```

This matches the pre-existing accepted A10/A13 Testbench and board/software
golden for the same sample. The new A15.2 bench calculates the sum independently
and does not derive its expected value from XSim output.

## Self-checking cases

All required cases passed:

1. one row-37 lookup produced one AXI AR and one AXI R handshake;
2. the successful 128-bit response was injected into A13 slot 0;
3. Host-configured slots 1 through 3 remained unchanged;
4. `embedding_loaded_mask` reached `4'hF` before START;
5. START ready was false before slot 0 and true after all four slots loaded;
6. Bottom produced eight outputs and a non-zero cycle count;
7. all five exact Interaction vectors were loaded in the audited order;
8. Interaction produced 18 outputs and Top completed;
9. final data/index/last/tag matched `36/0/1/4`;
10. all four cycle counters were non-zero and froze with the final result;
11. the ABI guard retained `0x218/0x21C/0x220/0x224`;
12. all four embedding values and loaded bits remained stable after inference.

The final result and cycle counters were additionally held stable for eight
cycles of output backpressure before result retirement.

## Cycle-counter evidence

| Counter | XSim value |
|---|---:|
| Bottom | 322 |
| Interaction | 100 |
| Top | 744 |
| Total | 1174 |
| Controller overhead, `Total-Bottom-Interaction-Top` | 8 |

These values exactly match the accepted A13 definition and sample. The counters
are functional observability evidence only. They are not an A15 performance or
speedup measurement.

## Files added

- `tb/tb_dlrm_hbm_pipeline_integration_stage2n_a15_v2.sv`
- `scripts/run_stage2n_a15_2_pipeline_xsim_v1.ps1`
- `scripts/run_stage2n_a15_2_pipeline_xsim_v1.tcl`
- `docs/STAGE2N_A15_2_END_TO_END_PIPELINE_XSIM_V1.md`

## XSim command and retained evidence

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File scripts\run_stage2n_a15_2_pipeline_xsim_v1.ps1
```

Accepted local evidence directory:
`results/stage2n_a15_2/pipeline_xsim_v1/`.

The runner compiles 15 exact sources and independently checks the final marker,
all component markers, the result, every cycle value, the A13 source ABI, and
anchored warning/error/fatal records.

## XSim result

- Vivado/XSim: 2022.1, SW Build 3526262;
- `xvlog`: exit code 0;
- `xelab`: exit code 0;
- `xsim`: exit code 0;
- warning count: 0;
- anchored error/fatal count: 0;
- expected result: 36;
- actual result: 36;
- simulation completion time: 41,716 ns.

## PASS markers

- `A15_2_HBM_LOOKUP=PASS`
- `A15_2_SLOT0_INJECTION=PASS`
- `A15_2_HOST_SLOT123_PRESERVED=PASS`
- `A15_2_EMBEDDING_MASK=PASS`
- `A15_2_BOTTOM_MLP=PASS`
- `A15_2_INTERACTION=PASS`
- `A15_2_TOP_MLP=PASS`
- `A15_2_FINAL_RESULT_MATCH=PASS`
- `A15_2_CYCLE_COUNTERS=PASS`
- `A15_2_A13_ABI_PRESERVED=PASS`
- `STAGE2N_A15_2_END_TO_END_PIPELINE_XSIM_V1_PASS`

## Limitations and evidence boundary

- physical HBM validation: **NOT RUN**;
- target build: **NOT RUN**;
- XO/xclbin build or validation: **NOT RUN**;
- FPGA programming/device access: **NOT RUN**;
- board validation: **NOT RUN**;
- A15 public AXI4-Lite/kernel-top integration: **NOT IMPLEMENTED**;
- multi-table/multi-bank/cache/burst/multiple-outstanding/INT8 work:
  **NOT IMPLEMENTED**;
- performance, latency, bandwidth, throughput, power, or speedup:
  **NOT CLAIMED**.

The earlier A14.7 physical lookup remains valid standalone evidence, but it is
not physical evidence for this local A15.2 integrated inference.

## Next stage

Any public F37X control-top integration, target build/link, xclbin, or board run
requires a separately authorized stage. Functional equivalence must remain the
first gate; multi-bank, multi-table, caching, and performance work remain out of
scope until that integrated path is accepted.
