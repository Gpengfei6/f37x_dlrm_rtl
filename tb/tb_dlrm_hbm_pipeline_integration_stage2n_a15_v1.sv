`timescale 1ns/1ps

module tb_dlrm_hbm_pipeline_integration_stage2n_a15_v1;
  localparam integer MAX_LAYERS = 8;
  localparam integer MAX_IN_DIM = 64;
  localparam integer MAX_OUT_DIM = 64;
  localparam integer NUM_PE = 16;
  localparam integer INPUT_WIDTH = 16;
  localparam integer LAYER_INDEX_WIDTH = 3;
  localparam integer LAYER_COUNT_WIDTH = 4;
  localparam integer ACT_CHUNK_ADDR_WIDTH = 2;
  localparam integer SHIFT_WIDTH = 6;
  localparam integer OUT_INDEX_WIDTH = 6;
  localparam integer HBM_ADDR_WIDTH = 64;
  localparam integer HBM_DATA_WIDTH = 128;
  localparam integer HBM_INDEX_WIDTH = 32;

  localparam logic [11:0] A13_BOTTOM_CYCLES_ADDR = 12'h218;
  localparam logic [11:0] A13_INTERACTION_CYCLES_ADDR = 12'h21C;
  localparam logic [11:0] A13_TOP_CYCLES_ADDR = 12'h220;
  localparam logic [11:0] A13_TOTAL_CYCLES_ADDR = 12'h224;
  localparam logic [HBM_ADDR_WIDTH-1:0] ALIGNED_TABLE_BASE =
      64'h0000_0001_2345_6000;

  logic clk;
  logic rst;

  logic descriptor_cfg_valid;
  logic descriptor_cfg_ready;
  logic [LAYER_INDEX_WIDTH-1:0] descriptor_cfg_index;
  logic [95:0] descriptor_cfg_data;

  logic act_load_valid;
  logic act_load_ready;
  logic act_load_buffer_select;
  logic [ACT_CHUNK_ADDR_WIDTH-1:0] act_load_chunk_index;
  logic [NUM_PE-1:0] act_load_lane_mask;
  logic [NUM_PE*INPUT_WIDTH-1:0] act_load_data;

  logic host_embedding_cfg_valid;
  logic host_embedding_cfg_ready;
  logic [1:0] host_embedding_cfg_index;
  logic [127:0] host_embedding_cfg_data;
  logic host_embedding_cfg_rejected;
  logic [3:0] embedding_loaded_mask;

  logic weight_cfg_valid;
  logic weight_cfg_ready;
  logic [31:0] weight_cfg_address;
  logic signed [7:0] weight_cfg_data;
  logic bias_cfg_valid;
  logic bias_cfg_ready;
  logic [31:0] bias_cfg_address;
  logic signed [23:0] bias_cfg_data;

  logic pipeline_start_valid;
  logic pipeline_start_ready;
  logic [LAYER_INDEX_WIDTH-1:0] bottom_descriptor_base;
  logic [LAYER_COUNT_WIDTH-1:0] bottom_layer_count;
  logic [LAYER_INDEX_WIDTH-1:0] top_descriptor_base;
  logic [LAYER_COUNT_WIDTH-1:0] top_layer_count;
  logic bottom_initial_buffer_select;
  logic top_input_buffer_select;
  logic [SHIFT_WIDTH-1:0] interaction_shift;

  logic result_valid;
  logic result_ready;
  logic signed [15:0] result_data;
  logic [OUT_INDEX_WIDTH-1:0] result_index;
  logic result_last;
  logic [7:0] result_tag;
  logic busy;
  logic done;
  logic [3:0] phase;
  logic [3:0] bottom_result_count;
  logic [4:0] interaction_result_count;
  logic [31:0] bottom_cycle_count;
  logic [31:0] interaction_cycle_count;
  logic [31:0] top_cycle_count;
  logic [31:0] total_cycle_count;
  logic pipeline_error_valid;
  logic pipeline_error_ready;
  logic [7:0] pipeline_error_code;

  logic [HBM_ADDR_WIDTH-1:0] table_base_addr;
  logic lookup_req_valid;
  logic lookup_req_ready;
  logic [HBM_INDEX_WIDTH-1:0] lookup_req_index;
  logic hbm_lookup_busy;
  logic hbm_inject_pending;
  logic hbm_inject_done;
  logic hbm_lookup_error_valid;
  logic hbm_lookup_error_ready;
  logic [HBM_INDEX_WIDTH-1:0] hbm_lookup_error_index;

  logic m_axi_arid;
  logic [HBM_ADDR_WIDTH-1:0] m_axi_araddr;
  logic [7:0] m_axi_arlen;
  logic [2:0] m_axi_arsize;
  logic [1:0] m_axi_arburst;
  logic m_axi_arlock;
  logic [3:0] m_axi_arcache;
  logic [2:0] m_axi_arprot;
  logic [3:0] m_axi_arqos;
  logic m_axi_arvalid;
  logic m_axi_arready;
  logic m_axi_rid;
  logic [HBM_DATA_WIDTH-1:0] m_axi_rdata;
  logic [1:0] m_axi_rresp;
  logic m_axi_rlast;
  logic m_axi_rvalid;
  logic m_axi_rready;

  logic memory_pending;
  logic [5:0] pending_row;
  integer response_delay;
  integer next_response_delay;
  logic [HBM_ADDR_WIDTH-1:0] accepted_table_base;
  logic [HBM_INDEX_WIDTH-1:0] accepted_lookup_index;
  integer accepted_response_delay;
  integer lookup_handshake_count;
  integer ar_handshake_count;
  integer r_handshake_count;
  integer timeout_cycles;

  logic [127:0] slot1_pattern;
  logic [127:0] slot2_pattern;
  logic [127:0] slot3_pattern;
  logic [127:0] expected_slot0;
  logic [127:0] held_pending_data;
  integer count_before;
  integer hold_cycle;

  always #5 clk = ~clk;

  function automatic logic [127:0] packed_lane_sequence(
      input integer first_value
  );
    integer lane;
    integer lane_value;
    begin
      packed_lane_sequence = '0;
      for (lane = 0; lane < 8; lane = lane + 1) begin
        lane_value = first_value + lane;
        packed_lane_sequence[lane*16 +: 16] = lane_value[15:0];
      end
    end
  endfunction

  function automatic logic [127:0] golden_hbm_row(input integer row);
    begin
      golden_hbm_row = packed_lane_sequence(row*8 - 256);
    end
  endfunction

  task automatic configure_host_embedding(
      input logic [1:0] index,
      input logic [127:0] data,
      input logic expect_reject
  );
    begin
      @(negedge clk);
      host_embedding_cfg_index = index;
      host_embedding_cfg_data = data;
      host_embedding_cfg_valid = 1'b1;
      while (!host_embedding_cfg_ready)
        @(negedge clk);
      @(posedge clk);
      #1;
      if (host_embedding_cfg_rejected !== expect_reject)
        $fatal(1,
               "Host embedding rejection mismatch index=%0d expected=%0b actual=%0b",
               index, expect_reject, host_embedding_cfg_rejected);
      @(negedge clk);
      host_embedding_cfg_valid = 1'b0;
    end
  endtask

  task automatic start_lookup(
      input logic [HBM_ADDR_WIDTH-1:0] base_address,
      input integer row_index,
      input integer delay_cycles
  );
    begin
      next_response_delay = delay_cycles;
      @(negedge clk);
      table_base_addr = base_address;
      lookup_req_index = row_index;
      lookup_req_valid = 1'b1;
      while (!lookup_req_ready)
        @(negedge clk);
      @(posedge clk);
      @(negedge clk);
      lookup_req_valid = 1'b0;
    end
  endtask

  task automatic acknowledge_hbm_error;
    begin
      @(negedge clk);
      hbm_lookup_error_ready = 1'b1;
      @(posedge clk);
      @(negedge clk);
      hbm_lookup_error_ready = 1'b0;
      if (hbm_lookup_error_valid)
        $fatal(1, "HBM error did not clear after acknowledgement");
    end
  endtask

  task automatic acknowledge_pipeline_error;
    begin
      @(negedge clk);
      pipeline_error_ready = 1'b1;
      @(posedge clk);
      @(negedge clk);
      pipeline_error_ready = 1'b0;
    end
  endtask

  assign m_axi_arready = !memory_pending && !m_axi_rvalid;

  always_ff @(posedge clk) begin
    if (rst) begin
      accepted_table_base <= '0;
      accepted_lookup_index <= '0;
      accepted_response_delay <= 0;
      lookup_handshake_count <= 0;
      memory_pending <= 1'b0;
      pending_row <= '0;
      response_delay <= 0;
      ar_handshake_count <= 0;
      r_handshake_count <= 0;
      m_axi_rid <= 1'b0;
      m_axi_rdata <= '0;
      m_axi_rresp <= 2'b00;
      m_axi_rlast <= 1'b0;
      m_axi_rvalid <= 1'b0;
    end else begin
      if (lookup_req_valid && lookup_req_ready) begin
        accepted_table_base <= table_base_addr;
        accepted_lookup_index <= lookup_req_index;
        accepted_response_delay <= next_response_delay;
        lookup_handshake_count <= lookup_handshake_count + 1;
      end

      if (m_axi_arvalid && m_axi_arready) begin
        if (m_axi_arid !== 1'b0 || m_axi_arlen !== 8'd0 ||
            m_axi_arsize !== 3'd4 || m_axi_arburst !== 2'b01)
          $fatal(1, "A15.1 observed an invalid AXI read request");
        if (m_axi_araddr !==
            accepted_table_base + (accepted_lookup_index << 4))
          $fatal(1,
                 "A15.1 AXI address mismatch expected=%016h actual=%016h",
                 accepted_table_base + (accepted_lookup_index << 4),
                 m_axi_araddr);
        pending_row <= accepted_lookup_index[5:0];
        response_delay <= accepted_response_delay;
        memory_pending <= 1'b1;
        ar_handshake_count <= ar_handshake_count + 1;
      end

      if (memory_pending) begin
        if (response_delay == 0) begin
          m_axi_rid <= 1'b0;
          m_axi_rdata <= golden_hbm_row(pending_row);
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
        r_handshake_count <= r_handshake_count + 1;
      end
    end
  end

  dlrm_hbm_pipeline_integration_stage2n_a15_v1 dut (
    .clk(clk),
    .rst(rst),
    .descriptor_cfg_valid(descriptor_cfg_valid),
    .descriptor_cfg_ready(descriptor_cfg_ready),
    .descriptor_cfg_index(descriptor_cfg_index),
    .descriptor_cfg_data(descriptor_cfg_data),
    .act_load_valid(act_load_valid),
    .act_load_ready(act_load_ready),
    .act_load_buffer_select(act_load_buffer_select),
    .act_load_chunk_index(act_load_chunk_index),
    .act_load_lane_mask(act_load_lane_mask),
    .act_load_data(act_load_data),
    .host_embedding_cfg_valid(host_embedding_cfg_valid),
    .host_embedding_cfg_ready(host_embedding_cfg_ready),
    .host_embedding_cfg_index(host_embedding_cfg_index),
    .host_embedding_cfg_data(host_embedding_cfg_data),
    .host_embedding_cfg_rejected(host_embedding_cfg_rejected),
    .embedding_loaded_mask(embedding_loaded_mask),
    .weight_cfg_valid(weight_cfg_valid),
    .weight_cfg_ready(weight_cfg_ready),
    .weight_cfg_address(weight_cfg_address),
    .weight_cfg_data(weight_cfg_data),
    .bias_cfg_valid(bias_cfg_valid),
    .bias_cfg_ready(bias_cfg_ready),
    .bias_cfg_address(bias_cfg_address),
    .bias_cfg_data(bias_cfg_data),
    .pipeline_start_valid(pipeline_start_valid),
    .pipeline_start_ready(pipeline_start_ready),
    .bottom_descriptor_base(bottom_descriptor_base),
    .bottom_layer_count(bottom_layer_count),
    .top_descriptor_base(top_descriptor_base),
    .top_layer_count(top_layer_count),
    .bottom_initial_buffer_select(bottom_initial_buffer_select),
    .top_input_buffer_select(top_input_buffer_select),
    .interaction_shift(interaction_shift),
    .result_valid(result_valid),
    .result_ready(result_ready),
    .result_data(result_data),
    .result_index(result_index),
    .result_last(result_last),
    .result_tag(result_tag),
    .busy(busy),
    .done(done),
    .phase(phase),
    .bottom_result_count(bottom_result_count),
    .interaction_result_count(interaction_result_count),
    .bottom_cycle_count(bottom_cycle_count),
    .interaction_cycle_count(interaction_cycle_count),
    .top_cycle_count(top_cycle_count),
    .total_cycle_count(total_cycle_count),
    .pipeline_error_valid(pipeline_error_valid),
    .pipeline_error_ready(pipeline_error_ready),
    .pipeline_error_code(pipeline_error_code),
    .table_base_addr(table_base_addr),
    .lookup_req_valid(lookup_req_valid),
    .lookup_req_ready(lookup_req_ready),
    .lookup_req_index(lookup_req_index),
    .hbm_lookup_busy(hbm_lookup_busy),
    .hbm_inject_pending(hbm_inject_pending),
    .hbm_inject_done(hbm_inject_done),
    .hbm_lookup_error_valid(hbm_lookup_error_valid),
    .hbm_lookup_error_ready(hbm_lookup_error_ready),
    .hbm_lookup_error_index(hbm_lookup_error_index),
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

  always_ff @(posedge clk) begin
    if (rst)
      timeout_cycles <= 0;
    else begin
      timeout_cycles <= timeout_cycles + 1;
      if (timeout_cycles > 20000)
        $fatal(1, "A15.1 integration test timeout");
    end
  end

  initial begin
    clk = 1'b0;
    rst = 1'b1;
    descriptor_cfg_valid = 1'b0;
    descriptor_cfg_index = '0;
    descriptor_cfg_data = '0;
    act_load_valid = 1'b0;
    act_load_buffer_select = 1'b0;
    act_load_chunk_index = '0;
    act_load_lane_mask = '0;
    act_load_data = '0;
    host_embedding_cfg_valid = 1'b0;
    host_embedding_cfg_index = 2'd0;
    host_embedding_cfg_data = '0;
    weight_cfg_valid = 1'b0;
    weight_cfg_address = '0;
    weight_cfg_data = '0;
    bias_cfg_valid = 1'b0;
    bias_cfg_address = '0;
    bias_cfg_data = '0;
    pipeline_start_valid = 1'b0;
    bottom_descriptor_base = '0;
    bottom_layer_count = '0;
    top_descriptor_base = '0;
    top_layer_count = '0;
    bottom_initial_buffer_select = 1'b0;
    top_input_buffer_select = 1'b0;
    interaction_shift = '0;
    result_ready = 1'b0;
    pipeline_error_ready = 1'b0;
    table_base_addr = ALIGNED_TABLE_BASE;
    lookup_req_valid = 1'b0;
    lookup_req_index = '0;
    hbm_lookup_error_ready = 1'b0;
    next_response_delay = 0;

    slot1_pattern = packed_lane_sequence(100);
    slot2_pattern = packed_lane_sequence(-200);
    slot3_pattern = packed_lane_sequence(300);

    repeat (8) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;
    repeat (3) @(posedge clk);

    if ((A13_BOTTOM_CYCLES_ADDR !== 12'h218) ||
        (A13_INTERACTION_CYCLES_ADDR !== 12'h21C) ||
        (A13_TOP_CYCLES_ADDR !== 12'h220) ||
        (A13_TOTAL_CYCLES_ADDR !== 12'h224))
      $fatal(1, "A13 cycle-counter ABI guard failed");
    $display("A15_1_A13_ABI_PRESERVED=PASS");

    // Host slot 0 is consumed and explicitly rejected, never forwarded.
    configure_host_embedding(2'd0, packed_lane_sequence(700), 1'b1);
    if (embedding_loaded_mask !== 4'b0000)
      $fatal(1, "Host slot-0 request changed the loaded mask");
    $display("A15_1_HOST_SLOT0_GUARD=PASS");

    configure_host_embedding(2'd1, slot1_pattern, 1'b0);
    configure_host_embedding(2'd2, slot2_pattern, 1'b0);
    configure_host_embedding(2'd3, slot3_pattern, 1'b0);
    if (embedding_loaded_mask !== 4'b1110)
      $fatal(1, "Host slot1-3 loaded mask mismatch: %b",
             embedding_loaded_mask);
    if (dut.u_a13_pipeline.u_canonical_pipeline.embedding_mem[1] !==
            slot1_pattern ||
        dut.u_a13_pipeline.u_canonical_pipeline.embedding_mem[2] !==
            slot2_pattern ||
        dut.u_a13_pipeline.u_canonical_pipeline.embedding_mem[3] !==
            slot3_pattern)
      $fatal(1, "Host slot1-3 data mismatch");
    $display("A15_1_HOST_SLOT123_PRESERVED=PASS");

    // A locally rejected A14 request must not issue AXI or set slot 0 loaded.
    count_before = ar_handshake_count;
    start_lookup(ALIGNED_TABLE_BASE + 64'd8, 7, 0);
    wait (hbm_lookup_error_valid === 1'b1);
    #1;
    if (hbm_lookup_error_index !== 32'd7 || hbm_inject_pending ||
        embedding_loaded_mask[0] || ar_handshake_count != count_before)
      $fatal(1, "Initial lookup error guard failed");
    acknowledge_hbm_error();

    // Force the accepted A13 controller into its missing-embedding error state.
    // This closes its configuration window so a successful HBM response must
    // be retained until the A13 error is acknowledged.
    @(negedge clk);
    pipeline_start_valid = 1'b1;
    @(posedge clk);
    @(negedge clk);
    pipeline_start_valid = 1'b0;
    wait (pipeline_error_valid === 1'b1);
    if (pipeline_error_code !== 8'h01)
      $fatal(1, "Expected A13 missing-embedding error, got %02h",
             pipeline_error_code);

    expected_slot0 = golden_hbm_row(37);
    start_lookup(ALIGNED_TABLE_BASE, 37, 2);
    wait (hbm_inject_pending === 1'b1);
    #1;
    held_pending_data = dut.hbm_inject_data_reg;
    if (held_pending_data !== expected_slot0)
      $fatal(1, "Pending HBM row-37 data mismatch");
    for (hold_cycle = 0; hold_cycle < 4; hold_cycle = hold_cycle + 1) begin
      @(posedge clk);
      #1;
      if (!hbm_inject_pending || hbm_inject_done ||
          dut.hbm_inject_data_reg !== held_pending_data)
        $fatal(1, "Pending HBM injection changed while A13 was not ready");
    end
    $display("A15_1_DELAYED_READY=PASS");

    acknowledge_pipeline_error();
    wait (hbm_inject_done === 1'b1);
    #1;
    if (hbm_inject_pending || embedding_loaded_mask !== 4'hF)
      $fatal(1, "Successful HBM injection did not complete mask=%b",
             embedding_loaded_mask);
    if (dut.u_a13_pipeline.u_canonical_pipeline.embedding_mem[0] !==
            expected_slot0)
      $fatal(1, "A13 slot0 did not retain HBM row 37");
    if (expected_slot0[15:0] !== 16'd40 ||
        expected_slot0[31:16] !== 16'd41 ||
        expected_slot0[47:32] !== 16'd42 ||
        expected_slot0[63:48] !== 16'd43 ||
        expected_slot0[79:64] !== 16'd44 ||
        expected_slot0[95:80] !== 16'd45 ||
        expected_slot0[111:96] !== 16'd46 ||
        expected_slot0[127:112] !== 16'd47)
      $fatal(1, "A15.1 128-bit lane order mismatch");
    $display("A15_1_HBM_SLOT0_INJECTION=PASS");
    $display("A15_1_LANE_ORDER=PASS");
    $display("A15_1_LOADED_MASK=PASS");

    // A busy second request is not accepted and cannot replace the first.
    count_before = lookup_handshake_count;
    expected_slot0 = golden_hbm_row(10);
    start_lookup(ALIGNED_TABLE_BASE, 10, 8);
    @(negedge clk);
    lookup_req_index = 32'd11;
    lookup_req_valid = 1'b1;
    for (hold_cycle = 0; hold_cycle < 3; hold_cycle = hold_cycle + 1) begin
      @(posedge clk);
      #1;
      if (lookup_req_ready)
        $fatal(1, "Busy lookup unexpectedly asserted ready");
    end
    @(negedge clk);
    lookup_req_valid = 1'b0;
    wait (hbm_inject_done === 1'b1);
    #1;
    if (lookup_handshake_count != count_before + 1)
      $fatal(1, "Busy request was incorrectly accepted");
    if (dut.u_a13_pipeline.u_canonical_pipeline.embedding_mem[0] !==
            expected_slot0)
      $fatal(1, "Busy request corrupted the first lookup response");
    $display("A15_1_BUSY_GUARD=PASS");

    // An error after a valid slot0 load must preserve both data and loaded bit.
    count_before = ar_handshake_count;
    start_lookup(ALIGNED_TABLE_BASE + 64'd8, 20, 0);
    wait (hbm_lookup_error_valid === 1'b1);
    #1;
    if (embedding_loaded_mask !== 4'hF || hbm_inject_pending ||
        ar_handshake_count != count_before ||
        dut.u_a13_pipeline.u_canonical_pipeline.embedding_mem[0] !==
            expected_slot0)
      $fatal(1, "Error after valid lookup corrupted slot0 state");
    $display("A15_1_LOOKUP_ERROR_GUARD=PASS");
    acknowledge_hbm_error();

    repeat (2) @(posedge clk);
    if (!pipeline_start_ready)
      $fatal(1, "A13 pipeline START did not become ready at mask 4'hF");
    if (bottom_cycle_count !== 0 || interaction_cycle_count !== 0 ||
        top_cycle_count !== 0 || total_cycle_count !== 0)
      $fatal(1, "A13 cycle counters changed without an accepted START");

    if (dut.u_a13_pipeline.u_canonical_pipeline.embedding_mem[1] !==
            slot1_pattern ||
        dut.u_a13_pipeline.u_canonical_pipeline.embedding_mem[2] !==
            slot2_pattern ||
        dut.u_a13_pipeline.u_canonical_pipeline.embedding_mem[3] !==
            slot3_pattern)
      $fatal(1, "Host slot1-3 changed during HBM activity");

    if (ar_handshake_count !== 2 || r_handshake_count !== 2)
      $fatal(1, "Expected two physical AXI reads, got AR=%0d R=%0d",
             ar_handshake_count, r_handshake_count);

    $display("A15_1_ACCEPTED_LOOKUPS=%0d", lookup_handshake_count);
    $display("A15_1_AXI_AR_HANDSHAKES=%0d", ar_handshake_count);
    $display("A15_1_AXI_R_HANDSHAKES=%0d", r_handshake_count);
    $display("STAGE2N_A15_1_HBM_PIPELINE_INTEGRATION_V1_PASS");
    $finish;
  end

endmodule
