# Stage 2N-A9 — Protected F37X Automatic-Pipeline Board Smoke

## Authorization boundary

Stage 2N-A9 is authorized only for:

- xbutil index `2`;
- BDF `0000:9b:00.1`;
- render node `/dev/dri/renderD129`.

The flow must not access devices 0, 1, or 3 and must not reset any FPGA.

## Image

- kernel: `dlrm_f37x_rtl_kernel_stage2n_a7`;
- compute unit: `dlrm_a7_1`;
- xclbin UUID: `5d4ac982-14e3-40fb-afaa-f04ba82dce61`;
- xclbin size: 43,550,638 bytes;
- requested frequency: 100 MHz.

## Host test

The host uses low-level XRT HAL register access:

```text
xclOpen
xclOpenContext
xclIPName2Index
xclRegRead
xclRegWrite
```

It verifies:

1. legacy MLP version `0x00024701`;
2. standalone interaction version `0x00024E02`;
3. automatic-pipeline version `0x00024E07`;
4. descriptor, weight, bias, embedding, and activation loading;
5. two one-command pipeline executions;
6. final result `-60`;
7. Bottom output count `8`;
8. interaction output count `18`;
9. twelve host backpressure reads while the final result remains stable;
10. return to an idle, error-free state.

## Protected runner

The runner:

- validates the A8 PASS and final acceptance records;
- validates xclbin size, UUID, kernel, CU, and SHA256 format;
- compiles the host before programming;
- checks index/BDF/render-node mapping;
- checks firewall status;
- rejects an active render node;
- accepts only recognized idle source images;
- performs a 30-second read-only activity guard;
- requires exact interactive confirmations;
- programs only BDF `0000:9b:00.1`;
- runs the host and verifies the PASS marker;
- checks firewall, UUID, and CU idle state afterward.

There is no FPGA reset and no automatic rollback.
