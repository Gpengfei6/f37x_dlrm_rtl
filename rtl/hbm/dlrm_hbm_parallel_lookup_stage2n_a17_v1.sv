`timescale 1ns/1ps

// Four independent accepted A14 engines, one retained response per slot.
// Fetch the complete group before exposing any A13 configuration writes.
// All four engine responses are consumed before error acknowledgement is exposed.
module dlrm_hbm_parallel_lookup_stage2n_a17_v1 #(
  parameter integer ROWS = 64
) (
  input logic clk,
  input logic rst,
  input logic load_valid,
  output logic load_ready,
  input logic [3:0][63:0] table_base_addr,
  input logic [3:0][31:0] lookup_index,
  output logic busy,
  output logic all_loaded,
  output logic done,
  output logic error_valid,
  input logic error_ready,
  output logic [3:0] error_mask,
  output logic [3:0] committed_mask,
  output logic cfg_valid,
  input logic cfg_ready,
  output logic [1:0] cfg_index,
  output logic [127:0] cfg_data,
  output logic [3:0][0:0] m_axi_arid,
  output logic [3:0][63:0] m_axi_araddr,
  output logic [3:0][7:0] m_axi_arlen,
  output logic [3:0][2:0] m_axi_arsize,
  output logic [3:0][1:0] m_axi_arburst,
  output logic [3:0] m_axi_arlock,
  output logic [3:0][3:0] m_axi_arcache,
  output logic [3:0][2:0] m_axi_arprot,
  output logic [3:0][3:0] m_axi_arqos,
  output logic [3:0] m_axi_arvalid,
  input logic [3:0] m_axi_arready,
  input logic [3:0][0:0] m_axi_rid,
  input logic [3:0][127:0] m_axi_rdata,
  input logic [3:0][1:0] m_axi_rresp,
  input logic [3:0] m_axi_rlast,
  input logic [3:0] m_axi_rvalid,
  output logic [3:0] m_axi_rready
);
  typedef enum logic [2:0] {IDLE, FETCH, INJECT, LOADED, ERROR} state_t;
  state_t state;
  logic [3:0][63:0] base_reg;
  logic [3:0][31:0] index_reg;
  logic [3:0][127:0] response_reg;
  logic [3:0] issued, received;
  logic [3:0] req_valid, req_ready, rsp_valid, rsp_ready, rsp_error;
  logic [3:0][127:0] rsp_data;
  logic [3:0][31:0] rsp_index;
  logic [1:0] slot;

  assign load_ready = !rst && ((state == IDLE) || (state == LOADED));
  assign busy = (state == FETCH) || (state == INJECT);
  assign all_loaded = (state == LOADED) && (&committed_mask);
  assign error_valid = !rst && (state == ERROR);
  assign cfg_valid = !rst && (state == INJECT);
  assign cfg_index = slot;
  assign cfg_data = response_reg[slot];

  for (genvar g = 0; g < 4; g = g + 1) begin : banks
    assign req_valid[g] = !rst && (state == FETCH) && !issued[g];
    assign rsp_ready[g] = !rst && (state == FETCH) && issued[g] && !received[g];
    dlrm_hbm_embedding_lookup_stage2n_a14_v2 #(
      .ROWS(ROWS), .INDEX_WIDTH(32)
    ) u_lookup (
      .clk(clk), .rst(rst), .table_base_addr(base_reg[g]),
      .lookup_req_valid(req_valid[g]), .lookup_req_ready(req_ready[g]),
      .lookup_req_index(index_reg[g]), .lookup_rsp_valid(rsp_valid[g]),
      .lookup_rsp_ready(rsp_ready[g]), .lookup_rsp_data(rsp_data[g]),
      .lookup_rsp_index(rsp_index[g]), .lookup_rsp_error(rsp_error[g]),
      .m_axi_arid(m_axi_arid[g]), .m_axi_araddr(m_axi_araddr[g]),
      .m_axi_arlen(m_axi_arlen[g]), .m_axi_arsize(m_axi_arsize[g]),
      .m_axi_arburst(m_axi_arburst[g]), .m_axi_arlock(m_axi_arlock[g]),
      .m_axi_arcache(m_axi_arcache[g]), .m_axi_arprot(m_axi_arprot[g]),
      .m_axi_arqos(m_axi_arqos[g]), .m_axi_arvalid(m_axi_arvalid[g]),
      .m_axi_arready(m_axi_arready[g]), .m_axi_rid(m_axi_rid[g]),
      .m_axi_rdata(m_axi_rdata[g]), .m_axi_rresp(m_axi_rresp[g]),
      .m_axi_rlast(m_axi_rlast[g]), .m_axi_rvalid(m_axi_rvalid[g]),
      .m_axi_rready(m_axi_rready[g])
    );
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      state <= IDLE;
      base_reg <= '0;
      index_reg <= '0;
      response_reg <= '0;
      issued <= '0;
      received <= '0;
      error_mask <= '0;
      committed_mask <= '0;
      slot <= '0;
      done <= 1'b0;
    end else begin
      done <= 1'b0;
      case (state)
        IDLE, LOADED: begin
          if (load_valid && load_ready) begin
            base_reg <= table_base_addr;
            index_reg <= lookup_index;
            issued <= '0;
            received <= '0;
            error_mask <= '0;
            committed_mask <= '0;
            response_reg <= '0;
            slot <= '0;
            state <= FETCH;
          end
        end
        FETCH: begin
          // Continue all four requests after an error. No new group can enter
          // until every engine has returned and its response has been consumed.
          for (integer i = 0; i < 4; i = i + 1) begin
            if (req_valid[i] && req_ready[i]) issued[i] <= 1'b1;
            if (rsp_valid[i] && rsp_ready[i]) begin
              received[i] <= 1'b1;
              response_reg[i] <= rsp_data[i];
              error_mask[i] <= rsp_error[i] || (rsp_index[i] != index_reg[i]);
            end
          end
          if (&received) begin
            if (|error_mask) state <= ERROR;
            else state <= INJECT;
          end
        end
        INJECT: begin
          if (cfg_valid && cfg_ready) begin
            committed_mask[slot] <= 1'b1;
            if (slot == 2'd3) begin
              done <= 1'b1;
              state <= LOADED;
            end else slot <= slot + 1'b1;
          end
        end
        ERROR: begin
          if (error_valid && error_ready) state <= IDLE;
        end
        default: begin
          state <= ERROR;
          error_mask <= 4'hF;
        end
      endcase
    end
  end
endmodule
