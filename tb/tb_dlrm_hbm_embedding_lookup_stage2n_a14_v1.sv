`timescale 1ns/1ps

module tb_dlrm_hbm_embedding_lookup_stage2n_a14_v1;
  localparam integer ROWS = 64;
  localparam integer DIM = 8;
  localparam integer ELEMENT_WIDTH = 16;
  localparam integer DATA_WIDTH = 128;
  localparam integer AXI_ADDR_WIDTH = 32;
  localparam integer AXI_ID_WIDTH = 1;
  localparam integer INDEX_WIDTH = $clog2(ROWS);

  logic clk = 1'b0;
  logic rst;

  logic lookup_req_valid;
  logic lookup_req_ready;
  logic [INDEX_WIDTH-1:0] lookup_req_index;

  logic lookup_rsp_valid;
  logic lookup_rsp_ready;
  logic [DATA_WIDTH-1:0] lookup_rsp_data;
  logic [INDEX_WIDTH-1:0] lookup_rsp_index;
  logic lookup_rsp_error;

  logic [AXI_ID_WIDTH-1:0] m_axi_arid;
  logic [AXI_ADDR_WIDTH-1:0] m_axi_araddr;
  logic [7:0] m_axi_arlen;
  logic [2:0] m_axi_arsize;
  logic [1:0] m_axi_arburst;
  logic m_axi_arlock;
  logic [3:0] m_axi_arcache;
  logic [2:0] m_axi_arprot;
  logic [3:0] m_axi_arqos;
  logic m_axi_arvalid;
  logic m_axi_arready;

  logic [AXI_ID_WIDTH-1:0] m_axi_rid;
  logic [DATA_WIDTH-1:0] m_axi_rdata;
  logic [1:0] m_axi_rresp;
  logic m_axi_rlast;
  logic m_axi_rvalid;
  logic m_axi_rready;

  logic [DATA_WIDTH-1:0] fake_memory [0:ROWS-1];
  logic memory_pending;
  logic [INDEX_WIDTH-1:0] pending_row;
  logic [AXI_ID_WIDTH-1:0] pending_id;
  integer response_delay;
  integer memory_cycle;
  integer ar_handshake_count;
  integer r_handshake_count;
  integer pass_count;
  integer expected_request_index;
  integer row;
  integer lane;

  logic ar_stall_active;
  logic [AXI_ADDR_WIDTH-1:0] stalled_araddr;

  always #5 clk = ~clk;

  assign m_axi_arready =
      !memory_pending && !m_axi_rvalid && (memory_cycle[1:0] != 2'b00);

  function automatic logic [DATA_WIDTH-1:0] expected_vector(
      input integer row_id
  );
    integer vector_lane;
    begin
      expected_vector = '0;
      for (vector_lane = 0; vector_lane < DIM;
           vector_lane = vector_lane + 1) begin
        expected_vector[
            vector_lane*ELEMENT_WIDTH +: ELEMENT_WIDTH] =
            row_id*DIM + vector_lane - 256;
      end
    end
  endfunction

  dlrm_hbm_embedding_lookup_stage2n_a14_v1 #(
    .ROWS(ROWS),
    .DIM(DIM),
    .ELEMENT_WIDTH(ELEMENT_WIDTH),
    .DATA_WIDTH(DATA_WIDTH),
    .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
    .AXI_ID_WIDTH(AXI_ID_WIDTH)
  ) dut (
    .clk(clk),
    .rst(rst),
    .lookup_req_valid(lookup_req_valid),
    .lookup_req_ready(lookup_req_ready),
    .lookup_req_index(lookup_req_index),
    .lookup_rsp_valid(lookup_rsp_valid),
    .lookup_rsp_ready(lookup_rsp_ready),
    .lookup_rsp_data(lookup_rsp_data),
    .lookup_rsp_index(lookup_rsp_index),
    .lookup_rsp_error(lookup_rsp_error),
    .m_axi_arid(m_axi_arid),
    .m_axi_araddr(m_axi_araddr),
    .m_axi_arlen(m_axi_arlen),
    .m_axi_arsize(m_axi_arsize),
    .m_axi_arburst(m_axi_arburst),
    .m_axi_arlock(m_axi_arlock),
    .m_axi_arcache(m_axi_arcache),
    .m_axi_arprot(m_axi_arprot),
    .m_axi_arqos(m_axi_arqos),
    .m_axi_arvalid(m_axi_arvalid),
    .m_axi_arready(m_axi_arready),
    .m_axi_rid(m_axi_rid),
    .m_axi_rdata(m_axi_rdata),
    .m_axi_rresp(m_axi_rresp),
    .m_axi_rlast(m_axi_rlast),
    .m_axi_rvalid(m_axi_rvalid),
    .m_axi_rready(m_axi_rready)
  );

  initial begin : timeout_guard
    #200000;
    $display("tb_dlrm_hbm_embedding_lookup_stage2n_a14_v1: FAIL timeout");
    $fatal(1, "A14.1 HBM lookup simulation timeout");
  end

  initial begin : initialize_fake_memory
    for (row = 0; row < ROWS; row = row + 1) begin
      fake_memory[row] = '0;
      for (lane = 0; lane < DIM; lane = lane + 1) begin
        fake_memory[row][lane*ELEMENT_WIDTH +: ELEMENT_WIDTH] =
            row*DIM + lane - 256;
      end
    end
  end

  always @(posedge clk) begin : fake_axi_memory
    if (rst) begin
      memory_pending <= 1'b0;
      pending_row <= '0;
      pending_id <= '0;
      response_delay <= 0;
      memory_cycle <= 0;
      ar_handshake_count <= 0;
      r_handshake_count <= 0;
      m_axi_rid <= '0;
      m_axi_rdata <= '0;
      m_axi_rresp <= 2'b00;
      m_axi_rlast <= 1'b0;
      m_axi_rvalid <= 1'b0;
    end else begin
      memory_cycle <= memory_cycle + 1;

      if (m_axi_arvalid && m_axi_arready) begin
        if (memory_pending || m_axi_rvalid)
          $fatal(1, "AXI memory accepted more than one outstanding read");
        if (m_axi_arlen !== 8'd0)
          $fatal(1, "ARLEN must be zero for a single-beat read");
        if (m_axi_arsize !== 3'd4)
          $fatal(1, "ARSIZE must describe a 16-byte transfer");
        if (m_axi_arburst !== 2'b01)
          $fatal(1, "ARBURST must be INCR");
        if (m_axi_arid !== '0)
          $fatal(1, "A14.1 prototype must issue AXI ID zero");
        if (m_axi_araddr[3:0] !== 4'b0000)
          $fatal(1, "AXI row address is not 16-byte aligned");
        if ((m_axi_araddr >> 4) >= ROWS)
          $fatal(1, "AXI row address is outside fake memory");
        if (m_axi_araddr !==
            (AXI_ADDR_WIDTH'(expected_request_index) << 4))
          $fatal(1,
                 "address mismatch index=%0d expected=%0h actual=%0h",
                 expected_request_index,
                 expected_request_index << 4,
                 m_axi_araddr);

        pending_row <= m_axi_araddr[INDEX_WIDTH+3:4];
        pending_id <= m_axi_arid;
        response_delay <= (expected_request_index % 3) + 1;
        memory_pending <= 1'b1;
        ar_handshake_count <= ar_handshake_count + 1;
      end

      if (memory_pending) begin
        if (response_delay == 0) begin
          m_axi_rid <= pending_id;
          m_axi_rdata <= fake_memory[pending_row];
          m_axi_rresp <= 2'b00;
          m_axi_rlast <= 1'b1;
          m_axi_rvalid <= 1'b1;
          memory_pending <= 1'b0;
        end else begin
          response_delay <= response_delay - 1;
        end
      end

      if (m_axi_rvalid && m_axi_rready) begin
        m_axi_rvalid <= 1'b0;
        m_axi_rlast <= 1'b0;
        r_handshake_count <= r_handshake_count + 1;
      end
    end
  end

  always @(posedge clk) begin : check_ar_stability
    if (rst) begin
      ar_stall_active <= 1'b0;
      stalled_araddr <= '0;
    end else if (m_axi_arvalid && !m_axi_arready) begin
      if (ar_stall_active && m_axi_araddr !== stalled_araddr)
        $fatal(1, "ARADDR changed while ARVALID was stalled");
      stalled_araddr <= m_axi_araddr;
      ar_stall_active <= 1'b1;
    end else begin
      ar_stall_active <= 1'b0;
    end
  end

  task automatic run_lookup(input integer row_id);
    logic [DATA_WIDTH-1:0] expected;
    logic [DATA_WIDTH-1:0] held_data;
    logic [INDEX_WIDTH-1:0] held_index;
    logic held_error;
    integer stall_cycles;
    integer stall_index;
    begin
      expected = expected_vector(row_id);
      expected_request_index = row_id;

      @(negedge clk);
      lookup_req_index = row_id[INDEX_WIDTH-1:0];
      lookup_req_valid = 1'b1;
      while (!lookup_req_ready)
        @(negedge clk);

      @(posedge clk);
      @(negedge clk);
      lookup_req_valid = 1'b0;

      wait (lookup_rsp_valid === 1'b1);
      #1;
      if (lookup_rsp_data !== expected)
        $fatal(1,
               "lookup data mismatch row=%0d expected=%0h actual=%0h",
               row_id, expected, lookup_rsp_data);
      if (lookup_rsp_index !== row_id[INDEX_WIDTH-1:0])
        $fatal(1,
               "lookup index mismatch expected=%0d actual=%0d",
               row_id, lookup_rsp_index);
      if (lookup_rsp_error !== 1'b0)
        $fatal(1, "lookup unexpectedly reported an AXI error row=%0d", row_id);

      held_data = lookup_rsp_data;
      held_index = lookup_rsp_index;
      held_error = lookup_rsp_error;
      stall_cycles = row_id % 4;
      for (stall_index = 0; stall_index < stall_cycles;
           stall_index = stall_index + 1) begin
        @(posedge clk);
        #1;
        if (!lookup_rsp_valid ||
            lookup_rsp_data !== held_data ||
            lookup_rsp_index !== held_index ||
            lookup_rsp_error !== held_error)
          $fatal(1, "lookup response changed under backpressure row=%0d",
                 row_id);
      end

      @(negedge clk);
      lookup_rsp_ready = 1'b1;
      @(posedge clk);
      @(negedge clk);
      lookup_rsp_ready = 1'b0;
      pass_count = pass_count + 1;
    end
  endtask

  initial begin : run_test
    rst = 1'b1;
    lookup_req_valid = 1'b0;
    lookup_req_index = '0;
    lookup_rsp_ready = 1'b0;
    pass_count = 0;
    expected_request_index = 0;

    repeat (5) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;

    for (row = 0; row < ROWS; row = row + 1)
      run_lookup(row);

    repeat (3) @(posedge clk);
    if (pass_count != 64)
      $fatal(1, "expected 64 passing lookups, observed %0d", pass_count);
    if (ar_handshake_count != 64)
      $fatal(1, "expected 64 AR handshakes, observed %0d",
             ar_handshake_count);
    if (r_handshake_count != 64)
      $fatal(1, "expected 64 R handshakes, observed %0d",
             r_handshake_count);
    if (!lookup_req_ready || lookup_rsp_valid)
      $fatal(1, "DUT did not return to IDLE after final response");

    $display(
        "tb_dlrm_hbm_embedding_lookup_stage2n_a14_v1: PASS cases=64");
    $finish;
  end
endmodule
