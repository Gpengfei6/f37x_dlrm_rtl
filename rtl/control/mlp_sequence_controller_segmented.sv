`timescale 1ns/1ps

// Stage 2N-A5 segmented MLP controller.
//
// This module is derived from the verified mlp_sequence_controller but adds a
// descriptor-base field to each start request. A single dense engine, activation
// buffer pair, weight memory, and bias memory can therefore execute a Bottom-MLP
// descriptor segment and later a Top-MLP descriptor segment without duplicating
// the arithmetic datapath.
module mlp_sequence_controller_segmented #(
  parameter integer MAX_LAYERS          = 4,
  parameter integer MAX_IN_DIM          = 1024,
  parameter integer MAX_OUT_DIM         = 1024,
  parameter integer NUM_PE              = 16,
  parameter integer INPUT_WIDTH         = 16,
  parameter integer WEIGHT_WIDTH        = 8,
  parameter integer BIAS_WIDTH          = 24,
  parameter integer ACC_WIDTH           = 48,
  parameter integer OUTPUT_WIDTH        = 16,
  parameter integer WEIGHT_ADDR_WIDTH   = 32,
  parameter integer BIAS_ADDR_WIDTH     = 32,
  parameter integer MAX_WEIGHT_VALUES   = 65536,
  parameter integer MAX_BIAS_VALUES     = 1024,
  parameter integer RESULT_FIFO_DEPTH   = 2,
  parameter integer JOB_TAG_WIDTH       = 8,
  parameter integer DESCRIPTOR_WIDTH    = 96,
  parameter integer IN_DIM_WIDTH =
      (MAX_IN_DIM <= 1) ? 1 : $clog2(MAX_IN_DIM+1),
  parameter integer OUT_DIM_WIDTH =
      (MAX_OUT_DIM <= 1) ? 1 : $clog2(MAX_OUT_DIM+1),
  parameter integer OUT_INDEX_WIDTH =
      (MAX_OUT_DIM <= 1) ? 1 : $clog2(MAX_OUT_DIM),
  parameter integer ACT_MAX_DIM =
      (MAX_IN_DIM > MAX_OUT_DIM) ? MAX_IN_DIM : MAX_OUT_DIM,
  parameter integer ACT_BANK_DEPTH =
      (ACT_MAX_DIM+NUM_PE-1)/NUM_PE,
  parameter integer ACT_CHUNK_ADDR_WIDTH =
      (ACT_BANK_DEPTH <= 1) ? 1 : $clog2(ACT_BANK_DEPTH),
  parameter integer SHIFT_WIDTH =
      (ACC_WIDTH <= 1) ? 1 : $clog2(ACC_WIDTH+1),
  parameter integer LAYER_INDEX_WIDTH =
      (MAX_LAYERS <= 1) ? 1 : $clog2(MAX_LAYERS),
  parameter integer LAYER_COUNT_WIDTH =
      (MAX_LAYERS <= 1) ? 1 : $clog2(MAX_LAYERS+1)
) (
  input  logic                                      clk,
  input  logic                                      rst,

  input  logic                                      descriptor_cfg_valid,
  output logic                                      descriptor_cfg_ready,
  input  logic [LAYER_INDEX_WIDTH-1:0]             descriptor_cfg_index,
  input  logic [DESCRIPTOR_WIDTH-1:0]              descriptor_cfg_data,

  input  logic                                      start_valid,
  output logic                                      start_ready,
  input  logic [LAYER_INDEX_WIDTH-1:0]             descriptor_base,
  input  logic [LAYER_COUNT_WIDTH-1:0]             layer_count,
  input  logic                                      initial_buffer_select,

  input  logic                                      act_load_valid,
  output logic                                      act_load_ready,
  input  logic                                      act_load_buffer_select,
  input  logic [ACT_CHUNK_ADDR_WIDTH-1:0]           act_load_chunk_index,
  input  logic [NUM_PE-1:0]                         act_load_lane_mask,
  input  logic [NUM_PE*INPUT_WIDTH-1:0]             act_load_data,

  input  logic                                      weight_cfg_valid,
  output logic                                      weight_cfg_ready,
  input  logic [WEIGHT_ADDR_WIDTH-1:0]              weight_cfg_address,
  input  logic signed [WEIGHT_WIDTH-1:0]            weight_cfg_data,

  input  logic                                      bias_cfg_valid,
  output logic                                      bias_cfg_ready,
  input  logic [BIAS_ADDR_WIDTH-1:0]                bias_cfg_address,
  input  logic signed [BIAS_WIDTH-1:0]              bias_cfg_data,

  output logic                                      result_valid,
  input  logic                                      result_ready,
  output logic signed [OUTPUT_WIDTH-1:0]            result_data,
  output logic [OUT_INDEX_WIDTH-1:0]                result_index,
  output logic                                      result_last,
  output logic [JOB_TAG_WIDTH-1:0]                  result_tag,

  output logic                                      busy,
  output logic                                      done,
  output logic                                      final_buffer_select,

  output logic                                      error_valid,
  input  logic                                      error_ready,
  output logic [3:0]                                error_code
);

  localparam integer DESC_IN_DIM_OFFSET      = 0;
  localparam integer DESC_OUT_DIM_OFFSET     = 11;
  localparam integer DESC_WEIGHT_BASE_OFFSET = 22;
  localparam integer DESC_BIAS_BASE_OFFSET   = 54;
  localparam integer DESC_SHIFT_OFFSET       = 86;
  localparam integer DESC_RELU_OFFSET        = 92;

  localparam logic [3:0] ERROR_NONE               = 4'd0;
  localparam logic [3:0] ERROR_BAD_LAYER_COUNT    = 4'd1;
  localparam logic [3:0] ERROR_MISSING_DESCRIPTOR = 4'd2;
  localparam logic [3:0] ERROR_BAD_DIMENSION      = 4'd3;
  localparam logic [3:0] ERROR_DIMENSION_MISMATCH = 4'd4;
  localparam logic [3:0] ERROR_WEIGHT_RANGE       = 4'd5;
  localparam logic [3:0] ERROR_BIAS_RANGE         = 4'd6;
  localparam logic [3:0] ERROR_BAD_SHIFT          = 4'd7;
  localparam logic [3:0] ERROR_DENSE_BASE         = 4'd8;

  typedef enum logic [2:0] {
    STATE_IDLE,
    STATE_ISSUE_JOB,
    STATE_RUN_LAYER,
    STATE_WAIT_DRAIN,
    STATE_FINISH,
    STATE_ERROR
  } state_t;

  state_t state;

  logic [IN_DIM_WIDTH-1:0] desc_in_dim [0:MAX_LAYERS-1];
  logic [OUT_DIM_WIDTH-1:0] desc_out_dim [0:MAX_LAYERS-1];
  logic [WEIGHT_ADDR_WIDTH-1:0] desc_weight_base [0:MAX_LAYERS-1];
  logic [BIAS_ADDR_WIDTH-1:0] desc_bias_base [0:MAX_LAYERS-1];
  logic [SHIFT_WIDTH-1:0] desc_output_shift [0:MAX_LAYERS-1];
  logic desc_relu_enable [0:MAX_LAYERS-1];
  logic [MAX_LAYERS-1:0] desc_loaded;

  logic [LAYER_INDEX_WIDTH-1:0] descriptor_base_reg;
  logic [LAYER_COUNT_WIDTH-1:0] layer_count_reg;
  logic [LAYER_INDEX_WIDTH-1:0] current_layer;
  logic initial_buffer_reg;
  logic final_buffer_reg;
  logic final_last_accepted;

  logic [LAYER_INDEX_WIDTH:0] selected_descriptor_index_ext;
  logic [LAYER_INDEX_WIDTH-1:0] selected_descriptor_index;
  logic [LAYER_INDEX_WIDTH:0] requested_descriptor_end;

  logic validation_ok;
  logic [3:0] validation_error;
  longint unsigned validation_weight_end;
  longint unsigned validation_bias_end;
  integer validation_descriptor_index;

  logic config_access_allowed;
  logic final_layer_active;

  logic dense_job_valid;
  logic dense_job_ready;
  logic [IN_DIM_WIDTH-1:0] dense_job_in_dim;
  logic [OUT_DIM_WIDTH-1:0] dense_job_out_dim;
  logic dense_job_input_buffer_select;
  logic dense_job_output_buffer_select;
  logic [WEIGHT_ADDR_WIDTH-1:0] dense_job_weight_offset;
  logic [BIAS_ADDR_WIDTH-1:0] dense_job_bias_offset;
  logic [SHIFT_WIDTH-1:0] dense_job_output_shift;
  logic dense_job_relu_enable;
  logic [JOB_TAG_WIDTH-1:0] dense_job_tag;
  logic dense_job_done;

  logic dense_act_load_valid;
  logic dense_act_load_ready;
  logic dense_weight_cfg_valid;
  logic dense_weight_cfg_ready;
  logic dense_bias_cfg_valid;
  logic dense_bias_cfg_ready;

  logic dense_result_valid;
  logic dense_result_ready;
  logic signed [OUTPUT_WIDTH-1:0] dense_result_data;
  logic [OUT_INDEX_WIDTH-1:0] dense_result_index;
  logic dense_result_last;
  logic [JOB_TAG_WIDTH-1:0] dense_result_tag;

  logic dense_error_valid;
  logic dense_error_ready;
  logic [3:0] dense_error_code;

  logic error_valid_reg;
  logic [3:0] error_code_reg;

  integer validation_index;
  integer reset_index;

  assign busy = (state != STATE_IDLE);
  assign done = (state == STATE_FINISH);
  assign final_buffer_select = final_buffer_reg;

  assign selected_descriptor_index_ext =
      {1'b0, descriptor_base_reg} + current_layer;
  assign selected_descriptor_index =
      selected_descriptor_index_ext[LAYER_INDEX_WIDTH-1:0];
  assign requested_descriptor_end =
      {1'b0, descriptor_base} + layer_count;

  assign config_access_allowed =
      (state == STATE_IDLE) &&
      !start_valid &&
      !error_valid_reg;

  assign descriptor_cfg_ready = config_access_allowed;

  assign start_ready =
      (state == STATE_IDLE) &&
      !error_valid_reg &&
      !descriptor_cfg_valid &&
      !act_load_valid &&
      !weight_cfg_valid &&
      !bias_cfg_valid;

  assign dense_act_load_valid =
      act_load_valid && config_access_allowed;
  assign act_load_ready =
      config_access_allowed && dense_act_load_ready;

  assign dense_weight_cfg_valid =
      weight_cfg_valid && config_access_allowed;
  assign weight_cfg_ready =
      config_access_allowed && dense_weight_cfg_ready;

  assign dense_bias_cfg_valid =
      bias_cfg_valid && config_access_allowed;
  assign bias_cfg_ready =
      config_access_allowed && dense_bias_cfg_ready;

  assign final_layer_active =
      (layer_count_reg != 0) &&
      (current_layer == layer_count_reg - 1'b1);

  assign dense_job_valid = (state == STATE_ISSUE_JOB);
  assign dense_job_in_dim = desc_in_dim[selected_descriptor_index];
  assign dense_job_out_dim = desc_out_dim[selected_descriptor_index];
  assign dense_job_input_buffer_select =
      initial_buffer_reg ^ current_layer[0];
  assign dense_job_output_buffer_select =
      ~(initial_buffer_reg ^ current_layer[0]);
  assign dense_job_weight_offset =
      desc_weight_base[selected_descriptor_index];
  assign dense_job_bias_offset =
      desc_bias_base[selected_descriptor_index];
  assign dense_job_output_shift =
      desc_output_shift[selected_descriptor_index];
  assign dense_job_relu_enable =
      desc_relu_enable[selected_descriptor_index];
  assign dense_job_tag = selected_descriptor_index;

  assign result_valid = final_layer_active && dense_result_valid;
  assign result_data = dense_result_data;
  assign result_index = dense_result_index;
  assign result_last = dense_result_last;
  assign result_tag = dense_result_tag;

  assign dense_result_ready =
      final_layer_active ? result_ready : 1'b1;

  assign error_valid = error_valid_reg;
  assign error_code = error_code_reg;
  assign dense_error_ready = !error_valid_reg;

  always_comb begin
    validation_ok = 1'b1;
    validation_error = ERROR_NONE;
    validation_weight_end = 0;
    validation_bias_end = 0;
    validation_descriptor_index = 0;

    if ((layer_count < 1) ||
        (layer_count > MAX_LAYERS) ||
        (descriptor_base >= MAX_LAYERS) ||
        (requested_descriptor_end > MAX_LAYERS)) begin
      validation_ok = 1'b0;
      validation_error = ERROR_BAD_LAYER_COUNT;
    end else begin
      for (validation_index = 0;
           validation_index < MAX_LAYERS;
           validation_index = validation_index + 1) begin
        validation_descriptor_index =
            descriptor_base + validation_index;

        if (validation_ok && (validation_index < layer_count)) begin
          if (!desc_loaded[validation_descriptor_index]) begin
            validation_ok = 1'b0;
            validation_error = ERROR_MISSING_DESCRIPTOR;
          end else if (
              (desc_in_dim[validation_descriptor_index] < 1) ||
              (desc_out_dim[validation_descriptor_index] < 1) ||
              (desc_in_dim[validation_descriptor_index] > MAX_IN_DIM) ||
              (desc_out_dim[validation_descriptor_index] > MAX_OUT_DIM)) begin
            validation_ok = 1'b0;
            validation_error = ERROR_BAD_DIMENSION;
          end else if (
              desc_output_shift[validation_descriptor_index] > ACC_WIDTH) begin
            validation_ok = 1'b0;
            validation_error = ERROR_BAD_SHIFT;
          end else if (
              (validation_index > 0) &&
              (desc_out_dim[validation_descriptor_index-1] !=
               desc_in_dim[validation_descriptor_index])) begin
            validation_ok = 1'b0;
            validation_error = ERROR_DIMENSION_MISMATCH;
          end else begin
            validation_weight_end =
                desc_weight_base[validation_descriptor_index] +
                (desc_in_dim[validation_descriptor_index] *
                 desc_out_dim[validation_descriptor_index]);
            validation_bias_end =
                desc_bias_base[validation_descriptor_index] +
                desc_out_dim[validation_descriptor_index];

            if (validation_weight_end > MAX_WEIGHT_VALUES) begin
              validation_ok = 1'b0;
              validation_error = ERROR_WEIGHT_RANGE;
            end else if (validation_bias_end > MAX_BIAS_VALUES) begin
              validation_ok = 1'b0;
              validation_error = ERROR_BIAS_RANGE;
            end
          end
        end
      end
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      state <= STATE_IDLE;
      descriptor_base_reg <= '0;
      layer_count_reg <= '0;
      current_layer <= '0;
      initial_buffer_reg <= 1'b0;
      final_buffer_reg <= 1'b0;
      final_last_accepted <= 1'b0;
      desc_loaded <= '0;
      error_valid_reg <= 1'b0;
      error_code_reg <= ERROR_NONE;

      for (reset_index = 0;
           reset_index < MAX_LAYERS;
           reset_index = reset_index + 1) begin
        desc_in_dim[reset_index] <= '0;
        desc_out_dim[reset_index] <= '0;
        desc_weight_base[reset_index] <= '0;
        desc_bias_base[reset_index] <= '0;
        desc_output_shift[reset_index] <= '0;
        desc_relu_enable[reset_index] <= 1'b0;
      end
    end else begin
      if (descriptor_cfg_valid && descriptor_cfg_ready) begin
        desc_in_dim[descriptor_cfg_index] <=
            descriptor_cfg_data[DESC_IN_DIM_OFFSET +: 11];
        desc_out_dim[descriptor_cfg_index] <=
            descriptor_cfg_data[DESC_OUT_DIM_OFFSET +: 11];
        desc_weight_base[descriptor_cfg_index] <=
            descriptor_cfg_data[DESC_WEIGHT_BASE_OFFSET +: 32];
        desc_bias_base[descriptor_cfg_index] <=
            descriptor_cfg_data[DESC_BIAS_BASE_OFFSET +: 32];
        desc_output_shift[descriptor_cfg_index] <=
            descriptor_cfg_data[DESC_SHIFT_OFFSET +: 6];
        desc_relu_enable[descriptor_cfg_index] <=
            descriptor_cfg_data[DESC_RELU_OFFSET];
        desc_loaded[descriptor_cfg_index] <= 1'b1;
      end

      if (error_valid_reg && error_ready) begin
        error_valid_reg <= 1'b0;
        error_code_reg <= ERROR_NONE;
      end

      if (dense_error_valid && dense_error_ready) begin
        error_valid_reg <= 1'b1;
        error_code_reg <=
            ERROR_DENSE_BASE | {1'b0, dense_error_code[2:0]};
        state <= STATE_ERROR;
      end else begin
        case (state)
          STATE_IDLE: begin
            final_last_accepted <= 1'b0;

            if (start_valid && start_ready) begin
              if (validation_ok) begin
                descriptor_base_reg <= descriptor_base;
                layer_count_reg <= layer_count;
                current_layer <= '0;
                initial_buffer_reg <= initial_buffer_select;
                final_buffer_reg <=
                    initial_buffer_select ^ layer_count[0];
                state <= STATE_ISSUE_JOB;
              end else begin
                error_valid_reg <= 1'b1;
                error_code_reg <= validation_error;
                state <= STATE_ERROR;
              end
            end
          end

          STATE_ISSUE_JOB: begin
            if (dense_job_valid && dense_job_ready) begin
              final_last_accepted <= 1'b0;
              state <= STATE_RUN_LAYER;
            end
          end

          STATE_RUN_LAYER: begin
            if (final_layer_active &&
                dense_result_valid &&
                dense_result_ready &&
                dense_result_last) begin
              final_last_accepted <= 1'b1;
            end

            if (dense_job_done) begin
              state <= STATE_WAIT_DRAIN;
            end
          end

          STATE_WAIT_DRAIN: begin
            if (final_layer_active &&
                dense_result_valid &&
                dense_result_ready &&
                dense_result_last) begin
              final_last_accepted <= 1'b1;
            end

            if (final_layer_active) begin
              if (final_last_accepted &&
                  !dense_result_valid &&
                  dense_job_ready) begin
                state <= STATE_FINISH;
              end
            end else if (!dense_result_valid && dense_job_ready) begin
              current_layer <= current_layer + 1'b1;
              state <= STATE_ISSUE_JOB;
            end
          end

          STATE_FINISH: begin
            state <= STATE_IDLE;
          end

          STATE_ERROR: begin
            if (error_valid_reg && error_ready) begin
              state <= STATE_IDLE;
            end
          end

          default: begin
            state <= STATE_IDLE;
          end
        endcase
      end
    end
  end

  dense_layer_engine #(
    .MAX_IN_DIM(MAX_IN_DIM),
    .MAX_OUT_DIM(MAX_OUT_DIM),
    .NUM_PE(NUM_PE),
    .INPUT_WIDTH(INPUT_WIDTH),
    .WEIGHT_WIDTH(WEIGHT_WIDTH),
    .BIAS_WIDTH(BIAS_WIDTH),
    .ACC_WIDTH(ACC_WIDTH),
    .OUTPUT_WIDTH(OUTPUT_WIDTH),
    .WEIGHT_ADDR_WIDTH(WEIGHT_ADDR_WIDTH),
    .BIAS_ADDR_WIDTH(BIAS_ADDR_WIDTH),
    .MAX_WEIGHT_VALUES(MAX_WEIGHT_VALUES),
    .MAX_BIAS_VALUES(MAX_BIAS_VALUES),
    .RESULT_FIFO_DEPTH(RESULT_FIFO_DEPTH),
    .JOB_TAG_WIDTH(JOB_TAG_WIDTH)
  ) u_dense_layer_engine (
    .clk(clk),
    .rst(rst),

    .job_valid(dense_job_valid),
    .job_ready(dense_job_ready),
    .job_in_dim(dense_job_in_dim),
    .job_out_dim(dense_job_out_dim),
    .job_input_buffer_select(dense_job_input_buffer_select),
    .job_output_buffer_select(dense_job_output_buffer_select),
    .job_weight_offset(dense_job_weight_offset),
    .job_bias_offset(dense_job_bias_offset),
    .job_output_shift(dense_job_output_shift),
    .job_relu_enable(dense_job_relu_enable),
    .job_tag(dense_job_tag),

    .act_load_valid(dense_act_load_valid),
    .act_load_ready(dense_act_load_ready),
    .act_load_buffer_select(act_load_buffer_select),
    .act_load_chunk_index(act_load_chunk_index),
    .act_load_lane_mask(act_load_lane_mask),
    .act_load_data(act_load_data),

    .weight_cfg_valid(dense_weight_cfg_valid),
    .weight_cfg_ready(dense_weight_cfg_ready),
    .weight_cfg_address(weight_cfg_address),
    .weight_cfg_data(weight_cfg_data),

    .bias_cfg_valid(dense_bias_cfg_valid),
    .bias_cfg_ready(dense_bias_cfg_ready),
    .bias_cfg_address(bias_cfg_address),
    .bias_cfg_data(bias_cfg_data),

    .result_valid(dense_result_valid),
    .result_ready(dense_result_ready),
    .result_data(dense_result_data),
    .result_index(dense_result_index),
    .result_last(dense_result_last),
    .result_tag(dense_result_tag),
    .job_done(dense_job_done),

    .error_valid(dense_error_valid),
    .error_ready(dense_error_ready),
    .error_code(dense_error_code)
  );

  initial begin
    if (MAX_LAYERS < 1)
      $error("mlp_sequence_controller_segmented MAX_LAYERS must be positive");
    if (MAX_LAYERS > (1 << LAYER_INDEX_WIDTH))
      $error("mlp_sequence_controller_segmented LAYER_INDEX_WIDTH is too small");
    if (JOB_TAG_WIDTH < LAYER_INDEX_WIDTH)
      $error("mlp_sequence_controller_segmented JOB_TAG_WIDTH is too small");
    if (DESCRIPTOR_WIDTH < 93)
      $error("mlp_sequence_controller_segmented DESCRIPTOR_WIDTH must be at least 93");
  end

endmodule
