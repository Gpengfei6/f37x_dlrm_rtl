`timescale 1ns/1ps

// Stage 2N-A15.3 local sequential four-row HBM integration proof.
// The fake AXI memory is independent of the accepted A14 lookup RTL. The
// accepted A13 test network is configured exactly as in A15.2, while all four
// embedding slots are populated from canonical A14 rows 37 through 40.
module tb_dlrm_hbm_pipeline_integration_stage2n_a15_v3;

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
  localparam integer SLOT0_LOOKUP_INDEX = 37;
  localparam integer SLOT1_LOOKUP_INDEX = 38;
  localparam integer SLOT2_LOOKUP_INDEX = 39;
  localparam integer SLOT3_LOOKUP_INDEX = 40;

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
  logic load_all_req_valid;
  logic load_all_req_ready;
  logic hbm_sequence_busy;
  logic hbm_all_loaded;
  logic hbm_sequence_done;
  logic hbm_inject_pending;
  logic [1:0] hbm_inject_slot;
  logic [127:0] hbm_inject_data;
  logic hbm_inject_done;
  logic hbm_sequence_error_valid;
  logic hbm_sequence_error_ready;
  logic [1:0] hbm_sequence_error_slot;
  logic [31:0] hbm_sequence_error_index;

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

  logic fake_arready_enable;
  logic fake_memory_pending;
  integer fake_memory_delay;
  integer fake_response_delay;
  integer fake_pending_row;
  logic fake_error_enable;
  integer fake_error_row;

  integer logical_lookup_request_count;
  integer load_all_accept_count;
  integer ar_handshake_count;
  integer r_handshake_count;
  integer successful_injection_count;
  integer mask_transition_count;
  logic [3:0] previous_loaded_mask;
  logic sequence_done_seen;
  integer timeout_cycles;

  logic [4:0] interaction_vector_seen;
  logic [127:0] interaction_input_vectors [0:4];
  integer expected_interaction [0:17];
  integer golden_result;
  integer controller_overhead;
  integer slot_index;
  integer interaction_monitor_index;
  integer lane_index;
  integer pair_row_index;
  integer pair_column_index;
  integer pair_output_index;
  integer dot_accumulator;
  integer address_index;
  integer wait_cycles;

  logic signed [15:0] held_result;
  logic [5:0] held_result_index;
  logic held_result_last;
  logic [7:0] held_result_tag;
  logic [31:0] held_bottom_cycles;
  logic [31:0] held_interaction_cycles;
  logic [31:0] held_top_cycles;
  logic [31:0] held_total_cycles;
  logic [127:0] held_inject_data;
  logic [1:0] held_inject_slot;
  logic [63:0] held_araddr;

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

  function automatic integer canonical_lane(
    input integer row,
    input integer lane
  );
    begin
      canonical_lane = row * 8 + lane - 256;
    end
  endfunction

  function automatic logic [127:0] canonical_row(input integer row);
    logic [127:0] value;
    logic signed [15:0] lane_value;
    integer lane;
    begin
      value = '0;
      for (lane = 0; lane < 8; lane = lane + 1) begin
        lane_value = canonical_lane(row, lane);
        value[lane*16 +: 16] = lane_value;
      end
      canonical_row = value;
    end
  endfunction

  function automatic integer source_lane(
    input integer vector_index,
    input integer lane
  );
    begin
      if (vector_index == 0)
        source_lane = lane + 1;
      else
        source_lane = canonical_lane(36 + vector_index, lane);
    end
  endfunction

  function automatic integer saturate_int16(input integer value);
    begin
      if (value > 32767)
        saturate_int16 = 32767;
      else if (value < -32768)
        saturate_int16 = -32768;
      else
        saturate_int16 = value;
    end
  endfunction

  task automatic build_independent_golden;
    begin
      for (lane_index = 0; lane_index < 8; lane_index = lane_index + 1)
        expected_interaction[lane_index] = lane_index + 1;

      pair_output_index = 8;
      for (pair_row_index = 1; pair_row_index < 5;
           pair_row_index = pair_row_index + 1) begin
        for (pair_column_index = 0;
             pair_column_index < pair_row_index;
             pair_column_index = pair_column_index + 1) begin
          dot_accumulator = 0;
          for (lane_index = 0; lane_index < 8;
               lane_index = lane_index + 1) begin
            dot_accumulator = dot_accumulator +
                source_lane(pair_row_index, lane_index) *
                source_lane(pair_column_index, lane_index);
          end
          expected_interaction[pair_output_index] =
              saturate_int16(dot_accumulator);
          pair_output_index = pair_output_index + 1;
        end
      end

      // The accepted sparse Top configuration copies Interaction outputs 0..7
      // through two layers and sums those eight lanes in its final layer.
      golden_result = 0;
      for (lane_index = 0; lane_index < 8; lane_index = lane_index + 1)
        golden_result = golden_result + expected_interaction[lane_index];
    end
  endtask

  task automatic perform_reset;
    begin
      @(negedge clk);
      rst = 1'b1;
      repeat (6) @(posedge clk);
      @(negedge clk);
      rst = 1'b0;
      repeat (4) @(posedge clk);
    end
  endtask

  task automatic load_descriptor(
    input integer index,
    input logic [95:0] value
  );
    integer cycles;
    begin
      @(negedge clk);
      descriptor_cfg_index = index[LAYER_INDEX_WIDTH-1:0];
      descriptor_cfg_data = value;
      descriptor_cfg_valid = 1'b1;
      cycles = 0;
      while (!descriptor_cfg_ready && cycles < 200) begin
        @(posedge clk);
        cycles = cycles + 1;
      end
      if (!descriptor_cfg_ready)
        $fatal(1, "descriptor %0d configuration timeout", index);
      @(negedge clk);
      descriptor_cfg_valid = 1'b0;
    end
  endtask

  task automatic load_weight(input integer address, input integer value);
    integer cycles;
    begin
      @(negedge clk);
      weight_cfg_address = address[WEIGHT_ADDR_WIDTH-1:0];
      weight_cfg_data = value;
      weight_cfg_valid = 1'b1;
      cycles = 0;
      while (!weight_cfg_ready && cycles < 200) begin
        @(posedge clk);
        cycles = cycles + 1;
      end
      if (!weight_cfg_ready)
        $fatal(1, "weight %0d configuration timeout", address);
      @(negedge clk);
      weight_cfg_valid = 1'b0;
    end
  endtask

  task automatic load_bias(input integer address, input integer value);
    integer cycles;
    begin
      @(negedge clk);
      bias_cfg_address = address[BIAS_ADDR_WIDTH-1:0];
      bias_cfg_data = value;
      bias_cfg_valid = 1'b1;
      cycles = 0;
      while (!bias_cfg_ready && cycles < 200) begin
        @(posedge clk);
        cycles = cycles + 1;
      end
      if (!bias_cfg_ready)
        $fatal(1, "bias %0d configuration timeout", address);
      @(negedge clk);
      bias_cfg_valid = 1'b0;
    end
  endtask

  task automatic load_bottom_input;
    integer cycles;
    integer lane;
    begin
      @(negedge clk);
      act_load_buffer_select = 1'b0;
      act_load_chunk_index = '0;
      act_load_lane_mask = 16'h00FF;
      act_load_data = '0;
      for (lane = 0; lane < 8; lane = lane + 1)
        act_load_data[lane*16 +: 16] = lane + 1;
      act_load_valid = 1'b1;
      cycles = 0;
      while (!act_load_ready && cycles < 200) begin
        @(posedge clk);
        cycles = cycles + 1;
      end
      if (!act_load_ready)
        $fatal(1, "bottom input configuration timeout");
      @(negedge clk);
      act_load_valid = 1'b0;
    end
  endtask

  task automatic configure_accepted_pipeline_sample;
    integer address;
    begin
      load_descriptor(0, pack_descriptor(8, 16, 0, 0, 0, 1));
      load_descriptor(1, pack_descriptor(16, 8, 128, 16, 0, 1));
      load_descriptor(2, pack_descriptor(18, 32, 256, 24, 0, 1));
      load_descriptor(3, pack_descriptor(32, 16, 832, 56, 0, 1));
      load_descriptor(4, pack_descriptor(16, 1, 1344, 72, 0, 0));

      for (address = 0; address < 1360; address = address + 1)
        load_weight(address, 0);
      for (address = 0; address < 8; address = address + 1)
        load_weight(address * 9, 1);
      for (address = 0; address < 8; address = address + 1)
        load_weight(128 + address * 17, 1);
      for (address = 0; address < 8; address = address + 1)
        load_weight(256 + address * 19, 1);
      for (address = 0; address < 8; address = address + 1)
        load_weight(832 + address * 33, 1);
      for (address = 0; address < 8; address = address + 1)
        load_weight(1344 + address, 1);

      for (address = 0; address < 73; address = address + 1)
        load_bias(address, 0);
      load_bottom_input();
    end
  endtask

  task automatic pulse_load_all;
    integer cycles;
    begin
      @(negedge clk);
      load_all_req_valid = 1'b1;
      cycles = 0;
      while (!load_all_req_ready && cycles < 200) begin
        @(posedge clk);
        cycles = cycles + 1;
      end
      if (!load_all_req_ready)
        $fatal(1, "load-all request timeout");
      @(negedge clk);
      load_all_req_valid = 1'b0;
    end
  endtask

  task automatic host_embedding_write_attempt(input integer slot);
    begin
      @(negedge clk);
      host_embedding_cfg_index = slot[1:0];
      host_embedding_cfg_data = canonical_row(10 + slot);
      host_embedding_cfg_valid = 1'b1;
      @(posedge clk);
      #1;
      if (!host_embedding_cfg_ready || !host_embedding_cfg_rejected)
        $fatal(1, "Host embedding slot%0d write was not rejected", slot);
      @(negedge clk);
      host_embedding_cfg_valid = 1'b0;
    end
  endtask

  task automatic acknowledge_sequence_error;
    begin
      @(negedge clk);
      hbm_sequence_error_ready = 1'b1;
      @(posedge clk);
      @(negedge clk);
      hbm_sequence_error_ready = 1'b0;
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

  task automatic trigger_missing_embedding_start;
    begin
      @(negedge clk);
      pipeline_start_valid = 1'b1;
      @(posedge clk);
      @(negedge clk);
      pipeline_start_valid = 1'b0;
      wait_cycles = 0;
      while (!pipeline_error_valid && wait_cycles < 200) begin
        @(posedge clk);
        wait_cycles = wait_cycles + 1;
      end
      if (!pipeline_error_valid || pipeline_error_code !== 8'h01)
        $fatal(1, "missing-embedding START guard did not report A13 error");
      if (result_valid || (total_cycle_count != 0))
        $fatal(1, "pipeline ran before all embeddings were loaded");
    end
  endtask

  task automatic start_pipeline;
    integer cycles;
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
      cycles = 0;
      while (!pipeline_start_ready && cycles < 200) begin
        @(posedge clk);
        cycles = cycles + 1;
      end
      if (!pipeline_start_ready)
        $fatal(1, "pipeline START timeout mask=%h", embedding_loaded_mask);
      @(negedge clk);
      pipeline_start_valid = 1'b0;
    end
  endtask

  dlrm_hbm_pipeline_integration_stage2n_a15_v2 #(
    .SLOT0_LOOKUP_INDEX(SLOT0_LOOKUP_INDEX),
    .SLOT1_LOOKUP_INDEX(SLOT1_LOOKUP_INDEX),
    .SLOT2_LOOKUP_INDEX(SLOT2_LOOKUP_INDEX),
    .SLOT3_LOOKUP_INDEX(SLOT3_LOOKUP_INDEX)
  ) dut (
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
    .load_all_req_valid(load_all_req_valid),
    .load_all_req_ready(load_all_req_ready),
    .hbm_sequence_busy(hbm_sequence_busy),
    .hbm_all_loaded(hbm_all_loaded),
    .hbm_sequence_done(hbm_sequence_done),
    .hbm_inject_pending(hbm_inject_pending),
    .hbm_inject_slot(hbm_inject_slot),
    .hbm_inject_data(hbm_inject_data),
    .hbm_inject_done(hbm_inject_done),
    .hbm_sequence_error_valid(hbm_sequence_error_valid),
    .hbm_sequence_error_ready(hbm_sequence_error_ready),
    .hbm_sequence_error_slot(hbm_sequence_error_slot),
    .hbm_sequence_error_index(hbm_sequence_error_index),
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

  assign m_axi_arready =
      fake_arready_enable && !fake_memory_pending && !m_axi_rvalid;
  assign m_axi_rid = 1'b0;
  assign m_axi_rlast = 1'b1;

  always_ff @(posedge clk) begin
    if (rst) begin
      fake_memory_pending <= 1'b0;
      fake_memory_delay <= 0;
      fake_pending_row <= 0;
      m_axi_rdata <= '0;
      m_axi_rresp <= 2'b00;
      m_axi_rvalid <= 1'b0;
      ar_handshake_count <= 0;
      r_handshake_count <= 0;
    end else begin
      if (m_axi_arvalid && m_axi_arready) begin
        if (m_axi_araddr < TABLE_BASE)
          $fatal(1, "AXI AR address below table base");
        fake_pending_row <= (m_axi_araddr - TABLE_BASE) >> 4;
        if (m_axi_araddr !==
            TABLE_BASE + ((SLOT0_LOOKUP_INDEX + ar_handshake_count) << 4))
          $fatal(1, "AXI AR sequence mismatch count=%0d addr=%h",
                 ar_handshake_count, m_axi_araddr);
        if ((m_axi_arlen !== 8'd0) || (m_axi_arsize !== 3'd4) ||
            (m_axi_arburst !== 2'b01))
          $fatal(1, "AXI single-beat attributes mismatch");
        fake_memory_pending <= 1'b1;
        fake_memory_delay <= fake_response_delay;
        ar_handshake_count <= ar_handshake_count + 1;
      end

      if (fake_memory_pending) begin
        if (fake_memory_delay != 0)
          fake_memory_delay <= fake_memory_delay - 1;
        else if (!m_axi_rvalid) begin
          m_axi_rdata <= canonical_row(fake_pending_row);
          if (fake_error_enable && (fake_pending_row == fake_error_row))
            m_axi_rresp <= 2'b10;
          else
            m_axi_rresp <= 2'b00;
          m_axi_rvalid <= 1'b1;
          fake_memory_pending <= 1'b0;
        end
      end

      if (m_axi_rvalid && m_axi_rready) begin
        m_axi_rvalid <= 1'b0;
        m_axi_rresp <= 2'b00;
        r_handshake_count <= r_handshake_count + 1;
      end
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      logical_lookup_request_count <= 0;
      load_all_accept_count <= 0;
      successful_injection_count <= 0;
      sequence_done_seen <= 1'b0;
    end else begin
      if (dut.a14_lookup_req_valid && dut.a14_lookup_req_ready)
        logical_lookup_request_count <= logical_lookup_request_count + 1;
      if (load_all_req_valid && load_all_req_ready)
        load_all_accept_count <= load_all_accept_count + 1;
      if (dut.a13_embedding_cfg_valid && dut.a13_embedding_cfg_ready)
        successful_injection_count <= successful_injection_count + 1;
      if (hbm_sequence_done)
        sequence_done_seen <= 1'b1;
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      previous_loaded_mask <= 4'h0;
      mask_transition_count <= 0;
    end else if (embedding_loaded_mask != previous_loaded_mask) begin
      case (mask_transition_count)
        0: if (embedding_loaded_mask !== 4'h1)
             $fatal(1, "first loaded-mask transition was %h",
                    embedding_loaded_mask);
        1: if (embedding_loaded_mask !== 4'h3)
             $fatal(1, "second loaded-mask transition was %h",
                    embedding_loaded_mask);
        2: if (embedding_loaded_mask !== 4'h7)
             $fatal(1, "third loaded-mask transition was %h",
                    embedding_loaded_mask);
        3: if (embedding_loaded_mask !== 4'hF)
             $fatal(1, "fourth loaded-mask transition was %h",
                    embedding_loaded_mask);
        default: $fatal(1, "unexpected loaded-mask transition to %h",
                        embedding_loaded_mask);
      endcase
      previous_loaded_mask <= embedding_loaded_mask;
      mask_transition_count <= mask_transition_count + 1;
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      interaction_vector_seen <= '0;
      for (interaction_monitor_index = 0;
           interaction_monitor_index < 5;
           interaction_monitor_index = interaction_monitor_index + 1)
        interaction_input_vectors[interaction_monitor_index] <= '0;
    end else if (
        dut.u_a13_pipeline.u_canonical_pipeline.interaction_vector_load_valid &&
        dut.u_a13_pipeline.u_canonical_pipeline.interaction_vector_load_ready) begin
      interaction_vector_seen[
          dut.u_a13_pipeline.u_canonical_pipeline.interaction_vector_load_index
      ] <= 1'b1;
      interaction_input_vectors[
          dut.u_a13_pipeline.u_canonical_pipeline.interaction_vector_load_index
      ] <= dut.u_a13_pipeline.u_canonical_pipeline.interaction_vector_load_data;
    end
  end

  always_ff @(posedge clk) begin
    if (rst)
      timeout_cycles <= 0;
    else begin
      timeout_cycles <= timeout_cycles + 1;
      if (timeout_cycles > 250000)
        $fatal(1, "A15.3 end-to-end test timeout");
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
    load_all_req_valid = 1'b0;
    hbm_sequence_error_ready = 1'b0;
    fake_arready_enable = 1'b1;
    fake_response_delay = 2;
    fake_error_enable = 1'b0;
    fake_error_row = -1;

    build_independent_golden();
    if (golden_result != 36)
      $fatal(1, "independent A15.3 golden mismatch: %0d", golden_result);
    if ((expected_interaction[8] != 1608) ||
        (expected_interaction[9] != 1896) ||
        (expected_interaction[10] != 17964) ||
        (expected_interaction[11] != 2184) ||
        (expected_interaction[12] != 20748) ||
        (expected_interaction[13] != 24556) ||
        (expected_interaction[14] != 2472) ||
        (expected_interaction[15] != 23532) ||
        (expected_interaction[16] != 27852) ||
        (expected_interaction[17] != 32172))
      $fatal(1, "independent Feature Interaction golden mismatch");

    if ((A13_BOTTOM_CYCLES_ADDR !== 12'h218) ||
        (A13_INTERACTION_CYCLES_ADDR !== 12'h21C) ||
        (A13_TOP_CYCLES_ADDR !== 12'h220) ||
        (A13_TOTAL_CYCLES_ADDR !== 12'h224))
      $fatal(1, "A13 cycle-counter ABI localparam guard failed");

    // Error sequence: slots 0 and 1 commit, slot 2 fails, and slot 3 is never
    // requested. Successful state must remain intact and no pipeline starts.
    perform_reset();
    host_embedding_write_attempt(0);
    if (embedding_loaded_mask !== 4'h0)
      $fatal(1, "Host rejection changed loaded mask before error test");
    fake_error_enable = 1'b1;
    fake_error_row = SLOT2_LOOKUP_INDEX;
    fake_arready_enable = 1'b1;
    fake_response_delay = 2;
    pulse_load_all();

    wait_cycles = 0;
    while (!hbm_sequence_busy && wait_cycles < 200) begin
      @(posedge clk);
      wait_cycles = wait_cycles + 1;
    end
    if (!hbm_sequence_busy)
      $fatal(1, "sequence did not become busy");
    @(negedge clk);
    load_all_req_valid = 1'b1;
    repeat (3) begin
      @(posedge clk);
      #1;
      if (load_all_req_ready)
        $fatal(1, "busy repeated load-all request was accepted");
    end
    @(negedge clk);
    load_all_req_valid = 1'b0;

    wait_cycles = 0;
    while (!hbm_sequence_error_valid && wait_cycles < 500) begin
      @(posedge clk);
      wait_cycles = wait_cycles + 1;
    end
    #1;
    if (!hbm_sequence_error_valid ||
        (hbm_sequence_error_slot !== 2'd2) ||
        (hbm_sequence_error_index !== SLOT2_LOOKUP_INDEX))
      $fatal(1, "slot2 error status mismatch slot=%0d index=%0d",
             hbm_sequence_error_slot, hbm_sequence_error_index);
    if ((embedding_loaded_mask !== 4'h3) || hbm_all_loaded ||
        (successful_injection_count != 2))
      $fatal(1, "error preservation mask/injection mismatch mask=%h inject=%0d",
             embedding_loaded_mask, successful_injection_count);
    if ((dut.u_a13_pipeline.u_canonical_pipeline.embedding_mem[0] !==
         canonical_row(SLOT0_LOOKUP_INDEX)) ||
        (dut.u_a13_pipeline.u_canonical_pipeline.embedding_mem[1] !==
         canonical_row(SLOT1_LOOKUP_INDEX)) ||
        (dut.u_a13_pipeline.u_canonical_pipeline.embedding_mem[2] !== 128'd0) ||
        (dut.u_a13_pipeline.u_canonical_pipeline.embedding_mem[3] !== 128'd0))
      $fatal(1, "error sequence corrupted embedding contents");
    if ((logical_lookup_request_count != 3) ||
        (ar_handshake_count != 3) || (r_handshake_count != 3) ||
        (load_all_accept_count != 1))
      $fatal(1, "error sequence transaction count mismatch L=%0d AR=%0d R=%0d A=%0d",
             logical_lookup_request_count, ar_handshake_count,
             r_handshake_count, load_all_accept_count);
    repeat (6) @(posedge clk);
    if ((logical_lookup_request_count != 3) ||
        (ar_handshake_count != 3) || result_valid || sequence_done_seen)
      $fatal(1, "error sequence advanced or started pipeline");
    $display("A15_3_LOOKUP_ERROR_PROTECTION=PASS");
    $display("A15_3_ERROR_FAILING_SLOT_NOT_LOADED=PASS");
    $display("A15_3_BUSY_REQUEST_PROTECTION=PASS");
    acknowledge_sequence_error();

    // Successful sequence and complete accepted pipeline.
    perform_reset();
    fake_error_enable = 1'b0;
    fake_error_row = -1;
    fake_response_delay = 3;
    fake_arready_enable = 1'b1;
    configure_accepted_pipeline_sample();
    trigger_missing_embedding_start();
    $display("A15_3_PIPELINE_START_GUARD=PASS");

    // Keep the first AR request stalled, and present a repeated sequence
    // request while the accepted request/index/address must remain stable.
    fake_arready_enable = 1'b0;
    pulse_load_all();
    wait_cycles = 0;
    while (!m_axi_arvalid && wait_cycles < 200) begin
      @(posedge clk);
      wait_cycles = wait_cycles + 1;
    end
    if (!m_axi_arvalid)
      $fatal(1, "first AXI AR valid timeout");
    held_araddr = m_axi_araddr;
    @(negedge clk);
    load_all_req_valid = 1'b1;
    repeat (4) begin
      @(posedge clk);
      #1;
      if (!m_axi_arvalid || m_axi_arready ||
          (m_axi_araddr !== held_araddr) || load_all_req_ready)
        $fatal(1, "request/address changed under delayed AXI AR ready");
    end
    @(negedge clk);
    load_all_req_valid = 1'b0;
    fake_arready_enable = 1'b1;
    $display("A15_3_DELAYED_REQUEST_READY=PASS");

    // The pre-existing A13 missing-embedding error keeps configuration ready
    // low. The first successful response must therefore remain retained.
    wait_cycles = 0;
    while (!hbm_inject_pending && wait_cycles < 500) begin
      @(posedge clk);
      wait_cycles = wait_cycles + 1;
    end
    #1;
    if (!hbm_inject_pending || (hbm_inject_slot !== 2'd0) ||
        (hbm_inject_data !== canonical_row(SLOT0_LOOKUP_INDEX)))
      $fatal(1, "slot0 retained response mismatch");
    held_inject_slot = hbm_inject_slot;
    held_inject_data = hbm_inject_data;
    @(negedge clk);
    load_all_req_valid = 1'b1;
    repeat (5) begin
      @(posedge clk);
      #1;
      if (!hbm_inject_pending || hbm_inject_done ||
          (hbm_inject_slot !== held_inject_slot) ||
          (hbm_inject_data !== held_inject_data) ||
          (logical_lookup_request_count != 1) ||
          (embedding_loaded_mask != 4'h0) || load_all_req_ready)
        $fatal(1, "retained injection changed while A13 ready was low");
    end
    @(negedge clk);
    load_all_req_valid = 1'b0;
    if (load_all_accept_count != 1)
      $fatal(1, "repeated request was accepted while response was retained");
    $display("A15_3_DELAYED_RESPONSE=PASS");
    $display("A15_3_DELAYED_EMBEDDING_READY=PASS");
    $display("A15_3_RESPONSE_HOLD=PASS");
    acknowledge_pipeline_error();

    wait_cycles = 0;
    while (!hbm_all_loaded && wait_cycles < 1000) begin
      @(posedge clk);
      wait_cycles = wait_cycles + 1;
    end
    #1;
    if (!hbm_all_loaded || !sequence_done_seen ||
        (embedding_loaded_mask !== 4'hF) ||
        (mask_transition_count != 4))
      $fatal(1, "successful all-HBM sequence incomplete mask=%h transitions=%0d",
             embedding_loaded_mask, mask_transition_count);
    if ((logical_lookup_request_count != 4) ||
        (ar_handshake_count != 4) || (r_handshake_count != 4) ||
        (successful_injection_count != 4) ||
        (load_all_accept_count != 1))
      $fatal(1, "successful transaction count mismatch L=%0d AR=%0d R=%0d I=%0d",
             logical_lookup_request_count, ar_handshake_count,
             r_handshake_count, successful_injection_count);

    for (slot_index = 0; slot_index < 4; slot_index = slot_index + 1) begin
      if (dut.u_a13_pipeline.u_canonical_pipeline.embedding_mem[slot_index] !==
          canonical_row(SLOT0_LOOKUP_INDEX + slot_index))
        $fatal(1, "slot%0d full 128-bit row mismatch", slot_index);
      for (lane_index = 0; lane_index < 8; lane_index = lane_index + 1) begin
        if ($signed(dut.u_a13_pipeline.u_canonical_pipeline.
                    embedding_mem[slot_index][lane_index*16 +: 16]) !=
            canonical_lane(SLOT0_LOOKUP_INDEX + slot_index, lane_index))
          $fatal(1, "slot%0d lane%0d mismatch", slot_index, lane_index);
      end
    end

    $display("A15_3_SLOT0_HBM_LOOKUP=PASS");
    $display("A15_3_SLOT1_HBM_LOOKUP=PASS");
    $display("A15_3_SLOT2_HBM_LOOKUP=PASS");
    $display("A15_3_SLOT3_HBM_LOOKUP=PASS");
    $display("A15_3_SLOT0_LANE_ORDER=PASS");
    $display("A15_3_SLOT1_LANE_ORDER=PASS");
    $display("A15_3_SLOT2_LANE_ORDER=PASS");
    $display("A15_3_SLOT3_LANE_ORDER=PASS");
    $display("A15_3_ALL_FOUR_HBM_EMBEDDINGS=PASS");
    $display("A15_3_EMBEDDING_LOADED_MASK=PASS");

    // All four Host embedding writes are consumed and rejected; data and mask
    // remain owned by the four HBM lookups.
    for (slot_index = 0; slot_index < 4; slot_index = slot_index + 1)
      host_embedding_write_attempt(slot_index);
    for (slot_index = 0; slot_index < 4; slot_index = slot_index + 1) begin
      if (dut.u_a13_pipeline.u_canonical_pipeline.embedding_mem[slot_index] !==
          canonical_row(SLOT0_LOOKUP_INDEX + slot_index))
        $fatal(1, "Host write changed HBM-owned slot%0d", slot_index);
    end
    if (embedding_loaded_mask !== 4'hF)
      $fatal(1, "Host rejection changed loaded mask");
    $display("A15_3_HOST_EMBEDDING_WRITE_REJECT=PASS");

    if (!pipeline_start_ready)
      $fatal(1, "A13 pipeline not ready after four HBM injections");
    start_pipeline();

    wait_cycles = 0;
    while (!result_valid && wait_cycles < 5000) begin
      @(posedge clk);
      wait_cycles = wait_cycles + 1;
      if (pipeline_error_valid)
        $fatal(1, "pipeline error before result code=%02h phase=%0d",
               pipeline_error_code, phase);
    end
    #1;
    if (!result_valid)
      $fatal(1, "final result timeout");

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
    if ((held_result_index !== 0) || !held_result_last ||
        (held_result_tag !== 8'd4))
      $fatal(1, "final metadata mismatch index=%0d last=%b tag=%0d",
             held_result_index, held_result_last, held_result_tag);
    if ((bottom_result_count !== 4'd8) ||
        (interaction_result_count !== 5'd18))
      $fatal(1, "phase count mismatch bottom=%0d interaction=%0d",
             bottom_result_count, interaction_result_count);

    if (interaction_vector_seen !== 5'b11111)
      $fatal(1, "not all Interaction inputs were loaded: %b",
             interaction_vector_seen);
    if (interaction_input_vectors[0] !==
        128'h0008_0007_0006_0005_0004_0003_0002_0001)
      $fatal(1, "Interaction vector0 is not the Bottom output");
    for (slot_index = 0; slot_index < 4; slot_index = slot_index + 1) begin
      if (interaction_input_vectors[slot_index+1] !==
          canonical_row(SLOT0_LOOKUP_INDEX + slot_index))
        $fatal(1, "Interaction embedding vector%0d mismatch", slot_index+1);
    end
    for (address_index = 0; address_index < 18;
         address_index = address_index + 1) begin
      if ($signed(dut.u_a13_pipeline.u_canonical_pipeline.
                  interaction_vector[address_index]) !=
          expected_interaction[address_index])
        $fatal(1, "Interaction output%0d mismatch actual=%0d expected=%0d",
               address_index,
               $signed(dut.u_a13_pipeline.u_canonical_pipeline.
                       interaction_vector[address_index]),
               expected_interaction[address_index]);
    end

    if ((held_bottom_cycles == 0) || (held_interaction_cycles == 0) ||
        (held_top_cycles == 0) || (held_total_cycles == 0))
      $fatal(1, "zero cycle counter B=%0d I=%0d T=%0d Total=%0d",
             held_bottom_cycles, held_interaction_cycles,
             held_top_cycles, held_total_cycles);
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

    repeat (8) begin
      @(posedge clk);
      #1;
      if (!result_valid || (result_data !== held_result) ||
          (result_index !== held_result_index) ||
          (result_last !== held_result_last) ||
          (result_tag !== held_result_tag))
        $fatal(1, "final result changed under backpressure");
      if ((bottom_cycle_count !== held_bottom_cycles) ||
          (interaction_cycle_count !== held_interaction_cycles) ||
          (top_cycle_count !== held_top_cycles) ||
          (total_cycle_count !== held_total_cycles))
        $fatal(1, "cycle counters changed under result backpressure");
    end

    @(negedge clk);
    result_ready = 1'b1;
    @(posedge clk);
    @(negedge clk);
    result_ready = 1'b0;
    wait_cycles = 0;
    while (!done && wait_cycles < 200) begin
      @(posedge clk);
      wait_cycles = wait_cycles + 1;
    end
    if (!done)
      $fatal(1, "pipeline done timeout");

    $display("A15_3_A13_PIPELINE_ABI_UNCHANGED=PASS");
    $display("A15_3_A13_CYCLE_COUNTER_ABI_UNCHANGED=PASS");
    $display("A15_3_END_TO_END_PIPELINE=PASS");
    $display("A15_3_END_TO_END_RESULT_MATCH=PASS");

    $display("LOOKUP_SLOT0_INDEX=%0d", SLOT0_LOOKUP_INDEX);
    $display("LOOKUP_SLOT1_INDEX=%0d", SLOT1_LOOKUP_INDEX);
    $display("LOOKUP_SLOT2_INDEX=%0d", SLOT2_LOOKUP_INDEX);
    $display("LOOKUP_SLOT3_INDEX=%0d", SLOT3_LOOKUP_INDEX);
    $display("SLOT0_EXPECTED=[40,41,42,43,44,45,46,47]");
    $display("SLOT1_EXPECTED=[48,49,50,51,52,53,54,55]");
    $display("SLOT2_EXPECTED=[56,57,58,59,60,61,62,63]");
    $display("SLOT3_EXPECTED=[64,65,66,67,68,69,70,71]");
    $display("SLOT0_ACTUAL=[%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d]",
             $signed(dut.u_a13_pipeline.u_canonical_pipeline.embedding_mem[0][15:0]),
             $signed(dut.u_a13_pipeline.u_canonical_pipeline.embedding_mem[0][31:16]),
             $signed(dut.u_a13_pipeline.u_canonical_pipeline.embedding_mem[0][47:32]),
             $signed(dut.u_a13_pipeline.u_canonical_pipeline.embedding_mem[0][63:48]),
             $signed(dut.u_a13_pipeline.u_canonical_pipeline.embedding_mem[0][79:64]),
             $signed(dut.u_a13_pipeline.u_canonical_pipeline.embedding_mem[0][95:80]),
             $signed(dut.u_a13_pipeline.u_canonical_pipeline.embedding_mem[0][111:96]),
             $signed(dut.u_a13_pipeline.u_canonical_pipeline.embedding_mem[0][127:112]));
    $display("SLOT1_ACTUAL=[%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d]",
             $signed(dut.u_a13_pipeline.u_canonical_pipeline.embedding_mem[1][15:0]),
             $signed(dut.u_a13_pipeline.u_canonical_pipeline.embedding_mem[1][31:16]),
             $signed(dut.u_a13_pipeline.u_canonical_pipeline.embedding_mem[1][47:32]),
             $signed(dut.u_a13_pipeline.u_canonical_pipeline.embedding_mem[1][63:48]),
             $signed(dut.u_a13_pipeline.u_canonical_pipeline.embedding_mem[1][79:64]),
             $signed(dut.u_a13_pipeline.u_canonical_pipeline.embedding_mem[1][95:80]),
             $signed(dut.u_a13_pipeline.u_canonical_pipeline.embedding_mem[1][111:96]),
             $signed(dut.u_a13_pipeline.u_canonical_pipeline.embedding_mem[1][127:112]));
    $display("SLOT2_ACTUAL=[%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d]",
             $signed(dut.u_a13_pipeline.u_canonical_pipeline.embedding_mem[2][15:0]),
             $signed(dut.u_a13_pipeline.u_canonical_pipeline.embedding_mem[2][31:16]),
             $signed(dut.u_a13_pipeline.u_canonical_pipeline.embedding_mem[2][47:32]),
             $signed(dut.u_a13_pipeline.u_canonical_pipeline.embedding_mem[2][63:48]),
             $signed(dut.u_a13_pipeline.u_canonical_pipeline.embedding_mem[2][79:64]),
             $signed(dut.u_a13_pipeline.u_canonical_pipeline.embedding_mem[2][95:80]),
             $signed(dut.u_a13_pipeline.u_canonical_pipeline.embedding_mem[2][111:96]),
             $signed(dut.u_a13_pipeline.u_canonical_pipeline.embedding_mem[2][127:112]));
    $display("SLOT3_ACTUAL=[%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d]",
             $signed(dut.u_a13_pipeline.u_canonical_pipeline.embedding_mem[3][15:0]),
             $signed(dut.u_a13_pipeline.u_canonical_pipeline.embedding_mem[3][31:16]),
             $signed(dut.u_a13_pipeline.u_canonical_pipeline.embedding_mem[3][47:32]),
             $signed(dut.u_a13_pipeline.u_canonical_pipeline.embedding_mem[3][63:48]),
             $signed(dut.u_a13_pipeline.u_canonical_pipeline.embedding_mem[3][79:64]),
             $signed(dut.u_a13_pipeline.u_canonical_pipeline.embedding_mem[3][95:80]),
             $signed(dut.u_a13_pipeline.u_canonical_pipeline.embedding_mem[3][111:96]),
             $signed(dut.u_a13_pipeline.u_canonical_pipeline.embedding_mem[3][127:112]));
    $display("EMBEDDING_LOADED_MASK=%h", embedding_loaded_mask);
    $display("LOGICAL_LOOKUP_REQUESTS=%0d", logical_lookup_request_count);
    $display("AXI_AR_HANDSHAKES=%0d", ar_handshake_count);
    $display("AXI_R_HANDSHAKES=%0d", r_handshake_count);
    $display("SUCCESSFUL_SLOT_INJECTIONS=%0d", successful_injection_count);
    $display("A15_3_GOLDEN_FINAL_RESULT=%0d", golden_result);
    $display("A15_3_ACTUAL_FINAL_RESULT=%0d", held_result);
    $display("BOTTOM_CYCLES=%0d", held_bottom_cycles);
    $display("INTERACTION_CYCLES=%0d", held_interaction_cycles);
    $display("TOP_CYCLES=%0d", held_top_cycles);
    $display("TOTAL_CYCLES=%0d", held_total_cycles);
    $display("CONTROLLER_OVERHEAD_CYCLES=%0d", controller_overhead);
    $display("STAGE2N_A15_3_ALL_HBM_EMBEDDING_PIPELINE_XSIM_V1_PASS");
    $finish;
  end

endmodule
