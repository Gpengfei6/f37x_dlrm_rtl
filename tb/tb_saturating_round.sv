`timescale 1ns/1ps
module tb_saturating_round;
  logic signed [31:0] in_data;
  logic signed [15:0] out_data;

  saturating_round #(.IN_WIDTH(32), .OUT_WIDTH(16), .SHIFT(4)) dut (
    .in_data(in_data), .out_data(out_data)
  );

  initial begin : timeout_guard
    #1000;
    $display("tb_saturating_round: FAIL - timeout");
    $fatal(1, "tb_saturating_round timeout");
  end

  task automatic check_value(
    input logic signed [31:0] value,
    input logic signed [15:0] expected
  );
    begin
      in_data = value;
      #1;
      if (out_data !== expected)
        $fatal(1, "round mismatch input=%0d expected=%0d actual=%0d",
               value, expected, out_data);
    end
  endtask

  initial begin
    check_value(32'sd0, 16'sd0);
    check_value(32'sd7, 16'sd0);
    check_value(32'sd8, 16'sd1);
    check_value(32'sd23, 16'sd1);
    check_value(32'sd24, 16'sd2);
    check_value(-32'sd7, 16'sd0);
    check_value(-32'sd8, -16'sd1);
    check_value(-32'sd23, -16'sd1);
    check_value(-32'sd24, -16'sd2);
    check_value(32'sd524272, 16'sd32767);
    check_value(32'sd524280, 16'sd32767);
    check_value(-32'sd524288, -16'sd32768);
    check_value(-32'sd524296, -16'sd32768);
    check_value(32'sh7fffffff, 16'sd32767);
    check_value(32'sh80000000, -16'sd32768);
    $display("tb_saturating_round: PASS");
    $finish;
  end
endmodule
