`timescale 1ns/1ps

module saturating_round #(
  parameter integer IN_WIDTH  = 32,
  parameter integer OUT_WIDTH = 16,
  parameter integer SHIFT     = 4
) (
  input  logic signed [IN_WIDTH-1:0]  in_data,
  output logic signed [OUT_WIDTH-1:0] out_data
);
  logic signed [IN_WIDTH:0] extended_input;
  logic        [IN_WIDTH:0] magnitude;
  logic        [IN_WIDTH:0] rounded_magnitude;
  logic signed [IN_WIDTH:0] shifted_signed;

  localparam logic signed [IN_WIDTH:0] ONE_EXT =
      {{IN_WIDTH{1'b0}}, 1'b1};
  localparam logic signed [IN_WIDTH:0] OUTPUT_MAX_EXT =
      (ONE_EXT <<< (OUT_WIDTH-1)) - 1'b1;
  localparam logic signed [IN_WIDTH:0] OUTPUT_MIN_EXT =
      -(ONE_EXT <<< (OUT_WIDTH-1));

  generate
    if (SHIFT == 0) begin : g_no_shift
      always_comb begin
        extended_input = {in_data[IN_WIDTH-1], in_data};
        magnitude = '0;
        rounded_magnitude = '0;
        shifted_signed = extended_input;
      end
    end else begin : g_round_shift
      always_comb begin
        extended_input = {in_data[IN_WIDTH-1], in_data};
        if (extended_input < 0)
          magnitude = $unsigned(-extended_input);
        else
          magnitude = $unsigned(extended_input);
        rounded_magnitude =
            (magnitude + $unsigned(ONE_EXT <<< (SHIFT-1))) >> SHIFT;
        if (extended_input < 0)
          shifted_signed = -$signed(rounded_magnitude);
        else
          shifted_signed = $signed(rounded_magnitude);
      end
    end
  endgenerate

  always_comb begin
    if (shifted_signed > OUTPUT_MAX_EXT)
      out_data = OUTPUT_MAX_EXT[OUT_WIDTH-1:0];
    else if (shifted_signed < OUTPUT_MIN_EXT)
      out_data = OUTPUT_MIN_EXT[OUT_WIDTH-1:0];
    else
      out_data = shifted_signed[OUT_WIDTH-1:0];
  end

  initial begin
    if (IN_WIDTH <= 0) $error("saturating_round IN_WIDTH must be positive");
    if (OUT_WIDTH <= 0) $error("saturating_round OUT_WIDTH must be positive");
    if (OUT_WIDTH > IN_WIDTH+1)
      $error("saturating_round OUT_WIDTH exceeds extended input width");
    if (SHIFT < 0 || SHIFT > IN_WIDTH)
      $error("saturating_round SHIFT is out of range");
  end
endmodule
