`timescale 1ns/1ps

module tb_runtime_relu_quant;
  logic clk;
  logic rst;
  logic in_valid;
  logic in_ready;
  logic signed [47:0] in_data;
  logic [5:0] shift_amount;
  logic relu_enable;
  logic out_valid;
  logic out_ready;
  logic signed [15:0] out_data;
  logic invalid_shift;

  always #5 clk = ~clk;

  initial begin : timeout_guard
    #200000;
    $display("tb_runtime_relu_quant: FAIL - timeout");
    $fatal(1, "tb_runtime_relu_quant timeout");
  end

  runtime_relu_quant #(
    .IN_WIDTH(48), .OUT_WIDTH(16), .SHIFT_WIDTH(6)
  ) dut (
    .clk(clk), .rst(rst), .in_valid(in_valid), .in_ready(in_ready),
    .in_data(in_data), .shift_amount(shift_amount),
    .relu_enable(relu_enable), .out_valid(out_valid),
    .out_ready(out_ready), .out_data(out_data),
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
      @(negedge clk);
      in_data = value;
      shift_amount = shift;
      relu_enable = relu;
      in_valid = 1'b1;
      if (!in_ready)
        $fatal(1, "quant input unexpectedly stalled");
      @(posedge clk);
      @(negedge clk);
      in_valid = 1'b0;
      @(posedge clk);
      #1;
      if (!out_valid || out_data !== expected ||
          invalid_shift !== expected_invalid)
        $fatal(1, "quant value=%0d shift=%0d relu=%0d expected=%0d actual=%0d valid=%0d invalid=%0d",
               value, shift, relu, expected, out_data, out_valid,
               invalid_shift);
    end
  endtask

  task automatic check_full_rate;
    integer item;
    begin
      @(negedge clk);
      out_ready = 1'b1;
      in_valid = 1'b1;
      shift_amount = 6'd4;
      relu_enable = 1'b0;
      for (item = 0; item < 8; item = item + 1) begin
        in_data = 48'(16*item + 8);
        if (!in_ready)
          $fatal(1, "full-rate quant input stalled at item %0d", item);
        @(posedge clk);
        #1;
        if (item == 0 && out_valid)
          $fatal(1, "two-stage quant pipeline produced an early result");
        if (item > 0 && (!out_valid || out_data !== item || invalid_shift))
          $fatal(1, "full-rate quant mismatch item=%0d data=%0d valid=%0d invalid=%0d",
                 item, out_data, out_valid, invalid_shift);
        @(negedge clk);
      end
      in_valid = 1'b0;
      @(posedge clk);
      #1;
      if (!out_valid || out_data !== 16'sd8 || invalid_shift)
        $fatal(1, "full-rate quant final pipeline result mismatch");
      @(negedge clk);
      @(posedge clk);
      #1;
      if (out_valid)
        $fatal(1, "quant valid did not clear after full-rate stream");
    end
  endtask

  task automatic check_backpressure_and_refill;
    integer stall_cycle;
    begin
      @(negedge clk);
      out_ready = 1'b0;
      in_valid = 1'b1;
      in_data = 48'sd24;
      shift_amount = 6'd4;
      relu_enable = 1'b0;
      if (!in_ready)
        $fatal(1, "empty quant pipeline was not ready");
      @(posedge clk);
      @(negedge clk);
      in_data = -48'sd24;
      if (!in_ready)
        $fatal(1, "quant second stage did not accept while output was empty");
      @(posedge clk);
      #1;
      if (!out_valid || out_data !== 16'sd2 || invalid_shift)
        $fatal(1, "failed to fill stalled quant output");

      @(negedge clk);
      in_data = 48'sd40;
      for (stall_cycle = 0; stall_cycle < 3;
           stall_cycle = stall_cycle + 1) begin
        if (in_ready)
          $fatal(1, "quant pipeline accepted input while output stalled");
        @(posedge clk);
        #1;
        if (!out_valid || out_data !== 16'sd2 || invalid_shift)
          $fatal(1, "quant output changed under backpressure cycle=%0d",
                 stall_cycle);
        @(negedge clk);
      end

      out_ready = 1'b1;
      #1;
      if (!in_ready)
        $fatal(1, "quant pipeline did not allow same-edge drain/refill");
      @(posedge clk);
      #1;
      if (!out_valid || out_data !== -16'sd2 || invalid_shift)
        $fatal(1, "quant same-edge drain/refill lost replacement result");

      @(negedge clk);
      in_valid = 1'b0;
      @(posedge clk);
      #1;
      if (!out_valid || out_data !== 16'sd3 || invalid_shift)
        $fatal(1, "quant refill input did not advance behind drained output");
      @(negedge clk);
      @(posedge clk);
      #1;
      if (out_valid)
        $fatal(1, "quant output did not drain after refill test");
    end
  endtask

  task automatic check_reset_clears_pipeline;
    begin
      @(negedge clk);
      out_ready = 1'b0;
      in_valid = 1'b1;
      in_data = 48'sd32768;
      shift_amount = 6'd0;
      relu_enable = 1'b0;
      @(posedge clk);
      @(negedge clk);
      in_data = -48'sd24;
      @(posedge clk);
      #1;
      if (!out_valid || !dut.stage1_valid)
        $fatal(1, "reset test failed to fill both quant stages");
      @(negedge clk);
      in_valid = 1'b0;
      rst = 1'b1;
      @(posedge clk);
      #1;
      if (out_valid || dut.stage1_valid || invalid_shift)
        $fatal(1, "reset left a valid quant result behind");
      @(negedge clk);
      rst = 1'b0;
      out_ready = 1'b1;
    end
  endtask

  initial begin
    clk = 1'b0;
    rst = 1'b1;
    in_valid = 1'b0;
    in_data = '0;
    shift_amount = '0;
    relu_enable = 1'b0;
    out_ready = 1'b1;
    repeat (3) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;

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
    check_full_rate();
    check_backpressure_and_refill();
    check_reset_clears_pipeline();
    $display("tb_runtime_relu_quant: PASS");
    $finish;
  end
endmodule
