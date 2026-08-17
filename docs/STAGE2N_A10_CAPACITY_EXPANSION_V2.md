# Stage 2N-A10 v2 Recovery

The first A10 checkpoint accidentally committed zero-byte files. The v2 files
are new canonical files and do not overwrite the empty v1 placeholders.

Canonical v2 modules:

- `dlrm_internal_pipeline_axi_lite_adapter_stage2n_a10_v2`
- `dlrm_f37x_rtl_kernel_stage2n_a10_v2`
- `tb_dlrm_f37x_rtl_kernel_stage2n_a10_capacity_v2`

The interface version is `0x00024E11`. Capacity remains:

- descriptors/layers: 8;
- weights: 2048;
- biases: 128.

The capacity regression still exercises the Stage 2M shape
`8→16→8→Interaction(18)→32→16→1`, writes all 1,360 weight locations and
73 bias locations, runs twice, expects result 36, and holds the second result
for twelve backpressure cycles.

All v2 scripts reject missing or zero-byte source files before invoking XSim
or Vivado.
