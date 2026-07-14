# Stage-1 RTL static review

Date: 2026-07-14.  This is a source review, not compiler, simulation, synthesis,
timing, or F37X evidence.

## Compile order and language boundary

The required order is package, common arithmetic/FIFO, compute, memory,
pipeline, top, and then testbenches.  `run_xsim_stage1.tcl` and the Icarus/
Verilator lists in `run_all_local.ps1` encode this order.  External vectors are
flattened packed ports; unpacked arrays remain internal, reducing Vivado 2020.2
port compatibility risk.  Core RTL uses `always_ff`, `always_comb`, constant
generate loops, indexed packed slices, and `$readmemh`, all common SV-2012
constructs supported by the intended flow but still awaiting real compilation.

## Per-file findings

| File | Reviewed properties | Finding/action |
|---|---|---|
| `dlrm_config_pkg.sv` | localparam types, `$clog2`, compile order | Positive integer constants; package is first in top builds. |
| `rv_fifo.sv` | count/pointers, full/empty, simultaneous pop/push, loop, reset | No combinational loop; full replacement transfer preserves count.  Test now forces pointer wraps and protocol-correct random backpressure. |
| `saturating_round.sv` | sign extension, `INT_MIN`, shift/round constants, saturation, generate completeness | Magnitude-domain rounding is intentional and fully assigned; directed positive/negative ties and limits exist. |
| `relu_quant.sv` | operation order, signed comparison, multiple drivers | Quantization/saturation precedes signed negative clamp; one combinational driver. |
| `dot_product_core.sv` | signed slices/products, sign extension, wrap, elastic handshake | Signed internal arrays make multiplication explicit.  ACC-width assignment gives two's-complement wrap after each addition.  Same-edge output retirement/input replacement is tested. |
| `dense_layer_core.sv` | local memories, dynamic address, FSM, reset, hold behavior | One dot core is reused.  Output buffer is stable in output state; blocked output also blocks the next input and is now tested. |
| `embedding_mem_model.sv` | `$readmemh`, one-cycle response, invalid ID, elastic replacement | Flat internal array avoids unpacked port/file ambiguity.  Response retirement plus next request on one edge is tested. |
| `minimal_recommendation_pipeline.sv` | ID slice order, response sequencing, signed aggregate, FSM, backpressure | Lane 0 is LSB; each row is consumed once; addition is modulo `AGG_WIDTH`.  Source hold while sink is blocked is tested. |
| `dlrm_minimal_top.sv` | package references, public ports, wrapper-only behavior | No public-interface change; package-qualified defaults require package-first compile. |

No source-level multiple driver, inferred latch, ready/valid combinational cycle,
or vendor algorithm IP was found.  Parameter-invalid negative replication can
still fail during elaboration before an `initial $error`; such parameter sets are
outside the documented valid domain.

## Independent fixed-point derivation

- Four INT8 values span `[-512, 508]`; signed 9 bits are insufficient and signed
  10 bits are sufficient.
- Aggregate Q*.4 multiplied by weight Q*.4 produces Q*.8, exactly matching Bias
  and accumulator.  Bias is sign-extended and added before products without a
  shift.
- For shift four, absolute-magnitude remainder 8 is the half tie and increments
  magnitude for both signs.  The Python regression independently re-derives all
  values from -4096 through 4096.
- Saturation occurs after sign restoration and before ReLU.
- Sequential ACC assignments and Python `wrap_signed` are both modulo `2^N`;
  directed INT16 and INT32 regressions re-derive the final residues.
- Packed lane `i` occupies `[i*WIDTH +: WIDTH]`; hex/JSON round trips verify lane
  zero is least significant and signed hex files decode as two's complement.

## Testbench portability review

All eight benches now contain a global timeout, explicit `tb_*: PASS`, `$fatal`
failure paths, reset initialization, and directed backpressure where applicable.
The FIFO random source now seeds once and calls `$urandom()` thereafter; it also
holds valid/data while stalled, avoiding simulator-dependent reseeding and an
invalid producer model.  Delay statements exist only in testbenches.

Remaining confirmation requires real `xvlog`, `xelab`, and `xsim` logs.
