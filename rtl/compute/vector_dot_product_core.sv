`timescale 1ns/1ps

module vector_dot_product_core #(
  parameter integer MAX_IN_DIM   = 1024,
  parameter integer NUM_PE       = 16,
  parameter integer INPUT_WIDTH  = 16,
  parameter integer WEIGHT_WIDTH = 8,
  parameter integer BIAS_WIDTH   = 24,
  parameter integer ACC_WIDTH    = 48,
  parameter integer DIM_WIDTH = (MAX_IN_DIM <= 1) ? 1 : $clog2(MAX_IN_DIM+1),
  parameter integer REDUCTION_LEVELS = $clog2(NUM_PE),
  parameter integer REDUCTION_LEVEL_WIDTH =
      (REDUCTION_LEVELS <= 1) ? 1 : $clog2(REDUCTION_LEVELS)
) (
  input  logic                                      clk,
  input  logic                                      rst,

  input  logic                                      command_valid,
  output logic                                      command_ready,
  input  logic [DIM_WIDTH-1:0]                      command_in_dim,
  input  logic signed [BIAS_WIDTH-1:0]              command_bias,

  input  logic                                      chunk_valid,
  output logic                                      chunk_ready,
  input  logic signed [NUM_PE*INPUT_WIDTH-1:0]      chunk_inputs,
  input  logic signed [NUM_PE*WEIGHT_WIDTH-1:0]     chunk_weights,
  input  logic [NUM_PE-1:0]                         chunk_lane_mask,
  input  logic                                      chunk_last,

  output logic                                      result_valid,
  input  logic                                      result_ready,
  output logic signed [ACC_WIDTH-1:0]               result_data,
  output logic                                      protocol_error
);
  localparam logic [2:0] STATE_IDLE      = 3'd0;
  localparam logic [2:0] STATE_MAC       = 3'd1;
  localparam logic [2:0] STATE_MAC_DRAIN = 3'd2;
  localparam logic [2:0] STATE_REDUCE    = 3'd3;
  localparam logic [2:0] STATE_OUTPUT    = 3'd4;

  logic [2:0] state;
  logic [DIM_WIDTH-1:0] active_in_dim;
  logic [DIM_WIDTH-1:0] chunk_count;
  logic [DIM_WIDTH-1:0] chunk_index;
  logic signed [ACC_WIDTH-1:0] bias_extended;
  logic [NUM_PE-1:0] expected_lane_mask;
  logic expected_last;
  logic chunk_fire;
  logic [REDUCTION_LEVEL_WIDTH-1:0] reduction_level;

  logic signed [ACC_WIDTH-1:0] lane_accumulator [0:NUM_PE-1];
  logic signed [ACC_WIDTH-1:0] reduction_work [0:NUM_PE-1];

  assign command_ready = (state == STATE_IDLE) ||
                         ((state == STATE_OUTPUT) && result_ready);
  assign chunk_ready = (state == STATE_MAC);
  assign chunk_fire = chunk_valid && chunk_ready;
  assign result_valid = (state == STATE_OUTPUT);

  always_comb begin : expected_tail
    integer mask_lane;
    expected_lane_mask = '0;
    for (mask_lane = 0; mask_lane < NUM_PE; mask_lane = mask_lane + 1)
      if ((chunk_index*NUM_PE + mask_lane) < active_in_dim)
        expected_lane_mask[mask_lane] = 1'b1;
    expected_last = (chunk_index == chunk_count-1'b1);
  end

  generate
    genvar lane;
    for (lane = 0; lane < NUM_PE; lane = lane + 1) begin : g_mac_lanes
      localparam logic LANE_IS_ZERO = (lane == 0);
      logic signed [ACC_WIDTH-1:0] lane_seed;
      assign lane_seed = LANE_IS_ZERO ? bias_extended : '0;

      mac_lane #(
        .INPUT_WIDTH(INPUT_WIDTH),
        .WEIGHT_WIDTH(WEIGHT_WIDTH),
        .ACC_WIDTH(ACC_WIDTH)
      ) u_mac_lane (
        .clk(clk),
        .rst(rst),
        .clear(chunk_fire && (chunk_index == 0)),
        .enable(chunk_fire && expected_lane_mask[lane] &&
                chunk_lane_mask[lane]),
        .seed_data(lane_seed),
        .input_data(chunk_inputs[lane*INPUT_WIDTH +: INPUT_WIDTH]),
        .weight_data(chunk_weights[lane*WEIGHT_WIDTH +: WEIGHT_WIDTH]),
        .accumulator(lane_accumulator[lane])
      );
    end
  endgenerate

  always_ff @(posedge clk) begin : control_and_reduction
    integer reduce_index;
    if (rst) begin
      state <= STATE_IDLE;
      active_in_dim <= '0;
      chunk_count <= '0;
      chunk_index <= '0;
      bias_extended <= '0;
      reduction_level <= '0;
      result_data <= '0;
      protocol_error <= 1'b0;
      for (reduce_index = 0; reduce_index < NUM_PE;
           reduce_index = reduce_index + 1)
        reduction_work[reduce_index] <= '0;
    end else begin
      case (state)
        STATE_IDLE: begin
          if (command_valid && command_ready) begin
            if (command_in_dim == 0 || command_in_dim > MAX_IN_DIM) begin
              protocol_error <= 1'b1;
            end else begin
              active_in_dim <= command_in_dim;
              chunk_count <= (command_in_dim + NUM_PE-1) / NUM_PE;
              chunk_index <= '0;
              bias_extended <=
                  {{(ACC_WIDTH-BIAS_WIDTH){command_bias[BIAS_WIDTH-1]}},
                   command_bias};
              state <= STATE_MAC;
            end
          end
        end

        STATE_MAC: begin
          if (chunk_fire) begin
            if (chunk_lane_mask != expected_lane_mask ||
                chunk_last != expected_last)
              protocol_error <= 1'b1;
            if (expected_last) begin
              state <= STATE_MAC_DRAIN;
            end else begin
              chunk_index <= chunk_index + 1'b1;
            end
          end
        end

        // The MAC lanes register DSP products. This explicit drain cycle lets
        // the final product reach each accumulator before reduction samples it.
        STATE_MAC_DRAIN: begin
          reduction_level <= '0;
          state <= STATE_REDUCE;
        end

        STATE_REDUCE: begin
          if (reduction_level == 0) begin
            for (reduce_index = 0; reduce_index < NUM_PE/2;
                 reduce_index = reduce_index + 1)
              reduction_work[reduce_index] <=
                  lane_accumulator[2*reduce_index] +
                  lane_accumulator[2*reduce_index+1];
            if (REDUCTION_LEVELS == 1) begin
              result_data <= lane_accumulator[0] + lane_accumulator[1];
              state <= STATE_OUTPUT;
            end else begin
              reduction_level <= 1;
            end
          end else begin
            for (reduce_index = 0; reduce_index < NUM_PE/2;
                 reduce_index = reduce_index + 1)
              if (reduce_index < (NUM_PE >> (reduction_level+1)))
                reduction_work[reduce_index] <=
                    reduction_work[2*reduce_index] +
                    reduction_work[2*reduce_index+1];
            if (reduction_level == REDUCTION_LEVELS-1) begin
              result_data <= reduction_work[0] + reduction_work[1];
              state <= STATE_OUTPUT;
            end else begin
              reduction_level <= reduction_level + 1'b1;
            end
          end
        end

        STATE_OUTPUT: begin
          if (result_valid && result_ready) begin
            if (command_valid) begin
              if (command_in_dim == 0 || command_in_dim > MAX_IN_DIM) begin
                protocol_error <= 1'b1;
                state <= STATE_IDLE;
              end else begin
                active_in_dim <= command_in_dim;
                chunk_count <= (command_in_dim + NUM_PE-1) / NUM_PE;
                chunk_index <= '0;
                bias_extended <=
                    {{(ACC_WIDTH-BIAS_WIDTH){command_bias[BIAS_WIDTH-1]}},
                     command_bias};
                state <= STATE_MAC;
              end
            end else begin
              state <= STATE_IDLE;
            end
          end
        end

        default: state <= STATE_IDLE;
      endcase
    end
  end

  initial begin
    if (MAX_IN_DIM <= 0 || NUM_PE < 2 || INPUT_WIDTH <= 0 ||
        WEIGHT_WIDTH <= 0 || BIAS_WIDTH <= 0 || ACC_WIDTH <= 0)
      $error("vector_dot_product_core parameters are invalid");
    if ((NUM_PE & (NUM_PE-1)) != 0)
      $error("vector_dot_product_core NUM_PE must be a power of two");
    if (ACC_WIDTH < INPUT_WIDTH+WEIGHT_WIDTH || ACC_WIDTH < BIAS_WIDTH)
      $error("vector_dot_product_core ACC_WIDTH is too small");
  end
endmodule
