`timescale 1ns/1ps
// A18.9 TB: four-line FIFO cache + pairwise fold. WARM_REPEAT expects
// zero extra ARs after a cold unique ident group. Fold is not A13 DLRM.
module tb_dlrm_hbm_t8_folded_lookup_stage2n_a18_9_v1;
  logic clk = 1'b0;
  logic rst = 1'b1;
  always #5 clk = ~clk;

  logic [1:0] mapping_sel;
  logic load_valid;
  logic load_ready;
  logic [3:0][63:0] table_base_addr;
  logic [7:0][31:0] lookup_index;
  logic busy;
  logic done;
  logic error_valid;
  logic error_ready;
  logic [7:0] error_mask;
  logic [7:0][127:0] vec;
  logic [3:0][127:0] slot;
  logic [15:0] banks_flat;
  logic [15:0] occupancy_flat;
  logic [3:0][15:0] hit_count;
  logic [3:0][15:0] miss_count;
  logic [3:0][0:0] m_axi_arid;
  logic [3:0][63:0] m_axi_araddr;
  logic [3:0][7:0] m_axi_arlen;
  logic [3:0][2:0] m_axi_arsize;
  logic [3:0][1:0] m_axi_arburst;
  logic [3:0] m_axi_arlock;
  logic [3:0][3:0] m_axi_arcache;
  logic [3:0][2:0] m_axi_arprot;
  logic [3:0][3:0] m_axi_arqos;
  logic [3:0] m_axi_arvalid;
  logic [3:0] m_axi_arready;
  logic [3:0][0:0] m_axi_rid;
  logic [3:0][127:0] m_axi_rdata;
  logic [3:0][1:0] m_axi_rresp;
  logic [3:0] m_axi_rlast;
  logic [3:0] m_axi_rvalid;
  logic [3:0] m_axi_rready;

  integer ar_count [0:3];
  integer pending [0:3];
  integer delay_left [0:3];
  integer row_hold [0:3];
  integer errors;
  integer t;
  integer n;
  integer n_ready;
  integer ar_before [0:3];
  integer expect_bank;
  integer expect_occ [0:3];
  integer expect_ar [0:3];
  integer idx_hold [0:7];

  function automatic [127:0] golden(input integer row);
    integer lane;
    begin
      golden = 128'd0;
      for (lane = 0; lane < 8; lane = lane + 1) begin
        golden[lane*16 +: 16] = row * 8 + lane - 256;
      end
    end
  endfunction

  function automatic signed [15:0] sat_add(
      input [15:0] a,
      input [15:0] b
  );
    integer sum;
    begin
      sum = $signed(a) + $signed(b);
      if (sum > 32767) sat_add = 16'sh7fff;
      else if (sum < -32768) sat_add = 16'sh8000;
      else sat_add = sum[15:0];
    end
  endfunction

  function automatic [127:0] fold_pair(input integer row_a, input integer row_b);
    integer lane;
    logic [127:0] ga;
    logic [127:0] gb;
    begin
      ga = golden(row_a);
      gb = golden(row_b);
      fold_pair = 128'd0;
      for (lane = 0; lane < 8; lane = lane + 1) begin
        fold_pair[lane*16 +: 16] = sat_add(ga[lane*16 +: 16], gb[lane*16 +: 16]);
      end
    end
  endfunction

  function automatic [1:0] bank_of(input integer table_id, input [1:0] sel);
    begin
      bank_of = table_id[1:0];
      if (sel == 2'd1) begin
        if ((table_id == 4) && (bank_of == 2'd0)) bank_of = 2'd1;
        if ((table_id == 5) && (bank_of == 2'd1)) bank_of = 2'd2;
      end else if (sel == 2'd2) begin
        if (table_id == 0) bank_of = 2'd0;
        if (table_id == 1) bank_of = 2'd0;
      end
    end
  endfunction

  dlrm_hbm_t8_folded_lookup_stage2n_a18_9_v1 dut (
    .clk(clk),
    .rst(rst),
    .mapping_sel(mapping_sel),
    .load_valid(load_valid),
    .load_ready(load_ready),
    .table_base_addr(table_base_addr),
    .lookup_index(lookup_index),
    .busy(busy),
    .done(done),
    .error_valid(error_valid),
    .error_ready(error_ready),
    .error_mask(error_mask),
    .vec(vec),
    .slot(slot),
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

  assign m_axi_rid = '0;
  assign m_axi_rlast = 4'hF;
  always_comb begin
    for (n_ready = 0; n_ready < 4; n_ready = n_ready + 1) begin
      m_axi_arready[n_ready] = (pending[n_ready] == 0) && !m_axi_rvalid[n_ready];
    end
  end

  always @(posedge clk) begin
    if (rst) begin
      m_axi_rvalid <= '0;
      m_axi_rdata <= '0;
      m_axi_rresp <= '0;
      for (n = 0; n < 4; n = n + 1) begin
        pending[n] <= 0;
        delay_left[n] <= 0;
        row_hold[n] <= 0;
        ar_count[n] <= 0;
      end
    end else begin
      for (n = 0; n < 4; n = n + 1) begin
        if (m_axi_arvalid[n] && m_axi_arready[n]) begin
          if (m_axi_arlen[n] !== 8'd0 || m_axi_arsize[n] !== 3'd4 ||
              m_axi_arburst[n] !== 2'd1) begin
            errors = errors + 1;
            $display("FAIL AXI shape bank %0d", n);
          end
          pending[n] <= 1;
          delay_left[n] <= 2;
          row_hold[n] <= (m_axi_araddr[n] - table_base_addr[n]) >> 4;
          ar_count[n] <= ar_count[n] + 1;
        end
        if (pending[n] != 0) begin
          if (delay_left[n] != 0) begin
            delay_left[n] <= delay_left[n] - 1;
          end else begin
            pending[n] <= 0;
            m_axi_rvalid[n] <= 1'b1;
            m_axi_rdata[n] <= golden(row_hold[n]);
            m_axi_rresp[n] <= 2'b00;
          end
        end
        if (m_axi_rvalid[n] && m_axi_rready[n]) begin
          m_axi_rvalid[n] <= 1'b0;
        end
      end
    end
  end

  task automatic tick;
    begin
      @(posedge clk);
      #1;
    end
  endtask

  task automatic pulse_rst;
    begin
      rst = 1'b1;
      load_valid = 1'b0;
      repeat (3) tick;
      rst = 1'b0;
      repeat (2) tick;
    end
  endtask

  task automatic wait_load;
    begin
      begin : wait_load_blk
        load_valid = 1'b1;
        forever begin
          @(posedge clk);
          if (load_ready) begin
            @(negedge clk);
            load_valid = 1'b0;
            disable wait_load_blk;
          end
        end
      end
    end
  endtask

  task automatic run_named(
      input [1:0] sel,
      input string name,
      input integer exp_ar0,
      input integer exp_ar1,
      input integer exp_ar2,
      input integer exp_ar3
  );
    begin
      mapping_sel = sel;
      error_ready = 1'b1;
      for (n = 0; n < 4; n = n + 1) begin
        table_base_addr[n] = 64'h0000_0000_0001_0000 + (n * 64'h0001_0000);
        expect_occ[n] = 0;
      end
      expect_ar[0] = exp_ar0;
      expect_ar[1] = exp_ar1;
      expect_ar[2] = exp_ar2;
      expect_ar[3] = exp_ar3;
      tick;
      for (n = 0; n < 4; n = n + 1) ar_before[n] = ar_count[n];
      wait_load();
      while (!done && !error_valid) @(posedge clk);
      #1;
      if (error_valid || !done) begin
        errors = errors + 1;
        $display("FAIL %s error/done", name);
      end
      for (t = 0; t < 8; t = t + 1) begin
        expect_bank = bank_of(t, sel);
        expect_occ[expect_bank] = expect_occ[expect_bank] + 1;
        if (banks_flat[(2 * t) +: 2] !== expect_bank[1:0]) begin
          errors = errors + 1;
          $display("FAIL %s table %0d bank", name, t);
        end
        if (vec[t] !== golden(idx_hold[t])) begin
          errors = errors + 1;
          $display("FAIL %s table %0d vec", name, t);
        end
      end
      for (n = 0; n < 4; n = n + 1) begin
        if (occupancy_flat[(4 * n) +: 4] !== expect_occ[n][3:0]) begin
          errors = errors + 1;
          $display("FAIL %s occupancy bank %0d", name, n);
        end
        if ((ar_count[n] - ar_before[n]) !== expect_ar[n]) begin
          errors = errors + 1;
          $display("FAIL %s AR bank %0d got %0d exp %0d",
                   name, n, ar_count[n] - ar_before[n], expect_ar[n]);
        end
      end
      if (errors == 0) $display("PASS %s", name);
    end
  endtask

  initial begin
    errors = 0;
    load_valid = 1'b0;
    error_ready = 1'b1;
    mapping_sel = 2'd0;
    lookup_index = '0;
    table_base_addr = '0;
    pulse_rst();

    for (t = 0; t < 8; t = t + 1) begin
      lookup_index[t] = 32'(10 + t);
      idx_hold[t] = 10 + t;
    end
    run_named(2'd0, "IDENT_COLD", 2, 2, 2, 2);
    for (t = 0; t < 4; t = t + 1) begin
      if (slot[t] !== fold_pair(idx_hold[t], idx_hold[t + 4])) begin
        errors = errors + 1;
        $display("FAIL IDENT_FOLD slot %0d", t);
      end
    end
    if (errors == 0) $display("PASS IDENT_FOLD");
    run_named(2'd0, "IDENT_WARM", 0, 0, 0, 0);

    pulse_rst();
    for (t = 0; t < 8; t = t + 1) begin
      lookup_index[t] = 32'(10 + t);
      idx_hold[t] = 10 + t;
    end
    run_named(2'd1, "COACC_COLD", 1, 2, 3, 2);

    pulse_rst();
    for (t = 0; t < 8; t = t + 1) begin
      lookup_index[t] = 32'(10 + t);
      idx_hold[t] = 10 + t;
    end
    run_named(2'd2, "FORCE_COLD", 3, 1, 2, 2);

    pulse_rst();
    lookup_index[0] = 32'd7; idx_hold[0] = 7;
    lookup_index[1] = 32'd11; idx_hold[1] = 11;
    lookup_index[2] = 32'd12; idx_hold[2] = 12;
    lookup_index[3] = 32'd13; idx_hold[3] = 13;
    lookup_index[4] = 32'd7; idx_hold[4] = 7;
    lookup_index[5] = 32'd15; idx_hold[5] = 15;
    lookup_index[6] = 32'd16; idx_hold[6] = 16;
    lookup_index[7] = 32'd17; idx_hold[7] = 17;
    run_named(2'd0, "SAME_LINE_BANK0", 1, 2, 2, 2);
    if (hit_count[0] !== 16'd1 || miss_count[0] !== 16'd1) begin
      errors = errors + 1;
      $display("FAIL SAME_LINE hit/miss bank0 hit=%0d miss=%0d",
               hit_count[0], miss_count[0]);
    end else if (errors == 0) begin
      $display("PASS SAME_LINE_BANK0_COUNTS");
    end

    pulse_rst();
    mapping_sel = 2'd0;
    lookup_index[0] = 32'd64;
    for (t = 1; t < 8; t = t + 1) lookup_index[t] = 32'(t);
    tick;
    for (n = 0; n < 4; n = n + 1) ar_before[n] = ar_count[n];
    wait_load();
    while (!error_valid) @(posedge clk);
    #1;
    for (n = 0; n < 4; n = n + 1) begin
      if ((ar_count[n] - ar_before[n]) !== 0) begin
        errors = errors + 1;
        $display("FAIL OOB issued AR on bank %0d", n);
      end
    end
    if (error_mask[0] !== 1'b1) begin
      errors = errors + 1;
      $display("FAIL OOB mask");
    end
    if (errors == 0) $display("PASS OOB");

    if (errors != 0) begin
      $display("TB_A18_9_FOLDED_LOOKUP=FAIL errors=%0d", errors);
      $finish;
    end
    $display("TB_A18_9_FOLDED_LOOKUP=PASS");
    $display("PHYSICAL_HBM=NOT_RUN");
    $display("A13_NUMERIC=NOT_CLAIMED");
    $display("PERFORMANCE=NOT_CLAIMED");
    $finish;
  end

  initial begin
    #300000;
    $display("TB_A18_9_FOLDED_LOOKUP=FAIL timeout");
    $fatal(1);
  end
endmodule
