# Stage 2N-A10 Board Smoke Stale-Result Recovery v3

The v2 Host correctly expected final descriptor tag 4, but it checked BUSY
before checking VALID. The previous v1 process exited after reading the valid
final result and before issuing POP. Under this intentional output
backpressure, the pipeline reports both BUSY and VALID:

```text
status = 0x01f28b0d
BUSY = 1
VALID = 1
LAST = 1
result = 36
tag = 4
```

This is a held final result, not an actively computing pipeline.

Host v3 performs safe cleanup in this order:

1. acknowledge any existing error;
2. when VALID is set, read and record the stale result metadata;
3. issue the normal result POP command;
4. wait for BUSY, VALID, and command PENDING to clear;
5. clear DONE when present;
6. continue only after the pipeline is idle.

BUSY without VALID is still treated as a genuine active computation and causes
an immediate refusal. No RTL, XO, xclbin, FPGA programming, or reset is needed.
