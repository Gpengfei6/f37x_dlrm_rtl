`timescale 1ns/1ps

// Reusable saturating interval counter used by the A16.1 instrumentation.
// START is counted as cycle one.  While active, every later rising edge is
// counted, including the edge on which STOP is observed.  CLEAR discards an
// incomplete interval; a retained completed count is otherwise stable.
module dlrm_saturating_interval_counter_stage2n_a16_v1 #(
    parameter integer COUNTER_WIDTH = 32
) (
    input  logic                     clk,
    input  logic                     rst,
    input  logic                     clear,
    input  logic                     start,
    input  logic                     stop,
    output logic                     active,
    output logic [COUNTER_WIDTH-1:0] count
);

    function automatic logic [COUNTER_WIDTH-1:0] saturating_increment(
        input logic [COUNTER_WIDTH-1:0] value
    );
        begin
            if (&value)
                saturating_increment = value;
            else
                saturating_increment = value + 1'b1;
        end
    endfunction

    always_ff @(posedge clk) begin
        if (rst) begin
            active <= 1'b0;
            count <= '0;
        end else if (clear) begin
            active <= 1'b0;
            count <= '0;
        end else if (start) begin
            active <= !stop;
            count <= {{(COUNTER_WIDTH-1){1'b0}}, 1'b1};
        end else if (active) begin
            count <= saturating_increment(count);
            if (stop)
                active <= 1'b0;
        end
    end

    initial begin
        if (COUNTER_WIDTH < 1)
            $error("A16.1 counter width must be positive");
    end

endmodule

// Stage 2N-A16.1 v1 F37X latency-instrumented kernel top.
//
// The verified Stage 2N-A2 kernel remains unchanged at 0x000-0x17F:
//   0x000-0x0FF legacy MLP window
//   0x100-0x13F standalone interaction window
//
// The accepted A13 register map remains unchanged through 0x224, including
// its four read-only cycle counters.  The accepted A15 window at 0x300-0x308
// is unchanged. A16.1 adds two read-only counters at 0x30C and 0x310 while
// retaining the same single public m_axi_gmem read master.
module dlrm_f37x_rtl_kernel_stage2n_a16_v1 #(
    parameter integer C_S_AXI_CONTROL_ADDR_WIDTH = 12,
    parameter integer C_S_AXI_CONTROL_DATA_WIDTH = 32,
    parameter integer C_M_AXI_GMEM_ADDR_WIDTH = 64,
    parameter integer C_M_AXI_GMEM_DATA_WIDTH = 128,
    parameter integer C_M_AXI_GMEM_ID_WIDTH = 1
) (
    input  logic ap_clk,
    input  logic ap_rst_n,

    input  logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0] s_axi_control_awaddr,
    input  logic                                  s_axi_control_awvalid,
    output logic                                  s_axi_control_awready,

    input  logic [C_S_AXI_CONTROL_DATA_WIDTH-1:0] s_axi_control_wdata,
    input  logic [(C_S_AXI_CONTROL_DATA_WIDTH/8)-1:0]
                                                   s_axi_control_wstrb,
    input  logic                                  s_axi_control_wvalid,
    output logic                                  s_axi_control_wready,

    output logic [1:0] s_axi_control_bresp,
    output logic       s_axi_control_bvalid,
    input  logic       s_axi_control_bready,

    input  logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0] s_axi_control_araddr,
    input  logic                                  s_axi_control_arvalid,
    output logic                                  s_axi_control_arready,

    output logic [C_S_AXI_CONTROL_DATA_WIDTH-1:0] s_axi_control_rdata,
    output logic [1:0]                            s_axi_control_rresp,
    output logic                                  s_axi_control_rvalid,
    input  logic                                  s_axi_control_rready,

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
        ADDR_PIPELINE_BASE = 12'h180;

    logic host_aw_pending;
    logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0] host_awaddr_reg;
    logic host_w_pending;
    logic [C_S_AXI_CONTROL_DATA_WIDTH-1:0] host_wdata_reg;
    logic [(C_S_AXI_CONTROL_DATA_WIDTH/8)-1:0] host_wstrb_reg;

    logic write_active;
    logic write_target_pipeline;
    logic write_aw_sent;
    logic write_w_sent;

    logic read_active;
    logic read_target_pipeline;
    logic read_ar_sent;
    logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0] read_araddr_reg;

    logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0] a2_awaddr;
    logic a2_awvalid;
    logic a2_awready;
    logic [C_S_AXI_CONTROL_DATA_WIDTH-1:0] a2_wdata;
    logic [(C_S_AXI_CONTROL_DATA_WIDTH/8)-1:0] a2_wstrb;
    logic a2_wvalid;
    logic a2_wready;
    logic [1:0] a2_bresp;
    logic a2_bvalid;
    logic a2_bready;
    logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0] a2_araddr;
    logic a2_arvalid;
    logic a2_arready;
    logic [C_S_AXI_CONTROL_DATA_WIDTH-1:0] a2_rdata;
    logic [1:0] a2_rresp;
    logic a2_rvalid;
    logic a2_rready;

    logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0] pipe_awaddr;
    logic pipe_awvalid;
    logic pipe_awready;
    logic [C_S_AXI_CONTROL_DATA_WIDTH-1:0] pipe_wdata;
    logic [(C_S_AXI_CONTROL_DATA_WIDTH/8)-1:0] pipe_wstrb;
    logic pipe_wvalid;
    logic pipe_wready;
    logic [1:0] pipe_bresp;
    logic pipe_bvalid;
    logic pipe_bready;
    logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0] pipe_araddr;
    logic pipe_arvalid;
    logic pipe_arready;
    logic [C_S_AXI_CONTROL_DATA_WIDTH-1:0] pipe_rdata;
    logic [1:0] pipe_rresp;
    logic pipe_rvalid;
    logic pipe_rready;

    logic selected_awready;
    logic selected_wready;
    logic selected_bvalid;
    logic [1:0] selected_bresp;
    logic selected_arready;
    logic selected_rvalid;
    logic [C_S_AXI_CONTROL_DATA_WIDTH-1:0] selected_rdata;
    logic [1:0] selected_rresp;

    assign s_axi_control_awready =
        !host_aw_pending && !write_active && !s_axi_control_bvalid;
    assign s_axi_control_wready =
        !host_w_pending && !write_active && !s_axi_control_bvalid;
    assign s_axi_control_arready =
        !read_active && !s_axi_control_rvalid;

    assign a2_awaddr = host_awaddr_reg;
    assign a2_awvalid =
        write_active && !write_target_pipeline && !write_aw_sent;
    assign a2_wdata = host_wdata_reg;
    assign a2_wstrb = host_wstrb_reg;
    assign a2_wvalid =
        write_active && !write_target_pipeline && !write_w_sent;
    assign a2_bready =
        write_active && !write_target_pipeline &&
        write_aw_sent && write_w_sent && !s_axi_control_bvalid;

    assign pipe_awaddr = host_awaddr_reg;
    assign pipe_awvalid =
        write_active && write_target_pipeline && !write_aw_sent;
    assign pipe_wdata = host_wdata_reg;
    assign pipe_wstrb = host_wstrb_reg;
    assign pipe_wvalid =
        write_active && write_target_pipeline && !write_w_sent;
    assign pipe_bready =
        write_active && write_target_pipeline &&
        write_aw_sent && write_w_sent && !s_axi_control_bvalid;

    assign selected_awready =
        write_target_pipeline ? pipe_awready : a2_awready;
    assign selected_wready =
        write_target_pipeline ? pipe_wready : a2_wready;
    assign selected_bvalid =
        write_target_pipeline ? pipe_bvalid : a2_bvalid;
    assign selected_bresp =
        write_target_pipeline ? pipe_bresp : a2_bresp;

    assign a2_araddr = read_araddr_reg;
    assign a2_arvalid =
        read_active && !read_target_pipeline && !read_ar_sent;
    assign a2_rready =
        read_active && !read_target_pipeline && read_ar_sent &&
        !s_axi_control_rvalid;

    assign pipe_araddr = read_araddr_reg;
    assign pipe_arvalid =
        read_active && read_target_pipeline && !read_ar_sent;
    assign pipe_rready =
        read_active && read_target_pipeline && read_ar_sent &&
        !s_axi_control_rvalid;

    assign selected_arready =
        read_target_pipeline ? pipe_arready : a2_arready;
    assign selected_rvalid =
        read_target_pipeline ? pipe_rvalid : a2_rvalid;
    assign selected_rdata =
        read_target_pipeline ? pipe_rdata : a2_rdata;
    assign selected_rresp =
        read_target_pipeline ? pipe_rresp : a2_rresp;

    always_ff @(posedge ap_clk) begin
        if (!ap_rst_n) begin
            host_aw_pending <= 1'b0;
            host_awaddr_reg <= '0;
            host_w_pending <= 1'b0;
            host_wdata_reg <= '0;
            host_wstrb_reg <= '0;
            write_active <= 1'b0;
            write_target_pipeline <= 1'b0;
            write_aw_sent <= 1'b0;
            write_w_sent <= 1'b0;
            s_axi_control_bresp <= 2'b00;
            s_axi_control_bvalid <= 1'b0;
        end else begin
            if (s_axi_control_awvalid && s_axi_control_awready) begin
                host_awaddr_reg <= s_axi_control_awaddr;
                host_aw_pending <= 1'b1;
            end

            if (s_axi_control_wvalid && s_axi_control_wready) begin
                host_wdata_reg <= s_axi_control_wdata;
                host_wstrb_reg <= s_axi_control_wstrb;
                host_w_pending <= 1'b1;
            end

            if (!write_active && host_aw_pending && host_w_pending &&
                !s_axi_control_bvalid) begin
                write_active <= 1'b1;
                write_target_pipeline <=
                    (host_awaddr_reg >= ADDR_PIPELINE_BASE);
                write_aw_sent <= 1'b0;
                write_w_sent <= 1'b0;
                host_aw_pending <= 1'b0;
                host_w_pending <= 1'b0;
            end

            if (write_active) begin
                if (!write_aw_sent && selected_awready)
                    write_aw_sent <= 1'b1;
                if (!write_w_sent && selected_wready)
                    write_w_sent <= 1'b1;

                if (selected_bvalid &&
                    ((write_target_pipeline && pipe_bready) ||
                     (!write_target_pipeline && a2_bready))) begin
                    s_axi_control_bresp <= selected_bresp;
                    s_axi_control_bvalid <= 1'b1;
                    write_active <= 1'b0;
                    write_aw_sent <= 1'b0;
                    write_w_sent <= 1'b0;
                end
            end

            if (s_axi_control_bvalid && s_axi_control_bready)
                s_axi_control_bvalid <= 1'b0;
        end
    end

    always_ff @(posedge ap_clk) begin
        if (!ap_rst_n) begin
            read_active <= 1'b0;
            read_target_pipeline <= 1'b0;
            read_ar_sent <= 1'b0;
            read_araddr_reg <= '0;
            s_axi_control_rdata <= '0;
            s_axi_control_rresp <= 2'b00;
            s_axi_control_rvalid <= 1'b0;
        end else begin
            if (s_axi_control_arvalid && s_axi_control_arready) begin
                read_active <= 1'b1;
                read_target_pipeline <=
                    (s_axi_control_araddr >= ADDR_PIPELINE_BASE);
                read_araddr_reg <= s_axi_control_araddr;
                read_ar_sent <= 1'b0;
            end

            if (read_active) begin
                if (!read_ar_sent && selected_arready)
                    read_ar_sent <= 1'b1;

                if (selected_rvalid &&
                    ((read_target_pipeline && pipe_rready) ||
                     (!read_target_pipeline && a2_rready))) begin
                    s_axi_control_rdata <= selected_rdata;
                    s_axi_control_rresp <= selected_rresp;
                    s_axi_control_rvalid <= 1'b1;
                    read_active <= 1'b0;
                    read_ar_sent <= 1'b0;
                end
            end

            if (s_axi_control_rvalid && s_axi_control_rready)
                s_axi_control_rvalid <= 1'b0;
        end
    end

    dlrm_f37x_rtl_kernel_stage2n_a2 u_stage2n_a2 (
        .ap_clk(ap_clk),
        .ap_rst_n(ap_rst_n),
        .s_axi_control_awaddr(a2_awaddr),
        .s_axi_control_awvalid(a2_awvalid),
        .s_axi_control_awready(a2_awready),
        .s_axi_control_wdata(a2_wdata),
        .s_axi_control_wstrb(a2_wstrb),
        .s_axi_control_wvalid(a2_wvalid),
        .s_axi_control_wready(a2_wready),
        .s_axi_control_bresp(a2_bresp),
        .s_axi_control_bvalid(a2_bvalid),
        .s_axi_control_bready(a2_bready),
        .s_axi_control_araddr(a2_araddr),
        .s_axi_control_arvalid(a2_arvalid),
        .s_axi_control_arready(a2_arready),
        .s_axi_control_rdata(a2_rdata),
        .s_axi_control_rresp(a2_rresp),
        .s_axi_control_rvalid(a2_rvalid),
        .s_axi_control_rready(a2_rready)
    );

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

    dlrm_internal_pipeline_axi_lite_adapter_stage2n_a16_v1 #(
        .C_S_AXI_CONTROL_ADDR_WIDTH(C_S_AXI_CONTROL_ADDR_WIDTH),
        .C_S_AXI_CONTROL_DATA_WIDTH(C_S_AXI_CONTROL_DATA_WIDTH),
        .C_M_AXI_GMEM_ADDR_WIDTH(C_M_AXI_GMEM_ADDR_WIDTH),
        .C_M_AXI_GMEM_DATA_WIDTH(C_M_AXI_GMEM_DATA_WIDTH),
        .C_M_AXI_GMEM_ID_WIDTH(C_M_AXI_GMEM_ID_WIDTH)
    )
        u_pipeline_adapter (
        .ap_clk(ap_clk),
        .ap_rst_n(ap_rst_n),
        .s_axi_control_awaddr(pipe_awaddr),
        .s_axi_control_awvalid(pipe_awvalid),
        .s_axi_control_awready(pipe_awready),
        .s_axi_control_wdata(pipe_wdata),
        .s_axi_control_wstrb(pipe_wstrb),
        .s_axi_control_wvalid(pipe_wvalid),
        .s_axi_control_wready(pipe_wready),
        .s_axi_control_bresp(pipe_bresp),
        .s_axi_control_bvalid(pipe_bvalid),
        .s_axi_control_bready(pipe_bready),
        .s_axi_control_araddr(pipe_araddr),
        .s_axi_control_arvalid(pipe_arvalid),
        .s_axi_control_arready(pipe_arready),
        .s_axi_control_rdata(pipe_rdata),
        .s_axi_control_rresp(pipe_rresp),
        .s_axi_control_rvalid(pipe_rvalid),
        .s_axi_control_rready(pipe_rready),
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

`timescale 1ns/1ps

