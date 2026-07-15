`timescale 1ns/1ps

module tb_local_weight_provider;
  localparam integer P = 4;
  logic clk = 1'b0;
  logic rst;
  logic weight_cfg_valid;
  logic weight_cfg_ready;
  logic [7:0] weight_cfg_address;
  logic signed [7:0] weight_cfg_data;
  logic bias_cfg_valid;
  logic bias_cfg_ready;
  logic [7:0] bias_cfg_address;
  logic signed [23:0] bias_cfg_data;
  logic weight_req_valid;
  logic weight_req_ready;
  logic [7:0] weight_req_address;
  logic [P-1:0] weight_req_lane_mask;
  logic weight_rsp_valid;
  logic weight_rsp_ready;
  logic [P*8-1:0] weight_rsp_data;
  logic weight_rsp_error;
  logic bias_req_valid;
  logic bias_req_ready;
  logic [7:0] bias_req_address;
  logic bias_rsp_valid;
  logic bias_rsp_ready;
  logic signed [23:0] bias_rsp_data;
  logic bias_rsp_error;
  integer index;

  always #5 clk = ~clk;

  initial begin : timeout_guard
    #200000;
    $display("tb_local_weight_provider: FAIL - timeout");
    $fatal(1, "tb_local_weight_provider timeout");
  end

  local_weight_provider #(
    .NUM_PE(P), .WEIGHT_ADDR_WIDTH(8), .BIAS_ADDR_WIDTH(8),
    .MAX_WEIGHT_VALUES(16), .MAX_BIAS_VALUES(4)
  ) dut (.*);

  initial begin
    rst = 1'b1;
    weight_cfg_valid = 1'b0;
    weight_cfg_address = '0;
    weight_cfg_data = '0;
    bias_cfg_valid = 1'b0;
    bias_cfg_address = '0;
    bias_cfg_data = '0;
    weight_req_valid = 1'b0;
    weight_req_address = '0;
    weight_req_lane_mask = '0;
    weight_rsp_ready = 1'b0;
    bias_req_valid = 1'b0;
    bias_req_address = '0;
    bias_rsp_ready = 1'b0;
    repeat (3) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;

    for (index = 0; index < 16; index = index + 1) begin
      weight_cfg_address = index;
      weight_cfg_data = index-8;
      weight_cfg_valid = 1'b1;
      @(posedge clk);
      @(negedge clk);
    end
    weight_cfg_valid = 1'b0;
    bias_cfg_address = 2;
    bias_cfg_data = -24'sd12345;
    bias_cfg_valid = 1'b1;
    @(posedge clk);
    @(negedge clk);
    bias_cfg_valid = 1'b0;

    weight_req_address = 4;
    weight_req_lane_mask = 4'b1111;
    weight_req_valid = 1'b1;
    @(posedge clk);
    @(negedge clk);
    weight_req_valid = 1'b0;
    if (!weight_rsp_valid) $fatal(1, "weight response missing");
    for (index = 0; index < P; index = index + 1)
      if ($signed(weight_rsp_data[index*8 +: 8]) !== index-4)
        $fatal(1, "weight lane mismatch");
    repeat (3) begin
      @(negedge clk);
      if (!weight_rsp_valid)
        $fatal(1, "weight response dropped under backpressure");
    end

    // Consume address 4 and replace it with address 8 on the same edge.
    weight_rsp_ready = 1'b1;
    weight_req_valid = 1'b1;
    weight_req_address = 8;
    #1;
    if (!weight_req_ready)
      $fatal(1, "weight provider blocked same-edge replacement");
    @(posedge clk);
    @(negedge clk);
    weight_req_valid = 1'b0;
    weight_rsp_ready = 1'b0;
    if (!weight_rsp_valid || $signed(weight_rsp_data[0 +: 8]) !== 0)
      $fatal(1, "replacement weight response mismatch");
    weight_rsp_ready = 1'b1;
    @(posedge clk);
    @(negedge clk);
    weight_rsp_ready = 1'b0;

    bias_req_address = 2;
    bias_req_valid = 1'b1;
    @(posedge clk);
    @(negedge clk);
    bias_req_valid = 1'b0;
    if (!bias_rsp_valid || bias_rsp_data !== -24'sd12345 || bias_rsp_error)
      $fatal(1, "bias response mismatch");
    bias_rsp_ready = 1'b1;
    @(posedge clk);
    @(negedge clk);
    bias_rsp_ready = 1'b0;

    // Tail request must zero masked lanes even when their addresses are valid.
    weight_req_address = 14;
    weight_req_lane_mask = 4'b0011;
    weight_req_valid = 1'b1;
    @(posedge clk);
    @(negedge clk);
    weight_req_valid = 1'b0;
    if (weight_rsp_error || weight_rsp_data[31:16] !== 16'h0000)
      $fatal(1, "tail mask behavior mismatch");
    weight_rsp_ready = 1'b1;
    @(posedge clk);
    @(negedge clk);
    weight_rsp_ready = 1'b0;

    weight_req_address = 15;
    weight_req_lane_mask = 4'b0011;
    weight_req_valid = 1'b1;
    @(posedge clk);
    @(negedge clk);
    weight_req_valid = 1'b0;
    if (!weight_rsp_valid || !weight_rsp_error)
      $fatal(1, "out-of-range weight request lacked error response");
    weight_rsp_ready = 1'b1;
    @(posedge clk);
    @(negedge clk);
    weight_rsp_ready = 1'b0;

    bias_req_address = 4;
    bias_req_valid = 1'b1;
    @(posedge clk);
    @(negedge clk);
    bias_req_valid = 1'b0;
    if (!bias_rsp_valid || !bias_rsp_error)
      $fatal(1, "out-of-range bias request lacked error response");
    bias_rsp_ready = 1'b1;
    @(posedge clk);

    $display("tb_local_weight_provider: PASS");
    $finish;
  end
endmodule
