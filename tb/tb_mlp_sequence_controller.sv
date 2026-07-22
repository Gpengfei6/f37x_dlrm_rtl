`timescale 1ns/1ps

module tb_mlp_sequence_controller;

  localparam integer CASE_COUNT = 20;
  localparam integer VALID_CASE_COUNT = 11;
  localparam integer MAX_LAYERS = 4;
  localparam integer MAX_IN_DIM = 1024;
  localparam integer MAX_OUT_DIM = 1024;
  localparam integer NUM_PE = 16;
  localparam integer INPUT_WIDTH = 16;
  localparam integer WEIGHT_WIDTH = 8;
  localparam integer BIAS_WIDTH = 24;
  localparam integer OUTPUT_WIDTH = 16;
  localparam integer OUT_INDEX_WIDTH = 10;
  localparam integer ACT_CHUNK_ADDR_WIDTH = 6;
  localparam integer LAYER_INDEX_WIDTH = 2;
  localparam integer LAYER_COUNT_WIDTH = 3;
  localparam integer INPUT_ROW_WIDTH = MAX_IN_DIM*INPUT_WIDTH;
  localparam integer OUTPUT_ROW_WIDTH = MAX_OUT_DIM*OUTPUT_WIDTH;
  localparam integer DESCRIPTOR_WIDTH = 96;
  localparam integer WEIGHT_VALUE_COUNT = 1958;
  localparam integer BIAS_VALUE_COUNT = 70;
  localparam integer DESCRIPTOR_ROW_COUNT = CASE_COUNT*MAX_LAYERS;

  localparam logic [3:0] ERROR_BAD_LAYER_COUNT    = 4'd1;
  localparam logic [3:0] ERROR_MISSING_DESCRIPTOR = 4'd2;
  localparam logic [3:0] ERROR_BAD_DIMENSION      = 4'd3;
  localparam logic [3:0] ERROR_DIMENSION_MISMATCH = 4'd4;
  localparam logic [3:0] ERROR_WEIGHT_RANGE       = 4'd5;
  localparam logic [3:0] ERROR_BIAS_RANGE         = 4'd6;
  localparam logic [3:0] ERROR_BAD_SHIFT          = 4'd7;

  logic clk;
  logic rst;

  logic descriptor_cfg_valid;
  logic [LAYER_INDEX_WIDTH-1:0] descriptor_cfg_index;
  logic [DESCRIPTOR_WIDTH-1:0] descriptor_cfg_data;
  logic descriptor_cfg_ready_48;
  logic descriptor_cfg_ready_32;

  logic start_valid_48;
  logic start_ready_48;
  logic start_valid_32;
  logic start_ready_32;
  logic [LAYER_COUNT_WIDTH-1:0] layer_count;
  logic initial_buffer_select;

  logic act_load_valid;
  logic act_load_buffer_select;
  logic [ACT_CHUNK_ADDR_WIDTH-1:0] act_load_chunk_index;
  logic [NUM_PE-1:0] act_load_lane_mask;
  logic [NUM_PE*INPUT_WIDTH-1:0] act_load_data;
  logic act_load_ready_48;
  logic act_load_ready_32;

  logic weight_cfg_valid;
  logic [31:0] weight_cfg_address;
  logic signed [WEIGHT_WIDTH-1:0] weight_cfg_data;
  logic weight_cfg_ready_48;
  logic weight_cfg_ready_32;

  logic bias_cfg_valid;
  logic [31:0] bias_cfg_address;
  logic signed [BIAS_WIDTH-1:0] bias_cfg_data;
  logic bias_cfg_ready_48;
  logic bias_cfg_ready_32;

  logic result_valid_48;
  logic result_ready_48;
  logic signed [OUTPUT_WIDTH-1:0] result_data_48;
  logic [OUT_INDEX_WIDTH-1:0] result_index_48;
  logic result_last_48;
  logic [7:0] result_tag_48;

  logic result_valid_32;
  logic result_ready_32;
  logic signed [OUTPUT_WIDTH-1:0] result_data_32;
  logic [OUT_INDEX_WIDTH-1:0] result_index_32;
  logic result_last_32;
  logic [7:0] result_tag_32;

  logic busy_48;
  logic done_48;
  logic final_buffer_select_48;
  logic error_valid_48;
  logic error_ready_48;
  logic [3:0] error_code_48;

  logic busy_32;
  logic done_32;
  logic final_buffer_select_32;
  logic error_valid_32;
  logic error_ready_32;
  logic [3:0] error_code_32;

  logic [INPUT_ROW_WIDTH-1:0] input_rows [0:CASE_COUNT-1];
  logic [OUTPUT_ROW_WIDTH-1:0] expected_output_rows [0:CASE_COUNT-1];
  logic [DESCRIPTOR_WIDTH-1:0]
      descriptor_rows [0:DESCRIPTOR_ROW_COUNT-1];
  logic [WEIGHT_WIDTH-1:0] weight_values [0:WEIGHT_VALUE_COUNT-1];
  logic [BIAS_WIDTH-1:0] bias_values [0:BIAS_VALUE_COUNT-1];

  integer global_cycle_count;
  integer case_index;

  wire descriptor_cfg_ready_all =
      descriptor_cfg_ready_48 && descriptor_cfg_ready_32;
  wire act_load_ready_all =
      act_load_ready_48 && act_load_ready_32;
  wire weight_cfg_ready_all =
      weight_cfg_ready_48 && weight_cfg_ready_32;
  wire bias_cfg_ready_all =
      bias_cfg_ready_48 && bias_cfg_ready_32;

  mlp_sequence_controller #(
    .MAX_LAYERS(MAX_LAYERS),
    .MAX_IN_DIM(MAX_IN_DIM),
    .MAX_OUT_DIM(MAX_OUT_DIM),
    .NUM_PE(NUM_PE),
    .ACC_WIDTH(48)
  ) dut_acc48 (
    .clk(clk),
    .rst(rst),

    .descriptor_cfg_valid(descriptor_cfg_valid),
    .descriptor_cfg_ready(descriptor_cfg_ready_48),
    .descriptor_cfg_index(descriptor_cfg_index),
    .descriptor_cfg_data(descriptor_cfg_data),

    .start_valid(start_valid_48),
    .start_ready(start_ready_48),
    .layer_count(layer_count),
    .initial_buffer_select(initial_buffer_select),

    .act_load_valid(act_load_valid),
    .act_load_ready(act_load_ready_48),
    .act_load_buffer_select(act_load_buffer_select),
    .act_load_chunk_index(act_load_chunk_index),
    .act_load_lane_mask(act_load_lane_mask),
    .act_load_data(act_load_data),

    .weight_cfg_valid(weight_cfg_valid),
    .weight_cfg_ready(weight_cfg_ready_48),
    .weight_cfg_address(weight_cfg_address),
    .weight_cfg_data(weight_cfg_data),

    .bias_cfg_valid(bias_cfg_valid),
    .bias_cfg_ready(bias_cfg_ready_48),
    .bias_cfg_address(bias_cfg_address),
    .bias_cfg_data(bias_cfg_data),

    .result_valid(result_valid_48),
    .result_ready(result_ready_48),
    .result_data(result_data_48),
    .result_index(result_index_48),
    .result_last(result_last_48),
    .result_tag(result_tag_48),

    .busy(busy_48),
    .done(done_48),
    .final_buffer_select(final_buffer_select_48),

    .error_valid(error_valid_48),
    .error_ready(error_ready_48),
    .error_code(error_code_48)
  );

  mlp_sequence_controller #(
    .MAX_LAYERS(MAX_LAYERS),
    .MAX_IN_DIM(MAX_IN_DIM),
    .MAX_OUT_DIM(MAX_OUT_DIM),
    .NUM_PE(NUM_PE),
    .ACC_WIDTH(32)
  ) dut_acc32 (
    .clk(clk),
    .rst(rst),

    .descriptor_cfg_valid(descriptor_cfg_valid),
    .descriptor_cfg_ready(descriptor_cfg_ready_32),
    .descriptor_cfg_index(descriptor_cfg_index),
    .descriptor_cfg_data(descriptor_cfg_data),

    .start_valid(start_valid_32),
    .start_ready(start_ready_32),
    .layer_count(layer_count),
    .initial_buffer_select(initial_buffer_select),

    .act_load_valid(act_load_valid),
    .act_load_ready(act_load_ready_32),
    .act_load_buffer_select(act_load_buffer_select),
    .act_load_chunk_index(act_load_chunk_index),
    .act_load_lane_mask(act_load_lane_mask),
    .act_load_data(act_load_data),

    .weight_cfg_valid(weight_cfg_valid),
    .weight_cfg_ready(weight_cfg_ready_32),
    .weight_cfg_address(weight_cfg_address),
    .weight_cfg_data(weight_cfg_data),

    .bias_cfg_valid(bias_cfg_valid),
    .bias_cfg_ready(bias_cfg_ready_32),
    .bias_cfg_address(bias_cfg_address),
    .bias_cfg_data(bias_cfg_data),

    .result_valid(result_valid_32),
    .result_ready(result_ready_32),
    .result_data(result_data_32),
    .result_index(result_index_32),
    .result_last(result_last_32),
    .result_tag(result_tag_32),

    .busy(busy_32),
    .done(done_32),
    .final_buffer_select(final_buffer_select_32),

    .error_valid(error_valid_32),
    .error_ready(error_ready_32),
    .error_code(error_code_32)
  );

  always #5 clk = ~clk;

  initial begin : timeout_guard
    #2000000;
    $display("tb_mlp_sequence_controller: FAIL - global timeout");
    $fatal(1, "tb_mlp_sequence_controller global timeout");
  end

  function automatic integer case_layer_count(input integer index);
    begin
      case (index)
        0: case_layer_count = 1;
        1: case_layer_count = 2;
        2: case_layer_count = 3;
        3: case_layer_count = 4;
        4: case_layer_count = 2;
        5: case_layer_count = 2;
        6: case_layer_count = 2;
        7: case_layer_count = 2;
        8: case_layer_count = 1;
        9: case_layer_count = 1;
        10: case_layer_count = 1;
        11: case_layer_count = 0;
        12: case_layer_count = 5;
        13: case_layer_count = 2;
        14: case_layer_count = 2;
        15: case_layer_count = 1;
        16: case_layer_count = 1;
        17: case_layer_count = 1;
        18: case_layer_count = 1;
        19: case_layer_count = 1;
        default: case_layer_count = 0;
      endcase
    end
  endfunction

  function automatic integer case_uses_acc32(input integer index);
    begin
      case_uses_acc32 = ((index == 0) || (index == 9));
    end
  endfunction

  function automatic integer descriptor_should_load(
      input integer index,
      input integer layer_index
  );
    integer count;
    begin
      count = case_layer_count(index);

      if ((index == 11) || (index == 12))
        descriptor_should_load = 0;
      else if (index == 13)
        descriptor_should_load = (layer_index == 0);
      else
        descriptor_should_load =
            ((layer_index >= 0) && (layer_index < count));
    end
  endfunction

  function automatic logic [3:0] expected_error_code(
      input integer index
  );
    begin
      case (index)
        11: expected_error_code = ERROR_BAD_LAYER_COUNT;
        12: expected_error_code = ERROR_BAD_LAYER_COUNT;
        13: expected_error_code = ERROR_MISSING_DESCRIPTOR;
        14: expected_error_code = ERROR_DIMENSION_MISMATCH;
        15: expected_error_code = ERROR_BAD_DIMENSION;
        16: expected_error_code = ERROR_BAD_DIMENSION;
        17: expected_error_code = ERROR_WEIGHT_RANGE;
        18: expected_error_code = ERROR_BIAS_RANGE;
        19: expected_error_code = ERROR_BAD_SHIFT;
        default: expected_error_code = 4'h0;
      endcase
    end
  endfunction

  task automatic apply_reset;
    begin
      @(negedge clk);
      rst = 1'b1;
      start_valid_48 = 1'b0;
      start_valid_32 = 1'b0;
      descriptor_cfg_valid = 1'b0;
      act_load_valid = 1'b0;
      weight_cfg_valid = 1'b0;
      bias_cfg_valid = 1'b0;
      result_ready_48 = 1'b0;
      result_ready_32 = 1'b0;
      error_ready_48 = 1'b1;
      error_ready_32 = 1'b1;
      repeat (4) @(posedge clk);
      @(negedge clk);
      rst = 1'b0;
    end
  endtask

  task automatic write_descriptor_both(
      input integer layer_index,
      input logic [DESCRIPTOR_WIDTH-1:0] descriptor_word
  );
    begin
      @(negedge clk);
      descriptor_cfg_index =
          layer_index[LAYER_INDEX_WIDTH-1:0];
      descriptor_cfg_data = descriptor_word;
      descriptor_cfg_valid = 1'b1;

      while (!descriptor_cfg_ready_all)
        @(posedge clk);

      @(negedge clk);
      descriptor_cfg_valid = 1'b0;
    end
  endtask

  task automatic write_weight_both(
      input integer address,
      input logic [WEIGHT_WIDTH-1:0] value
  );
    begin
      @(negedge clk);
      weight_cfg_address = address;
      weight_cfg_data = value;
      weight_cfg_valid = 1'b1;

      while (!weight_cfg_ready_all)
        @(posedge clk);

      @(negedge clk);
      weight_cfg_valid = 1'b0;
    end
  endtask

  task automatic write_bias_both(
      input integer address,
      input logic [BIAS_WIDTH-1:0] value
  );
    begin
      @(negedge clk);
      bias_cfg_address = address;
      bias_cfg_data = value;
      bias_cfg_valid = 1'b1;

      while (!bias_cfg_ready_all)
        @(posedge clk);

      @(negedge clk);
      bias_cfg_valid = 1'b0;
    end
  endtask

  task automatic load_global_parameters;
    integer address;
    begin
      for (address = 0;
           address < WEIGHT_VALUE_COUNT;
           address = address + 1)
        write_weight_both(address, weight_values[address]);

      for (address = 0;
           address < BIAS_VALUE_COUNT;
           address = address + 1)
        write_bias_both(address, bias_values[address]);

      $display(
          "tb_mlp_sequence_controller: loaded %0d weights and %0d biases",
          WEIGHT_VALUE_COUNT,
          BIAS_VALUE_COUNT);
    end
  endtask

  task automatic load_case_descriptors(input integer index);
    integer layer_index;
    begin
      for (layer_index = 0;
           layer_index < MAX_LAYERS;
           layer_index = layer_index + 1) begin
        if (descriptor_should_load(index, layer_index)) begin
          write_descriptor_both(
              layer_index,
              descriptor_rows[index*MAX_LAYERS + layer_index]);
        end
      end
    end
  endtask

  task automatic load_case_input(input integer index);
    integer in_dim;
    integer chunk_count;
    integer chunk_index;
    integer lane_index;
    integer element_index;
    begin
      in_dim =
          descriptor_rows[index*MAX_LAYERS][0 +: 11];
      chunk_count = (in_dim + NUM_PE - 1)/NUM_PE;

      for (chunk_index = 0;
           chunk_index < chunk_count;
           chunk_index = chunk_index + 1) begin
        @(negedge clk);

        act_load_buffer_select = 1'b0;
        act_load_chunk_index =
            chunk_index[ACT_CHUNK_ADDR_WIDTH-1:0];
        act_load_lane_mask = '0;
        act_load_data = '0;

        for (lane_index = 0;
             lane_index < NUM_PE;
             lane_index = lane_index + 1) begin
          element_index = chunk_index*NUM_PE + lane_index;
          if (element_index < in_dim) begin
            act_load_lane_mask[lane_index] = 1'b1;
            act_load_data[
                lane_index*INPUT_WIDTH +: INPUT_WIDTH] =
                input_rows[index][
                    element_index*INPUT_WIDTH +: INPUT_WIDTH];
          end
        end

        act_load_valid = 1'b1;
        while (!act_load_ready_all)
          @(posedge clk);

        @(negedge clk);
        act_load_valid = 1'b0;
      end
    end
  endtask

  task automatic start_selected_controller(
      input integer use_acc32
  );
    begin
      @(negedge clk);

      if (use_acc32)
        start_valid_32 = 1'b1;
      else
        start_valid_48 = 1'b1;

      if (use_acc32) begin
        while (!start_ready_32)
          @(posedge clk);
      end else begin
        while (!start_ready_48)
          @(posedge clk);
      end

      @(negedge clk);
      start_valid_48 = 1'b0;
      start_valid_32 = 1'b0;
    end
  endtask

  task automatic run_valid_case(input integer index);
    integer count;
    integer use_acc32;
    integer final_descriptor_row;
    integer expected_out_dim;
    integer received;
    integer local_cycles;
    integer dense_done_count;
    logic selected_valid;
    logic selected_ready;
    logic selected_last;
    logic selected_done;
    logic selected_error_valid;
    logic selected_final_buffer;
    logic selected_dense_done;
    logic selected_final_layer;
    logic signed [OUTPUT_WIDTH-1:0] selected_data;
    logic signed [OUTPUT_WIDTH-1:0] expected_data;
    logic [OUT_INDEX_WIDTH-1:0] selected_index;
    logic [7:0] selected_tag;
    begin
      count = case_layer_count(index);
      use_acc32 = case_uses_acc32(index);
      final_descriptor_row = index*MAX_LAYERS + count - 1;
      expected_out_dim =
          descriptor_rows[final_descriptor_row][11 +: 11];

      load_case_descriptors(index);
      load_case_input(index);

      layer_count = count[LAYER_COUNT_WIDTH-1:0];
      initial_buffer_select = 1'b0;
      error_ready_48 = 1'b1;
      error_ready_32 = 1'b1;
      result_ready_48 = !use_acc32;
      result_ready_32 = use_acc32;

      start_selected_controller(use_acc32);

      received = 0;
      local_cycles = 0;
      dense_done_count = 0;
      selected_done = 1'b0;

      while (!selected_done) begin
        @(posedge clk);

        if (use_acc32) begin
          selected_valid = result_valid_32;
          selected_ready = result_ready_32;
          selected_data = result_data_32;
          selected_index = result_index_32;
          selected_last = result_last_32;
          selected_tag = result_tag_32;
          selected_done = done_32;
          selected_error_valid = error_valid_32;
          selected_final_buffer = final_buffer_select_32;
          selected_dense_done = dut_acc32.dense_job_done;
          selected_final_layer = dut_acc32.final_layer_active;
        end else begin
          selected_valid = result_valid_48;
          selected_ready = result_ready_48;
          selected_data = result_data_48;
          selected_index = result_index_48;
          selected_last = result_last_48;
          selected_tag = result_tag_48;
          selected_done = done_48;
          selected_error_valid = error_valid_48;
          selected_final_buffer = final_buffer_select_48;
          selected_dense_done = dut_acc48.dense_job_done;
          selected_final_layer = dut_acc48.final_layer_active;
        end

        if (selected_dense_done) begin
          if (selected_final_layer !== (dense_done_count == count-1))
            $fatal(
                1,
                "case %0d dense completion %0d final-layer mismatch",
                index,
                dense_done_count);
          dense_done_count = dense_done_count + 1;
        end

        if (selected_error_valid)
          $fatal(
              1,
              "case %0d: unexpected controller error",
              index);

        if (selected_valid && selected_ready) begin
          if (received >= expected_out_dim)
            $fatal(
                1,
                "case %0d: received too many outputs",
                index);

          expected_data = $signed(
              expected_output_rows[index][
                  received*OUTPUT_WIDTH +: OUTPUT_WIDTH]);

          if (selected_data !== expected_data)
            $fatal(
                1,
                "case %0d output %0d mismatch: expected %0d got %0d",
                index,
                received,
                expected_data,
                selected_data);

          if (selected_index !==
              received[OUT_INDEX_WIDTH-1:0])
            $fatal(
                1,
                "case %0d output index mismatch: expected %0d got %0d",
                index,
                received,
                selected_index);

          if (selected_last !==
              (received == expected_out_dim-1))
            $fatal(
                1,
                "case %0d output %0d last mismatch",
                index,
                received);

          if (selected_tag !== count-1)
            $fatal(
                1,
                "case %0d tag mismatch: expected %0d got %0d",
                index,
                count-1,
                selected_tag);

          received = received + 1;
        end

        local_cycles = local_cycles + 1;
        if (local_cycles > 500000)
          $fatal(
              1,
              "case %0d: valid-case timeout",
              index);
      end

      if (received != expected_out_dim)
        $fatal(
            1,
            "case %0d output count mismatch: expected %0d got %0d",
            index,
            expected_out_dim,
            received);

      if (dense_done_count != count)
        $fatal(
            1,
            "case %0d dense completion count mismatch: expected %0d got %0d",
            index,
            count,
            dense_done_count);

      if (selected_final_buffer !== count[0])
        $fatal(
            1,
            "case %0d final buffer mismatch: expected %0d got %0d",
            index,
            count[0],
            selected_final_buffer);

      result_ready_48 = 1'b0;
      result_ready_32 = 1'b0;

      $display(
          "tb_mlp_sequence_controller: valid case %0d PASS layers=%0d acc=%0d outputs=%0d",
          index,
          count,
          use_acc32 ? 32 : 48,
          expected_out_dim);
    end
  endtask

  task automatic run_invalid_case(input integer index);
    integer count;
    integer local_cycles;
    logic [3:0] expected_code;
    begin
      apply_reset();
      load_case_descriptors(index);

      count = case_layer_count(index);
      expected_code = expected_error_code(index);
      layer_count = count[LAYER_COUNT_WIDTH-1:0];
      initial_buffer_select = 1'b0;

      error_ready_48 = 1'b0;
      error_ready_32 = 1'b1;
      result_ready_48 = 1'b0;
      result_ready_32 = 1'b0;

      start_selected_controller(0);

      local_cycles = 0;
      while (!error_valid_48) begin
        @(posedge clk);
        local_cycles = local_cycles + 1;

        if (done_48)
          $fatal(
              1,
              "case %0d: invalid case incorrectly completed",
              index);

        if (local_cycles > 100)
          $fatal(
              1,
              "case %0d: invalid-case timeout",
              index);
      end

      if (error_code_48 !== expected_code)
        $fatal(
            1,
            "case %0d error mismatch: expected %0d got %0d",
            index,
            expected_code,
            error_code_48);

      @(negedge clk);
      error_ready_48 = 1'b1;
      @(posedge clk);
      @(negedge clk);

      $display(
          "tb_mlp_sequence_controller: invalid case %0d PASS error=%0d",
          index,
          expected_code);
    end
  endtask

  always @(posedge clk) begin
    if (rst)
      global_cycle_count <= 0;
    else
      global_cycle_count <= global_cycle_count + 1;

    if (!rst && global_cycle_count > 2000000)
      $fatal(
          1,
          "tb_mlp_sequence_controller: GLOBAL TIMEOUT");
  end

  initial begin
    $readmemh(
        "tests/vectors/stage2b_inputs.hex",
        input_rows);
    $readmemh(
        "tests/vectors/stage2b_weights.hex",
        weight_values);
    $readmemh(
        "tests/vectors/stage2b_biases.hex",
        bias_values);
    $readmemh(
        "tests/vectors/stage2b_descriptors.hex",
        descriptor_rows);
    $readmemh(
        "tests/expected/stage2b_final_outputs.hex",
        expected_output_rows);

    clk = 1'b0;
    rst = 1'b1;

    descriptor_cfg_valid = 1'b0;
    descriptor_cfg_index = '0;
    descriptor_cfg_data = '0;

    start_valid_48 = 1'b0;
    start_valid_32 = 1'b0;
    layer_count = '0;
    initial_buffer_select = 1'b0;

    act_load_valid = 1'b0;
    act_load_buffer_select = 1'b0;
    act_load_chunk_index = '0;
    act_load_lane_mask = '0;
    act_load_data = '0;

    weight_cfg_valid = 1'b0;
    weight_cfg_address = '0;
    weight_cfg_data = '0;

    bias_cfg_valid = 1'b0;
    bias_cfg_address = '0;
    bias_cfg_data = '0;

    result_ready_48 = 1'b0;
    result_ready_32 = 1'b0;
    error_ready_48 = 1'b1;
    error_ready_32 = 1'b1;
    global_cycle_count = 0;

    repeat (4) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;

    load_global_parameters();

    for (case_index = 0;
         case_index < VALID_CASE_COUNT;
         case_index = case_index + 1)
      run_valid_case(case_index);

    for (case_index = VALID_CASE_COUNT;
         case_index < CASE_COUNT;
         case_index = case_index + 1)
      run_invalid_case(case_index);

    $display(
        "tb_mlp_sequence_controller: PASS valid=11 invalid=9 total=20");
    repeat (4) @(posedge clk);
    $finish;
  end

endmodule
