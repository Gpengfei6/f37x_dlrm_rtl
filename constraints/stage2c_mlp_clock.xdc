# Stage 2C multilayer MLP controller OOC synthesis constraint.
# Initial target: 100 MHz.

create_clock \
    -name stage2c_clk \
    -period 10.000 \
    -waveform {0.000 5.000} \
    [get_ports clk]
