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
  logic [NUM_BANKS*DATA_WIDTH-1:0] bank_read_data;
  logic read_rsp_error;

  assign scalar_write_ready = 1'b1;
  assign load_ready = !scalar_write_valid;
  assign read_req_ready = !read_rsp_valid || read_rsp_ready;

  always_ff @(posedge clk) begin : response_control
    if (rst) begin
      read_rsp_valid <= 1'b0;
      read_rsp_error <= 1'b0;
      access_error <= 1'b0;
    end else begin
      if (read_req_ready) begin
        read_rsp_valid <= read_req_valid;
        read_rsp_error <=
            read_req_valid && (read_req_chunk_index >= BANK_DEPTH);
        if (read_req_valid && (read_req_chunk_index >= BANK_DEPTH))
            access_error <= 1'b1;
      end

      if (load_valid && load_ready && (load_chunk_index >= BANK_DEPTH))
          access_error <= 1'b1;

      if (scalar_write_valid && scalar_write_ready &&
          (scalar_write_index >= MAX_DIM))
          access_error <= 1'b1;
    end
  end

  assign read_rsp_data = read_rsp_error ? '0 : bank_read_data;

  genvar bank_index;
  generate
    for (bank_index = 0; bank_index < NUM_BANKS;
         bank_index = bank_index + 1) begin : activation_bank
      (* ram_style = "block" *)
      logic signed [DATA_WIDTH-1:0] memory [0:BANK_DEPTH-1];
      logic signed [DATA_WIDTH-1:0] read_data;
      logic write_enable;
      logic [CHUNK_ADDR_WIDTH-1:0] write_address;
      logic signed [DATA_WIDTH-1:0] write_data;

      always_comb begin : select_write_port
        write_enable = 1'b0;
        write_address = '0;
        write_data = '0;

        if (load_valid && load_ready &&
            (load_chunk_index < BANK_DEPTH) &&
            load_lane_mask[bank_index]) begin
          write_enable = 1'b1;
          write_address = load_chunk_index;
          write_data = load_data[bank_index*DATA_WIDTH +: DATA_WIDTH];
        end else if (scalar_write_valid && scalar_write_ready &&
                     (scalar_write_index < MAX_DIM) &&
                     ((scalar_write_index % NUM_BANKS) == bank_index)) begin
          write_enable = 1'b1;
          write_address = scalar_write_index / NUM_BANKS;
          write_data = scalar_write_data;
        end
      end

      always_ff @(posedge clk) begin : bank_ports
        if (write_enable)
          memory[write_address] <= write_data;

        if (rst) begin
          read_data <= '0;
        end else if (read_req_valid && read_req_ready &&
                     (read_req_chunk_index < BANK_DEPTH)) begin
          read_data <= memory[read_req_chunk_index];
        end
      end

      assign bank_read_data[bank_index*DATA_WIDTH +: DATA_WIDTH] = read_data;
    end
  endgenerate

  initial begin
    if (MAX_DIM <= 0 || NUM_BANKS <= 0 || DATA_WIDTH <= 0)
      $error("banked_activation_buffer parameters must be positive");
    if ((NUM_BANKS & (NUM_BANKS-1)) != 0)
      $error("banked_activation_buffer NUM_BANKS must be a power of two");
  end
endmodule
