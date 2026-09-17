`timescale 1ns/1ps
// A18.9 combinational T=8 -> 4-slot pairwise saturating INT16 add.
// slot[i] = sat_add(vec[i], vec[i+4]) per lane. Does not instantiate A13.
module dlrm_t8_pair_fold_stage2n_a18_9_v1 (
  input  logic [7:0][127:0] vec,
  output logic [3:0][127:0] slot
);
  function automatic signed [15:0] sat_add(
      input signed [15:0] a,
      input signed [15:0] b
  );
    logic signed [16:0] sum;
    begin
      sum = {a[15], a} + {b[15], b};
      if (sum > 17'sd32767) begin
        sat_add = 16'sh7fff;
      end else if (sum < -17'sd32768) begin
        sat_add = 16'sh8000;
      end else begin
        sat_add = sum[15:0];
      end
    end
  endfunction

  integer s;
  integer lane;
  always_comb begin
    for (s = 0; s < 4; s = s + 1) begin
      slot[s] = 128'd0;
      for (lane = 0; lane < 8; lane = lane + 1) begin
        slot[s][lane*16 +: 16] = sat_add(
            $signed(vec[s][lane*16 +: 16]),
            $signed(vec[s + 4][lane*16 +: 16])
        );
      end
    end
  end
endmodule
