# Stage 2N-A11 256-Sample Automatic-Pipeline Board Regression v1

> 恢复状态：历史代码/总结存在，但当前恢复阶段未重新验证。当前本地缺少对应的原始 board status/log/CSV 证据。

This stage runs the verified `F37XPB1` v2 asset through the already-linked and
already-programmed Stage 2N-A10 automatic pipeline.

The C++ Host:

- parses and validates the 128-byte asset header and payload FNV1a64;
- programs five descriptors, 1,360 INT8 weights, and 73 signed biases once;
- writes each sample's eight dense inputs and four resolved embedding vectors;
- sets interaction shift 11;
- issues one automatic-pipeline start command per sample;
- verifies final result index 0, descriptor tag 4, bottom count 8, and
  interaction count 18;
- compares all 256 FPGA logits and predictions with the software reference;
- checks the expected classification result of 228/256 (`0.890625`);
- writes a per-sample CSV.

The protected runner is locked to:

```text
xbutil index 2
BDF 0000:9b:00.1
render node /dev/dri/renderD129
UUID f7a23117-5218-4fba-adb5-f093b596df03
```

It uses the existing A10 image and never programs, resets, or rolls back the
FPGA. Before any FPGA access, it requires an exact interactive authorization.

The claim remains limited to the deterministic synthetic Stage 2M
trained-model regression package; it is not real Criteo evidence.
