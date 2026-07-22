`timescale 1ns/1ps

module tb_local_weight_provider;
  localparam integer P = 4;
  localparam integer MAX_WEIGHT_VALUES = 18;
  localparam integer MAX_BIAS_VALUES = 5;
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
    .MAX_WEIGHT_VALUES(MAX_WEIGHT_VALUES),
    .MAX_BIAS_VALUES(MAX_BIAS_VALUES)
  ) dut (.*);

  task automatic request_weight_and_check(
    input integer address,
    input logic [P-1:0] mask,
    input logic expected_error,
    input integer stall_cycles
  );
    integer lane;
    integer stall;
    integer expected_value;
    logic [P*8-1:0] held_data;
    logic held_error;
    begin
      @(negedge clk);
      weight_req_address = address;
      weight_req_lane_mask = mask;
      weight_req_valid = 1'b1;
      while (!weight_req_ready) @(negedge clk);
      @(posedge clk);
      @(negedge clk);
      weight_req_valid = 1'b0;
      if (!weight_rsp_valid || weight_rsp_error !== expected_error)
        $fatal(1, "weight response/error mismatch address=%0d", address);
      for (lane = 0; lane < P; lane = lane + 1) begin
        if (mask[lane] && ((address+lane) < MAX_WEIGHT_VALUES))
          expected_value = address+lane-9;
        else
          expected_value = 0;
        if ($signed(weight_rsp_data[lane*8 +: 8]) !== expected_value)
          $fatal(1,
              "weight data mismatch address=%0d lane=%0d expected=%0d got=%0d",
              address, lane, expected_value,
              $signed(weight_rsp_data[lane*8 +: 8]));
      end
      held_data = weight_rsp_data;
      held_error = weight_rsp_error;
      for (stall = 0; stall < stall_cycles; stall = stall + 1) begin
        @(negedge clk);
        if (!weight_rsp_valid || weight_rsp_data !== held_data ||
            weight_rsp_error !== held_error)
          $fatal(1, "weight response changed under backpressure");
      end
      weight_rsp_ready = 1'b1;
      @(posedge clk);
      @(negedge clk);
      weight_rsp_ready = 1'b0;
    end
  endtask

  task automatic check_continuous_weight_reads;
    integer request_index;
    integer lane;
    integer address;
    integer expected_value;
    begin
      @(negedge clk);
      weight_rsp_ready = 1'b1;
      weight_req_valid = 1'b1;
      weight_req_lane_mask = 4'b1111;
      weight_req_address = 1;
      for (request_index = 0; request_index < 3;
           request_index = request_index + 1) begin
        address = request_index+1;
        #1;
        if (!weight_req_ready)
          $fatal(1, "weight provider blocked continuous request %0d", address);
        @(posedge clk);
        @(negedge clk);
        if (!weight_rsp_valid || weight_rsp_error)
          $fatal(1, "continuous weight response missing address=%0d", address);
        for (lane = 0; lane < P; lane = lane + 1) begin
          expected_value = address+lane-9;
          if ($signed(weight_rsp_data[lane*8 +: 8]) !== expected_value)
            $fatal(1,
                "continuous weight mismatch address=%0d lane=%0d",
                address, lane);
        end
        weight_req_address = address+1;
      end
      weight_req_valid = 1'b0;
      @(posedge clk);
      @(negedge clk);
      weight_rsp_ready = 1'b0;
      if (weight_rsp_valid)
        $fatal(1, "continuous weight response failed to drain");
    end
  endtask

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

    for (index = 0; index < MAX_WEIGHT_VALUES; index = index + 1) begin
      weight_cfg_address = index;
      weight_cfg_data = index-9;
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
    bias_cfg_address = MAX_BIAS_VALUES-1;
    bias_cfg_data = 24'sd765432;
    @(posedge clk);
    @(negedge clk);
    bias_cfg_valid = 1'b0;

    // Aligned, unaligned, cross-row, stalled, and continuous requests.
    request_weight_and_check(4, 4'b1111, 1'b0, 3);
    request_weight_and_check(1, 4'b1111, 1'b0, 0);
    request_weight_and_check(3, 4'b1111, 1'b0, 0);
    check_continuous_weight_reads();

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

    // Final row, highest address, masked lanes, and one lane past the end.
    request_weight_and_check(14, 4'b1111, 1'b0, 0);
    request_weight_and_check(17, 4'b0001, 1'b0, 0);
    request_weight_and_check(14, 4'b0011, 1'b0, 0);
    request_weight_and_check(17, 4'b0011, 1'b1, 0);

    bias_req_address = MAX_BIAS_VALUES-1;
    bias_req_valid = 1'b1;
    @(posedge clk);
    @(negedge clk);
    bias_req_valid = 1'b0;
    if (!bias_rsp_valid || bias_rsp_data !== 24'sd765432 || bias_rsp_error)
      $fatal(1, "highest bias response mismatch");
    bias_rsp_ready = 1'b1;
    @(posedge clk);
    @(negedge clk);
    bias_rsp_ready = 1'b0;

    bias_req_address = MAX_BIAS_VALUES;
    bias_req_valid = 1'b1;
    @(posedge clk);
    @(negedge clk);
    bias_req_valid = 1'b0;
    if (!bias_rsp_valid || !bias_rsp_error || bias_rsp_data !== '0)
      $fatal(1, "out-of-range bias request lacked error response");
    bias_rsp_ready = 1'b1;
    @(posedge clk);

    $display("tb_local_weight_provider: PASS");
    $finish;
  end
endmodule
