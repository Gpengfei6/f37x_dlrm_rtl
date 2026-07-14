`timescale 1ns/1ps
module tb_dlrm_minimal_top;
  localparam integer LOOKUPS = 4;
  localparam integer ID_WIDTH = 5;
  localparam integer OUT_DIM = 4;
  localparam integer OUTPUT_WIDTH = 16;
  localparam integer CASE_COUNT = 24;

  logic clk = 1'b0;
  logic rst;
  logic in_valid;
  logic in_ready;
  logic [LOOKUPS*ID_WIDTH-1:0] in_ids;
  logic out_valid;
  logic out_ready;
  logic signed [OUT_DIM*OUTPUT_WIDTH-1:0] out_data;
  logic [LOOKUPS*ID_WIDTH-1:0] id_vectors [0:CASE_COUNT-1];
  logic [OUT_DIM*OUTPUT_WIDTH-1:0] expected_vectors [0:CASE_COUNT-1];
  integer test_index;
  integer stall;
  integer result_file;

  always #5 clk = ~clk;

  initial begin : timeout_guard
    #1000000;
    $display("tb_dlrm_minimal_top: FAIL - timeout");
    $fatal(1, "tb_dlrm_minimal_top timeout");
  end

  dlrm_minimal_top #(
    .EMBED_INIT_FILE("tests/vectors/embedding.hex"),
    .WEIGHT_INIT_FILE("tests/vectors/weights.hex"),
    .BIAS_INIT_FILE("tests/vectors/biases.hex")
  ) dut (
    .clk(clk), .rst(rst),
    .in_valid(in_valid), .in_ready(in_ready), .in_ids(in_ids),
    .out_valid(out_valid), .out_ready(out_ready), .out_data(out_data)
  );

  task automatic stalled_next_input(
    input integer first_index,
    input integer second_index
  );
    integer hold_cycle;
    begin
      @(negedge clk);
      in_ids = id_vectors[first_index];
      in_valid = 1'b1;
      while (!in_ready) @(negedge clk);
      @(posedge clk);
      @(negedge clk);
      in_valid = 1'b0;
      while (!out_valid) @(negedge clk);
      if (out_data !== expected_vectors[first_index])
        $fatal(1, "top overlap first result mismatch");

      in_ids = id_vectors[second_index];
      in_valid = 1'b1;
      out_ready = 1'b0;
      for (hold_cycle = 0; hold_cycle < 3; hold_cycle = hold_cycle + 1) begin
        @(negedge clk);
        if (in_ready) $fatal(1, "top accepted input while output was blocked");
        if (!out_valid || out_data !== expected_vectors[first_index])
          $fatal(1, "top overlap output changed under backpressure");
      end

      out_ready = 1'b1;
      @(posedge clk);
      @(negedge clk);
      out_ready = 1'b0;
      if (!in_ready) $fatal(1, "top did not return input ready");
      @(posedge clk);
      @(negedge clk);
      in_valid = 1'b0;
      while (!out_valid) @(negedge clk);
      if (out_data !== expected_vectors[second_index])
        $fatal(1, "top overlap second result mismatch");
      out_ready = 1'b1;
      @(posedge clk);
      @(negedge clk);
      out_ready = 1'b0;
    end
  endtask

  initial begin
    $readmemh("tests/vectors/top_case_ids.hex", id_vectors);
    $readmemh("tests/expected/top_outputs.hex", expected_vectors);
    result_file = $fopen("results/rtl_top_outputs.hex", "w");
    if (result_file == 0) $fatal(1, "cannot open RTL result output file");
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
        $fatal(1, "top mismatch case=%0d expected=%h actual=%h",
               test_index, expected_vectors[test_index], out_data);
      for (stall = 0; stall < (test_index % 5); stall = stall + 1) begin
        @(negedge clk);
        if (!out_valid || out_data !== expected_vectors[test_index])
          $fatal(1, "top output changed under backpressure case=%0d", test_index);
      end
      $fdisplay(result_file, "%h", out_data);
      out_ready = 1'b1;
      @(posedge clk);
      @(negedge clk);
      out_ready = 1'b0;
    end
    // This directed pair holds the next request while both ends are stalled.
    stalled_next_input(5, 6);
    $fclose(result_file);
    $display("tb_dlrm_minimal_top: PASS cases=%0d", CASE_COUNT);
    $finish;
  end
endmodule
