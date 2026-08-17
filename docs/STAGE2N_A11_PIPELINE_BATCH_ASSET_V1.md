# Stage 2N-A11 Real-Model Pipeline Batch Asset v1

> 恢复状态：历史代码/总结存在，但当前恢复阶段未重新验证。当前本地缺少对应的原始 status/log/CSV 证据。

This stage converts the verified Stage 2M `F37XHD1` trained-model package into
an input asset designed for the Stage 2N-A10 automatic pipeline.

The source model contains:

- bottom MLP `8 -> 16 -> 8`;
- four embedding tables with 8-value vectors;
- 18-value interaction output;
- top MLP `18 -> 32 -> 16 -> 1`;
- 256 deterministic test samples;
- 1,360 INT8 weights;
- 73 INT24-compatible biases.

The generated `F37XPB1` asset contains:

- five hardware descriptor words;
- one contiguous weight image;
- one contiguous bias image;
- every sample's dense input;
- categorical IDs for provenance;
- four resolved embedding vectors for direct pipeline programming;
- expected bottom output, interaction vector, final logit, and prediction.

Before writing the asset, the builder independently recomputes all 256 bottom
MLP results, all 256 interactions, and all 256 top MLP results using the exact
integer rounding, saturation, ReLU, and interaction-shift semantics. It also
requires the known classification result of 228/256 (`0.890625`).

This stage does not access, program, or reset the FPGA. The resulting asset is
the stable input contract for the A11 automatic-pipeline C++ Host.
