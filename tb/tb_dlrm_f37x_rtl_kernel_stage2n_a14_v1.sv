`timescale 1ns/1ps

module tb_dlrm_f37x_rtl_kernel_stage2n_a14_v1;

    localparam integer CONTROL_ADDR_WIDTH = 12;
    localparam integer CONTROL_DATA_WIDTH = 32;
    localparam integer GMEM_ADDR_WIDTH = 64;
    localparam integer GMEM_DATA_WIDTH = 128;
    localparam integer GMEM_ID_WIDTH = 1;

    localparam logic [CONTROL_ADDR_WIDTH-1:0]
        ADDR_CONTROL      = 12'h000;
    localparam logic [CONTROL_ADDR_WIDTH-1:0]
        ADDR_LOOKUP_INDEX = 12'h010;
    localparam logic [CONTROL_ADDR_WIDTH-1:0]
        ADDR_RESULT0      = 12'h020;
    localparam logic [CONTROL_ADDR_WIDTH-1:0]
        ADDR_RESULT1      = 12'h024;
    localparam logic [CONTROL_ADDR_WIDTH-1:0]
        ADDR_RESULT2      = 12'h028;
    localparam logic [CONTROL_ADDR_WIDTH-1:0]
        ADDR_RESULT3      = 12'h02C;

    logic ap_clk;
    logic ap_rst_n;

    logic [CONTROL_ADDR_WIDTH-1:0] s_axi_control_awaddr;
    logic s_axi_control_awvalid;
    logic s_axi_control_awready;
    logic [CONTROL_DATA_WIDTH-1:0] s_axi_control_wdata;
    logic [(CONTROL_DATA_WIDTH/8)-1:0] s_axi_control_wstrb;
    logic s_axi_control_wvalid;
    logic s_axi_control_wready;
    logic [1:0] s_axi_control_bresp;
    logic s_axi_control_bvalid;
    logic s_axi_control_bready;
    logic [CONTROL_ADDR_WIDTH-1:0] s_axi_control_araddr;
    logic s_axi_control_arvalid;
    logic s_axi_control_arready;
    logic [CONTROL_DATA_WIDTH-1:0] s_axi_control_rdata;
    logic [1:0] s_axi_control_rresp;
    logic s_axi_control_rvalid;
    logic s_axi_control_rready;

    logic [GMEM_ID_WIDTH-1:0] m_axi_gmem_awid;
    logic [GMEM_ADDR_WIDTH-1:0] m_axi_gmem_awaddr;
    logic [7:0] m_axi_gmem_awlen;
    logic [2:0] m_axi_gmem_awsize;
    logic [1:0] m_axi_gmem_awburst;
    logic m_axi_gmem_awlock;
    logic [3:0] m_axi_gmem_awcache;
    logic [2:0] m_axi_gmem_awprot;
    logic [3:0] m_axi_gmem_awqos;
    logic m_axi_gmem_awvalid;
    logic m_axi_gmem_awready;
    logic [GMEM_DATA_WIDTH-1:0] m_axi_gmem_wdata;
    logic [(GMEM_DATA_WIDTH/8)-1:0] m_axi_gmem_wstrb;
    logic m_axi_gmem_wlast;
    logic m_axi_gmem_wvalid;
    logic m_axi_gmem_wready;
    logic [GMEM_ID_WIDTH-1:0] m_axi_gmem_bid;
    logic [1:0] m_axi_gmem_bresp;
    logic m_axi_gmem_bvalid;
    logic m_axi_gmem_bready;
    logic [GMEM_ID_WIDTH-1:0] m_axi_gmem_arid;
    logic [GMEM_ADDR_WIDTH-1:0] m_axi_gmem_araddr;
    logic [7:0] m_axi_gmem_arlen;
    logic [2:0] m_axi_gmem_arsize;
    logic [1:0] m_axi_gmem_arburst;
    logic m_axi_gmem_arlock;
    logic [3:0] m_axi_gmem_arcache;
    logic [2:0] m_axi_gmem_arprot;
    logic [3:0] m_axi_gmem_arqos;
    logic m_axi_gmem_arvalid;
    logic m_axi_gmem_arready;
    logic [GMEM_ID_WIDTH-1:0] m_axi_gmem_rid;
    logic [GMEM_DATA_WIDTH-1:0] m_axi_gmem_rdata;
    logic [1:0] m_axi_gmem_rresp;
    logic m_axi_gmem_rlast;
    logic m_axi_gmem_rvalid;
    logic m_axi_gmem_rready;

    logic [GMEM_DATA_WIDTH-1:0] fake_memory [0:63];
    logic read_pending;
    logic [5:0] pending_row;
    logic [GMEM_ID_WIDTH-1:0] pending_id;
    integer ar_delay_count;
    integer r_delay_count;
    integer ar_handshake_count;
    integer r_handshake_count;
    integer pass_count;
    integer current_expected_index;
    logic [GMEM_ADDR_WIDTH-1:0] current_expected_address;

    integer row_index;
    integer lane_index;
    integer random_seed;
    integer random_index;
    integer random_case;

    function automatic logic [GMEM_DATA_WIDTH-1:0] golden_row(
        input integer row
    );
        integer lane;
        integer element_value;
        begin
            golden_row = '0;
            for (lane = 0; lane < 8; lane = lane + 1) begin
                element_value = row * 8 + lane - 256;
                golden_row[lane*16 +: 16] = element_value;
            end
        end
    endfunction

    task automatic axi_lite_write(
        input logic [CONTROL_ADDR_WIDTH-1:0] address,
        input logic [CONTROL_DATA_WIDTH-1:0] data
    );
        integer aw_finished;
        integer w_finished;
        integer timeout_cycles;
        begin
            aw_finished = 0;
            w_finished = 0;
            timeout_cycles = 0;

            @(negedge ap_clk);
            s_axi_control_awaddr = address;
            s_axi_control_awvalid = 1'b1;
            s_axi_control_wdata = data;
            s_axi_control_wstrb = 4'hF;
            s_axi_control_wvalid = 1'b1;

            while (!(aw_finished && w_finished)) begin
                @(posedge ap_clk);
                if (s_axi_control_awvalid && s_axi_control_awready)
                    aw_finished = 1;
                if (s_axi_control_wvalid && s_axi_control_wready)
                    w_finished = 1;
                timeout_cycles = timeout_cycles + 1;
                if (timeout_cycles > 50)
                    $fatal(1, "AXI-Lite write handshake timeout at 0x%0h",
                           address);

                @(negedge ap_clk);
                if (aw_finished)
                    s_axi_control_awvalid = 1'b0;
                if (w_finished)
                    s_axi_control_wvalid = 1'b0;
            end

            timeout_cycles = 0;
            while (!s_axi_control_bvalid) begin
                @(posedge ap_clk);
                timeout_cycles = timeout_cycles + 1;
                if (timeout_cycles > 50)
                    $fatal(1, "AXI-Lite write response timeout at 0x%0h",
                           address);
            end

            if (s_axi_control_bresp !== 2'b00)
                $fatal(1,
                       "AXI-Lite write failed at 0x%0h, BRESP=%0b",
                       address, s_axi_control_bresp);
        end
    endtask

    task automatic axi_lite_read(
        input logic [CONTROL_ADDR_WIDTH-1:0] address,
        output logic [CONTROL_DATA_WIDTH-1:0] data
    );
        integer timeout_cycles;
        begin
            timeout_cycles = 0;

            @(negedge ap_clk);
            s_axi_control_araddr = address;
            s_axi_control_arvalid = 1'b1;

            while (!(s_axi_control_arvalid &&
                     s_axi_control_arready)) begin
                @(posedge ap_clk);
                timeout_cycles = timeout_cycles + 1;
                if (timeout_cycles > 50)
                    $fatal(1, "AXI-Lite read address timeout at 0x%0h",
                           address);
            end

            @(posedge ap_clk);
            @(negedge ap_clk);
            s_axi_control_arvalid = 1'b0;

            timeout_cycles = 0;
            while (!s_axi_control_rvalid) begin
                @(posedge ap_clk);
                timeout_cycles = timeout_cycles + 1;
                if (timeout_cycles > 50)
                    $fatal(1, "AXI-Lite read response timeout at 0x%0h",
                           address);
            end

            if (s_axi_control_rresp !== 2'b00)
                $fatal(1,
                       "AXI-Lite read failed at 0x%0h, RRESP=%0b",
                       address, s_axi_control_rresp);
            data = s_axi_control_rdata;
        end
    endtask

    task automatic wait_for_done(
        output logic [31:0] final_control
    );
        integer poll_count;
        integer done_seen;
        logic [31:0] control_word;
        begin
            poll_count = 0;
            done_seen = 0;
            control_word = 32'd0;

            while (!done_seen && poll_count < 200) begin
                axi_lite_read(ADDR_CONTROL, control_word);
                if (control_word[4] !== 1'b0)
                    $fatal(1,
                           "Lookup error asserted for index %0d",
                           current_expected_index);
                done_seen = control_word[1];
                poll_count = poll_count + 1;
            end

            if (!done_seen)
                $fatal(1, "Done timeout for index %0d",
                       current_expected_index);

            final_control = control_word;
        end
    endtask

    task automatic run_lookup_case(
        input integer test_index,
        input string case_name
    );
        integer ar_count_before;
        integer r_count_before;
        logic [31:0] control_word;
        logic [31:0] result0;
        logic [31:0] result1;
        logic [31:0] result2;
        logic [31:0] result3;
        logic [127:0] observed_vector;
        logic [127:0] expected_vector;
        begin
            current_expected_index = test_index;
            current_expected_address = test_index * 16;
            ar_count_before = ar_handshake_count;
            r_count_before = r_handshake_count;
            expected_vector = golden_row(test_index);

            axi_lite_write(ADDR_LOOKUP_INDEX, test_index);
            axi_lite_write(ADDR_CONTROL, 32'h0000_0001);
            wait_for_done(control_word);

            if (control_word[1] !== 1'b1 ||
                control_word[4] !== 1'b0)
                $fatal(1,
                       "Bad final control state for index %0d: 0x%08h",
                       test_index, control_word);

            axi_lite_read(ADDR_RESULT0, result0);
            axi_lite_read(ADDR_RESULT1, result1);
            axi_lite_read(ADDR_RESULT2, result2);
            axi_lite_read(ADDR_RESULT3, result3);
            observed_vector = {result3, result2, result1, result0};

            if (observed_vector !== expected_vector)
                $fatal(1,
                       "Result mismatch for index %0d: got=%032h expected=%032h",
                       test_index, observed_vector, expected_vector);

            if (ar_handshake_count != ar_count_before + 1)
                $fatal(1,
                       "Index %0d issued %0d AR handshakes instead of one",
                       test_index,
                       ar_handshake_count - ar_count_before);
            if (r_handshake_count != r_count_before + 1)
                $fatal(1,
                       "Index %0d completed %0d R handshakes instead of one",
                       test_index,
                       r_handshake_count - r_count_before);

            axi_lite_read(ADDR_CONTROL, control_word);
            if (control_word[1] !== 1'b0 ||
                control_word[4] !== 1'b0 ||
                control_word[2] !== 1'b1 ||
                control_word[3] !== 1'b1)
                $fatal(1,
                       "Control did not return idle after index %0d: 0x%08h",
                       test_index, control_word);

            pass_count = pass_count + 1;
            $display("PASS case=%0s index=%0d result=%032h",
                     case_name, test_index, observed_vector);
        end
    endtask

    assign m_axi_gmem_awready = 1'b0;
    assign m_axi_gmem_wready = 1'b0;
    assign m_axi_gmem_bid = '0;
    assign m_axi_gmem_bresp = 2'b00;
    assign m_axi_gmem_bvalid = 1'b0;

    always #5 ap_clk = ~ap_clk;

    // Fake single-bank AXI memory. Each request is held off for two cycles so
    // the DUT must retain a stable AR payload under backpressure.
    always_ff @(posedge ap_clk) begin
        if (!ap_rst_n) begin
            m_axi_gmem_arready <= 1'b0;
            m_axi_gmem_rid <= '0;
            m_axi_gmem_rdata <= '0;
            m_axi_gmem_rresp <= 2'b00;
            m_axi_gmem_rlast <= 1'b1;
            m_axi_gmem_rvalid <= 1'b0;
            read_pending <= 1'b0;
            pending_row <= '0;
            pending_id <= '0;
            ar_delay_count <= 0;
            r_delay_count <= 0;
            ar_handshake_count <= 0;
            r_handshake_count <= 0;
        end else begin
            m_axi_gmem_arready <= 1'b0;

            if (!read_pending && !m_axi_gmem_rvalid) begin
                if (m_axi_gmem_arvalid) begin
                    if (ar_delay_count < 2)
                        ar_delay_count <= ar_delay_count + 1;
                    else
                        m_axi_gmem_arready <= 1'b1;
                end else begin
                    ar_delay_count <= 0;
                end
            end

            if (m_axi_gmem_arvalid && m_axi_gmem_arready) begin
                if (read_pending || m_axi_gmem_rvalid)
                    $fatal(1, "More than one AXI read is outstanding");
                if (m_axi_gmem_arid !== '0)
                    $fatal(1, "Unexpected ARID %0h", m_axi_gmem_arid);
                if (m_axi_gmem_arlen !== 8'd0)
                    $fatal(1, "ARLEN must be zero, got %0d",
                           m_axi_gmem_arlen);
                if (m_axi_gmem_arsize !== 3'd4)
                    $fatal(1, "ARSIZE must encode 16 bytes, got %0d",
                           m_axi_gmem_arsize);
                if (m_axi_gmem_arburst !== 2'b01)
                    $fatal(1, "ARBURST must be INCR, got %0b",
                           m_axi_gmem_arburst);
                if (m_axi_gmem_araddr[3:0] !== 4'd0 ||
                    m_axi_gmem_araddr >= 64'd1024)
                    $fatal(1, "Out-of-range or unaligned ARADDR 0x%0h",
                           m_axi_gmem_araddr);
                if (m_axi_gmem_araddr !== current_expected_address)
                    $fatal(1,
                           "Wrong ARADDR for index %0d: got=0x%0h expected=0x%0h",
                           current_expected_index,
                           m_axi_gmem_araddr,
                           current_expected_address);

                pending_row <= m_axi_gmem_araddr[9:4];
                pending_id <= m_axi_gmem_arid;
                read_pending <= 1'b1;
                r_delay_count <= 2;
                ar_delay_count <= 0;
                ar_handshake_count <= ar_handshake_count + 1;
            end

            if (read_pending) begin
                if (r_delay_count > 0) begin
                    r_delay_count <= r_delay_count - 1;
                end else if (!m_axi_gmem_rvalid) begin
                    m_axi_gmem_rid <= pending_id;
                    m_axi_gmem_rdata <= fake_memory[pending_row];
                    m_axi_gmem_rresp <= 2'b00;
                    m_axi_gmem_rlast <= 1'b1;
                    m_axi_gmem_rvalid <= 1'b1;
                    read_pending <= 1'b0;
                end
            end

            if (m_axi_gmem_rvalid && m_axi_gmem_rready) begin
                m_axi_gmem_rvalid <= 1'b0;
                r_handshake_count <= r_handshake_count + 1;
            end

            if (m_axi_gmem_awvalid || m_axi_gmem_wvalid ||
                m_axi_gmem_bready)
                $fatal(1, "Read-only wrapper activated an AXI write channel");
        end
    end

    initial begin
        for (row_index = 0; row_index < 64;
             row_index = row_index + 1) begin
            fake_memory[row_index] = '0;
            for (lane_index = 0; lane_index < 8;
                 lane_index = lane_index + 1) begin
                fake_memory[row_index][lane_index*16 +: 16] =
                    row_index * 8 + lane_index - 256;
            end
        end
    end

    initial begin
        ap_clk = 1'b0;
        ap_rst_n = 1'b0;

        s_axi_control_awaddr = '0;
        s_axi_control_awvalid = 1'b0;
        s_axi_control_wdata = '0;
        s_axi_control_wstrb = '0;
        s_axi_control_wvalid = 1'b0;
        s_axi_control_bready = 1'b1;
        s_axi_control_araddr = '0;
        s_axi_control_arvalid = 1'b0;
        s_axi_control_rready = 1'b1;

        pass_count = 0;
        current_expected_index = 0;
        current_expected_address = 64'd0;

        repeat (8) @(posedge ap_clk);
        @(negedge ap_clk);
        ap_rst_n = 1'b1;

        repeat (2) @(posedge ap_clk);

        run_lookup_case(0, "directed_0");
        run_lookup_case(1, "directed_1");
        run_lookup_case(31, "directed_31");
        run_lookup_case(63, "directed_63");

        random_seed = 32'h14A3_A002;
        random_index = $urandom(random_seed);
        for (random_case = 0; random_case < 10;
             random_case = random_case + 1) begin
            random_index = $urandom_range(63, 0);
            run_lookup_case(
                random_index,
                $sformatf("random_%0d", random_case)
            );
        end

        if (pass_count != 14)
            $fatal(1, "Expected 14 passing cases, got %0d", pass_count);
        if (ar_handshake_count != 14 || r_handshake_count != 14)
            $fatal(1,
                   "Expected 14 AR/R handshakes, got AR=%0d R=%0d",
                   ar_handshake_count, r_handshake_count);

        $display(
            "tb_dlrm_f37x_rtl_kernel_stage2n_a14_v1: PASS cases=%0d ar=%0d r=%0d",
            pass_count, ar_handshake_count, r_handshake_count
        );
        $finish;
    end

    initial begin
        #2000000;
        $fatal(1, "Global simulation timeout");
    end

    dlrm_f37x_rtl_kernel_stage2n_a14_v1 #(
        .C_S_AXI_CONTROL_ADDR_WIDTH(CONTROL_ADDR_WIDTH),
        .C_S_AXI_CONTROL_DATA_WIDTH(CONTROL_DATA_WIDTH),
        .C_M_AXI_GMEM_ADDR_WIDTH(GMEM_ADDR_WIDTH),
        .C_M_AXI_GMEM_DATA_WIDTH(GMEM_DATA_WIDTH),
        .C_M_AXI_GMEM_ID_WIDTH(GMEM_ID_WIDTH),
        .ROWS(64),
        .DIM(8),
        .ELEMENT_WIDTH(16)
    ) dut (
        .ap_clk(ap_clk),
        .ap_rst_n(ap_rst_n),

        .s_axi_control_awaddr(s_axi_control_awaddr),
        .s_axi_control_awvalid(s_axi_control_awvalid),
        .s_axi_control_awready(s_axi_control_awready),
        .s_axi_control_wdata(s_axi_control_wdata),
        .s_axi_control_wstrb(s_axi_control_wstrb),
        .s_axi_control_wvalid(s_axi_control_wvalid),
        .s_axi_control_wready(s_axi_control_wready),
        .s_axi_control_bresp(s_axi_control_bresp),
        .s_axi_control_bvalid(s_axi_control_bvalid),
        .s_axi_control_bready(s_axi_control_bready),
        .s_axi_control_araddr(s_axi_control_araddr),
        .s_axi_control_arvalid(s_axi_control_arvalid),
        .s_axi_control_arready(s_axi_control_arready),
        .s_axi_control_rdata(s_axi_control_rdata),
        .s_axi_control_rresp(s_axi_control_rresp),
        .s_axi_control_rvalid(s_axi_control_rvalid),
        .s_axi_control_rready(s_axi_control_rready),

        .m_axi_gmem_awid(m_axi_gmem_awid),
        .m_axi_gmem_awaddr(m_axi_gmem_awaddr),
        .m_axi_gmem_awlen(m_axi_gmem_awlen),
        .m_axi_gmem_awsize(m_axi_gmem_awsize),
        .m_axi_gmem_awburst(m_axi_gmem_awburst),
        .m_axi_gmem_awlock(m_axi_gmem_awlock),
        .m_axi_gmem_awcache(m_axi_gmem_awcache),
        .m_axi_gmem_awprot(m_axi_gmem_awprot),
        .m_axi_gmem_awqos(m_axi_gmem_awqos),
        .m_axi_gmem_awvalid(m_axi_gmem_awvalid),
        .m_axi_gmem_awready(m_axi_gmem_awready),
        .m_axi_gmem_wdata(m_axi_gmem_wdata),
        .m_axi_gmem_wstrb(m_axi_gmem_wstrb),
        .m_axi_gmem_wlast(m_axi_gmem_wlast),
        .m_axi_gmem_wvalid(m_axi_gmem_wvalid),
        .m_axi_gmem_wready(m_axi_gmem_wready),
        .m_axi_gmem_bid(m_axi_gmem_bid),
        .m_axi_gmem_bresp(m_axi_gmem_bresp),
        .m_axi_gmem_bvalid(m_axi_gmem_bvalid),
        .m_axi_gmem_bready(m_axi_gmem_bready),
        .m_axi_gmem_arid(m_axi_gmem_arid),
        .m_axi_gmem_araddr(m_axi_gmem_araddr),
        .m_axi_gmem_arlen(m_axi_gmem_arlen),
        .m_axi_gmem_arsize(m_axi_gmem_arsize),
        .m_axi_gmem_arburst(m_axi_gmem_arburst),
        .m_axi_gmem_arlock(m_axi_gmem_arlock),
        .m_axi_gmem_arcache(m_axi_gmem_arcache),
        .m_axi_gmem_arprot(m_axi_gmem_arprot),
        .m_axi_gmem_arqos(m_axi_gmem_arqos),
        .m_axi_gmem_arvalid(m_axi_gmem_arvalid),
        .m_axi_gmem_arready(m_axi_gmem_arready),
        .m_axi_gmem_rid(m_axi_gmem_rid),
        .m_axi_gmem_rdata(m_axi_gmem_rdata),
        .m_axi_gmem_rresp(m_axi_gmem_rresp),
        .m_axi_gmem_rlast(m_axi_gmem_rlast),
        .m_axi_gmem_rvalid(m_axi_gmem_rvalid),
        .m_axi_gmem_rready(m_axi_gmem_rready)
    );

endmodule
