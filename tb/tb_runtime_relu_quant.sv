`timescale 1ns/1ps

module tb_runtime_relu_quant;
  logic signed [47:0] in_data;
  logic [5:0] shift_amount;
  logic relu_enable;
  logic signed [15:0] out_data;
  logic invalid_shift;

  initial begin : timeout_guard
    #200000;
    $display("tb_runtime_relu_quant: FAIL - timeout");
    $fatal(1, "tb_runtime_relu_quant timeout");
  end

  runtime_relu_quant #(
    .IN_WIDTH(48), .OUT_WIDTH(16), .SHIFT_WIDTH(6)
  ) dut (
    .in_data(in_data), .shift_amount(shift_amount),
    .relu_enable(relu_enable), .out_data(out_data),
    .invalid_shift(invalid_shift)
  );

  task automatic check_value(
    input logic signed [47:0] value,
    input logic [5:0] shift,
    input logic relu,
    input logic signed [15:0] expected,
    input logic expected_invalid
  );
    begin
      in_data = value;
      shift_amount = shift;
      relu_enable = relu;
      #1;
      if (out_data !== expected || invalid_shift !== expected_invalid)
        $fatal(1, "quant value=%0d shift=%0d relu=%0d expected=%0d actual=%0d invalid=%0d",
               value, shift, relu, expected, out_data, invalid_shift);
    end
  endtask

  initial begin
    check_value(48'sd7, 6'd4, 1'b0, 16'sd0, 1'b0);
    check_value(48'sd8, 6'd4, 1'b0, 16'sd1, 1'b0);
    check_value(48'sd24, 6'd4, 1'b0, 16'sd2, 1'b0);
    check_value(-48'sd7, 6'd4, 1'b0, 16'sd0, 1'b0);
    check_value(-48'sd8, 6'd4, 1'b0, -16'sd1, 1'b0);
    check_value(-48'sd24, 6'd4, 1'b0, -16'sd2, 1'b0);
    check_value(-48'sd24, 6'd4, 1'b1, 16'sd0, 1'b0);
    check_value(48'sd32767, 6'd0, 1'b0, 16'sd32767, 1'b0);
    check_value(48'sd32768, 6'd0, 1'b0, 16'sd32767, 1'b0);
    check_value(-48'sd32768, 6'd0, 1'b0, -16'sd32768, 1'b0);
    check_value(-48'sd32769, 6'd0, 1'b0, -16'sd32768, 1'b0);
    check_value(48'sd1, 6'd49, 1'b0, 16'sd0, 1'b1);
    $display("tb_runtime_relu_quant: PASS");
    $finish;
  end
endmodule
