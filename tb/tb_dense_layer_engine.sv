`timescale 1ns/1ps

module dense_engine_checker #(
  parameter integer NUM_PE = 16,
  parameter integer ACC_WIDTH = 48,
  parameter integer RUN_COMPAT = 0
) (
  input  logic clk,
  input  logic rst,
  output logic done
);
  localparam integer MAX_IN_DIM = 1024;
  localparam integer MAX_OUT_DIM = 32;
  localparam integer IN_DIM_WIDTH = 11;
  localparam integer OUT_DIM_WIDTH = 6;
  localparam integer OUT_INDEX_WIDTH = 5;
  localparam integer INPUT_WIDTH = 16;
  localparam integer OUTPUT_WIDTH = 16;
  localparam integer WEIGHT_WIDTH = 8;
  localparam integer BIAS_WIDTH = 24;
  localparam integer ACT_BANK_DEPTH = MAX_IN_DIM/NUM_PE;
  localparam integer ACT_CHUNK_ADDR_WIDTH = $clog2(ACT_BANK_DEPTH);
  localparam integer SHIFT_WIDTH = $clog2(ACC_WIDTH+1);
  localparam integer PHASE1_CASE_COUNT = 24;
  localparam integer PHASE1_IN_DIM = 8;
  localparam integer PHASE1_OUT_DIM = 4;
  localparam integer PHASE1_INPUT_WIDTH = 10;
  localparam integer PHASE1_INPUT_ROW_WIDTH =
      PHASE1_IN_DIM*PHASE1_INPUT_WIDTH;
  localparam integer PHASE1_OUTPUT_ROW_WIDTH =
      PHASE1_OUT_DIM*OUTPUT_WIDTH;

  logic job_valid;
  logic job_ready;
  logic [IN_DIM_WIDTH-1:0] job_in_dim;
  logic [OUT_DIM_WIDTH-1:0] job_out_dim;
  logic job_input_buffer_select;
  logic job_output_buffer_select;
  logic [31:0] job_weight_offset;
  logic [31:0] job_bias_offset;
  logic [SHIFT_WIDTH-1:0] job_output_shift;
  logic job_relu_enable;
  logic [7:0] job_tag;
  logic act_load_valid;
  logic act_load_ready;
  logic act_load_buffer_select;
  logic [ACT_CHUNK_ADDR_WIDTH-1:0] act_load_chunk_index;
  logic [NUM_PE-1:0] act_load_lane_mask;
  logic [NUM_PE*INPUT_WIDTH-1:0] act_load_data;
  logic weight_cfg_valid;
  logic weight_cfg_ready;
  logic [31:0] weight_cfg_address;
  logic signed [WEIGHT_WIDTH-1:0] weight_cfg_data;
  logic bias_cfg_valid;
  logic bias_cfg_ready;
  logic [31:0] bias_cfg_address;
  logic signed [BIAS_WIDTH-1:0] bias_cfg_data;
  logic result_valid;
  logic result_ready;
  logic signed [OUTPUT_WIDTH-1:0] result_data;
  logic [OUT_INDEX_WIDTH-1:0] result_index;
  logic result_last;
  logic [7:0] result_tag;
  logic job_done;
  logic error_valid;
  logic error_ready;
  logic [3:0] error_code;
  logic [PHASE1_INPUT_ROW_WIDTH-1:0]
      phase1_input_rows [0:PHASE1_CASE_COUNT-1];
  logic [PHASE1_OUTPUT_ROW_WIDTH-1:0]
      phase1_output_rows [0:PHASE1_CASE_COUNT-1];
  logic signed [WEIGHT_WIDTH-1:0]
      phase1_weights [0:PHASE1_OUT_DIM*PHASE1_IN_DIM-1];
  logic signed [BIAS_WIDTH-1:0] phase1_biases [0:PHASE1_OUT_DIM-1];

  dense_layer_engine #(
    .MAX_IN_DIM(MAX_IN_DIM), .MAX_OUT_DIM(MAX_OUT_DIM),
    .NUM_PE(NUM_PE), .INPUT_WIDTH(INPUT_WIDTH),
    .WEIGHT_WIDTH(WEIGHT_WIDTH), .BIAS_WIDTH(BIAS_WIDTH),
    .ACC_WIDTH(ACC_WIDTH), .OUTPUT_WIDTH(OUTPUT_WIDTH),
    .MAX_WEIGHT_VALUES(4096), .MAX_BIAS_VALUES(64),
    .RESULT_FIFO_DEPTH(2), .JOB_TAG_WIDTH(8)
  ) dut (
    .clk(clk), .rst(rst),
    .job_valid(job_valid), .job_ready(job_ready),
    .job_in_dim(job_in_dim), .job_out_dim(job_out_dim),
    .job_input_buffer_select(job_input_buffer_select),
    .job_output_buffer_select(job_output_buffer_select),
    .job_weight_offset(job_weight_offset), .job_bias_offset(job_bias_offset),
    .job_output_shift(job_output_shift), .job_relu_enable(job_relu_enable),
    .job_tag(job_tag),
    .act_load_valid(act_load_valid), .act_load_ready(act_load_ready),
    .act_load_buffer_select(act_load_buffer_select),
    .act_load_chunk_index(act_load_chunk_index),
    .act_load_lane_mask(act_load_lane_mask), .act_load_data(act_load_data),
    .weight_cfg_valid(weight_cfg_valid), .weight_cfg_ready(weight_cfg_ready),
    .weight_cfg_address(weight_cfg_address), .weight_cfg_data(weight_cfg_data),
    .bias_cfg_valid(bias_cfg_valid), .bias_cfg_ready(bias_cfg_ready),
    .bias_cfg_address(bias_cfg_address), .bias_cfg_data(bias_cfg_data),
    .result_valid(result_valid), .result_ready(result_ready),
    .result_data(result_data), .result_index(result_index),
    .result_last(result_last), .result_tag(result_tag), .job_done(job_done),
    .error_valid(error_valid), .error_ready(error_ready), .error_code(error_code)
  );

  function automatic logic signed [INPUT_WIDTH-1:0] input_value(
    input integer pattern,
    input integer element_index
  );
    begin
      if (pattern == 2)
        input_value = 16'sh8000;
      else if (pattern == 1)
        input_value = (element_index % 5) - 2;
      else
        input_value = (element_index % 17) - 8;
    end
  endfunction

  function automatic logic signed [PHASE1_INPUT_WIDTH-1:0]
      phase1_input_lane(input integer case_index, input integer lane_index);
    begin
      phase1_input_lane = $signed(
          phase1_input_rows[case_index]
              [lane_index*PHASE1_INPUT_WIDTH +: PHASE1_INPUT_WIDTH]);
    end
  endfunction

  function automatic logic signed [OUTPUT_WIDTH-1:0]
      phase1_output_lane(input integer case_index, input integer lane_index);
    begin
      phase1_output_lane = $signed(
          phase1_output_rows[case_index]
              [lane_index*OUTPUT_WIDTH +: OUTPUT_WIDTH]);
    end
  endfunction

  function automatic logic signed [WEIGHT_WIDTH-1:0] weight_value(
    input integer pattern,
    input integer output_number,
    input integer element_index
  );
    begin
      if (pattern == 2)
        weight_value = 8'sh80;
      else if (pattern == 1)
        weight_value = ((output_number + element_index) % 7) - 3;
      else
        weight_value = ((output_number*3 + element_index) % 9) - 4;
    end
  endfunction

  function automatic logic signed [BIAS_WIDTH-1:0] bias_value(
    input integer pattern,
    input integer output_number
  );
    begin
      if (pattern == 2)
        bias_value = 24'sh7fffff;
      else
        bias_value = output_number*37 - 100;
    end
  endfunction

  function automatic logic signed [ACC_WIDTH-1:0] expected_accumulator(
    input integer input_dim,
    input integer output_number,
    input integer pattern
  );
    logic signed [ACC_WIDTH-1:0] accumulator;
    logic signed [INPUT_WIDTH-1:0] input_element;
    logic signed [WEIGHT_WIDTH-1:0] weight_element;
    integer element_index;
    begin
      accumulator = bias_value(pattern, output_number);
      for (element_index = 0; element_index < input_dim;
           element_index = element_index + 1) begin
        input_element = input_value(pattern, element_index);
        weight_element = weight_value(pattern, output_number, element_index);
        accumulator = accumulator + input_element * weight_element;
      end
      expected_accumulator = accumulator;
    end
  endfunction

  function automatic logic signed [OUTPUT_WIDTH-1:0] expected_output(
    input integer input_dim,
    input integer output_number,
    input integer pattern,
    input integer shift_value,
    input logic relu_value
  );
    logic signed [ACC_WIDTH-1:0] accumulator;
    logic signed [ACC_WIDTH:0] extended;
    logic [ACC_WIDTH:0] magnitude;
    logic [ACC_WIDTH:0] rounded_magnitude;
    logic signed [ACC_WIDTH:0] shifted;
    logic signed [OUTPUT_WIDTH-1:0] saturated;
    begin
      accumulator = expected_accumulator(input_dim, output_number, pattern);
      extended = {accumulator[ACC_WIDTH-1], accumulator};
      magnitude = (extended < 0) ? $unsigned(-extended) : $unsigned(extended);
      if (shift_value == 0)
        shifted = extended;
      else begin
        rounded_magnitude =
            (magnitude + ({{ACC_WIDTH{1'b0}}, 1'b1} << (shift_value-1))) >>
            shift_value;
        shifted = (extended < 0) ? -$signed(rounded_magnitude) :
                                  $signed(rounded_magnitude);
      end
      if (shifted > 32767)
        saturated = 16'sh7fff;
      else if (shifted < -32768)
        saturated = 16'sh8000;
      else
        saturated = shifted[OUTPUT_WIDTH-1:0];
      if (relu_value && saturated < 0)
        expected_output = '0;
      else
        expected_output = saturated;
    end
  endfunction

  task automatic configure_layer(
    input integer input_dim,
    input integer output_dim,
    input integer pattern
  );
    integer chunk_count;
    integer chunk_number;
    integer lane;
    integer element_index;
    integer output_number;
    begin
      chunk_count = (input_dim+NUM_PE-1)/NUM_PE;
      for (chunk_number = 0; chunk_number < chunk_count;
           chunk_number = chunk_number + 1) begin
        @(negedge clk);
        act_load_data = '0;
        act_load_lane_mask = '0;
        act_load_chunk_index = chunk_number;
        for (lane = 0; lane < NUM_PE; lane = lane + 1) begin
          element_index = chunk_number*NUM_PE + lane;
          if (element_index < input_dim) begin
            act_load_lane_mask[lane] = 1'b1;
            act_load_data[lane*INPUT_WIDTH +: INPUT_WIDTH] =
                input_value(pattern, element_index);
          end
        end
        act_load_valid = 1'b1;
        while (!act_load_ready) @(negedge clk);
        @(posedge clk);
      end
      @(negedge clk);
      act_load_valid = 1'b0;

      for (output_number = 0; output_number < output_dim;
           output_number = output_number + 1)
        for (element_index = 0; element_index < input_dim;
             element_index = element_index + 1) begin
          @(negedge clk);
          weight_cfg_address = output_number*input_dim + element_index;
          weight_cfg_data = weight_value(pattern, output_number, element_index);
          weight_cfg_valid = 1'b1;
          if (!weight_cfg_ready)
            $fatal(1, "P=%0d weight configuration unexpectedly stalled", NUM_PE);
          @(posedge clk);
        end
      @(negedge clk);
      weight_cfg_valid = 1'b0;

      for (output_number = 0; output_number < output_dim;
           output_number = output_number + 1) begin
        @(negedge clk);
        bias_cfg_address = output_number;
        bias_cfg_data = bias_value(pattern, output_number);
        bias_cfg_valid = 1'b1;
        if (!bias_cfg_ready)
          $fatal(1, "P=%0d bias configuration unexpectedly stalled", NUM_PE);
        @(posedge clk);
      end
      @(negedge clk);
      bias_cfg_valid = 1'b0;
    end
  endtask

  task automatic run_layer(
    input integer input_dim,
    input integer output_dim,
    input integer pattern,
    input integer shift_value,
    input logic relu_value,
    input logic [7:0] tag_value
  );
    integer received;
    integer cycles;
    logic saw_done;
    logic signed [OUTPUT_WIDTH-1:0] expected;
    logic held_valid;
    logic signed [OUTPUT_WIDTH-1:0] held_data;
    logic [OUT_INDEX_WIDTH-1:0] held_index;
    logic held_last;
    logic [7:0] held_tag;
    begin
      configure_layer(input_dim, output_dim, pattern);
      @(negedge clk);
      job_in_dim = input_dim;
      job_out_dim = output_dim;
      job_input_buffer_select = 1'b0;
      job_output_buffer_select = 1'b1;
      job_weight_offset = '0;
      job_bias_offset = '0;
      job_output_shift = shift_value;
      job_relu_enable = relu_value;
      job_tag = tag_value;
      job_valid = 1'b1;
      while (!job_ready) @(negedge clk);
      @(posedge clk);
      @(negedge clk);
      job_valid = 1'b0;
      // Poison source pins to prove the descriptor was copied at handshake.
      job_in_dim = 1;
      job_out_dim = 1;
      job_output_shift = '0;
      job_relu_enable = !relu_value;
      job_tag = ~tag_value;

      received = 0;
      cycles = 0;
      saw_done = 1'b0;
      held_valid = 1'b0;
      while (received < output_dim) begin
        @(negedge clk);
        result_ready = ((cycles % 5) != 1) && ((cycles % 7) != 3);
        if (job_done)
          saw_done = 1'b1;
        if (result_valid && !result_ready) begin
          if (held_valid && (result_data !== held_data ||
              result_index !== held_index || result_last !== held_last ||
              result_tag !== held_tag))
            $fatal(1, "dense result payload changed under backpressure");
          held_valid = 1'b1;
          held_data = result_data;
          held_index = result_index;
          held_last = result_last;
          held_tag = result_tag;
        end
        if (result_valid && result_ready) begin
          expected = expected_output(input_dim, received, pattern,
                                     shift_value, relu_value);
          if (result_index !== received || result_data !== expected ||
              result_tag !== tag_value ||
              result_last !== (received == output_dim-1))
            $fatal(1, "P=%0d ACC=%0d output %0d mismatch exp=%0d got=%0d index=%0d last=%0d",
                   NUM_PE, ACC_WIDTH, received, expected, result_data,
                   result_index, result_last);
          received = received + 1;
          held_valid = 1'b0;
        end
        cycles = cycles + 1;
        if (cycles > 200000)
          $fatal(1, "dense engine layer timeout");
      end
      @(negedge clk);
      result_ready = 1'b0;
      if (job_done)
        saw_done = 1'b1;
      while (!job_ready) begin
        @(negedge clk);
        if (job_done)
          saw_done = 1'b1;
      end
      if (!saw_done)
        $fatal(1, "P=%0d dense engine job_done missing", NUM_PE);
      if (error_valid)
        $fatal(1, "P=%0d unexpected dense engine error %0d", NUM_PE, error_code);
    end
  endtask

  task automatic check_invalid_descriptor(input integer invalid_kind);
    logic [3:0] expected_error;
    begin
      @(negedge clk);
      job_in_dim = 1;
      job_out_dim = 1;
      job_input_buffer_select = 1'b0;
      job_output_buffer_select = 1'b1;
      job_output_shift = 4;
      expected_error = 4'd1;
      case (invalid_kind)
        0: job_in_dim = 0;
        1: job_in_dim = MAX_IN_DIM+1;
        2: job_out_dim = MAX_OUT_DIM+1;
        3: begin
          job_output_buffer_select = 1'b0;
          expected_error = 4'd2;
        end
        4: begin
          job_output_shift = ACC_WIDTH+1;
          expected_error = 4'd3;
        end
        default: job_in_dim = 0;
      endcase
      job_valid = 1'b1;
      while (!job_ready) @(negedge clk);
      @(posedge clk);
      @(negedge clk);
      job_valid = 1'b0;
      while (!error_valid) @(negedge clk);
      if (error_code !== expected_error || result_valid)
        $fatal(1, "invalid descriptor kind=%0d expected error=%0d actual=%0d",
               invalid_kind, expected_error, error_code);
      error_ready = 1'b1;
      @(posedge clk);
      @(negedge clk);
      error_ready = 1'b0;
      while (!job_ready) @(negedge clk);
    end
  endtask

  task automatic configure_phase1_model;
    integer model_index;
    begin
      for (model_index = 0; model_index < 4*8;
           model_index = model_index + 1) begin
        @(negedge clk);
        weight_cfg_address = model_index;
        weight_cfg_data = phase1_weights[model_index];
        weight_cfg_valid = 1'b1;
        if (!weight_cfg_ready)
          $fatal(1, "phase1 weight configuration stalled");
        @(posedge clk);
      end
      @(negedge clk);
      weight_cfg_valid = 1'b0;
      for (model_index = 0; model_index < 4; model_index = model_index + 1) begin
        @(negedge clk);
        bias_cfg_address = model_index;
        bias_cfg_data = phase1_biases[model_index];
        bias_cfg_valid = 1'b1;
        if (!bias_cfg_ready)
          $fatal(1, "phase1 bias configuration stalled");
        @(posedge clk);
      end
      @(negedge clk);
      bias_cfg_valid = 1'b0;
    end
  endtask

  task automatic run_phase1_case(input integer case_index);
    integer chunk_number;
    integer lane;
    integer element_index;
    integer received;
    integer cycles;
    logic saw_done;
    logic signed [PHASE1_INPUT_WIDTH-1:0] phase1_input_element;
    logic signed [OUTPUT_WIDTH-1:0] phase1_expected_output;
    begin
      for (chunk_number = 0;
           chunk_number < (PHASE1_IN_DIM+NUM_PE-1)/NUM_PE;
           chunk_number = chunk_number + 1) begin
        @(negedge clk);
        act_load_data = '0;
        act_load_lane_mask = '0;
        act_load_chunk_index = chunk_number;
        for (lane = 0; lane < NUM_PE; lane = lane + 1) begin
          element_index = chunk_number*NUM_PE + lane;
          if (element_index < PHASE1_IN_DIM) begin
            act_load_lane_mask[lane] = 1'b1;
            phase1_input_element = phase1_input_lane(case_index, element_index);
            act_load_data[lane*INPUT_WIDTH +: INPUT_WIDTH] =
                INPUT_WIDTH'(phase1_input_element);
          end
        end
        act_load_valid = 1'b1;
        while (!act_load_ready) @(negedge clk);
        @(posedge clk);
      end
      @(negedge clk);
      act_load_valid = 1'b0;

      job_in_dim = PHASE1_IN_DIM;
      job_out_dim = PHASE1_OUT_DIM;
      job_input_buffer_select = 1'b0;
      job_output_buffer_select = 1'b1;
      job_weight_offset = '0;
      job_bias_offset = '0;
      job_output_shift = 4;
      job_relu_enable = 1'b1;
      job_tag = case_index;
      job_valid = 1'b1;
      while (!job_ready) @(negedge clk);
      @(posedge clk);
      @(negedge clk);
      job_valid = 1'b0;
      received = 0;
      cycles = 0;
      saw_done = 1'b0;
      while (received < PHASE1_OUT_DIM) begin
        @(negedge clk);
        result_ready = ((case_index + cycles) % 4) != 1;
        if (job_done)
          saw_done = 1'b1;
        if (result_valid && result_ready) begin
          phase1_expected_output = phase1_output_lane(case_index, received);
          if (result_index !== received ||
              result_data !== phase1_expected_output ||
              result_tag !== case_index ||
              result_last !== (received == PHASE1_OUT_DIM-1))
            $fatal(1, "phase1 case=%0d output=%0d mismatch expected=%0d actual=%0d",
                   case_index, received,
                   phase1_expected_output, result_data);
          received = received + 1;
        end
        cycles = cycles + 1;
      end
      @(negedge clk);
      result_ready = 1'b0;
      if (job_done)
        saw_done = 1'b1;
      while (!job_ready) begin
        @(negedge clk);
        if (job_done)
          saw_done = 1'b1;
      end
      if (!saw_done)
        $fatal(1, "phase1 compatibility job_done missing");
    end
  endtask

  initial begin : checker_sequence
    integer phase1_case;
    job_valid = 1'b0;
    job_in_dim = '0;
    job_out_dim = '0;
    job_input_buffer_select = 1'b0;
    job_output_buffer_select = 1'b1;
    job_weight_offset = '0;
    job_bias_offset = '0;
    job_output_shift = '0;
    job_relu_enable = 1'b0;
    job_tag = '0;
    act_load_valid = 1'b0;
    act_load_buffer_select = 1'b0;
    act_load_chunk_index = '0;
    act_load_lane_mask = '0;
    act_load_data = '0;
    weight_cfg_valid = 1'b0;
    weight_cfg_address = '0;
    weight_cfg_data = '0;
    bias_cfg_valid = 1'b0;
    bias_cfg_address = '0;
    bias_cfg_data = '0;
    result_ready = 1'b0;
    error_ready = 1'b0;
    done = 1'b0;
    if (RUN_COMPAT && INPUT_WIDTH < PHASE1_INPUT_WIDTH)
      $fatal(1, "Phase-1 compatibility requires INPUT_WIDTH >= %0d",
             PHASE1_INPUT_WIDTH);
    $readmemh("tests/vectors/dense_inputs.hex", phase1_input_rows);
    $readmemh("tests/vectors/weights.hex", phase1_weights);
    $readmemh("tests/vectors/biases.hex", phase1_biases);
    $readmemh("tests/expected/dense_outputs.hex", phase1_output_rows);
    wait (!rst);

    if (RUN_COMPAT) begin
      configure_phase1_model();
      for (phase1_case = 0; phase1_case < PHASE1_CASE_COUNT;
           phase1_case = phase1_case + 1)
        run_phase1_case(phase1_case);
      run_layer(13, 7, 1, 1, 1'b0, 8'h82);
      run_layer(1024, 1, 2, 20, 1'b0, 8'h83);
    end else begin
      run_layer(3, 5, 1, 0, 1'b0, 8'h41);
      run_layer(64, 32, 0, 4, 1'b1, 8'h42);
      run_layer(65, 17, 1, 4, 1'b0, 8'h43);
      run_layer(1024, 1, 2, 20, 1'b0, 8'h44);
    end
    check_invalid_descriptor(0);
    check_invalid_descriptor(1);
    check_invalid_descriptor(2);
    check_invalid_descriptor(3);
    check_invalid_descriptor(4);
    done = 1'b1;
  end
endmodule

module tb_dense_layer_engine;
  logic clk = 1'b0;
  logic rst;
  logic done32;
  logic done48;

  always #5 clk = ~clk;

  initial begin : timeout_guard
    #5000000;
    $display("tb_dense_layer_engine: FAIL - timeout");
    $fatal(1, "tb_dense_layer_engine timeout");
  end

  dense_engine_checker #(
    .NUM_PE(4), .ACC_WIDTH(32), .RUN_COMPAT(1)
  ) checker32 (.clk(clk), .rst(rst), .done(done32));
  dense_engine_checker #(
    .NUM_PE(16), .ACC_WIDTH(48), .RUN_COMPAT(0)
  ) checker48 (.clk(clk), .rst(rst), .done(done48));

  initial begin
    rst = 1'b1;
    repeat (4) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;
    wait (done32 && done48);
    $display("tb_dense_layer_engine: PASS P=4/16 ACC=32/48 tails/backpressure/errors");
    $finish;
  end
endmodule
