# Stage 2N-A11 Pipeline Batch Asset v2

The v1 builder wrote the seven-byte literal `F37XPB1` into an eight-byte
`struct` field. Python `struct.pack("<8s", ...)` padded the stored value with a
zero byte, while the verifier compared the unpacked eight-byte value against
the original seven-byte constant. This caused:

```text
output magic mismatch
```

Builder v2 defines the binary magic as exactly eight bytes:

```text
F37XPB1\0
```

and asserts its length before any asset is generated.

No model semantics, descriptor layout, weights, biases, samples, software
reference calculations, or FPGA interface have changed. Version 2 writes to
new `assets_v2` and `stage2n_a11_assets_v2` directories so the historical v1
failure remains intact.

This stage performs no FPGA access, programming, or reset.
