# Stage 2N-A10 Final Evidence Collector v4

Collector v3 correctly found the XO packaging Tcl file, but validated the board
status file using labels from the human-readable console summary:

```text
TARGET=...
UUID=...
CU=...
```

The protected board runner's machine-readable status file actually uses:

```text
TARGET_INDEX=2
TARGET_BDF=0000:9b:00.1
TARGET_RENDER=/dev/dri/renderD129
XCLBIN_UUID=...
KERNEL=...
COMPUTE_UNIT=dlrm_a10_1
IP_NAME=kernel:instance
NO_FPGA_RESET=1
NO_OTHER_DEVICE_ACCESS=1
```

Collector v4 validates that real schema and writes to the new directory:

```text
docs/evidence/stage2n_a10_final_v4
```

It preserves the committed v3 failure status. Stale-result recovery is checked
when present in the board log but is not required for every otherwise valid
board run. The collector performs no FPGA access, programming, or reset.
