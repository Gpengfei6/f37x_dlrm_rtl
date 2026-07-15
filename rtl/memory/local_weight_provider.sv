`timescale 1ns/1ps

module local_weight_provider #(
  parameter integer NUM_PE            = 16,
  parameter integer WEIGHT_WIDTH      = 8,
  parameter integer BIAS_WIDTH        = 24,
  parameter integer WEIGHT_ADDR_WIDTH = 32,
  parameter integer BIAS_ADDR_WIDTH   = 32,
  parameter integer MAX_WEIGHT_VALUES = 65536,
  parameter integer MAX_BIAS_VALUES   = 1024
) (
  input  logic                                       clk,
  input  logic                                       rst,

  input  logic                                       weight_cfg_valid,
  output logic                                       weight_cfg_ready,
  input  logic [WEIGHT_ADDR_WIDTH-1:0]               weight_cfg_address,
  input  logic signed [WEIGHT_WIDTH-1:0]             weight_cfg_data,
  input  logic                                       bias_cfg_valid,
  output logic                                       bias_cfg_ready,
  input  logic [BIAS_ADDR_WIDTH-1:0]                 bias_cfg_address,
  input  logic signed [BIAS_WIDTH-1:0]               bias_cfg_data,

  input  logic                                       weight_req_valid,
  output logic                                       weight_req_ready,
  input  logic [WEIGHT_ADDR_WIDTH-1:0]               weight_req_address,
  input  logic [NUM_PE-1:0]                          weight_req_lane_mask,
  output logic                                       weight_rsp_valid,
  input  logic                                       weight_rsp_ready,
  output logic [NUM_PE*WEIGHT_WIDTH-1:0]             weight_rsp_data,
  output logic                                       weight_rsp_error,

  input  logic                                       bias_req_valid,
  output logic                                       bias_req_ready,
  input  logic [BIAS_ADDR_WIDTH-1:0]                 bias_req_address,
  output logic                                       bias_rsp_valid,
  input  logic                                       bias_rsp_ready,
  output logic signed [BIAS_WIDTH-1:0]               bias_rsp_data,
  output logic                                       bias_rsp_error
);
  logic signed [WEIGHT_WIDTH-1:0] weight_memory [0:MAX_WEIGHT_VALUES-1];
  logic signed [BIAS_WIDTH-1:0] bias_memory [0:MAX_BIAS_VALUES-1];

  assign weight_cfg_ready = 1'b1;
  assign bias_cfg_ready = 1'b1;
  assign weight_req_ready = !weight_rsp_valid || weight_rsp_ready;
  assign bias_req_ready = !bias_rsp_valid || bias_rsp_ready;

  always_ff @(posedge clk) begin : provider_registers
    integer response_lane;
    if (rst) begin
      weight_rsp_valid <= 1'b0;
      weight_rsp_data <= '0;
      weight_rsp_error <= 1'b0;
      bias_rsp_valid <= 1'b0;
      bias_rsp_data <= '0;
      bias_rsp_error <= 1'b0;
    end else begin
      if (weight_cfg_valid && weight_cfg_ready &&
          weight_cfg_address < MAX_WEIGHT_VALUES)
        weight_memory[weight_cfg_address] <= weight_cfg_data;
      if (bias_cfg_valid && bias_cfg_ready &&
          bias_cfg_address < MAX_BIAS_VALUES)
        bias_memory[bias_cfg_address] <= bias_cfg_data;

      if (weight_req_ready) begin
        weight_rsp_valid <= weight_req_valid;
        if (weight_req_valid) begin
          weight_rsp_error <= 1'b0;
          weight_rsp_data <= '0;
          for (response_lane = 0; response_lane < NUM_PE;
               response_lane = response_lane + 1) begin
            if (weight_req_lane_mask[response_lane]) begin
              if ((weight_req_address + response_lane) < MAX_WEIGHT_VALUES)
                weight_rsp_data[response_lane*WEIGHT_WIDTH +: WEIGHT_WIDTH] <=
                    weight_memory[weight_req_address + response_lane];
              else
                weight_rsp_error <= 1'b1;
            end
          end
        end
      end

      if (bias_req_ready) begin
        bias_rsp_valid <= bias_req_valid;
        if (bias_req_valid) begin
          if (bias_req_address < MAX_BIAS_VALUES) begin
            bias_rsp_data <= bias_memory[bias_req_address];
            bias_rsp_error <= 1'b0;
          end else begin
            bias_rsp_data <= '0;
            bias_rsp_error <= 1'b1;
          end
        end
      end
    end
  end

  initial begin
    if (NUM_PE <= 0 || WEIGHT_WIDTH <= 0 || BIAS_WIDTH <= 0 ||
        MAX_WEIGHT_VALUES <= 0 || MAX_BIAS_VALUES <= 0)
      $error("local_weight_provider parameters must be positive");
    if ((NUM_PE & (NUM_PE-1)) != 0)
      $error("local_weight_provider NUM_PE must be a power of two");
  end
endmodule
