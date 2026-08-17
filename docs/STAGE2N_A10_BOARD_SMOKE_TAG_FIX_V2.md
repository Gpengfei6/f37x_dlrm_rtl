# Stage 2N-A10 Board Smoke v2 Tag Fix

The A10 v1 board run reached a valid final result but rejected metadata tag 4
because the Host incorrectly retained the A9 single-top-layer expectation
`tag == 1`.

The segmented MLP controller tags each dense result with the active descriptor
index. A10 uses:

- bottom descriptors: 0 and 1;
- top descriptors: 2, 3, and 4.

Therefore the final top-layer result must carry tag 4. Host v2 derives the
expected tag as:

```text
TOP_DESCRIPTOR_BASE + TOP_LAYER_COUNT - 1
= 2 + 3 - 1
= 4
```

No RTL, XO, xclbin, timing, or FPGA image change is required. The protected
runner v2 reuses the currently loaded A10 image and skips programming when its
UUID is already present.
