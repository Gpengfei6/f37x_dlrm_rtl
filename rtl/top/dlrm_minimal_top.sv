module dlrm_minimal_top #(
  parameter integer NUM_EMBED_ROWS = dlrm_config_pkg::NUM_EMBED_ROWS,
  parameter integer EMBED_DIM      = dlrm_config_pkg::EMBED_DIM,
  parameter integer NUM_LOOKUPS    = dlrm_config_pkg::NUM_LOOKUPS,
  parameter integer DENSE_OUT_DIM  = dlrm_config_pkg::DENSE_OUT_DIM,
  parameter integer DATA_WIDTH     = dlrm_config_pkg::DATA_WIDTH,
  parameter integer WEIGHT_WIDTH   = dlrm_config_pkg::WEIGHT_WIDTH,
  parameter integer BIAS_WIDTH     = dlrm_config_pkg::BIAS_WIDTH,
  parameter integer ACC_WIDTH      = dlrm_config_pkg::ACC_WIDTH,
  parameter integer OUTPUT_WIDTH   = dlrm_config_pkg::OUTPUT_WIDTH,
  parameter integer OUTPUT_SHIFT   = dlrm_config_pkg::OUTPUT_SHIFT,
  parameter integer ID_WIDTH       = (NUM_EMBED_ROWS <= 1) ? 1 : $clog2(NUM_EMBED_ROWS),
  parameter integer AGG_WIDTH      = DATA_WIDTH +
      ((NUM_LOOKUPS <= 1) ? 0 : $clog2(NUM_LOOKUPS)),
  parameter EMBED_INIT_FILE = "",
  parameter WEIGHT_INIT_FILE = "",
  parameter BIAS_INIT_FILE = ""
) (
  input  logic                                          clk,
  input  logic                                          rst,
  input  logic                                          in_valid,
  output logic                                          in_ready,
  input  logic [NUM_LOOKUPS*ID_WIDTH-1:0]               in_ids,
  output logic                                          out_valid,
  input  logic                                          out_ready,
  output logic signed [DENSE_OUT_DIM*OUTPUT_WIDTH-1:0]  out_data
);
  minimal_recommendation_pipeline #(
    .NUM_EMBED_ROWS(NUM_EMBED_ROWS),
    .EMBED_DIM(EMBED_DIM),
    .NUM_LOOKUPS(NUM_LOOKUPS),
    .DENSE_OUT_DIM(DENSE_OUT_DIM),
    .DATA_WIDTH(DATA_WIDTH),
    .WEIGHT_WIDTH(WEIGHT_WIDTH),
    .BIAS_WIDTH(BIAS_WIDTH),
    .ACC_WIDTH(ACC_WIDTH),
    .OUTPUT_WIDTH(OUTPUT_WIDTH),
    .OUTPUT_SHIFT(OUTPUT_SHIFT),
    .ID_WIDTH(ID_WIDTH),
    .AGG_WIDTH(AGG_WIDTH),
    .EMBED_INIT_FILE(EMBED_INIT_FILE),
    .WEIGHT_INIT_FILE(WEIGHT_INIT_FILE),
    .BIAS_INIT_FILE(BIAS_INIT_FILE)
  ) u_pipeline (
    .clk(clk),
    .rst(rst),
    .in_valid(in_valid),
    .in_ready(in_ready),
    .in_ids(in_ids),
    .out_valid(out_valid),
    .out_ready(out_ready),
    .out_data(out_data)
  );
endmodule

