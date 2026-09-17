`timescale 1ns/1ps
// Hit/miss TB for the A18.7 one-line cache. Fake AXI through A14 v2.
module tb_dlrm_hbm_bank_line_cache_stage2n_a18_7_v1;
  logic clk = 1'b0;
  logic rst = 1'b1;
  always #5 clk = ~clk;

  logic lookup_req_valid;
  logic lookup_req_ready;
  logic [31:0] lookup_req_index;
  logic lookup_rsp_valid;
  logic lookup_rsp_ready;
  logic [127:0] lookup_rsp_data;
  logic [31:0] lookup_rsp_index;
  logic lookup_rsp_error;
  logic eng_req_valid;
  logic eng_req_ready;
  logic [31:0] eng_req_index;
  logic eng_rsp_valid;
  logic eng_rsp_ready;
  logic [127:0] eng_rsp_data;
  logic [31:0] eng_rsp_index;
  logic eng_rsp_error;
  logic hit;
  logic miss;
  logic [15:0] hit_count;
  logic [15:0] miss_count;

  logic [63:0] table_base_addr;
  logic [0:0] m_axi_arid;
  logic [63:0] m_axi_araddr;
  logic [7:0] m_axi_arlen;
  logic [2:0] m_axi_arsize;
  logic [1:0] m_axi_arburst;
  logic m_axi_arlock;
  logic [3:0] m_axi_arcache;
  logic [2:0] m_axi_arprot;
  logic [3:0] m_axi_arqos;
  logic m_axi_arvalid;
  logic m_axi_arready;
  logic [0:0] m_axi_rid;
  logic [127:0] m_axi_rdata;
  logic [1:0] m_axi_rresp;
  logic m_axi_rlast;
  logic m_axi_rvalid;
  logic m_axi_rready;

  integer ar_count;
  integer pending;
  integer delay_left;
  integer row_hold;
  integer errors;

  function automatic [127:0] golden(input integer row);
    integer lane;
    begin
      golden = 128'd0;
      for (lane = 0; lane < 8; lane = lane + 1) begin
        golden[lane*16 +: 16] = row * 8 + lane - 256;
      end
    end
  endfunction

  dlrm_hbm_bank_line_cache_stage2n_a18_7_v1 u_cache (
    .clk(clk),
    .rst(rst),
    .lookup_req_valid(lookup_req_valid),
    .lookup_req_ready(lookup_req_ready),
    .lookup_req_index(lookup_req_index),
    .lookup_rsp_valid(lookup_rsp_valid),
    .lookup_rsp_ready(lookup_rsp_ready),
    .lookup_rsp_data(lookup_rsp_data),
    .lookup_rsp_index(lookup_rsp_index),
    .lookup_rsp_error(lookup_rsp_error),
    .eng_req_valid(eng_req_valid),
    .eng_req_ready(eng_req_ready),
    .eng_req_index(eng_req_index),
    .eng_rsp_valid(eng_rsp_valid),
    .eng_rsp_ready(eng_rsp_ready),
    .eng_rsp_data(eng_rsp_data),
    .eng_rsp_index(eng_rsp_index),
    .eng_rsp_error(eng_rsp_error),
    .hit(hit),
    .miss(miss),
    .hit_count(hit_count),
    .miss_count(miss_count)
  );

  dlrm_hbm_embedding_lookup_stage2n_a14_v2 #(
    .ROWS(64),
    .INDEX_WIDTH(32)
  ) u_lookup (
    .clk(clk),
    .rst(rst),
    .table_base_addr(table_base_addr),
    .lookup_req_valid(eng_req_valid),
    .lookup_req_ready(eng_req_ready),
    .lookup_req_index(eng_req_index),
    .lookup_rsp_valid(eng_rsp_valid),
    .lookup_rsp_ready(eng_rsp_ready),
    .lookup_rsp_data(eng_rsp_data),
    .lookup_rsp_index(eng_rsp_index),
    .lookup_rsp_error(eng_rsp_error),
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

  assign m_axi_arready = (pending == 0) && !m_axi_rvalid;
  assign m_axi_rid = 1'b0;
  assign m_axi_rlast = 1'b1;

  always @(posedge clk) begin
    if (rst) begin
      pending <= 0;
      delay_left <= 0;
      row_hold <= 0;
      ar_count <= 0;
      m_axi_rvalid <= 1'b0;
      m_axi_rdata <= 128'd0;
      m_axi_rresp <= 2'b00;
    end else begin
      if (m_axi_arvalid && m_axi_arready) begin
        pending <= 1;
        delay_left <= 2;
        row_hold <= (m_axi_araddr - table_base_addr) >> 4;
        ar_count <= ar_count + 1;
      end
      if (pending != 0) begin
        if (delay_left != 0) delay_left <= delay_left - 1;
        else begin
          pending <= 0;
          m_axi_rvalid <= 1'b1;
          m_axi_rdata <= golden(row_hold);
          m_axi_rresp <= 2'b00;
        end
      end
      if (m_axi_rvalid && m_axi_rready) m_axi_rvalid <= 1'b0;
    end
  end

  task automatic tick;
    begin
      @(posedge clk);
      #1;
    end
  endtask

  task automatic one_lookup(input integer row);
    begin
      lookup_req_index = row;
      begin : wait_req
        lookup_req_valid = 1'b1;
        forever begin
          @(posedge clk);
          if (lookup_req_ready) begin
            @(negedge clk);
            lookup_req_valid = 1'b0;
            disable wait_req;
          end
        end
      end
      while (!lookup_rsp_valid) @(posedge clk);
      #1;
      if (lookup_rsp_data !== golden(row) || lookup_rsp_error !== 1'b0 ||
          lookup_rsp_index !== row) begin
        errors = errors + 1;
        $display("FAIL lookup row %0d", row);
      end
      lookup_rsp_ready = 1'b1;
      @(posedge clk);
      @(negedge clk);
      lookup_rsp_ready = 1'b0;
    end
  endtask

  initial begin
    errors = 0;
    lookup_req_valid = 1'b0;
    lookup_rsp_ready = 1'b0;
    lookup_req_index = 32'd0;
    table_base_addr = 64'h0000_0000_0002_0000;
    repeat (4) tick;
    rst = 1'b0;
    repeat (2) tick;
    one_lookup(7);
    if (ar_count !== 1 || miss_count !== 16'd1 || hit_count !== 16'd0) begin
      errors = errors + 1;
      $display("FAIL first miss AR=%0d miss=%0d hit=%0d",
               ar_count, miss_count, hit_count);
    end
    one_lookup(7);
    if (ar_count !== 1 || miss_count !== 16'd1 || hit_count !== 16'd1) begin
      errors = errors + 1;
      $display("FAIL second hit AR=%0d miss=%0d hit=%0d",
               ar_count, miss_count, hit_count);
    end
    one_lookup(8);
    if (ar_count !== 2 || miss_count !== 16'd2 || hit_count !== 16'd1) begin
      errors = errors + 1;
      $display("FAIL third miss AR=%0d miss=%0d hit=%0d",
               ar_count, miss_count, hit_count);
    end
    if (errors != 0) begin
      $display("TB_A18_7_LINE_CACHE=FAIL errors=%0d", errors);
      $fatal(1);
    end
    $display("TB_A18_7_LINE_CACHE=PASS");
    $display("PHYSICAL_HBM=NOT_RUN");
    $display("PERFORMANCE=NOT_CLAIMED");
    $finish;
  end

  initial begin
    #100000;
    $display("TB_A18_7_LINE_CACHE=FAIL timeout");
    $fatal(1);
  end
endmodule
