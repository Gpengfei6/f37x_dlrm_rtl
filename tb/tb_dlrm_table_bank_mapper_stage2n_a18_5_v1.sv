`timescale 1ns/1ps
// Self-checking TB for the A18.5 combinational mapper. Not FPGA evidence.
module tb_dlrm_table_bank_mapper_stage2n_a18_5_v1;
  logic [1:0]  mapping_sel;
  logic [15:0] banks_flat;
  logic [15:0] occupancy_flat;
  integer errors;

  dlrm_table_bank_mapper_stage2n_a18_5_v1 dut (
    .mapping_sel(mapping_sel),
    .banks_flat(banks_flat),
    .occupancy_flat(occupancy_flat)
  );

  task expect_vec(input [15:0] banks_exp, input [15:0] occ_exp, input string name);
    begin
      #1;
      if (banks_flat !== banks_exp || occupancy_flat !== occ_exp) begin
        errors = errors + 1;
        $display("FAIL %s banks=%h occ=%h exp_banks=%h exp_occ=%h",
                 name, banks_flat, occupancy_flat, banks_exp, occ_exp);
      end else begin
        $display("PASS %s", name);
      end
    end
  endtask

  initial begin
    errors = 0;
    mapping_sel = 2'd0;
    // ident T=8: 0,1,2,3,0,1,2,3 occupancy 2,2,2,2
    expect_vec(16'b11_10_01_00_11_10_01_00, 16'h2222, "IDENT");
    mapping_sel = 2'd1;
    // coacc split: 0,1,2,3,1,2,2,3 occupancy 1,2,3,2
    expect_vec(16'b11_10_10_01_11_10_01_00, 16'h2321, "COACC_SPLIT");
    mapping_sel = 2'd2;
    // force 0,1 -> bank 0: 0,0,2,3,0,1,2,3 occupancy 3,1,2,2
    expect_vec(16'b11_10_01_00_11_10_00_00, 16'h2213, "FORCE_01");
    if (errors != 0) begin
      $display("TB_A18_5_MAPPER=FAIL errors=%0d", errors);
      $fatal(1);
    end
    $display("TB_A18_5_MAPPER=PASS");
    $display("PHYSICAL_HBM=NOT_RUN");
    $display("PERFORMANCE=NOT_CLAIMED");
    $finish;
  end
endmodule
