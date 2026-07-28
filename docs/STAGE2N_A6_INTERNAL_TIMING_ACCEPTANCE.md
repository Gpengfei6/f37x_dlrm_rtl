# Stage 2N-A6 Internal Timing Acceptance

## Decision

Stage 2N-A6 is accepted against the timing intrinsic to the internal DLRM RTL
pipeline:

- register-to-register setup timing;
- register-to-register hold timing;
- complete routing;
- no inferred latches;
- no DRC errors.

Top-level output-port hold timing is reported but is not used as the A6 internal
acceptance condition.

## Why output hold is excluded here

The A6 implementation is an out-of-context block. Its top-level output ports are
not yet connected to the final AXI/XRT/F37X shell registers and clocking
structure. The earlier diagnostic established:

- 148 negative hold paths;
- all 148 terminate at output ports;
- zero input-related hold paths;
- zero internal register-to-register hold paths;
- path class `pin -> port`.

Therefore those paths describe the temporary OOC boundary assumption, not an
internal Bottom MLP, interaction-engine, Top MLP, or controller hold failure.

## Established A6 implementation facts

From the existing routed checkpoint:

- target part: `xcvu37p-fsvh2892-2L-e`;
- target clock: 100 MHz;
- full OOC setup WNS: `+1.482 ns`;
- unrouted nets: `0`;
- latches: `0`;
- DRC errors: `0`;
- approximate direct primitive counts:
  - LUT: `7156`;
  - FF: `3553`;
  - RAMB18: `49`;
  - RAMB36: `0`;
  - DSP48: `17`.

The final internal acceptance script independently checks internal setup and
hold paths from the routed checkpoint.

## Boundary of the conclusion

An A6 PASS means that the verified Stage 2N-A5 internal pipeline is feasible on
the VU37P at 100 MHz as an internal RTL block.

It does not yet prove:

- timing of a future AXI or XRT wrapper;
- timing inside the complete F37X shell;
- host-to-FPGA throughput;
- embedding-table or HBM bandwidth;
- full model accuracy on a new board-integrated automatic pipeline.

Output interface timing must be re-evaluated after the block is connected to its
real shell-side registers and clocks.
