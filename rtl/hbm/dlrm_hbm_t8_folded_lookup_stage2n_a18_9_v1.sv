`timescale 1ns/1ps
// A18.9: T=8 mapped lookup, four-line FIFO cache per bank, pairwise fold
// to four INT16 slots. Does not instantiate A13 or the boarded A18 kernel.
module dlrm_hbm_t8_folded_lookup_stage2n_a18_9_v1 #(
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
  output logic              done,
  output logic              error_valid,
  input  logic              error_ready,
  output logic [7:0]        error_mask,
  output logic [7:0][127:0] vec,
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
  typedef enum logic [1:0] {IDLE, FETCH, ERROR} state_t;
  state_t state;

  logic [3:0][63:0] base_reg;
  logic [7:0][31:0] index_reg;
  logic [7:0] pending;
  logic [3:0] inflight;
  logic [3:0][2:0] inflight_table;
  logic [7:0] received;
  logic error_hold;
  logic [7:0] index_oob;
  logic any_oob;

  logic [3:0] req_valid;
  logic [3:0] req_ready;
  logic [3:0][31:0] req_index;
  logic [3:0] rsp_valid;
  logic [3:0] rsp_ready;
  logic [3:0][127:0] rsp_data;
  logic [3:0][31:0] rsp_index;
  logic [3:0] rsp_error;
  logic [3:0][3:0] pick;

  logic [3:0] eng_req_valid;
  logic [3:0] eng_req_ready;
  logic [3:0][31:0] eng_req_index;
  logic [3:0] eng_rsp_valid;
  logic [3:0] eng_rsp_ready;
  logic [3:0][127:0] eng_rsp_data;
  logic [3:0][31:0] eng_rsp_index;
  logic [3:0] eng_rsp_error;

  logic [7:0] next_pending;
  logic [3:0] next_inflight;
  logic [7:0] next_received;
  logic next_error;
  logic [7:0] next_mask;

  dlrm_table_bank_mapper_stage2n_a18_5_v1 u_mapper (
    .mapping_sel(mapping_sel),
    .banks_flat(banks_flat),
    .occupancy_flat(occupancy_flat)
  );

  always_comb begin : oob_scan
    integer t;
    any_oob = 1'b0;
    for (t = 0; t < 8; t = t + 1) begin
      index_oob[t] = lookup_index[t] >= ROWS;
      if (index_oob[t]) begin
        any_oob = 1'b1;
      end
    end
  end

  function automatic logic [3:0] pick_table(
      input logic [7:0] pending_i,
      input logic [1:0] bank_i,
      input logic [15:0] banks_flat_i
  );
    integer tt;
    begin
      pick_table = 4'd8;
      for (tt = 0; tt < 8; tt = tt + 1) begin
        if ((pick_table == 4'd8) && pending_i[tt] &&
            (banks_flat_i[(2 * tt) +: 2] == bank_i)) begin
          pick_table = tt[3:0];
        end
      end
    end
  endfunction

  always_comb begin : issue_pick
    integer b;
    for (b = 0; b < 4; b = b + 1) begin
      pick[b] = pick_table(pending, b[1:0], banks_flat);
      req_valid[b] = (state == FETCH) && !error_hold && !inflight[b] &&
                     (pick[b] != 4'd8);
      req_index[b] = (pick[b] != 4'd8) ? index_reg[pick[b][2:0]] : 32'd0;
      rsp_ready[b] = (state == FETCH) && inflight[b];
    end
  end

  always_comb begin : fetch_next
    integer b;
    next_pending = pending;
    next_inflight = inflight;
    next_received = received;
    next_error = error_hold;
    next_mask = error_mask;
    if (state == FETCH) begin
      for (b = 0; b < 4; b = b + 1) begin
        if (req_valid[b] && req_ready[b]) begin
          next_inflight[b] = 1'b1;
          next_pending[pick[b][2:0]] = 1'b0;
        end
        if (rsp_valid[b] && rsp_ready[b]) begin
          next_inflight[b] = 1'b0;
          next_received[inflight_table[b]] = 1'b1;
          if (rsp_error[b] ||
              (rsp_index[b] != index_reg[inflight_table[b]])) begin
            next_error = 1'b1;
            next_mask[inflight_table[b]] = 1'b1;
          end
        end
      end
    end
  end

  assign load_ready = !rst && (state == IDLE);
  assign busy = (state == FETCH);
  assign error_valid = !rst && (state == ERROR);

  for (genvar g = 0; g < 4; g = g + 1) begin : banks
    dlrm_hbm_bank_line_cache_stage2n_a18_9_v1 u_cache (
      .clk(clk),
      .rst(rst),
      .lookup_req_valid(req_valid[g]),
      .lookup_req_ready(req_ready[g]),
      .lookup_req_index(req_index[g]),
      .lookup_rsp_valid(rsp_valid[g]),
      .lookup_rsp_ready(rsp_ready[g]),
      .lookup_rsp_data(rsp_data[g]),
      .lookup_rsp_index(rsp_index[g]),
      .lookup_rsp_error(rsp_error[g]),
      .eng_req_valid(eng_req_valid[g]),
      .eng_req_ready(eng_req_ready[g]),
      .eng_req_index(eng_req_index[g]),
      .eng_rsp_valid(eng_rsp_valid[g]),
      .eng_rsp_ready(eng_rsp_ready[g]),
      .eng_rsp_data(eng_rsp_data[g]),
      .eng_rsp_index(eng_rsp_index[g]),
      .eng_rsp_error(eng_rsp_error[g]),
      .hit(),
      .miss(),
      .hit_count(hit_count[g]),
      .miss_count(miss_count[g])
    );

    dlrm_hbm_embedding_lookup_stage2n_a14_v2 #(
      .ROWS(ROWS),
      .INDEX_WIDTH(32)
    ) u_lookup (
      .clk(clk),
      .rst(rst),
      .table_base_addr(base_reg[g]),
      .lookup_req_valid(eng_req_valid[g]),
      .lookup_req_ready(eng_req_ready[g]),
      .lookup_req_index(eng_req_index[g]),
      .lookup_rsp_valid(eng_rsp_valid[g]),
      .lookup_rsp_ready(eng_rsp_ready[g]),
      .lookup_rsp_data(eng_rsp_data[g]),
      .lookup_rsp_index(eng_rsp_index[g]),
      .lookup_rsp_error(eng_rsp_error[g]),
      .m_axi_arid(m_axi_arid[g]),
      .m_axi_araddr(m_axi_araddr[g]),
      .m_axi_arlen(m_axi_arlen[g]),
      .m_axi_arsize(m_axi_arsize[g]),
      .m_axi_arburst(m_axi_arburst[g]),
      .m_axi_arlock(m_axi_arlock[g]),
      .m_axi_arcache(m_axi_arcache[g]),
      .m_axi_arprot(m_axi_arprot[g]),
      .m_axi_arqos(m_axi_arqos[g]),
      .m_axi_arvalid(m_axi_arvalid[g]),
      .m_axi_arready(m_axi_arready[g]),
      .m_axi_rid(m_axi_rid[g]),
      .m_axi_rdata(m_axi_rdata[g]),
      .m_axi_rresp(m_axi_rresp[g]),
      .m_axi_rlast(m_axi_rlast[g]),
      .m_axi_rvalid(m_axi_rvalid[g]),
      .m_axi_rready(m_axi_rready[g])
    );
  end

  dlrm_t8_pair_fold_stage2n_a18_9_v1 u_fold (
    .vec(vec),
    .slot(slot)
  );

  always_ff @(posedge clk) begin
    if (rst) begin
      state <= IDLE;
      base_reg <= '0;
      index_reg <= '0;
      pending <= '0;
      inflight <= '0;
      inflight_table <= '0;
      received <= '0;
      error_hold <= 1'b0;
      error_mask <= '0;
      vec <= '0;
      done <= 1'b0;
    end else begin
      case (state)
        IDLE: begin
          if (load_valid && load_ready) begin
            done <= 1'b0;
            base_reg <= table_base_addr;
            index_reg <= lookup_index;
            inflight <= 4'h0;
            received <= 8'h00;
            error_hold <= 1'b0;
            vec <= '0;
            if (any_oob) begin
              pending <= 8'h00;
              error_mask <= index_oob;
              state <= ERROR;
            end else begin
              pending <= 8'hFF;
              error_mask <= 8'h00;
              state <= FETCH;
            end
          end
        end
        FETCH: begin
          begin : fetch_capture
            integer b;
            for (b = 0; b < 4; b = b + 1) begin
              if (req_valid[b] && req_ready[b]) begin
                inflight_table[b] <= pick[b][2:0];
              end
              if (rsp_valid[b] && rsp_ready[b]) begin
                vec[inflight_table[b]] <= rsp_data[b];
              end
            end
          end
          pending <= next_pending;
          inflight <= next_inflight;
          received <= next_received;
          error_hold <= next_error;
          error_mask <= next_mask;
          if (next_error && (next_inflight == 4'h0)) begin
            state <= ERROR;
          end else if (!next_error && (&next_received) &&
                       (next_inflight == 4'h0) && (next_pending == 8'h00)) begin
            done <= 1'b1;
            state <= IDLE;
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
