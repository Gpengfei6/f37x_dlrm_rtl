`timescale 1ns/1ps

// Stage 2N-A13 v1 integration top with hardware cycle counters.
//
// The verified Stage 2N-A2 kernel remains unchanged at 0x000-0x17F:
//   0x000-0x0FF legacy MLP window
//   0x100-0x13F standalone interaction window
//
// The A10 v2 register map remains unchanged at 0x180-0x217. A13 extends the
// pipeline window through 0x227 with four read-only cycle counters. One START
// command still launches Bottom MLP -> Interaction -> Top MLP.
module dlrm_f37x_rtl_kernel_stage2n_a13_v1 #(
    parameter integer C_S_AXI_CONTROL_ADDR_WIDTH = 12,
    parameter integer C_S_AXI_CONTROL_DATA_WIDTH = 32
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
    input  logic                                  s_axi_control_rready
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

    dlrm_internal_pipeline_axi_lite_adapter_stage2n_a13_v1
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
        .s_axi_control_rready(pipe_rready)
    );

endmodule
