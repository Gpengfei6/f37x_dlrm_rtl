`timescale 1ns/1ps
// A18.7 one-line per-bank embedding cache. Combinational hit check, one
// outstanding miss. Not instantiated in the boarded A18 kernel.
module dlrm_hbm_bank_line_cache_stage2n_a18_7_v1 (
  input  logic         clk,
  input  logic         rst,
  input  logic         lookup_req_valid,
  output logic         lookup_req_ready,
  input  logic [31:0]  lookup_req_index,
  output logic         lookup_rsp_valid,
  input  logic         lookup_rsp_ready,
  output logic [127:0] lookup_rsp_data,
  output logic [31:0]  lookup_rsp_index,
  output logic         lookup_rsp_error,
  output logic         eng_req_valid,
  input  logic         eng_req_ready,
  output logic [31:0]  eng_req_index,
  input  logic         eng_rsp_valid,
  output logic         eng_rsp_ready,
  input  logic [127:0] eng_rsp_data,
  input  logic [31:0]  eng_rsp_index,
  input  logic         eng_rsp_error,
  output logic         hit,
  output logic         miss,
  output logic [15:0]  hit_count,
  output logic [15:0]  miss_count
);
  typedef enum logic [1:0] {IDLE, HIT_RESP, MISS_WAIT} state_t;
  state_t state;

  logic        line_valid;
  logic [31:0] line_index;
  logic [127:0] line_data;
  logic [31:0]  hold_index;
  logic         comb_hit;

  assign comb_hit = line_valid && (line_index == lookup_req_index);
  assign hit = !rst && (state == IDLE) && lookup_req_valid && comb_hit;
  assign miss = !rst && (state == IDLE) && lookup_req_valid && !comb_hit;
  assign lookup_req_ready = !rst && (state == IDLE) && (comb_hit || eng_req_ready);
  assign eng_req_valid = !rst && (state == IDLE) && lookup_req_valid && !comb_hit;
  assign eng_req_index = lookup_req_index;
  assign eng_rsp_ready = !rst && (state == MISS_WAIT);
  assign lookup_rsp_valid = !rst && (state == HIT_RESP);

  always_ff @(posedge clk) begin
    if (rst) begin
      state <= IDLE;
      line_valid <= 1'b0;
      line_index <= 32'd0;
      line_data <= 128'd0;
      hold_index <= 32'd0;
      lookup_rsp_data <= 128'd0;
      lookup_rsp_index <= 32'd0;
      lookup_rsp_error <= 1'b0;
      hit_count <= 16'd0;
      miss_count <= 16'd0;
    end else begin
      case (state)
        IDLE: begin
          if (lookup_req_valid && lookup_req_ready) begin
            hold_index <= lookup_req_index;
            if (comb_hit) begin
              lookup_rsp_data <= line_data;
              lookup_rsp_index <= lookup_req_index;
              lookup_rsp_error <= 1'b0;
              if (hit_count != 16'hFFFF) begin
                hit_count <= hit_count + 16'd1;
              end
              state <= HIT_RESP;
            end else begin
              if (miss_count != 16'hFFFF) begin
                miss_count <= miss_count + 16'd1;
              end
              state <= MISS_WAIT;
            end
          end
        end
        HIT_RESP: begin
          if (lookup_rsp_valid && lookup_rsp_ready) begin
            state <= IDLE;
          end
        end
        MISS_WAIT: begin
          if (eng_rsp_valid && eng_rsp_ready) begin
            lookup_rsp_data <= eng_rsp_data;
            lookup_rsp_index <= hold_index;
            lookup_rsp_error <= eng_rsp_error || (eng_rsp_index != hold_index);
            if (!eng_rsp_error && (eng_rsp_index == hold_index)) begin
              line_valid <= 1'b1;
              line_index <= hold_index;
              line_data <= eng_rsp_data;
            end
            state <= HIT_RESP;
          end
        end
        default: begin
          state <= IDLE;
        end
      endcase
    end
  end
endmodule
