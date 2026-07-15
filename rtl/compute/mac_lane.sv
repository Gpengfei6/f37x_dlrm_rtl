`timescale 1ns/1ps

module mac_lane #(
  parameter integer INPUT_WIDTH  = 16,
  parameter integer WEIGHT_WIDTH = 8,
  parameter integer ACC_WIDTH    = 48
) (
  input  logic                              clk,
  input  logic                              rst,
  input  logic                              clear,
  input  logic                              enable,
  input  logic signed [ACC_WIDTH-1:0]       seed_data,
  input  logic signed [INPUT_WIDTH-1:0]     input_data,
  input  logic signed [WEIGHT_WIDTH-1:0]    weight_data,
  output logic signed [ACC_WIDTH-1:0]       accumulator
);
  localparam integer PRODUCT_WIDTH = INPUT_WIDTH + WEIGHT_WIDTH;

  logic signed [PRODUCT_WIDTH-1:0] product;
  logic signed [ACC_WIDTH-1:0] product_extended;
  logic signed [ACC_WIDTH-1:0] selected_base;
  logic signed [ACC_WIDTH-1:0] accumulator_next;

  assign product = input_data * weight_data;
  assign product_extended =
      {{(ACC_WIDTH-PRODUCT_WIDTH){product[PRODUCT_WIDTH-1]}}, product};
  assign selected_base = clear ? seed_data : accumulator;
  assign accumulator_next = enable ? selected_base + product_extended
                                   : selected_base;

  always_ff @(posedge clk) begin
    if (rst)
      accumulator <= '0;
    else if (clear || enable)
      accumulator <= accumulator_next;
  end

  initial begin
    if (INPUT_WIDTH <= 0 || WEIGHT_WIDTH <= 0 || ACC_WIDTH <= 0)
      $error("mac_lane parameters must be positive");
    if (ACC_WIDTH < PRODUCT_WIDTH)
      $error("mac_lane ACC_WIDTH is smaller than the signed product");
  end
endmodule
