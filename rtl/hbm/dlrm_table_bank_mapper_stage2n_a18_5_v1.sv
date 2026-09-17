`timescale 1ns/1ps
// A18.5 kernel-side T=8 / B=4 table-to-bank mapper.
// Combinational. Does not instantiate A14 engines, A13, or the boarded A18 top.
// MAP_IDENT        : bank = table_id % 4
// MAP_COACC_SPLIT  : ident, then move co-occurring pair seconds (4,5) off the
//                    partner bank. This is a split mapper, not Host same-row-index.
// MAP_FORCE_01     : ident, then pin tables 0 and 1 to bank 0 (A18.4 E5 occupancy).
module dlrm_table_bank_mapper_stage2n_a18_5_v1 (
  input  logic [1:0]  mapping_sel,
  output logic [15:0] banks_flat,
  output logic [15:0] occupancy_flat
);
  localparam logic [1:0] MAP_IDENT       = 2'd0;
  localparam logic [1:0] MAP_COACC_SPLIT = 2'd1;
  localparam logic [1:0] MAP_FORCE_01    = 2'd2;

  integer t;
  logic [1:0] bank [0:7];
  logic [3:0] occ  [0:3];

  always_comb begin
    for (t = 0; t < 8; t = t + 1) begin
      bank[t] = t[1:0];
    end
    unique case (mapping_sel)
      MAP_IDENT: begin
      end
      MAP_COACC_SPLIT: begin
        if (bank[4] == bank[0]) begin
          bank[4] = bank[0] + 2'd1;
        end
        if (bank[5] == bank[1]) begin
          bank[5] = bank[1] + 2'd1;
        end
      end
      MAP_FORCE_01: begin
        bank[0] = 2'd0;
        bank[1] = 2'd0;
      end
      default: begin
      end
    endcase
    occ[0] = 4'd0;
    occ[1] = 4'd0;
    occ[2] = 4'd0;
    occ[3] = 4'd0;
    for (t = 0; t < 8; t = t + 1) begin
      occ[bank[t]] = occ[bank[t]] + 4'd1;
    end
  end

  assign banks_flat = {
      bank[7], bank[6], bank[5], bank[4],
      bank[3], bank[2], bank[1], bank[0]
  };
  assign occupancy_flat = {occ[3], occ[2], occ[1], occ[0]};
endmodule
