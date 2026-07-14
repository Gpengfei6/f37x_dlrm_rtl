`timescale 1ns/1ps

module dot_product_core #(
  parameter integer VEC_LEN      = 8,
  parameter integer IN_WIDTH     = 10,
  parameter integer WEIGHT_WIDTH = 8,
  parameter integer BIAS_WIDTH   = 24,
  parameter integer ACC_WIDTH    = 32
) (
  input  logic                                  clk,
  input  logic                                  rst,
  input  logic                                  in_valid,
  output logic                                  in_ready,
  input  logic signed [VEC_LEN*IN_WIDTH-1:0]     in_data,
  input  logic signed [VEC_LEN*WEIGHT_WIDTH-1:0] weight_data,
  input  logic signed [BIAS_WIDTH-1:0]           bias_data,
  output logic                                  out_valid,
  input  logic                                  out_ready,
  output logic signed [ACC_WIDTH-1:0]            out_data
);
  localparam integer PRODUCT_WIDTH = IN_WIDTH + WEIGHT_WIDTH;

  logic signed [IN_WIDTH-1:0] input_elements [0:VEC_LEN-1];
  logic signed [WEIGHT_WIDTH-1:0] weight_elements [0:VEC_LEN-1];
  logic signed [PRODUCT_WIDTH-1:0] products [0:VEC_LEN-1];
  logic signed [ACC_WIDTH-1:0] accumulator_comb;
  integer sum_index;
  genvar lane;

  generate
    for (lane = 0; lane < VEC_LEN; lane = lane + 1) begin : g_products
      assign input_elements[lane] = in_data[lane*IN_WIDTH +: IN_WIDTH];
      assign weight_elements[lane] =
          weight_data[lane*WEIGHT_WIDTH +: WEIGHT_WIDTH];
      assign products[lane] = input_elements[lane] * weight_elements[lane];
    end
  endgenerate

  always_comb begin
    accumulator_comb =
        {{(ACC_WIDTH-BIAS_WIDTH){bias_data[BIAS_WIDTH-1]}}, bias_data};
    for (sum_index = 0; sum_index < VEC_LEN; sum_index = sum_index + 1)
      accumulator_comb = accumulator_comb +
          {{(ACC_WIDTH-PRODUCT_WIDTH){products[sum_index][PRODUCT_WIDTH-1]}},
            products[sum_index]};
  end

  assign in_ready = !out_valid || out_ready;

  always_ff @(posedge clk) begin
    if (rst) begin
      out_valid <= 1'b0;
      out_data <= '0;
    end else if (in_ready) begin
      out_valid <= in_valid;
      if (in_valid)
        out_data <= accumulator_comb;
    end
  end

  initial begin
    if (VEC_LEN <= 0 || IN_WIDTH <= 0 || WEIGHT_WIDTH <= 0 ||
        BIAS_WIDTH <= 0 || ACC_WIDTH <= 0)
      $error("dot_product_core parameters must be positive");
    if (ACC_WIDTH < BIAS_WIDTH)
      $error("dot_product_core ACC_WIDTH is smaller than BIAS_WIDTH");
    if (ACC_WIDTH < PRODUCT_WIDTH)
      $error("dot_product_core ACC_WIDTH is smaller than PRODUCT_WIDTH");
  end
endmodule
