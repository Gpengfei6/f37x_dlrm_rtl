`timescale 1ns/1ps

// Stage 2N-A5 internal DLRM pipeline controller.
//
// One host-visible start request automatically performs:
//   1. Bottom-MLP descriptor segment;
//   2. feature interaction using the Bottom-MLP 8-vector plus four embeddings;
//   3. loading the 18 interaction outputs into the shared activation buffer;
//   4. Top-MLP descriptor segment;
//   5. external final-result ready/valid delivery.
//
// The arithmetic modules are reused unchanged. There is one dense engine and
// one pair of activation buffers; Bottom and Top segments are selected through
// descriptor_base/layer_count pairs.
module dlrm_internal_pipeline_controller #(
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

  output logic                                      error_valid,
  input  logic                                      error_ready,
  output logic [7:0]                                error_code
);

  localparam logic [7:0] ERROR_NONE                 = 8'h00;
  localparam logic [7:0] ERROR_MISSING_EMBEDDING    = 8'h01;
  localparam logic [7:0] ERROR_BOTTOM_PROTOCOL      = 8'h02;
  localparam logic [7:0] ERROR_INTERACTION_PROTOCOL = 8'h03;
  localparam logic [7:0] ERROR_MLP_BASE             = 8'h20;
  localparam logic [7:0] ERROR_INTERACTION_BASE     = 8'h40;

  typedef enum logic [3:0] {
    STATE_IDLE,
    STATE_START_BOTTOM,
    STATE_RUN_BOTTOM,
    STATE_LOAD_BOTTOM_VECTOR,
    STATE_LOAD_EMBEDDING,
    STATE_START_INTERACTION,
    STATE_RUN_INTERACTION,
    STATE_WAIT_INTERACTION_DONE,
    STATE_LOAD_TOP_CHUNK0,
    STATE_LOAD_TOP_CHUNK1,
    STATE_START_TOP,
    STATE_RUN_TOP,
    STATE_FINISH,
    STATE_ERROR
  } state_t;

  state_t state;

  logic [8*INPUT_WIDTH-1:0] embedding_mem [0:3];
  logic [3:0] embedding_loaded;
  logic [1:0] embedding_load_index;

  logic signed [INPUT_WIDTH-1:0] bottom_vector [0:7];
  logic signed [INPUT_WIDTH-1:0] interaction_vector [0:17];
  logic [8*INPUT_WIDTH-1:0] bottom_vector_packed;
  logic [NUM_PE*INPUT_WIDTH-1:0] top_chunk0_data;
  logic [NUM_PE*INPUT_WIDTH-1:0] top_chunk1_data;

  logic [LAYER_INDEX_WIDTH-1:0] bottom_descriptor_base_reg;
  logic [LAYER_COUNT_WIDTH-1:0] bottom_layer_count_reg;
  logic [LAYER_INDEX_WIDTH-1:0] top_descriptor_base_reg;
  logic [LAYER_COUNT_WIDTH-1:0] top_layer_count_reg;
  logic bottom_initial_buffer_reg;
  logic top_input_buffer_reg;
  logic [SHIFT_WIDTH-1:0] interaction_shift_reg;

  logic [3:0] bottom_result_count_reg;
  logic [4:0] interaction_result_count_reg;
  logic interaction_last_seen;

  logic error_valid_reg;
  logic [7:0] error_code_reg;

  logic mlp_descriptor_cfg_valid;
  logic mlp_descriptor_cfg_ready;
  logic mlp_start_valid;
  logic mlp_start_ready;
  logic [LAYER_INDEX_WIDTH-1:0] mlp_descriptor_base;
  logic [LAYER_COUNT_WIDTH-1:0] mlp_layer_count;
  logic mlp_initial_buffer_select;

  logic mlp_act_load_valid;
  logic mlp_act_load_ready;
  logic mlp_act_load_buffer_select;
  logic [ACT_CHUNK_ADDR_WIDTH-1:0] mlp_act_load_chunk_index;
  logic [NUM_PE-1:0] mlp_act_load_lane_mask;
  logic [NUM_PE*INPUT_WIDTH-1:0] mlp_act_load_data;

  logic mlp_weight_cfg_valid;
  logic mlp_weight_cfg_ready;
  logic mlp_bias_cfg_valid;
  logic mlp_bias_cfg_ready;

  logic mlp_result_valid;
  logic mlp_result_ready;
  logic signed [OUTPUT_WIDTH-1:0] mlp_result_data;
  logic [OUT_INDEX_WIDTH-1:0] mlp_result_index;
  logic mlp_result_last;
  logic [JOB_TAG_WIDTH-1:0] mlp_result_tag;
  logic mlp_busy;
  logic mlp_done;
  logic mlp_final_buffer_select;
  logic mlp_error_valid;
  logic mlp_error_ready;
  logic [3:0] mlp_error_code;

  logic interaction_vector_load_valid;
  logic interaction_vector_load_ready;
  logic [2:0] interaction_vector_load_index;
  logic [8*INPUT_WIDTH-1:0] interaction_vector_load_data;
  logic interaction_start_valid;
  logic interaction_start_ready;
  logic interaction_result_valid;
  logic interaction_result_ready;
  logic signed [OUTPUT_WIDTH-1:0] interaction_result_data;
  logic [4:0] interaction_result_index;
  logic interaction_result_last;
  logic interaction_busy;
  logic interaction_done;
  logic interaction_error_valid;
  logic interaction_error_ready;
  logic [3:0] interaction_error_code;

  logic config_window_open;

  integer pack_index;
  integer reset_index;

  assign phase = state;
  assign busy = (state != STATE_IDLE);
  assign done = (state == STATE_FINISH);
  assign error_valid = error_valid_reg;
  assign error_code = error_code_reg;
  assign embedding_loaded_mask = embedding_loaded;
  assign bottom_result_count = bottom_result_count_reg;
  assign interaction_result_count = interaction_result_count_reg;

  assign config_window_open =
      (state == STATE_IDLE) &&
      !pipeline_start_valid &&
      !error_valid_reg;

  assign mlp_descriptor_cfg_valid =
      descriptor_cfg_valid && config_window_open;
  assign descriptor_cfg_ready =
      config_window_open && mlp_descriptor_cfg_ready;

  assign embedding_cfg_ready = config_window_open;

  assign mlp_weight_cfg_valid =
      weight_cfg_valid && config_window_open;
  assign weight_cfg_ready =
      config_window_open && mlp_weight_cfg_ready;

  assign mlp_bias_cfg_valid =
      bias_cfg_valid && config_window_open;
  assign bias_cfg_ready =
      config_window_open && mlp_bias_cfg_ready;

  assign pipeline_start_ready =
      (state == STATE_IDLE) &&
      !error_valid_reg &&
      (embedding_loaded == 4'hF) &&
      mlp_start_ready &&
      !descriptor_cfg_valid &&
      !act_load_valid &&
      !embedding_cfg_valid &&
      !weight_cfg_valid &&
      !bias_cfg_valid;

  always_comb begin
    mlp_start_valid = 1'b0;
    mlp_descriptor_base = '0;
    mlp_layer_count = '0;
    mlp_initial_buffer_select = 1'b0;

    if (state == STATE_START_BOTTOM) begin
      mlp_start_valid = 1'b1;
      mlp_descriptor_base = bottom_descriptor_base_reg;
      mlp_layer_count = bottom_layer_count_reg;
      mlp_initial_buffer_select = bottom_initial_buffer_reg;
    end else if (state == STATE_START_TOP) begin
      mlp_start_valid = 1'b1;
      mlp_descriptor_base = top_descriptor_base_reg;
      mlp_layer_count = top_layer_count_reg;
      mlp_initial_buffer_select = top_input_buffer_reg;
    end
  end

  always_comb begin
    mlp_act_load_valid = 1'b0;
    mlp_act_load_buffer_select = act_load_buffer_select;
    mlp_act_load_chunk_index = act_load_chunk_index;
    mlp_act_load_lane_mask = act_load_lane_mask;
    mlp_act_load_data = act_load_data;
    act_load_ready = 1'b0;

    if (config_window_open) begin
      mlp_act_load_valid = act_load_valid;
      act_load_ready = mlp_act_load_ready;
    end else if (state == STATE_LOAD_TOP_CHUNK0) begin
      mlp_act_load_valid = 1'b1;
      mlp_act_load_buffer_select = top_input_buffer_reg;
      mlp_act_load_chunk_index = '0;
      mlp_act_load_lane_mask = {NUM_PE{1'b1}};
      mlp_act_load_data = top_chunk0_data;
    end else if (state == STATE_LOAD_TOP_CHUNK1) begin
      mlp_act_load_valid = 1'b1;
      mlp_act_load_buffer_select = top_input_buffer_reg;
      mlp_act_load_chunk_index = {{(ACT_CHUNK_ADDR_WIDTH-1){1'b0}}, 1'b1};
      mlp_act_load_lane_mask = {{(NUM_PE-2){1'b0}}, 2'b11};
      mlp_act_load_data = top_chunk1_data;
    end
  end

  assign mlp_result_ready =
      (state == STATE_RUN_BOTTOM) ? 1'b1 :
      (state == STATE_RUN_TOP) ? result_ready : 1'b0;

  assign result_valid =
      (state == STATE_RUN_TOP) && mlp_result_valid;
  assign result_data = mlp_result_data;
  assign result_index = mlp_result_index;
  assign result_last = mlp_result_last;
  assign result_tag = mlp_result_tag;

  always_comb begin
    interaction_vector_load_valid = 1'b0;
    interaction_vector_load_index = 3'd0;
    interaction_vector_load_data = '0;

    if (state == STATE_LOAD_BOTTOM_VECTOR) begin
      interaction_vector_load_valid = 1'b1;
      interaction_vector_load_index = 3'd0;
      interaction_vector_load_data = bottom_vector_packed;
    end else if (state == STATE_LOAD_EMBEDDING) begin
      interaction_vector_load_valid = 1'b1;
      interaction_vector_load_index = {1'b0, embedding_load_index} + 1'b1;
      interaction_vector_load_data = embedding_mem[embedding_load_index];
    end
  end

  assign interaction_start_valid =
      (state == STATE_START_INTERACTION);
  assign interaction_result_ready =
      (state == STATE_RUN_INTERACTION);

  assign mlp_error_ready =
      (state == STATE_ERROR) && error_valid_reg && error_ready;
  assign interaction_error_ready =
      (state == STATE_ERROR) && error_valid_reg && error_ready;

  always_comb begin
    bottom_vector_packed = '0;
    top_chunk0_data = '0;
    top_chunk1_data = '0;

    for (pack_index = 0; pack_index < 8; pack_index = pack_index + 1) begin
      bottom_vector_packed[pack_index*INPUT_WIDTH +: INPUT_WIDTH] =
          bottom_vector[pack_index];
    end

    for (pack_index = 0; pack_index < NUM_PE; pack_index = pack_index + 1) begin
      if (pack_index < 16) begin
        top_chunk0_data[pack_index*INPUT_WIDTH +: INPUT_WIDTH] =
            interaction_vector[pack_index];
      end
    end

    top_chunk1_data[0 +: INPUT_WIDTH] = interaction_vector[16];
    top_chunk1_data[INPUT_WIDTH +: INPUT_WIDTH] = interaction_vector[17];
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      state <= STATE_IDLE;
      embedding_loaded <= '0;
      embedding_load_index <= '0;
      bottom_descriptor_base_reg <= '0;
      bottom_layer_count_reg <= '0;
      top_descriptor_base_reg <= '0;
      top_layer_count_reg <= '0;
      bottom_initial_buffer_reg <= 1'b0;
      top_input_buffer_reg <= 1'b0;
      interaction_shift_reg <= '0;
      bottom_result_count_reg <= '0;
      interaction_result_count_reg <= '0;
      interaction_last_seen <= 1'b0;
      error_valid_reg <= 1'b0;
      error_code_reg <= ERROR_NONE;

      for (reset_index = 0; reset_index < 4; reset_index = reset_index + 1)
        embedding_mem[reset_index] <= '0;
      for (reset_index = 0; reset_index < 8; reset_index = reset_index + 1)
        bottom_vector[reset_index] <= '0;
      for (reset_index = 0; reset_index < 18; reset_index = reset_index + 1)
        interaction_vector[reset_index] <= '0;
    end else begin
      if (embedding_cfg_valid && embedding_cfg_ready) begin
        embedding_mem[embedding_cfg_index] <= embedding_cfg_data;
        embedding_loaded[embedding_cfg_index] <= 1'b1;
      end

      if (mlp_error_valid && !error_valid_reg) begin
        error_valid_reg <= 1'b1;
        error_code_reg <= ERROR_MLP_BASE | mlp_error_code;
        state <= STATE_ERROR;
      end else if (interaction_error_valid && !error_valid_reg) begin
        error_valid_reg <= 1'b1;
        error_code_reg <= ERROR_INTERACTION_BASE | interaction_error_code;
        state <= STATE_ERROR;
      end else begin
        case (state)
          STATE_IDLE: begin
            bottom_result_count_reg <= '0;
            interaction_result_count_reg <= '0;
            interaction_last_seen <= 1'b0;

            if (pipeline_start_valid) begin
              if (embedding_loaded != 4'hF) begin
                error_valid_reg <= 1'b1;
                error_code_reg <= ERROR_MISSING_EMBEDDING;
                state <= STATE_ERROR;
              end else if (pipeline_start_ready) begin
                bottom_descriptor_base_reg <= bottom_descriptor_base;
                bottom_layer_count_reg <= bottom_layer_count;
                top_descriptor_base_reg <= top_descriptor_base;
                top_layer_count_reg <= top_layer_count;
                bottom_initial_buffer_reg <= bottom_initial_buffer_select;
                top_input_buffer_reg <= top_input_buffer_select;
                interaction_shift_reg <= interaction_shift;
                state <= STATE_START_BOTTOM;
              end
            end
          end

          STATE_START_BOTTOM: begin
            if (mlp_start_valid && mlp_start_ready)
              state <= STATE_RUN_BOTTOM;
          end

          STATE_RUN_BOTTOM: begin
            if (mlp_result_valid && mlp_result_ready) begin
              if ((bottom_result_count_reg >= 8) ||
                  (mlp_result_index != bottom_result_count_reg) ||
                  (mlp_result_last != (bottom_result_count_reg == 7))) begin
                error_valid_reg <= 1'b1;
                error_code_reg <= ERROR_BOTTOM_PROTOCOL;
                state <= STATE_ERROR;
              end else begin
                bottom_vector[bottom_result_count_reg] <= mlp_result_data;
                bottom_result_count_reg <= bottom_result_count_reg + 1'b1;
              end
            end

            if (mlp_done) begin
              if (bottom_result_count_reg != 8) begin
                error_valid_reg <= 1'b1;
                error_code_reg <= ERROR_BOTTOM_PROTOCOL;
                state <= STATE_ERROR;
              end else begin
                state <= STATE_LOAD_BOTTOM_VECTOR;
              end
            end
          end

          STATE_LOAD_BOTTOM_VECTOR: begin
            if (interaction_vector_load_valid &&
                interaction_vector_load_ready) begin
              embedding_load_index <= 2'd0;
              state <= STATE_LOAD_EMBEDDING;
            end
          end

          STATE_LOAD_EMBEDDING: begin
            if (interaction_vector_load_valid &&
                interaction_vector_load_ready) begin
              if (embedding_load_index == 2'd3) begin
                state <= STATE_START_INTERACTION;
              end else begin
                embedding_load_index <= embedding_load_index + 1'b1;
              end
            end
          end

          STATE_START_INTERACTION: begin
            if (interaction_start_valid && interaction_start_ready) begin
              interaction_result_count_reg <= '0;
              interaction_last_seen <= 1'b0;
              state <= STATE_RUN_INTERACTION;
            end
          end

          STATE_RUN_INTERACTION: begin
            if (interaction_result_valid && interaction_result_ready) begin
              if ((interaction_result_count_reg >= 18) ||
                  (interaction_result_index != interaction_result_count_reg) ||
                  (interaction_result_last !=
                   (interaction_result_count_reg == 17))) begin
                error_valid_reg <= 1'b1;
                error_code_reg <= ERROR_INTERACTION_PROTOCOL;
                state <= STATE_ERROR;
              end else begin
                interaction_vector[interaction_result_count_reg] <=
                    interaction_result_data;
                interaction_result_count_reg <=
                    interaction_result_count_reg + 1'b1;
                if (interaction_result_last) begin
                  interaction_last_seen <= 1'b1;
                  state <= STATE_WAIT_INTERACTION_DONE;
                end
              end
            end
          end

          STATE_WAIT_INTERACTION_DONE: begin
            if (interaction_done) begin
              if ((interaction_result_count_reg != 18) ||
                  !interaction_last_seen) begin
                error_valid_reg <= 1'b1;
                error_code_reg <= ERROR_INTERACTION_PROTOCOL;
                state <= STATE_ERROR;
              end else begin
                state <= STATE_LOAD_TOP_CHUNK0;
              end
            end
          end

          STATE_LOAD_TOP_CHUNK0: begin
            if (mlp_act_load_valid && mlp_act_load_ready)
              state <= STATE_LOAD_TOP_CHUNK1;
          end

          STATE_LOAD_TOP_CHUNK1: begin
            if (mlp_act_load_valid && mlp_act_load_ready)
              state <= STATE_START_TOP;
          end

          STATE_START_TOP: begin
            if (mlp_start_valid && mlp_start_ready)
              state <= STATE_RUN_TOP;
          end

          STATE_RUN_TOP: begin
            if (mlp_done)
              state <= STATE_FINISH;
          end

          STATE_FINISH: begin
            state <= STATE_IDLE;
          end

          STATE_ERROR: begin
            if (error_valid_reg && error_ready) begin
              error_valid_reg <= 1'b0;
              error_code_reg <= ERROR_NONE;
              state <= STATE_IDLE;
            end
          end

          default: begin
            error_valid_reg <= 1'b1;
            error_code_reg <= ERROR_INTERACTION_PROTOCOL;
            state <= STATE_ERROR;
          end
        endcase
      end
    end
  end

  mlp_sequence_controller_segmented #(
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
  ) u_segmented_mlp (
    .clk(clk),
    .rst(rst),
    .descriptor_cfg_valid(mlp_descriptor_cfg_valid),
    .descriptor_cfg_ready(mlp_descriptor_cfg_ready),
    .descriptor_cfg_index(descriptor_cfg_index),
    .descriptor_cfg_data(descriptor_cfg_data),
    .start_valid(mlp_start_valid),
    .start_ready(mlp_start_ready),
    .descriptor_base(mlp_descriptor_base),
    .layer_count(mlp_layer_count),
    .initial_buffer_select(mlp_initial_buffer_select),
    .act_load_valid(mlp_act_load_valid),
    .act_load_ready(mlp_act_load_ready),
    .act_load_buffer_select(mlp_act_load_buffer_select),
    .act_load_chunk_index(mlp_act_load_chunk_index),
    .act_load_lane_mask(mlp_act_load_lane_mask),
    .act_load_data(mlp_act_load_data),
    .weight_cfg_valid(mlp_weight_cfg_valid),
    .weight_cfg_ready(mlp_weight_cfg_ready),
    .weight_cfg_address(weight_cfg_address),
    .weight_cfg_data(weight_cfg_data),
    .bias_cfg_valid(mlp_bias_cfg_valid),
    .bias_cfg_ready(mlp_bias_cfg_ready),
    .bias_cfg_address(bias_cfg_address),
    .bias_cfg_data(bias_cfg_data),
    .result_valid(mlp_result_valid),
    .result_ready(mlp_result_ready),
    .result_data(mlp_result_data),
    .result_index(mlp_result_index),
    .result_last(mlp_result_last),
    .result_tag(mlp_result_tag),
    .busy(mlp_busy),
    .done(mlp_done),
    .final_buffer_select(mlp_final_buffer_select),
    .error_valid(mlp_error_valid),
    .error_ready(mlp_error_ready),
    .error_code(mlp_error_code)
  );

  dlrm_feature_interaction_engine #(
    .VECTOR_COUNT(5),
    .VECTOR_DIM(8),
    .INPUT_WIDTH(INPUT_WIDTH),
    .ACC_WIDTH(ACC_WIDTH),
    .OUTPUT_WIDTH(OUTPUT_WIDTH)
  ) u_interaction (
    .clk(clk),
    .rst(rst),
    .vector_load_valid(interaction_vector_load_valid),
    .vector_load_ready(interaction_vector_load_ready),
    .vector_load_index(interaction_vector_load_index),
    .vector_load_data(interaction_vector_load_data),
    .start_valid(interaction_start_valid),
    .start_ready(interaction_start_ready),
    .interaction_shift(interaction_shift_reg),
    .result_valid(interaction_result_valid),
    .result_ready(interaction_result_ready),
    .result_data(interaction_result_data),
    .result_index(interaction_result_index),
    .result_last(interaction_result_last),
    .busy(interaction_busy),
    .done(interaction_done),
    .error_valid(interaction_error_valid),
    .error_ready(interaction_error_ready),
    .error_code(interaction_error_code)
  );

  initial begin
    if (NUM_PE != 16)
      $error("dlrm_internal_pipeline_controller currently requires NUM_PE=16");
    if (INPUT_WIDTH != 16)
      $error("dlrm_internal_pipeline_controller requires signed INT16 activations");
    if (OUTPUT_WIDTH != 16)
      $error("dlrm_internal_pipeline_controller requires signed INT16 outputs");
    if (MAX_IN_DIM < 18)
      $error("dlrm_internal_pipeline_controller MAX_IN_DIM must be at least 18");
  end

endmodule