// Stage 2N-A16.1 AXI-Lite adapter for the instrumented all-HBM pipeline.
//
// The complete accepted A13 window through 0x224 and the accepted A15 window
// through 0x308 are preserved. A16.1 adds only the two read-only counters at
// 0x30C/0x310 around the unchanged four-lookup and compute sequence.
module dlrm_internal_pipeline_axi_lite_adapter_stage2n_a16_v1 #(
    parameter integer C_S_AXI_CONTROL_ADDR_WIDTH = 12,
    parameter integer C_S_AXI_CONTROL_DATA_WIDTH = 32,
    parameter integer C_M_AXI_GMEM_ADDR_WIDTH = 64,
    parameter integer C_M_AXI_GMEM_DATA_WIDTH = 128,
    parameter integer C_M_AXI_GMEM_ID_WIDTH = 1,
    parameter integer MAX_LAYERS = 8,
    parameter integer MAX_IN_DIM = 64,
    parameter integer MAX_OUT_DIM = 64,
    parameter integer NUM_PE = 16,
    parameter integer INPUT_WIDTH = 16,
    parameter integer WEIGHT_WIDTH = 8,
    parameter integer BIAS_WIDTH = 24,
    parameter integer ACC_WIDTH = 48,
    parameter integer OUTPUT_WIDTH = 16,
    parameter integer MAX_WEIGHT_VALUES = 2048,
    parameter integer MAX_BIAS_VALUES = 128,
    parameter integer RESULT_FIFO_DEPTH = 2,
    parameter integer LAYER_INDEX_WIDTH =
        (MAX_LAYERS <= 1) ? 1 : $clog2(MAX_LAYERS),
    parameter integer LAYER_COUNT_WIDTH =
        (MAX_LAYERS <= 1) ? 1 : $clog2(MAX_LAYERS+1),
    parameter integer ACT_MAX_DIM =
        (MAX_IN_DIM > MAX_OUT_DIM) ? MAX_IN_DIM : MAX_OUT_DIM,
    parameter integer ACT_BANK_DEPTH =
        (ACT_MAX_DIM+NUM_PE-1)/NUM_PE,
    parameter integer ACT_CHUNK_ADDR_WIDTH =
        (ACT_BANK_DEPTH <= 1) ? 1 : $clog2(ACT_BANK_DEPTH),
    parameter integer SHIFT_WIDTH =
        (ACC_WIDTH <= 1) ? 1 : $clog2(ACC_WIDTH+1),
    parameter integer OUT_INDEX_WIDTH =
        (MAX_OUT_DIM <= 1) ? 1 : $clog2(MAX_OUT_DIM)
) (
    input  logic ap_clk,
    input  logic ap_rst_n,

    input  logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0] s_axi_control_awaddr,
    input  logic                                  s_axi_control_awvalid,
    output logic                                  s_axi_control_awready,

    input  logic [C_S_AXI_CONTROL_DATA_WIDTH-1:0] s_axi_control_wdata,
    input  logic [(C_S_AXI_CONTROL_DATA_WIDTH/8)-1:0]
                                                   s_axi_control_wstrb,
    input  logic                                  s_axi_control_wvalid,
    output logic                                  s_axi_control_wready,

    output logic [1:0] s_axi_control_bresp,
    output logic       s_axi_control_bvalid,
    input  logic       s_axi_control_bready,

    input  logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0] s_axi_control_araddr,
    input  logic                                  s_axi_control_arvalid,
    output logic                                  s_axi_control_arready,

    output logic [C_S_AXI_CONTROL_DATA_WIDTH-1:0] s_axi_control_rdata,
    output logic [1:0]                            s_axi_control_rresp,
    output logic                                  s_axi_control_rvalid,
    input  logic                                  s_axi_control_rready,

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
        ADDR_PIPE_CONTROL_STATUS = 12'h180;
    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_PIPE_VERSION = 12'h184;
    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_PIPE_RESULT_COUNT = 12'h188;
    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_PIPE_PHASE_COUNTS = 12'h18C;

    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_PIPE_DESC_INDEX = 12'h190;
    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_PIPE_DESC_WORD0 = 12'h194;
    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_PIPE_DESC_WORD1 = 12'h198;
    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_PIPE_DESC_WORD2 = 12'h19C;

    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_PIPE_ACT_BUFFER = 12'h1A0;
    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_PIPE_ACT_CHUNK_INDEX = 12'h1A4;
    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_PIPE_ACT_LANE_MASK = 12'h1A8;
    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_PIPE_ACT_DATA0 = 12'h1B0;
    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_PIPE_ACT_DATA1 = 12'h1B4;
    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_PIPE_ACT_DATA2 = 12'h1B8;
    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_PIPE_ACT_DATA3 = 12'h1BC;
    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_PIPE_ACT_DATA4 = 12'h1C0;
    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_PIPE_ACT_DATA5 = 12'h1C4;
    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_PIPE_ACT_DATA6 = 12'h1C8;
    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_PIPE_ACT_DATA7 = 12'h1CC;

    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_PIPE_EMB_INDEX = 12'h1D0;
    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_PIPE_EMB_DATA0 = 12'h1D4;
    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_PIPE_EMB_DATA1 = 12'h1D8;
    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_PIPE_EMB_DATA2 = 12'h1DC;
    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_PIPE_EMB_DATA3 = 12'h1E0;

    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_PIPE_WEIGHT_ADDRESS = 12'h1E4;
    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_PIPE_WEIGHT_DATA = 12'h1E8;
    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_PIPE_BIAS_ADDRESS = 12'h1EC;
    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_PIPE_BIAS_DATA = 12'h1F0;

    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_PIPE_BOTTOM_CONFIG = 12'h1F4;
    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_PIPE_TOP_CONFIG = 12'h1F8;
    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_PIPELINE_CONFIG = 12'h1FC;

    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_PIPE_RESULT_DATA = 12'h200;
    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_PIPE_RESULT_INDEX = 12'h204;
    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_PIPE_RESULT_META = 12'h208;
    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_PIPE_EMB_LOADED_MASK = 12'h20C;
    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_PIPE_ERROR_CODE = 12'h210;
    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_PIPE_CONFIG_READY = 12'h214;
    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_PIPE_BOTTOM_CYCLES = 12'h218;
    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_PIPE_INTERACTION_CYCLES = 12'h21C;
    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_PIPE_TOP_CYCLES = 12'h220;
    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_PIPE_TOTAL_CYCLES = 12'h224;

    // A15.4 uses a separate window so every accepted A13 address remains
    // unchanged. Rows 37-40 are fixed by the accepted A15.3 controller.
    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_A15_CONTROL_STATUS = 12'h300;
    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_A15_TABLE_BASE_LO = 12'h304;
    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_A15_TABLE_BASE_HI = 12'h308;
    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_A16_HBM_LOOKUP_CYCLES = 12'h30C;
    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_A16_FPGA_END_TO_END_CYCLES = 12'h310;

    localparam logic [15:0] PIPE_CMD_DESC_COMMIT = 16'h0001;
    localparam logic [15:0] PIPE_CMD_ACT_COMMIT = 16'h0002;
    localparam logic [15:0] PIPE_CMD_EMB_COMMIT = 16'h0004;
    localparam logic [15:0] PIPE_CMD_WEIGHT_COMMIT = 16'h0008;
    localparam logic [15:0] PIPE_CMD_BIAS_COMMIT = 16'h0010;
    localparam logic [15:0] PIPE_CMD_START = 16'h0020;
    localparam logic [15:0] PIPE_CMD_RESULT_POP = 16'h0040;
    localparam logic [15:0] PIPE_CMD_ERROR_ACK = 16'h0080;
    localparam logic [15:0] PIPE_CMD_CLEAR_DONE = 16'h0100;

    localparam logic [15:0] A15_CMD_START = 16'h0001;
    localparam logic [15:0] A15_CMD_CLEAR = 16'h0002;

    localparam logic [3:0] WRAPPER_ERROR_NONE = 4'd0;
    localparam logic [3:0] WRAPPER_ERROR_PENDING = 4'd1;
    localparam logic [3:0] WRAPPER_ERROR_BAD_COMMAND = 4'd2;
    localparam logic [3:0] WRAPPER_ERROR_CORE_NOT_READY = 4'd3;
    localparam logic [3:0] WRAPPER_ERROR_BAD_ADDRESS = 4'd4;
    localparam logic [3:0] WRAPPER_ERROR_EMBEDDING_OWNED = 4'd5;

    typedef enum logic [2:0] {
        A15_IDLE,
        A15_LOAD_REQUEST,
        A15_LOAD_WAIT,
        A15_PIPE_START,
        A15_PIPE_WAIT,
        A15_DONE,
        A15_ERROR,
        A15_RECOVER
    } a15_state_t;

    logic aw_pending;
    logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0] awaddr_reg;
    logic w_pending;
    logic [C_S_AXI_CONTROL_DATA_WIDTH-1:0] wdata_reg;
    logic [(C_S_AXI_CONTROL_DATA_WIDTH/8)-1:0] wstrb_reg;
    logic aw_fire;
    logic w_fire;
    logic write_fire;
    logic ar_fire;

    logic [31:0] desc_index_stage;
    logic [31:0] desc_word_stage [0:2];
    logic [31:0] act_buffer_stage;
    logic [31:0] act_chunk_stage;
    logic [31:0] act_lane_mask_stage;
    logic [31:0] act_data_stage [0:7];
    logic [31:0] emb_index_stage;
    logic [31:0] emb_data_stage [0:3];
    logic [31:0] weight_address_stage;
    logic [31:0] weight_data_stage;
    logic [31:0] bias_address_stage;
    logic [31:0] bias_data_stage;
    logic [31:0] bottom_config_stage;
    logic [31:0] top_config_stage;
    logic [31:0] pipeline_config_stage;
    logic [C_M_AXI_GMEM_ADDR_WIDTH-1:0] a15_table_base_stage;
    logic [C_M_AXI_GMEM_ADDR_WIDTH-1:0] a15_table_base_cmd;

    logic descriptor_pending;
    logic [LAYER_INDEX_WIDTH-1:0] descriptor_index_cmd;
    logic [95:0] descriptor_data_cmd;

    logic act_pending;
    logic act_buffer_cmd;
    logic [ACT_CHUNK_ADDR_WIDTH-1:0] act_chunk_cmd;
    logic [NUM_PE-1:0] act_lane_mask_cmd;
    logic [NUM_PE*INPUT_WIDTH-1:0] act_data_cmd;

    logic embedding_pending;
    logic [1:0] embedding_index_cmd;
    logic [8*INPUT_WIDTH-1:0] embedding_data_cmd;

    logic weight_pending;
    logic [31:0] weight_address_cmd;
    logic signed [WEIGHT_WIDTH-1:0] weight_data_cmd;

    logic bias_pending;
    logic [31:0] bias_address_cmd;
    logic signed [BIAS_WIDTH-1:0] bias_data_cmd;

    logic start_pending;
    logic [LAYER_INDEX_WIDTH-1:0] bottom_descriptor_base_cmd;
    logic [LAYER_COUNT_WIDTH-1:0] bottom_layer_count_cmd;
    logic [LAYER_INDEX_WIDTH-1:0] top_descriptor_base_cmd;
    logic [LAYER_COUNT_WIDTH-1:0] top_layer_count_cmd;
    logic bottom_initial_buffer_cmd;
    logic top_input_buffer_cmd;
    logic [SHIFT_WIDTH-1:0] interaction_shift_cmd;

    logic [LAYER_INDEX_WIDTH-1:0] a15_bottom_descriptor_base_cmd;
    logic [LAYER_COUNT_WIDTH-1:0] a15_bottom_layer_count_cmd;
    logic [LAYER_INDEX_WIDTH-1:0] a15_top_descriptor_base_cmd;
    logic [LAYER_COUNT_WIDTH-1:0] a15_top_layer_count_cmd;
    logic a15_bottom_initial_buffer_cmd;
    logic a15_top_input_buffer_cmd;
    logic [SHIFT_WIDTH-1:0] a15_interaction_shift_cmd;

    logic result_ready_pulse;
    logic error_ready_pulse;

    logic core_descriptor_ready;
    logic core_act_ready;
    logic core_embedding_ready;
    logic core_weight_ready;
    logic core_bias_ready;
    logic core_start_ready;
    logic [3:0] core_embedding_loaded_mask;

    logic core_result_valid;
    logic signed [OUTPUT_WIDTH-1:0] core_result_data;
    logic [OUT_INDEX_WIDTH-1:0] core_result_index;
    logic core_result_last;
    logic [7:0] core_result_tag;

    logic core_busy;
    logic core_done;
    logic [3:0] core_phase;
    logic [3:0] core_bottom_result_count;
    logic [4:0] core_interaction_result_count;
    logic [31:0] core_bottom_cycle_count;
    logic [31:0] core_interaction_cycle_count;
    logic [31:0] core_top_cycle_count;
    logic [31:0] core_total_cycle_count;
    logic core_error_valid;
    logic [7:0] core_error_code;

    a15_state_t a15_state;
    logic a15_active;
    logic a15_start_ready;
    logic a15_auto_start_valid;
    logic core_pipeline_start_valid;
    logic host_embedding_cfg_rejected;
    logic load_all_req_ready;
    logic hbm_sequence_busy;
    logic hbm_all_loaded;
    logic hbm_sequence_done;
    logic hbm_inject_pending;
    logic [1:0] hbm_inject_slot;
    logic [C_M_AXI_GMEM_DATA_WIDTH-1:0] hbm_inject_data;
    logic hbm_inject_done;
    logic hbm_sequence_error_valid;
    logic hbm_sequence_error_ready;
    logic [1:0] hbm_sequence_error_slot;
    logic [31:0] hbm_sequence_error_index;

    logic done_latched;
    logic [31:0] result_count;
    logic signed [OUTPUT_WIDTH-1:0] result_data_latched;
    logic [OUT_INDEX_WIDTH-1:0] result_index_latched;
    logic result_last_latched;
    logic [7:0] result_tag_latched;
    logic [3:0] bottom_count_latched;
    logic [4:0] interaction_count_latched;

    logic wrapper_error_latched;
    logic [3:0] wrapper_error_code;
    logic command_pending_any;

    logic [31:0] status_word;
    logic [31:0] phase_counts_word;
    logic [31:0] result_meta_word;
    logic [31:0] error_code_word;
    logic [31:0] config_ready_word;
    logic [31:0] a15_status_word;
    logic [31:0] control_command_word;
    logic [3:0] visible_bottom_count;
    logic [4:0] visible_interaction_count;

    logic a16_start_accept;
    logic a16_first_lookup_start;
    logic a16_lookup_complete;
    logic a16_final_result_visible;
    logic a16_terminal_error;
    logic a16_hbm_lookup_active;
    logic a16_fpga_end_to_end_active;
    logic [31:0] a16_hbm_lookup_cycle_count;
    logic [31:0] a16_fpga_end_to_end_cycle_count;

    integer reset_index;

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

    assign a15_active =
        (a15_state == A15_LOAD_REQUEST) ||
        (a15_state == A15_LOAD_WAIT) ||
        (a15_state == A15_PIPE_START) ||
        (a15_state == A15_PIPE_WAIT);

    assign a15_start_ready =
        (a15_state == A15_IDLE) &&
        !descriptor_pending &&
        !act_pending &&
        !embedding_pending &&
        !weight_pending &&
        !bias_pending &&
        !start_pending &&
        core_descriptor_ready &&
        core_act_ready &&
        core_weight_ready &&
        core_bias_ready &&
        !core_busy &&
        !core_result_valid &&
        !core_error_valid &&
        !wrapper_error_latched &&
        load_all_req_ready;

    assign a15_auto_start_valid = (a15_state == A15_PIPE_START);
    assign core_pipeline_start_valid =
        start_pending || a15_auto_start_valid;
    assign hbm_sequence_error_ready = (a15_state == A15_RECOVER);

    assign command_pending_any =
        descriptor_pending ||
        act_pending ||
        embedding_pending ||
        weight_pending ||
        bias_pending ||
        start_pending ||
        (a15_state != A15_IDLE);

    assign control_command_word =
        apply_wstrb32(32'd0, wdata_reg, wstrb_reg);

    // A16.1 event contract:
    // - end-to-end begins on the same accepted A15 START write that advances
    //   the frozen A15.4 sequencer out of IDLE;
    // - lookup begins only on the first real AXI AR handshake;
    // - lookup ends when the accepted A15.3 sequence reports that slot 3 has
    //   been injected, rather than merely when its R beat arrives;
    // - end-to-end ends on first final-result visibility, before Host POP.
    assign a16_start_accept =
        write_fire &&
        (awaddr_reg == ADDR_A15_CONTROL_STATUS) &&
        (control_command_word[15:0] == A15_CMD_START) &&
        a15_start_ready;
    assign a16_first_lookup_start =
        a16_fpga_end_to_end_active &&
        !a16_hbm_lookup_active &&
        m_axi_gmem_arvalid && m_axi_gmem_arready;
    assign a16_lookup_complete =
        hbm_sequence_done || hbm_sequence_error_valid;
    assign a16_final_result_visible =
        core_result_valid && core_result_last;
    assign a16_terminal_error =
        hbm_sequence_error_valid || core_error_valid;

    assign visible_bottom_count =
        core_busy ? core_bottom_result_count : bottom_count_latched;
    assign visible_interaction_count =
        core_busy ? core_interaction_result_count :
                    interaction_count_latched;

    always_comb begin
        s_axi_control_awready =
            !aw_pending && !s_axi_control_bvalid;
        s_axi_control_wready =
            !w_pending && !s_axi_control_bvalid;
        s_axi_control_arready = !s_axi_control_rvalid;

        s_axi_control_bresp = 2'b00;
        s_axi_control_rresp = 2'b00;

        aw_fire = s_axi_control_awvalid && s_axi_control_awready;
        w_fire = s_axi_control_wvalid && s_axi_control_wready;
        write_fire = aw_pending && w_pending && !s_axi_control_bvalid;
        ar_fire = s_axi_control_arvalid && s_axi_control_arready;
    end

    always_comb begin
        status_word = 32'd0;
        status_word[0] = core_busy;
        status_word[1] = done_latched;
        status_word[2] = core_result_valid;
        status_word[3] = core_result_last;
        status_word[4] = core_error_valid;
        status_word[5] = wrapper_error_latched;
        status_word[6] = command_pending_any;
        status_word[7] = core_start_ready;
        status_word[11:8] = core_phase;
        status_word[15:12] = visible_bottom_count;
        status_word[20:16] = visible_interaction_count;
        status_word[24:21] = core_embedding_loaded_mask;
        status_word[25] = core_descriptor_ready;
        status_word[26] = core_act_ready;
        status_word[27] = core_embedding_ready;
        status_word[28] = core_weight_ready;
        status_word[29] = core_bias_ready;
        status_word[30] = (result_count != 0);
        status_word[31] = core_error_valid || wrapper_error_latched;

        phase_counts_word = 32'd0;
        phase_counts_word[3:0] = core_phase;
        phase_counts_word[11:8] = visible_bottom_count;
        phase_counts_word[20:16] = visible_interaction_count;
        phase_counts_word[27:24] = core_embedding_loaded_mask;

        result_meta_word = 32'd0;
        result_meta_word[0] = core_result_valid;
        result_meta_word[1] = core_result_last;
        result_meta_word[9:4] = core_result_index;
        result_meta_word[23:16] = core_result_tag;

        error_code_word = 32'd0;
        error_code_word[7:0] = core_error_code;
        error_code_word[11:8] = wrapper_error_code;
        error_code_word[16] = core_error_valid;
        error_code_word[17] = wrapper_error_latched;

        config_ready_word = 32'd0;
        config_ready_word[0] = core_descriptor_ready;
        config_ready_word[1] = core_act_ready;
        config_ready_word[2] = core_embedding_ready;
        config_ready_word[3] = core_weight_ready;
        config_ready_word[4] = core_bias_ready;
        config_ready_word[5] = core_start_ready;
        config_ready_word[6] = core_result_valid;
        config_ready_word[7] = core_error_valid;

        a15_status_word = 32'd0;
        a15_status_word[0] = a15_active;
        a15_status_word[1] = hbm_sequence_busy;
        a15_status_word[2] = hbm_all_loaded;
        a15_status_word[3] = core_busy;
        a15_status_word[4] = (a15_state == A15_DONE);
        a15_status_word[5] =
            (a15_state == A15_ERROR) ||
            (a15_state == A15_RECOVER) ||
            hbm_sequence_error_valid;
        a15_status_word[6] = a15_start_ready;
        a15_status_word[7] = core_result_valid;
        a15_status_word[11:8] = core_embedding_loaded_mask;
        a15_status_word[13:12] = hbm_sequence_error_slot;
        a15_status_word[14] = hbm_inject_pending;
        a15_status_word[15] = wrapper_error_latched;
        a15_status_word[23:16] = hbm_sequence_error_index[7:0];
        a15_status_word[24] = load_all_req_ready;
        a15_status_word[25] = core_start_ready;
        a15_status_word[26] = hbm_sequence_done;
        a15_status_word[27] = hbm_inject_done;
        a15_status_word[30:28] = a15_state;
        a15_status_word[31] =
            core_error_valid || wrapper_error_latched ||
            hbm_sequence_error_valid || (a15_state == A15_ERROR);
    end

    // Kernel-level command sequencer. It owns only the A15.4 load-all and
    // automatic pipeline START policy; the accepted A15.3 and A13 state
    // machines continue to own all lookup, injection, and inference details.
    always_ff @(posedge ap_clk) begin
        if (!ap_rst_n) begin
            a15_state <= A15_IDLE;
            a15_table_base_cmd <= '0;
            a15_bottom_descriptor_base_cmd <= '0;
            a15_bottom_layer_count_cmd <= '0;
            a15_top_descriptor_base_cmd <= '0;
            a15_top_layer_count_cmd <= '0;
            a15_bottom_initial_buffer_cmd <= 1'b0;
            a15_top_input_buffer_cmd <= 1'b0;
            a15_interaction_shift_cmd <= '0;
        end else begin
            case (a15_state)
                A15_IDLE: begin
                    if (write_fire &&
                        (awaddr_reg == ADDR_A15_CONTROL_STATUS) &&
                        (control_command_word[15:0] == A15_CMD_START) &&
                        a15_start_ready) begin
                        a15_table_base_cmd <= a15_table_base_stage;
                        a15_bottom_descriptor_base_cmd <=
                            bottom_config_stage[LAYER_INDEX_WIDTH-1:0];
                        a15_bottom_layer_count_cmd <=
                            bottom_config_stage[8 +: LAYER_COUNT_WIDTH];
                        a15_bottom_initial_buffer_cmd <=
                            bottom_config_stage[16];
                        a15_top_descriptor_base_cmd <=
                            top_config_stage[LAYER_INDEX_WIDTH-1:0];
                        a15_top_layer_count_cmd <=
                            top_config_stage[8 +: LAYER_COUNT_WIDTH];
                        a15_top_input_buffer_cmd <= top_config_stage[16];
                        a15_interaction_shift_cmd <=
                            pipeline_config_stage[SHIFT_WIDTH-1:0];
                        a15_state <= A15_LOAD_REQUEST;
                    end
                end

                A15_LOAD_REQUEST: begin
                    if (load_all_req_ready)
                        a15_state <= A15_LOAD_WAIT;
                end

                A15_LOAD_WAIT: begin
                    if (hbm_sequence_error_valid)
                        a15_state <= A15_ERROR;
                    else if (hbm_all_loaded)
                        a15_state <= A15_PIPE_START;
                end

                A15_PIPE_START: begin
                    if (a15_auto_start_valid && core_start_ready)
                        a15_state <= A15_PIPE_WAIT;
                end

                A15_PIPE_WAIT: begin
                    if (core_error_valid)
                        a15_state <= A15_ERROR;
                    else if (core_done)
                        a15_state <= A15_DONE;
                end

                A15_DONE: begin
                    if (write_fire &&
                        (awaddr_reg == ADDR_A15_CONTROL_STATUS) &&
                        (control_command_word[15:0] == A15_CMD_CLEAR))
                        a15_state <= A15_IDLE;
                end

                A15_ERROR: begin
                    if (write_fire &&
                        (awaddr_reg == ADDR_A15_CONTROL_STATUS) &&
                        (control_command_word[15:0] == A15_CMD_CLEAR))
                        a15_state <= A15_RECOVER;
                end

                A15_RECOVER: begin
                    if (!hbm_sequence_error_valid)
                        a15_state <= A15_IDLE;
                end

                default: a15_state <= A15_ERROR;
            endcase
        end
    end

    always_ff @(posedge ap_clk) begin
        if (!ap_rst_n) begin
            aw_pending <= 1'b0;
            awaddr_reg <= '0;
            w_pending <= 1'b0;
            wdata_reg <= '0;
            wstrb_reg <= '0;
            s_axi_control_bvalid <= 1'b0;

            desc_index_stage <= 32'd0;
            desc_word_stage[0] <= 32'd0;
            desc_word_stage[1] <= 32'd0;
            desc_word_stage[2] <= 32'd0;
            act_buffer_stage <= 32'd0;
            act_chunk_stage <= 32'd0;
            act_lane_mask_stage <= 32'd0;
            emb_index_stage <= 32'd0;
            emb_data_stage[0] <= 32'd0;
            emb_data_stage[1] <= 32'd0;
            emb_data_stage[2] <= 32'd0;
            emb_data_stage[3] <= 32'd0;
            weight_address_stage <= 32'd0;
            weight_data_stage <= 32'd0;
            bias_address_stage <= 32'd0;
            bias_data_stage <= 32'd0;
            bottom_config_stage <= 32'd0;
            top_config_stage <= 32'd0;
            pipeline_config_stage <= 32'd0;
            a15_table_base_stage <= '0;

            for (reset_index = 0; reset_index < 8;
                 reset_index = reset_index + 1) begin
                act_data_stage[reset_index] <= 32'd0;
            end

            descriptor_pending <= 1'b0;
            descriptor_index_cmd <= '0;
            descriptor_data_cmd <= '0;
            act_pending <= 1'b0;
            act_buffer_cmd <= 1'b0;
            act_chunk_cmd <= '0;
            act_lane_mask_cmd <= '0;
            act_data_cmd <= '0;
            embedding_pending <= 1'b0;
            embedding_index_cmd <= '0;
            embedding_data_cmd <= '0;
            weight_pending <= 1'b0;
            weight_address_cmd <= '0;
            weight_data_cmd <= '0;
            bias_pending <= 1'b0;
            bias_address_cmd <= '0;
            bias_data_cmd <= '0;
            start_pending <= 1'b0;
            bottom_descriptor_base_cmd <= '0;
            bottom_layer_count_cmd <= '0;
            top_descriptor_base_cmd <= '0;
            top_layer_count_cmd <= '0;
            bottom_initial_buffer_cmd <= 1'b0;
            top_input_buffer_cmd <= 1'b0;
            interaction_shift_cmd <= '0;
            result_ready_pulse <= 1'b0;
            error_ready_pulse <= 1'b0;

            done_latched <= 1'b0;
            result_count <= 32'd0;
            result_data_latched <= '0;
            result_index_latched <= '0;
            result_last_latched <= 1'b0;
            result_tag_latched <= 8'd0;
            bottom_count_latched <= 4'd0;
            interaction_count_latched <= 5'd0;
            wrapper_error_latched <= 1'b0;
            wrapper_error_code <= WRAPPER_ERROR_NONE;
        end else begin
            result_ready_pulse <= 1'b0;
            error_ready_pulse <= 1'b0;

            if (host_embedding_cfg_rejected) begin
                wrapper_error_latched <= 1'b1;
                wrapper_error_code <= WRAPPER_ERROR_EMBEDDING_OWNED;
            end

            if (core_done) begin
                done_latched <= 1'b1;
                bottom_count_latched <= core_bottom_result_count;
                interaction_count_latched <=
                    core_interaction_result_count;
            end

            if (core_result_valid && result_ready_pulse) begin
                result_count <= result_count + 1'b1;
                result_data_latched <= core_result_data;
                result_index_latched <= core_result_index;
                result_last_latched <= core_result_last;
                result_tag_latched <= core_result_tag;
            end

            if (descriptor_pending && core_descriptor_ready)
                descriptor_pending <= 1'b0;
            if (act_pending && core_act_ready)
                act_pending <= 1'b0;
            if (embedding_pending && core_embedding_ready)
                embedding_pending <= 1'b0;
            if (weight_pending && core_weight_ready)
                weight_pending <= 1'b0;
            if (bias_pending && core_bias_ready)
                bias_pending <= 1'b0;
            if (start_pending && core_start_ready)
                start_pending <= 1'b0;

            if (aw_fire) begin
                awaddr_reg <= s_axi_control_awaddr;
                aw_pending <= 1'b1;
            end

            if (w_fire) begin
                wdata_reg <= s_axi_control_wdata;
                wstrb_reg <= s_axi_control_wstrb;
                w_pending <= 1'b1;
            end

            if (write_fire) begin
                aw_pending <= 1'b0;
                w_pending <= 1'b0;
                s_axi_control_bvalid <= 1'b1;

                case (awaddr_reg)
                    ADDR_PIPE_CONTROL_STATUS: begin
                        case (control_command_word[15:0])
                            16'h0000: begin
                            end

                            PIPE_CMD_DESC_COMMIT: begin
                                if (command_pending_any) begin
                                    wrapper_error_latched <= 1'b1;
                                    wrapper_error_code <=
                                        WRAPPER_ERROR_PENDING;
                                end else if (!core_descriptor_ready) begin
                                    wrapper_error_latched <= 1'b1;
                                    wrapper_error_code <=
                                        WRAPPER_ERROR_CORE_NOT_READY;
                                end else begin
                                    descriptor_index_cmd <=
                                        desc_index_stage[
                                            LAYER_INDEX_WIDTH-1:0];
                                    descriptor_data_cmd <= {
                                        desc_word_stage[2],
                                        desc_word_stage[1],
                                        desc_word_stage[0]
                                    };
                                    descriptor_pending <= 1'b1;
                                end
                            end

                            PIPE_CMD_ACT_COMMIT: begin
                                if (command_pending_any) begin
                                    wrapper_error_latched <= 1'b1;
                                    wrapper_error_code <=
                                        WRAPPER_ERROR_PENDING;
                                end else if (!core_act_ready) begin
                                    wrapper_error_latched <= 1'b1;
                                    wrapper_error_code <=
                                        WRAPPER_ERROR_CORE_NOT_READY;
                                end else begin
                                    act_buffer_cmd <= act_buffer_stage[0];
                                    act_chunk_cmd <= act_chunk_stage[
                                        ACT_CHUNK_ADDR_WIDTH-1:0];
                                    act_lane_mask_cmd <=
                                        act_lane_mask_stage[NUM_PE-1:0];
                                    act_data_cmd <= {
                                        act_data_stage[7],
                                        act_data_stage[6],
                                        act_data_stage[5],
                                        act_data_stage[4],
                                        act_data_stage[3],
                                        act_data_stage[2],
                                        act_data_stage[1],
                                        act_data_stage[0]
                                    };
                                    act_pending <= 1'b1;
                                end
                            end

                            PIPE_CMD_EMB_COMMIT: begin
                                if (command_pending_any) begin
                                    wrapper_error_latched <= 1'b1;
                                    wrapper_error_code <=
                                        WRAPPER_ERROR_PENDING;
                                end else if (!core_embedding_ready) begin
                                    wrapper_error_latched <= 1'b1;
                                    wrapper_error_code <=
                                        WRAPPER_ERROR_CORE_NOT_READY;
                                end else begin
                                    embedding_index_cmd <=
                                        emb_index_stage[1:0];
                                    embedding_data_cmd <= {
                                        emb_data_stage[3],
                                        emb_data_stage[2],
                                        emb_data_stage[1],
                                        emb_data_stage[0]
                                    };
                                    embedding_pending <= 1'b1;
                                end
                            end

                            PIPE_CMD_WEIGHT_COMMIT: begin
                                if (command_pending_any) begin
                                    wrapper_error_latched <= 1'b1;
                                    wrapper_error_code <=
                                        WRAPPER_ERROR_PENDING;
                                end else if (!core_weight_ready) begin
                                    wrapper_error_latched <= 1'b1;
                                    wrapper_error_code <=
                                        WRAPPER_ERROR_CORE_NOT_READY;
                                end else begin
                                    weight_address_cmd <=
                                        weight_address_stage;
                                    weight_data_cmd <=
                                        weight_data_stage[
                                            WEIGHT_WIDTH-1:0];
                                    weight_pending <= 1'b1;
                                end
                            end

                            PIPE_CMD_BIAS_COMMIT: begin
                                if (command_pending_any) begin
                                    wrapper_error_latched <= 1'b1;
                                    wrapper_error_code <=
                                        WRAPPER_ERROR_PENDING;
                                end else if (!core_bias_ready) begin
                                    wrapper_error_latched <= 1'b1;
                                    wrapper_error_code <=
                                        WRAPPER_ERROR_CORE_NOT_READY;
                                end else begin
                                    bias_address_cmd <= bias_address_stage;
                                    bias_data_cmd <=
                                        bias_data_stage[BIAS_WIDTH-1:0];
                                    bias_pending <= 1'b1;
                                end
                            end

                            PIPE_CMD_START: begin
                                if (command_pending_any) begin
                                    wrapper_error_latched <= 1'b1;
                                    wrapper_error_code <=
                                        WRAPPER_ERROR_PENDING;
                                end else if (!core_start_ready) begin
                                    wrapper_error_latched <= 1'b1;
                                    wrapper_error_code <=
                                        WRAPPER_ERROR_CORE_NOT_READY;
                                end else begin
                                    bottom_descriptor_base_cmd <=
                                        bottom_config_stage[
                                            LAYER_INDEX_WIDTH-1:0];
                                    bottom_layer_count_cmd <=
                                        bottom_config_stage[
                                            8 +: LAYER_COUNT_WIDTH];
                                    bottom_initial_buffer_cmd <=
                                        bottom_config_stage[16];
                                    top_descriptor_base_cmd <=
                                        top_config_stage[
                                            LAYER_INDEX_WIDTH-1:0];
                                    top_layer_count_cmd <=
                                        top_config_stage[
                                            8 +: LAYER_COUNT_WIDTH];
                                    top_input_buffer_cmd <=
                                        top_config_stage[16];
                                    interaction_shift_cmd <=
                                        pipeline_config_stage[
                                            SHIFT_WIDTH-1:0];
                                    start_pending <= 1'b1;
                                    done_latched <= 1'b0;
                                    result_count <= 32'd0;
                                    bottom_count_latched <= 4'd0;
                                    interaction_count_latched <= 5'd0;
                                end
                            end

                            PIPE_CMD_RESULT_POP: begin
                                if (core_result_valid)
                                    result_ready_pulse <= 1'b1;
                                else begin
                                    wrapper_error_latched <= 1'b1;
                                    wrapper_error_code <=
                                        WRAPPER_ERROR_CORE_NOT_READY;
                                end
                            end

                            PIPE_CMD_ERROR_ACK: begin
                                error_ready_pulse <= 1'b1;
                                wrapper_error_latched <= 1'b0;
                                wrapper_error_code <=
                                    WRAPPER_ERROR_NONE;
                            end

                            PIPE_CMD_CLEAR_DONE: begin
                                done_latched <= 1'b0;
                            end

                            default: begin
                                wrapper_error_latched <= 1'b1;
                                wrapper_error_code <=
                                    WRAPPER_ERROR_BAD_COMMAND;
                            end
                        endcase
                    end

                    ADDR_PIPE_DESC_INDEX:
                        desc_index_stage <= apply_wstrb32(
                            desc_index_stage, wdata_reg, wstrb_reg);
                    ADDR_PIPE_DESC_WORD0:
                        desc_word_stage[0] <= apply_wstrb32(
                            desc_word_stage[0], wdata_reg, wstrb_reg);
                    ADDR_PIPE_DESC_WORD1:
                        desc_word_stage[1] <= apply_wstrb32(
                            desc_word_stage[1], wdata_reg, wstrb_reg);
                    ADDR_PIPE_DESC_WORD2:
                        desc_word_stage[2] <= apply_wstrb32(
                            desc_word_stage[2], wdata_reg, wstrb_reg);
                    ADDR_PIPE_ACT_BUFFER:
                        act_buffer_stage <= apply_wstrb32(
                            act_buffer_stage, wdata_reg, wstrb_reg);
                    ADDR_PIPE_ACT_CHUNK_INDEX:
                        act_chunk_stage <= apply_wstrb32(
                            act_chunk_stage, wdata_reg, wstrb_reg);
                    ADDR_PIPE_ACT_LANE_MASK:
                        act_lane_mask_stage <= apply_wstrb32(
                            act_lane_mask_stage, wdata_reg, wstrb_reg);
                    ADDR_PIPE_ACT_DATA0:
                        act_data_stage[0] <= apply_wstrb32(
                            act_data_stage[0], wdata_reg, wstrb_reg);
                    ADDR_PIPE_ACT_DATA1:
                        act_data_stage[1] <= apply_wstrb32(
                            act_data_stage[1], wdata_reg, wstrb_reg);
                    ADDR_PIPE_ACT_DATA2:
                        act_data_stage[2] <= apply_wstrb32(
                            act_data_stage[2], wdata_reg, wstrb_reg);
                    ADDR_PIPE_ACT_DATA3:
                        act_data_stage[3] <= apply_wstrb32(
                            act_data_stage[3], wdata_reg, wstrb_reg);
                    ADDR_PIPE_ACT_DATA4:
                        act_data_stage[4] <= apply_wstrb32(
                            act_data_stage[4], wdata_reg, wstrb_reg);
                    ADDR_PIPE_ACT_DATA5:
                        act_data_stage[5] <= apply_wstrb32(
                            act_data_stage[5], wdata_reg, wstrb_reg);
                    ADDR_PIPE_ACT_DATA6:
                        act_data_stage[6] <= apply_wstrb32(
                            act_data_stage[6], wdata_reg, wstrb_reg);
                    ADDR_PIPE_ACT_DATA7:
                        act_data_stage[7] <= apply_wstrb32(
                            act_data_stage[7], wdata_reg, wstrb_reg);
                    ADDR_PIPE_EMB_INDEX:
                        emb_index_stage <= apply_wstrb32(
                            emb_index_stage, wdata_reg, wstrb_reg);
                    ADDR_PIPE_EMB_DATA0:
                        emb_data_stage[0] <= apply_wstrb32(
                            emb_data_stage[0], wdata_reg, wstrb_reg);
                    ADDR_PIPE_EMB_DATA1:
                        emb_data_stage[1] <= apply_wstrb32(
                            emb_data_stage[1], wdata_reg, wstrb_reg);
                    ADDR_PIPE_EMB_DATA2:
                        emb_data_stage[2] <= apply_wstrb32(
                            emb_data_stage[2], wdata_reg, wstrb_reg);
                    ADDR_PIPE_EMB_DATA3:
                        emb_data_stage[3] <= apply_wstrb32(
                            emb_data_stage[3], wdata_reg, wstrb_reg);
                    ADDR_PIPE_WEIGHT_ADDRESS:
                        weight_address_stage <= apply_wstrb32(
                            weight_address_stage, wdata_reg, wstrb_reg);
                    ADDR_PIPE_WEIGHT_DATA:
                        weight_data_stage <= apply_wstrb32(
                            weight_data_stage, wdata_reg, wstrb_reg);
                    ADDR_PIPE_BIAS_ADDRESS:
                        bias_address_stage <= apply_wstrb32(
                            bias_address_stage, wdata_reg, wstrb_reg);
                    ADDR_PIPE_BIAS_DATA:
                        bias_data_stage <= apply_wstrb32(
                            bias_data_stage, wdata_reg, wstrb_reg);
                    ADDR_PIPE_BOTTOM_CONFIG:
                        bottom_config_stage <= apply_wstrb32(
                            bottom_config_stage, wdata_reg, wstrb_reg);
                    ADDR_PIPE_TOP_CONFIG:
                        top_config_stage <= apply_wstrb32(
                            top_config_stage, wdata_reg, wstrb_reg);
                    ADDR_PIPELINE_CONFIG:
                        pipeline_config_stage <= apply_wstrb32(
                            pipeline_config_stage, wdata_reg, wstrb_reg);

                    ADDR_A15_CONTROL_STATUS: begin
                        case (control_command_word[15:0])
                            16'h0000: begin
                            end

                            A15_CMD_START: begin
                                if (!a15_start_ready) begin
                                    wrapper_error_latched <= 1'b1;
                                    wrapper_error_code <=
                                        WRAPPER_ERROR_CORE_NOT_READY;
                                end else begin
                                    done_latched <= 1'b0;
                                    result_count <= 32'd0;
                                    bottom_count_latched <= 4'd0;
                                    interaction_count_latched <= 5'd0;
                                end
                            end

                            A15_CMD_CLEAR: begin
                                if ((a15_state != A15_DONE) &&
                                    (a15_state != A15_ERROR)) begin
                                    wrapper_error_latched <= 1'b1;
                                    wrapper_error_code <=
                                        WRAPPER_ERROR_CORE_NOT_READY;
                                end else begin
                                    done_latched <= 1'b0;
                                    wrapper_error_latched <= 1'b0;
                                    wrapper_error_code <=
                                        WRAPPER_ERROR_NONE;
                                end
                            end

                            default: begin
                                wrapper_error_latched <= 1'b1;
                                wrapper_error_code <=
                                    WRAPPER_ERROR_BAD_COMMAND;
                            end
                        endcase
                    end

                    ADDR_A15_TABLE_BASE_LO: begin
                        if (a15_state != A15_IDLE) begin
                            wrapper_error_latched <= 1'b1;
                            wrapper_error_code <= WRAPPER_ERROR_PENDING;
                        end else begin
                            a15_table_base_stage[31:0] <= apply_wstrb32(
                                a15_table_base_stage[31:0],
                                wdata_reg, wstrb_reg);
                        end
                    end

                    ADDR_A15_TABLE_BASE_HI: begin
                        if (a15_state != A15_IDLE) begin
                            wrapper_error_latched <= 1'b1;
                            wrapper_error_code <= WRAPPER_ERROR_PENDING;
                        end else begin
                            a15_table_base_stage[63:32] <= apply_wstrb32(
                                a15_table_base_stage[63:32],
                                wdata_reg, wstrb_reg);
                        end
                    end

                    default: begin
                        wrapper_error_latched <= 1'b1;
                        wrapper_error_code <=
                            WRAPPER_ERROR_BAD_ADDRESS;
                    end
                endcase
            end else if (s_axi_control_bvalid &&
                         s_axi_control_bready) begin
                s_axi_control_bvalid <= 1'b0;
            end
        end
    end

    always_ff @(posedge ap_clk) begin
        if (!ap_rst_n) begin
            s_axi_control_rvalid <= 1'b0;
            s_axi_control_rdata <= 32'd0;
        end else begin
            if (ar_fire) begin
                case (s_axi_control_araddr)
                    ADDR_PIPE_CONTROL_STATUS:
                        s_axi_control_rdata <= status_word;
                    ADDR_PIPE_VERSION:
                        s_axi_control_rdata <= 32'h0002_4E13;
                    ADDR_PIPE_RESULT_COUNT:
                        s_axi_control_rdata <= result_count;
                    ADDR_PIPE_PHASE_COUNTS:
                        s_axi_control_rdata <= phase_counts_word;
                    ADDR_PIPE_DESC_INDEX:
                        s_axi_control_rdata <= desc_index_stage;
                    ADDR_PIPE_DESC_WORD0:
                        s_axi_control_rdata <= desc_word_stage[0];
                    ADDR_PIPE_DESC_WORD1:
                        s_axi_control_rdata <= desc_word_stage[1];
                    ADDR_PIPE_DESC_WORD2:
                        s_axi_control_rdata <= desc_word_stage[2];
                    ADDR_PIPE_ACT_BUFFER:
                        s_axi_control_rdata <= act_buffer_stage;
                    ADDR_PIPE_ACT_CHUNK_INDEX:
                        s_axi_control_rdata <= act_chunk_stage;
                    ADDR_PIPE_ACT_LANE_MASK:
                        s_axi_control_rdata <= act_lane_mask_stage;
                    ADDR_PIPE_ACT_DATA0:
                        s_axi_control_rdata <= act_data_stage[0];
                    ADDR_PIPE_ACT_DATA1:
                        s_axi_control_rdata <= act_data_stage[1];
                    ADDR_PIPE_ACT_DATA2:
                        s_axi_control_rdata <= act_data_stage[2];
                    ADDR_PIPE_ACT_DATA3:
                        s_axi_control_rdata <= act_data_stage[3];
                    ADDR_PIPE_ACT_DATA4:
                        s_axi_control_rdata <= act_data_stage[4];
                    ADDR_PIPE_ACT_DATA5:
                        s_axi_control_rdata <= act_data_stage[5];
                    ADDR_PIPE_ACT_DATA6:
                        s_axi_control_rdata <= act_data_stage[6];
                    ADDR_PIPE_ACT_DATA7:
                        s_axi_control_rdata <= act_data_stage[7];
                    ADDR_PIPE_EMB_INDEX:
                        s_axi_control_rdata <= emb_index_stage;
                    ADDR_PIPE_EMB_DATA0:
                        s_axi_control_rdata <= emb_data_stage[0];
                    ADDR_PIPE_EMB_DATA1:
                        s_axi_control_rdata <= emb_data_stage[1];
                    ADDR_PIPE_EMB_DATA2:
                        s_axi_control_rdata <= emb_data_stage[2];
                    ADDR_PIPE_EMB_DATA3:
                        s_axi_control_rdata <= emb_data_stage[3];
                    ADDR_PIPE_WEIGHT_ADDRESS:
                        s_axi_control_rdata <= weight_address_stage;
                    ADDR_PIPE_WEIGHT_DATA:
                        s_axi_control_rdata <= weight_data_stage;
                    ADDR_PIPE_BIAS_ADDRESS:
                        s_axi_control_rdata <= bias_address_stage;
                    ADDR_PIPE_BIAS_DATA:
                        s_axi_control_rdata <= bias_data_stage;
                    ADDR_PIPE_BOTTOM_CONFIG:
                        s_axi_control_rdata <= bottom_config_stage;
                    ADDR_PIPE_TOP_CONFIG:
                        s_axi_control_rdata <= top_config_stage;
                    ADDR_PIPELINE_CONFIG:
                        s_axi_control_rdata <= pipeline_config_stage;
                    ADDR_PIPE_RESULT_DATA: begin
                        if (core_result_valid)
                            s_axi_control_rdata <= {
                                {16{core_result_data[15]}},
                                core_result_data
                            };
                        else
                            s_axi_control_rdata <= {
                                {16{result_data_latched[15]}},
                                result_data_latched
                            };
                    end
                    ADDR_PIPE_RESULT_INDEX: begin
                        if (core_result_valid)
                            s_axi_control_rdata <= {
                                {(32-OUT_INDEX_WIDTH){1'b0}},
                                core_result_index
                            };
                        else
                            s_axi_control_rdata <= {
                                {(32-OUT_INDEX_WIDTH){1'b0}},
                                result_index_latched
                            };
                    end
                    ADDR_PIPE_RESULT_META: begin
                        if (core_result_valid)
                            s_axi_control_rdata <= result_meta_word;
                        else begin
                            s_axi_control_rdata <= 32'd0;
                            s_axi_control_rdata[1] <=
                                result_last_latched;
                            s_axi_control_rdata[9:4] <=
                                result_index_latched;
                            s_axi_control_rdata[23:16] <=
                                result_tag_latched;
                        end
                    end
                    ADDR_PIPE_EMB_LOADED_MASK:
                        s_axi_control_rdata <= {
                            28'd0, core_embedding_loaded_mask};
                    ADDR_PIPE_ERROR_CODE:
                        s_axi_control_rdata <= error_code_word;
                    ADDR_PIPE_CONFIG_READY:
                        s_axi_control_rdata <= config_ready_word;
                    ADDR_PIPE_BOTTOM_CYCLES:
                        s_axi_control_rdata <= core_bottom_cycle_count;
                    ADDR_PIPE_INTERACTION_CYCLES:
                        s_axi_control_rdata <=
                            core_interaction_cycle_count;
                    ADDR_PIPE_TOP_CYCLES:
                        s_axi_control_rdata <= core_top_cycle_count;
                    ADDR_PIPE_TOTAL_CYCLES:
                        s_axi_control_rdata <= core_total_cycle_count;
                    ADDR_A15_CONTROL_STATUS:
                        s_axi_control_rdata <= a15_status_word;
                    ADDR_A15_TABLE_BASE_LO:
                        s_axi_control_rdata <= a15_table_base_stage[31:0];
                    ADDR_A15_TABLE_BASE_HI:
                        s_axi_control_rdata <= a15_table_base_stage[63:32];
                    ADDR_A16_HBM_LOOKUP_CYCLES:
                        s_axi_control_rdata <=
                            a16_hbm_lookup_cycle_count;
                    ADDR_A16_FPGA_END_TO_END_CYCLES:
                        s_axi_control_rdata <=
                            a16_fpga_end_to_end_cycle_count;
                    default:
                        s_axi_control_rdata <= 32'd0;
                endcase
                s_axi_control_rvalid <= 1'b1;
            end else if (s_axi_control_rvalid &&
                         s_axi_control_rready) begin
                s_axi_control_rvalid <= 1'b0;
            end
        end
    end

    dlrm_saturating_interval_counter_stage2n_a16_v1 #(
        .COUNTER_WIDTH(32)
    ) u_hbm_lookup_cycle_counter (
        .clk(ap_clk),
        .rst(!ap_rst_n),
        .clear(a16_start_accept),
        .start(a16_first_lookup_start),
        .stop(a16_lookup_complete),
        .active(a16_hbm_lookup_active),
        .count(a16_hbm_lookup_cycle_count)
    );

    dlrm_saturating_interval_counter_stage2n_a16_v1 #(
        .COUNTER_WIDTH(32)
    ) u_fpga_end_to_end_cycle_counter (
        .clk(ap_clk),
        .rst(!ap_rst_n),
        .clear(1'b0),
        .start(a16_start_accept),
        .stop(a16_final_result_visible || a16_terminal_error),
        .active(a16_fpga_end_to_end_active),
        .count(a16_fpga_end_to_end_cycle_count)
    );

    dlrm_hbm_pipeline_integration_stage2n_a15_v2 #(
        .MAX_LAYERS(MAX_LAYERS),
        .MAX_IN_DIM(MAX_IN_DIM),
        .MAX_OUT_DIM(MAX_OUT_DIM),
        .NUM_PE(NUM_PE),
        .INPUT_WIDTH(INPUT_WIDTH),
        .WEIGHT_WIDTH(WEIGHT_WIDTH),
        .BIAS_WIDTH(BIAS_WIDTH),
        .ACC_WIDTH(ACC_WIDTH),
        .OUTPUT_WIDTH(OUTPUT_WIDTH),
        .MAX_WEIGHT_VALUES(MAX_WEIGHT_VALUES),
        .MAX_BIAS_VALUES(MAX_BIAS_VALUES),
        .RESULT_FIFO_DEPTH(RESULT_FIFO_DEPTH),
        .HBM_ADDR_WIDTH(C_M_AXI_GMEM_ADDR_WIDTH),
        .HBM_DATA_WIDTH(C_M_AXI_GMEM_DATA_WIDTH),
        .HBM_ID_WIDTH(C_M_AXI_GMEM_ID_WIDTH),
        .SLOT0_LOOKUP_INDEX(37),
        .SLOT1_LOOKUP_INDEX(38),
        .SLOT2_LOOKUP_INDEX(39),
        .SLOT3_LOOKUP_INDEX(40)
    ) u_all_hbm_pipeline (
        .clk(ap_clk),
        .rst(!ap_rst_n),
        .descriptor_cfg_valid(descriptor_pending),
        .descriptor_cfg_ready(core_descriptor_ready),
        .descriptor_cfg_index(descriptor_index_cmd),
        .descriptor_cfg_data(descriptor_data_cmd),
        .act_load_valid(act_pending),
        .act_load_ready(core_act_ready),
        .act_load_buffer_select(act_buffer_cmd),
        .act_load_chunk_index(act_chunk_cmd),
        .act_load_lane_mask(act_lane_mask_cmd),
        .act_load_data(act_data_cmd),
        .host_embedding_cfg_valid(embedding_pending),
        .host_embedding_cfg_ready(core_embedding_ready),
        .host_embedding_cfg_index(embedding_index_cmd),
        .host_embedding_cfg_data(embedding_data_cmd),
        .host_embedding_cfg_rejected(host_embedding_cfg_rejected),
        .embedding_loaded_mask(core_embedding_loaded_mask),
        .weight_cfg_valid(weight_pending),
        .weight_cfg_ready(core_weight_ready),
        .weight_cfg_address(weight_address_cmd),
        .weight_cfg_data(weight_data_cmd),
        .bias_cfg_valid(bias_pending),
        .bias_cfg_ready(core_bias_ready),
        .bias_cfg_address(bias_address_cmd),
        .bias_cfg_data(bias_data_cmd),
        .pipeline_start_valid(core_pipeline_start_valid),
        .pipeline_start_ready(core_start_ready),
        .bottom_descriptor_base(
            a15_auto_start_valid ? a15_bottom_descriptor_base_cmd :
                                   bottom_descriptor_base_cmd),
        .bottom_layer_count(
            a15_auto_start_valid ? a15_bottom_layer_count_cmd :
                                   bottom_layer_count_cmd),
        .top_descriptor_base(
            a15_auto_start_valid ? a15_top_descriptor_base_cmd :
                                   top_descriptor_base_cmd),
        .top_layer_count(
            a15_auto_start_valid ? a15_top_layer_count_cmd :
                                   top_layer_count_cmd),
        .bottom_initial_buffer_select(
            a15_auto_start_valid ? a15_bottom_initial_buffer_cmd :
                                   bottom_initial_buffer_cmd),
        .top_input_buffer_select(
            a15_auto_start_valid ? a15_top_input_buffer_cmd :
                                   top_input_buffer_cmd),
        .interaction_shift(
            a15_auto_start_valid ? a15_interaction_shift_cmd :
                                   interaction_shift_cmd),
        .result_valid(core_result_valid),
        .result_ready(result_ready_pulse),
        .result_data(core_result_data),
        .result_index(core_result_index),
        .result_last(core_result_last),
        .result_tag(core_result_tag),
        .busy(core_busy),
        .done(core_done),
        .phase(core_phase),
        .bottom_result_count(core_bottom_result_count),
        .interaction_result_count(core_interaction_result_count),
        .bottom_cycle_count(core_bottom_cycle_count),
        .interaction_cycle_count(core_interaction_cycle_count),
        .top_cycle_count(core_top_cycle_count),
        .total_cycle_count(core_total_cycle_count),
        .pipeline_error_valid(core_error_valid),
        .pipeline_error_ready(error_ready_pulse),
        .pipeline_error_code(core_error_code),
        .table_base_addr(a15_table_base_cmd),
        .load_all_req_valid(a15_state == A15_LOAD_REQUEST),
        .load_all_req_ready(load_all_req_ready),
        .hbm_sequence_busy(hbm_sequence_busy),
        .hbm_all_loaded(hbm_all_loaded),
        .hbm_sequence_done(hbm_sequence_done),
        .hbm_inject_pending(hbm_inject_pending),
        .hbm_inject_slot(hbm_inject_slot),
        .hbm_inject_data(hbm_inject_data),
        .hbm_inject_done(hbm_inject_done),
        .hbm_sequence_error_valid(hbm_sequence_error_valid),
        .hbm_sequence_error_ready(hbm_sequence_error_ready),
        .hbm_sequence_error_slot(hbm_sequence_error_slot),
        .hbm_sequence_error_index(hbm_sequence_error_index),
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
        if (C_S_AXI_CONTROL_DATA_WIDTH != 32)
            $error("A16.1 pipeline adapter requires a 32-bit AXI-Lite bus");
        if (NUM_PE != 16)
            $error("A16.1 pipeline adapter requires NUM_PE=16");
        if (INPUT_WIDTH != 16 || OUTPUT_WIDTH != 16)
            $error("A16.1 pipeline adapter requires signed INT16 activations");
        if (C_M_AXI_GMEM_ADDR_WIDTH != 64)
            $error("A16.1 m_axi_gmem address width must be 64 bits");
        if (C_M_AXI_GMEM_DATA_WIDTH != 128)
            $error("A16.1 m_axi_gmem data width must be 128 bits");
    end

endmodule
