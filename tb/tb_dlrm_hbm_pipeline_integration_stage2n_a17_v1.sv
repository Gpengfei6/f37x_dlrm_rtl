`timescale 1ns/1ps

// A17.1 four-port local pipeline proof. Sparse result36 is not embedding-sensitive.
// The fake AXI memory is independent of the accepted A14 lookup RTL. The
// accepted A13 test network is configured exactly as in A15.2, while all four
// embedding slots are checked bit-for-bit separately from the final result.
//
// LUTLP handshake coverage (registered compute_idle_q / A15-style START split):
// 1. START held until ready and accepted once: start_pipeline keeps valid high
//    after the first ready and checks start_count.
// 2. Load during busy: run_compute drives load_all_req_valid for four cycles
//    after START and requires !load_all_req_ready && busy. The registered
//    idle snapshot can lag busy by one cycle; this bench and the public kernel
//    FSM do not issue a new load on that START cycle. Same-cycle START+load is
//    mutexed by start_gate (!load_all_req_valid).
// 3. Stale fresh_group after complete/CLEAR/error: run_compute rejects START
//    on the old token; error-drain then a new load is required before the
//    second compute. start_count==2 at the end.
module tb_dlrm_hbm_pipeline_integration_stage2n_a17_v1;

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
  integer start_count;
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

  logic [3:0] [HBM_ADDR_WIDTH-1:0] table_base_addr;
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

  logic [3:0][0:0] m_axi_arid;
  logic [3:0] [HBM_ADDR_WIDTH-1:0] m_axi_araddr;
  logic [3:0] [7:0] m_axi_arlen;
  logic [3:0] [2:0] m_axi_arsize;
  logic [3:0] [1:0] m_axi_arburst;
  logic [3:0] m_axi_arlock;
  logic [3:0] [3:0] m_axi_arcache;
  logic [3:0] [2:0] m_axi_arprot;
  logic [3:0] [3:0] m_axi_arqos;
  logic [3:0] m_axi_arvalid;
  logic [3:0] m_axi_arready;
  logic [3:0][0:0] m_axi_rid;
  logic [3:0] [HBM_DATA_WIDTH-1:0] m_axi_rdata;
  logic [3:0] [1:0] m_axi_rresp;
  logic [3:0] m_axi_rlast;
  logic [3:0] m_axi_rvalid;
  logic [3:0] m_axi_rready;



  integer expected_interaction [0:17];
  integer golden_result;
  integer lane_index;
  integer pair_row_index;
  integer pair_column_index;
  integer pair_output_index;
  integer dot_accumulator;
  integer wait_cycles;

  logic signed [15:0] held_result;

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

  task automatic start_pipeline;
    integer cycles;
    integer start_count_before;
    begin
      @(negedge clk);
      bottom_descriptor_base = 0;
      bottom_layer_count = 2;
      top_descriptor_base = 2;
      top_layer_count = 3;
      bottom_initial_buffer_select = 1'b0;
      top_input_buffer_select = 1'b0;
      interaction_shift = 0;
      start_count_before = start_count;
      pipeline_start_valid = 1'b1;
      cycles = 0;
      while (!pipeline_start_ready && cycles < 200) begin
        @(posedge clk);
        cycles = cycles + 1;
      end
      if (!pipeline_start_ready)
        $fatal(1, "pipeline START timeout mask=%h", embedding_loaded_mask);
      // Keep the request asserted after the first ready. It must be accepted
      // once; a second START must not sneak through on the registered idle.
      repeat (6) begin
        @(posedge clk);
        #1;
        if (start_count !== start_count_before + 1)
          $fatal(1, "START accepted %0d times, expected once",
              start_count - start_count_before);
        if (pipeline_start_valid && pipeline_start_ready &&
            load_all_req_valid && load_all_req_ready)
          $fatal(1, "START and load both accepted");
      end
      @(negedge clk);
      pipeline_start_valid = 1'b0;
    end
  endtask

  dlrm_hbm_pipeline_integration_stage2n_a17_v1 #(
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

  integer delay_left [0:3];
  logic [3:0] pending;
  integer ar_count [0:3];
  integer r_count [0:3];
  integer inject_count, run_count;
  integer fail_bank;
  integer b;
  logic [3:0] ar_enable;
  assign m_axi_arready = ar_enable & ~pending & ~m_axi_rvalid;
  assign m_axi_rid = '0;
  assign m_axi_rlast = 4'hF;
  always @(posedge clk) begin
    if (rst) begin
      pending <= '0; m_axi_rvalid <= '0; m_axi_rdata <= '0; m_axi_rresp <= '0;
      inject_count <= 0; start_count <= 0;
      for (integer n=0;n<4;n=n+1) begin
        delay_left[n] <= 0; ar_count[n] <= 0; r_count[n] <= 0;
      end
    end else begin
      if (pipeline_start_valid && pipeline_start_ready) start_count <= start_count+1;
      if (hbm_inject_done) inject_count <= inject_count+1;
      for (integer n=0;n<4;n=n+1) begin
        if (m_axi_arvalid[n] && m_axi_arready[n]) begin
          if (m_axi_araddr[n] !== (TABLE_BASE + n*65536 + (37+n)*16))
            $fatal(1,"bank%0d wrong runtime address %h",n,m_axi_araddr[n]);
          if (m_axi_arlen[n] !== 0 || m_axi_arsize[n] !== 4 || m_axi_arburst[n] !== 1)
            $fatal(1,"bank%0d invalid AXI shape",n);
          pending[n] <= 1; delay_left[n] <= 3+(3-n)*4;
          ar_count[n] <= ar_count[n]+1;
        end
        if (pending[n]) begin
          if (delay_left[n] !== 0) delay_left[n] <= delay_left[n]-1;
          else begin
            pending[n] <= 0; m_axi_rvalid[n] <= 1;
            m_axi_rdata[n] <= canonical_row(37+n);
            m_axi_rresp[n] <= (fail_bank == n) ? 2'b10 : 2'b00;
          end
        end
        if (m_axi_rvalid[n] && m_axi_rready[n]) begin
          m_axi_rvalid[n] <= 0; r_count[n] <= r_count[n]+1;
        end
      end
    end
  end

  task automatic wait_loaded;
    integer t;
    begin
      t=0;
      while (!pipeline_start_ready && t<500) begin @(negedge clk); t=t+1; end
      if (!hbm_all_loaded || embedding_loaded_mask !== 4'hF || !pipeline_start_ready)
        $fatal(1,"fresh complete group timeout");
      for (integer n=0;n<4;n=n+1)
        if (dut.u_a13_pipeline.u_canonical_pipeline.embedding_mem[n] !== canonical_row(37+n))
          $fatal(1,"slot%0d not exact canonical row",n);
    end
  endtask

  task automatic run_compute;
    integer t;
    begin
      start_pipeline();
      // Loads during active compute cannot be accepted.
      @(negedge clk); load_all_req_valid=1;
      repeat(4) begin @(posedge clk); #1;
        if (load_all_req_ready || !busy) $fatal(1,"load accepted during compute");
      end
      @(negedge clk); load_all_req_valid=0;
      t=0;
      while (!result_valid && t<5000) begin @(negedge clk); t=t+1;
        if(pipeline_error_valid) $fatal(1,"A13 error %h",pipeline_error_code);
      end
      // A13 freezes counters on the rising edge observing final result valid.
      @(posedge clk); #1;
      if (result_valid !== 1'b1 || $signed(result_data) !== golden_result || result_index !== 0 || result_last !== 1'b1 || result_tag !== 4)
        $fatal(1,"result mismatch actual=%0d golden=%0d",result_data,golden_result);
      if (bottom_cycle_count !== 322 || interaction_cycle_count !== 100 || top_cycle_count !== 744 || total_cycle_count !== 1174)
        $fatal(1,"compute counters changed B=%0d I=%0d T=%0d total=%0d",bottom_cycle_count,interaction_cycle_count,top_cycle_count,total_cycle_count);
      if (bottom_result_count !== 8 || interaction_result_count !== 18)
        $fatal(1,"compute output counts mismatch");
      for(integer n=0;n<18;n=n+1)
        if ($signed(dut.u_a13_pipeline.u_canonical_pipeline.interaction_vector[n]) !== expected_interaction[n])
          $fatal(1,"interaction lane%0d mismatch",n);
      held_result=result_data;
      load_all_req_valid=1;
      repeat(8) begin @(posedge clk); #1;
        if (result_valid !== 1'b1 || result_data !== held_result || load_all_req_ready || pipeline_start_ready)
          $fatal(1,"result hold or load/start exclusion failed");
      end
      @(negedge clk); load_all_req_valid=0; result_ready=1;
      @(negedge clk); result_ready=0;
      t=0;
      while(busy && t<200) begin @(negedge clk); t=t+1; end
      if(busy) $fatal(1,"compute did not retire");
      // Old all-loaded bits must not permit a second START.
      pipeline_start_valid=1;
      repeat(4) begin @(posedge clk); #1;
        if(pipeline_start_ready || busy) $fatal(1,"reused stale load token");
      end
      @(negedge clk); pipeline_start_valid=0;
      run_count=run_count+1;
    end
  endtask

  initial begin
    clk=0; rst=1; descriptor_cfg_valid=0; descriptor_cfg_index=0; descriptor_cfg_data=0;
    act_load_valid=0; act_load_buffer_select=0; act_load_chunk_index=0; act_load_lane_mask=0; act_load_data=0;
    host_embedding_cfg_valid=0; host_embedding_cfg_index=0; host_embedding_cfg_data=0;
    weight_cfg_valid=0; weight_cfg_address=0; weight_cfg_data=0;
    bias_cfg_valid=0; bias_cfg_address=0; bias_cfg_data=0;
    pipeline_start_valid=0; bottom_descriptor_base=0; bottom_layer_count=2;
    top_descriptor_base=2; top_layer_count=3; bottom_initial_buffer_select=0;
    top_input_buffer_select=0; interaction_shift=0; result_ready=0; pipeline_error_ready=0;
    load_all_req_valid=0; hbm_sequence_error_ready=0; ar_enable=4'hF; fail_bank=-1; run_count=0;
    for(b=0;b<4;b=b+1) table_base_addr[b]=TABLE_BASE+b*65536;
    build_independent_golden();
    if(golden_result !== 36) $fatal(1,"golden construction failed");
    perform_reset(); configure_accepted_pipeline_sample();
    pipeline_start_valid=1;
    repeat(3) begin @(posedge clk); #1;
      if(pipeline_start_ready || busy) $fatal(1,"START allowed before initial load");
    end
    @(negedge clk); pipeline_start_valid=0;
    pulse_load_all(); wait_loaded();
    for(b=0;b<4;b=b+1) host_embedding_write_attempt(b);
    // With a fresh token available, a simultaneous reload wins over START.
    @(negedge clk); ar_enable=0; load_all_req_valid=1; pipeline_start_valid=1;
    #1; if(pipeline_start_ready || !load_all_req_ready) $fatal(1,"load priority failed");
    @(negedge clk); load_all_req_valid=0;
    repeat(8) begin @(posedge clk); #1;
      if(pipeline_start_ready || busy || hbm_all_loaded || embedding_loaded_mask !== 4'hF)
        $fatal(1,"stale A13 mask allowed compute during reload");
    end
    @(negedge clk); pipeline_start_valid=0; ar_enable=4'hF;
    wait_loaded(); run_compute();
    load_bottom_input();
    // Failed fresh group after successful run leaves stale mask but no START.
    fail_bank=2; pulse_load_all();
    wait_cycles=0;
    while(!hbm_sequence_error_valid && wait_cycles<500) begin @(negedge clk); wait_cycles=wait_cycles+1; end
    if(!hbm_sequence_error_valid || hbm_sequence_error_slot !== 2 || hbm_sequence_error_index !== 39 || hbm_all_loaded)
      $fatal(1,"failed group status mismatch");
    if(inject_count !== 8) $fatal(1,"failed group performed a configuration write");
    pipeline_start_valid=1;
    repeat(6) begin @(posedge clk); #1;
      if(pipeline_start_ready || busy || load_all_req_ready || hbm_sequence_error_slot !== 2)
        $fatal(1,"failed group started or error changed under backpressure");
    end
    @(negedge clk); hbm_sequence_error_ready=1;
    @(negedge clk); hbm_sequence_error_ready=0;
    repeat(4) begin @(posedge clk); #1;
      if(pipeline_start_ready || busy) $fatal(1,"error ACK exposed stale mask");
    end
    @(negedge clk); pipeline_start_valid=0; fail_bank=-1;
    pulse_load_all(); wait_loaded(); run_compute();
    if(start_count !== 2 || run_count !== 2 || inject_count !== 12)
      $fatal(1,"group/start/inject totals mismatch S=%0d R=%0d I=%0d",start_count,run_count,inject_count);
    for(b=0;b<4;b=b+1)
      if(ar_count[b] !== 4 || r_count[b] !== 4) $fatal(1,"bank%0d transaction totals mismatch",b);
    $display("A17_LUTLP_START_HELD_ONCE=PASS");
    $display("A17_LUTLP_LOAD_DURING_COMPUTE=PASS");
    $display("A17_LUTLP_STALE_FRESH_GROUP=PASS");
    $display("A17_LUTLP_IDLE_Q_LAG_WINDOW=KERNEL_SEQUENCED_NOT_DRIVEN");
    $display("A17_1_GOLDEN_FINAL_RESULT=%0d",golden_result);
    $display("A17_1_ACTUAL_FINAL_RESULT=%0d",held_result);
    $display("BOTTOM_CYCLES=%0d",bottom_cycle_count);
    $display("INTERACTION_CYCLES=%0d",interaction_cycle_count);
    $display("TOP_CYCLES=%0d",top_cycle_count);
    $display("TOTAL_CYCLES=%0d",total_cycle_count);
    $display("PIPELINE_RUN_COUNT=%0d",run_count);
    $display("A17_1_PIPELINE_INTEGRATION_TEST=PASS");
    $finish;
  end
  initial begin #2000000; $fatal(1,"global integration watchdog"); end
endmodule
