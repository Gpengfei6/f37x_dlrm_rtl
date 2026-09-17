`timescale 1ns/1ps
// A18.1 four independent ports; frozen compute modules reused unchanged.
// Structural copy of dlrm_hbm_pipeline_integration_stage2n_a17_v1 with:
//   1. runtime lookup_index[] instead of hardcoded {40,39,38,37}
//   2. group OOB: any index >= HBM_ROWS blocks load_valid (no AR on any channel)
module dlrm_hbm_pipeline_integration_stage2n_a18_v1 #(
  parameter integer MAX_LAYERS          = 8,
  parameter integer MAX_IN_DIM          = 64,
  parameter integer MAX_OUT_DIM         = 64,
  parameter integer NUM_PE              = 16,
  parameter integer INPUT_WIDTH         = 16,
  parameter integer WEIGHT_WIDTH        = 8,
  parameter integer BIAS_WIDTH          = 24,
  parameter integer ACC_WIDTH           = 48,
  parameter integer OUTPUT_WIDTH        = 16,
  parameter integer WEIGHT_ADDR_WIDTH   = 32,
  parameter integer BIAS_ADDR_WIDTH     = 32,
  parameter integer MAX_WEIGHT_VALUES   = 2048,
  parameter integer MAX_BIAS_VALUES     = 128,
  parameter integer RESULT_FIFO_DEPTH   = 2,
  parameter integer JOB_TAG_WIDTH       = 8,
  parameter integer DESCRIPTOR_WIDTH    = 96,
  parameter integer HBM_ROWS            = 64,
  parameter integer HBM_DIM             = 8,
  parameter integer HBM_ELEMENT_WIDTH   = 16,
  parameter integer HBM_DATA_WIDTH      = 128,
  parameter integer HBM_ADDR_WIDTH      = 64,
  parameter integer HBM_ID_WIDTH        = 1,
  parameter integer HBM_INDEX_WIDTH     = 32,
  parameter integer SLOT0_LOOKUP_INDEX  = 37,
  parameter integer SLOT1_LOOKUP_INDEX  = 38,
  parameter integer SLOT2_LOOKUP_INDEX  = 39,
  parameter integer SLOT3_LOOKUP_INDEX  = 40,
  parameter integer IN_DIM_WIDTH =
      (MAX_IN_DIM <= 1) ? 1 : $clog2(MAX_IN_DIM+1),
  parameter integer OUT_DIM_WIDTH =
      (MAX_OUT_DIM <= 1) ? 1 : $clog2(MAX_OUT_DIM+1),
  parameter integer OUT_INDEX_WIDTH =
      (MAX_OUT_DIM <= 1) ? 1 : $clog2(MAX_OUT_DIM),
  parameter integer ACT_MAX_DIM =
      (MAX_IN_DIM > MAX_OUT_DIM) ? MAX_IN_DIM : MAX_OUT_DIM,
  parameter integer ACT_BANK_DEPTH =
      (ACT_MAX_DIM+NUM_PE-1)/NUM_PE,
  parameter integer ACT_CHUNK_ADDR_WIDTH =
      (ACT_BANK_DEPTH <= 1) ? 1 : $clog2(ACT_BANK_DEPTH),
  parameter integer SHIFT_WIDTH =
      (ACC_WIDTH <= 1) ? 1 : $clog2(ACC_WIDTH+1),
  parameter integer LAYER_INDEX_WIDTH =
      (MAX_LAYERS <= 1) ? 1 : $clog2(MAX_LAYERS),
  parameter integer LAYER_COUNT_WIDTH =
      (MAX_LAYERS <= 1) ? 1 : $clog2(MAX_LAYERS+1)
) (
  input  logic                                      clk,
  input  logic                                      rst,

  input  logic                                      descriptor_cfg_valid,
  output logic                                      descriptor_cfg_ready,
  input  logic [LAYER_INDEX_WIDTH-1:0]             descriptor_cfg_index,
  input  logic [DESCRIPTOR_WIDTH-1:0]              descriptor_cfg_data,

  input  logic                                      act_load_valid,
  output logic                                      act_load_ready,
  input  logic                                      act_load_buffer_select,
  input  logic [ACT_CHUNK_ADDR_WIDTH-1:0]           act_load_chunk_index,
  input  logic [NUM_PE-1:0]                         act_load_lane_mask,
  input  logic [NUM_PE*INPUT_WIDTH-1:0]             act_load_data,

  input  logic                                      host_embedding_cfg_valid,
  output logic                                      host_embedding_cfg_ready,
  input  logic [1:0]                                host_embedding_cfg_index,
  input  logic [8*INPUT_WIDTH-1:0]                  host_embedding_cfg_data,
  output logic                                      host_embedding_cfg_rejected,
  output logic [3:0]                                embedding_loaded_mask,

  input  logic                                      weight_cfg_valid,
  output logic                                      weight_cfg_ready,
  input  logic [WEIGHT_ADDR_WIDTH-1:0]              weight_cfg_address,
  input  logic signed [WEIGHT_WIDTH-1:0]            weight_cfg_data,

  input  logic                                      bias_cfg_valid,
  output logic                                      bias_cfg_ready,
  input  logic [BIAS_ADDR_WIDTH-1:0]                bias_cfg_address,
  input  logic signed [BIAS_WIDTH-1:0]              bias_cfg_data,

  input  logic                                      pipeline_start_valid,
  output logic                                      pipeline_start_ready,
  input  logic [LAYER_INDEX_WIDTH-1:0]             bottom_descriptor_base,
  input  logic [LAYER_COUNT_WIDTH-1:0]             bottom_layer_count,
  input  logic [LAYER_INDEX_WIDTH-1:0]             top_descriptor_base,
  input  logic [LAYER_COUNT_WIDTH-1:0]             top_layer_count,
  input  logic                                      bottom_initial_buffer_select,
  input  logic                                      top_input_buffer_select,
  input  logic [SHIFT_WIDTH-1:0]                    interaction_shift,

  output logic                                      result_valid,
  input  logic                                      result_ready,
  output logic signed [OUTPUT_WIDTH-1:0]            result_data,
  output logic [OUT_INDEX_WIDTH-1:0]                result_index,
  output logic                                      result_last,
  output logic [JOB_TAG_WIDTH-1:0]                  result_tag,

  output logic                                      busy,
  output logic                                      done,
  output logic [3:0]                                phase,
  output logic [3:0]                                bottom_result_count,
  output logic [4:0]                                interaction_result_count,
  output logic [31:0]                               bottom_cycle_count,
  output logic [31:0]                               interaction_cycle_count,
  output logic [31:0]                               top_cycle_count,
  output logic [31:0]                               total_cycle_count,

  output logic                                      pipeline_error_valid,
  input  logic                                      pipeline_error_ready,
  output logic [7:0]                                pipeline_error_code,

  input  logic [3:0] [HBM_ADDR_WIDTH-1:0]                table_base_addr,
  input  logic [3:0] [HBM_INDEX_WIDTH-1:0]               lookup_index,
  input  logic                                      load_all_req_valid,
  output logic                                      load_all_req_ready,
  output logic                                      hbm_sequence_busy,
  output logic                                      hbm_all_loaded,
  output logic                                      hbm_sequence_done,
  output logic                                      hbm_inject_pending,
  output logic [1:0]                                hbm_inject_slot,
  output logic [HBM_DATA_WIDTH-1:0]                hbm_inject_data,
  output logic                                      hbm_inject_done,
  output logic                                      hbm_sequence_error_valid,
  input  logic                                      hbm_sequence_error_ready,
  output logic [1:0]                                hbm_sequence_error_slot,
  output logic [HBM_INDEX_WIDTH-1:0]               hbm_sequence_error_index,

  output logic [3:0] [HBM_ID_WIDTH-1:0]                  m_axi_arid,
  output logic [3:0] [HBM_ADDR_WIDTH-1:0]                m_axi_araddr,
  output logic [3:0] [7:0]                               m_axi_arlen,
  output logic [3:0] [2:0]                               m_axi_arsize,
  output logic [3:0] [1:0]                               m_axi_arburst,
  output logic [3:0]                                     m_axi_arlock,
  output logic [3:0] [3:0]                               m_axi_arcache,
  output logic [3:0] [2:0]                               m_axi_arprot,
  output logic [3:0] [3:0]                               m_axi_arqos,
  output logic [3:0]                                     m_axi_arvalid,
  input  logic [3:0]                                     m_axi_arready,

  input  logic [3:0] [HBM_ID_WIDTH-1:0]                  m_axi_rid,
  input  logic [3:0] [HBM_DATA_WIDTH-1:0]                m_axi_rdata,
  input  logic [3:0] [1:0]                               m_axi_rresp,
  input  logic [3:0]                                     m_axi_rlast,
  input  logic [3:0]                                     m_axi_rvalid,
  output logic [3:0]                                     m_axi_rready
);

  logic a13_embedding_cfg_valid, a13_embedding_cfg_ready;
  logic [1:0] a13_embedding_cfg_index;
  logic [127:0] a13_embedding_cfg_data;
  logic a13_pipeline_start_valid, a13_pipeline_start_ready;
  logic controller_load_ready, controller_all_loaded;
  logic [3:0] controller_error_mask, controller_committed_mask;
  logic [3:0][31:0] lookup_indexes;
  logic fresh_group, compute_idle, compute_idle_q, start_gate;
  logic index_oob;
  logic oob_error_hold;
  logic oob_fire;
  logic lookup_load_valid;
  logic lookup_error_valid;
  logic [1:0] oob_slot;
  logic [1:0] lookup_error_slot;

  // Packed LSB slot0 = lookup_index[0]. Do not reverse.
  assign lookup_indexes = lookup_index;
  assign index_oob =
      (lookup_index[0] >= HBM_ROWS) ||
      (lookup_index[1] >= HBM_ROWS) ||
      (lookup_index[2] >= HBM_ROWS) ||
      (lookup_index[3] >= HBM_ROWS);
  assign oob_slot =
      (lookup_index[0] >= HBM_ROWS) ? 2'd0 :
      (lookup_index[1] >= HBM_ROWS) ? 2'd1 :
      (lookup_index[2] >= HBM_ROWS) ? 2'd2 : 2'd3;
  assign oob_fire = load_all_req_valid && compute_idle_q && index_oob &&
      !oob_error_hold;

  assign compute_idle = !busy && !result_valid && !pipeline_error_valid;
  assign hbm_all_loaded = controller_all_loaded && (&embedding_loaded_mask);
  // Registered idle plus A15-style valid/ready split: do not AND
  // a13_pipeline_start_ready into start valid, and do not combinationally
  // feed A13 result_fifo outputs into the lookup load port. Target link 003
  // failed write_bitstream with LUTLP-1 through mlp_act_load_valid and
  // u_hbm_lookup/fresh_group.
  assign start_gate =
      !rst && hbm_all_loaded && fresh_group && !load_all_req_valid &&
      compute_idle_q && !oob_error_hold;
  // Accept the load token even when indexes are OOB so START can complete;
  // lookup_load_valid still blocks every AR.
  assign load_all_req_ready =
      !rst && controller_load_ready && compute_idle_q && !oob_error_hold;
  assign lookup_load_valid =
      load_all_req_valid && compute_idle_q && !index_oob && !oob_error_hold;
  assign pipeline_start_ready = a13_pipeline_start_ready && start_gate;
  assign a13_pipeline_start_valid = pipeline_start_valid && start_gate;
  assign hbm_inject_pending = a13_embedding_cfg_valid;
  assign hbm_inject_slot = a13_embedding_cfg_index;
  assign hbm_inject_data = a13_embedding_cfg_data;
  assign host_embedding_cfg_ready = !rst;
  assign lookup_error_slot = controller_error_mask[0] ? 2'd0 :
      controller_error_mask[1] ? 2'd1 : controller_error_mask[2] ? 2'd2 : 2'd3;
  assign hbm_sequence_error_valid = oob_error_hold || oob_fire ||
      lookup_error_valid;
  assign hbm_sequence_error_slot = (oob_error_hold || oob_fire) ? oob_slot :
      lookup_error_slot;
  assign hbm_sequence_error_index = lookup_index[hbm_sequence_error_slot];
  always_ff @(posedge clk) begin
    if (rst) begin
      fresh_group <= 1'b0;
      compute_idle_q <= 1'b0;
      hbm_inject_done <= 1'b0;
      host_embedding_cfg_rejected <= 1'b0;
      oob_error_hold <= 1'b0;
    end else begin
      compute_idle_q <= compute_idle;
      hbm_inject_done <= a13_embedding_cfg_valid && a13_embedding_cfg_ready;
      host_embedding_cfg_rejected <= host_embedding_cfg_valid && host_embedding_cfg_ready;
      // One START token per newly completed group, never from the stale A13 mask.
      if (load_all_req_valid && load_all_req_ready) fresh_group <= 1'b0;
      else if (a13_pipeline_start_valid && a13_pipeline_start_ready) fresh_group <= 1'b0;
      else if (hbm_sequence_done) fresh_group <= 1'b1;
      if (oob_fire)
        oob_error_hold <= 1'b1;
      else if (oob_error_hold && hbm_sequence_error_valid &&
               hbm_sequence_error_ready)
        oob_error_hold <= 1'b0;
    end
  end
  dlrm_hbm_parallel_lookup_stage2n_a17_v1 #(.ROWS(HBM_ROWS)) u_hbm_lookup (
    .clk(clk), .rst(rst), .load_valid(lookup_load_valid),
    .load_ready(controller_load_ready), .table_base_addr(table_base_addr),
    .lookup_index(lookup_indexes), .busy(hbm_sequence_busy),
    .all_loaded(controller_all_loaded), .done(hbm_sequence_done),
    .error_valid(lookup_error_valid), .error_ready(hbm_sequence_error_ready),
    .error_mask(controller_error_mask), .committed_mask(controller_committed_mask),
    .cfg_valid(a13_embedding_cfg_valid), .cfg_ready(a13_embedding_cfg_ready),
    .cfg_index(a13_embedding_cfg_index), .cfg_data(a13_embedding_cfg_data),
    .m_axi_arid(m_axi_arid),
    .m_axi_araddr(m_axi_araddr),
    .m_axi_arlen(m_axi_arlen),
    .m_axi_arsize(m_axi_arsize),
    .m_axi_arburst(m_axi_arburst),
    .m_axi_arlock(m_axi_arlock),
    .m_axi_arcache(m_axi_arcache),
    .m_axi_arprot(m_axi_arprot),
    .m_axi_arqos(m_axi_arqos),
    .m_axi_arvalid(m_axi_arvalid),
    .m_axi_arready(m_axi_arready),
    .m_axi_rid(m_axi_rid),
    .m_axi_rdata(m_axi_rdata),
    .m_axi_rresp(m_axi_rresp),
    .m_axi_rlast(m_axi_rlast),
    .m_axi_rvalid(m_axi_rvalid),
    .m_axi_rready(m_axi_rready)
  );
  dlrm_internal_pipeline_controller_stage2n_a13_v1 #(
    .MAX_LAYERS(MAX_LAYERS),
    .MAX_IN_DIM(MAX_IN_DIM),
    .MAX_OUT_DIM(MAX_OUT_DIM),
    .NUM_PE(NUM_PE),
    .INPUT_WIDTH(INPUT_WIDTH),
    .WEIGHT_WIDTH(WEIGHT_WIDTH),
    .BIAS_WIDTH(BIAS_WIDTH),
    .ACC_WIDTH(ACC_WIDTH),
    .OUTPUT_WIDTH(OUTPUT_WIDTH),
    .WEIGHT_ADDR_WIDTH(WEIGHT_ADDR_WIDTH),
    .BIAS_ADDR_WIDTH(BIAS_ADDR_WIDTH),
    .MAX_WEIGHT_VALUES(MAX_WEIGHT_VALUES),
    .MAX_BIAS_VALUES(MAX_BIAS_VALUES),
    .RESULT_FIFO_DEPTH(RESULT_FIFO_DEPTH),
    .JOB_TAG_WIDTH(JOB_TAG_WIDTH),
    .DESCRIPTOR_WIDTH(DESCRIPTOR_WIDTH)
  ) u_a13_pipeline (
    .clk(clk),
    .rst(rst),
    .descriptor_cfg_valid(descriptor_cfg_valid),
    .descriptor_cfg_ready(descriptor_cfg_ready),
    .descriptor_cfg_index(descriptor_cfg_index),
    .descriptor_cfg_data(descriptor_cfg_data),
    .act_load_valid(act_load_valid),
    .act_load_ready(act_load_ready),
    .act_load_buffer_select(act_load_buffer_select),
    .act_load_chunk_index(act_load_chunk_index),
    .act_load_lane_mask(act_load_lane_mask),
    .act_load_data(act_load_data),
    .embedding_cfg_valid(a13_embedding_cfg_valid),
    .embedding_cfg_ready(a13_embedding_cfg_ready),
    .embedding_cfg_index(a13_embedding_cfg_index),
    .embedding_cfg_data(a13_embedding_cfg_data),
    .embedding_loaded_mask(embedding_loaded_mask),
    .weight_cfg_valid(weight_cfg_valid),
    .weight_cfg_ready(weight_cfg_ready),
    .weight_cfg_address(weight_cfg_address),
    .weight_cfg_data(weight_cfg_data),
    .bias_cfg_valid(bias_cfg_valid),
    .bias_cfg_ready(bias_cfg_ready),
    .bias_cfg_address(bias_cfg_address),
    .bias_cfg_data(bias_cfg_data),
    .pipeline_start_valid(a13_pipeline_start_valid),
    .pipeline_start_ready(a13_pipeline_start_ready),
    .bottom_descriptor_base(bottom_descriptor_base),
    .bottom_layer_count(bottom_layer_count),
    .top_descriptor_base(top_descriptor_base),
    .top_layer_count(top_layer_count),
    .bottom_initial_buffer_select(bottom_initial_buffer_select),
    .top_input_buffer_select(top_input_buffer_select),
    .interaction_shift(interaction_shift),
    .result_valid(result_valid),
    .result_ready(result_ready),
    .result_data(result_data),
    .result_index(result_index),
    .result_last(result_last),
    .result_tag(result_tag),
    .busy(busy),
    .done(done),
    .phase(phase),
    .bottom_result_count(bottom_result_count),
    .interaction_result_count(interaction_result_count),
    .bottom_cycle_count(bottom_cycle_count),
    .interaction_cycle_count(interaction_cycle_count),
    .top_cycle_count(top_cycle_count),
    .total_cycle_count(total_cycle_count),
    .error_valid(pipeline_error_valid),
    .error_ready(pipeline_error_ready),
    .error_code(pipeline_error_code)
  );

  initial begin
    if (HBM_ID_WIDTH != 1 || SLOT0_LOOKUP_INDEX != 37 ||
        SLOT1_LOOKUP_INDEX != 38 || SLOT2_LOOKUP_INDEX != 39 || SLOT3_LOOKUP_INDEX != 40)
      $error("A18.1 documents AXI ID width 1 and reset defaults slot0=37 .. slot3=40");
    if (INPUT_WIDTH != 16 || HBM_ELEMENT_WIDTH != 16)
      $error("A18.1 requires matching signed INT16 embedding lanes");
    if (HBM_DIM != 8 || HBM_DATA_WIDTH != 128)
      $error("A18.1 requires an 8-lane, 128-bit HBM row");
    if (HBM_DATA_WIDTH != 8*INPUT_WIDTH)
      $error("A18.1 HBM data width must match the A13 embedding port");
    if (HBM_ADDR_WIDTH != 64 || HBM_INDEX_WIDTH != 32)
      $error("A18.1 requires the accepted A14 v2 address/index ABI");
  end

endmodule
