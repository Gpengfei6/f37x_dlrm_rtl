# Stage 2N-A7 — Kernel-Controlled Internal DLRM Pipeline

## Goal

Stage 2N-A7 connects the verified Stage 2N-A5 internal pipeline to the F37X
AXI-Lite kernel register interface. A host now configures the model and inputs,
then issues one pipeline `START` command. The RTL automatically performs:

1. Bottom MLP;
2. five-vector feature interaction;
3. transfer of 18 interaction values into the shared activation buffer;
4. Top MLP;
5. final result delivery through AXI-Lite status/result registers.

This is a simulation-only integration stage. It does not package an XO, link an
xclbin, or access an FPGA board.

## Compatibility

The two previously verified register windows remain unchanged:

- `0x000-0x0FF`: legacy MLP kernel;
- `0x100-0x13F`: standalone feature interaction.

A7 adds a third window:

- `0x180-0x217`: automatic internal DLRM pipeline.

Version registers:

- `0x004 = 0x00024701` — legacy MLP;
- `0x104 = 0x00024E02` — standalone interaction;
- `0x184 = 0x00024E07` — A7 automatic pipeline.

## A7 pipeline register map

| Address | Register | Purpose |
|---:|---|---|
| `0x180` | `PIPE_CONTROL_STATUS` | status read / command write |
| `0x184` | `PIPE_VERSION` | A7 version |
| `0x188` | `PIPE_RESULT_COUNT` | consumed final-result count |
| `0x18C` | `PIPE_PHASE_COUNTS` | phase, Bottom count, interaction count, embedding mask |
| `0x190` | `PIPE_DESC_INDEX` | descriptor staging index |
| `0x194-0x19C` | `PIPE_DESC_WORD0-2` | 96-bit descriptor staging |
| `0x1A0` | `PIPE_ACT_BUFFER` | input activation buffer select |
| `0x1A4` | `PIPE_ACT_CHUNK_INDEX` | activation chunk index |
| `0x1A8` | `PIPE_ACT_LANE_MASK` | activation lane mask |
| `0x1B0-0x1CC` | `PIPE_ACT_DATA0-7` | 256-bit activation staging |
| `0x1D0` | `PIPE_EMB_INDEX` | embedding index 0-3 |
| `0x1D4-0x1E0` | `PIPE_EMB_DATA0-3` | 128-bit embedding staging |
| `0x1E4` | `PIPE_WEIGHT_ADDRESS` | weight address |
| `0x1E8` | `PIPE_WEIGHT_DATA` | signed INT8 weight |
| `0x1EC` | `PIPE_BIAS_ADDRESS` | bias address |
| `0x1F0` | `PIPE_BIAS_DATA` | signed INT24 bias |
| `0x1F4` | `PIPE_BOTTOM_CONFIG` | descriptor base/count and initial buffer |
| `0x1F8` | `PIPE_TOP_CONFIG` | descriptor base/count and top input buffer |
| `0x1FC` | `PIPELINE_CONFIG` | interaction shift |
| `0x200` | `PIPE_RESULT_DATA` | signed INT16 final result |
| `0x204` | `PIPE_RESULT_INDEX` | final result index |
| `0x208` | `PIPE_RESULT_META` | valid, last, index, tag |
| `0x20C` | `PIPE_EMB_LOADED_MASK` | four loaded embedding bits |
| `0x210` | `PIPE_ERROR_CODE` | core and wrapper error information |
| `0x214` | `PIPE_CONFIG_READY` | ready bits for each configuration channel |

## Commands written to 0x180

- `0x0001`: descriptor commit;
- `0x0002`: activation commit;
- `0x0004`: embedding commit;
- `0x0008`: weight commit;
- `0x0010`: bias commit;
- `0x0020`: start the complete internal pipeline;
- `0x0040`: consume the final result;
- `0x0080`: acknowledge core/wrapper error;
- `0x0100`: clear the latched done bit.

## XSim contract

The A7 testbench:

1. reads all three version registers;
2. programs the same verified A5 two-descriptor profile;
3. loads 50 weights, 9 biases, four embeddings, and one Bottom input;
4. starts the complete pipeline using one command;
5. expects final output `-60`;
6. repeats the inference and applies 12 host-side backpressure cycles;
7. verifies latched Bottom count `8` and interaction count `18`;
8. verifies the old MLP and interaction windows are still accessible.

Expected marker:

```text

tb_dlrm_f37x_rtl_kernel_stage2n_a7: PASS runs=2 final=-60 legacy_windows=2
```

## Boundary

An A7 XSim PASS proves AXI-Lite control integration and one-command automatic
execution in RTL simulation. It does not yet prove XO packaging, xclbin link,
F37X shell timing, host runtime compatibility, or board execution.
