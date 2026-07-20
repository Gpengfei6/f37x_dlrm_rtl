`timescale 1ns/1ps

module dense_layer_engine #(
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
  parameter integer IN_DIM_WIDTH =
      (MAX_IN_DIM <= 1) ? 1 : $clog2(MAX_IN_DIM+1),
  parameter integer OUT_DIM_WIDTH =
      (MAX_OUT_DIM <= 1) ? 1 : $clog2(MAX_OUT_DIM+1),
  parameter integer OUT_INDEX_WIDTH =
      (MAX_OUT_DIM <= 1) ? 1 : $clog2(MAX_OUT_DIM),
  parameter integer ACT_MAX_DIM =
      (MAX_IN_DIM > MAX_OUT_DIM) ? MAX_IN_DIM : MAX_OUT_DIM,
  parameter integer ACT_BANK_DEPTH = (ACT_MAX_DIM+NUM_PE-1)/NUM_PE,
  parameter integer ACT_CHUNK_ADDR_WIDTH =
      (ACT_BANK_DEPTH <= 1) ? 1 : $clog2(ACT_BANK_DEPTH),
  parameter integer ACT_INDEX_WIDTH =
      (ACT_MAX_DIM <= 1) ? 1 : $clog2(ACT_MAX_DIM),
  parameter integer SHIFT_WIDTH = (ACC_WIDTH <= 1) ? 1 : $clog2(ACC_WIDTH+1)
) (
  input  logic                                      clk,
  input  logic                                      rst,

  input  logic                                      job_valid,
  output logic                                      job_ready,
  input  logic [IN_DIM_WIDTH-1:0]                   job_in_dim,
  input  logic [OUT_DIM_WIDTH-1:0]                  job_out_dim,
  input  logic                                      job_input_buffer_select,
  input  logic                                      job_output_buffer_select,
  input  logic [WEIGHT_ADDR_WIDTH-1:0]              job_weight_offset,
  input  logic [BIAS_ADDR_WIDTH-1:0]                job_bias_offset,
  input  logic [SHIFT_WIDTH-1:0]                    job_output_shift,
  input  logic                                      job_relu_enable,
  input  logic [JOB_TAG_WIDTH-1:0]                  job_tag,

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
  output logic                                      job_done,

  output logic                                      error_valid,
  input  logic                                      error_ready,
  output logic [3:0]                                error_code
);
  localparam logic [3:0] STATE_IDLE        = 4'd0;
  localparam logic [3:0] STATE_BIAS_REQ    = 4'd1;
  localparam logic [3:0] STATE_BIAS_WAIT   = 4'd2;
  localparam logic [3:0] STATE_DOT_COMMAND = 4'd3;
  localparam logic [3:0] STATE_FETCH_REQ   = 4'd4;
  localparam logic [3:0] STATE_FETCH_JOIN  = 4'd5;
  localparam logic [3:0] STATE_WAIT_DOT    = 4'd6;
  localparam logic [3:0] STATE_DRAIN       = 4'd7;
  localparam logic [3:0] STATE_ERROR       = 4'd8;

  localparam logic [3:0] ERROR_BAD_DIMENSION = 4'd1;
  localparam logic [3:0] ERROR_BUFFER_ALIAS  = 4'd2;
  localparam logic [3:0] ERROR_BAD_SHIFT     = 4'd3;
  localparam logic [3:0] ERROR_PROVIDER      = 4'd4;
  localparam logic [3:0] ERROR_DOT_PROTOCOL  = 4'd5;

  localparam integer RESULT_PAYLOAD_WIDTH =
      OUTPUT_WIDTH + OUT_INDEX_WIDTH + 1 + JOB_TAG_WIDTH;
  localparam integer FIFO_COUNT_WIDTH = $clog2(RESULT_FIFO_DEPTH+1);

  logic [3:0] state;
  logic [IN_DIM_WIDTH-1:0] descriptor_in_dim;
  logic [OUT_DIM_WIDTH-1:0] descriptor_out_dim;
  logic descriptor_input_buffer;
  logic descriptor_output_buffer;
  logic [WEIGHT_ADDR_WIDTH-1:0] descriptor_weight_offset;
  logic [BIAS_ADDR_WIDTH-1:0] descriptor_bias_offset;
  logic [SHIFT_WIDTH-1:0] descriptor_output_shift;
  logic descriptor_relu_enable;
  logic [JOB_TAG_WIDTH-1:0] descriptor_tag;

  logic [OUT_INDEX_WIDTH-1:0] output_index_counter;
  logic [ACT_INDEX_WIDTH-1:0] output_scalar_write_index;
  logic [IN_DIM_WIDTH-1:0] chunk_index_counter;
  logic [NUM_PE-1:0] current_lane_mask;
  logic current_chunk_last;
  logic descriptor_invalid_dimension;
  logic descriptor_invalid_shift;

  logic buffer0_load_ready;
  logic buffer1_load_ready;
  logic buffer0_read_req_valid;
  logic buffer0_read_req_ready;
  logic buffer1_read_req_valid;
  logic buffer1_read_req_ready;
  logic buffer0_read_rsp_valid;
  logic buffer0_read_rsp_ready;
  logic buffer1_read_rsp_valid;
  logic buffer1_read_rsp_ready;
  logic [NUM_PE*INPUT_WIDTH-1:0] buffer0_read_rsp_data;
  logic [NUM_PE*INPUT_WIDTH-1:0] buffer1_read_rsp_data;
  logic buffer0_scalar_valid;
  logic buffer0_scalar_ready;
  logic buffer1_scalar_valid;
  logic buffer1_scalar_ready;
  logic buffer0_access_error;
  logic buffer1_access_error;
  logic selected_act_req_ready;
  logic selected_act_rsp_valid;
  logic selected_act_rsp_ready;
  logic [NUM_PE*INPUT_WIDTH-1:0] selected_act_rsp_data;
  logic selected_scalar_ready;

  logic provider_weight_cfg_ready;
  logic provider_bias_cfg_ready;
  logic provider_weight_req_valid;
  logic provider_weight_req_ready;
  logic [WEIGHT_ADDR_WIDTH-1:0] provider_weight_req_address;
  logic provider_weight_rsp_valid;
  logic provider_weight_rsp_ready;
  logic [NUM_PE*WEIGHT_WIDTH-1:0] provider_weight_rsp_data;
  logic provider_weight_rsp_error;
  logic provider_bias_req_valid;
  logic provider_bias_req_ready;
  logic [BIAS_ADDR_WIDTH-1:0] provider_bias_req_address;
  logic provider_bias_rsp_valid;
  logic provider_bias_rsp_ready;
  logic signed [BIAS_WIDTH-1:0] provider_bias_rsp_data;
  logic provider_bias_rsp_error;
  logic signed [BIAS_WIDTH-1:0] bias_hold;

  logic act_request_sent;
  logic weight_request_sent;
  logic activation_request_valid;
  logic activation_request_fire;
  logic weight_request_fire;
  logic joined_response_valid;
  logic joined_response_error;
  logic joined_response_ready;

  logic dot_command_valid;
  logic dot_command_ready;
  logic dot_chunk_valid;
  logic dot_chunk_ready;
  logic dot_result_valid;
  logic dot_result_ready;
  logic signed [ACC_WIDTH-1:0] dot_result_data;
  logic dot_protocol_error;
  logic core_reset;

  logic signed [OUTPUT_WIDTH-1:0] quantized_result;
  logic quant_invalid_shift;
  logic commit_ready;

  logic fifo_in_valid;
  logic fifo_in_ready;
  logic [RESULT_PAYLOAD_WIDTH-1:0] fifo_in_data;
  logic fifo_out_valid;
  logic [RESULT_PAYLOAD_WIDTH-1:0] fifo_out_data;
  logic fifo_full;
  logic fifo_empty;
  logic [FIFO_COUNT_WIDTH-1:0] fifo_count;

  assign descriptor_invalid_dimension =
      (job_in_dim == 0) || (job_in_dim > MAX_IN_DIM) ||
      (job_out_dim == 0) || (job_out_dim > MAX_OUT_DIM);
  assign descriptor_invalid_shift = (job_output_shift > ACC_WIDTH);
  assign job_ready = (state == STATE_IDLE) && fifo_empty && !error_valid;

  assign act_load_ready = (state == STATE_IDLE) &&
      (act_load_buffer_select ? buffer1_load_ready : buffer0_load_ready);
  assign weight_cfg_ready = (state == STATE_IDLE) && provider_weight_cfg_ready;
  assign bias_cfg_ready = (state == STATE_IDLE) && provider_bias_cfg_ready;

  always_comb begin : make_lane_mask
    integer mask_lane;
    current_lane_mask = '0;
    for (mask_lane = 0; mask_lane < NUM_PE; mask_lane = mask_lane + 1)
      if ((chunk_index_counter*NUM_PE + mask_lane) < descriptor_in_dim)
        current_lane_mask[mask_lane] = 1'b1;
    current_chunk_last =
        ((chunk_index_counter+1'b1)*NUM_PE >= descriptor_in_dim);
  end

  assign activation_request_valid =
      (state == STATE_FETCH_REQ) && !act_request_sent;
  assign provider_weight_req_valid =
      (state == STATE_FETCH_REQ) && !weight_request_sent;
  assign activation_request_fire =
      activation_request_valid && selected_act_req_ready;
  assign weight_request_fire =
      provider_weight_req_valid && provider_weight_req_ready;

  assign buffer0_read_req_valid =
      activation_request_valid && !descriptor_input_buffer;
  assign buffer1_read_req_valid =
      activation_request_valid && descriptor_input_buffer;
  assign selected_act_req_ready = descriptor_input_buffer ?
      buffer1_read_req_ready : buffer0_read_req_ready;
  assign selected_act_rsp_valid = descriptor_input_buffer ?
      buffer1_read_rsp_valid : buffer0_read_rsp_valid;
  assign selected_act_rsp_data = descriptor_input_buffer ?
      buffer1_read_rsp_data : buffer0_read_rsp_data;
  assign buffer0_read_rsp_ready =
      !descriptor_input_buffer && selected_act_rsp_ready;
  assign buffer1_read_rsp_ready =
      descriptor_input_buffer && selected_act_rsp_ready;

  assign provider_weight_req_address = descriptor_weight_offset +
      output_index_counter*descriptor_in_dim + chunk_index_counter*NUM_PE;
  assign provider_bias_req_address =
      descriptor_bias_offset + output_index_counter;

  assign joined_response_valid = selected_act_rsp_valid &&
                                 provider_weight_rsp_valid;
  assign joined_response_error = joined_response_valid &&
                                 provider_weight_rsp_error;
  assign joined_response_ready = joined_response_error || dot_chunk_ready;
  assign selected_act_rsp_ready = (state == STATE_FETCH_JOIN) &&
      provider_weight_rsp_valid && joined_response_ready;
  assign provider_weight_rsp_ready = (state == STATE_FETCH_JOIN) &&
      selected_act_rsp_valid && joined_response_ready;

  assign dot_command_valid = (state == STATE_DOT_COMMAND);
  assign dot_chunk_valid = (state == STATE_FETCH_JOIN) &&
      joined_response_valid && !joined_response_error;
  assign dot_result_ready = (state == STATE_WAIT_DOT) && commit_ready;
  assign core_reset = rst || (state == STATE_ERROR);

  assign selected_scalar_ready = descriptor_output_buffer ?
      buffer1_scalar_ready : buffer0_scalar_ready;
  assign commit_ready = fifo_in_ready && selected_scalar_ready &&
                        !quant_invalid_shift;
  assign fifo_in_valid = (state == STATE_WAIT_DOT) && dot_result_valid &&
                         selected_scalar_ready && !quant_invalid_shift;
  assign fifo_in_data = {descriptor_tag,
                         (output_index_counter == descriptor_out_dim-1'b1),
                         output_index_counter, quantized_result};
  assign buffer0_scalar_valid = (state == STATE_WAIT_DOT) &&
      dot_result_valid && fifo_in_ready && !quant_invalid_shift &&
      !descriptor_output_buffer;
  assign buffer1_scalar_valid = (state == STATE_WAIT_DOT) &&
      dot_result_valid && fifo_in_ready && !quant_invalid_shift &&
      descriptor_output_buffer;
  assign output_scalar_write_index =
      ACT_INDEX_WIDTH'(output_index_counter);

  assign result_valid = fifo_out_valid;
  assign result_data = fifo_out_data[0 +: OUTPUT_WIDTH];
  assign result_index = fifo_out_data[OUTPUT_WIDTH +: OUT_INDEX_WIDTH];
  assign result_last = fifo_out_data[OUTPUT_WIDTH+OUT_INDEX_WIDTH];
  assign result_tag = fifo_out_data[OUTPUT_WIDTH+OUT_INDEX_WIDTH+1 +:
                                    JOB_TAG_WIDTH];

  banked_activation_buffer #(
    .MAX_DIM(ACT_MAX_DIM),
    .NUM_BANKS(NUM_PE),
    .DATA_WIDTH(INPUT_WIDTH),
    .BANK_DEPTH(ACT_BANK_DEPTH),
    .CHUNK_ADDR_WIDTH(ACT_CHUNK_ADDR_WIDTH),
    .INDEX_WIDTH(ACT_INDEX_WIDTH)
  ) u_activation_buffer0 (
    .clk(clk), .rst(rst),
    .load_valid(act_load_valid && act_load_ready && !act_load_buffer_select),
    .load_ready(buffer0_load_ready),
    .load_chunk_index(act_load_chunk_index),
    .load_lane_mask(act_load_lane_mask),
    .load_data(act_load_data),
    .read_req_valid(buffer0_read_req_valid),
    .read_req_ready(buffer0_read_req_ready),
    .read_req_chunk_index(chunk_index_counter[ACT_CHUNK_ADDR_WIDTH-1:0]),
    .read_rsp_valid(buffer0_read_rsp_valid),
    .read_rsp_ready(buffer0_read_rsp_ready),
    .read_rsp_data(buffer0_read_rsp_data),
    .scalar_write_valid(buffer0_scalar_valid),
    .scalar_write_ready(buffer0_scalar_ready),
    .scalar_write_index(output_scalar_write_index),
    .scalar_write_data(quantized_result),
    .access_error(buffer0_access_error)
  );

  banked_activation_buffer #(
    .MAX_DIM(ACT_MAX_DIM),
    .NUM_BANKS(NUM_PE),
    .DATA_WIDTH(INPUT_WIDTH),
    .BANK_DEPTH(ACT_BANK_DEPTH),
    .CHUNK_ADDR_WIDTH(ACT_CHUNK_ADDR_WIDTH),
    .INDEX_WIDTH(ACT_INDEX_WIDTH)
  ) u_activation_buffer1 (
    .clk(clk), .rst(rst),
    .load_valid(act_load_valid && act_load_ready && act_load_buffer_select),
    .load_ready(buffer1_load_ready),
    .load_chunk_index(act_load_chunk_index),
    .load_lane_mask(act_load_lane_mask),
    .load_data(act_load_data),
    .read_req_valid(buffer1_read_req_valid),
    .read_req_ready(buffer1_read_req_ready),
    .read_req_chunk_index(chunk_index_counter[ACT_CHUNK_ADDR_WIDTH-1:0]),
    .read_rsp_valid(buffer1_read_rsp_valid),
    .read_rsp_ready(buffer1_read_rsp_ready),
    .read_rsp_data(buffer1_read_rsp_data),
    .scalar_write_valid(buffer1_scalar_valid),
    .scalar_write_ready(buffer1_scalar_ready),
    .scalar_write_index(output_scalar_write_index),
    .scalar_write_data(quantized_result),
    .access_error(buffer1_access_error)
  );

  local_weight_provider #(
    .NUM_PE(NUM_PE),
    .WEIGHT_WIDTH(WEIGHT_WIDTH),
    .BIAS_WIDTH(BIAS_WIDTH),
    .WEIGHT_ADDR_WIDTH(WEIGHT_ADDR_WIDTH),
    .BIAS_ADDR_WIDTH(BIAS_ADDR_WIDTH),
    .MAX_WEIGHT_VALUES(MAX_WEIGHT_VALUES),
    .MAX_BIAS_VALUES(MAX_BIAS_VALUES)
  ) u_weight_provider (
    .clk(clk), .rst(rst),
    .weight_cfg_valid(weight_cfg_valid && (state == STATE_IDLE)),
    .weight_cfg_ready(provider_weight_cfg_ready),
    .weight_cfg_address(weight_cfg_address),
    .weight_cfg_data(weight_cfg_data),
    .bias_cfg_valid(bias_cfg_valid && (state == STATE_IDLE)),
    .bias_cfg_ready(provider_bias_cfg_ready),
    .bias_cfg_address(bias_cfg_address),
    .bias_cfg_data(bias_cfg_data),
    .weight_req_valid(provider_weight_req_valid),
    .weight_req_ready(provider_weight_req_ready),
    .weight_req_address(provider_weight_req_address),
    .weight_req_lane_mask(current_lane_mask),
    .weight_rsp_valid(provider_weight_rsp_valid),
    .weight_rsp_ready(provider_weight_rsp_ready),
    .weight_rsp_data(provider_weight_rsp_data),
    .weight_rsp_error(provider_weight_rsp_error),
    .bias_req_valid(provider_bias_req_valid),
    .bias_req_ready(provider_bias_req_ready),
    .bias_req_address(provider_bias_req_address),
    .bias_rsp_valid(provider_bias_rsp_valid),
    .bias_rsp_ready(provider_bias_rsp_ready),
    .bias_rsp_data(provider_bias_rsp_data),
    .bias_rsp_error(provider_bias_rsp_error)
  );

  vector_dot_product_core #(
    .MAX_IN_DIM(MAX_IN_DIM),
    .NUM_PE(NUM_PE),
    .INPUT_WIDTH(INPUT_WIDTH),
    .WEIGHT_WIDTH(WEIGHT_WIDTH),
    .BIAS_WIDTH(BIAS_WIDTH),
    .ACC_WIDTH(ACC_WIDTH),
    .DIM_WIDTH(IN_DIM_WIDTH)
  ) u_vector_dot (
    .clk(clk), .rst(core_reset),
    .command_valid(dot_command_valid),
    .command_ready(dot_command_ready),
    .command_in_dim(descriptor_in_dim),
    .command_bias(bias_hold),
    .chunk_valid(dot_chunk_valid),
    .chunk_ready(dot_chunk_ready),
    .chunk_inputs(selected_act_rsp_data),
    .chunk_weights(provider_weight_rsp_data),
    .chunk_lane_mask(current_lane_mask),
    .chunk_last(current_chunk_last),
    .result_valid(dot_result_valid),
    .result_ready(dot_result_ready),
    .result_data(dot_result_data),
    .protocol_error(dot_protocol_error)
  );

  runtime_relu_quant #(
    .IN_WIDTH(ACC_WIDTH),
    .OUT_WIDTH(OUTPUT_WIDTH),
    .SHIFT_WIDTH(SHIFT_WIDTH)
  ) u_runtime_quant (
    .in_data(dot_result_data),
    .shift_amount(descriptor_output_shift),
    .relu_enable(descriptor_relu_enable),
    .out_data(quantized_result),
    .invalid_shift(quant_invalid_shift)
  );

  rv_fifo #(
    .DATA_WIDTH(RESULT_PAYLOAD_WIDTH),
    .DEPTH(RESULT_FIFO_DEPTH)
  ) u_result_fifo (
    .clk(clk), .rst(rst),
    .in_valid(fifo_in_valid), .in_ready(fifo_in_ready), .in_data(fifo_in_data),
    .out_valid(fifo_out_valid), .out_ready(result_ready),
    .out_data(fifo_out_data),
    .full(fifo_full), .empty(fifo_empty), .count(fifo_count)
  );

  always_ff @(posedge clk) begin : job_controller
    if (rst) begin
      state <= STATE_IDLE;
      descriptor_in_dim <= '0;
      descriptor_out_dim <= '0;
      descriptor_input_buffer <= 1'b0;
      descriptor_output_buffer <= 1'b1;
      descriptor_weight_offset <= '0;
      descriptor_bias_offset <= '0;
      descriptor_output_shift <= '0;
      descriptor_relu_enable <= 1'b0;
      descriptor_tag <= '0;
      output_index_counter <= '0;
      chunk_index_counter <= '0;
      bias_hold <= '0;
      act_request_sent <= 1'b0;
      weight_request_sent <= 1'b0;
      job_done <= 1'b0;
      error_valid <= 1'b0;
      error_code <= '0;
    end else begin
      job_done <= 1'b0;
      case (state)
        STATE_IDLE: begin
          if (job_valid && job_ready) begin
            if (descriptor_invalid_dimension) begin
              error_valid <= 1'b1;
              error_code <= ERROR_BAD_DIMENSION;
              state <= STATE_ERROR;
            end else if (job_input_buffer_select == job_output_buffer_select) begin
              error_valid <= 1'b1;
              error_code <= ERROR_BUFFER_ALIAS;
              state <= STATE_ERROR;
            end else if (descriptor_invalid_shift) begin
              error_valid <= 1'b1;
              error_code <= ERROR_BAD_SHIFT;
              state <= STATE_ERROR;
            end else begin
              descriptor_in_dim <= job_in_dim;
              descriptor_out_dim <= job_out_dim;
              descriptor_input_buffer <= job_input_buffer_select;
              descriptor_output_buffer <= job_output_buffer_select;
              descriptor_weight_offset <= job_weight_offset;
              descriptor_bias_offset <= job_bias_offset;
              descriptor_output_shift <= job_output_shift;
              descriptor_relu_enable <= job_relu_enable;
              descriptor_tag <= job_tag;
              output_index_counter <= '0;
              chunk_index_counter <= '0;
              state <= STATE_BIAS_REQ;
            end
          end
        end

        STATE_BIAS_REQ: begin
          if (provider_bias_req_valid && provider_bias_req_ready)
            state <= STATE_BIAS_WAIT;
        end

        STATE_BIAS_WAIT: begin
          if (provider_bias_rsp_valid && provider_bias_rsp_ready) begin
            if (provider_bias_rsp_error) begin
              error_valid <= 1'b1;
              error_code <= ERROR_PROVIDER;
              state <= STATE_ERROR;
            end else begin
              bias_hold <= provider_bias_rsp_data;
              state <= STATE_DOT_COMMAND;
            end
          end
        end

        STATE_DOT_COMMAND: begin
          if (dot_command_valid && dot_command_ready) begin
            chunk_index_counter <= '0;
            act_request_sent <= 1'b0;
            weight_request_sent <= 1'b0;
            state <= STATE_FETCH_REQ;
          end
        end

        STATE_FETCH_REQ: begin
          if (activation_request_fire)
            act_request_sent <= 1'b1;
          if (weight_request_fire)
            weight_request_sent <= 1'b1;
          if ((act_request_sent || activation_request_fire) &&
              (weight_request_sent || weight_request_fire))
            state <= STATE_FETCH_JOIN;
        end

        STATE_FETCH_JOIN: begin
          if (joined_response_error) begin
            error_valid <= 1'b1;
            error_code <= ERROR_PROVIDER;
            state <= STATE_ERROR;
          end else if (dot_chunk_valid && dot_chunk_ready) begin
            if (current_chunk_last) begin
              state <= STATE_WAIT_DOT;
            end else begin
              chunk_index_counter <= chunk_index_counter + 1'b1;
              act_request_sent <= 1'b0;
              weight_request_sent <= 1'b0;
              state <= STATE_FETCH_REQ;
            end
          end
        end

        STATE_WAIT_DOT: begin
          if (dot_protocol_error) begin
            error_valid <= 1'b1;
            error_code <= ERROR_DOT_PROTOCOL;
            state <= STATE_ERROR;
          end else if (dot_result_valid && dot_result_ready) begin
            if (output_index_counter == descriptor_out_dim-1'b1) begin
              job_done <= 1'b1;
              state <= STATE_DRAIN;
            end else begin
              output_index_counter <= output_index_counter + 1'b1;
              state <= STATE_BIAS_REQ;
            end
          end
        end

        STATE_DRAIN: begin
          if (fifo_empty)
            state <= STATE_IDLE;
        end

        STATE_ERROR: begin
          if (error_valid && error_ready && fifo_empty) begin
            error_valid <= 1'b0;
            error_code <= '0;
            state <= STATE_IDLE;
          end
        end

        default: state <= STATE_IDLE;
      endcase
    end
  end

  assign provider_bias_req_valid = (state == STATE_BIAS_REQ);
  assign provider_bias_rsp_ready = (state == STATE_BIAS_WAIT);

  initial begin
    if (MAX_IN_DIM <= 0 || MAX_OUT_DIM <= 0 || NUM_PE < 2 ||
        INPUT_WIDTH <= 0 || WEIGHT_WIDTH <= 0 || BIAS_WIDTH <= 0 ||
        ACC_WIDTH <= 0 || OUTPUT_WIDTH <= 0 || RESULT_FIFO_DEPTH <= 0)
      $error("dense_layer_engine parameters are invalid");
    if ((NUM_PE & (NUM_PE-1)) != 0)
      $error("dense_layer_engine NUM_PE must be a power of two");
    if (OUTPUT_WIDTH != INPUT_WIDTH)
      $error("dense_layer_engine ping-pong buffers require OUTPUT_WIDTH=INPUT_WIDTH");
    if (ACT_MAX_DIM < MAX_OUT_DIM)
      $fatal(1, "dense_layer_engine output buffer is smaller than MAX_OUT_DIM");
    if (ACT_INDEX_WIDTH < OUT_INDEX_WIDTH)
      $fatal(1, "dense_layer_engine scalar output index would be truncated");
  end
endmodule
