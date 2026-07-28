# Stage 2N-A6 internal DLRM pipeline OOC timing constraints.
#
# Target: 100 MHz on the F37X VU37P device.
# The 2 ns interface budget is an OOC assumption for external register/control
# logic. It is not a board pin assignment and does not model the F37X shell.

create_clock \
    -name stage2n_a6_clk \
    -period 10.000 \
    -waveform {0.000 5.000} \
    [get_ports clk]

set_clock_uncertainty 0.200 [get_clocks stage2n_a6_clk]

set stage2n_a6_non_clock_inputs \
    [remove_from_collection [all_inputs] [get_ports clk]]

set_input_delay \
    -clock stage2n_a6_clk \
    -max 2.000 \
    $stage2n_a6_non_clock_inputs

set_input_delay \
    -clock stage2n_a6_clk \
    -min 0.000 \
    $stage2n_a6_non_clock_inputs

set_output_delay \
    -clock stage2n_a6_clk \
    -max 2.000 \
    [all_outputs]

set_output_delay \
    -clock stage2n_a6_clk \
    -min 0.000 \
    [all_outputs]
