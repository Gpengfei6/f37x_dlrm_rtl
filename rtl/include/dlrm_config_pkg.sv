package dlrm_config_pkg;
  localparam integer NUM_EMBED_ROWS = 32;
  localparam integer EMBED_DIM      = 8;
  localparam integer NUM_LOOKUPS    = 4;
  localparam integer DENSE_IN_DIM   = 8;
  localparam integer DENSE_OUT_DIM  = 4;

  localparam integer DATA_WIDTH     = 8;
  localparam integer WEIGHT_WIDTH   = 8;
  localparam integer BIAS_WIDTH     = 24;
  localparam integer ACC_WIDTH      = 32;
  localparam integer OUTPUT_WIDTH   = 16;
  localparam integer OUTPUT_SHIFT   = 4;

  localparam integer ID_WIDTH =
      (NUM_EMBED_ROWS <= 1) ? 1 : $clog2(NUM_EMBED_ROWS);
  localparam integer AGG_WIDTH = DATA_WIDTH +
      ((NUM_LOOKUPS <= 1) ? 0 : $clog2(NUM_LOOKUPS));
endpackage

