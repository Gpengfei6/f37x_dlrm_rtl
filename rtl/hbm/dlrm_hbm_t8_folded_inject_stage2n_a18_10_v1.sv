`timescale 1ns/1ps
// A18.10: wrap A18.9 folded T=8 lookup with an A13-style sequential
// embedding inject handshake. Does not instantiate A13 or the boarded A18 kernel.
module dlrm_hbm_t8_folded_inject_stage2n_a18_10_v1 #(
  parameter integer ROWS = 64
) (
  input  logic              clk,
  input  logic              rst,
  input  logic [1:0]        mapping_sel,
  input  logic              load_valid,
  output logic              load_ready,
  input  logic [3:0][63:0]  table_base_addr,
  input  logic [7:0][31:0]  lookup_index,
  output logic              busy,
  output logic              all_loaded,
  output logic              done,
  output logic              error_valid,
  input  logic              error_ready,
  output logic [7:0]        error_mask,
  output logic [3:0]        committed_mask,
  output logic              cfg_valid,
  input  logic              cfg_ready,
  output logic [1:0]        cfg_index,
  output logic [127:0]      cfg_data,
  output logic [3:0][127:0] slot,
  output logic [15:0]       banks_flat,
  output logic [15:0]       occupancy_flat,
  output logic [3:0][15:0]  hit_count,
  output logic [3:0][15:0]  miss_count,
  output logic [3:0][0:0]   m_axi_arid,
  output logic [3:0][63:0]  m_axi_araddr,
  output logic [3:0][7:0]   m_axi_arlen,
  output logic [3:0][2:0]   m_axi_arsize,
  output logic [3:0][1:0]   m_axi_arburst,
  output logic [3:0]        m_axi_arlock,
  output logic [3:0][3:0]   m_axi_arcache,
  output logic [3:0][2:0]   m_axi_arprot,
  output logic [3:0][3:0]   m_axi_arqos,
  output logic [3:0]        m_axi_arvalid,
  input  logic [3:0]        m_axi_arready,
  input  logic [3:0][0:0]   m_axi_rid,
  input  logic [3:0][127:0] m_axi_rdata,
  input  logic [3:0][1:0]   m_axi_rresp,
  input  logic [3:0]        m_axi_rlast,
  input  logic [3:0]        m_axi_rvalid,
  output logic [3:0]        m_axi_rready
);
  typedef enum logic [2:0] {IDLE, FETCH, INJECT, LOADED, ERROR} state_t;
  state_t state;

  logic [1:0] sel_reg;
  logic [3:0][63:0] base_reg;
  logic [7:0][31:0] index_reg;
  logic [3:0][127:0] response_reg;
  logic lookup_accepted;
  logic [1:0] inject_slot;

  logic lookup_load_valid;
  logic lookup_load_ready;
  logic lookup_busy;
  logic lookup_done;
  logic lookup_error_valid;
  logic lookup_error_ready;
  logic [7:0] lookup_error_mask;
  logic [7:0][127:0] lookup_vec;
  logic [3:0][127:0] lookup_slot;

  assign load_ready = !rst && ((state == IDLE) || (state == LOADED));
  assign busy = (state == FETCH) || (state == INJECT);
  assign all_loaded = (state == LOADED) && (&committed_mask);
  assign error_valid = !rst && (state == ERROR);
  assign cfg_valid = !rst && (state == INJECT);
  assign cfg_index = inject_slot;
  assign cfg_data = response_reg[inject_slot];
  assign slot = response_reg;
  assign lookup_load_valid = !rst && (state == FETCH) && !lookup_accepted;
  assign lookup_error_ready = !rst && (state == ERROR);

  dlrm_hbm_t8_folded_lookup_stage2n_a18_9_v1 #(.ROWS(ROWS)) u_lookup (
    .clk(clk),
    .rst(rst),
    .mapping_sel(sel_reg),
    .load_valid(lookup_load_valid),
    .load_ready(lookup_load_ready),
    .table_base_addr(base_reg),
    .lookup_index(index_reg),
    .busy(lookup_busy),
    .done(lookup_done),
    .error_valid(lookup_error_valid),
    .error_ready(lookup_error_ready),
    .error_mask(lookup_error_mask),
    .vec(lookup_vec),
    .slot(lookup_slot),
    .banks_flat(banks_flat),
    .occupancy_flat(occupancy_flat),
    .hit_count(hit_count),
    .miss_count(miss_count),
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

  always_ff @(posedge clk) begin
    if (rst) begin
      state <= IDLE;
      sel_reg <= 2'd0;
      base_reg <= '0;
      index_reg <= '0;
      response_reg <= '0;
      lookup_accepted <= 1'b0;
      inject_slot <= 2'd0;
      committed_mask <= 4'h0;
      error_mask <= 8'h00;
      done <= 1'b0;
    end else begin
      done <= 1'b0;
      case (state)
        IDLE, LOADED: begin
          if (load_valid && load_ready) begin
            sel_reg <= mapping_sel;
            base_reg <= table_base_addr;
            index_reg <= lookup_index;
            lookup_accepted <= 1'b0;
            inject_slot <= 2'd0;
            committed_mask <= 4'h0;
            error_mask <= 8'h00;
            response_reg <= '0;
            state <= FETCH;
          end
        end
        FETCH: begin
          if (lookup_load_valid && lookup_load_ready) begin
            lookup_accepted <= 1'b1;
          end
          if (lookup_error_valid) begin
            error_mask <= lookup_error_mask;
            state <= ERROR;
          end else if (lookup_accepted && lookup_done) begin
            response_reg <= lookup_slot;
            inject_slot <= 2'd0;
            committed_mask <= 4'h0;
            state <= INJECT;
          end
        end
        INJECT: begin
          if (cfg_valid && cfg_ready) begin
            committed_mask[inject_slot] <= 1'b1;
            if (inject_slot == 2'd3) begin
              done <= 1'b1;
              state <= LOADED;
            end else begin
              inject_slot <= inject_slot + 2'd1;
            end
          end
        end
        ERROR: begin
          if (error_valid && error_ready) begin
            state <= IDLE;
          end
        end
        default: begin
          state <= ERROR;
          error_mask <= 8'hFF;
        end
      endcase
    end
  end
endmodule
