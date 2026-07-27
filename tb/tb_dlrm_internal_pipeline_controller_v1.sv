`timescale 1ns/1ps

module tb_dlrm_internal_pipeline_controller_v1;

  localparam integer MAX_LAYERS = 4;
  localparam integer MAX_IN_DIM = 64;
  localparam integer MAX_OUT_DIM = 64;
  localparam integer NUM_PE = 16;
  localparam integer INPUT_WIDTH = 16;
  localparam integer OUTPUT_WIDTH = 16;
  localparam integer WEIGHT_ADDR_WIDTH = 32;
  localparam integer BIAS_ADDR_WIDTH = 32;
  localparam integer MAX_WEIGHT_VALUES = 1024;
  localparam integer MAX_BIAS_VALUES = 64;
  localparam integer ACT_CHUNK_ADDR_WIDTH = 2;
  localparam integer LAYER_INDEX_WIDTH = 2;
  localparam integer LAYER_COUNT_WIDTH = 3;

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

  logic embedding_cfg_valid;
  logic embedding_cfg_ready;
  logic [1:0] embedding_cfg_index;
  logic [8*INPUT_WIDTH-1:0] embedding_cfg_data;
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
  logic error_valid;
  logic error_ready;
  logic [7:0] error_code;

  integer timeout_cycles;
  integer address_index;
  integer output_count;
  logic signed [15:0] held_result_data;
  logic [5:0] held_result_index;
  logic held_result_last;
  logic [7:0] held_result_tag;

  dlrm_internal_pipeline_controller #(
    .MAX_LAYERS(MAX_LAYERS),
    .MAX_IN_DIM(MAX_IN_DIM),
    .MAX_OUT_DIM(MAX_OUT_DIM),
    .NUM_PE(NUM_PE),
    .MAX_WEIGHT_VALUES(MAX_WEIGHT_VALUES),
    .MAX_BIAS_VALUES(MAX_BIAS_VALUES)
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
    .embedding_cfg_valid(embedding_cfg_valid),
    .embedding_cfg_ready(embedding_cfg_ready),
    .embedding_cfg_index(embedding_cfg_index),
    .embedding_cfg_data(embedding_cfg_data),
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
    .error_valid(error_valid),
    .error_ready(error_ready),
    .error_code(error_code)
  );

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
    logic signed [15:0] x0;
    logic signed [15:0] x1;
    logic signed [15:0] x2;
    logic signed [15:0] x3;
    logic signed [15:0] x4;
    logic signed [15:0] x5;
    logic signed [15:0] x6;
    logic signed [15:0] x7;
    begin
      x0=v0; x1=v1; x2=v2; x3=v3;
      x4=v4; x5=v5; x6=v6; x7=v7;
      pack_vector8 = {x7,x6,x5,x4,x3,x2,x1,x0};
    end
  endfunction

  task automatic reset_dut;
    begin
      rst = 1'b1;
      repeat (6) @(posedge clk);
      rst = 1'b0;
      repeat (3) @(posedge clk);
    end
  endtask

  task automatic load_descriptor(
    input [1:0] index,
    input [95:0] value
  );
    begin
      @(negedge clk);
      descriptor_cfg_index = index;
      descriptor_cfg_data = value;
      descriptor_cfg_valid = 1'b1;
      timeout_cycles = 0;
      while (!descriptor_cfg_ready && timeout_cycles < 200) begin
        @(posedge clk);
        timeout_cycles = timeout_cycles + 1;
      end
      if (!descriptor_cfg_ready)
        $fatal(1, "descriptor %0d timeout", index);
      @(posedge clk);
      @(negedge clk);
      descriptor_cfg_valid = 1'b0;
    end
  endtask

  task automatic load_weight(
    input integer address,
    input integer value
  );
    begin
      @(negedge clk);
      weight_cfg_address = address;
      weight_cfg_data = value;
      weight_cfg_valid = 1'b1;
      timeout_cycles = 0;
      while (!weight_cfg_ready && timeout_cycles < 200) begin
        @(posedge clk);
        timeout_cycles = timeout_cycles + 1;
      end
      if (!weight_cfg_ready)
        $fatal(1, "weight %0d timeout", address);
      @(posedge clk);
      @(negedge clk);
      weight_cfg_valid = 1'b0;
    end
  endtask

  task automatic load_bias(
    input integer address,
    input integer value
  );
    begin
      @(negedge clk);
      bias_cfg_address = address;
      bias_cfg_data = value;
      bias_cfg_valid = 1'b1;
      timeout_cycles = 0;
      while (!bias_cfg_ready && timeout_cycles < 200) begin
        @(posedge clk);
        timeout_cycles = timeout_cycles + 1;
      end
      if (!bias_cfg_ready)
        $fatal(1, "bias %0d timeout", address);
      @(posedge clk);
      @(negedge clk);
      bias_cfg_valid = 1'b0;
    end
  endtask

  task automatic load_bottom_input;
    begin
      @(negedge clk);
      act_load_buffer_select = 1'b0;
      act_load_chunk_index = '0;
      act_load_lane_mask = 16'h000F;
      act_load_data = '0;
      act_load_data[0 +: 16] = 16'sd1;
      act_load_data[16 +: 16] = 16'sd2;
      act_load_data[32 +: 16] = 16'sd3;
      act_load_data[48 +: 16] = 16'sd4;
      act_load_valid = 1'b1;
      timeout_cycles = 0;
      while (!act_load_ready && timeout_cycles < 200) begin
        @(posedge clk);
        timeout_cycles = timeout_cycles + 1;
      end
      if (!act_load_ready)
        $fatal(1, "bottom input timeout");
      @(posedge clk);
      @(negedge clk);
      act_load_valid = 1'b0;
    end
  endtask

  task automatic load_embedding(
    input [1:0] index,
    input [127:0] value
  );
    begin
      @(negedge clk);
      embedding_cfg_index = index;
      embedding_cfg_data = value;
      embedding_cfg_valid = 1'b1;
      timeout_cycles = 0;
      while (!embedding_cfg_ready && timeout_cycles < 200) begin
        @(posedge clk);
        timeout_cycles = timeout_cycles + 1;
      end
      if (!embedding_cfg_ready)
        $fatal(1, "embedding %0d timeout", index);
      @(posedge clk);
      @(negedge clk);
      embedding_cfg_valid = 1'b0;
    end
  endtask

  task automatic start_pipeline;
    begin
      @(negedge clk);
      bottom_descriptor_base = 2'd0;
      bottom_layer_count = 3'd1;
      top_descriptor_base = 2'd1;
      top_layer_count = 3'd1;
      bottom_initial_buffer_select = 1'b0;
      top_input_buffer_select = 1'b0;
      interaction_shift = 6'd0;
      pipeline_start_valid = 1'b1;
      timeout_cycles = 0;
      while (!pipeline_start_ready && timeout_cycles < 200) begin
        @(posedge clk);
        timeout_cycles = timeout_cycles + 1;
      end
      if (!pipeline_start_ready)
        $fatal(1, "pipeline start timeout mask=0x%0h", embedding_loaded_mask);
      @(posedge clk);
      @(negedge clk);
      pipeline_start_valid = 1'b0;
    end
  endtask

  task automatic wait_for_result(input integer backpressure_cycles);
    begin
      output_count = 0;
      result_ready = 1'b0;
      timeout_cycles = 0;

      while (!result_valid && timeout_cycles < 20000) begin
        @(posedge clk);
        timeout_cycles = timeout_cycles + 1;
        if (error_valid)
          $fatal(1, "pipeline error before result: 0x%0h phase=%0d", error_code, phase);
      end
      if (!result_valid)
        $fatal(1, "result timeout phase=%0d", phase);

      held_result_data = result_data;
      held_result_index = result_index;
      held_result_last = result_last;
      held_result_tag = result_tag;

      if (held_result_data !== -16'sd60 ||
          held_result_index !== 0 ||
          !held_result_last ||
          held_result_tag !== 8'd1)
        $fatal(1,
               "top output mismatch data=%0d index=%0d last=%0d tag=%0d",
               held_result_data,
               held_result_index,
               held_result_last,
               held_result_tag);

      repeat (backpressure_cycles) begin
        @(posedge clk);
        if (!result_valid ||
            result_data !== held_result_data ||
            result_index !== held_result_index ||
            result_last !== held_result_last ||
            result_tag !== held_result_tag)
          $fatal(1, "top result changed under backpressure");
      end

      @(negedge clk);
      result_ready = 1'b1;
      @(posedge clk);
      output_count = output_count + 1;
      @(negedge clk);
      result_ready = 1'b0;

      timeout_cycles = 0;
      while (!done && timeout_cycles < 2000) begin
        @(posedge clk);
        timeout_cycles = timeout_cycles + 1;
        if (error_valid)
          $fatal(1, "pipeline error after result: 0x%0h phase=%0d", error_code, phase);
      end
      if (!done)
        $fatal(1, "done timeout phase=%0d", phase);
      if (bottom_result_count !== 8)
        $fatal(1, "bottom result count mismatch: %0d", bottom_result_count);
      if (interaction_result_count !== 18)
        $fatal(1, "interaction result count mismatch: %0d", interaction_result_count);
      if (output_count != 1)
        $fatal(1, "top output count mismatch: %0d", output_count);
      @(posedge clk);
    end
  endtask

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
    embedding_cfg_valid = 1'b0;
    embedding_cfg_index = '0;
    embedding_cfg_data = '0;
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
    error_ready = 1'b0;

    reset_dut();

    load_descriptor(2'd0, pack_descriptor(4, 8, 0, 0, 0, 0));
    load_descriptor(2'd1, pack_descriptor(18, 1, 32, 8, 0, 0));

    // Bottom weights, row-major [8][4].
    // Outputs become exactly [1,2,3,4,5,6,7,8].
    for (address_index = 0; address_index < 32; address_index = address_index + 1)
      load_weight(address_index, 0);
    load_weight(0, 1);
    load_weight(5, 1);
    load_weight(10, 1);
    load_weight(15, 1);
    load_weight(16, 1); load_weight(19, 1);
    load_weight(21, 1); load_weight(23, 1);
    load_weight(26, 1); load_weight(27, 1);
    load_weight(31, 2);

    // Top weights are all one, so the 18 interaction values sum to -60.
    for (address_index = 32; address_index < 50; address_index = address_index + 1)
      load_weight(address_index, 1);

    for (address_index = 0; address_index < 9; address_index = address_index + 1)
      load_bias(address_index, 0);

    load_embedding(2'd0, pack_vector8(1,0,-1,0,1,0,-1,0));
    load_embedding(2'd1, pack_vector8(2,2,2,2,2,2,2,2));
    load_embedding(2'd2, pack_vector8(-1,-2,-3,-4,-5,-6,-7,-8));
    load_embedding(2'd3, pack_vector8(10,9,8,7,6,5,4,3));

    if (embedding_loaded_mask !== 4'hF)
      $fatal(1, "embedding mask mismatch: 0x%0h", embedding_loaded_mask);

    // Run 1: no final-result backpressure.
    load_bottom_input();
    start_pipeline();
    wait_for_result(0);

    // Run 2: reload only the overwritten Bottom input, then verify final-result
    // stability while the host holds ready low for 12 cycles.
    load_bottom_input();
    start_pipeline();
    wait_for_result(12);

    if (error_valid)
      $fatal(1, "unexpected terminal error: 0x%0h", error_code);

    $display("tb_dlrm_internal_pipeline_controller_v1: PASS runs=2 bottom=8 interaction=18 top=-60 backpressure=12");
    $finish;
  end

endmodule
