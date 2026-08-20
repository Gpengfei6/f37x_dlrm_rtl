`timescale 1ns/1ps

// Stage 2N-A14.3-A standalone Vitis RTL-kernel wrapper prototype.
//
// AXI4-Lite control map:
//   0x00 CONTROL
//          write bit 0: START (write-one command)
//          read  bit 0: start pending
//          read  bit 1: done (clear on CONTROL read)
//          read  bit 2: idle
//          read  bit 3: ready for START
//          read  bit 4: lookup response error
//   0x10 LOOKUP_INDEX
//   0x20 RESULT0, lanes 0 and 1
//   0x24 RESULT1, lanes 2 and 3
//   0x28 RESULT2, lanes 4 and 5
//   0x2C RESULT3, lanes 6 and 7
//
// This wrapper does not instantiate or modify the accepted A13 kernel. It
// connects the standalone A14.1 lookup prototype to a logical m_axi_gmem
// interface. The write side of m_axi_gmem is intentionally inactive.
module dlrm_f37x_rtl_kernel_stage2n_a14_v1 #(
    parameter integer C_S_AXI_CONTROL_ADDR_WIDTH = 12,
    parameter integer C_S_AXI_CONTROL_DATA_WIDTH = 32,
    parameter integer C_M_AXI_GMEM_ADDR_WIDTH    = 64,
    parameter integer C_M_AXI_GMEM_DATA_WIDTH    = 128,
    parameter integer C_M_AXI_GMEM_ID_WIDTH      = 1,
    parameter integer ROWS                       = 64,
    parameter integer DIM                        = 8,
    parameter integer ELEMENT_WIDTH              = 16
) (
    input  logic ap_clk,
    input  logic ap_rst_n,

    input  logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
                 s_axi_control_awaddr,
    input  logic  s_axi_control_awvalid,
    output logic  s_axi_control_awready,

    input  logic [C_S_AXI_CONTROL_DATA_WIDTH-1:0]
                 s_axi_control_wdata,
    input  logic [(C_S_AXI_CONTROL_DATA_WIDTH/8)-1:0]
                 s_axi_control_wstrb,
    input  logic  s_axi_control_wvalid,
    output logic  s_axi_control_wready,

    output logic [1:0] s_axi_control_bresp,
    output logic       s_axi_control_bvalid,
    input  logic       s_axi_control_bready,

    input  logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
                 s_axi_control_araddr,
    input  logic  s_axi_control_arvalid,
    output logic  s_axi_control_arready,

    output logic [C_S_AXI_CONTROL_DATA_WIDTH-1:0]
                 s_axi_control_rdata,
    output logic [1:0] s_axi_control_rresp,
    output logic       s_axi_control_rvalid,
    input  logic       s_axi_control_rready,

    output logic [C_M_AXI_GMEM_ID_WIDTH-1:0]   m_axi_gmem_awid,
    output logic [C_M_AXI_GMEM_ADDR_WIDTH-1:0] m_axi_gmem_awaddr,
    output logic [7:0]                         m_axi_gmem_awlen,
    output logic [2:0]                         m_axi_gmem_awsize,
    output logic [1:0]                         m_axi_gmem_awburst,
    output logic                               m_axi_gmem_awlock,
    output logic [3:0]                         m_axi_gmem_awcache,
    output logic [2:0]                         m_axi_gmem_awprot,
    output logic [3:0]                         m_axi_gmem_awqos,
    output logic                               m_axi_gmem_awvalid,
    input  logic                               m_axi_gmem_awready,

    output logic [C_M_AXI_GMEM_DATA_WIDTH-1:0] m_axi_gmem_wdata,
    output logic [(C_M_AXI_GMEM_DATA_WIDTH/8)-1:0]
                                                 m_axi_gmem_wstrb,
    output logic                               m_axi_gmem_wlast,
    output logic                               m_axi_gmem_wvalid,
    input  logic                               m_axi_gmem_wready,

    input  logic [C_M_AXI_GMEM_ID_WIDTH-1:0]   m_axi_gmem_bid,
    input  logic [1:0]                         m_axi_gmem_bresp,
    input  logic                               m_axi_gmem_bvalid,
    output logic                               m_axi_gmem_bready,

    output logic [C_M_AXI_GMEM_ID_WIDTH-1:0]   m_axi_gmem_arid,
    output logic [C_M_AXI_GMEM_ADDR_WIDTH-1:0] m_axi_gmem_araddr,
    output logic [7:0]                         m_axi_gmem_arlen,
    output logic [2:0]                         m_axi_gmem_arsize,
    output logic [1:0]                         m_axi_gmem_arburst,
    output logic                               m_axi_gmem_arlock,
    output logic [3:0]                         m_axi_gmem_arcache,
    output logic [2:0]                         m_axi_gmem_arprot,
    output logic [3:0]                         m_axi_gmem_arqos,
    output logic                               m_axi_gmem_arvalid,
    input  logic                               m_axi_gmem_arready,

    input  logic [C_M_AXI_GMEM_ID_WIDTH-1:0]   m_axi_gmem_rid,
    input  logic [C_M_AXI_GMEM_DATA_WIDTH-1:0] m_axi_gmem_rdata,
    input  logic [1:0]                         m_axi_gmem_rresp,
    input  logic                               m_axi_gmem_rlast,
    input  logic                               m_axi_gmem_rvalid,
    output logic                               m_axi_gmem_rready
);

    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_CONTROL      = 12'h000;
    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_LOOKUP_INDEX = 12'h010;
    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_RESULT0      = 12'h020;
    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_RESULT1      = 12'h024;
    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_RESULT2      = 12'h028;
    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_RESULT3      = 12'h02C;

    logic aw_pending;
    logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0] awaddr_reg;
    logic w_pending;
    logic [C_S_AXI_CONTROL_DATA_WIDTH-1:0] wdata_reg;
    logic [(C_S_AXI_CONTROL_DATA_WIDTH/8)-1:0] wstrb_reg;

    logic [31:0] lookup_index_reg;
    logic [31:0] lookup_request_index_reg;
    logic start_pending;
    logic done_latched;
    logic response_error_latched;
    logic [31:0] result_reg [0:3];

    logic lookup_req_ready;
    logic lookup_rsp_valid;
    logic [C_M_AXI_GMEM_DATA_WIDTH-1:0] lookup_rsp_data;
    logic [31:0] lookup_rsp_index;
    logic lookup_rsp_error;
    logic lookup_idle;
    logic lookup_start_ready;
    logic [31:0] control_status_word;

    integer reset_word;

    function automatic logic [31:0] apply_wstrb32(
        input logic [31:0] current_value,
        input logic [31:0] next_value,
        input logic [3:0] strobe
    );
        integer byte_index;
        begin
            apply_wstrb32 = current_value;
            for (byte_index = 0; byte_index < 4;
                 byte_index = byte_index + 1) begin
                if (strobe[byte_index]) begin
                    apply_wstrb32[byte_index*8 +: 8] =
                        next_value[byte_index*8 +: 8];
                end
            end
        end
    endfunction

    assign s_axi_control_awready =
        !aw_pending && !s_axi_control_bvalid;
    assign s_axi_control_wready =
        !w_pending && !s_axi_control_bvalid;
    assign s_axi_control_arready = !s_axi_control_rvalid;

    assign lookup_idle = lookup_req_ready && !start_pending;
    assign lookup_start_ready = lookup_idle && !done_latched;

    always_comb begin
        control_status_word = 32'd0;
        control_status_word[0] = start_pending;
        control_status_word[1] = done_latched;
        control_status_word[2] = lookup_idle;
        control_status_word[3] = lookup_start_ready;
        control_status_word[4] = response_error_latched;
    end

    // The A14.3-A prototype is read-only. Expose a complete AXI4 port bundle
    // for later Vitis packaging while keeping every write channel inactive.
    assign m_axi_gmem_awid = '0;
    assign m_axi_gmem_awaddr = '0;
    assign m_axi_gmem_awlen = 8'd0;
    assign m_axi_gmem_awsize = 3'd4;
    assign m_axi_gmem_awburst = 2'b01;
    assign m_axi_gmem_awlock = 1'b0;
    assign m_axi_gmem_awcache = 4'b0011;
    assign m_axi_gmem_awprot = 3'b000;
    assign m_axi_gmem_awqos = 4'b0000;
    assign m_axi_gmem_awvalid = 1'b0;

    assign m_axi_gmem_wdata = '0;
    assign m_axi_gmem_wstrb = '0;
    assign m_axi_gmem_wlast = 1'b0;
    assign m_axi_gmem_wvalid = 1'b0;
    assign m_axi_gmem_bready = 1'b0;

    always_ff @(posedge ap_clk) begin
        if (!ap_rst_n) begin
            aw_pending <= 1'b0;
            awaddr_reg <= '0;
            w_pending <= 1'b0;
            wdata_reg <= '0;
            wstrb_reg <= '0;
            s_axi_control_bresp <= 2'b00;
            s_axi_control_bvalid <= 1'b0;

            s_axi_control_rdata <= '0;
            s_axi_control_rresp <= 2'b00;
            s_axi_control_rvalid <= 1'b0;

            lookup_index_reg <= 32'd0;
            lookup_request_index_reg <= 32'd0;
            start_pending <= 1'b0;
            done_latched <= 1'b0;
            response_error_latched <= 1'b0;
            for (reset_word = 0; reset_word < 4;
                 reset_word = reset_word + 1) begin
                result_reg[reset_word] <= 32'd0;
            end
        end else begin
            if (s_axi_control_bvalid && s_axi_control_bready)
                s_axi_control_bvalid <= 1'b0;

            if (s_axi_control_awvalid && s_axi_control_awready) begin
                awaddr_reg <= s_axi_control_awaddr;
                aw_pending <= 1'b1;
            end

            if (s_axi_control_wvalid && s_axi_control_wready) begin
                wdata_reg <= s_axi_control_wdata;
                wstrb_reg <= s_axi_control_wstrb;
                w_pending <= 1'b1;
            end

            if (aw_pending && w_pending &&
                !s_axi_control_bvalid) begin
                aw_pending <= 1'b0;
                w_pending <= 1'b0;
                s_axi_control_bresp <= 2'b00;
                s_axi_control_bvalid <= 1'b1;

                case (awaddr_reg)
                    ADDR_CONTROL: begin
                        if (wstrb_reg[0] && wdata_reg[0]) begin
                            if (lookup_start_ready) begin
                                lookup_request_index_reg <=
                                    lookup_index_reg;
                                start_pending <= 1'b1;
                                response_error_latched <= 1'b0;
                            end else begin
                                s_axi_control_bresp <= 2'b10;
                            end
                        end
                    end

                    ADDR_LOOKUP_INDEX: begin
                        lookup_index_reg <= apply_wstrb32(
                            lookup_index_reg,
                            wdata_reg,
                            wstrb_reg
                        );
                    end

                    default: begin
                        s_axi_control_bresp <= 2'b10;
                    end
                endcase
            end

            if (start_pending && lookup_req_ready)
                start_pending <= 1'b0;

            if (s_axi_control_rvalid && s_axi_control_rready)
                s_axi_control_rvalid <= 1'b0;

            if (s_axi_control_arvalid && s_axi_control_arready) begin
                s_axi_control_rdata <= 32'd0;
                s_axi_control_rresp <= 2'b00;
                s_axi_control_rvalid <= 1'b1;

                case (s_axi_control_araddr)
                    ADDR_CONTROL: begin
                        s_axi_control_rdata <= control_status_word;
                        done_latched <= 1'b0;
                    end

                    ADDR_LOOKUP_INDEX:
                        s_axi_control_rdata <= lookup_index_reg;
                    ADDR_RESULT0:
                        s_axi_control_rdata <= result_reg[0];
                    ADDR_RESULT1:
                        s_axi_control_rdata <= result_reg[1];
                    ADDR_RESULT2:
                        s_axi_control_rdata <= result_reg[2];
                    ADDR_RESULT3:
                        s_axi_control_rdata <= result_reg[3];

                    default: begin
                        s_axi_control_rdata <= 32'd0;
                        s_axi_control_rresp <= 2'b10;
                    end
                endcase
            end

            if (lookup_rsp_valid) begin
                result_reg[0] <= lookup_rsp_data[31:0];
                result_reg[1] <= lookup_rsp_data[63:32];
                result_reg[2] <= lookup_rsp_data[95:64];
                result_reg[3] <= lookup_rsp_data[127:96];
                done_latched <= 1'b1;
                response_error_latched <= lookup_rsp_error;
            end
        end
    end

    dlrm_hbm_embedding_lookup_stage2n_a14_v1 #(
        .ROWS(ROWS),
        .DIM(DIM),
        .ELEMENT_WIDTH(ELEMENT_WIDTH),
        .DATA_WIDTH(C_M_AXI_GMEM_DATA_WIDTH),
        .AXI_ADDR_WIDTH(C_M_AXI_GMEM_ADDR_WIDTH),
        .AXI_ID_WIDTH(C_M_AXI_GMEM_ID_WIDTH),
        .INDEX_WIDTH(32)
    ) u_hbm_embedding_lookup (
        .clk(ap_clk),
        .rst(!ap_rst_n),

        .lookup_req_valid(start_pending),
        .lookup_req_ready(lookup_req_ready),
        .lookup_req_index(lookup_request_index_reg),

        .lookup_rsp_valid(lookup_rsp_valid),
        .lookup_rsp_ready(1'b1),
        .lookup_rsp_data(lookup_rsp_data),
        .lookup_rsp_index(lookup_rsp_index),
        .lookup_rsp_error(lookup_rsp_error),

        .m_axi_arid(m_axi_gmem_arid),
        .m_axi_araddr(m_axi_gmem_araddr),
        .m_axi_arlen(m_axi_gmem_arlen),
        .m_axi_arsize(m_axi_gmem_arsize),
        .m_axi_arburst(m_axi_gmem_arburst),
        .m_axi_arlock(m_axi_gmem_arlock),
        .m_axi_arcache(m_axi_gmem_arcache),
        .m_axi_arprot(m_axi_gmem_arprot),
        .m_axi_arqos(m_axi_gmem_arqos),
        .m_axi_arvalid(m_axi_gmem_arvalid),
        .m_axi_arready(m_axi_gmem_arready),

        .m_axi_rid(m_axi_gmem_rid),
        .m_axi_rdata(m_axi_gmem_rdata),
        .m_axi_rresp(m_axi_gmem_rresp),
        .m_axi_rlast(m_axi_gmem_rlast),
        .m_axi_rvalid(m_axi_gmem_rvalid),
        .m_axi_rready(m_axi_gmem_rready)
    );

    initial begin
        if (C_S_AXI_CONTROL_ADDR_WIDTH < 6)
            $error("A14.3-A AXI-Lite address width must cover 0x2C");
        if (C_S_AXI_CONTROL_DATA_WIDTH != 32)
            $error("A14.3-A AXI-Lite data width must be 32 bits");
        if (C_M_AXI_GMEM_ADDR_WIDTH != 64)
            $error("A14.3-A m_axi_gmem address width must be 64 bits");
        if (C_M_AXI_GMEM_DATA_WIDTH != 128)
            $error("A14.3-A m_axi_gmem data width must be 128 bits");
        if (ROWS != 64 || DIM != 8 || ELEMENT_WIDTH != 16)
            $error("A14.3-A prototype requires ROWS=64, DIM=8, INT16");
    end

endmodule
