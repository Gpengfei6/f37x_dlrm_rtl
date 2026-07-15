`timescale 1ns/1ps

module banked_activation_buffer #(
  parameter integer MAX_DIM    = 1024,
  parameter integer NUM_BANKS  = 16,
  parameter integer DATA_WIDTH = 16,
  parameter integer BANK_DEPTH = (MAX_DIM+NUM_BANKS-1)/NUM_BANKS,
  parameter integer CHUNK_ADDR_WIDTH =
      (BANK_DEPTH <= 1) ? 1 : $clog2(BANK_DEPTH),
  parameter integer INDEX_WIDTH = (MAX_DIM <= 1) ? 1 : $clog2(MAX_DIM)
) (
  input  logic                                  clk,
  input  logic                                  rst,

  input  logic                                  load_valid,
  output logic                                  load_ready,
  input  logic [CHUNK_ADDR_WIDTH-1:0]           load_chunk_index,
  input  logic [NUM_BANKS-1:0]                  load_lane_mask,
  input  logic [NUM_BANKS*DATA_WIDTH-1:0]       load_data,

  input  logic                                  read_req_valid,
  output logic                                  read_req_ready,
  input  logic [CHUNK_ADDR_WIDTH-1:0]           read_req_chunk_index,
  output logic                                  read_rsp_valid,
  input  logic                                  read_rsp_ready,
  output logic [NUM_BANKS*DATA_WIDTH-1:0]       read_rsp_data,

  input  logic                                  scalar_write_valid,
  output logic                                  scalar_write_ready,
  input  logic [INDEX_WIDTH-1:0]                scalar_write_index,
  input  logic signed [DATA_WIDTH-1:0]          scalar_write_data,
  output logic                                  access_error
);
  logic signed [DATA_WIDTH-1:0] bank_memory
      [0:NUM_BANKS-1][0:BANK_DEPTH-1];

  assign scalar_write_ready = 1'b1;
  assign load_ready = !scalar_write_valid;
  assign read_req_ready = !read_rsp_valid || read_rsp_ready;

  always_ff @(posedge clk) begin : response_and_memory
    integer read_lane;
    integer write_lane;
    if (rst) begin
      read_rsp_valid <= 1'b0;
      read_rsp_data <= '0;
      access_error <= 1'b0;
    end else begin
      if (read_req_ready) begin
        read_rsp_valid <= read_req_valid;
        if (read_req_valid) begin
          if (read_req_chunk_index < BANK_DEPTH) begin
            for (read_lane = 0; read_lane < NUM_BANKS;
                 read_lane = read_lane + 1)
              read_rsp_data[read_lane*DATA_WIDTH +: DATA_WIDTH] <=
                  bank_memory[read_lane][read_req_chunk_index];
          end else begin
            read_rsp_data <= '0;
            access_error <= 1'b1;
          end
        end
      end

      if (load_valid && load_ready) begin
        if (load_chunk_index < BANK_DEPTH) begin
          for (write_lane = 0; write_lane < NUM_BANKS;
               write_lane = write_lane + 1)
            if (load_lane_mask[write_lane])
              bank_memory[write_lane][load_chunk_index] <=
                  load_data[write_lane*DATA_WIDTH +: DATA_WIDTH];
        end else begin
          access_error <= 1'b1;
        end
      end

      if (scalar_write_valid && scalar_write_ready) begin
        if (scalar_write_index < MAX_DIM)
          bank_memory[scalar_write_index % NUM_BANKS]
                     [scalar_write_index / NUM_BANKS] <= scalar_write_data;
        else
          access_error <= 1'b1;
      end
    end
  end

  initial begin
    if (MAX_DIM <= 0 || NUM_BANKS <= 0 || DATA_WIDTH <= 0)
      $error("banked_activation_buffer parameters must be positive");
    if ((NUM_BANKS & (NUM_BANKS-1)) != 0)
      $error("banked_activation_buffer NUM_BANKS must be a power of two");
  end
endmodule
