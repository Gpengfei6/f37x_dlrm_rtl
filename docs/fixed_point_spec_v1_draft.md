# Fixed-point specification v1 draft — Stage-2 candidate

## Status

This is a candidate Stage-2 extension.  It does not modify or supersede
`fixed_point_spec_v0.md`, which remains the approved GATE-1 contract.  The v1
draft adds a parameterized internal accumulator and per-job shift/ReLU metadata
while preserving all external formats and operation ordering.

## Formats and binary point

| Quantity | Compatibility configuration | Stage-2 default |
|---|---|---|
| Activation | Existing signed width and Q format | Signed INT16 with 4 fractional bits unless a layer contract says otherwise |
| Weight | Signed INT8 Q3.4 | unchanged |
| Product | Signed product, 8 fractional bits | unchanged |
| Bias | Signed INT24 Q15.8 | unchanged |
| Accumulator | Signed INT32, 8 fractional bits | Signed INT48, 8 fractional bits |
| Output | Signed INT16, descriptor-selected shift | unchanged width |

Bias is sign-extended directly because product and bias both have eight
fractional bits.  ACC48 widening adds integer guard bits only; it does not
rescale products or bias.

## Accumulation modes

### `compat_int32_wrap`

After every lane addition and every reduction/bias addition, retain the low 32
bits and reinterpret them as signed two's complement.  This reproduces the v0
modulo-`2^32` behavior.  No early saturation is allowed.

### `wide_int48`

Sign-extend each signed product and bias to 48 bits.  After every addition,
retain the low 48 bits.  For all reviewed dimensions through D=1024 with the
declared operand widths, verification must compare the result with the exact
mathematical sum and identify any case requiring more than 48 bits.  The five
architecture-review layers require at most 33 signed bits.

`ACC_WIDTH` remains a parameter so both modes use the same structural engine.
This document makes no DSP mapping claim.

## Quantization order

For an accepted descriptor with shift S:

1. Complete the full signed dot product and aligned bias accumulation.
2. If S is zero, use the accumulator unchanged.
3. Otherwise round an arithmetic division by `2^S` to nearest, ties away from
   zero, using magnitude-domain bias exactly as v0.
4. Saturate to the signed INT16 range.
5. If `relu_enable=1`, replace a negative saturated value with zero; otherwise
   preserve the saturated signed value.

No rounding, truncation, saturation, or ReLU may occur between chunks or in the
reduction tree.  Shift values outside the implemented legal range cause an
explicit invalid-descriptor error, not an implicit mask/modulo operation.

## Layer metadata

`output_shift` and `relu_enable` are captured with the job descriptor.  The
phase-1-compatible 8-to-4 configuration uses shift four and ReLU enabled.  Other
layer values are interface capability only until the trained-model scales are
approved.

## Required evidence before finalization

- Python and RTL bit equality in ACC32 and ACC48 modes;
- positive/negative product and bias extrema;
- exact wrap boundaries and a case distinguishing 32 from 48 bits;
- positive and negative rounding ties;
- saturation edges and ReLU on/off;
- formal per-layer scale decisions from the trained model;
- Vivado synthesis evidence for the selected width and implementation.

Until that evidence and a human review exist, this file remains a draft and v0
remains authoritative for GATE-1 behavior.
