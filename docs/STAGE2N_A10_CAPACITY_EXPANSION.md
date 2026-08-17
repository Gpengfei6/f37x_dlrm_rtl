# Stage 2N-A10 Capacity Expansion

## Why A7 cannot directly run the Stage 2M package

The accepted Stage 2M package has this model shape:

```text
Bottom MLP: 8 → 16 → 8
Interaction: 5 vectors × 8 dimensions → 18 outputs
Top MLP: 18 → 32 → 16 → 1
```

It requires:

- five descriptors;
- 1,360 weight values;
- 73 bias values.

The Stage 2N-A7 pipeline adapter was intentionally sized for the first
automatic-pipeline proof:

- `MAX_LAYERS=4`;
- `MAX_WEIGHT_VALUES=1024`;
- `MAX_BIAS_VALUES=64`.

Therefore, the A7 xclbin cannot safely hold the complete Stage 2M model.

## A10 change

A10 creates a new pipeline adapter and top without modifying A7:

- `MAX_LAYERS=8`;
- `MAX_WEIGHT_VALUES=2048`;
- `MAX_BIAS_VALUES=128`;
- pipeline version `0x00024E10`.

The legacy MLP and standalone interaction windows remain unchanged.

## A10 capacity regression

The XSim regression uses the exact Stage 2M layer dimensions:

```text
8 → 16 → 8 → Interaction(18) → 32 → 16 → 1
```

It loads:

- five descriptors;
- all 1,360 weight addresses, including address 1,359;
- all 73 bias addresses, including address 72;
- four 8-element embeddings;
- an 8-element dense input.

A deterministic sparse parameterization produces final output `36`. The
pipeline is executed twice, and the second final result is held for twelve
backpressure cycles.

This stage is simulation-only. It does not package an XO, link an xclbin,
access a render node, program an FPGA, or reset a board.
