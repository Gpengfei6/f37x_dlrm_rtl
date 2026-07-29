# Stage 2N-A11 Final Acceptance v1

Stage 2N-A11 closes the numerical-regression gap left by Stage 2N-A10.

Accepted execution path:

```text
8 dense values
+ four resolved 8-value embedding vectors
-> Bottom MLP 8 -> 16 -> 8
-> 18-value interaction
-> Top MLP 18 -> 32 -> 16 -> 1
-> final logit
```

The F37X board test used:

- xbutil index 2;
- BDF `0000:9b:00.1`;
- render node `/dev/dri/renderD129`;
- A10 xclbin UUID `f7a23117-5218-4fba-adb5-f093b596df03`;
- CU `dlrm_f37x_rtl_kernel_stage2n_a10_v2:dlrm_a10_1`.

Final board regression:

- 256 automatic-pipeline start commands;
- 256/256 exact FPGA logits;
- 256/256 exact FPGA predictions;
- 256/256 correct result indices;
- 256/256 correct final descriptor tags;
- 256/256 correct bottom-output counts;
- 256/256 correct interaction-output counts;
- 228/256 classification accuracy (`0.890625`);
- measured batch Host time recorded in the evidence status.

The test programmed five descriptors, 1,360 INT8 weights, and 73 biases once,
then executed all 256 samples. The board firewall remained GOOD and the CU
returned to IDLE. No FPGA programming, reset, rollback, or access to another
device occurred.

The claim is limited to the deterministic synthetic Stage 2M trained-model
package. This is not real Criteo dataset evidence.
