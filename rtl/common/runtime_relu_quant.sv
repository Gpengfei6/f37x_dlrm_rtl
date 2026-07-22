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
  logic signed [IN_WIDTH:0] extended_input_next;
  logic [IN_WIDTH:0] magnitude_next;
  logic [IN_WIDTH:0] rounding_bias_next;
  logic [IN_WIDTH:0] rounded_magnitude_next;
  logic invalid_shift_stage1_next;

  logic stage1_valid;
  logic stage1_ready;
  logic [IN_WIDTH:0] rounded_magnitude_stage1;
  logic [SHIFT_WIDTH-1:0] shift_amount_stage1;
  logic input_negative_stage1;
  logic relu_enable_stage1;
  logic invalid_shift_stage1;

  logic output_stage_ready;
  logic [IN_WIDTH:0] shifted_magnitude_next;
  logic signed [IN_WIDTH:0] shifted_signed_next;
  logic signed [OUT_WIDTH-1:0] saturated_next;
  logic signed [OUT_WIDTH-1:0] out_data_next;

  localparam logic signed [IN_WIDTH:0] ONE_EXT =
      {{IN_WIDTH{1'b0}}, 1'b1};
  localparam logic signed [IN_WIDTH:0] OUTPUT_MAX_EXT =
      (ONE_EXT <<< (OUT_WIDTH-1)) - 1'b1;
  localparam logic signed [IN_WIDTH:0] OUTPUT_MIN_EXT =
      -(ONE_EXT <<< (OUT_WIDTH-1));

  // Two-entry elastic pipeline: accepted inputs emerge after two registered
  // stages, sustain one result per clock, and remain bit-stable until the
  // output handshake. The first stage ends after magnitude rounding; the
  // second performs the runtime right shift, sign restore, saturation and ReLU.
  // Arithmetic remains signed round-to-nearest-away-from-zero, followed by
  // signed saturation to OUT_WIDTH and optional ReLU clamping.
  assign output_stage_ready = !out_valid || out_ready;
  assign stage1_ready = !stage1_valid || output_stage_ready;
  assign in_ready = stage1_ready;

  always_comb begin : round_magnitude_next
    extended_input_next = {in_data[IN_WIDTH-1], in_data};
    if (extended_input_next < 0)
      magnitude_next = $unsigned(-extended_input_next);
    else
      magnitude_next = $unsigned(extended_input_next);
    rounding_bias_next = '0;
    rounded_magnitude_next = magnitude_next;
    invalid_shift_stage1_next = (shift_amount > IN_WIDTH);

    if (invalid_shift_stage1_next) begin
      rounded_magnitude_next = '0;
    end else if (shift_amount != 0) begin
      rounding_bias_next =
          $unsigned(ONE_EXT <<< (shift_amount-1'b1));
      rounded_magnitude_next = magnitude_next + rounding_bias_next;
    end
  end

  always_comb begin : shift_saturate_relu_next
    shifted_magnitude_next = '0;
    shifted_signed_next = '0;
    if (!invalid_shift_stage1) begin
      shifted_magnitude_next =
          rounded_magnitude_stage1 >> shift_amount_stage1;
      if (input_negative_stage1)
        shifted_signed_next = -$signed(shifted_magnitude_next);
      else
        shifted_signed_next = $signed(shifted_magnitude_next);
    end

    if (invalid_shift_stage1)
      saturated_next = '0;
    else if (shifted_signed_next > OUTPUT_MAX_EXT)
      saturated_next = OUTPUT_MAX_EXT[OUT_WIDTH-1:0];
    else if (shifted_signed_next < OUTPUT_MIN_EXT)
      saturated_next = OUTPUT_MIN_EXT[OUT_WIDTH-1:0];
    else
      saturated_next = shifted_signed_next[OUT_WIDTH-1:0];

    if (relu_enable_stage1 && saturated_next < 0)
      out_data_next = '0;
    else
      out_data_next = saturated_next;
  end

  always_ff @(posedge clk) begin : elastic_round_stage
    if (rst) begin
      stage1_valid <= 1'b0;
      rounded_magnitude_stage1 <= '0;
      shift_amount_stage1 <= '0;
      input_negative_stage1 <= 1'b0;
      relu_enable_stage1 <= 1'b0;
      invalid_shift_stage1 <= 1'b0;
    end else if (stage1_ready) begin
      stage1_valid <= in_valid;
      if (in_valid) begin
        rounded_magnitude_stage1 <= rounded_magnitude_next;
        shift_amount_stage1 <= shift_amount;
        input_negative_stage1 <= in_data[IN_WIDTH-1];
        relu_enable_stage1 <= relu_enable;
        invalid_shift_stage1 <= invalid_shift_stage1_next;
      end else begin
        rounded_magnitude_stage1 <= '0;
        shift_amount_stage1 <= '0;
        input_negative_stage1 <= 1'b0;
        relu_enable_stage1 <= 1'b0;
        invalid_shift_stage1 <= 1'b0;
      end
    end
  end

  always_ff @(posedge clk) begin : elastic_output_stage
    if (rst) begin
      out_valid <= 1'b0;
      out_data <= '0;
      invalid_shift <= 1'b0;
    end else if (output_stage_ready) begin
      out_valid <= stage1_valid;
      if (stage1_valid) begin
        out_data <= out_data_next;
        invalid_shift <= invalid_shift_stage1;
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
