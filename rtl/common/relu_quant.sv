module relu_quant #(
  parameter integer IN_WIDTH  = 32,
  parameter integer OUT_WIDTH = 16,
  parameter integer SHIFT     = 4
) (
  input  logic signed [IN_WIDTH-1:0]  in_data,
  output logic signed [OUT_WIDTH-1:0] out_data
);
  logic signed [OUT_WIDTH-1:0] quantized;

  saturating_round #(
    .IN_WIDTH(IN_WIDTH),
    .OUT_WIDTH(OUT_WIDTH),
    .SHIFT(SHIFT)
  ) u_saturating_round (
    .in_data(in_data),
    .out_data(quantized)
  );

  always_comb begin
    if (quantized < 0)
      out_data = '0;
    else
      out_data = quantized;
  end
endmodule

