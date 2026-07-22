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
  localparam integer WEIGHT_BANK_SELECT_WIDTH =
      (NUM_PE <= 1) ? 1 : $clog2(NUM_PE);
  localparam integer WEIGHT_BANK_DEPTH =
      (MAX_WEIGHT_VALUES+NUM_PE-1)/NUM_PE;
  localparam integer WEIGHT_BANK_ADDR_WIDTH =
      (WEIGHT_BANK_DEPTH <= 1) ? 1 : $clog2(WEIGHT_BANK_DEPTH);

  logic [NUM_PE*WEIGHT_WIDTH-1:0] weight_bank_read_data;
  logic [NUM_PE-1:0] weight_response_lane_mask;
  logic [WEIGHT_BANK_SELECT_WIDTH-1:0] weight_response_base_bank;
  logic weight_request_range_error;

  (* ram_style = "block" *)
  logic signed [BIAS_WIDTH-1:0] bias_memory [0:MAX_BIAS_VALUES-1];

  assign weight_cfg_ready = 1'b1;
  assign bias_cfg_ready = 1'b1;
  assign weight_req_ready = !weight_rsp_valid || weight_rsp_ready;
  assign bias_req_ready = !bias_rsp_valid || bias_rsp_ready;

  always_comb begin : detect_weight_range_error
    integer range_lane;
    logic [WEIGHT_ADDR_WIDTH:0] range_address;

    weight_request_range_error = 1'b0;
    range_address = '0;
    for (range_lane = 0; range_lane < NUM_PE;
         range_lane = range_lane + 1) begin
      range_address = {1'b0, weight_req_address} + range_lane;
      if (weight_req_lane_mask[range_lane] &&
          (range_address >= MAX_WEIGHT_VALUES))
        weight_request_range_error = 1'b1;
    end
  end

  always_comb begin : rotate_weight_response
    integer response_lane;
    integer response_bank;

    weight_rsp_data = '0;
    response_bank = 0;
    for (response_lane = 0; response_lane < NUM_PE;
         response_lane = response_lane + 1) begin
      response_bank =
          (weight_response_base_bank + response_lane) % NUM_PE;
      if (weight_response_lane_mask[response_lane])
        weight_rsp_data[response_lane*WEIGHT_WIDTH +: WEIGHT_WIDTH] =
            weight_bank_read_data[
                response_bank*WEIGHT_WIDTH +: WEIGHT_WIDTH];
    end
  end

  always_ff @(posedge clk) begin : provider_registers
    if (rst) begin
      weight_rsp_valid <= 1'b0;
      weight_rsp_error <= 1'b0;
      weight_response_lane_mask <= '0;
      weight_response_base_bank <= '0;
      bias_rsp_valid <= 1'b0;
      bias_rsp_data <= '0;
      bias_rsp_error <= 1'b0;
    end else begin
      if (bias_cfg_valid && bias_cfg_ready &&
          bias_cfg_address < MAX_BIAS_VALUES)
        bias_memory[bias_cfg_address] <= bias_cfg_data;

      if (weight_req_ready) begin
        weight_rsp_valid <= weight_req_valid;
        if (weight_req_valid) begin
          weight_rsp_error <= weight_request_range_error;
          weight_response_lane_mask <= weight_req_lane_mask;
          weight_response_base_bank <=
              weight_req_address[WEIGHT_BANK_SELECT_WIDTH-1:0];
        end else begin
          weight_rsp_error <= 1'b0;
          weight_response_lane_mask <= '0;
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

  genvar bank_index;
  generate
    for (bank_index = 0; bank_index < NUM_PE;
         bank_index = bank_index + 1) begin : weight_bank
      localparam logic [WEIGHT_BANK_SELECT_WIDTH-1:0] BANK_NUMBER =
          bank_index;

      (* ram_style = "block" *)
      logic signed [WEIGHT_WIDTH-1:0] memory [0:WEIGHT_BANK_DEPTH-1];
      logic signed [WEIGHT_WIDTH-1:0] read_data;
      logic [WEIGHT_BANK_SELECT_WIDTH-1:0] request_lane;
      logic [WEIGHT_ADDR_WIDTH:0] request_global_address;
      logic [WEIGHT_BANK_ADDR_WIDTH-1:0] request_row;

      always_comb begin : bank_address
        request_lane =
            BANK_NUMBER -
            weight_req_address[WEIGHT_BANK_SELECT_WIDTH-1:0];
        request_global_address =
            {1'b0, weight_req_address} + request_lane;
        request_row = request_global_address >> WEIGHT_BANK_SELECT_WIDTH;
      end

      always_ff @(posedge clk) begin : bank_ports
        if (weight_cfg_valid && weight_cfg_ready &&
            (weight_cfg_address < MAX_WEIGHT_VALUES) &&
            ((weight_cfg_address % NUM_PE) == bank_index)) begin
          memory[weight_cfg_address / NUM_PE] <= weight_cfg_data;
        end

        if (rst) begin
          read_data <= '0;
        end else if (weight_req_valid && weight_req_ready) begin
          if (weight_req_lane_mask[request_lane] &&
              (request_global_address < MAX_WEIGHT_VALUES))
            read_data <= memory[request_row];
          else
            read_data <= '0;
        end
      end

      assign weight_bank_read_data[
          bank_index*WEIGHT_WIDTH +: WEIGHT_WIDTH] = read_data;
    end
  endgenerate

  initial begin
    if (NUM_PE <= 0 || WEIGHT_WIDTH <= 0 || BIAS_WIDTH <= 0 ||
        MAX_WEIGHT_VALUES <= 0 || MAX_BIAS_VALUES <= 0)
      $error("local_weight_provider parameters must be positive");
    if ((NUM_PE & (NUM_PE-1)) != 0)
      $error("local_weight_provider NUM_PE must be a power of two");
    if (WEIGHT_ADDR_WIDTH < WEIGHT_BANK_SELECT_WIDTH)
      $error("local_weight_provider WEIGHT_ADDR_WIDTH is too small");
  end
endmodule
