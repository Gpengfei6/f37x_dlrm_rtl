`timescale 1ns/1ps

// Stage 2N-A15.3 local four-embedding integration proof.
//
// One accepted A14 v2 lookup engine fetches four rows sequentially. Each
// successful response is retained until the accepted A13 embedding
// configuration port accepts it. Accepted A13 and A14 RTL are instantiated
// unchanged. Host writes to all four HBM-owned embedding slots are consumed
// with an explicit rejection pulse and are never forwarded to A13.
module dlrm_hbm_pipeline_integration_stage2n_a15_v2 #(
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

  input  logic [HBM_ADDR_WIDTH-1:0]                table_base_addr,
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

  typedef enum logic [2:0] {
    SEQ_IDLE,
    SEQ_REQUEST,
    SEQ_WAIT_RESPONSE,
    SEQ_INJECT,
    SEQ_ALL_LOADED,
    SEQ_ERROR
  } sequence_state_t;

  sequence_state_t sequence_state;

  logic a13_embedding_cfg_valid;
  logic a13_embedding_cfg_ready;
  logic [1:0] a13_embedding_cfg_index;
  logic [8*INPUT_WIDTH-1:0] a13_embedding_cfg_data;
  logic a13_pipeline_start_valid;
  logic a13_pipeline_start_ready;

  logic a14_lookup_req_valid;
  logic a14_lookup_req_ready;
  logic [HBM_INDEX_WIDTH-1:0] a14_lookup_req_index;
  logic a14_lookup_rsp_valid;
  logic a14_lookup_rsp_ready;
  logic [HBM_DATA_WIDTH-1:0] a14_lookup_rsp_data;
  logic [HBM_INDEX_WIDTH-1:0] a14_lookup_rsp_index;
  logic a14_lookup_rsp_error;

  logic [1:0] current_slot_reg;
  logic [HBM_DATA_WIDTH-1:0] response_data_reg;
  logic [HBM_INDEX_WIDTH-1:0] response_index_reg;
  logic hbm_sequence_done_reg;
  logic hbm_inject_done_reg;
  logic host_embedding_cfg_rejected_reg;
  logic [1:0] sequence_error_slot_reg;
  logic [HBM_INDEX_WIDTH-1:0] sequence_error_index_reg;
  logic sequence_active;

  function automatic logic [HBM_INDEX_WIDTH-1:0] slot_lookup_index(
      input logic [1:0] slot
  );
    begin
      case (slot)
        2'd0: slot_lookup_index = SLOT0_LOOKUP_INDEX;
        2'd1: slot_lookup_index = SLOT1_LOOKUP_INDEX;
        2'd2: slot_lookup_index = SLOT2_LOOKUP_INDEX;
        default: slot_lookup_index = SLOT3_LOOKUP_INDEX;
      endcase
    end
  endfunction

  assign load_all_req_ready =
      (sequence_state == SEQ_IDLE) ||
      (sequence_state == SEQ_ALL_LOADED);

  assign sequence_active =
      (sequence_state == SEQ_REQUEST) ||
      (sequence_state == SEQ_WAIT_RESPONSE) ||
      (sequence_state == SEQ_INJECT);

  assign hbm_sequence_busy = sequence_active;
  assign hbm_all_loaded =
      (sequence_state == SEQ_ALL_LOADED) &&
      (embedding_loaded_mask == 4'hF);
  assign hbm_sequence_done = hbm_sequence_done_reg;
  assign hbm_inject_pending = (sequence_state == SEQ_INJECT);
  assign hbm_inject_slot = current_slot_reg;
  assign hbm_inject_data = response_data_reg;
  assign hbm_inject_done = hbm_inject_done_reg;
  assign hbm_sequence_error_valid = (sequence_state == SEQ_ERROR);
  assign hbm_sequence_error_slot = sequence_error_slot_reg;
  assign hbm_sequence_error_index = sequence_error_index_reg;
  assign host_embedding_cfg_ready = !rst;
  assign host_embedding_cfg_rejected = host_embedding_cfg_rejected_reg;

  assign a14_lookup_req_valid = (sequence_state == SEQ_REQUEST);
  assign a14_lookup_req_index = slot_lookup_index(current_slot_reg);
  assign a14_lookup_rsp_ready = (sequence_state == SEQ_WAIT_RESPONSE);

  assign a13_embedding_cfg_valid = (sequence_state == SEQ_INJECT);
  assign a13_embedding_cfg_index = current_slot_reg;
  assign a13_embedding_cfg_data = response_data_reg;

  // A load-all request has priority over pipeline START. A START is also
  // blocked while a sequence or retained sequence error is active. The A13
  // controller keeps its original loaded-mask and configuration gates.
  assign a13_pipeline_start_valid =
      pipeline_start_valid &&
      !sequence_active &&
      (sequence_state != SEQ_ERROR) &&
      !load_all_req_valid;
  assign pipeline_start_ready =
      a13_pipeline_start_ready &&
      !sequence_active &&
      (sequence_state != SEQ_ERROR) &&
      !load_all_req_valid;

  always_ff @(posedge clk) begin
    if (rst) begin
      sequence_state <= SEQ_IDLE;
      current_slot_reg <= 2'd0;
      response_data_reg <= '0;
      response_index_reg <= '0;
      hbm_sequence_done_reg <= 1'b0;
      hbm_inject_done_reg <= 1'b0;
      host_embedding_cfg_rejected_reg <= 1'b0;
      sequence_error_slot_reg <= 2'd0;
      sequence_error_index_reg <= '0;
    end else begin
      hbm_sequence_done_reg <= 1'b0;
      hbm_inject_done_reg <= 1'b0;
      host_embedding_cfg_rejected_reg <= 1'b0;

      if (host_embedding_cfg_valid && host_embedding_cfg_ready)
        host_embedding_cfg_rejected_reg <= 1'b1;

      case (sequence_state)
        SEQ_IDLE,
        SEQ_ALL_LOADED: begin
          if (load_all_req_valid && load_all_req_ready) begin
            current_slot_reg <= 2'd0;
            response_data_reg <= '0;
            response_index_reg <= '0;
            sequence_state <= SEQ_REQUEST;
          end
        end

        SEQ_REQUEST: begin
          if (a14_lookup_req_valid && a14_lookup_req_ready)
            sequence_state <= SEQ_WAIT_RESPONSE;
        end

        SEQ_WAIT_RESPONSE: begin
          if (a14_lookup_rsp_valid && a14_lookup_rsp_ready) begin
            if (a14_lookup_rsp_error) begin
              sequence_error_slot_reg <= current_slot_reg;
              sequence_error_index_reg <= a14_lookup_rsp_index;
              sequence_state <= SEQ_ERROR;
            end else begin
              response_data_reg <= a14_lookup_rsp_data;
              response_index_reg <= a14_lookup_rsp_index;
              sequence_state <= SEQ_INJECT;
            end
          end
        end

        SEQ_INJECT: begin
          if (a13_embedding_cfg_valid && a13_embedding_cfg_ready) begin
            hbm_inject_done_reg <= 1'b1;
            if (current_slot_reg == 2'd3) begin
              hbm_sequence_done_reg <= 1'b1;
              sequence_state <= SEQ_ALL_LOADED;
            end else begin
              current_slot_reg <= current_slot_reg + 1'b1;
              sequence_state <= SEQ_REQUEST;
            end
          end
        end

        SEQ_ERROR: begin
          if (hbm_sequence_error_valid && hbm_sequence_error_ready)
            sequence_state <= SEQ_IDLE;
        end

        default: begin
          sequence_state <= SEQ_ERROR;
          sequence_error_slot_reg <= current_slot_reg;
          sequence_error_index_reg <= response_index_reg;
        end
      endcase
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
    .lookup_req_valid(a14_lookup_req_valid),
    .lookup_req_ready(a14_lookup_req_ready),
    .lookup_req_index(a14_lookup_req_index),
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
      $error("A15.3 requires matching signed INT16 embedding lanes");
    if (HBM_DIM != 8 || HBM_DATA_WIDTH != 128)
      $error("A15.3 requires an 8-lane, 128-bit HBM row");
    if (HBM_DATA_WIDTH != 8*INPUT_WIDTH)
      $error("A15.3 HBM data width must match the A13 embedding port");
    if (HBM_ADDR_WIDTH != 64 || HBM_INDEX_WIDTH != 32)
      $error("A15.3 requires the accepted A14 v2 address/index ABI");
    if ((SLOT0_LOOKUP_INDEX < 0) || (SLOT0_LOOKUP_INDEX >= HBM_ROWS) ||
        (SLOT1_LOOKUP_INDEX < 0) || (SLOT1_LOOKUP_INDEX >= HBM_ROWS) ||
        (SLOT2_LOOKUP_INDEX < 0) || (SLOT2_LOOKUP_INDEX >= HBM_ROWS) ||
        (SLOT3_LOOKUP_INDEX < 0) || (SLOT3_LOOKUP_INDEX >= HBM_ROWS))
      $error("A15.3 lookup indexes must be within the canonical table");
  end

endmodule
