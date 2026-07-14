# Fixed-point specification v0

## 1. Stored formats

| Quantity | Stored type | Binary point | Real interpretation |
|---|---:|---:|---:|
| Embedding element | signed INT8 | 4 fractional bits | `raw / 16` |
| Dense weight | signed INT8 | 4 fractional bits | `raw / 16` |
| Dense bias | signed INT24 | 8 fractional bits | `raw / 256` |
| Dense accumulator | signed INT32 | 8 fractional bits | `raw / 256` |
| Dense/ReLU output | signed INT16 | 4 fractional bits | `raw / 16` |

All interfaces carry two's-complement raw integers.  No RTL port uses a floating
type.  Python floating values are diagnostic only.

## 2. Embedding aggregation

Four signed INT8 rows are summed element by element.  The default aggregate
width is `DATA_WIDTH + ceil(log2(NUM_LOOKUPS)) = 10` bits.  The binary point
remains at four fractional bits.  This width exactly represents the default
range `[-512, 508]`; generalized parameter sets apply two's-complement wrapping
at `AGG_WIDTH` after each addition.

## 3. Dense multiply and accumulate

For output neuron `o`:

```text
acc[0]   = sign_extend_32(bias[o])
acc[i+1] = wrap_signed_32(acc[i] + aggregate[i] * weight[o][i])
```

The aggregate/weight product has four plus four fractional bits, matching the
Q*.8 bias and accumulator.  Product operands are signed.  Bias is sign-extended.
Each addition is reduced to `ACC_WIDTH` using two's-complement wrap.  Saturating
accumulation is intentionally **not** used in v0.  A narrow-ACC directed test
forces wraparound; default legal data does not normally overflow INT32.

## 4. Quantization

The INT32 Q*.8 accumulator is converted to INT16 Q*.4:

1. Record the sign and take the magnitude in an extra bit, so `INT_MIN` is safe.
2. Add `2^(OUTPUT_SHIFT-1)` to the magnitude (`OUTPUT_SHIFT=4`).
3. Shift the magnitude right by `OUTPUT_SHIFT`.
4. Restore the sign.
5. Clamp to `[-32768, 32767]`.
6. ReLU clamps a negative quantized result to zero.

This is round-to-nearest with an exact half-LSB rounded away from zero.  Examples
for shift 4 are `23 -> 1`, `24 -> 2`, `-23 -> -1`, and `-24 -> -2`.
Saturation occurs before ReLU.  Python functions in `python/fixed_point.py` are
the executable contract used to produce expected RTL values.

## 5. Overflow and invalid configuration

- Embedding sum and accumulator overflow are deterministic two's-complement wrap.
- Quantized output overflow is deterministic signed saturation.
- ReLU changes only negative post-quantization values.
- RTL elaboration checks require positive widths/dimensions, output width no
  larger than the quantizer's extended input, and accumulator width large enough
  for bias and one full product.
- An ID outside `NUM_EMBED_ROWS` returns a zero row in the phase-1 memory model;
  generated tests use only valid IDs.

