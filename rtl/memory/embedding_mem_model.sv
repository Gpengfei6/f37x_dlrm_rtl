`timescale 1ns/1ps

module embedding_mem_model #(
  parameter integer NUM_ROWS   = 32,
  parameter integer EMBED_DIM  = 8,
  parameter integer DATA_WIDTH = 8,
  parameter integer ID_WIDTH   = (NUM_ROWS <= 1) ? 1 : $clog2(NUM_ROWS),
  parameter         INIT_FILE  = ""
) (
  input  logic                              clk,
  input  logic                              rst,
  input  logic                              req_valid,
  output logic                              req_ready,
  input  logic [ID_WIDTH-1:0]               req_id,
  output logic                              rsp_valid,
  input  logic                              rsp_ready,
  output logic signed [EMBED_DIM*DATA_WIDTH-1:0] rsp_data
);
  logic signed [DATA_WIDTH-1:0] memory [0:NUM_ROWS*EMBED_DIM-1];
  integer index;
  integer lane;

  assign req_ready = !rsp_valid || rsp_ready;

  initial begin
    for (index = 0; index < NUM_ROWS*EMBED_DIM; index = index + 1)
      memory[index] = '0;
    if (INIT_FILE != "")
      $readmemh(INIT_FILE, memory);
    if (NUM_ROWS <= 0 || EMBED_DIM <= 0 || DATA_WIDTH <= 0)
      $error("embedding_mem_model parameters must be positive");
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      rsp_valid <= 1'b0;
      rsp_data <= '0;
    end else if (req_ready) begin
      rsp_valid <= req_valid;
      if (req_valid) begin
        if (req_id < NUM_ROWS) begin
          for (lane = 0; lane < EMBED_DIM; lane = lane + 1)
            rsp_data[lane*DATA_WIDTH +: DATA_WIDTH] <=
                memory[req_id*EMBED_DIM + lane];
        end else begin
          rsp_data <= '0;
        end
      end
    end
  end
endmodule
