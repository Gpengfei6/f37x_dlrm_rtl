`timescale 1ns/1ps
module tb_relu_quant;
  logic signed [31:0] in_data;
  logic signed [15:0] out_data;

  relu_quant #(.IN_WIDTH(32), .OUT_WIDTH(16), .SHIFT(4)) dut (
    .in_data(in_data), .out_data(out_data)
  );

  task automatic check_value(
    input logic signed [31:0] value,
    input logic signed [15:0] expected
  );
    begin
      in_data = value;
      #1;
      if (out_data !== expected)
        $fatal(1, "ReLU mismatch input=%0d expected=%0d actual=%0d",
               value, expected, out_data);
    end
  endtask

  initial begin
    check_value(-32'sd1, 16'sd0);
    check_value(-32'sd24, 16'sd0);
    check_value(32'sd7, 16'sd0);
    check_value(32'sd8, 16'sd1);
    check_value(32'sd24, 16'sd2);
    check_value(32'sh7fffffff, 16'sd32767);
    check_value(32'sh80000000, 16'sd0);
    $display("tb_relu_quant: PASS");
    $finish;
  end
endmodule

