`timescale 1ns/1ps
// Public-port TB for A18.6 T=8 mapped lookup. Fake AXI only. Not FPGA.
module tb_dlrm_hbm_t8_mapped_lookup_stage2n_a18_6_v1;
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
  logic [15:0] banks_flat;
  logic [15:0] occupancy_flat;
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
  integer bank;
  integer ar_before [0:3];
  integer expect_bank;
  integer expect_occ [0:3];

  function automatic [127:0] golden(input integer row);
    integer lane;
    begin
      golden = 128'd0;
      for (lane = 0; lane < 8; lane = lane + 1) begin
        golden[lane*16 +: 16] = row * 8 + lane - 256;
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

  dlrm_hbm_t8_mapped_lookup_stage2n_a18_6_v1 dut (
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
    .banks_flat(banks_flat),
    .occupancy_flat(occupancy_flat),
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
    for (n = 0; n < 4; n = n + 1) begin
      m_axi_arready[n] = (pending[n] == 0) && !m_axi_rvalid[n];
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

  task automatic run_group(input [1:0] sel, input string name);
    begin
      mapping_sel = sel;
      load_valid = 1'b0;
      error_ready = 1'b1;
      for (t = 0; t < 8; t = t + 1) begin
        lookup_index[t] = 32'(10 + t);
      end
      for (n = 0; n < 4; n = n + 1) begin
        table_base_addr[n] = 64'h0000_0000_0001_0000 + (n * 64'h0001_0000);
        expect_occ[n] = 0;
      end
      tick;
      for (n = 0; n < 4; n = n + 1) begin
        ar_before[n] = ar_count[n];
      end
      begin : wait_load
        load_valid = 1'b1;
        forever begin
          @(posedge clk);
          if (load_ready) begin
            @(negedge clk);
            load_valid = 1'b0;
            disable wait_load;
          end
        end
      end
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
        if (vec[t] !== golden(10 + t)) begin
          errors = errors + 1;
          $display("FAIL %s table %0d vec", name, t);
        end
      end
      for (n = 0; n < 4; n = n + 1) begin
        if (occupancy_flat[(4 * n) +: 4] !== expect_occ[n][3:0]) begin
          errors = errors + 1;
          $display("FAIL %s occupancy bank %0d", name, n);
        end
        if ((ar_count[n] - ar_before[n]) !== expect_occ[n]) begin
          errors = errors + 1;
          $display("FAIL %s AR count bank %0d got %0d exp %0d",
                   name, n, ar_count[n] - ar_before[n], expect_occ[n]);
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
    repeat (4) tick;
    rst = 1'b0;
    repeat (2) tick;
    run_group(2'd0, "IDENT");
    run_group(2'd1, "COACC_SPLIT");
    run_group(2'd2, "FORCE_01");

    mapping_sel = 2'd0;
    lookup_index[0] = 32'd64;
    for (t = 1; t < 8; t = t + 1) lookup_index[t] = 32'(t);
    tick;
    for (n = 0; n < 4; n = n + 1) ar_before[n] = ar_count[n];
    begin : wait_oob
      load_valid = 1'b1;
      forever begin
        @(posedge clk);
        if (load_ready) begin
          @(negedge clk);
          load_valid = 1'b0;
          disable wait_oob;
        end
      end
    end
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
    tick;
    if (errors != 0) begin
      $display("TB_A18_6_T8_LOOKUP=FAIL errors=%0d", errors);
      $fatal(1);
    end
    $display("TB_A18_6_T8_LOOKUP=PASS");
    $display("PHYSICAL_HBM=NOT_RUN");
    $display("A13_NUMERIC=NOT_CLAIMED");
    $display("PERFORMANCE=NOT_CLAIMED");
    $finish;
  end

  initial begin
    #200000;
    $display("TB_A18_6_T8_LOOKUP=FAIL timeout");
    $fatal(1);
  end
endmodule
