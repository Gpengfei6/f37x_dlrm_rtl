`timescale 1ns/1ps

module runtime_relu_quant #(
  parameter integer IN_WIDTH  = 48,
  parameter integer OUT_WIDTH = 16,
  parameter integer SHIFT_WIDTH = (IN_WIDTH <= 1) ? 1 : $clog2(IN_WIDTH+1)
) (
  input  logic                         clk,
  input  logic                         rst,
  input  logic                         in_valid,
  output logic                         in_ready,
  input  logic signed [IN_WIDTH-1:0]   in_data,
  input  logic [SHIFT_WIDTH-1:0]       shift_amount,
  input  logic                         relu_enable,
  output logic                         out_valid,
  input  logic                         out_ready,
  output logic signed [OUT_WIDTH-1:0]  out_data,
  output logic                         invalid_shift
);
  logic signed [IN_WIDTH:0] extended_input;
  logic [IN_WIDTH:0] magnitude;
  logic [IN_WIDTH:0] rounding_bias;
  logic [IN_WIDTH:0] rounded_magnitude;
  logic signed [IN_WIDTH:0] shifted_signed;
  logic signed [OUT_WIDTH-1:0] saturated_next;
  logic signed [OUT_WIDTH-1:0] out_data_next;
  logic invalid_shift_next;

  localparam logic signed [IN_WIDTH:0] ONE_EXT =
      {{IN_WIDTH{1'b0}}, 1'b1};
  localparam logic signed [IN_WIDTH:0] OUTPUT_MAX_EXT =
      (ONE_EXT <<< (OUT_WIDTH-1)) - 1'b1;
  localparam logic signed [IN_WIDTH:0] OUTPUT_MIN_EXT =
      -(ONE_EXT <<< (OUT_WIDTH-1));

  // One-entry elastic stage: accepted inputs emerge after one clock, sustain
  // one result per clock, and remain bit-stable until the output handshake.
  // Arithmetic remains signed round-to-nearest-away-from-zero, followed by
  // signed saturation to OUT_WIDTH and optional ReLU clamping.
  assign in_ready = !out_valid || out_ready;

  always_comb begin : quantize_next
    extended_input = {in_data[IN_WIDTH-1], in_data};
    magnitude = '0;
    rounding_bias = '0;
    rounded_magnitude = '0;
    shifted_signed = '0;
    invalid_shift_next = (shift_amount > IN_WIDTH);

    if (!invalid_shift_next) begin
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

    if (invalid_shift_next)
      saturated_next = '0;
    else if (shifted_signed > OUTPUT_MAX_EXT)
      saturated_next = OUTPUT_MAX_EXT[OUT_WIDTH-1:0];
    else if (shifted_signed < OUTPUT_MIN_EXT)
      saturated_next = OUTPUT_MIN_EXT[OUT_WIDTH-1:0];
    else
      saturated_next = shifted_signed[OUT_WIDTH-1:0];

    if (relu_enable && saturated_next < 0)
      out_data_next = '0;
    else
      out_data_next = saturated_next;
  end

  always_ff @(posedge clk) begin : elastic_output
    if (rst) begin
      out_valid <= 1'b0;
      out_data <= '0;
      invalid_shift <= 1'b0;
    end else if (in_ready) begin
      out_valid <= in_valid;
      if (in_valid) begin
        out_data <= out_data_next;
        invalid_shift <= invalid_shift_next;
      end else begin
        out_data <= '0;
        invalid_shift <= 1'b0;
      end
    end
  end

  initial begin
    if (IN_WIDTH <= 0 || OUT_WIDTH <= 0 || SHIFT_WIDTH <= 0)
      $error("runtime_relu_quant parameters must be positive");
    if (OUT_WIDTH > IN_WIDTH+1)
      $error("runtime_relu_quant OUT_WIDTH exceeds extended input width");
  end
endmodule
