`timescale 1ns/1ps

// Stage 2N-A15.1 controller-level integration proof.
//
// This wrapper leaves the accepted A13 controller and A14 v2 lookup unchanged.
// A successful A14 response is retained until it can be written into A13
// embedding slot 0. Host configuration retains ownership of slots 1..3; a
// Host request for slot 0 is consumed with an explicit rejection pulse and is
// never forwarded to A13.
module dlrm_hbm_pipeline_integration_stage2n_a15_v1 #(
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

  input  logic [HBM_ADDR_WIDTH-1:0]                table_base_addr,
  input  logic                                      lookup_req_valid,
  output logic                                      lookup_req_ready,
  input  logic [HBM_INDEX_WIDTH-1:0]               lookup_req_index,
  output logic                                      hbm_lookup_busy,
  output logic                                      hbm_inject_pending,
  output logic                                      hbm_inject_done,
  output logic                                      hbm_lookup_error_valid,
  input  logic                                      hbm_lookup_error_ready,
  output logic [HBM_INDEX_WIDTH-1:0]               hbm_lookup_error_index,

  output logic [HBM_ID_WIDTH-1:0]                  m_axi_arid,
  output logic [HBM_ADDR_WIDTH-1:0]                m_axi_araddr,
  output logic [7:0]                               m_axi_arlen,
  output logic [2:0]                               m_axi_arsize,
  output logic [1:0]                               m_axi_arburst,
  output logic                                     m_axi_arlock,
  output logic [3:0]                               m_axi_arcache,
  output logic [2:0]                               m_axi_arprot,
  output logic [3:0]                               m_axi_arqos,
  output logic                                     m_axi_arvalid,
  input  logic                                     m_axi_arready,

  input  logic [HBM_ID_WIDTH-1:0]                  m_axi_rid,
  input  logic [HBM_DATA_WIDTH-1:0]                m_axi_rdata,
  input  logic [1:0]                               m_axi_rresp,
  input  logic                                     m_axi_rlast,
  input  logic                                     m_axi_rvalid,
  output logic                                     m_axi_rready
);

  logic a13_embedding_cfg_valid;
  logic a13_embedding_cfg_ready;
  logic [1:0] a13_embedding_cfg_index;
  logic [8*INPUT_WIDTH-1:0] a13_embedding_cfg_data;

  logic a13_pipeline_start_valid;
  logic a13_pipeline_start_ready;

  logic a14_lookup_req_ready;
  logic a14_lookup_rsp_valid;
  logic a14_lookup_rsp_ready;
  logic [HBM_DATA_WIDTH-1:0] a14_lookup_rsp_data;
  logic [HBM_INDEX_WIDTH-1:0] a14_lookup_rsp_index;
  logic a14_lookup_rsp_error;

  logic hbm_inject_pending_reg;
  logic [HBM_DATA_WIDTH-1:0] hbm_inject_data_reg;
  logic hbm_inject_done_reg;
  logic hbm_lookup_error_valid_reg;
  logic [HBM_INDEX_WIDTH-1:0] hbm_lookup_error_index_reg;
  logic host_embedding_cfg_rejected_reg;
  logic hbm_path_idle;

  assign hbm_inject_pending = hbm_inject_pending_reg;
  assign hbm_inject_done = hbm_inject_done_reg;
  assign hbm_lookup_error_valid = hbm_lookup_error_valid_reg;
  assign hbm_lookup_error_index = hbm_lookup_error_index_reg;
  assign host_embedding_cfg_rejected = host_embedding_cfg_rejected_reg;

  assign lookup_req_ready =
      a14_lookup_req_ready &&
      !hbm_inject_pending_reg &&
      !hbm_lookup_error_valid_reg;

  assign hbm_lookup_busy =
      !a14_lookup_req_ready ||
      hbm_inject_pending_reg ||
      hbm_lookup_error_valid_reg;

  assign a14_lookup_rsp_ready =
      !hbm_inject_pending_reg && !hbm_lookup_error_valid_reg;

  assign hbm_path_idle =
      a14_lookup_req_ready &&
      !a14_lookup_rsp_valid &&
      !hbm_inject_pending_reg &&
      !hbm_lookup_error_valid_reg;

  // A simultaneous lookup request has priority over a pipeline START. This
  // prevents an accepted job from observing the previous slot-0 value while a
  // replacement lookup is beginning.
  assign a13_pipeline_start_valid =
      pipeline_start_valid && hbm_path_idle && !lookup_req_valid;
  assign pipeline_start_ready =
      a13_pipeline_start_ready && hbm_path_idle && !lookup_req_valid;

  // Slot ownership and arbitration. A retained HBM response has priority.
  always_comb begin
    a13_embedding_cfg_valid = 1'b0;
    a13_embedding_cfg_index = 2'd0;
    a13_embedding_cfg_data = '0;
    host_embedding_cfg_ready = 1'b0;

    if (hbm_inject_pending_reg) begin
      a13_embedding_cfg_valid = 1'b1;
      a13_embedding_cfg_index = 2'd0;
      a13_embedding_cfg_data = hbm_inject_data_reg;
    end else if (host_embedding_cfg_index == 2'd0) begin
      // Deterministic consume-and-reject semantics for the HBM-owned slot.
      host_embedding_cfg_ready = 1'b1;
    end else begin
      a13_embedding_cfg_valid = host_embedding_cfg_valid;
      a13_embedding_cfg_index = host_embedding_cfg_index;
      a13_embedding_cfg_data = host_embedding_cfg_data;
      host_embedding_cfg_ready = a13_embedding_cfg_ready;
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      hbm_inject_pending_reg <= 1'b0;
      hbm_inject_data_reg <= '0;
      hbm_inject_done_reg <= 1'b0;
      hbm_lookup_error_valid_reg <= 1'b0;
      hbm_lookup_error_index_reg <= '0;
      host_embedding_cfg_rejected_reg <= 1'b0;
    end else begin
      hbm_inject_done_reg <= 1'b0;
      host_embedding_cfg_rejected_reg <= 1'b0;

      if (hbm_lookup_error_valid_reg && hbm_lookup_error_ready)
        hbm_lookup_error_valid_reg <= 1'b0;

      if (host_embedding_cfg_valid && host_embedding_cfg_ready &&
          (host_embedding_cfg_index == 2'd0)) begin
        host_embedding_cfg_rejected_reg <= 1'b1;
      end

      if (a14_lookup_rsp_valid && a14_lookup_rsp_ready) begin
        if (a14_lookup_rsp_error) begin
          hbm_lookup_error_valid_reg <= 1'b1;
          hbm_lookup_error_index_reg <= a14_lookup_rsp_index;
        end else begin
          hbm_inject_pending_reg <= 1'b1;
          hbm_inject_data_reg <= a14_lookup_rsp_data;
        end
      end

      if (hbm_inject_pending_reg && a13_embedding_cfg_ready) begin
        hbm_inject_pending_reg <= 1'b0;
        hbm_inject_done_reg <= 1'b1;
      end
    end
  end

  dlrm_hbm_embedding_lookup_stage2n_a14_v2 #(
    .ROWS(HBM_ROWS),
    .DIM(HBM_DIM),
    .ELEMENT_WIDTH(HBM_ELEMENT_WIDTH),
    .DATA_WIDTH(HBM_DATA_WIDTH),
    .AXI_ADDR_WIDTH(HBM_ADDR_WIDTH),
    .AXI_ID_WIDTH(HBM_ID_WIDTH),
    .INDEX_WIDTH(HBM_INDEX_WIDTH)
  ) u_hbm_lookup (
    .clk(clk),
    .rst(rst),
    .table_base_addr(table_base_addr),
    .lookup_req_valid(lookup_req_valid && lookup_req_ready),
    .lookup_req_ready(a14_lookup_req_ready),
    .lookup_req_index(lookup_req_index),
    .lookup_rsp_valid(a14_lookup_rsp_valid),
    .lookup_rsp_ready(a14_lookup_rsp_ready),
    .lookup_rsp_data(a14_lookup_rsp_data),
    .lookup_rsp_index(a14_lookup_rsp_index),
    .lookup_rsp_error(a14_lookup_rsp_error),
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
    if (INPUT_WIDTH != 16 || HBM_ELEMENT_WIDTH != 16)
      $error("A15.1 requires matching signed INT16 embedding lanes");
    if (HBM_DIM != 8 || HBM_DATA_WIDTH != 128)
      $error("A15.1 requires an 8-lane, 128-bit HBM row");
    if (HBM_DATA_WIDTH != 8*INPUT_WIDTH)
      $error("A15.1 HBM data width must match the A13 embedding port");
    if (HBM_ADDR_WIDTH != 64 || HBM_INDEX_WIDTH != 32)
      $error("A15.1 requires the accepted A14 v2 address/index ABI");
  end

endmodule
