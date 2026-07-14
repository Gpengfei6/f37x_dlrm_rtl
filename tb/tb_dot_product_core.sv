`timescale 1ns/1ps
module tb_dot_product_core;
  localparam integer VEC_LEN = 4;
  localparam integer WIDTH = 8;
  localparam integer ACC_WIDTH = 16;

  logic clk = 1'b0;
  logic rst;
  logic in_valid;
  logic in_ready;
  logic signed [VEC_LEN*WIDTH-1:0] in_data;
  logic signed [VEC_LEN*WIDTH-1:0] weight_data;
  logic signed [ACC_WIDTH-1:0] bias_data;
  logic out_valid;
  logic out_ready;
  logic signed [ACC_WIDTH-1:0] out_data;

  logic signed [VEC_LEN*WIDTH-1:0] vector_a;
  logic signed [VEC_LEN*WIDTH-1:0] vector_b;
  integer lane;

  always #5 clk = ~clk;

  dot_product_core #(
    .VEC_LEN(VEC_LEN), .IN_WIDTH(WIDTH), .WEIGHT_WIDTH(WIDTH),
    .BIAS_WIDTH(ACC_WIDTH), .ACC_WIDTH(ACC_WIDTH)
  ) dut (
    .clk(clk), .rst(rst),
    .in_valid(in_valid), .in_ready(in_ready), .in_data(in_data),
    .weight_data(weight_data), .bias_data(bias_data),
    .out_valid(out_valid), .out_ready(out_ready), .out_data(out_data)
  );

  function automatic logic signed [ACC_WIDTH-1:0] expected_dot(
    input logic signed [VEC_LEN*WIDTH-1:0] inputs,
    input logic signed [VEC_LEN*WIDTH-1:0] weights,
    input logic signed [ACC_WIDTH-1:0] bias
  );
    logic signed [ACC_WIDTH-1:0] accumulator;
    logic signed [WIDTH-1:0] input_element;
    logic signed [WIDTH-1:0] weight_element;
    integer index;
    begin
      accumulator = bias;
      for (index = 0; index < VEC_LEN; index = index + 1) begin
        input_element = inputs[index*WIDTH +: WIDTH];
        weight_element = weights[index*WIDTH +: WIDTH];
        accumulator = accumulator + input_element * weight_element;
      end
      expected_dot = accumulator;
    end
  endfunction

  task automatic transact(
    input logic signed [VEC_LEN*WIDTH-1:0] inputs,
    input logic signed [VEC_LEN*WIDTH-1:0] weights,
    input logic signed [ACC_WIDTH-1:0] bias,
    input integer stall_cycles
  );
    logic signed [ACC_WIDTH-1:0] expected;
    logic signed [ACC_WIDTH-1:0] held;
    integer stall;
    begin
      expected = expected_dot(inputs, weights, bias);
      @(negedge clk);
      in_data = inputs;
      weight_data = weights;
      bias_data = bias;
      in_valid = 1'b1;
      while (!in_ready) @(negedge clk);
      @(posedge clk);
      @(negedge clk);
      in_valid = 1'b0;
      while (!out_valid) @(negedge clk);
      held = out_data;
      if (held !== expected)
        $fatal(1, "dot mismatch expected=%0d actual=%0d", expected, held);
      for (stall = 0; stall < stall_cycles; stall = stall + 1) begin
        @(negedge clk);
        if (!out_valid || out_data !== held)
          $fatal(1, "dot output changed under backpressure");
      end
      out_ready = 1'b1;
      @(posedge clk);
      @(negedge clk);
      out_ready = 1'b0;
    end
  endtask

  initial begin
    rst = 1'b1;
    in_valid = 1'b0;
    in_data = '0;
    weight_data = '0;
    bias_data = '0;
    out_ready = 1'b0;
    vector_a = '0;
    vector_b = '0;
    repeat (3) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;

    // Four maximum positive products force signed INT16 accumulation wrap.
    for (lane = 0; lane < VEC_LEN; lane = lane + 1) begin
      vector_a[lane*WIDTH +: WIDTH] = 8'sd127;
      vector_b[lane*WIDTH +: WIDTH] = 8'sd127;
    end
    transact(vector_a, vector_b, 16'sd0, 3);

    vector_a[0*WIDTH +: WIDTH] = -8'sd3;
    vector_a[1*WIDTH +: WIDTH] = 8'sd4;
    vector_a[2*WIDTH +: WIDTH] = -8'sd5;
    vector_a[3*WIDTH +: WIDTH] = 8'sd6;
    vector_b[0*WIDTH +: WIDTH] = 8'sd7;
    vector_b[1*WIDTH +: WIDTH] = -8'sd8;
    vector_b[2*WIDTH +: WIDTH] = 8'sd9;
    vector_b[3*WIDTH +: WIDTH] = -8'sd10;
    transact(vector_a, vector_b, 16'sd123, 0);

    $display("tb_dot_product_core: PASS");
    $finish;
  end
endmodule

