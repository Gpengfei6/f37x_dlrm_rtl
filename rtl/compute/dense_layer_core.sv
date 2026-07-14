module dense_layer_core #(
  parameter integer IN_DIM       = 8,
  parameter integer OUT_DIM      = 4,
  parameter integer IN_WIDTH     = 10,
  parameter integer WEIGHT_WIDTH = 8,
  parameter integer BIAS_WIDTH   = 24,
  parameter integer ACC_WIDTH    = 32,
  parameter integer OUTPUT_WIDTH = 16,
  parameter integer OUTPUT_SHIFT = 4,
  parameter         WEIGHT_INIT_FILE = "",
  parameter         BIAS_INIT_FILE   = ""
) (
  input  logic                                  clk,
  input  logic                                  rst,
  input  logic                                  in_valid,
  output logic                                  in_ready,
  input  logic signed [IN_DIM*IN_WIDTH-1:0]      in_data,
  output logic                                  out_valid,
  input  logic                                  out_ready,
  output logic signed [OUT_DIM*OUTPUT_WIDTH-1:0] out_data
);
  localparam integer OUT_INDEX_WIDTH = (OUT_DIM <= 1) ? 1 : $clog2(OUT_DIM);

  localparam logic [2:0] STATE_IDLE = 3'd0;
  localparam logic [2:0] STATE_SEND_DOT = 3'd1;
  localparam logic [2:0] STATE_WAIT_DOT = 3'd2;
  localparam logic [2:0] STATE_OUTPUT = 3'd3;

  logic [2:0] state;
  logic [OUT_INDEX_WIDTH-1:0] output_index;
  logic signed [IN_DIM*IN_WIDTH-1:0] input_buffer;
  logic signed [OUTPUT_WIDTH-1:0] output_buffer [0:OUT_DIM-1];
  logic signed [WEIGHT_WIDTH-1:0] weight_memory [0:OUT_DIM*IN_DIM-1];
  logic signed [BIAS_WIDTH-1:0] bias_memory [0:OUT_DIM-1];

  logic dot_in_valid;
  logic dot_in_ready;
  logic signed [IN_DIM*WEIGHT_WIDTH-1:0] dot_weights;
  logic signed [BIAS_WIDTH-1:0] dot_bias;
  logic dot_out_valid;
  logic dot_out_ready;
  logic signed [ACC_WIDTH-1:0] dot_result;
  logic signed [OUTPUT_WIDTH-1:0] activated_result;

  integer index;
  integer pack_index;
  genvar output_lane;

  initial begin
    for (index = 0; index < OUT_DIM*IN_DIM; index = index + 1)
      weight_memory[index] = '0;
    for (index = 0; index < OUT_DIM; index = index + 1)
      bias_memory[index] = '0;
    if (WEIGHT_INIT_FILE != "")
      $readmemh(WEIGHT_INIT_FILE, weight_memory);
    if (BIAS_INIT_FILE != "")
      $readmemh(BIAS_INIT_FILE, bias_memory);
    if (IN_DIM <= 0 || OUT_DIM <= 0)
      $error("dense_layer_core dimensions must be positive");
  end

  always_comb begin
    dot_weights = '0;
    for (pack_index = 0; pack_index < IN_DIM; pack_index = pack_index + 1)
      dot_weights[pack_index*WEIGHT_WIDTH +: WEIGHT_WIDTH] =
          weight_memory[output_index*IN_DIM + pack_index];
    dot_bias = bias_memory[output_index];
  end

  dot_product_core #(
    .VEC_LEN(IN_DIM),
    .IN_WIDTH(IN_WIDTH),
    .WEIGHT_WIDTH(WEIGHT_WIDTH),
    .BIAS_WIDTH(BIAS_WIDTH),
    .ACC_WIDTH(ACC_WIDTH)
  ) u_dot_product (
    .clk(clk),
    .rst(rst),
    .in_valid(dot_in_valid),
    .in_ready(dot_in_ready),
    .in_data(input_buffer),
    .weight_data(dot_weights),
    .bias_data(dot_bias),
    .out_valid(dot_out_valid),
    .out_ready(dot_out_ready),
    .out_data(dot_result)
  );

  relu_quant #(
    .IN_WIDTH(ACC_WIDTH),
    .OUT_WIDTH(OUTPUT_WIDTH),
    .SHIFT(OUTPUT_SHIFT)
  ) u_relu_quant (
    .in_data(dot_result),
    .out_data(activated_result)
  );

  assign in_ready = (state == STATE_IDLE);
  assign dot_in_valid = (state == STATE_SEND_DOT);
  assign dot_out_ready = (state == STATE_WAIT_DOT);
  assign out_valid = (state == STATE_OUTPUT);

  generate
    for (output_lane = 0; output_lane < OUT_DIM; output_lane = output_lane + 1)
      assign out_data[output_lane*OUTPUT_WIDTH +: OUTPUT_WIDTH] =
          output_buffer[output_lane];
  endgenerate

  always_ff @(posedge clk) begin
    if (rst) begin
      state <= STATE_IDLE;
      output_index <= '0;
      input_buffer <= '0;
      for (index = 0; index < OUT_DIM; index = index + 1)
        output_buffer[index] <= '0;
    end else begin
      case (state)
        STATE_IDLE: begin
          if (in_valid && in_ready) begin
            input_buffer <= in_data;
            output_index <= '0;
            state <= STATE_SEND_DOT;
          end
        end
        STATE_SEND_DOT: begin
          if (dot_in_valid && dot_in_ready)
            state <= STATE_WAIT_DOT;
        end
        STATE_WAIT_DOT: begin
          if (dot_out_valid && dot_out_ready) begin
            output_buffer[output_index] <= activated_result;
            if (output_index == OUT_DIM-1) begin
              state <= STATE_OUTPUT;
            end else begin
              output_index <= output_index + 1'b1;
              state <= STATE_SEND_DOT;
            end
          end
        end
        STATE_OUTPUT: begin
          if (out_valid && out_ready)
            state <= STATE_IDLE;
        end
        default: state <= STATE_IDLE;
      endcase
    end
  end
endmodule

