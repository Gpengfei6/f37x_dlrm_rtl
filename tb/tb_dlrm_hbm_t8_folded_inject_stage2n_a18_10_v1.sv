`timescale 1ns/1ps
// A18.10 TB: A18.9 folded lookup plus sequential A13-style inject.
// Fold is not an A13 DLRM golden. Does not instantiate A13.
module tb_dlrm_hbm_t8_folded_inject_stage2n_a18_10_v1;
  logic clk = 1'b0;
  logic rst = 1'b1;
  always #5 clk = ~clk;

  logic [1:0] mapping_sel;
  logic load_valid;
  logic load_ready;
  logic [3:0][63:0] table_base_addr;
  logic [7:0][31:0] lookup_index;
  logic busy;
  logic all_loaded;
  logic done;
  logic error_valid;
  logic error_ready;
  logic [7:0] error_mask;
  logic [3:0] committed_mask;
  logic cfg_valid;
  logic cfg_ready;
  logic [1:0] cfg_index;
  logic [127:0] cfg_data;
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
  integer idx_hold [0:7];
  integer inject_seen;
  integer hold_cycles;
  integer guard;
  logic [127:0] first_cfg;

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

  dlrm_hbm_t8_folded_inject_stage2n_a18_10_v1 dut (
    .clk(clk),
    .rst(rst),
    .mapping_sel(mapping_sel),
    .load_valid(load_valid),
    .load_ready(load_ready),
    .table_base_addr(table_base_addr),
    .lookup_index(lookup_index),
    .busy(busy),
    .all_loaded(all_loaded),
    .done(done),
    .error_valid(error_valid),
    .error_ready(error_ready),
    .error_mask(error_mask),
    .committed_mask(committed_mask),
    .cfg_valid(cfg_valid),
    .cfg_ready(cfg_ready),
    .cfg_index(cfg_index),
    .cfg_data(cfg_data),
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
      cfg_ready = 1'b0;
      error_ready = 1'b1;
      repeat (3) tick;
      rst = 1'b0;
      repeat (2) tick;
    end
  endtask

  task automatic set_unique_indexes;
    begin
      for (t = 0; t < 8; t = t + 1) begin
        lookup_index[t] = 32'(10 + t);
        idx_hold[t] = 10 + t;
      end
      for (n = 0; n < 4; n = n + 1) begin
        table_base_addr[n] = 64'h0000_0000_0001_0000 + (n * 64'h0001_0000);
      end
      mapping_sel = 2'd0;
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

  task automatic accept_one(input integer exp_idx, input integer expect_hold);
    begin
      cfg_ready = 1'b0;
      guard = 0;
      while (!cfg_valid && !error_valid && guard < 400) begin
        @(posedge clk);
        #1;
        guard = guard + 1;
      end
      if (error_valid || !cfg_valid) begin
        errors = errors + 1;
        $display("FAIL missing cfg slot %0d", exp_idx);
      end else begin
        if (cfg_index !== exp_idx[1:0]) begin
          errors = errors + 1;
          $display("FAIL cfg_index got %0d exp %0d", cfg_index, exp_idx);
        end
        if (cfg_data !== fold_pair(idx_hold[exp_idx], idx_hold[exp_idx + 4])) begin
          errors = errors + 1;
          $display("FAIL cfg_data slot %0d", exp_idx);
        end
        first_cfg = cfg_data;
        for (hold_cycles = 0; hold_cycles < expect_hold; hold_cycles = hold_cycles + 1) begin
          @(posedge clk);
          #1;
          if (!cfg_valid || cfg_index !== exp_idx[1:0] || cfg_data !== first_cfg) begin
            errors = errors + 1;
            $display("FAIL BACKPRESSURE dropped slot %0d", exp_idx);
          end
        end
        @(negedge clk);
        cfg_ready = 1'b1;
        @(posedge clk);
        #1;
        cfg_ready = 1'b0;
      end
    end
  endtask

  task automatic collect_injects(input integer expect_hold);
    begin
      for (inject_seen = 0; inject_seen < 4; inject_seen = inject_seen + 1) begin
        if (inject_seen == 0) accept_one(inject_seen, expect_hold);
        else accept_one(inject_seen, 0);
      end
      guard = 0;
      while (!all_loaded && guard < 20) begin
        @(posedge clk);
        #1;
        guard = guard + 1;
      end
      if (!all_loaded || committed_mask !== 4'hF) begin
        errors = errors + 1;
        $display("FAIL committed_mask/all_loaded");
      end
      for (t = 0; t < 4; t = t + 1) begin
        if (slot[t] !== fold_pair(idx_hold[t], idx_hold[t + 4])) begin
          errors = errors + 1;
          $display("FAIL captured slot %0d", t);
        end
      end
    end
  endtask

  initial begin
    errors = 0;
    load_valid = 1'b0;
    cfg_ready = 1'b0;
    error_ready = 1'b1;
    mapping_sel = 2'd0;
    lookup_index = '0;
    table_base_addr = '0;
    pulse_rst();
    set_unique_indexes();
    wait_load();
    collect_injects(5);
    if (errors == 0) $display("PASS IDENT_INJECT");
    if (errors == 0) $display("PASS BACKPRESSURE");

    set_unique_indexes();
    wait_load();
    collect_injects(0);
    if (errors == 0) $display("PASS SECOND_GROUP");

    pulse_rst();
    set_unique_indexes();
    lookup_index[0] = 32'd64;
    idx_hold[0] = 64;
    wait_load();
    begin : oob_wait
      integer guard;
      guard = 0;
      while (!error_valid && guard < 200) begin
        @(posedge clk);
        #1;
        if (cfg_valid) begin
          errors = errors + 1;
          $display("FAIL OOB issued cfg");
        end
        guard = guard + 1;
      end
    end
    if (!error_valid || error_mask[0] !== 1'b1) begin
      errors = errors + 1;
      $display("FAIL OOB mask");
    end
    if (errors == 0) $display("PASS OOB");

    if (errors != 0) begin
      $display("TB_A18_10_FOLDED_INJECT=FAIL errors=%0d", errors);
      $finish;
    end
    $display("TB_A18_10_FOLDED_INJECT=PASS");
    $display("A13_INSTANTIATED=NO");
    $display("PHYSICAL_HBM=NOT_RUN");
    $display("PERFORMANCE=NOT_CLAIMED");
    $finish;
  end

  initial begin
    #300000;
    $display("TB_A18_10_FOLDED_INJECT=FAIL timeout");
    $finish;
  end
endmodule
