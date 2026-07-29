# Stage 2N-A10 Final Acceptance

Stage 2N-A10 expands the automatic DLRM pipeline so that it can represent the
Stage 2M trained-model shape:

```text
Bottom MLP: 8 -> 16 -> 8
Interaction: 5 vectors x 8 dimensions -> 18 values
Top MLP: 18 -> 32 -> 16 -> 1
```

Accepted capacity:

- 8 layer descriptors;
- 2,048 weight values;
- 128 bias values.

Validated Stage 2M-shaped deterministic configuration:

- 5 descriptors;
- 1,360 weights;
- 73 biases;
- 4 embedding vectors;
- 8 dense input values.

Acceptance chain:

1. XSim completed two runs and returned final result 36.
2. RTL kernel XO packaging passed interface and source-content checks.
3. The F37X hardware xclbin linked at 100 MHz.
4. Routed timing met all specified constraints.
5. Board smoke passed twice on index 2 / BDF 0000:9b:00.1.
6. Both board runs returned result 36 with final descriptor tag 4.
7. Twelve result backpressure reads were tolerated.
8. No FPGA reset was performed and no other board was accessed.

This milestone proves capacity, register programming, automatic stage
sequencing, result metadata, and deterministic five-layer execution on the
F37X board. It does not yet prove numerical equivalence for all 256 samples of
the trained Stage 2M model. That batch regression is the next mainline stage.
