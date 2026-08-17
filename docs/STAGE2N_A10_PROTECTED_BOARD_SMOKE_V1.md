# Stage 2N-A10 Protected F37X Board Smoke v1

Target is locked to index `2`, BDF `0000:9b:00.1`, render node `/dev/dri/renderD129`.

The new image is UUID `f7a23117-5218-4fba-adb5-f093b596df03`, kernel `dlrm_f37x_rtl_kernel_stage2n_a10_v2`, CU `dlrm_a10_1`.

The protected script accepts only the verified A7 image as the source image. It requires firewall GOOD, source CU IDLE, no render-node handle, empty HBM[0], an unchanged 30-second activity guard, and three exact confirmations. It never resets the FPGA and never performs automatic rollback.

The smoke loads the Stage 2M-shaped deterministic model `8→16→8→Interaction(18)→32→16→1`, writes five descriptors, 1,360 weights, 73 biases, four embeddings, runs twice, expects final result 36, and holds the second result for twelve host reads.

Execution requires a new explicit Stage 2N-A10 board-programming authorization.
