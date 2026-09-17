`timescale 1ns/1ps
module tb_dlrm_t8_pair_fold_stage2n_a18_9_v1;
  logic [7:0][127:0] vec;
  logic [3:0][127:0] slot;
  integer errors;
  integer s;
  integer lane;

  function automatic signed [15:0] sat_add(
      input signed [15:0] a,
      input signed [15:0] b
  );
    integer sum;
    begin
      sum = a + b;
      if (sum > 32767) sat_add = 16'sh7fff;
      else if (sum < -32768) sat_add = 16'sh8000;
      else sat_add = sum[15:0];
    end
  endfunction

  dlrm_t8_pair_fold_stage2n_a18_9_v1 dut (
    .vec(vec),
    .slot(slot)
  );

  initial begin
    errors = 0;
    vec = '0;
    for (s = 0; s < 8; s = s + 1) begin
      for (lane = 0; lane < 8; lane = lane + 1) begin
        vec[s][lane*16 +: 16] = (s * 8 + lane) - 256;
      end
    end
    #1;
    for (s = 0; s < 4; s = s + 1) begin
      for (lane = 0; lane < 8; lane = lane + 1) begin
        if ($signed(slot[s][lane*16 +: 16]) !==
            sat_add($signed(vec[s][lane*16 +: 16]),
                    $signed(vec[s + 4][lane*16 +: 16]))) begin
          errors = errors + 1;
        end
      end
    end
    vec[0][15:0] = 16'sd20000;
    vec[4][15:0] = 16'sd20000;
    vec[1][15:0] = -16'sd20000;
    vec[5][15:0] = -16'sd20000;
    #1;
    if ($signed(slot[0][15:0]) !== 16'sh7fff) errors = errors + 1;
    if ($signed(slot[1][15:0]) !== 16'sh8000) errors = errors + 1;
    if (errors != 0) begin
      $display("TB_A18_9_PAIR_FOLD=FAIL errors=%0d", errors);
      $fatal(1);
    end
    $display("TB_A18_9_PAIR_FOLD=PASS");
    $display("A13_NUMERIC=NOT_CLAIMED");
    $display("PERFORMANCE=NOT_CLAIMED");
    $finish;
  end
endmodule
