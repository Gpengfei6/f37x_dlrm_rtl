# Stage 2N-A13 full AXI-Lite kernel OOC timing constraint.
#
# The 2 ns interface budget models surrounding registered control logic only.
# It is not a board-pin, PCIe-shell, HBM, or physical F37X constraint.

create_clock \
    -name stage2n_a13_clk \
    -period 10.000 \
    -waveform {0.000 5.000} \
    [get_ports ap_clk]

set_clock_uncertainty 0.200 [get_clocks stage2n_a13_clk]

set stage2n_a13_non_clock_inputs \
    [get_ports -filter {DIRECTION == IN && NAME != ap_clk}]

set_input_delay \
    -clock stage2n_a13_clk \
    -max 2.000 \
    $stage2n_a13_non_clock_inputs

set_input_delay \
    -clock stage2n_a13_clk \
    -min 0.000 \
    $stage2n_a13_non_clock_inputs

set_output_delay \
    -clock stage2n_a13_clk \
    -max 2.000 \
    [all_outputs]

set_output_delay \
    -clock stage2n_a13_clk \
    -min 0.000 \
    [all_outputs]
