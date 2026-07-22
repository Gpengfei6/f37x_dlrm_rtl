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

  logic signed [PRODUCT_WIDTH-1:0] product_pipeline;
  logic clear_pipeline;
  logic enable_pipeline;
  logic signed [ACC_WIDTH-1:0] seed_pipeline;
  logic signed [ACC_WIDTH-1:0] product_extended;
  logic signed [ACC_WIDTH-1:0] selected_base;
  (* use_dsp = "no" *)
  logic signed [ACC_WIDTH-1:0] fabric_sum;
  logic signed [ACC_WIDTH-1:0] accumulator_next;

  assign product_extended =
      {{(ACC_WIDTH-PRODUCT_WIDTH){product_pipeline[PRODUCT_WIDTH-1]}},
       product_pipeline};
  assign selected_base = clear_pipeline ? seed_pipeline : accumulator;
  assign fabric_sum = selected_base + product_extended;
  assign accumulator_next = enable_pipeline ?
      fabric_sum : selected_base;

  always_ff @(posedge clk) begin : product_and_control_pipeline
    if (rst) begin
      product_pipeline <= '0;
      clear_pipeline <= 1'b0;
      enable_pipeline <= 1'b0;
      seed_pipeline <= '0;
    end else begin
      // Registering the product maps the DSP output register and separates
      // BRAM/DSP delay from the fabric accumulator carry chain.
      product_pipeline <= input_data * weight_data;
      clear_pipeline <= clear;
      enable_pipeline <= enable;
      seed_pipeline <= seed_data;
    end
  end

  always_ff @(posedge clk) begin : fabric_accumulator
    if (rst)
      accumulator <= '0;
    else if (clear_pipeline || enable_pipeline)
      accumulator <= accumulator_next;
  end

  initial begin
    if (INPUT_WIDTH <= 0 || WEIGHT_WIDTH <= 0 || ACC_WIDTH <= 0)
      $error("mac_lane parameters must be positive");
    if (ACC_WIDTH < PRODUCT_WIDTH)
      $error("mac_lane ACC_WIDTH is smaller than the signed product");
  end
endmodule
