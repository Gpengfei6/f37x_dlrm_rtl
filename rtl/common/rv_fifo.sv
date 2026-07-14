module rv_fifo #(
  parameter integer DATA_WIDTH = 8,
  parameter integer DEPTH      = 4
) (
  input  logic                         clk,
  input  logic                         rst,
  input  logic                         in_valid,
  output logic                         in_ready,
  input  logic [DATA_WIDTH-1:0]        in_data,
  output logic                         out_valid,
  input  logic                         out_ready,
  output logic [DATA_WIDTH-1:0]        out_data,
  output logic                         full,
  output logic                         empty,
  output logic [$clog2(DEPTH+1)-1:0]   count
);
  localparam integer PTR_WIDTH = (DEPTH <= 1) ? 1 : $clog2(DEPTH);

  logic [DATA_WIDTH-1:0] memory [0:DEPTH-1];
  logic [PTR_WIDTH-1:0] read_pointer;
  logic [PTR_WIDTH-1:0] write_pointer;
  logic push;
  logic pop;

  assign empty = (count == 0);
  assign full = (count == DEPTH);
  assign out_valid = !empty;
  assign out_data = memory[read_pointer];
  assign pop = out_valid && out_ready;
  // A pop frees the full FIFO on the same edge, so a replacement push is legal.
  assign in_ready = !full || pop;
  assign push = in_valid && in_ready;

  always_ff @(posedge clk) begin
    if (rst) begin
      read_pointer <= '0;
      write_pointer <= '0;
      count <= '0;
    end else begin
      if (push) begin
        memory[write_pointer] <= in_data;
        if (write_pointer == DEPTH-1)
          write_pointer <= '0;
        else
          write_pointer <= write_pointer + 1'b1;
      end
      if (pop) begin
        if (read_pointer == DEPTH-1)
          read_pointer <= '0;
        else
          read_pointer <= read_pointer + 1'b1;
      end
      case ({push, pop})
        2'b10: count <= count + 1'b1;
        2'b01: count <= count - 1'b1;
        default: count <= count;
      endcase
    end
  end

  initial begin
    if (DATA_WIDTH <= 0) $error("rv_fifo DATA_WIDTH must be positive");
    if (DEPTH <= 0) $error("rv_fifo DEPTH must be positive");
  end
endmodule

