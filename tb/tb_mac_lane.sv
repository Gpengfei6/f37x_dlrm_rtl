`timescale 1ns/1ps

module tb_mac_lane;
  logic clk = 1'b0;
  logic rst;
  logic clear;
  logic enable;
  logic signed [15:0] seed_data;
  logic signed [7:0] input_data;
  logic signed [7:0] weight_data;
  logic signed [15:0] accumulator;

  always #5 clk = ~clk;

  initial begin : timeout_guard
    #200000;
    $display("tb_mac_lane: FAIL - timeout");
    $fatal(1, "tb_mac_lane timeout");
  end

  mac_lane #(
    .INPUT_WIDTH(8), .WEIGHT_WIDTH(8), .ACC_WIDTH(16)
  ) dut (
    .clk(clk), .rst(rst), .clear(clear), .enable(enable),
    .seed_data(seed_data), .input_data(input_data),
    .weight_data(weight_data), .accumulator(accumulator)
  );

  task automatic drive_step(
    input logic step_clear,
    input logic step_enable,
    input logic signed [15:0] step_seed,
    input logic signed [7:0] step_input,
    input logic signed [7:0] step_weight,
    input logic signed [15:0] expected
  );
    begin
      @(negedge clk);
      clear = step_clear;
      enable = step_enable;
      seed_data = step_seed;
      input_data = step_input;
      weight_data = step_weight;
      @(posedge clk);
      @(negedge clk);
      clear = 1'b0;
      enable = 1'b0;
      @(posedge clk);
      #1;
      if (accumulator !== expected)
        $fatal(1, "mac lane expected=%0d actual=%0d", expected, accumulator);
    end
  endtask

  initial begin
    rst = 1'b1;
    clear = 1'b0;
    enable = 1'b0;
    seed_data = '0;
    input_data = '0;
    weight_data = '0;
    repeat (3) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;

    drive_step(1'b1, 1'b1, 16'sd11, -8'sd3, 8'sd7, -16'sd10);
    drive_step(1'b0, 1'b1, 16'sd99, 8'sd4, -8'sd8, -16'sd42);
    drive_step(1'b0, 1'b0, 16'sd99, 8'sd127, 8'sd127, -16'sd42);
    drive_step(1'b1, 1'b0, 16'sd1234, 8'sd1, 8'sd1, 16'sd1234);
    drive_step(1'b1, 1'b1, 16'sd32760, 8'sd2, 8'sd5, -16'sd32766);

    $display("tb_mac_lane: PASS");
    $finish;
  end
endmodule
