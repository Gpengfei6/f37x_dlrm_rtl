`timescale 1ns/1ps

// Stage 2N-A15.2 local end-to-end substitution proof.
//
// This bench reuses the accepted A13 cycle-counter sample. The only input
// source change is embedding slot 0: the old Host-configured all-zero vector is
// returned as row 37 by the fake AXI memory and injected through A14 v2/A15.1.
module tb_dlrm_hbm_pipeline_integration_stage2n_a15_v2;

  localparam integer MAX_LAYERS = 8;
  localparam integer MAX_IN_DIM = 64;
  localparam integer MAX_OUT_DIM = 64;
  localparam integer NUM_PE = 16;
  localparam integer INPUT_WIDTH = 16;
  localparam integer OUTPUT_WIDTH = 16;
  localparam integer WEIGHT_ADDR_WIDTH = 32;
  localparam integer BIAS_ADDR_WIDTH = 32;
  localparam integer ACT_CHUNK_ADDR_WIDTH = 2;
  localparam integer LAYER_INDEX_WIDTH = 3;
  localparam integer LAYER_COUNT_WIDTH = 4;
  localparam integer HBM_ADDR_WIDTH = 64;
  localparam integer HBM_DATA_WIDTH = 128;
  localparam integer HBM_INDEX_WIDTH = 32;
  localparam logic [HBM_ADDR_WIDTH-1:0] TABLE_BASE =
      64'h0000_0001_0000_0000;
  localparam integer HBM_ROW = 37;

  localparam logic [11:0] A13_BOTTOM_CYCLES_ADDR = 12'h218;
  localparam logic [11:0] A13_INTERACTION_CYCLES_ADDR = 12'h21C;
  localparam logic [11:0] A13_TOP_CYCLES_ADDR = 12'h220;
  localparam logic [11:0] A13_TOTAL_CYCLES_ADDR = 12'h224;

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
  logic [WEIGHT_ADDR_WIDTH-1:0] weight_cfg_address;
  logic signed [7:0] weight_cfg_data;

  logic bias_cfg_valid;
  logic bias_cfg_ready;
  logic [BIAS_ADDR_WIDTH-1:0] bias_cfg_address;
  logic signed [23:0] bias_cfg_data;

  logic pipeline_start_valid;
  logic pipeline_start_ready;
  logic [LAYER_INDEX_WIDTH-1:0] bottom_descriptor_base;
  logic [LAYER_COUNT_WIDTH-1:0] bottom_layer_count;
  logic [LAYER_INDEX_WIDTH-1:0] top_descriptor_base;
  logic [LAYER_COUNT_WIDTH-1:0] top_layer_count;
  logic bottom_initial_buffer_select;
  logic top_input_buffer_select;
  logic [5:0] interaction_shift;

  logic result_valid;
  logic result_ready;
  logic signed [OUTPUT_WIDTH-1:0] result_data;
  logic [5:0] result_index;
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
  integer memory_delay;
  integer ar_handshake_count;
  integer r_handshake_count;
  integer timeout_cycles;
  integer address_index;
  integer monitor_index;
  integer golden_result;
  integer controller_overhead;
  logic [4:0] interaction_vector_seen;
  logic [127:0] interaction_vectors [0:4];
  logic signed [15:0] held_result;
  logic [5:0] held_result_index;
  logic held_result_last;
  logic [7:0] held_result_tag;
  logic [31:0] held_bottom_cycles;
  logic [31:0] held_interaction_cycles;
  logic [31:0] held_top_cycles;
  logic [31:0] held_total_cycles;

  always #5 clk = ~clk;

  function automatic logic [95:0] pack_descriptor(
    input integer in_dim,
    input integer out_dim,
    input integer weight_base,
    input integer bias_base,
    input integer output_shift,
    input integer relu_enable
  );
    logic [95:0] value;
    begin
      value = '0;
      value[0 +: 11] = in_dim[10:0];
      value[11 +: 11] = out_dim[10:0];
      value[22 +: 32] = weight_base[31:0];
      value[54 +: 32] = bias_base[31:0];
      value[86 +: 6] = output_shift[5:0];
      value[92] = relu_enable[0];
      pack_descriptor = value;
    end
  endfunction

  function automatic logic [127:0] pack_vector8(
    input integer v0,
    input integer v1,
    input integer v2,
    input integer v3,
    input integer v4,
    input integer v5,
    input integer v6,
    input integer v7
  );
    logic signed [15:0] lane [0:7];
    logic [127:0] value;
    integer index;
    begin
      lane[0] = v0;
      lane[1] = v1;
      lane[2] = v2;
      lane[3] = v3;
      lane[4] = v4;
      lane[5] = v5;
      lane[6] = v6;
      lane[7] = v7;
      value = '0;
      for (index = 0; index < 8; index = index + 1)
        value[index*16 +: 16] = lane[index];
      pack_vector8 = value;
    end
  endfunction

  function automatic integer accepted_software_golden;
    integer value;
    integer index;
    begin
      // The accepted A13 sample copies dense lanes 1..8 through Bottom,
      // preserves them as the first eight Interaction outputs because every
      // embedding is zero, copies them through two Top layers, then sums them.
      value = 0;
      for (index = 1; index <= 8; index = index + 1)
        value = value + index;
      accepted_software_golden = value;
    end
  endfunction

  task automatic load_descriptor(
    input integer index,
    input logic [95:0] value
  );
    integer wait_cycles;
    begin
      @(negedge clk);
      descriptor_cfg_index = index[LAYER_INDEX_WIDTH-1:0];
      descriptor_cfg_data = value;
      descriptor_cfg_valid = 1'b1;
      wait_cycles = 0;
      while (!descriptor_cfg_ready && wait_cycles < 200) begin
        @(posedge clk);
        wait_cycles = wait_cycles + 1;
      end
      if (!descriptor_cfg_ready)
        $fatal(1, "descriptor %0d configuration timeout", index);
      @(negedge clk);
      descriptor_cfg_valid = 1'b0;
    end
  endtask

  task automatic load_weight(input integer address, input integer value);
    integer wait_cycles;
    begin
      @(negedge clk);
      weight_cfg_address = address[WEIGHT_ADDR_WIDTH-1:0];
      weight_cfg_data = value;
      weight_cfg_valid = 1'b1;
      wait_cycles = 0;
      while (!weight_cfg_ready && wait_cycles < 200) begin
        @(posedge clk);
        wait_cycles = wait_cycles + 1;
      end
      if (!weight_cfg_ready)
        $fatal(1, "weight %0d configuration timeout", address);
      @(negedge clk);
      weight_cfg_valid = 1'b0;
    end
  endtask

  task automatic load_bias(input integer address, input integer value);
    integer wait_cycles;
    begin
      @(negedge clk);
      bias_cfg_address = address[BIAS_ADDR_WIDTH-1:0];
      bias_cfg_data = value;
      bias_cfg_valid = 1'b1;
      wait_cycles = 0;
      while (!bias_cfg_ready && wait_cycles < 200) begin
        @(posedge clk);
        wait_cycles = wait_cycles + 1;
      end
      if (!bias_cfg_ready)
        $fatal(1, "bias %0d configuration timeout", address);
      @(negedge clk);
      bias_cfg_valid = 1'b0;
    end
  endtask

  task automatic load_bottom_input;
    integer wait_cycles;
    integer index;
    begin
      @(negedge clk);
      act_load_buffer_select = 1'b0;
      act_load_chunk_index = '0;
      act_load_lane_mask = 16'h00FF;
      act_load_data = '0;
      for (index = 0; index < 8; index = index + 1)
        act_load_data[index*16 +: 16] = index + 1;
      act_load_valid = 1'b1;
      wait_cycles = 0;
      while (!act_load_ready && wait_cycles < 200) begin
        @(posedge clk);
        wait_cycles = wait_cycles + 1;
      end
      if (!act_load_ready)
        $fatal(1, "bottom input configuration timeout");
      @(negedge clk);
      act_load_valid = 1'b0;
    end
  endtask

  task automatic load_host_embedding(input integer index);
    integer wait_cycles;
    begin
      @(negedge clk);
      host_embedding_cfg_index = index[1:0];
      host_embedding_cfg_data = '0;
      host_embedding_cfg_valid = 1'b1;
      wait_cycles = 0;
      while (!host_embedding_cfg_ready && wait_cycles < 200) begin
        @(posedge clk);
        wait_cycles = wait_cycles + 1;
      end
      if (!host_embedding_cfg_ready)
        $fatal(1, "Host embedding %0d configuration timeout", index);
      @(negedge clk);
      host_embedding_cfg_valid = 1'b0;
    end
  endtask

  task automatic request_hbm_slot0;
    integer wait_cycles;
    begin
      @(negedge clk);
      lookup_req_index = HBM_ROW;
      lookup_req_valid = 1'b1;
      wait_cycles = 0;
      while (!lookup_req_ready && wait_cycles < 200) begin
        @(posedge clk);
        wait_cycles = wait_cycles + 1;
      end
      if (!lookup_req_ready)
        $fatal(1, "HBM lookup request timeout");
      @(negedge clk);
      lookup_req_valid = 1'b0;
      wait_cycles = 0;
      while (!hbm_inject_done && wait_cycles < 200) begin
        @(posedge clk);
        wait_cycles = wait_cycles + 1;
      end
      if (!hbm_inject_done)
        $fatal(1, "HBM slot0 injection timeout");
      #1;
    end
  endtask

  task automatic start_pipeline;
    integer wait_cycles;
    begin
      @(negedge clk);
      bottom_descriptor_base = 0;
      bottom_layer_count = 2;
      top_descriptor_base = 2;
      top_layer_count = 3;
      bottom_initial_buffer_select = 1'b0;
      top_input_buffer_select = 1'b0;
      interaction_shift = 0;
      pipeline_start_valid = 1'b1;
      wait_cycles = 0;
      while (!pipeline_start_ready && wait_cycles < 200) begin
        @(posedge clk);
        wait_cycles = wait_cycles + 1;
      end
      if (!pipeline_start_ready)
        $fatal(1, "pipeline START timeout mask=%h", embedding_loaded_mask);
      @(negedge clk);
      pipeline_start_valid = 1'b0;
    end
  endtask

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

  assign m_axi_arready = !memory_pending && !m_axi_rvalid;
  assign m_axi_rid = 1'b0;
  assign m_axi_rresp = 2'b00;
  assign m_axi_rlast = 1'b1;

  // One-row fake AXI memory. Row 37 is deliberately all-zero so it is
  // bit-identical to slot0 in the accepted A13 sample.
  always_ff @(posedge clk) begin
    if (rst) begin
      memory_pending <= 1'b0;
      memory_delay <= 0;
      m_axi_rdata <= '0;
      m_axi_rvalid <= 1'b0;
      ar_handshake_count <= 0;
      r_handshake_count <= 0;
    end else begin
      if (m_axi_arvalid && m_axi_arready) begin
        if (m_axi_araddr !== TABLE_BASE + (HBM_ROW << 4))
          $fatal(1, "HBM address mismatch actual=%h expected=%h",
                 m_axi_araddr, TABLE_BASE + (HBM_ROW << 4));
        if (m_axi_arlen !== 8'd0 || m_axi_arsize !== 3'd4 ||
            m_axi_arburst !== 2'b01)
          $fatal(1, "HBM AXI single-beat attributes mismatch");
        memory_pending <= 1'b1;
        memory_delay <= 2;
        ar_handshake_count <= ar_handshake_count + 1;
      end

      if (memory_pending) begin
        if (memory_delay != 0)
          memory_delay <= memory_delay - 1;
        else if (!m_axi_rvalid) begin
          m_axi_rdata <= '0;
          m_axi_rvalid <= 1'b1;
          memory_pending <= 1'b0;
        end
      end

      if (m_axi_rvalid && m_axi_rready) begin
        m_axi_rvalid <= 1'b0;
        r_handshake_count <= r_handshake_count + 1;
      end
    end
  end

  // Observe the accepted A13 controller's real Feature Interaction load port.
  // This proves the HBM-owned slot is consumed as vector1 rather than bypassed
  // directly into the Top MLP.
  always_ff @(posedge clk) begin
    if (rst) begin
      interaction_vector_seen <= '0;
      for (monitor_index = 0; monitor_index < 5;
           monitor_index = monitor_index + 1)
        interaction_vectors[monitor_index] <= '0;
    end else if (
        dut.u_a13_pipeline.u_canonical_pipeline.interaction_vector_load_valid &&
        dut.u_a13_pipeline.u_canonical_pipeline.interaction_vector_load_ready) begin
      interaction_vector_seen[
          dut.u_a13_pipeline.u_canonical_pipeline.interaction_vector_load_index
      ] <= 1'b1;
      interaction_vectors[
          dut.u_a13_pipeline.u_canonical_pipeline.interaction_vector_load_index
      ] <= dut.u_a13_pipeline.u_canonical_pipeline.interaction_vector_load_data;
    end
  end

  always_ff @(posedge clk) begin
    if (rst)
      timeout_cycles <= 0;
    else begin
      timeout_cycles <= timeout_cycles + 1;
      if (timeout_cycles > 200000)
        $fatal(1, "A15.2 end-to-end test timeout");
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
    host_embedding_cfg_index = '0;
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
    table_base_addr = TABLE_BASE;
    lookup_req_valid = 1'b0;
    lookup_req_index = '0;
    hbm_lookup_error_ready = 1'b0;

    golden_result = accepted_software_golden();
    if (golden_result != 36)
      $fatal(1, "independent accepted-sample golden mismatch: %0d",
             golden_result);

    repeat (8) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;
    repeat (4) @(posedge clk);

    if ((A13_BOTTOM_CYCLES_ADDR !== 12'h218) ||
        (A13_INTERACTION_CYCLES_ADDR !== 12'h21C) ||
        (A13_TOP_CYCLES_ADDR !== 12'h220) ||
        (A13_TOTAL_CYCLES_ADDR !== 12'h224))
      $fatal(1, "A13 counter ABI localparam guard failed");
    $display("A15_2_A13_ABI_PRESERVED=PASS");

    // Accepted A13 descriptors: Bottom 8->16->8, Top 18->32->16->1.
    load_descriptor(0, pack_descriptor(8, 16, 0, 0, 0, 1));
    load_descriptor(1, pack_descriptor(16, 8, 128, 16, 0, 1));
    load_descriptor(2, pack_descriptor(18, 32, 256, 24, 0, 1));
    load_descriptor(3, pack_descriptor(32, 16, 832, 56, 0, 1));
    load_descriptor(4, pack_descriptor(16, 1, 1344, 72, 0, 0));

    for (address_index = 0; address_index < 1360;
         address_index = address_index + 1)
      load_weight(address_index, 0);
    for (address_index = 0; address_index < 8;
         address_index = address_index + 1)
      load_weight(address_index * 9, 1);
    for (address_index = 0; address_index < 8;
         address_index = address_index + 1)
      load_weight(128 + address_index * 17, 1);
    for (address_index = 0; address_index < 8;
         address_index = address_index + 1)
      load_weight(256 + address_index * 19, 1);
    for (address_index = 0; address_index < 8;
         address_index = address_index + 1)
      load_weight(832 + address_index * 33, 1);
    for (address_index = 0; address_index < 8;
         address_index = address_index + 1)
      load_weight(1344 + address_index, 1);

    for (address_index = 0; address_index < 73;
         address_index = address_index + 1)
      load_bias(address_index, 0);

    load_bottom_input();
    load_host_embedding(1);
    load_host_embedding(2);
    load_host_embedding(3);

    if (embedding_loaded_mask !== 4'b1110)
      $fatal(1, "Host slot1-3 mask mismatch: %h", embedding_loaded_mask);
    if (pipeline_start_ready)
      $fatal(1, "pipeline START ready before HBM slot0 injection");

    request_hbm_slot0();
    if (ar_handshake_count !== 1 || r_handshake_count !== 1)
      $fatal(1, "HBM handshake count mismatch AR=%0d R=%0d",
             ar_handshake_count, r_handshake_count);
    if (hbm_lookup_error_valid)
      $fatal(1, "unexpected HBM lookup error index=%0d",
             hbm_lookup_error_index);
    if (dut.u_a13_pipeline.u_canonical_pipeline.embedding_mem[0] !== 128'd0)
      $fatal(1, "HBM slot0 data mismatch");
    $display("A15_2_HBM_LOOKUP=PASS");
    $display("A15_2_SLOT0_INJECTION=PASS");

    if (embedding_loaded_mask !== 4'hF || !pipeline_start_ready)
      $fatal(1, "pipeline not ready after all embeddings mask=%h ready=%b",
             embedding_loaded_mask, pipeline_start_ready);
    $display("A15_2_EMBEDDING_MASK=PASS");

    start_pipeline();

    while (!result_valid) begin
      @(posedge clk);
      if (pipeline_error_valid)
        $fatal(1, "pipeline error before result code=%02h phase=%0d",
               pipeline_error_code, phase);
    end
    #1;

    held_result = result_data;
    held_result_index = result_index;
    held_result_last = result_last;
    held_result_tag = result_tag;
    held_bottom_cycles = bottom_cycle_count;
    held_interaction_cycles = interaction_cycle_count;
    held_top_cycles = top_cycle_count;
    held_total_cycles = total_cycle_count;

    if (held_result !== golden_result)
      $fatal(1, "final result mismatch actual=%0d expected=%0d",
             held_result, golden_result);
    if (held_result_index !== 0 || !held_result_last || held_result_tag !== 8'd4)
      $fatal(1, "final metadata mismatch index=%0d last=%b tag=%0d",
             held_result_index, held_result_last, held_result_tag);
    if (bottom_result_count !== 4'd8 || interaction_result_count !== 5'd18)
      $fatal(1, "phase output counts mismatch bottom=%0d interaction=%0d",
             bottom_result_count, interaction_result_count);

    if (interaction_vector_seen !== 5'b11111)
      $fatal(1, "not all Interaction vectors were loaded: %b",
             interaction_vector_seen);
    if (interaction_vectors[0] !== pack_vector8(1,2,3,4,5,6,7,8))
      $fatal(1, "Interaction vector0 is not the Bottom output");
    for (address_index = 1; address_index < 5;
         address_index = address_index + 1) begin
      if (interaction_vectors[address_index] !== 128'd0)
        $fatal(1, "Interaction embedding vector%0d mismatch",
               address_index);
    end

    if ((held_bottom_cycles == 0) || (held_interaction_cycles == 0) ||
        (held_top_cycles == 0) || (held_total_cycles == 0))
      $fatal(1, "zero cycle counter B=%0d I=%0d T=%0d Total=%0d",
             held_bottom_cycles, held_interaction_cycles,
             held_top_cycles, held_total_cycles);
    if (held_total_cycles < held_bottom_cycles + held_interaction_cycles +
        held_top_cycles)
      $fatal(1, "total counter does not cover ordered stages");
    controller_overhead = held_total_cycles - held_bottom_cycles -
                          held_interaction_cycles - held_top_cycles;
    if ((held_bottom_cycles !== 32'd322) ||
        (held_interaction_cycles !== 32'd100) ||
        (held_top_cycles !== 32'd744) ||
        (held_total_cycles !== 32'd1174) ||
        (controller_overhead != 8))
      $fatal(1, "accepted A13 cycle mismatch B=%0d I=%0d T=%0d Total=%0d O=%0d",
             held_bottom_cycles, held_interaction_cycles,
             held_top_cycles, held_total_cycles, controller_overhead);

    $display("A15_2_BOTTOM_MLP=PASS");
    $display("A15_2_INTERACTION=PASS");
    $display("A15_2_TOP_MLP=PASS");
    $display("A15_2_FINAL_RESULT_MATCH=PASS");
    $display("A15_2_CYCLE_COUNTERS=PASS");

    repeat (8) begin
      @(posedge clk);
      #1;
      if (!result_valid || result_data !== held_result ||
          result_index !== held_result_index || result_last !== held_result_last ||
          result_tag !== held_result_tag)
        $fatal(1, "final result changed under backpressure");
      if ((bottom_cycle_count !== held_bottom_cycles) ||
          (interaction_cycle_count !== held_interaction_cycles) ||
          (top_cycle_count !== held_top_cycles) ||
          (total_cycle_count !== held_total_cycles))
        $fatal(1, "cycle counters changed under final-result backpressure");
    end

    @(negedge clk);
    result_ready = 1'b1;
    @(posedge clk);
    @(negedge clk);
    result_ready = 1'b0;

    while (!done) begin
      @(posedge clk);
      if (pipeline_error_valid)
        $fatal(1, "pipeline error after result code=%02h", pipeline_error_code);
    end
    #1;

    if (embedding_loaded_mask !== 4'hF ||
        dut.u_a13_pipeline.u_canonical_pipeline.embedding_mem[0] !== 128'd0 ||
        dut.u_a13_pipeline.u_canonical_pipeline.embedding_mem[1] !== 128'd0 ||
        dut.u_a13_pipeline.u_canonical_pipeline.embedding_mem[2] !== 128'd0 ||
        dut.u_a13_pipeline.u_canonical_pipeline.embedding_mem[3] !== 128'd0)
      $fatal(1, "embedding state changed after inference");
    $display("A15_2_HOST_SLOT123_PRESERVED=PASS");

    $display("HBM_ROW=%0d", HBM_ROW);
    $display("SLOT0_VALUE=[0,0,0,0,0,0,0,0]");
    $display("SLOT1_VALUE=[0,0,0,0,0,0,0,0]");
    $display("SLOT2_VALUE=[0,0,0,0,0,0,0,0]");
    $display("SLOT3_VALUE=[0,0,0,0,0,0,0,0]");
    $display("EXPECTED_RESULT=%0d", golden_result);
    $display("FINAL_RESULT=%0d", held_result);
    $display("BOTTOM_CYCLES=%0d", held_bottom_cycles);
    $display("INTERACTION_CYCLES=%0d", held_interaction_cycles);
    $display("TOP_CYCLES=%0d", held_top_cycles);
    $display("TOTAL_CYCLES=%0d", held_total_cycles);
    $display("CONTROLLER_OVERHEAD_CYCLES=%0d", controller_overhead);
    $display("STAGE2N_A15_2_END_TO_END_PIPELINE_XSIM_V1_PASS");
    $finish;
  end

endmodule
