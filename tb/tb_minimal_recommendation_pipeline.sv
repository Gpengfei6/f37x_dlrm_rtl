`timescale 1ns/1ps
module tb_minimal_recommendation_pipeline;
  localparam integer NUM_ROWS = 32;
  localparam integer DIM = 8;
  localparam integer LOOKUPS = 4;
  localparam integer OUT_DIM = 4;
  localparam integer ID_WIDTH = 5;
  localparam integer OUTPUT_WIDTH = 16;
  localparam integer CASE_COUNT = 9;

  logic clk = 1'b0;
  logic rst;
  logic in_valid;
  logic in_ready;
  logic [LOOKUPS*ID_WIDTH-1:0] in_ids;
  logic out_valid;
  logic out_ready;
  logic signed [OUT_DIM*OUTPUT_WIDTH-1:0] out_data;
  logic [LOOKUPS*ID_WIDTH-1:0] id_vectors [0:23];
  logic [OUT_DIM*OUTPUT_WIDTH-1:0] expected_vectors [0:23];
  integer test_index;
  integer stall;

  always #5 clk = ~clk;

  minimal_recommendation_pipeline #(
    .NUM_EMBED_ROWS(NUM_ROWS), .EMBED_DIM(DIM), .NUM_LOOKUPS(LOOKUPS),
    .DENSE_OUT_DIM(OUT_DIM), .DATA_WIDTH(8), .WEIGHT_WIDTH(8),
    .BIAS_WIDTH(24), .ACC_WIDTH(32), .OUTPUT_WIDTH(OUTPUT_WIDTH),
    .OUTPUT_SHIFT(4), .ID_WIDTH(ID_WIDTH), .AGG_WIDTH(10),
    .EMBED_INIT_FILE("tests/vectors/embedding.hex"),
    .WEIGHT_INIT_FILE("tests/vectors/weights.hex"),
    .BIAS_INIT_FILE("tests/vectors/biases.hex")
  ) dut (
    .clk(clk), .rst(rst),
    .in_valid(in_valid), .in_ready(in_ready), .in_ids(in_ids),
    .out_valid(out_valid), .out_ready(out_ready), .out_data(out_data)
  );

  initial begin
    $readmemh("tests/vectors/top_case_ids.hex", id_vectors);
    $readmemh("tests/expected/top_outputs.hex", expected_vectors);
    rst = 1'b1;
    in_valid = 1'b0;
    in_ids = '0;
    out_ready = 1'b0;
    repeat (3) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;

    for (test_index = 0; test_index < CASE_COUNT; test_index = test_index + 1) begin
      @(negedge clk);
      in_ids = id_vectors[test_index];
      in_valid = 1'b1;
      while (!in_ready) @(negedge clk);
      @(posedge clk);
      @(negedge clk);
      in_valid = 1'b0;
      while (!out_valid) @(negedge clk);
      if (out_data !== expected_vectors[test_index])
        $fatal(1, "pipeline mismatch case=%0d expected=%h actual=%h",
               test_index, expected_vectors[test_index], out_data);
      for (stall = 0; stall < (test_index % 3); stall = stall + 1) begin
        @(negedge clk);
        if (!out_valid || out_data !== expected_vectors[test_index])
          $fatal(1, "pipeline output changed under backpressure case=%0d", test_index);
      end
      out_ready = 1'b1;
      @(posedge clk);
      @(negedge clk);
      out_ready = 1'b0;
    end
    $display("tb_minimal_recommendation_pipeline: PASS cases=%0d", CASE_COUNT);
    $finish;
  end
endmodule

