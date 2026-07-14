`timescale 1ns/1ps
module tb_rv_fifo;
  localparam integer DATA_WIDTH = 8;
  localparam integer DEPTH = 4;

  logic clk = 1'b0;
  logic rst;
  logic in_valid;
  logic in_ready;
  logic [DATA_WIDTH-1:0] in_data;
  logic out_valid;
  logic out_ready;
  logic [DATA_WIDTH-1:0] out_data;
  logic full;
  logic empty;
  logic [$clog2(DEPTH+1)-1:0] count;

  logic depth1_in_valid;
  logic depth1_in_ready;
  logic [DATA_WIDTH-1:0] depth1_in_data;
  logic depth1_out_valid;
  logic depth1_out_ready;
  logic [DATA_WIDTH-1:0] depth1_out_data;
  logic depth1_full;
  logic depth1_empty;
  logic depth1_count;
  logic [DATA_WIDTH-1:0] depth1_expected;

  logic [DATA_WIDTH-1:0] expected [0:511];
  integer expected_write;
  integer expected_read;
  integer cycle;
  integer seed;

  always #5 clk = ~clk;

  initial begin : timeout_guard
    #200000;
    $display("tb_rv_fifo: FAIL - timeout");
    $fatal(1, "tb_rv_fifo timeout");
  end

  rv_fifo #(.DATA_WIDTH(DATA_WIDTH), .DEPTH(DEPTH)) dut (
    .clk(clk), .rst(rst),
    .in_valid(in_valid), .in_ready(in_ready), .in_data(in_data),
    .out_valid(out_valid), .out_ready(out_ready), .out_data(out_data),
    .full(full), .empty(empty), .count(count)
  );

  rv_fifo #(.DATA_WIDTH(DATA_WIDTH), .DEPTH(1)) depth1_dut (
    .clk(clk), .rst(rst),
    .in_valid(depth1_in_valid), .in_ready(depth1_in_ready),
    .in_data(depth1_in_data),
    .out_valid(depth1_out_valid), .out_ready(depth1_out_ready),
    .out_data(depth1_out_data),
    .full(depth1_full), .empty(depth1_empty), .count(depth1_count)
  );

  always @(posedge clk) begin
    if (!rst) begin
      if (out_valid && out_ready) begin
        if (expected_read >= expected_write)
          $fatal(1, "FIFO produced an unexpected word");
        if (out_data !== expected[expected_read])
          $fatal(1, "FIFO mismatch index=%0d expected=%0h actual=%0h",
                 expected_read, expected[expected_read], out_data);
        expected_read = expected_read + 1;
      end
      if (in_valid && in_ready) begin
        expected[expected_write] = in_data;
        expected_write = expected_write + 1;
      end
      if ((expected_write - expected_read) > DEPTH)
        $fatal(1, "scoreboard occupancy exceeded FIFO depth");
    end
  end

  task automatic push_word(input logic [DATA_WIDTH-1:0] value);
    begin
      @(negedge clk);
      in_valid = 1'b1;
      in_data = value;
      while (!in_ready) @(negedge clk);
      @(posedge clk);
      @(negedge clk);
      in_valid = 1'b0;
    end
  endtask

  task automatic pop_word;
    begin
      @(negedge clk);
      out_ready = 1'b1;
      while (!out_valid) @(negedge clk);
      @(posedge clk);
      @(negedge clk);
      out_ready = 1'b0;
    end
  endtask

  initial begin
    rst = 1'b1;
    in_valid = 1'b0;
    in_data = '0;
    out_ready = 1'b0;
    depth1_in_valid = 1'b0;
    depth1_in_data = '0;
    depth1_out_ready = 1'b0;
    depth1_expected = '0;
    expected_write = 0;
    expected_read = 0;
    seed = 32'h37f1f0;
    seed = $urandom(seed);
    repeat (3) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;

    if (!empty || full) $fatal(1, "FIFO reset status is incorrect");
    push_word(8'h11);
    push_word(8'h22);
    push_word(8'h33);
    push_word(8'h44);
    #1;
    if (!full || count != DEPTH) $fatal(1, "FIFO did not become full");
    repeat (3) begin
      @(negedge clk);
      if (!out_valid || out_data !== 8'h11)
        $fatal(1, "FIFO output changed under backpressure");
    end

    // Keep a full FIFO replacing one word per cycle through pointer wraps.
    @(negedge clk);
    in_valid = 1'b1;
    out_ready = 1'b1;
    for (cycle = 0; cycle < DEPTH*2; cycle = cycle + 1) begin
      in_data = 8'h55 + cycle;
      #1;
      if (!in_ready) $fatal(1, "FIFO blocked simultaneous full pop/push");
      if (!full || count != DEPTH)
        $fatal(1, "FIFO left full state before simultaneous transfer");
      @(posedge clk);
      @(negedge clk);
    end
    in_valid = 1'b0;
    out_ready = 1'b0;
    #1;
    if (!full || count != DEPTH) $fatal(1, "FIFO count changed on simultaneous transfer");

    repeat (DEPTH) pop_word();
    #1;
    if (!empty || count != 0) $fatal(1, "FIFO did not become empty");

    // DEPTH=1 must preserve the old output while replacing it every cycle.
    @(negedge clk);
    depth1_in_valid = 1'b1;
    depth1_in_data = 8'ha0;
    #1;
    if (!depth1_in_ready) $fatal(1, "depth-one FIFO rejected initial word");
    @(posedge clk);
    @(negedge clk);
    depth1_in_valid = 1'b0;
    depth1_expected = 8'ha0;
    #1;
    if (!depth1_full || !depth1_out_valid ||
        depth1_out_data !== depth1_expected)
      $fatal(1, "depth-one FIFO initial state mismatch");

    for (cycle = 0; cycle < 6; cycle = cycle + 1) begin
      depth1_in_valid = 1'b1;
      depth1_in_data = 8'hb0 + cycle;
      depth1_out_ready = 1'b1;
      #1;
      if (!depth1_in_ready)
        $fatal(1, "depth-one FIFO blocked replacement cycle=%0d", cycle);
      if (!depth1_out_valid || depth1_out_data !== depth1_expected)
        $fatal(1, "depth-one FIFO changed old output cycle=%0d", cycle);
      @(posedge clk);
      depth1_expected = 8'hb0 + cycle;
      @(negedge clk);
      #1;
      if (!depth1_full || depth1_count != 1'b1 ||
          depth1_out_data !== depth1_expected)
        $fatal(1, "depth-one FIFO replacement mismatch cycle=%0d", cycle);
    end
    depth1_in_valid = 1'b0;
    depth1_out_ready = 1'b1;
    @(posedge clk);
    @(negedge clk);
    depth1_out_ready = 1'b0;
    #1;
    if (!depth1_empty || depth1_count != 1'b0)
      $fatal(1, "depth-one FIFO did not drain");

    // Force multiple explicit pointer wraps before randomized traffic.
    for (cycle = 0; cycle < DEPTH*3; cycle = cycle + 1) begin
      push_word(cycle[DATA_WIDTH-1:0]);
      pop_word();
    end

    // Random source and random backpressure.  The scoreboard checks ordering.
    for (cycle = 0; cycle < 250; cycle = cycle + 1) begin
      @(negedge clk);
      // A stalled producer must hold valid and payload stable.
      if (!in_valid || in_ready) begin
        in_valid = $urandom() & 1;
        in_data = $urandom();
      end
      out_ready = $urandom() & 1;
    end
    @(negedge clk);
    in_valid = 1'b0;
    out_ready = 1'b1;
    cycle = 0;
    while (expected_read != expected_write && cycle < 32) begin
      @(negedge clk);
      cycle = cycle + 1;
    end
    if (expected_read != expected_write) $fatal(1, "FIFO drain timed out");
    @(negedge clk);
    out_ready = 1'b0;
    #1;
    if (!empty) $fatal(1, "FIFO not empty after random drain");
    $display("tb_rv_fifo: PASS transfers=%0d", expected_read);
    $finish;
  end
endmodule
