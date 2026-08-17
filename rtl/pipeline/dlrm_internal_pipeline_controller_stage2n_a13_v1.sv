`timescale 1ns/1ps

// Stage 2N-A13 v1 cycle-counting wrapper around the frozen canonical internal
// DLRM pipeline controller. The wrapped controller and all arithmetic RTL are
// unchanged. Four saturating 32-bit counters observe only controller-visible
// phase/result events.
module dlrm_internal_pipeline_controller_stage2n_a13_v1 #(
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

  input  logic                                      act_load_valid,
  output logic                                      act_load_ready,
  input  logic                                      act_load_buffer_select,
  input  logic [ACT_CHUNK_ADDR_WIDTH-1:0]           act_load_chunk_index,
  input  logic [NUM_PE-1:0]                         act_load_lane_mask,
  input  logic [NUM_PE*INPUT_WIDTH-1:0]             act_load_data,

  input  logic                                      embedding_cfg_valid,
  output logic                                      embedding_cfg_ready,
  input  logic [1:0]                                embedding_cfg_index,
  input  logic [8*INPUT_WIDTH-1:0]                  embedding_cfg_data,
  output logic [3:0]                                embedding_loaded_mask,

  input  logic                                      weight_cfg_valid,
  output logic                                      weight_cfg_ready,
  input  logic [WEIGHT_ADDR_WIDTH-1:0]              weight_cfg_address,
  input  logic signed [WEIGHT_WIDTH-1:0]            weight_cfg_data,

  input  logic                                      bias_cfg_valid,
  output logic                                      bias_cfg_ready,
  input  logic [BIAS_ADDR_WIDTH-1:0]                bias_cfg_address,
  input  logic signed [BIAS_WIDTH-1:0]              bias_cfg_data,

  input  logic                                      pipeline_start_valid,
  output logic                                      pipeline_start_ready,
  input  logic [LAYER_INDEX_WIDTH-1:0]             bottom_descriptor_base,
  input  logic [LAYER_COUNT_WIDTH-1:0]             bottom_layer_count,
  input  logic [LAYER_INDEX_WIDTH-1:0]             top_descriptor_base,
  input  logic [LAYER_COUNT_WIDTH-1:0]             top_layer_count,
  input  logic                                      bottom_initial_buffer_select,
  input  logic                                      top_input_buffer_select,
  input  logic [SHIFT_WIDTH-1:0]                    interaction_shift,

  output logic                                      result_valid,
  input  logic                                      result_ready,
  output logic signed [OUTPUT_WIDTH-1:0]            result_data,
  output logic [OUT_INDEX_WIDTH-1:0]                result_index,
  output logic                                      result_last,
  output logic [JOB_TAG_WIDTH-1:0]                  result_tag,

  output logic                                      busy,
  output logic                                      done,
  output logic [3:0]                                phase,
  output logic [3:0]                                bottom_result_count,
  output logic [4:0]                                interaction_result_count,

  output logic [31:0]                               bottom_cycle_count,
  output logic [31:0]                               interaction_cycle_count,
  output logic [31:0]                               top_cycle_count,
  output logic [31:0]                               total_cycle_count,

  output logic                                      error_valid,
  input  logic                                      error_ready,
  output logic [7:0]                                error_code
);

  localparam logic [3:0] PHASE_START_BOTTOM          = 4'd1;
  localparam logic [3:0] PHASE_RUN_BOTTOM            = 4'd2;
  localparam logic [3:0] PHASE_START_INTERACTION     = 4'd5;
  localparam logic [3:0] PHASE_RUN_INTERACTION       = 4'd6;
  localparam logic [3:0] PHASE_WAIT_INTERACTION_DONE = 4'd7;
  localparam logic [3:0] PHASE_START_TOP             = 4'd10;
  localparam logic [3:0] PHASE_RUN_TOP               = 4'd11;

  logic total_count_active;
  logic start_accept;
  logic final_result_visible;

  assign start_accept = pipeline_start_valid && pipeline_start_ready;
  assign final_result_visible = result_valid && result_last;

  function automatic logic [31:0] saturating_increment32(
      input logic [31:0] value
  );
    begin
      if (&value)
        saturating_increment32 = value;
      else
        saturating_increment32 = value + 1'b1;
    end
  endfunction

  // Cycle contract:
  // - total counts the accepted pipeline START edge as cycle one and freezes
  //   on the first edge that exposes the final result (valid && last).
  // - each stage counter counts rising edges spent in that stage's controller
  //   dispatch/run phases. Bottom and Interaction include their done-observe
  //   edge. Top freezes on final result visibility, before Host retirement.
  // - all counters saturate at 0xffffffff and restart from zero/one only when a
  //   new pipeline START is accepted. Result POP and CLEAR_DONE do not change
  //   the latched values.
  always_ff @(posedge clk) begin
    if (rst) begin
      bottom_cycle_count <= 32'd0;
      interaction_cycle_count <= 32'd0;
      top_cycle_count <= 32'd0;
      total_cycle_count <= 32'd0;
      total_count_active <= 1'b0;
    end else begin
      if (start_accept) begin
        bottom_cycle_count <= 32'd0;
        interaction_cycle_count <= 32'd0;
        top_cycle_count <= 32'd0;
        total_cycle_count <= 32'd1;
        total_count_active <= 1'b1;
      end else if (total_count_active) begin
        total_cycle_count <= saturating_increment32(total_cycle_count);

        if ((phase == PHASE_START_BOTTOM) ||
            (phase == PHASE_RUN_BOTTOM)) begin
          bottom_cycle_count <=
              saturating_increment32(bottom_cycle_count);
        end

        if ((phase == PHASE_START_INTERACTION) ||
            (phase == PHASE_RUN_INTERACTION) ||
            (phase == PHASE_WAIT_INTERACTION_DONE)) begin
          interaction_cycle_count <=
              saturating_increment32(interaction_cycle_count);
        end

        if ((phase == PHASE_START_TOP) ||
            (phase == PHASE_RUN_TOP)) begin
          top_cycle_count <= saturating_increment32(top_cycle_count);
        end

        if (final_result_visible || error_valid)
          total_count_active <= 1'b0;
      end
    end
  end

  dlrm_internal_pipeline_controller #(
    .MAX_LAYERS(MAX_LAYERS),
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
    .JOB_TAG_WIDTH(JOB_TAG_WIDTH),
    .DESCRIPTOR_WIDTH(DESCRIPTOR_WIDTH)
  ) u_canonical_pipeline (
    .clk(clk),
    .rst(rst),
    .descriptor_cfg_valid(descriptor_cfg_valid),
    .descriptor_cfg_ready(descriptor_cfg_ready),
    .descriptor_cfg_index(descriptor_cfg_index),
    .descriptor_cfg_data(descriptor_cfg_data),
    .act_load_valid(act_load_valid),
    .act_load_ready(act_load_ready),
    .act_load_buffer_select(act_load_buffer_select),
    .act_load_chunk_index(act_load_chunk_index),
    .act_load_lane_mask(act_load_lane_mask),
    .act_load_data(act_load_data),
    .embedding_cfg_valid(embedding_cfg_valid),
    .embedding_cfg_ready(embedding_cfg_ready),
    .embedding_cfg_index(embedding_cfg_index),
    .embedding_cfg_data(embedding_cfg_data),
    .embedding_loaded_mask(embedding_loaded_mask),
    .weight_cfg_valid(weight_cfg_valid),
    .weight_cfg_ready(weight_cfg_ready),
    .weight_cfg_address(weight_cfg_address),
    .weight_cfg_data(weight_cfg_data),
    .bias_cfg_valid(bias_cfg_valid),
    .bias_cfg_ready(bias_cfg_ready),
    .bias_cfg_address(bias_cfg_address),
    .bias_cfg_data(bias_cfg_data),
    .pipeline_start_valid(pipeline_start_valid),
    .pipeline_start_ready(pipeline_start_ready),
    .bottom_descriptor_base(bottom_descriptor_base),
    .bottom_layer_count(bottom_layer_count),
    .top_descriptor_base(top_descriptor_base),
    .top_layer_count(top_layer_count),
    .bottom_initial_buffer_select(bottom_initial_buffer_select),
    .top_input_buffer_select(top_input_buffer_select),
    .interaction_shift(interaction_shift),
    .result_valid(result_valid),
    .result_ready(result_ready),
    .result_data(result_data),
    .result_index(result_index),
    .result_last(result_last),
    .result_tag(result_tag),
    .busy(busy),
    .done(done),
    .phase(phase),
    .bottom_result_count(bottom_result_count),
    .interaction_result_count(interaction_result_count),
    .error_valid(error_valid),
    .error_ready(error_ready),
    .error_code(error_code)
  );

endmodule
