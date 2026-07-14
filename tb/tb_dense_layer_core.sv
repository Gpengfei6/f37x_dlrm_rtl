`timescale 1ns/1ps
module tb_dense_layer_core;
  localparam integer IN_DIM = 8;
  localparam integer OUT_DIM = 4;
  localparam integer IN_WIDTH = 10;
  localparam integer OUTPUT_WIDTH = 16;
  localparam integer CASE_COUNT = 24;

  logic clk = 1'b0;
  logic rst;
  logic in_valid;
  logic in_ready;
  logic signed [IN_DIM*IN_WIDTH-1:0] in_data;
  logic out_valid;
  logic out_ready;
  logic signed [OUT_DIM*OUTPUT_WIDTH-1:0] out_data;
  logic [IN_DIM*IN_WIDTH-1:0] input_vectors [0:CASE_COUNT-1];
  logic [OUT_DIM*OUTPUT_WIDTH-1:0] expected_vectors [0:CASE_COUNT-1];
  integer test_index;
  integer stall;

  always #5 clk = ~clk;

  initial begin : timeout_guard
    #500000;
    $display("tb_dense_layer_core: FAIL - timeout");
    $fatal(1, "tb_dense_layer_core timeout");
  end

  dense_layer_core #(
    .IN_DIM(IN_DIM), .OUT_DIM(OUT_DIM), .IN_WIDTH(IN_WIDTH),
    .WEIGHT_WIDTH(8), .BIAS_WIDTH(24), .ACC_WIDTH(32),
    .OUTPUT_WIDTH(OUTPUT_WIDTH), .OUTPUT_SHIFT(4),
    .WEIGHT_INIT_FILE("tests/vectors/weights.hex"),
    .BIAS_INIT_FILE("tests/vectors/biases.hex")
  ) dut (
    .clk(clk), .rst(rst),
    .in_valid(in_valid), .in_ready(in_ready), .in_data(in_data),
    .out_valid(out_valid), .out_ready(out_ready), .out_data(out_data)
  );

  task automatic stalled_next_input(
    input integer first_index,
    input integer second_index
  );
    integer hold_cycle;
    begin
      @(negedge clk);
      in_data = input_vectors[first_index];
      in_valid = 1'b1;
      while (!in_ready) @(negedge clk);
      @(posedge clk);
      @(negedge clk);
      in_valid = 1'b0;
      while (!out_valid) @(negedge clk);
      if (out_data !== expected_vectors[first_index])
        $fatal(1, "dense overlap first result mismatch");

      in_data = input_vectors[second_index];
      in_valid = 1'b1;
      out_ready = 1'b0;
      for (hold_cycle = 0; hold_cycle < 3; hold_cycle = hold_cycle + 1) begin
        @(negedge clk);
        if (in_ready) $fatal(1, "dense accepted input while output was blocked");
        if (!out_valid || out_data !== expected_vectors[first_index])
          $fatal(1, "dense overlap output changed under backpressure");
      end

      out_ready = 1'b1;
      @(posedge clk);
      @(negedge clk);
      out_ready = 1'b0;
      if (!in_ready) $fatal(1, "dense did not return input ready after output transfer");
      @(posedge clk);
      @(negedge clk);
      in_valid = 1'b0;
      while (!out_valid) @(negedge clk);
      if (out_data !== expected_vectors[second_index])
        $fatal(1, "dense overlap second result mismatch");
      out_ready = 1'b1;
      @(posedge clk);
      @(negedge clk);
      out_ready = 1'b0;
    end
  endtask

  initial begin
    $readmemh("tests/vectors/dense_inputs.hex", input_vectors);
    $readmemh("tests/expected/dense_outputs.hex", expected_vectors);
    rst = 1'b1;
    in_valid = 1'b0;
    in_data = '0;
    out_ready = 1'b0;
    repeat (3) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;

    for (test_index = 0; test_index < CASE_COUNT; test_index = test_index + 1) begin
      @(negedge clk);
      in_data = input_vectors[test_index];
      in_valid = 1'b1;
      while (!in_ready) @(negedge clk);
      @(posedge clk);
      @(negedge clk);
      in_valid = 1'b0;
      while (!out_valid) @(negedge clk);
      if (out_data !== expected_vectors[test_index])
        $fatal(1, "dense mismatch case=%0d expected=%h actual=%h",
               test_index, expected_vectors[test_index], out_data);
      for (stall = 0; stall < (test_index % 4); stall = stall + 1) begin
        @(negedge clk);
        if (!out_valid || out_data !== expected_vectors[test_index])
          $fatal(1, "dense output changed under backpressure case=%0d", test_index);
      end
      out_ready = 1'b1;
      @(posedge clk);
      @(negedge clk);
      out_ready = 1'b0;
    end
    stalled_next_input(5, 6);
    $display("tb_dense_layer_core: PASS cases=%0d", CASE_COUNT);
    $finish;
  end
endmodule
