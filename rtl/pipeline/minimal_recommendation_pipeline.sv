`timescale 1ns/1ps

module minimal_recommendation_pipeline #(
  parameter integer NUM_EMBED_ROWS = 32,
  parameter integer EMBED_DIM      = 8,
  parameter integer NUM_LOOKUPS    = 4,
  parameter integer DENSE_OUT_DIM  = 4,
  parameter integer DATA_WIDTH     = 8,
  parameter integer WEIGHT_WIDTH   = 8,
  parameter integer BIAS_WIDTH     = 24,
  parameter integer ACC_WIDTH      = 32,
  parameter integer OUTPUT_WIDTH   = 16,
  parameter integer OUTPUT_SHIFT   = 4,
  parameter integer ID_WIDTH       = (NUM_EMBED_ROWS <= 1) ? 1 : $clog2(NUM_EMBED_ROWS),
  parameter integer AGG_WIDTH      = DATA_WIDTH +
      ((NUM_LOOKUPS <= 1) ? 0 : $clog2(NUM_LOOKUPS)),
  parameter EMBED_INIT_FILE = "",
  parameter WEIGHT_INIT_FILE = "",
  parameter BIAS_INIT_FILE = ""
) (
  input  logic                                      clk,
  input  logic                                      rst,
  input  logic                                      in_valid,
  output logic                                      in_ready,
  input  logic [NUM_LOOKUPS*ID_WIDTH-1:0]           in_ids,
  output logic                                      out_valid,
  input  logic                                      out_ready,
  output logic signed [DENSE_OUT_DIM*OUTPUT_WIDTH-1:0] out_data
);
  localparam integer LOOKUP_INDEX_WIDTH =
      (NUM_LOOKUPS <= 1) ? 1 : $clog2(NUM_LOOKUPS);

  localparam logic [2:0] STATE_IDLE       = 3'd0;
  localparam logic [2:0] STATE_READ_REQ   = 3'd1;
  localparam logic [2:0] STATE_READ_RSP   = 3'd2;
  localparam logic [2:0] STATE_DENSE_SEND = 3'd3;
  localparam logic [2:0] STATE_DENSE_WAIT = 3'd4;

  logic [2:0] state;
  logic [NUM_LOOKUPS*ID_WIDTH-1:0] id_buffer;
  logic [LOOKUP_INDEX_WIDTH-1:0] lookup_index;
  logic signed [AGG_WIDTH-1:0] aggregate_buffer [0:EMBED_DIM-1];
  logic signed [EMBED_DIM*AGG_WIDTH-1:0] dense_input;

  logic mem_req_valid;
  logic mem_req_ready;
  logic [ID_WIDTH-1:0] mem_req_id;
  logic mem_rsp_valid;
  logic mem_rsp_ready;
  logic signed [EMBED_DIM*DATA_WIDTH-1:0] mem_rsp_data;

  logic dense_in_valid;
  logic dense_in_ready;
  logic dense_out_valid;
  logic dense_out_ready;
  logic signed [DENSE_OUT_DIM*OUTPUT_WIDTH-1:0] dense_out_data;

  integer lane;
  genvar pack_lane;

  assign in_ready = (state == STATE_IDLE);
  assign mem_req_valid = (state == STATE_READ_REQ);
  assign mem_req_id = id_buffer[lookup_index*ID_WIDTH +: ID_WIDTH];
  assign mem_rsp_ready = (state == STATE_READ_RSP);
  assign dense_in_valid = (state == STATE_DENSE_SEND);
  assign dense_out_ready = (state == STATE_DENSE_WAIT) && out_ready;
  assign out_valid = (state == STATE_DENSE_WAIT) && dense_out_valid;
  assign out_data = dense_out_data;

  generate
    for (pack_lane = 0; pack_lane < EMBED_DIM; pack_lane = pack_lane + 1)
      assign dense_input[pack_lane*AGG_WIDTH +: AGG_WIDTH] =
          aggregate_buffer[pack_lane];
  endgenerate

  embedding_mem_model #(
    .NUM_ROWS(NUM_EMBED_ROWS),
    .EMBED_DIM(EMBED_DIM),
    .DATA_WIDTH(DATA_WIDTH),
    .ID_WIDTH(ID_WIDTH),
    .INIT_FILE(EMBED_INIT_FILE)
  ) u_embedding_memory (
    .clk(clk),
    .rst(rst),
    .req_valid(mem_req_valid),
    .req_ready(mem_req_ready),
    .req_id(mem_req_id),
    .rsp_valid(mem_rsp_valid),
    .rsp_ready(mem_rsp_ready),
    .rsp_data(mem_rsp_data)
  );

  dense_layer_core #(
    .IN_DIM(EMBED_DIM),
    .OUT_DIM(DENSE_OUT_DIM),
    .IN_WIDTH(AGG_WIDTH),
    .WEIGHT_WIDTH(WEIGHT_WIDTH),
    .BIAS_WIDTH(BIAS_WIDTH),
    .ACC_WIDTH(ACC_WIDTH),
    .OUTPUT_WIDTH(OUTPUT_WIDTH),
    .OUTPUT_SHIFT(OUTPUT_SHIFT),
    .WEIGHT_INIT_FILE(WEIGHT_INIT_FILE),
    .BIAS_INIT_FILE(BIAS_INIT_FILE)
  ) u_dense_layer (
    .clk(clk),
    .rst(rst),
    .in_valid(dense_in_valid),
    .in_ready(dense_in_ready),
    .in_data(dense_input),
    .out_valid(dense_out_valid),
    .out_ready(dense_out_ready),
    .out_data(dense_out_data)
  );

  always_ff @(posedge clk) begin
    if (rst) begin
      state <= STATE_IDLE;
      id_buffer <= '0;
      lookup_index <= '0;
      for (lane = 0; lane < EMBED_DIM; lane = lane + 1)
        aggregate_buffer[lane] <= '0;
    end else begin
      case (state)
        STATE_IDLE: begin
          if (in_valid && in_ready) begin
            id_buffer <= in_ids;
            lookup_index <= '0;
            for (lane = 0; lane < EMBED_DIM; lane = lane + 1)
              aggregate_buffer[lane] <= '0;
            state <= STATE_READ_REQ;
          end
        end
        STATE_READ_REQ: begin
          if (mem_req_valid && mem_req_ready)
            state <= STATE_READ_RSP;
        end
        STATE_READ_RSP: begin
          if (mem_rsp_valid && mem_rsp_ready) begin
            for (lane = 0; lane < EMBED_DIM; lane = lane + 1)
              aggregate_buffer[lane] <= aggregate_buffer[lane] +
                  {{(AGG_WIDTH-DATA_WIDTH){
                      mem_rsp_data[lane*DATA_WIDTH + DATA_WIDTH-1]}},
                    mem_rsp_data[lane*DATA_WIDTH +: DATA_WIDTH]};
            if (lookup_index == NUM_LOOKUPS-1) begin
              state <= STATE_DENSE_SEND;
            end else begin
              lookup_index <= lookup_index + 1'b1;
              state <= STATE_READ_REQ;
            end
          end
        end
        STATE_DENSE_SEND: begin
          if (dense_in_valid && dense_in_ready)
            state <= STATE_DENSE_WAIT;
        end
        STATE_DENSE_WAIT: begin
          if (dense_out_valid && dense_out_ready)
            state <= STATE_IDLE;
        end
        default: state <= STATE_IDLE;
      endcase
    end
  end

  initial begin
    if (NUM_EMBED_ROWS <= 0 || EMBED_DIM <= 0 || NUM_LOOKUPS <= 0 ||
        DENSE_OUT_DIM <= 0)
      $error("minimal_recommendation_pipeline dimensions must be positive");
    if (AGG_WIDTH < DATA_WIDTH)
      $error("minimal_recommendation_pipeline AGG_WIDTH is too small");
  end
endmodule
