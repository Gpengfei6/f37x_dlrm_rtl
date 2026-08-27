`timescale 1ns/1ps

module tb_dlrm_f37x_rtl_kernel_stage2n_a15_v1;

    localparam integer ADDR_WIDTH = 12;

    localparam logic [ADDR_WIDTH-1:0] ADDR_MLP_VERSION = 12'h004;
    localparam logic [ADDR_WIDTH-1:0] ADDR_INT_VERSION = 12'h104;

    localparam logic [ADDR_WIDTH-1:0]
        ADDR_PIPE_CONTROL_STATUS = 12'h180;
    localparam logic [ADDR_WIDTH-1:0]
        ADDR_PIPE_VERSION = 12'h184;
    localparam logic [ADDR_WIDTH-1:0]
        ADDR_PIPE_RESULT_COUNT = 12'h188;
    localparam logic [ADDR_WIDTH-1:0]
        ADDR_PIPE_PHASE_COUNTS = 12'h18C;
    localparam logic [ADDR_WIDTH-1:0]
        ADDR_PIPE_DESC_INDEX = 12'h190;
    localparam logic [ADDR_WIDTH-1:0]
        ADDR_PIPE_DESC_WORD0 = 12'h194;
    localparam logic [ADDR_WIDTH-1:0]
        ADDR_PIPE_DESC_WORD1 = 12'h198;
    localparam logic [ADDR_WIDTH-1:0]
        ADDR_PIPE_DESC_WORD2 = 12'h19C;
    localparam logic [ADDR_WIDTH-1:0]
        ADDR_PIPE_ACT_BUFFER = 12'h1A0;
    localparam logic [ADDR_WIDTH-1:0]
        ADDR_PIPE_ACT_CHUNK_INDEX = 12'h1A4;
    localparam logic [ADDR_WIDTH-1:0]
        ADDR_PIPE_ACT_LANE_MASK = 12'h1A8;
    localparam logic [ADDR_WIDTH-1:0]
        ADDR_PIPE_ACT_DATA0 = 12'h1B0;
    localparam logic [ADDR_WIDTH-1:0]
        ADDR_PIPE_ACT_DATA1 = 12'h1B4;
    localparam logic [ADDR_WIDTH-1:0]
        ADDR_PIPE_ACT_DATA2 = 12'h1B8;
    localparam logic [ADDR_WIDTH-1:0]
        ADDR_PIPE_ACT_DATA3 = 12'h1BC;
    localparam logic [ADDR_WIDTH-1:0]
        ADDR_PIPE_ACT_DATA4 = 12'h1C0;
    localparam logic [ADDR_WIDTH-1:0]
        ADDR_PIPE_ACT_DATA5 = 12'h1C4;
    localparam logic [ADDR_WIDTH-1:0]
        ADDR_PIPE_ACT_DATA6 = 12'h1C8;
    localparam logic [ADDR_WIDTH-1:0]
        ADDR_PIPE_ACT_DATA7 = 12'h1CC;
    localparam logic [ADDR_WIDTH-1:0]
        ADDR_PIPE_EMB_INDEX = 12'h1D0;
    localparam logic [ADDR_WIDTH-1:0]
        ADDR_PIPE_EMB_DATA0 = 12'h1D4;
    localparam logic [ADDR_WIDTH-1:0]
        ADDR_PIPE_EMB_DATA1 = 12'h1D8;
    localparam logic [ADDR_WIDTH-1:0]
        ADDR_PIPE_EMB_DATA2 = 12'h1DC;
    localparam logic [ADDR_WIDTH-1:0]
        ADDR_PIPE_EMB_DATA3 = 12'h1E0;
    localparam logic [ADDR_WIDTH-1:0]
        ADDR_PIPE_WEIGHT_ADDRESS = 12'h1E4;
    localparam logic [ADDR_WIDTH-1:0]
        ADDR_PIPE_WEIGHT_DATA = 12'h1E8;
    localparam logic [ADDR_WIDTH-1:0]
        ADDR_PIPE_BIAS_ADDRESS = 12'h1EC;
    localparam logic [ADDR_WIDTH-1:0]
        ADDR_PIPE_BIAS_DATA = 12'h1F0;
    localparam logic [ADDR_WIDTH-1:0]
        ADDR_PIPE_BOTTOM_CONFIG = 12'h1F4;
    localparam logic [ADDR_WIDTH-1:0]
        ADDR_PIPE_TOP_CONFIG = 12'h1F8;
    localparam logic [ADDR_WIDTH-1:0]
        ADDR_PIPELINE_CONFIG = 12'h1FC;
    localparam logic [ADDR_WIDTH-1:0]
        ADDR_PIPE_RESULT_DATA = 12'h200;
    localparam logic [ADDR_WIDTH-1:0]
        ADDR_PIPE_RESULT_INDEX = 12'h204;
    localparam logic [ADDR_WIDTH-1:0]
        ADDR_PIPE_RESULT_META = 12'h208;
    localparam logic [ADDR_WIDTH-1:0]
        ADDR_PIPE_EMB_LOADED_MASK = 12'h20C;
    localparam logic [ADDR_WIDTH-1:0]
        ADDR_PIPE_BOTTOM_CYCLES = 12'h218;
    localparam logic [ADDR_WIDTH-1:0]
        ADDR_PIPE_INTERACTION_CYCLES = 12'h21C;
    localparam logic [ADDR_WIDTH-1:0]
        ADDR_PIPE_TOP_CYCLES = 12'h220;
    localparam logic [ADDR_WIDTH-1:0]
        ADDR_PIPE_TOTAL_CYCLES = 12'h224;
    localparam logic [ADDR_WIDTH-1:0]
        ADDR_PIPE_ERROR_CODE = 12'h210;

    localparam logic [ADDR_WIDTH-1:0]
        ADDR_A15_CONTROL_STATUS = 12'h300;
    localparam logic [ADDR_WIDTH-1:0]
        ADDR_A15_TABLE_BASE_LO = 12'h304;
    localparam logic [ADDR_WIDTH-1:0]
        ADDR_A15_TABLE_BASE_HI = 12'h308;

    localparam logic [63:0] TABLE_BASE = 64'h0000_0001_2345_6000;
    localparam integer ROW0 = 37;
    localparam integer ROW1 = 38;
    localparam integer ROW2 = 39;
    localparam integer ROW3 = 40;

    localparam logic [31:0] PIPE_CMD_DESC_COMMIT = 32'h0000_0001;
    localparam logic [31:0] PIPE_CMD_ACT_COMMIT = 32'h0000_0002;
    localparam logic [31:0] PIPE_CMD_EMB_COMMIT = 32'h0000_0004;
    localparam logic [31:0] PIPE_CMD_WEIGHT_COMMIT = 32'h0000_0008;
    localparam logic [31:0] PIPE_CMD_BIAS_COMMIT = 32'h0000_0010;
    localparam logic [31:0] PIPE_CMD_START = 32'h0000_0020;
    localparam logic [31:0] PIPE_CMD_RESULT_POP = 32'h0000_0040;
    localparam logic [31:0] PIPE_CMD_ERROR_ACK = 32'h0000_0080;
    localparam logic [31:0] PIPE_CMD_CLEAR_DONE = 32'h0000_0100;
    localparam logic [31:0] A15_CMD_START = 32'h0000_0001;
    localparam logic [31:0] A15_CMD_CLEAR = 32'h0000_0002;

    logic ap_clk;
    logic ap_rst_n;

    logic [ADDR_WIDTH-1:0] s_axi_control_awaddr;
    logic s_axi_control_awvalid;
    logic s_axi_control_awready;
    logic [31:0] s_axi_control_wdata;
    logic [3:0] s_axi_control_wstrb;
    logic s_axi_control_wvalid;
    logic s_axi_control_wready;
    logic [1:0] s_axi_control_bresp;
    logic s_axi_control_bvalid;
    logic s_axi_control_bready;
    logic [ADDR_WIDTH-1:0] s_axi_control_araddr;
    logic s_axi_control_arvalid;
    logic s_axi_control_arready;
    logic [31:0] s_axi_control_rdata;
    logic [1:0] s_axi_control_rresp;
    logic s_axi_control_rvalid;
    logic s_axi_control_rready;

    logic m_axi_gmem_awid;
    logic [63:0] m_axi_gmem_awaddr;
    logic [7:0] m_axi_gmem_awlen;
    logic [2:0] m_axi_gmem_awsize;
    logic [1:0] m_axi_gmem_awburst;
    logic m_axi_gmem_awlock;
    logic [3:0] m_axi_gmem_awcache;
    logic [2:0] m_axi_gmem_awprot;
    logic [3:0] m_axi_gmem_awqos;
    logic m_axi_gmem_awvalid;
    logic m_axi_gmem_awready;
    logic [127:0] m_axi_gmem_wdata;
    logic [15:0] m_axi_gmem_wstrb;
    logic m_axi_gmem_wlast;
    logic m_axi_gmem_wvalid;
    logic m_axi_gmem_wready;
    logic m_axi_gmem_bid;
    logic [1:0] m_axi_gmem_bresp;
    logic m_axi_gmem_bvalid;
    logic m_axi_gmem_bready;
    logic m_axi_gmem_arid;
    logic [63:0] m_axi_gmem_araddr;
    logic [7:0] m_axi_gmem_arlen;
    logic [2:0] m_axi_gmem_arsize;
    logic [1:0] m_axi_gmem_arburst;
    logic m_axi_gmem_arlock;
    logic [3:0] m_axi_gmem_arcache;
    logic [2:0] m_axi_gmem_arprot;
    logic [3:0] m_axi_gmem_arqos;
    logic m_axi_gmem_arvalid;
    logic m_axi_gmem_arready;
    logic m_axi_gmem_rid;
    logic [127:0] m_axi_gmem_rdata;
    logic [1:0] m_axi_gmem_rresp;
    logic m_axi_gmem_rlast;
    logic m_axi_gmem_rvalid;
    logic m_axi_gmem_rready;

    integer cycle_count;
    integer wait_attempts;
    integer address_index;
    integer run_index;
    integer hold_index;
    integer lookup_request_count;
    integer ar_handshake_count;
    integer r_handshake_count;
    integer slot_injection_count;
    integer observed_row [0:3][0:7];

    logic [31:0] status_value;
    logic [31:0] version_value;
    logic [31:0] result_value;
    logic [31:0] result_index_value;
    logic [31:0] result_meta_value;
    logic [31:0] result_count_value;
    logic [31:0] phase_counts_value;
    logic [31:0] mask_value;
    logic [95:0] descriptor_value;
    logic signed [15:0] held_result;
    logic [31:0] bottom_cycles_value;
    logic [31:0] interaction_cycles_value;
    logic [31:0] top_cycles_value;
    logic [31:0] total_cycles_value;
    logic [31:0] held_bottom_cycles;
    logic [31:0] held_interaction_cycles;
    logic [31:0] held_top_cycles;
    logic [31:0] held_total_cycles;
    logic [31:0] first_bottom_cycles;
    logic [31:0] first_interaction_cycles;
    logic [31:0] first_top_cycles;
    logic [31:0] first_total_cycles;
    logic [31:0] stage_cycle_sum;
    logic [31:0] a15_status_value;
    logic [31:0] error_code_value;
    logic [127:0] expected_row_data;

    dlrm_f37x_rtl_kernel_stage2n_a15_v1 dut (
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

    always #5 ap_clk = ~ap_clk;

    function automatic logic [95:0] pack_descriptor(
        input integer in_dim,
        input integer out_dim,
        input integer weight_base,
        input integer bias_base,
        input integer output_shift,
        input integer relu_enable
    );
        logic [95:0] value;
        begin
            value = 96'd0;
            value[0 +: 11] = in_dim[10:0];
            value[11 +: 11] = out_dim[10:0];
            value[22 +: 32] = weight_base[31:0];
            value[54 +: 32] = bias_base[31:0];
            value[86 +: 6] = output_shift[5:0];
            value[92] = relu_enable[0];
            pack_descriptor = value;
        end
    endfunction

    function automatic logic [31:0] pack_pair(
        input integer low_value,
        input integer high_value
    );
        logic signed [15:0] low_word;
        logic signed [15:0] high_word;
        begin
            low_word = low_value;
            high_word = high_value;
            pack_pair = {high_word, low_word};
        end
    endfunction

    // Derived from the tracked stage2n_a14_embedding_table_v1 contract:
    // value[row][lane] = row*8 + lane - 256, lane0 in bits [15:0].
    function automatic logic [127:0] canonical_row(input integer row);
        logic [127:0] packed_data;
        logic signed [15:0] lane_value;
        integer lane;
        begin
            packed_data = 128'd0;
            for (lane = 0; lane < 8; lane = lane + 1) begin
                lane_value = row * 8 + lane - 256;
                packed_data[lane*16 +: 16] = lane_value;
            end
            canonical_row = packed_data;
        end
    endfunction

    task automatic axi_write(
        input logic [ADDR_WIDTH-1:0] address,
        input logic [31:0] data
    );
        begin
            @(negedge ap_clk);
            s_axi_control_awaddr = address;
            s_axi_control_awvalid = 1'b1;
            while (!s_axi_control_awready)
                @(posedge ap_clk);
            @(negedge ap_clk);
            s_axi_control_awvalid = 1'b0;

            s_axi_control_wdata = data;
            s_axi_control_wstrb = 4'hF;
            s_axi_control_wvalid = 1'b1;
            while (!s_axi_control_wready)
                @(posedge ap_clk);
            @(negedge ap_clk);
            s_axi_control_wvalid = 1'b0;
            s_axi_control_bready = 1'b1;

            while (!s_axi_control_bvalid)
                @(posedge ap_clk);
            if (s_axi_control_bresp !== 2'b00)
                $fatal(1, "AXI write response error address=0x%0h",
                       address);

            @(negedge ap_clk);
            s_axi_control_bready = 1'b0;
        end
    endtask

    task automatic axi_read(
        input logic [ADDR_WIDTH-1:0] address,
        output logic [31:0] data
    );
        begin
            @(negedge ap_clk);
            s_axi_control_araddr = address;
            s_axi_control_arvalid = 1'b1;
            while (!s_axi_control_arready)
                @(posedge ap_clk);
            @(negedge ap_clk);
            s_axi_control_arvalid = 1'b0;
            s_axi_control_rready = 1'b1;

            while (!s_axi_control_rvalid)
                @(posedge ap_clk);
            data = s_axi_control_rdata;
            if (s_axi_control_rresp !== 2'b00)
                $fatal(1, "AXI read response error address=0x%0h",
                       address);

            @(negedge ap_clk);
            s_axi_control_rready = 1'b0;
        end
    endtask

    task automatic reset_dut;
        begin
            ap_rst_n = 1'b0;
            s_axi_control_awaddr = '0;
            s_axi_control_awvalid = 1'b0;
            s_axi_control_wdata = '0;
            s_axi_control_wstrb = 4'hF;
            s_axi_control_wvalid = 1'b0;
            s_axi_control_bready = 1'b0;
            s_axi_control_araddr = '0;
            s_axi_control_arvalid = 1'b0;
            s_axi_control_rready = 1'b0;
            m_axi_gmem_awready = 1'b0;
            m_axi_gmem_wready = 1'b0;
            m_axi_gmem_bid = 1'b0;
            m_axi_gmem_bresp = 2'b00;
            m_axi_gmem_bvalid = 1'b0;
            m_axi_gmem_arready = 1'b0;
            m_axi_gmem_rid = 1'b0;
            m_axi_gmem_rdata = '0;
            m_axi_gmem_rresp = 2'b00;
            m_axi_gmem_rlast = 1'b0;
            m_axi_gmem_rvalid = 1'b0;
            lookup_request_count = 0;
            ar_handshake_count = 0;
            r_handshake_count = 0;
            slot_injection_count = 0;
            repeat (8) @(posedge ap_clk);
            ap_rst_n = 1'b1;
            repeat (4) @(posedge ap_clk);
        end
    endtask

    task automatic program_a15_table_base;
        logic [31:0] readback;
        begin
            axi_write(ADDR_A15_TABLE_BASE_LO, TABLE_BASE[31:0]);
            axi_write(ADDR_A15_TABLE_BASE_HI, TABLE_BASE[63:32]);
            axi_read(ADDR_A15_TABLE_BASE_LO, readback);
            if (readback !== TABLE_BASE[31:0])
                $fatal(1, "TABLE_BASE_LO readback mismatch");
            axi_read(ADDR_A15_TABLE_BASE_HI, readback);
            if (readback !== TABLE_BASE[63:32])
                $fatal(1, "TABLE_BASE_HI readback mismatch");
        end
    endtask

    task automatic wait_a15_error;
        begin
            wait_attempts = 0;
            axi_read(ADDR_A15_CONTROL_STATUS, a15_status_value);
            while (!a15_status_value[5]) begin
                wait_attempts = wait_attempts + 1;
                if (wait_attempts > 1000)
                    $fatal(1, "A15 error timeout status=0x%08x",
                           a15_status_value);
                axi_read(ADDR_A15_CONTROL_STATUS, a15_status_value);
            end
        end
    endtask

    task automatic wait_a15_idle;
        begin
            wait_attempts = 0;
            axi_read(ADDR_A15_CONTROL_STATUS, a15_status_value);
            while (!a15_status_value[6]) begin
                wait_attempts = wait_attempts + 1;
                if (wait_attempts > 1000)
                    $fatal(1, "A15 idle timeout status=0x%08x",
                           a15_status_value);
                axi_read(ADDR_A15_CONTROL_STATUS, a15_status_value);
            end
        end
    endtask

    task automatic service_lookup(
        input integer slot,
        input integer row,
        input logic inject_error,
        input logic repeat_start
    );
        logic [63:0] expected_address;
        logic [63:0] held_address;
        logic [127:0] row_data;
        logic [127:0] held_data;
        logic [3:0] expected_mask_before;
        logic [3:0] expected_mask_after;
        integer lane;
        begin
            expected_address = TABLE_BASE + row * 16;
            row_data = canonical_row(row);
            expected_mask_before = (4'b0001 << slot) - 1'b1;
            expected_mask_after = expected_mask_before | (4'b0001 << slot);

            wait_attempts = 0;
            while (!m_axi_gmem_arvalid) begin
                wait_attempts = wait_attempts + 1;
                if (wait_attempts > 1000)
                    $fatal(1, "ARVALID timeout slot=%0d", slot);
                @(posedge ap_clk);
            end
            lookup_request_count = lookup_request_count + 1;
            held_address = m_axi_gmem_araddr;
            if (held_address !== expected_address)
                $fatal(1,
                       "ARADDR mismatch slot=%0d actual=0x%016h expected=0x%016h",
                       slot, held_address, expected_address);
            if ((m_axi_gmem_arlen !== 8'd0) ||
                (m_axi_gmem_arsize !== 3'd4) ||
                (m_axi_gmem_arburst !== 2'b01) ||
                (m_axi_gmem_arid !== 1'b0))
                $fatal(1, "AXI AR control mismatch slot=%0d", slot);

            axi_read(ADDR_PIPE_EMB_LOADED_MASK, mask_value);
            if (mask_value[3:0] !== expected_mask_before)
                $fatal(1,
                       "mask before slot%0d mismatch actual=%h expected=%h",
                       slot, mask_value[3:0], expected_mask_before);

            // Delayed ARREADY: address/control must remain stable.
            repeat (4) begin
                @(posedge ap_clk);
                if (!m_axi_gmem_arvalid ||
                    (m_axi_gmem_araddr !== held_address))
                    $fatal(1, "AR payload changed while stalled slot=%0d",
                           slot);
            end

            if (repeat_start) begin
                axi_write(ADDR_A15_CONTROL_STATUS, A15_CMD_START);
                axi_read(ADDR_PIPE_ERROR_CODE, error_code_value);
                if (!error_code_value[17] ||
                    (error_code_value[11:8] !== 4'd3))
                    $fatal(1,
                           "repeated START was not rejected deterministically: 0x%08x",
                           error_code_value);
                axi_write(ADDR_PIPE_CONTROL_STATUS, PIPE_CMD_ERROR_ACK);
            end

            @(negedge ap_clk);
            m_axi_gmem_arready = 1'b1;
            @(posedge ap_clk);
            if (!(m_axi_gmem_arvalid && m_axi_gmem_arready))
                $fatal(1, "AR handshake missing slot=%0d", slot);
            ar_handshake_count = ar_handshake_count + 1;
            @(negedge ap_clk);
            m_axi_gmem_arready = 1'b0;

            // Delayed RVALID.
            repeat (5) @(posedge ap_clk);
            @(negedge ap_clk);
            m_axi_gmem_rdata = row_data;
            m_axi_gmem_rresp = inject_error ? 2'b10 : 2'b00;
            m_axi_gmem_rlast = 1'b1;
            m_axi_gmem_rid = 1'b0;
            m_axi_gmem_rvalid = 1'b1;
            held_data = row_data;
            wait_attempts = 0;
            while (!m_axi_gmem_rready) begin
                wait_attempts = wait_attempts + 1;
                if (wait_attempts > 1000)
                    $fatal(1, "RREADY timeout slot=%0d", slot);
                @(posedge ap_clk);
                if (!m_axi_gmem_rvalid ||
                    (m_axi_gmem_rdata !== held_data))
                    $fatal(1, "R payload changed while retained slot=%0d",
                           slot);
            end
            @(posedge ap_clk);
            r_handshake_count = r_handshake_count + 1;
            for (lane = 0; lane < 8; lane = lane + 1) begin
                observed_row[slot][lane] =
                    $signed(m_axi_gmem_rdata[lane*16 +: 16]);
                if (observed_row[slot][lane] !==
                    (row * 8 + lane - 256))
                    $fatal(1,
                           "row%0d lane%0d mismatch actual=%0d expected=%0d",
                           row, lane, observed_row[slot][lane],
                           row * 8 + lane - 256);
            end
            @(negedge ap_clk);
            m_axi_gmem_rvalid = 1'b0;
            m_axi_gmem_rlast = 1'b0;
            m_axi_gmem_rresp = 2'b00;

            if (!inject_error) begin
                wait_attempts = 0;
                axi_read(ADDR_PIPE_EMB_LOADED_MASK, mask_value);
                while (mask_value[3:0] !== expected_mask_after) begin
                    wait_attempts = wait_attempts + 1;
                    if (wait_attempts > 1000)
                        $fatal(1,
                               "slot injection timeout slot=%0d mask=%h",
                               slot, mask_value[3:0]);
                    axi_read(ADDR_PIPE_EMB_LOADED_MASK, mask_value);
                end
                slot_injection_count = slot_injection_count + 1;
            end
        end
    endtask

    task automatic wait_command_idle;
        begin
            wait_attempts = 0;
            axi_read(ADDR_PIPE_CONTROL_STATUS, status_value);
            while (status_value[6]) begin
                wait_attempts = wait_attempts + 1;
                if (wait_attempts > 3000)
                    $fatal(1, "pipeline command timeout status=0x%08x",
                           status_value);
                axi_read(ADDR_PIPE_CONTROL_STATUS, status_value);
            end
            if (status_value[31] || status_value[5] || status_value[4])
                $fatal(1, "pipeline command error status=0x%08x",
                       status_value);
        end
    endtask

    task automatic write_descriptor(
        input integer index,
        input logic [95:0] value
    );
        begin
            axi_write(ADDR_PIPE_DESC_INDEX, index);
            axi_write(ADDR_PIPE_DESC_WORD0, value[31:0]);
            axi_write(ADDR_PIPE_DESC_WORD1, value[63:32]);
            axi_write(ADDR_PIPE_DESC_WORD2, value[95:64]);
            axi_write(ADDR_PIPE_CONTROL_STATUS,
                      PIPE_CMD_DESC_COMMIT);
            wait_command_idle();
        end
    endtask

    task automatic write_weight(
        input integer address,
        input integer value
    );
        begin
            axi_write(ADDR_PIPE_WEIGHT_ADDRESS, address);
            axi_write(ADDR_PIPE_WEIGHT_DATA, value);
            axi_write(ADDR_PIPE_CONTROL_STATUS,
                      PIPE_CMD_WEIGHT_COMMIT);
            wait_command_idle();
        end
    endtask

    task automatic write_bias(
        input integer address,
        input integer value
    );
        begin
            axi_write(ADDR_PIPE_BIAS_ADDRESS, address);
            axi_write(ADDR_PIPE_BIAS_DATA, value);
            axi_write(ADDR_PIPE_CONTROL_STATUS,
                      PIPE_CMD_BIAS_COMMIT);
            wait_command_idle();
        end
    endtask

    task automatic write_embedding(
        input integer index,
        input integer v0,
        input integer v1,
        input integer v2,
        input integer v3,
        input integer v4,
        input integer v5,
        input integer v6,
        input integer v7
    );
        begin
            axi_write(ADDR_PIPE_EMB_INDEX, index);
            axi_write(ADDR_PIPE_EMB_DATA0, pack_pair(v0, v1));
            axi_write(ADDR_PIPE_EMB_DATA1, pack_pair(v2, v3));
            axi_write(ADDR_PIPE_EMB_DATA2, pack_pair(v4, v5));
            axi_write(ADDR_PIPE_EMB_DATA3, pack_pair(v6, v7));
            axi_write(ADDR_PIPE_CONTROL_STATUS,
                      PIPE_CMD_EMB_COMMIT);
            wait_command_idle();
        end
    endtask

    task automatic write_bottom_input;
        begin
            axi_write(ADDR_PIPE_ACT_BUFFER, 0);
            axi_write(ADDR_PIPE_ACT_CHUNK_INDEX, 0);
            axi_write(ADDR_PIPE_ACT_LANE_MASK, 32'h0000_00FF);
            axi_write(ADDR_PIPE_ACT_DATA0, pack_pair(1, 2));
            axi_write(ADDR_PIPE_ACT_DATA1, pack_pair(3, 4));
            axi_write(ADDR_PIPE_ACT_DATA2, pack_pair(5, 6));
            axi_write(ADDR_PIPE_ACT_DATA3, pack_pair(7, 8));
            axi_write(ADDR_PIPE_ACT_DATA4, 0);
            axi_write(ADDR_PIPE_ACT_DATA5, 0);
            axi_write(ADDR_PIPE_ACT_DATA6, 0);
            axi_write(ADDR_PIPE_ACT_DATA7, 0);
            axi_write(ADDR_PIPE_CONTROL_STATUS,
                      PIPE_CMD_ACT_COMMIT);
            wait_command_idle();
        end
    endtask

    task automatic start_a15_pipeline;
        begin
            // Stage 2M shape:
            // bottom descriptors 0..1, two layers, initial buffer 0.
            axi_write(ADDR_PIPE_BOTTOM_CONFIG, 32'h0000_0200);
            // top descriptors 2..4, three layers, input buffer 0.
            axi_write(ADDR_PIPE_TOP_CONFIG, 32'h0000_0302);
            // interaction shift=0 for the deterministic capacity vector.
            axi_write(ADDR_PIPELINE_CONFIG, 32'h0000_0000);
            program_a15_table_base();
            axi_write(ADDR_A15_CONTROL_STATUS, A15_CMD_START);
            axi_read(ADDR_A15_CONTROL_STATUS, a15_status_value);
            if (!a15_status_value[0])
                $fatal(1, "A15 START did not enter active state: 0x%08x",
                       a15_status_value);
        end
    endtask

    task automatic wait_for_result(input integer backpressure_cycles);
        begin
            wait_attempts = 0;
            axi_read(ADDR_PIPE_CONTROL_STATUS, status_value);
            while (!status_value[2]) begin
                wait_attempts = wait_attempts + 1;
                if (wait_attempts > 30000)
                    $fatal(1, "result timeout status=0x%08x",
                           status_value);
                if (status_value[31] || status_value[5] ||
                    status_value[4])
                    $fatal(1, "pipeline error before result 0x%08x",
                           status_value);
                axi_read(ADDR_PIPE_CONTROL_STATUS, status_value);
            end

            axi_read(ADDR_PIPE_RESULT_DATA, result_value);
            axi_read(ADDR_PIPE_RESULT_INDEX, result_index_value);
            axi_read(ADDR_PIPE_RESULT_META, result_meta_value);
            axi_read(ADDR_PIPE_BOTTOM_CYCLES, bottom_cycles_value);
            axi_read(ADDR_PIPE_INTERACTION_CYCLES,
                     interaction_cycles_value);
            axi_read(ADDR_PIPE_TOP_CYCLES, top_cycles_value);
            axi_read(ADDR_PIPE_TOTAL_CYCLES, total_cycles_value);
            held_result = result_value[15:0];
            held_bottom_cycles = bottom_cycles_value;
            held_interaction_cycles = interaction_cycles_value;
            held_top_cycles = top_cycles_value;
            held_total_cycles = total_cycles_value;
            stage_cycle_sum = bottom_cycles_value +
                              interaction_cycles_value +
                              top_cycles_value;

            if (held_result !== 16'sd36)
                $fatal(1, "result mismatch: %0d", held_result);
            if (result_index_value[5:0] !== 6'd0)
                $fatal(1, "result index mismatch: %0d",
                       result_index_value[5:0]);
            if (!result_meta_value[0] || !result_meta_value[1])
                $fatal(1, "result meta mismatch: 0x%08x",
                       result_meta_value);
            if (result_meta_value[23:16] !== 8'd4)
                $fatal(1, "result tag mismatch: %0d",
                       result_meta_value[23:16]);
            if ((bottom_cycles_value == 0) ||
                (interaction_cycles_value == 0) ||
                (top_cycles_value == 0) ||
                (total_cycles_value == 0)) begin
                $fatal(1,
                       "zero cycle counter bottom=%0d interaction=%0d top=%0d total=%0d",
                       bottom_cycles_value, interaction_cycles_value,
                       top_cycles_value, total_cycles_value);
            end
            if (total_cycles_value < stage_cycle_sum) begin
                $fatal(1,
                       "total cycles do not cover ordered stages total=%0d stage_sum=%0d",
                       total_cycles_value, stage_cycle_sum);
            end

            for (hold_index = 0;
                 hold_index < backpressure_cycles;
                 hold_index = hold_index + 1) begin
                axi_read(ADDR_PIPE_CONTROL_STATUS, status_value);
                axi_read(ADDR_PIPE_RESULT_DATA, result_value);
                axi_read(ADDR_PIPE_BOTTOM_CYCLES, bottom_cycles_value);
                axi_read(ADDR_PIPE_INTERACTION_CYCLES,
                         interaction_cycles_value);
                axi_read(ADDR_PIPE_TOP_CYCLES, top_cycles_value);
                axi_read(ADDR_PIPE_TOTAL_CYCLES, total_cycles_value);
                if (!status_value[2] ||
                    result_value[15:0] !== held_result)
                    $fatal(1,
                           "result changed under host backpressure");
                if ((bottom_cycles_value !== held_bottom_cycles) ||
                    (interaction_cycles_value !==
                     held_interaction_cycles) ||
                    (top_cycles_value !== held_top_cycles) ||
                    (total_cycles_value !== held_total_cycles)) begin
                    $fatal(1,
                           "cycle counter changed under host backpressure");
                end
            end

            axi_write(ADDR_PIPE_CONTROL_STATUS, PIPE_CMD_RESULT_POP);

            wait_attempts = 0;
            axi_read(ADDR_PIPE_CONTROL_STATUS, status_value);
            while (!status_value[1]) begin
                wait_attempts = wait_attempts + 1;
                if (wait_attempts > 5000)
                    $fatal(1, "done timeout status=0x%08x",
                           status_value);
                if (status_value[31] || status_value[5] ||
                    status_value[4])
                    $fatal(1, "pipeline error after result 0x%08x",
                           status_value);
                axi_read(ADDR_PIPE_CONTROL_STATUS, status_value);
            end

            axi_read(ADDR_PIPE_RESULT_COUNT, result_count_value);
            axi_read(ADDR_PIPE_PHASE_COUNTS, phase_counts_value);

            if (result_count_value !== 32'd1)
                $fatal(1, "result count mismatch: %0d",
                       result_count_value);
            if (phase_counts_value[11:8] !== 4'd8)
                $fatal(1, "bottom count mismatch: %0d",
                       phase_counts_value[11:8]);
            if (phase_counts_value[20:16] !== 5'd18)
                $fatal(1, "interaction count mismatch: %0d",
                       phase_counts_value[20:16]);

            axi_read(ADDR_PIPE_BOTTOM_CYCLES, bottom_cycles_value);
            axi_read(ADDR_PIPE_INTERACTION_CYCLES,
                     interaction_cycles_value);
            axi_read(ADDR_PIPE_TOP_CYCLES, top_cycles_value);
            axi_read(ADDR_PIPE_TOTAL_CYCLES, total_cycles_value);
            if ((bottom_cycles_value !== held_bottom_cycles) ||
                (interaction_cycles_value !== held_interaction_cycles) ||
                (top_cycles_value !== held_top_cycles) ||
                (total_cycles_value !== held_total_cycles)) begin
                $fatal(1, "cycle counter changed after result retirement");
            end

            axi_write(ADDR_PIPE_CONTROL_STATUS, PIPE_CMD_CLEAR_DONE);
            axi_read(ADDR_PIPE_CONTROL_STATUS, status_value);
            if (status_value[1] || status_value[31] ||
                status_value[5] || status_value[4]) begin
                $fatal(1, "clear-done status mismatch: 0x%08x",
                       status_value);
            end
            axi_read(ADDR_PIPE_BOTTOM_CYCLES, bottom_cycles_value);
            axi_read(ADDR_PIPE_INTERACTION_CYCLES,
                     interaction_cycles_value);
            axi_read(ADDR_PIPE_TOP_CYCLES, top_cycles_value);
            axi_read(ADDR_PIPE_TOTAL_CYCLES, total_cycles_value);
            if ((bottom_cycles_value !== held_bottom_cycles) ||
                (interaction_cycles_value !== held_interaction_cycles) ||
                (top_cycles_value !== held_top_cycles) ||
                (total_cycles_value !== held_total_cycles)) begin
                $fatal(1, "cycle counter changed after clear-done");
            end

            if (run_index == 0) begin
                first_bottom_cycles = held_bottom_cycles;
                first_interaction_cycles = held_interaction_cycles;
                first_top_cycles = held_top_cycles;
                first_total_cycles = held_total_cycles;
            end else begin
                if ((held_bottom_cycles !== first_bottom_cycles) ||
                    (held_interaction_cycles !==
                     first_interaction_cycles) ||
                    (held_top_cycles !== first_top_cycles) ||
                    (held_total_cycles !== first_total_cycles)) begin
                    $fatal(1,
                           "cycle counters differ across identical restarts");
                end
            end
        end
    endtask

    always @(posedge ap_clk) begin
        if (!ap_rst_n)
            cycle_count <= 0;
        else begin
            cycle_count <= cycle_count + 1;
            if (cycle_count > 3000000)
                $fatal(1,
                       "tb_dlrm_f37x_rtl_kernel_stage2n_a15_v1: TIMEOUT");
        end
    end

    initial begin
        ap_clk = 1'b0;
        cycle_count = 0;
        run_index = 0;
        first_bottom_cycles = 32'd0;
        first_interaction_cycles = 32'd0;
        first_top_cycles = 32'd0;
        first_total_cycles = 32'd0;

        // Reset must clear every A15.4-visible state.
        reset_dut();
        axi_read(ADDR_A15_CONTROL_STATUS, a15_status_value);
        axi_read(ADDR_A15_TABLE_BASE_LO, status_value);
        if ((a15_status_value[5:0] !== 6'd0) ||
            !a15_status_value[6] || (status_value !== 32'd0))
            $fatal(1, "A15 reset state mismatch status=0x%08x base=0x%08x",
                   a15_status_value, status_value);
        axi_read(ADDR_PIPE_EMB_LOADED_MASK, mask_value);
        if (mask_value[3:0] !== 4'h0)
            $fatal(1, "loaded mask not clear after reset");
        if (m_axi_gmem_awvalid || m_axi_gmem_wvalid ||
            m_axi_gmem_bready)
            $fatal(1, "read-only AXI write channels are not tied off");
        $display("A15_4_RESET_CLEAN=PASS");

        // Negative A: slot0 lookup error.
        program_a15_table_base();
        axi_write(ADDR_A15_CONTROL_STATUS, A15_CMD_START);
        service_lookup(0, ROW0, 1'b1, 1'b0);
        wait_a15_error();
        axi_read(ADDR_PIPE_EMB_LOADED_MASK, mask_value);
        if ((mask_value[3:0] !== 4'h0) ||
            (a15_status_value[13:12] !== 2'd0) ||
            (a15_status_value[23:16] !== ROW0[7:0]))
            $fatal(1, "slot0 error preservation mismatch status=0x%08x mask=%h",
                   a15_status_value, mask_value[3:0]);
        repeat (12) begin
            @(posedge ap_clk);
            if (m_axi_gmem_arvalid)
                $fatal(1, "lookup continued after slot0 error");
        end
        axi_read(ADDR_PIPE_TOTAL_CYCLES, total_cycles_value);
        if (total_cycles_value !== 32'd0)
            $fatal(1, "pipeline started after slot0 error");
        axi_write(ADDR_A15_CONTROL_STATUS, A15_CMD_CLEAR);
        wait_a15_idle();
        $display("A15_4_SLOT0_ERROR_PROTECTION=PASS");

        // Negative B: slot2 error preserves slots0/1 and suppresses slot3.
        reset_dut();
        program_a15_table_base();
        axi_write(ADDR_A15_CONTROL_STATUS, A15_CMD_START);
        service_lookup(0, ROW0, 1'b0, 1'b0);
        service_lookup(1, ROW1, 1'b0, 1'b0);
        service_lookup(2, ROW2, 1'b1, 1'b0);
        wait_a15_error();
        axi_read(ADDR_PIPE_EMB_LOADED_MASK, mask_value);
        if ((mask_value[3:0] !== 4'h3) ||
            (a15_status_value[13:12] !== 2'd2) ||
            (a15_status_value[23:16] !== ROW2[7:0]))
            $fatal(1, "slot2 error preservation mismatch status=0x%08x mask=%h",
                   a15_status_value, mask_value[3:0]);
        repeat (12) begin
            @(posedge ap_clk);
            if (m_axi_gmem_arvalid)
                $fatal(1, "slot3 requested after slot2 error");
        end
        if ((lookup_request_count !== 3) ||
            (ar_handshake_count !== 3) ||
            (r_handshake_count !== 3) ||
            (slot_injection_count !== 2))
            $fatal(1, "slot2 error accounting mismatch");
        axi_read(ADDR_PIPE_TOTAL_CYCLES, total_cycles_value);
        if (total_cycles_value !== 32'd0)
            $fatal(1, "pipeline started after slot2 error");
        axi_write(ADDR_A15_CONTROL_STATUS, A15_CMD_CLEAR);
        wait_a15_idle();
        $display("A15_4_MID_SEQUENCE_ERROR_PROTECTION=PASS");

        // Negative G: legacy Host embedding writes remain address-compatible
        // but the A15.4 HBM-owned path rejects their commit.
        reset_dut();
        axi_write(ADDR_PIPE_EMB_INDEX, 32'd0);
        axi_write(ADDR_PIPE_EMB_DATA0, 32'h1111_1111);
        axi_write(ADDR_PIPE_EMB_DATA1, 32'h2222_2222);
        axi_write(ADDR_PIPE_EMB_DATA2, 32'h3333_3333);
        axi_write(ADDR_PIPE_EMB_DATA3, 32'h4444_4444);
        axi_write(ADDR_PIPE_CONTROL_STATUS, PIPE_CMD_EMB_COMMIT);
        repeat (6) @(posedge ap_clk);
        axi_read(ADDR_PIPE_EMB_LOADED_MASK, mask_value);
        axi_read(ADDR_PIPE_ERROR_CODE, error_code_value);
        if ((mask_value[3:0] !== 4'h0) ||
            !error_code_value[17] ||
            (error_code_value[11:8] !== 4'd5))
            $fatal(1, "Host embedding rejection mismatch mask=%h error=0x%08x",
                   mask_value[3:0], error_code_value);
        axi_write(ADDR_PIPE_CONTROL_STATUS, PIPE_CMD_ERROR_ACK);
        $display("A15_4_HOST_EMBEDDING_REJECT=PASS");

        // Successful public-kernel path.
        reset_dut();

        // Prove the accepted A13 public windows and counter addresses remain.
        axi_read(ADDR_MLP_VERSION, version_value);
        if (version_value !== 32'h0002_4701)
            $fatal(1, "legacy MLP version mismatch: 0x%08x", version_value);
        axi_read(ADDR_INT_VERSION, version_value);
        if (version_value !== 32'h0002_4E02)
            $fatal(1, "interaction version mismatch: 0x%08x", version_value);
        axi_read(ADDR_PIPE_VERSION, version_value);
        if (version_value !== 32'h0002_4E13)
            $fatal(1, "pipeline version mismatch: 0x%08x", version_value);
        axi_read(ADDR_PIPE_BOTTOM_CYCLES, bottom_cycles_value);
        axi_read(ADDR_PIPE_INTERACTION_CYCLES, interaction_cycles_value);
        axi_read(ADDR_PIPE_TOP_CYCLES, top_cycles_value);
        axi_read(ADDR_PIPE_TOTAL_CYCLES, total_cycles_value);
        if ((bottom_cycles_value !== 0) ||
            (interaction_cycles_value !== 0) ||
            (top_cycles_value !== 0) ||
            (total_cycles_value !== 0))
            $fatal(1, "cycle counters are not zero after reset");

        // Five accepted descriptors: Bottom 8->16->8 and Top 18->32->16->1.
        descriptor_value = pack_descriptor(8, 16, 0, 0, 0, 1);
        write_descriptor(0, descriptor_value);
        descriptor_value = pack_descriptor(16, 8, 128, 16, 0, 1);
        write_descriptor(1, descriptor_value);
        descriptor_value = pack_descriptor(18, 32, 256, 24, 0, 1);
        write_descriptor(2, descriptor_value);
        descriptor_value = pack_descriptor(32, 16, 832, 56, 0, 1);
        write_descriptor(3, descriptor_value);
        descriptor_value = pack_descriptor(16, 1, 1344, 72, 0, 0);
        write_descriptor(4, descriptor_value);

        for (address_index = 0; address_index < 1360;
             address_index = address_index + 1)
            write_weight(address_index, 0);
        for (address_index = 0; address_index < 8;
             address_index = address_index + 1)
            write_weight(address_index * 9, 1);
        for (address_index = 0; address_index < 8;
             address_index = address_index + 1)
            write_weight(128 + address_index * 17, 1);
        for (address_index = 0; address_index < 8;
             address_index = address_index + 1)
            write_weight(256 + address_index * 19, 1);
        for (address_index = 0; address_index < 8;
             address_index = address_index + 1)
            write_weight(832 + address_index * 33, 1);
        for (address_index = 0; address_index < 8;
             address_index = address_index + 1)
            write_weight(1344 + address_index, 1);
        for (address_index = 0; address_index < 73;
             address_index = address_index + 1)
            write_bias(address_index, 0);

        write_bottom_input();
        axi_read(ADDR_PIPE_EMB_LOADED_MASK, mask_value);
        if (mask_value[3:0] !== 4'h0)
            $fatal(1, "mask must be zero before A15 START");

        start_a15_pipeline();
        service_lookup(0, ROW0, 1'b0, 1'b1);
        service_lookup(1, ROW1, 1'b0, 1'b0);
        service_lookup(2, ROW2, 1'b0, 1'b0);
        service_lookup(3, ROW3, 1'b0, 1'b0);

        axi_read(ADDR_PIPE_EMB_LOADED_MASK, mask_value);
        if (mask_value[3:0] !== 4'hF)
            $fatal(1, "final embedding mask mismatch: %h", mask_value[3:0]);

        wait_for_result(12);

        if ((held_bottom_cycles !== 32'd322) ||
            (held_interaction_cycles !== 32'd100) ||
            (held_top_cycles !== 32'd744) ||
            (held_total_cycles !== 32'd1174))
            $fatal(1,
                   "accepted A13 counters changed: %0d/%0d/%0d/%0d",
                   held_bottom_cycles, held_interaction_cycles,
                   held_top_cycles, held_total_cycles);

        axi_read(ADDR_A15_CONTROL_STATUS, a15_status_value);
        if (!a15_status_value[4] || a15_status_value[5] ||
            a15_status_value[31])
            $fatal(1, "A15 completion status mismatch: 0x%08x",
                   a15_status_value);
        axi_write(ADDR_A15_CONTROL_STATUS, A15_CMD_CLEAR);
        wait_a15_idle();

        if ((lookup_request_count !== 4) ||
            (ar_handshake_count !== 4) ||
            (r_handshake_count !== 4) ||
            (slot_injection_count !== 4))
            $fatal(1,
                   "successful accounting mismatch lookup/ar/r/inject=%0d/%0d/%0d/%0d",
                   lookup_request_count, ar_handshake_count,
                   r_handshake_count, slot_injection_count);

        $display("A15_4_TABLE_BASE_CAPTURE=PASS");
        $display("A15_4_FOUR_LOOKUPS=PASS");
        $display("A15_4_FOUR_SLOT_INJECTION=PASS");
        $display("A15_4_LOADED_MASK=PASS");
        $display("A15_4_PIPELINE_START_GUARD=PASS");
        $display("A15_4_DELAYED_ARREADY=PASS");
        $display("A15_4_DELAYED_RVALID=PASS");
        $display("A15_4_RESPONSE_RETENTION_REUSED=PASS");
        $display("A15_4_REPEATED_START_REJECT=PASS");
        $display("A15_4_END_TO_END_PIPELINE=PASS");
        $display("A15_4_RESULT_MATCH=PASS");
        $display("A15_4_A13_COUNTER_ABI=PASS");
        $display("A15_4_A13_PUBLIC_ABI=PASS");
        $display("A15_4_CANONICAL_ROWS=37,38,39,40");
        $display("A15_4_ROW0_VALUES=40,41,42,43,44,45,46,47");
        $display("A15_4_ROW1_VALUES=48,49,50,51,52,53,54,55");
        $display("A15_4_ROW2_VALUES=56,57,58,59,60,61,62,63");
        $display("A15_4_ROW3_VALUES=64,65,66,67,68,69,70,71");
        $display("A15_4_GOLDEN_FINAL_RESULT=36");
        $display("A15_4_ACTUAL_FINAL_RESULT=%0d", held_result);
        $display("A15_4_BOTTOM_CYCLES=%0d", held_bottom_cycles);
        $display("A15_4_INTERACTION_CYCLES=%0d",
                 held_interaction_cycles);
        $display("A15_4_TOP_CYCLES=%0d", held_top_cycles);
        $display("A15_4_TOTAL_CYCLES=%0d", held_total_cycles);
        $display("A15_4_LOOKUP_REQUESTS=%0d", lookup_request_count);
        $display("A15_4_AR_HANDSHAKES=%0d", ar_handshake_count);
        $display("A15_4_R_HANDSHAKES=%0d", r_handshake_count);
        $display("A15_4_SLOT_INJECTIONS=%0d", slot_injection_count);
        $display("A15_4_FINAL_LOADED_MASK=0x%0h", mask_value[3:0]);
        $display("STAGE2N_A15_4_F37X_KERNEL_ALL_HBM_PIPELINE_XSIM_V1_PASS");
        $finish;
    end

endmodule
