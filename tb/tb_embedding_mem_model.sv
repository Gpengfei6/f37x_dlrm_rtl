`timescale 1ns/1ps
module tb_embedding_mem_model;
  localparam integer NUM_ROWS = 32;
  localparam integer DIM = 8;
  localparam integer WIDTH = 8;
  localparam integer ID_WIDTH = 5;

  logic clk = 1'b0;
  logic rst;
  logic req_valid;
  logic req_ready;
  logic [ID_WIDTH-1:0] req_id;
  logic rsp_valid;
  logic rsp_ready;
  logic signed [DIM*WIDTH-1:0] rsp_data;
  logic signed [DIM*WIDTH-1:0] expected_row;
  integer lane;

  always #5 clk = ~clk;

  initial begin : timeout_guard
    #200000;
    $display("tb_embedding_mem_model: FAIL - timeout");
    $fatal(1, "tb_embedding_mem_model timeout");
  end

  embedding_mem_model #(
    .NUM_ROWS(NUM_ROWS), .EMBED_DIM(DIM), .DATA_WIDTH(WIDTH),
    .ID_WIDTH(ID_WIDTH), .INIT_FILE("tests/vectors/embedding.hex")
  ) dut (
    .clk(clk), .rst(rst),
    .req_valid(req_valid), .req_ready(req_ready), .req_id(req_id),
    .rsp_valid(rsp_valid), .rsp_ready(rsp_ready), .rsp_data(rsp_data)
  );

  task automatic request_and_check(
    input logic [ID_WIDTH-1:0] id,
    input logic signed [DIM*WIDTH-1:0] expected,
    input integer stall_cycles
  );
    logic signed [DIM*WIDTH-1:0] held;
    integer stall;
    begin
      @(negedge clk);
      req_id = id;
      req_valid = 1'b1;
      while (!req_ready) @(negedge clk);
      @(posedge clk);
      @(negedge clk);
      req_valid = 1'b0;
      if (!rsp_valid) $fatal(1, "embedding response did not arrive in one cycle");
      held = rsp_data;
      if (held !== expected)
        $fatal(1, "embedding row mismatch id=%0d expected=%h actual=%h", id, expected, held);
      for (stall = 0; stall < stall_cycles; stall = stall + 1) begin
        @(negedge clk);
        if (!rsp_valid || rsp_data !== held)
          $fatal(1, "embedding response changed under backpressure");
      end
      rsp_ready = 1'b1;
      @(posedge clk);
      @(negedge clk);
      rsp_ready = 1'b0;
    end
  endtask

  task automatic replacement_request(
    input logic [ID_WIDTH-1:0] first_id,
    input logic signed [DIM*WIDTH-1:0] first_expected,
    input logic [ID_WIDTH-1:0] second_id,
    input logic signed [DIM*WIDTH-1:0] second_expected,
    input logic [ID_WIDTH-1:0] third_id,
    input logic signed [DIM*WIDTH-1:0] third_expected
  );
    begin
      @(negedge clk);
      req_id = first_id;
      req_valid = 1'b1;
      rsp_ready = 1'b0;
      while (!req_ready) @(negedge clk);
      @(posedge clk);
      @(negedge clk);
      req_valid = 1'b0;
      if (!rsp_valid || rsp_data !== first_expected)
        $fatal(1, "replacement first embedding mismatch");

      // Retire the first response and accept the second request together.
      @(negedge clk);
      req_id = second_id;
      req_valid = 1'b1;
      rsp_ready = 1'b1;
      #1;
      if (!req_ready) $fatal(1, "embedding memory blocked replacement request");
      @(posedge clk);
      @(negedge clk);
      if (!rsp_valid || rsp_data !== second_expected)
        $fatal(1, "replacement second embedding mismatch");

      // Keep valid/ready asserted for a second consecutive replacement edge.
      req_id = third_id;
      #1;
      if (!req_ready)
        $fatal(1, "embedding memory blocked consecutive replacement request");
      @(posedge clk);
      @(negedge clk);
      req_valid = 1'b0;
      rsp_ready = 1'b0;
      if (!rsp_valid || rsp_data !== third_expected)
        $fatal(1, "replacement third embedding mismatch");
      rsp_ready = 1'b1;
      @(posedge clk);
      @(negedge clk);
      rsp_ready = 1'b0;
    end
  endtask

  initial begin
    rst = 1'b1;
    req_valid = 1'b0;
    req_id = '0;
    rsp_ready = 1'b0;
    expected_row = '0;
    repeat (3) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;

    expected_row = '0;
    request_and_check(5'd0, expected_row, 2);
    for (lane = 0; lane < DIM; lane = lane + 1)
      expected_row[lane*WIDTH +: WIDTH] = 8'sd127;
    request_and_check(5'd1, expected_row, 0);
    for (lane = 0; lane < DIM; lane = lane + 1)
      expected_row[lane*WIDTH +: WIDTH] = 8'sh80;
    request_and_check(5'd2, expected_row, 1);
    for (lane = 0; lane < DIM; lane = lane + 1)
      expected_row[lane*WIDTH +: WIDTH] =
          (lane % 2 == 0) ? 8'sd127 : 8'sh80;
    request_and_check(5'd3, expected_row, 0);

    replacement_request(
        5'd0, {DIM{8'h00}},
        5'd1, {DIM{8'h7f}},
        5'd2, {DIM{8'h80}});

    $display("tb_embedding_mem_model: PASS");
    $finish;
  end
endmodule
