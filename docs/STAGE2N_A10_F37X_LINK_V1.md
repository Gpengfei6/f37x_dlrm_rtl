# Stage 2N-A10 F37X Link v1

This stage links the accepted A10 v2 XO into a hardware xclbin for the
Inspur F37X platform.

Configuration:

- platform:
  `inspur_f37x_xdma_201920_3`;
- part inherited from the platform:
  `xcvu37p-fsvh2892-2L-e`;
- kernel:
  `dlrm_f37x_rtl_kernel_stage2n_a10_v2`;
- compute unit:
  `dlrm_a10_1`;
- requested kernel frequency:
  100 MHz;
- pipeline interface version:
  `0x00024E11`;
- model capacity:
  8 descriptors, 2,048 weights, 128 biases.

The link script validates the accepted XO package, performs the Vitis hardware
link, checks xclbin metadata, requires a routed timing summary, and requires
the report to state that all user timing constraints are met.

The script does not open a render node, program an FPGA, or reset a board.
