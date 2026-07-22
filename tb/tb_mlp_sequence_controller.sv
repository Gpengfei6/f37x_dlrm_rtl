`timescale 1ns/1ps

module tb_mlp_sequence_controller;

  localparam integer MAX_LAYERS = 4;
  localparam integer MAX_IN_DIM = 1024;
  localparam integer MAX_OUT_DIM = 1024;
  localparam integer NUM_PE = 16;
  localparam integer INPUT_WIDTH = 16;
  localparam integer OUTPUT_WIDTH = 16;
  localparam integer OUT_INDEX_WIDTH = 10;
  localparam integer ACT_CHUNK_ADDR_WIDTH = 6;
  localparam integer LAYER_INDEX_WIDTH = 2;
  localparam integer LAYER_COUNT_WIDTH = 3;

  logic clk;
  logic rst;

  logic descriptor_cfg_valid;
  logic descriptor_cfg_ready;
  logic [LAYER_INDEX_WIDTH-1:0] descriptor_cfg_index;
  logic [95:0] descriptor_cfg_data;

  logic start_valid;
  logic start_ready;
  logic [LAYER_COUNT_WIDTH-1:0] layer_count;
  logic initial_buffer_select;

  logic act_load_valid;
  logic act_load_ready;
  logic act_load_buffer_select;
  logic [ACT_CHUNK_ADDR_WIDTH-1:0] act_load_chunk_index;
  logic [NUM_PE-1:0] act_load_lane_mask;
  logic [NUM_PE*INPUT_WIDTH-1:0] act_load_data;

  logic weight_cfg_valid;
  logic weight_cfg_ready;
  logic [31:0] weight_cfg_address;
  logic signed [7:0] weight_cfg_data;

  logic bias_cfg_valid;
  logic bias_cfg_ready;
  logic [31:0] bias_cfg_address;
  logic signed [23:0] bias_cfg_data;

  logic result_valid;
  logic result_ready;
  logic signed [OUTPUT_WIDTH-1:0] result_data;
  logic [OUT_INDEX_WIDTH-1:0] result_index;
  logic result_last;
  logic [7:0] result_tag;

  logic busy;
  logic done;
  logic final_buffer_select;

  logic error_valid;
  logic error_ready;
  logic [3:0] error_code;

  integer cycle_count;
  logic signed [OUTPUT_WIDTH-1:0] held_result_data;
  logic [OUT_INDEX_WIDTH-1:0] held_result_index;
  logic held_result_last;
  logic [7:0] held_result_tag;

  mlp_sequence_controller #(
    .MAX_LAYERS(MAX_LAYERS),
    .MAX_IN_DIM(MAX_IN_DIM),
    .MAX_OUT_DIM(MAX_OUT_DIM),
    .NUM_PE(NUM_PE)
  ) dut (
    .clk(clk),
    .rst(rst),

    .descriptor_cfg_valid(descriptor_cfg_valid),
    .descriptor_cfg_ready(descriptor_cfg_ready),
    .descriptor_cfg_index(descriptor_cfg_index),
    .descriptor_cfg_data(descriptor_cfg_data),

    .start_valid(start_valid),
    .start_ready(start_ready),
    .layer_count(layer_count),
    .initial_buffer_select(initial_buffer_select),

    .act_load_valid(act_load_valid),
    .act_load_ready(act_load_ready),
    .act_load_buffer_select(act_load_buffer_select),
    .act_load_chunk_index(act_load_chunk_index),
    .act_load_lane_mask(act_load_lane_mask),
    .act_load_data(act_load_data),

    .weight_cfg_valid(weight_cfg_valid),
    .weight_cfg_ready(weight_cfg_ready),
    .weight_cfg_address(weight_cfg_address),
    .weight_cfg_data(weight_cfg_data),

    .bias_cfg_valid(bias_cfg_valid),
    .bias_cfg_ready(bias_cfg_ready),
    .bias_cfg_address(bias_cfg_address),
    .bias_cfg_data(bias_cfg_data),

    .result_valid(result_valid),
    .result_ready(result_ready),
    .result_data(result_data),
    .result_index(result_index),
    .result_last(result_last),
    .result_tag(result_tag),

    .busy(busy),
    .done(done),
    .final_buffer_select(final_buffer_select),

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
    logic [95:0] descriptor_word;
    begin
      descriptor_word = '0;
      descriptor_word[0 +: 11] = in_dim[10:0];
      descriptor_word[11 +: 11] = out_dim[10:0];
      descriptor_word[22 +: 32] = weight_base[31:0];
      descriptor_word[54 +: 32] = bias_base[31:0];
      descriptor_word[86 +: 6] = output_shift[5:0];
      descriptor_word[92] = relu_enable[0];
      pack_descriptor = descriptor_word;
    end
  endfunction

  task automatic write_descriptor(
      input integer index,
      input logic [95:0] descriptor_word
  );
    begin
      @(negedge clk);
      descriptor_cfg_index = index[LAYER_INDEX_WIDTH-1:0];
      descriptor_cfg_data = descriptor_word;
      descriptor_cfg_valid = 1'b1;
      while (!descriptor_cfg_ready)
        @(posedge clk);
      @(negedge clk);
      descriptor_cfg_valid = 1'b0;
    end
  endtask

  task automatic write_weight(
      input integer address,
      input integer value
  );
    begin
      @(negedge clk);
      weight_cfg_address = address;
      weight_cfg_data = value;
      weight_cfg_valid = 1'b1;
      while (!weight_cfg_ready)
        @(posedge clk);
      @(negedge clk);
      weight_cfg_valid = 1'b0;
    end
  endtask

  task automatic write_bias(
      input integer address,
      input integer value
  );
    begin
      @(negedge clk);
      bias_cfg_address = address;
      bias_cfg_data = value;
      bias_cfg_valid = 1'b1;
      while (!bias_cfg_ready)
        @(posedge clk);
      @(negedge clk);
      bias_cfg_valid = 1'b0;
    end
  endtask

  task automatic write_activation_lane0(
      input integer value,
      input integer buffer_select
  );
    begin
      @(negedge clk);
      act_load_buffer_select = buffer_select[0];
      act_load_chunk_index = '0;
      act_load_lane_mask = 16'h0001;
      act_load_data = '0;
      act_load_data[0 +: INPUT_WIDTH] = value[INPUT_WIDTH-1:0];
      act_load_valid = 1'b1;
      while (!act_load_ready)
        @(posedge clk);
      @(negedge clk);
      act_load_valid = 1'b0;
    end
  endtask

  task automatic start_mlp;
    begin
      @(negedge clk);
      start_valid = 1'b1;
      while (!start_ready)
        @(posedge clk);
      @(negedge clk);
      start_valid = 1'b0;
    end
  endtask

  always @(posedge clk) begin
    if (rst)
      cycle_count <= 0;
    else
      cycle_count <= cycle_count + 1;

    if (!rst && cycle_count > 5000)
      $fatal(1, "tb_mlp_sequence_controller: TIMEOUT");

    if (error_valid)
      $fatal(1, "tb_mlp_sequence_controller: controller error_code=%0d",
             error_code);
  end

  initial begin
    clk = 1'b0;
    rst = 1'b1;

    descriptor_cfg_valid = 1'b0;
    descriptor_cfg_index = '0;
    descriptor_cfg_data = '0;

    start_valid = 1'b0;
    layer_count = 2;
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

    result_ready = 1'b0;
    error_ready = 1'b1;

    repeat (4) @(posedge clk);
    rst = 1'b0;

    write_descriptor(0, pack_descriptor(1, 1, 0, 0, 0, 0));
    write_descriptor(1, pack_descriptor(1, 1, 1, 1, 0, 0));

    write_weight(0, 2);
    write_weight(1, 3);

    write_bias(0, 1);
    write_bias(1, -2);

    write_activation_lane0(3, 0);

    start_mlp();

    wait (result_valid);

    held_result_data = result_data;
    held_result_index = result_index;
    held_result_last = result_last;
    held_result_tag = result_tag;

    repeat (3) begin
      @(posedge clk);
      if (!result_valid ||
          result_data !== held_result_data ||
          result_index !== held_result_index ||
          result_last !== held_result_last ||
          result_tag !== held_result_tag)
        $fatal(1,
            "tb_mlp_sequence_controller: output changed under backpressure");
    end

    if (held_result_data !== 16'sd19)
      $fatal(1,
          "tb_mlp_sequence_controller: expected result 19, got %0d",
          held_result_data);
    if (held_result_index !== 0)
      $fatal(1,
          "tb_mlp_sequence_controller: expected result_index 0, got %0d",
          held_result_index);
    if (!held_result_last)
      $fatal(1,
          "tb_mlp_sequence_controller: expected result_last=1");
    if (held_result_tag !== 8'd1)
      $fatal(1,
          "tb_mlp_sequence_controller: expected final layer tag 1, got %0d",
          held_result_tag);

    @(negedge clk);
    result_ready = 1'b1;

    @(posedge clk);
    @(negedge clk);
    result_ready = 1'b0;

    wait (done);

    if (final_buffer_select !== 1'b0)
      $fatal(1,
          "tb_mlp_sequence_controller: expected final buffer 0, got %0d",
          final_buffer_select);

    $display("tb_mlp_sequence_controller: PASS");
    repeat (3) @(posedge clk);
    $finish;
  end

endmodule
