`timescale 1ns/1ps

module tb_banked_activation_buffer;
  localparam integer P = 4;
  localparam integer WIDTH = 16;
  localparam integer MAX_DIM = 13;

  logic clk = 1'b0;
  logic rst;
  logic load_valid;
  logic load_ready;
  logic [1:0] load_chunk_index;
  logic [P-1:0] load_lane_mask;
  logic [P*WIDTH-1:0] load_data;
  logic read_req_valid;
  logic read_req_ready;
  logic [1:0] read_req_chunk_index;
  logic read_rsp_valid;
  logic read_rsp_ready;
  logic [P*WIDTH-1:0] read_rsp_data;
  logic scalar_write_valid;
  logic scalar_write_ready;
  logic [3:0] scalar_write_index;
  logic signed [WIDTH-1:0] scalar_write_data;
  logic access_error;

  always #5 clk = ~clk;

  initial begin : timeout_guard
    #200000;
    $display("tb_banked_activation_buffer: FAIL - timeout");
    $fatal(1, "tb_banked_activation_buffer timeout");
  end

  banked_activation_buffer #(
    .MAX_DIM(MAX_DIM), .NUM_BANKS(P), .DATA_WIDTH(WIDTH)
  ) dut (
    .clk(clk), .rst(rst),
    .load_valid(load_valid), .load_ready(load_ready),
    .load_chunk_index(load_chunk_index), .load_lane_mask(load_lane_mask),
    .load_data(load_data),
    .read_req_valid(read_req_valid), .read_req_ready(read_req_ready),
    .read_req_chunk_index(read_req_chunk_index),
    .read_rsp_valid(read_rsp_valid), .read_rsp_ready(read_rsp_ready),
    .read_rsp_data(read_rsp_data),
    .scalar_write_valid(scalar_write_valid),
    .scalar_write_ready(scalar_write_ready),
    .scalar_write_index(scalar_write_index),
    .scalar_write_data(scalar_write_data), .access_error(access_error)
  );

  task automatic load_chunk(
    input integer chunk,
    input logic [P-1:0] mask,
    input integer base
  );
    integer lane;
    begin
      @(negedge clk);
      load_chunk_index = chunk[1:0];
      load_lane_mask = mask;
      for (lane = 0; lane < P; lane = lane + 1)
        load_data[lane*WIDTH +: WIDTH] = base + lane;
      load_valid = 1'b1;
      while (!load_ready) @(negedge clk);
      @(posedge clk);
      @(negedge clk);
      load_valid = 1'b0;
    end
  endtask

  task automatic request_and_check(
    input integer chunk,
    input integer expected_base,
    input integer stall_cycles
  );
    integer lane;
    integer stall;
    logic [P*WIDTH-1:0] held;
    begin
      @(negedge clk);
      read_req_chunk_index = chunk[1:0];
      read_req_valid = 1'b1;
      while (!read_req_ready) @(negedge clk);
      @(posedge clk);
      @(negedge clk);
      read_req_valid = 1'b0;
      while (!read_rsp_valid) @(negedge clk);
      held = read_rsp_data;
      for (lane = 0; lane < P; lane = lane + 1)
        if ($signed(read_rsp_data[lane*WIDTH +: WIDTH]) !== expected_base+lane)
          $fatal(1, "banked read mismatch chunk=%0d lane=%0d", chunk, lane);
      for (stall = 0; stall < stall_cycles; stall = stall + 1) begin
        @(negedge clk);
        if (!read_rsp_valid || read_rsp_data !== held)
          $fatal(1, "banked response changed under backpressure");
      end
      read_rsp_ready = 1'b1;
      @(posedge clk);
      @(negedge clk);
      read_rsp_ready = 1'b0;
    end
  endtask

  initial begin
    rst = 1'b1;
    load_valid = 1'b0;
    load_chunk_index = '0;
    load_lane_mask = '0;
    load_data = '0;
    read_req_valid = 1'b0;
    read_req_chunk_index = '0;
    read_rsp_ready = 1'b0;
    scalar_write_valid = 1'b0;
    scalar_write_index = '0;
    scalar_write_data = '0;
    repeat (3) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;

    load_chunk(0, 4'b1111, 100);
    load_chunk(1, 4'b1111, 200);
    load_chunk(2, 4'b1111, 300);
    load_chunk(3, 4'b0001, 400);
    request_and_check(0, 100, 3);
    request_and_check(1, 200, 0);

    // Replace an accepted response with the next request on the same edge.
    @(negedge clk);
    read_req_valid = 1'b1;
    read_req_chunk_index = 2;
    while (!read_req_ready) @(negedge clk);
    @(posedge clk);
    @(negedge clk);
    if (!read_rsp_valid) $fatal(1, "missing first replacement response");
    read_rsp_ready = 1'b1;
    read_req_chunk_index = 3;
    #1;
    if (!read_req_ready)
      $fatal(1, "banked buffer blocked same-edge replacement");
    @(posedge clk);
    @(negedge clk);
    read_req_valid = 1'b0;
    read_rsp_ready = 1'b0;
    if (!read_rsp_valid || $signed(read_rsp_data[0 +: WIDTH]) !== 400)
      $fatal(1, "replacement response mismatch");
    read_rsp_ready = 1'b1;
    @(posedge clk);
    @(negedge clk);
    read_rsp_ready = 1'b0;

    // Scalar output index 5 maps to bank 1, address 1.
    scalar_write_index = 5;
    scalar_write_data = -16'sd77;
    scalar_write_valid = 1'b1;
    @(posedge clk);
    @(negedge clk);
    scalar_write_valid = 1'b0;
    read_req_chunk_index = 1;
    read_req_valid = 1'b1;
    while (!read_req_ready) @(negedge clk);
    @(posedge clk);
    @(negedge clk);
    read_req_valid = 1'b0;
    while (!read_rsp_valid) @(negedge clk);
    if ($signed(read_rsp_data[WIDTH +: WIDTH]) !== -16'sd77)
      $fatal(1, "scalar write bank mapping mismatch");
    if ($signed(read_rsp_data[0 +: WIDTH]) !== 16'sd200 ||
        $signed(read_rsp_data[2*WIDTH +: WIDTH]) !== 16'sd202 ||
        $signed(read_rsp_data[3*WIDTH +: WIDTH]) !== 16'sd203)
      $fatal(1, "scalar write corrupted another bank");
    read_rsp_ready = 1'b1;
    @(posedge clk);
    @(negedge clk);
    read_rsp_ready = 1'b0;

    if (access_error) $fatal(1, "unexpected banked access error");
    $display("tb_banked_activation_buffer: PASS");
    $finish;
  end
endmodule
