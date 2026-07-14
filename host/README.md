# Future C++11/XRT host boundary

No host implementation is included in phase 0/1.  A future C++11 program will:

1. select the `inspur_f37x_xdma_201920_3` device and load a user-built `.xclbin`;
2. allocate buffers with explicit HBM bank placement;
3. serialize packed IDs/model data using the lane order in
   `docs/interface_spec_v0.md`;
4. migrate input, start the RTL kernel, wait, migrate output, and compare it with
   Python fixed-point expected data;
5. record platform, XRT, xclbin hash, clocks, timing, and run logs.

The eventual kernel ABI must be documented separately before implementation.
This directory intentionally contains no XRT calls and no executable server
commands.

