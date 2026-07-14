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
    $display("tb_dense_layer_core: PASS cases=%0d", CASE_COUNT);
    $finish;
  end
endmodule

