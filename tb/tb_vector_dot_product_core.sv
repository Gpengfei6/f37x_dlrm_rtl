`timescale 1ns/1ps

module vector_dot_checker #(
  parameter integer NUM_PE = 4,
  parameter integer ACC_WIDTH = 32,
  parameter integer RUN_EXTREME = 0,
  parameter integer RUN_REPLACEMENT = 0
) (
  input  logic clk,
  input  logic rst,
  output logic done
);
  localparam integer MAX_IN_DIM = 1024;
  localparam integer DIM_WIDTH = 11;
  localparam integer INPUT_WIDTH = 16;
  localparam integer WEIGHT_WIDTH = 8;
  localparam integer BIAS_WIDTH = 24;

  logic command_valid;
  logic command_ready;
  logic [DIM_WIDTH-1:0] command_in_dim;
  logic signed [BIAS_WIDTH-1:0] command_bias;
  logic chunk_valid;
  logic chunk_ready;
  logic signed [NUM_PE*INPUT_WIDTH-1:0] chunk_inputs;
  logic signed [NUM_PE*WEIGHT_WIDTH-1:0] chunk_weights;
  logic [NUM_PE-1:0] chunk_lane_mask;
  logic chunk_last;
  logic result_valid;
  logic result_ready;
  logic signed [ACC_WIDTH-1:0] result_data;
  logic protocol_error;

  vector_dot_product_core #(
    .MAX_IN_DIM(MAX_IN_DIM), .NUM_PE(NUM_PE),
    .INPUT_WIDTH(INPUT_WIDTH), .WEIGHT_WIDTH(WEIGHT_WIDTH),
    .BIAS_WIDTH(BIAS_WIDTH), .ACC_WIDTH(ACC_WIDTH),
    .DIM_WIDTH(DIM_WIDTH)
  ) dut (
    .clk(clk), .rst(rst),
    .command_valid(command_valid), .command_ready(command_ready),
    .command_in_dim(command_in_dim), .command_bias(command_bias),
    .chunk_valid(chunk_valid), .chunk_ready(chunk_ready),
    .chunk_inputs(chunk_inputs), .chunk_weights(chunk_weights),
    .chunk_lane_mask(chunk_lane_mask), .chunk_last(chunk_last),
    .result_valid(result_valid), .result_ready(result_ready),
    .result_data(result_data), .protocol_error(protocol_error)
  );

  function automatic logic signed [INPUT_WIDTH-1:0] pattern_input(
    input integer pattern,
    input integer element_index
  );
    begin
      if (pattern == 1)
        pattern_input = -16'sd32768;
      else
        pattern_input = (element_index % 17) - 8;
    end
  endfunction

  function automatic logic signed [WEIGHT_WIDTH-1:0] pattern_weight(
    input integer pattern,
    input integer element_index
  );
    begin
      if (pattern == 1)
        pattern_weight = -8'sd128;
      else
        pattern_weight = (element_index % 9) - 4;
    end
  endfunction

  function automatic logic signed [ACC_WIDTH-1:0] expected_dot(
    input integer input_dim,
    input integer pattern,
    input logic signed [BIAS_WIDTH-1:0] bias
  );
    logic signed [ACC_WIDTH-1:0] accumulator;
    logic signed [INPUT_WIDTH-1:0] input_element;
    logic signed [WEIGHT_WIDTH-1:0] weight_element;
    integer element_index;
    begin
      accumulator = bias;
      for (element_index = 0; element_index < input_dim;
           element_index = element_index + 1) begin
        input_element = pattern_input(pattern, element_index);
        weight_element = pattern_weight(pattern, element_index);
        accumulator = accumulator + input_element * weight_element;
      end
      expected_dot = accumulator;
    end
  endfunction

  task automatic issue_command(
    input integer input_dim,
    input logic signed [BIAS_WIDTH-1:0] bias
  );
    begin
      @(negedge clk);
      command_in_dim = input_dim;
      command_bias = bias;
      command_valid = 1'b1;
      while (!command_ready) @(negedge clk);
      @(posedge clk);
      @(negedge clk);
      command_valid = 1'b0;
    end
  endtask

  task automatic send_chunks(
    input integer input_dim,
    input integer pattern
  );
    integer chunk_count;
    integer chunk_number;
    integer lane;
    integer element_index;
    begin
      chunk_count = (input_dim+NUM_PE-1)/NUM_PE;
      for (chunk_number = 0; chunk_number < chunk_count;
           chunk_number = chunk_number + 1) begin
        @(negedge clk);
        chunk_inputs = '0;
        chunk_weights = '0;
        chunk_lane_mask = '0;
        for (lane = 0; lane < NUM_PE; lane = lane + 1) begin
          element_index = chunk_number*NUM_PE + lane;
          if (element_index < input_dim) begin
            chunk_lane_mask[lane] = 1'b1;
            chunk_inputs[lane*INPUT_WIDTH +: INPUT_WIDTH] =
                pattern_input(pattern, element_index);
            chunk_weights[lane*WEIGHT_WIDTH +: WEIGHT_WIDTH] =
                pattern_weight(pattern, element_index);
          end
        end
        chunk_last = (chunk_number == chunk_count-1);
        chunk_valid = 1'b1;
        while (!chunk_ready) @(negedge clk);
        @(posedge clk);
        @(negedge clk);
        chunk_valid = 1'b0;
      end
    end
  endtask

  task automatic check_result(
    input logic signed [ACC_WIDTH-1:0] expected,
    input integer stall_cycles
  );
    logic signed [ACC_WIDTH-1:0] held;
    integer stall;
    begin
      while (!result_valid) @(negedge clk);
      held = result_data;
      if (held !== expected)
        $fatal(1, "P=%0d ACC=%0d dot expected=%0d actual=%0d",
               NUM_PE, ACC_WIDTH, expected, held);
      for (stall = 0; stall < stall_cycles; stall = stall + 1) begin
        @(negedge clk);
        if (!result_valid || result_data !== held)
          $fatal(1, "P=%0d vector result changed under backpressure", NUM_PE);
      end
      result_ready = 1'b1;
      @(posedge clk);
      @(negedge clk);
      result_ready = 1'b0;
    end
  endtask

  task automatic run_dot(
    input integer input_dim,
    input integer pattern,
    input logic signed [BIAS_WIDTH-1:0] bias,
    input integer stall_cycles
  );
    logic signed [ACC_WIDTH-1:0] expected;
    begin
      expected = expected_dot(input_dim, pattern, bias);
      issue_command(input_dim, bias);
      send_chunks(input_dim, pattern);
      check_result(expected, stall_cycles);
    end
  endtask

  initial begin : checker_sequence
    logic signed [ACC_WIDTH-1:0] first_expected;
    logic signed [ACC_WIDTH-1:0] second_expected;
    command_valid = 1'b0;
    command_in_dim = '0;
    command_bias = '0;
    chunk_valid = 1'b0;
    chunk_inputs = '0;
    chunk_weights = '0;
    chunk_lane_mask = '0;
    chunk_last = 1'b0;
    result_ready = 1'b0;
    done = 1'b0;
    wait (!rst);

    run_dot(13, 0, 24'sd123, 3);
    run_dot(NUM_PE-1, 0, -24'sd77, 0);
    run_dot(65, 0, 24'sd9, 1);
    if (RUN_EXTREME)
      run_dot(1024, 1, 24'sh7fffff, 2);

    if (RUN_REPLACEMENT) begin
      first_expected = expected_dot(9, 0, 24'sd5);
      second_expected = expected_dot(7, 0, -24'sd6);
      issue_command(9, 24'sd5);
      send_chunks(9, 0);
      while (!result_valid) @(negedge clk);
      if (result_data !== first_expected)
        $fatal(1, "replacement first result mismatch");
      command_valid = 1'b1;
      command_in_dim = 7;
      command_bias = -24'sd6;
      repeat (3) begin
        @(negedge clk);
        if (command_ready)
          $fatal(1, "vector command escaped output backpressure");
        if (!result_valid || result_data !== first_expected)
          $fatal(1, "vector result changed while command was backpressured");
      end
      result_ready = 1'b1;
      #1;
      if (!command_ready)
        $fatal(1, "vector core blocked same-edge command replacement");
      @(posedge clk);
      @(negedge clk);
      result_ready = 1'b0;
      command_valid = 1'b0;
      send_chunks(7, 0);
      check_result(second_expected, 0);
    end

    if (protocol_error)
      $fatal(1, "P=%0d vector core reported unexpected protocol error", NUM_PE);
    done = 1'b1;
  end
endmodule

module tb_vector_dot_product_core;
  logic clk = 1'b0;
  logic rst;
  logic done4;
  logic done8;
  logic done16;
  logic done32;

  always #5 clk = ~clk;

  initial begin : timeout_guard
    #1000000;
    $display("tb_vector_dot_product_core: FAIL - timeout");
    $fatal(1, "tb_vector_dot_product_core timeout");
  end

  vector_dot_checker #(
    .NUM_PE(4), .ACC_WIDTH(32), .RUN_EXTREME(1), .RUN_REPLACEMENT(1)
  ) checker4 (.clk(clk), .rst(rst), .done(done4));
  vector_dot_checker #(
    .NUM_PE(8), .ACC_WIDTH(48), .RUN_EXTREME(1)
  ) checker8 (.clk(clk), .rst(rst), .done(done8));
  vector_dot_checker #(
    .NUM_PE(16), .ACC_WIDTH(32)
  ) checker16 (.clk(clk), .rst(rst), .done(done16));
  vector_dot_checker #(
    .NUM_PE(32), .ACC_WIDTH(48)
  ) checker32 (.clk(clk), .rst(rst), .done(done32));

  initial begin
    rst = 1'b1;
    repeat (4) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;
    wait (done4 && done8 && done16 && done32);
    if ($time < 1) $fatal(1, "invalid completion time");
    $display("tb_vector_dot_product_core: PASS P=4,8,16,32 ACC=32,48");
    $finish;
  end
endmodule
