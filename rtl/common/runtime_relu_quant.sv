`timescale 1ns/1ps

module runtime_relu_quant #(
  parameter integer IN_WIDTH  = 48,
  parameter integer OUT_WIDTH = 16,
  parameter integer SHIFT_WIDTH = (IN_WIDTH <= 1) ? 1 : $clog2(IN_WIDTH+1)
) (
  input  logic signed [IN_WIDTH-1:0]   in_data,
  input  logic [SHIFT_WIDTH-1:0]       shift_amount,
  input  logic                         relu_enable,
  output logic signed [OUT_WIDTH-1:0]  out_data,
  output logic                         invalid_shift
);
  logic signed [IN_WIDTH:0] extended_input;
  logic [IN_WIDTH:0] magnitude;
  logic [IN_WIDTH:0] rounding_bias;
  logic [IN_WIDTH:0] rounded_magnitude;
  logic signed [IN_WIDTH:0] shifted_signed;
  logic signed [OUT_WIDTH-1:0] saturated;

  localparam logic signed [IN_WIDTH:0] ONE_EXT =
      {{IN_WIDTH{1'b0}}, 1'b1};
  localparam logic signed [IN_WIDTH:0] OUTPUT_MAX_EXT =
      (ONE_EXT <<< (OUT_WIDTH-1)) - 1'b1;
  localparam logic signed [IN_WIDTH:0] OUTPUT_MIN_EXT =
      -(ONE_EXT <<< (OUT_WIDTH-1));

  always_comb begin
    extended_input = {in_data[IN_WIDTH-1], in_data};
    magnitude = '0;
    rounding_bias = '0;
    rounded_magnitude = '0;
    shifted_signed = '0;
    invalid_shift = (shift_amount > IN_WIDTH);

    if (!invalid_shift) begin
      if (shift_amount == 0) begin
        shifted_signed = extended_input;
      end else begin
        if (extended_input < 0)
          magnitude = $unsigned(-extended_input);
        else
          magnitude = $unsigned(extended_input);
        rounding_bias = $unsigned(ONE_EXT <<< (shift_amount-1'b1));
        rounded_magnitude = (magnitude + rounding_bias) >> shift_amount;
        if (extended_input < 0)
          shifted_signed = -$signed(rounded_magnitude);
        else
          shifted_signed = $signed(rounded_magnitude);
      end
    end

    if (invalid_shift)
      saturated = '0;
    else if (shifted_signed > OUTPUT_MAX_EXT)
      saturated = OUTPUT_MAX_EXT[OUT_WIDTH-1:0];
    else if (shifted_signed < OUTPUT_MIN_EXT)
      saturated = OUTPUT_MIN_EXT[OUT_WIDTH-1:0];
    else
      saturated = shifted_signed[OUT_WIDTH-1:0];

    if (relu_enable && saturated < 0)
      out_data = '0;
    else
      out_data = saturated;
  end

  initial begin
    if (IN_WIDTH <= 0 || OUT_WIDTH <= 0 || SHIFT_WIDTH <= 0)
      $error("runtime_relu_quant parameters must be positive");
    if (OUT_WIDTH > IN_WIDTH+1)
      $error("runtime_relu_quant OUT_WIDTH exceeds extended input width");
  end
endmodule
