`timescale 1ns/1ps

module tb_dlrm_f37x_rtl_kernel_stage2n_a17_v1;

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
    localparam logic [ADDR_WIDTH-1:0]
        ADDR_A16_HBM_LOOKUP_CYCLES = 12'h30C;
    localparam logic [ADDR_WIDTH-1:0]
        ADDR_A16_FPGA_END_TO_END_CYCLES = 12'h310;
    localparam logic [ADDR_WIDTH-1:0]
        ADDR_A17_RESERVED = 12'h314;
    localparam logic [ADDR_WIDTH-1:0]
        ADDR_A17_TABLE_BASE1_LO = 12'h318;
    localparam logic [ADDR_WIDTH-1:0]
        ADDR_A17_TABLE_BASE1_HI = 12'h31C;
    localparam logic [ADDR_WIDTH-1:0]
        ADDR_A17_TABLE_BASE2_LO = 12'h320;
    localparam logic [ADDR_WIDTH-1:0]
        ADDR_A17_TABLE_BASE2_HI = 12'h324;
    localparam logic [ADDR_WIDTH-1:0]
        ADDR_A17_TABLE_BASE3_LO = 12'h328;
    localparam logic [ADDR_WIDTH-1:0]
        ADDR_A17_TABLE_BASE3_HI = 12'h32C;

    localparam logic [63:0] TABLE_BASE0 = 64'h0000_0001_2345_6000;
    localparam logic [63:0] TABLE_BASE1 = 64'h0000_0002_3456_7000;
    localparam logic [63:0] TABLE_BASE2 = 64'h0000_0003_4567_8000;
    localparam logic [63:0] TABLE_BASE3 = 64'h0000_0004_5678_9000;
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

    logic [3:0] m_axi_gmem_awid;
    logic [3:0][63:0] m_axi_gmem_awaddr;
    logic [3:0][7:0] m_axi_gmem_awlen;
    logic [3:0][2:0] m_axi_gmem_awsize;
    logic [3:0][1:0] m_axi_gmem_awburst;
    logic [3:0] m_axi_gmem_awlock;
    logic [3:0][3:0] m_axi_gmem_awcache;
    logic [3:0][2:0] m_axi_gmem_awprot;
    logic [3:0][3:0] m_axi_gmem_awqos;
    logic [3:0] m_axi_gmem_awvalid;
    logic [3:0] m_axi_gmem_awready;
    logic [3:0][127:0] m_axi_gmem_wdata;
    logic [3:0][15:0] m_axi_gmem_wstrb;
    logic [3:0] m_axi_gmem_wlast;
    logic [3:0] m_axi_gmem_wvalid;
    logic [3:0] m_axi_gmem_wready;
    logic [3:0] m_axi_gmem_bid;
    logic [3:0][1:0] m_axi_gmem_bresp;
    logic [3:0] m_axi_gmem_bvalid;
    logic [3:0] m_axi_gmem_bready;
    logic [3:0] m_axi_gmem_arid;
    logic [3:0][63:0] m_axi_gmem_araddr;
    logic [3:0][7:0] m_axi_gmem_arlen;
    logic [3:0][2:0] m_axi_gmem_arsize;
    logic [3:0][1:0] m_axi_gmem_arburst;
    logic [3:0] m_axi_gmem_arlock;
    logic [3:0][3:0] m_axi_gmem_arcache;
    logic [3:0][2:0] m_axi_gmem_arprot;
    logic [3:0][3:0] m_axi_gmem_arqos;
    logic [3:0] m_axi_gmem_arvalid;
    logic [3:0] m_axi_gmem_arready;
    logic [3:0] m_axi_gmem_rid;
    logic [3:0][127:0] m_axi_gmem_rdata;
    logic [3:0][1:0] m_axi_gmem_rresp;
    logic [3:0] m_axi_gmem_rlast;
    logic [3:0] m_axi_gmem_rvalid;
    logic [3:0] m_axi_gmem_rready;

    integer cycle_count;
    integer wait_attempts;
    integer address_index;
    integer run_index;
    integer hold_index;
    integer port;
    integer lane;
    integer step;
    integer ar_handshake_count;
    integer r_handshake_count;
    integer first_r_handshake_ar_count;
    integer response_order_count;
    integer response_order_observed [0:3];
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
    logic [31:0] hbm_lookup_cycles_value;
    logic [31:0] fpga_end_to_end_cycles_value;
    logic [31:0] held_hbm_lookup_cycles;
    logic [31:0] held_fpga_end_to_end_cycles;
    logic [31:0] first_hbm_lookup_cycles;
    logic [31:0] first_fpga_end_to_end_cycles;
    logic [31:0] pipeline_overhead_cycles;
    logic [31:0] stage_cycle_sum;
    logic [31:0] a15_status_value;
    logic [31:0] error_code_value;
    logic [31:0] reserved_value;
    logic [63:0] held_araddr [0:3];

    logic saturation_clear;
    logic saturation_start;
    logic saturation_stop;
    logic saturation_active;
    logic [3:0] saturation_count;

    dlrm_f37x_rtl_kernel_stage2n_a17_v1 dut (
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
        .m_axi_gmem0_awid(m_axi_gmem_awid[0]),
        .m_axi_gmem0_awaddr(m_axi_gmem_awaddr[0]),
        .m_axi_gmem0_awlen(m_axi_gmem_awlen[0]),
        .m_axi_gmem0_awsize(m_axi_gmem_awsize[0]),
        .m_axi_gmem0_awburst(m_axi_gmem_awburst[0]),
        .m_axi_gmem0_awlock(m_axi_gmem_awlock[0]),
        .m_axi_gmem0_awcache(m_axi_gmem_awcache[0]),
        .m_axi_gmem0_awprot(m_axi_gmem_awprot[0]),
        .m_axi_gmem0_awqos(m_axi_gmem_awqos[0]),
        .m_axi_gmem0_awvalid(m_axi_gmem_awvalid[0]),
        .m_axi_gmem0_awready(m_axi_gmem_awready[0]),
        .m_axi_gmem0_wdata(m_axi_gmem_wdata[0]),
        .m_axi_gmem0_wstrb(m_axi_gmem_wstrb[0]),
        .m_axi_gmem0_wlast(m_axi_gmem_wlast[0]),
        .m_axi_gmem0_wvalid(m_axi_gmem_wvalid[0]),
        .m_axi_gmem0_wready(m_axi_gmem_wready[0]),
        .m_axi_gmem0_bid(m_axi_gmem_bid[0]),
        .m_axi_gmem0_bresp(m_axi_gmem_bresp[0]),
        .m_axi_gmem0_bvalid(m_axi_gmem_bvalid[0]),
        .m_axi_gmem0_bready(m_axi_gmem_bready[0]),
        .m_axi_gmem0_arid(m_axi_gmem_arid[0]),
        .m_axi_gmem0_araddr(m_axi_gmem_araddr[0]),
        .m_axi_gmem0_arlen(m_axi_gmem_arlen[0]),
        .m_axi_gmem0_arsize(m_axi_gmem_arsize[0]),
        .m_axi_gmem0_arburst(m_axi_gmem_arburst[0]),
        .m_axi_gmem0_arlock(m_axi_gmem_arlock[0]),
        .m_axi_gmem0_arcache(m_axi_gmem_arcache[0]),
        .m_axi_gmem0_arprot(m_axi_gmem_arprot[0]),
        .m_axi_gmem0_arqos(m_axi_gmem_arqos[0]),
        .m_axi_gmem0_arvalid(m_axi_gmem_arvalid[0]),
        .m_axi_gmem0_arready(m_axi_gmem_arready[0]),
        .m_axi_gmem0_rid(m_axi_gmem_rid[0]),
        .m_axi_gmem0_rdata(m_axi_gmem_rdata[0]),
        .m_axi_gmem0_rresp(m_axi_gmem_rresp[0]),
        .m_axi_gmem0_rlast(m_axi_gmem_rlast[0]),
        .m_axi_gmem0_rvalid(m_axi_gmem_rvalid[0]),
        .m_axi_gmem0_rready(m_axi_gmem_rready[0]),
        .m_axi_gmem1_awid(m_axi_gmem_awid[1]),
        .m_axi_gmem1_awaddr(m_axi_gmem_awaddr[1]),
        .m_axi_gmem1_awlen(m_axi_gmem_awlen[1]),
        .m_axi_gmem1_awsize(m_axi_gmem_awsize[1]),
        .m_axi_gmem1_awburst(m_axi_gmem_awburst[1]),
        .m_axi_gmem1_awlock(m_axi_gmem_awlock[1]),
        .m_axi_gmem1_awcache(m_axi_gmem_awcache[1]),
        .m_axi_gmem1_awprot(m_axi_gmem_awprot[1]),
        .m_axi_gmem1_awqos(m_axi_gmem_awqos[1]),
        .m_axi_gmem1_awvalid(m_axi_gmem_awvalid[1]),
        .m_axi_gmem1_awready(m_axi_gmem_awready[1]),
        .m_axi_gmem1_wdata(m_axi_gmem_wdata[1]),
        .m_axi_gmem1_wstrb(m_axi_gmem_wstrb[1]),
        .m_axi_gmem1_wlast(m_axi_gmem_wlast[1]),
        .m_axi_gmem1_wvalid(m_axi_gmem_wvalid[1]),
        .m_axi_gmem1_wready(m_axi_gmem_wready[1]),
        .m_axi_gmem1_bid(m_axi_gmem_bid[1]),
        .m_axi_gmem1_bresp(m_axi_gmem_bresp[1]),
        .m_axi_gmem1_bvalid(m_axi_gmem_bvalid[1]),
        .m_axi_gmem1_bready(m_axi_gmem_bready[1]),
        .m_axi_gmem1_arid(m_axi_gmem_arid[1]),
        .m_axi_gmem1_araddr(m_axi_gmem_araddr[1]),
        .m_axi_gmem1_arlen(m_axi_gmem_arlen[1]),
        .m_axi_gmem1_arsize(m_axi_gmem_arsize[1]),
        .m_axi_gmem1_arburst(m_axi_gmem_arburst[1]),
        .m_axi_gmem1_arlock(m_axi_gmem_arlock[1]),
        .m_axi_gmem1_arcache(m_axi_gmem_arcache[1]),
        .m_axi_gmem1_arprot(m_axi_gmem_arprot[1]),
        .m_axi_gmem1_arqos(m_axi_gmem_arqos[1]),
        .m_axi_gmem1_arvalid(m_axi_gmem_arvalid[1]),
        .m_axi_gmem1_arready(m_axi_gmem_arready[1]),
        .m_axi_gmem1_rid(m_axi_gmem_rid[1]),
        .m_axi_gmem1_rdata(m_axi_gmem_rdata[1]),
        .m_axi_gmem1_rresp(m_axi_gmem_rresp[1]),
        .m_axi_gmem1_rlast(m_axi_gmem_rlast[1]),
        .m_axi_gmem1_rvalid(m_axi_gmem_rvalid[1]),
        .m_axi_gmem1_rready(m_axi_gmem_rready[1]),
        .m_axi_gmem2_awid(m_axi_gmem_awid[2]),
        .m_axi_gmem2_awaddr(m_axi_gmem_awaddr[2]),
        .m_axi_gmem2_awlen(m_axi_gmem_awlen[2]),
        .m_axi_gmem2_awsize(m_axi_gmem_awsize[2]),
        .m_axi_gmem2_awburst(m_axi_gmem_awburst[2]),
        .m_axi_gmem2_awlock(m_axi_gmem_awlock[2]),
        .m_axi_gmem2_awcache(m_axi_gmem_awcache[2]),
        .m_axi_gmem2_awprot(m_axi_gmem_awprot[2]),
        .m_axi_gmem2_awqos(m_axi_gmem_awqos[2]),
        .m_axi_gmem2_awvalid(m_axi_gmem_awvalid[2]),
        .m_axi_gmem2_awready(m_axi_gmem_awready[2]),
        .m_axi_gmem2_wdata(m_axi_gmem_wdata[2]),
        .m_axi_gmem2_wstrb(m_axi_gmem_wstrb[2]),
        .m_axi_gmem2_wlast(m_axi_gmem_wlast[2]),
        .m_axi_gmem2_wvalid(m_axi_gmem_wvalid[2]),
        .m_axi_gmem2_wready(m_axi_gmem_wready[2]),
        .m_axi_gmem2_bid(m_axi_gmem_bid[2]),
        .m_axi_gmem2_bresp(m_axi_gmem_bresp[2]),
        .m_axi_gmem2_bvalid(m_axi_gmem_bvalid[2]),
        .m_axi_gmem2_bready(m_axi_gmem_bready[2]),
        .m_axi_gmem2_arid(m_axi_gmem_arid[2]),
        .m_axi_gmem2_araddr(m_axi_gmem_araddr[2]),
        .m_axi_gmem2_arlen(m_axi_gmem_arlen[2]),
        .m_axi_gmem2_arsize(m_axi_gmem_arsize[2]),
        .m_axi_gmem2_arburst(m_axi_gmem_arburst[2]),
        .m_axi_gmem2_arlock(m_axi_gmem_arlock[2]),
        .m_axi_gmem2_arcache(m_axi_gmem_arcache[2]),
        .m_axi_gmem2_arprot(m_axi_gmem_arprot[2]),
        .m_axi_gmem2_arqos(m_axi_gmem_arqos[2]),
        .m_axi_gmem2_arvalid(m_axi_gmem_arvalid[2]),
        .m_axi_gmem2_arready(m_axi_gmem_arready[2]),
        .m_axi_gmem2_rid(m_axi_gmem_rid[2]),
        .m_axi_gmem2_rdata(m_axi_gmem_rdata[2]),
        .m_axi_gmem2_rresp(m_axi_gmem_rresp[2]),
        .m_axi_gmem2_rlast(m_axi_gmem_rlast[2]),
        .m_axi_gmem2_rvalid(m_axi_gmem_rvalid[2]),
        .m_axi_gmem2_rready(m_axi_gmem_rready[2]),
        .m_axi_gmem3_awid(m_axi_gmem_awid[3]),
        .m_axi_gmem3_awaddr(m_axi_gmem_awaddr[3]),
        .m_axi_gmem3_awlen(m_axi_gmem_awlen[3]),
        .m_axi_gmem3_awsize(m_axi_gmem_awsize[3]),
        .m_axi_gmem3_awburst(m_axi_gmem_awburst[3]),
        .m_axi_gmem3_awlock(m_axi_gmem_awlock[3]),
        .m_axi_gmem3_awcache(m_axi_gmem_awcache[3]),
        .m_axi_gmem3_awprot(m_axi_gmem_awprot[3]),
        .m_axi_gmem3_awqos(m_axi_gmem_awqos[3]),
        .m_axi_gmem3_awvalid(m_axi_gmem_awvalid[3]),
        .m_axi_gmem3_awready(m_axi_gmem_awready[3]),
        .m_axi_gmem3_wdata(m_axi_gmem_wdata[3]),
        .m_axi_gmem3_wstrb(m_axi_gmem_wstrb[3]),
        .m_axi_gmem3_wlast(m_axi_gmem_wlast[3]),
        .m_axi_gmem3_wvalid(m_axi_gmem_wvalid[3]),
        .m_axi_gmem3_wready(m_axi_gmem_wready[3]),
        .m_axi_gmem3_bid(m_axi_gmem_bid[3]),
        .m_axi_gmem3_bresp(m_axi_gmem_bresp[3]),
        .m_axi_gmem3_bvalid(m_axi_gmem_bvalid[3]),
        .m_axi_gmem3_bready(m_axi_gmem_bready[3]),
        .m_axi_gmem3_arid(m_axi_gmem_arid[3]),
        .m_axi_gmem3_araddr(m_axi_gmem_araddr[3]),
        .m_axi_gmem3_arlen(m_axi_gmem_arlen[3]),
        .m_axi_gmem3_arsize(m_axi_gmem_arsize[3]),
        .m_axi_gmem3_arburst(m_axi_gmem_arburst[3]),
        .m_axi_gmem3_arlock(m_axi_gmem_arlock[3]),
        .m_axi_gmem3_arcache(m_axi_gmem_arcache[3]),
        .m_axi_gmem3_arprot(m_axi_gmem_arprot[3]),
        .m_axi_gmem3_arqos(m_axi_gmem_arqos[3]),
        .m_axi_gmem3_arvalid(m_axi_gmem_arvalid[3]),
        .m_axi_gmem3_arready(m_axi_gmem_arready[3]),
        .m_axi_gmem3_rid(m_axi_gmem_rid[3]),
        .m_axi_gmem3_rdata(m_axi_gmem_rdata[3]),
        .m_axi_gmem3_rresp(m_axi_gmem_rresp[3]),
        .m_axi_gmem3_rlast(m_axi_gmem_rlast[3]),
        .m_axi_gmem3_rvalid(m_axi_gmem_rvalid[3]),
        .m_axi_gmem3_rready(m_axi_gmem_rready[3])
    );

    dlrm_saturating_interval_counter_stage2n_a16_v1 #(
        .COUNTER_WIDTH(4)
    ) saturation_probe (
        .clk(ap_clk),
        .rst(!ap_rst_n),
        .clear(saturation_clear),
        .start(saturation_start),
        .stop(saturation_stop),
        .active(saturation_active),
        .count(saturation_count)
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

    function automatic logic [127:0] canonical_row(input integer row);
        logic [127:0] packed_data;
        logic signed [15:0] lane_value;
        integer lane_i;
        begin
            packed_data = 128'd0;
            for (lane_i = 0; lane_i < 8; lane_i = lane_i + 1) begin
                lane_value = row * 8 + lane_i - 256;
                packed_data[lane_i*16 +: 16] = lane_value;
            end
            canonical_row = packed_data;
        end
    endfunction

    function automatic integer slot_row(input integer slot);
        begin
            slot_row = 37 + slot;
        end
    endfunction

    function automatic logic [63:0] table_base(input integer slot);
        begin
            case (slot)
                0: table_base = TABLE_BASE0;
                1: table_base = TABLE_BASE1;
                2: table_base = TABLE_BASE2;
                3: table_base = TABLE_BASE3;
                default: table_base = 64'hx;
            endcase
        end
    endfunction

    function automatic logic [ADDR_WIDTH-1:0] base_low_address(
        input integer slot
    );
        begin
            case (slot)
                0: base_low_address = ADDR_A15_TABLE_BASE_LO;
                1: base_low_address = ADDR_A17_TABLE_BASE1_LO;
                2: base_low_address = ADDR_A17_TABLE_BASE2_LO;
                3: base_low_address = ADDR_A17_TABLE_BASE3_LO;
                default: base_low_address = {ADDR_WIDTH{1'bx}};
            endcase
        end
    endfunction

    function automatic logic [ADDR_WIDTH-1:0] base_high_address(
        input integer slot
    );
        begin
            case (slot)
                0: base_high_address = ADDR_A15_TABLE_BASE_HI;
                1: base_high_address = ADDR_A17_TABLE_BASE1_HI;
                2: base_high_address = ADDR_A17_TABLE_BASE2_HI;
                3: base_high_address = ADDR_A17_TABLE_BASE3_HI;
                default: base_high_address = {ADDR_WIDTH{1'bx}};
            endcase
        end
    endfunction

    function automatic integer reorder_port(input integer step_i);
        begin
            case (step_i)
                0: reorder_port = 2;
                1: reorder_port = 0;
                2: reorder_port = 3;
                3: reorder_port = 1;
                default: reorder_port = -1;
            endcase
        end
    endfunction

    task automatic axi_write_split(
        input logic [ADDR_WIDTH-1:0] address,
        input logic [31:0] data,
        input logic [3:0] strobe,
        input logic w_before_aw,
        input integer channel_gap
    );
        begin
            if (w_before_aw) begin
                @(negedge ap_clk);
                s_axi_control_wdata = data;
                s_axi_control_wstrb = strobe;
                s_axi_control_wvalid = 1'b1;
                while (s_axi_control_wready !== 1'b1)
                    @(posedge ap_clk);
                @(negedge ap_clk);
                s_axi_control_wvalid = 1'b0;
                repeat (channel_gap) @(posedge ap_clk);
                @(negedge ap_clk);
                s_axi_control_awaddr = address;
                s_axi_control_awvalid = 1'b1;
                while (s_axi_control_awready !== 1'b1)
                    @(posedge ap_clk);
                @(negedge ap_clk);
                s_axi_control_awvalid = 1'b0;
            end else begin
                @(negedge ap_clk);
                s_axi_control_awaddr = address;
                s_axi_control_awvalid = 1'b1;
                while (s_axi_control_awready !== 1'b1)
                    @(posedge ap_clk);
                @(negedge ap_clk);
                s_axi_control_awvalid = 1'b0;
                repeat (channel_gap) @(posedge ap_clk);
                @(negedge ap_clk);
                s_axi_control_wdata = data;
                s_axi_control_wstrb = strobe;
                s_axi_control_wvalid = 1'b1;
                while (s_axi_control_wready !== 1'b1)
                    @(posedge ap_clk);
                @(negedge ap_clk);
                s_axi_control_wvalid = 1'b0;
            end
            s_axi_control_bready = 1'b1;

            while (s_axi_control_bvalid !== 1'b1)
                @(posedge ap_clk);
            if (s_axi_control_bresp !== 2'b00)
                $fatal(1, "AXI write response error address=0x%0h",
                       address);

            @(negedge ap_clk);
            s_axi_control_bready = 1'b0;
        end
    endtask

    task automatic axi_write(
        input logic [ADDR_WIDTH-1:0] address,
        input logic [31:0] data
    );
        begin
            axi_write_split(address, data, 4'hF, 1'b0, 0);
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
            while (s_axi_control_arready !== 1'b1)
                @(posedge ap_clk);
            @(negedge ap_clk);
            s_axi_control_arvalid = 1'b0;
            s_axi_control_rready = 1'b1;

            while (s_axi_control_rvalid !== 1'b1)
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
            m_axi_gmem_awready = 4'h0;
            m_axi_gmem_wready = 4'h0;
            m_axi_gmem_bid = 4'h0;
            m_axi_gmem_bresp = '0;
            m_axi_gmem_bvalid = 4'h0;
            m_axi_gmem_arready = 4'h0;
            m_axi_gmem_rid = 4'h0;
            m_axi_gmem_rdata = '0;
            m_axi_gmem_rresp = '0;
            m_axi_gmem_rlast = 4'h0;
            m_axi_gmem_rvalid = 4'h0;
            saturation_clear = 1'b0;
            saturation_start = 1'b0;
            saturation_stop = 1'b0;
            ar_handshake_count = 0;
            r_handshake_count = 0;
            first_r_handshake_ar_count = -1;
            response_order_count = 0;
            repeat (8) @(posedge ap_clk);
            ap_rst_n = 1'b1;
            repeat (4) @(posedge ap_clk);
        end
    endtask

    task automatic check_table_bases;
        logic [31:0] readback;
        logic [63:0] expected_base;
        integer slot;
        begin
            for (slot = 0; slot < 4; slot = slot + 1) begin
                expected_base = table_base(slot);
                axi_read(base_low_address(slot), readback);
                if (readback !== expected_base[31:0])
                    $fatal(1, "TABLE_BASE%0d_LO readback mismatch", slot);
                axi_read(base_high_address(slot), readback);
                if (readback !== expected_base[63:32])
                    $fatal(1, "TABLE_BASE%0d_HI readback mismatch", slot);
            end
        end
    endtask

    task automatic program_a17_table_bases;
        logic [63:0] expected_base;
        logic w_before_aw;
        integer slot;
        begin
            for (slot = 0; slot < 4; slot = slot + 1) begin
                expected_base = table_base(slot);
                w_before_aw = ((slot % 2) == 1);
                axi_write_split(base_low_address(slot),
                                expected_base[31:0], 4'b0101,
                                w_before_aw, slot + 1);
                axi_write_split(base_low_address(slot),
                                expected_base[31:0], 4'b1010,
                                !w_before_aw, 4 - slot);
                axi_write_split(base_high_address(slot),
                                expected_base[63:32], 4'b0011,
                                !w_before_aw, slot + 1);
                axi_write_split(base_high_address(slot),
                                expected_base[63:32], 4'b1100,
                                w_before_aw, 4 - slot);
            end
            check_table_bases();
        end
    endtask

    task automatic wait_a15_error;
        begin
            wait_attempts = 0;
            axi_read(ADDR_A15_CONTROL_STATUS, a15_status_value);
            while (a15_status_value[5] !== 1'b1) begin
                wait_attempts = wait_attempts + 1;
                if (wait_attempts > 2000)
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
            while (a15_status_value[6] !== 1'b1) begin
                wait_attempts = wait_attempts + 1;
                if (wait_attempts > 2000)
                    $fatal(1, "A15 idle timeout status=0x%08x",
                           a15_status_value);
                axi_read(ADDR_A15_CONTROL_STATUS, a15_status_value);
            end
        end
    endtask

    task automatic check_ar_payload(input integer slot);
        logic [63:0] expected_address;
        begin
            expected_address = table_base(slot) + (slot_row(slot) << 4);
            if (m_axi_gmem_arvalid[slot] !== 1'b1)
                $fatal(1, "ARVALID missing slot=%0d", slot);
            if (m_axi_gmem_araddr[slot] !== expected_address)
                $fatal(1,
                       "ARADDR mismatch slot=%0d actual=0x%016h expected=0x%016h",
                       slot, m_axi_gmem_araddr[slot], expected_address);
            if ((m_axi_gmem_arlen[slot] !== 8'd0) ||
                (m_axi_gmem_arsize[slot] !== 3'd4) ||
                (m_axi_gmem_arburst[slot] !== 2'b01) ||
                (m_axi_gmem_arid[slot] !== 1'b0) ||
                (m_axi_gmem_arlock[slot] !== 1'b0) ||
                (m_axi_gmem_arcache[slot] !== 4'b0011) ||
                (m_axi_gmem_arprot[slot] !== 3'b000) ||
                (m_axi_gmem_arqos[slot] !== 4'b0000))
                $fatal(1, "AXI AR control mismatch slot=%0d", slot);
        end
    endtask

    task automatic wait_arvalid_mask(input logic [3:0] mask);
        begin
            wait_attempts = 0;
            while ((m_axi_gmem_arvalid & mask) !== mask) begin
                wait_attempts = wait_attempts + 1;
                if (wait_attempts > 2000)
                    $fatal(1, "ARVALID mask timeout actual=%b expected=%b",
                           m_axi_gmem_arvalid, mask);
                @(posedge ap_clk);
            end
        end
    endtask

    task automatic handshake_ar(input integer slot);
        begin
            check_ar_payload(slot);
            held_araddr[slot] = m_axi_gmem_araddr[slot];
            @(negedge ap_clk);
            m_axi_gmem_arready[slot] = 1'b1;
            @(posedge ap_clk);
            if ((m_axi_gmem_arvalid[slot] !== 1'b1) ||
                (m_axi_gmem_arready[slot] !== 1'b1))
                $fatal(1, "AR handshake missing slot=%0d", slot);
            ar_handshake_count = ar_handshake_count + 1;
            @(negedge ap_clk);
            m_axi_gmem_arready[slot] = 1'b0;
        end
    endtask

    task automatic drive_r(input integer slot, input logic inject_error);
        logic [127:0] row_data;
        logic [127:0] held_data;
        integer lane_i;
        integer row;
        begin
            row = slot_row(slot);
            row_data = canonical_row(row);
            @(negedge ap_clk);
            m_axi_gmem_rdata[slot] = row_data;
            m_axi_gmem_rresp[slot] = inject_error ? 2'b10 : 2'b00;
            m_axi_gmem_rlast[slot] = 1'b1;
            m_axi_gmem_rid[slot] = 1'b0;
            m_axi_gmem_rvalid[slot] = 1'b1;
            held_data = row_data;
            wait_attempts = 0;
            while (m_axi_gmem_rready[slot] !== 1'b1) begin
                wait_attempts = wait_attempts + 1;
                if (wait_attempts > 2000)
                    $fatal(1, "RREADY timeout slot=%0d", slot);
                @(posedge ap_clk);
                if ((m_axi_gmem_rvalid[slot] !== 1'b1) ||
                    (m_axi_gmem_rdata[slot] !== held_data))
                    $fatal(1, "R payload changed while retained slot=%0d",
                           slot);
            end
            @(posedge ap_clk);
            if (first_r_handshake_ar_count < 0)
                first_r_handshake_ar_count = ar_handshake_count;
            r_handshake_count = r_handshake_count + 1;
            response_order_observed[response_order_count] = slot;
            response_order_count = response_order_count + 1;
            for (lane_i = 0; lane_i < 8; lane_i = lane_i + 1) begin
                observed_row[slot][lane_i] =
                    $signed(m_axi_gmem_rdata[slot][lane_i*16 +: 16]);
                if (observed_row[slot][lane_i] !==
                    (row * 8 + lane_i - 256))
                    $fatal(1,
                           "row%0d lane%0d mismatch actual=%0d expected=%0d",
                           row, lane_i, observed_row[slot][lane_i],
                           row * 8 + lane_i - 256);
            end
            @(negedge ap_clk);
            m_axi_gmem_rvalid[slot] = 1'b0;
            m_axi_gmem_rlast[slot] = 1'b0;
            m_axi_gmem_rresp[slot] = 2'b00;
        end
    endtask

    task automatic wait_loaded_mask(input logic [3:0] expected_mask);
        begin
            wait_attempts = 0;
            axi_read(ADDR_PIPE_EMB_LOADED_MASK, mask_value);
            while (mask_value[3:0] !== expected_mask) begin
                wait_attempts = wait_attempts + 1;
                if (wait_attempts > 2000)
                    $fatal(1, "loaded mask timeout actual=%h expected=%h",
                           mask_value[3:0], expected_mask);
                axi_read(ADDR_PIPE_EMB_LOADED_MASK, mask_value);
            end
        end
    endtask

    task automatic wait_command_idle;
        begin
            wait_attempts = 0;
            axi_read(ADDR_PIPE_CONTROL_STATUS, status_value);
            while (status_value[6] === 1'b1) begin
                wait_attempts = wait_attempts + 1;
                if (wait_attempts > 3000)
                    $fatal(1, "pipeline command timeout status=0x%08x",
                           status_value);
                axi_read(ADDR_PIPE_CONTROL_STATUS, status_value);
            end
            if ((status_value[31] === 1'b1) ||
                (status_value[5] === 1'b1) ||
                (status_value[4] === 1'b1))
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
            axi_write(ADDR_PIPE_BOTTOM_CONFIG, 32'h0000_0200);
            axi_write(ADDR_PIPE_TOP_CONFIG, 32'h0000_0302);
            axi_write(ADDR_PIPELINE_CONFIG, 32'h0000_0000);
            program_a17_table_bases();
            axi_write(ADDR_A15_CONTROL_STATUS, A15_CMD_START);
            axi_read(ADDR_A15_CONTROL_STATUS, a15_status_value);
            if (a15_status_value[0] !== 1'b1)
                $fatal(1, "A15 START did not enter active state: 0x%08x",
                       a15_status_value);
        end
    endtask

    task automatic verify_saturating_counter;
        begin
            @(negedge ap_clk);
            saturation_clear = 1'b1;
            @(negedge ap_clk);
            saturation_clear = 1'b0;
            saturation_start = 1'b1;
            @(negedge ap_clk);
            saturation_start = 1'b0;
            repeat (20) @(posedge ap_clk);
            @(negedge ap_clk);
            saturation_stop = 1'b1;
            @(posedge ap_clk);
            @(negedge ap_clk);
            saturation_stop = 1'b0;
            repeat (2) @(posedge ap_clk);
            if ((saturation_count !== 4'hF) || (saturation_active !== 1'b0))
                $fatal(1,
                       "saturating counter mismatch count=0x%0h active=%0b",
                       saturation_count, saturation_active);
        end
    endtask

    task automatic wait_for_result(input integer backpressure_cycles);
        begin
            wait_attempts = 0;
            axi_read(ADDR_PIPE_CONTROL_STATUS, status_value);
            while (status_value[2] !== 1'b1) begin
                wait_attempts = wait_attempts + 1;
                if (wait_attempts > 30000)
                    $fatal(1, "result timeout status=0x%08x",
                           status_value);
                if ((status_value[31] === 1'b1) ||
                    (status_value[5] === 1'b1) ||
                    (status_value[4] === 1'b1))
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
            axi_read(ADDR_A16_HBM_LOOKUP_CYCLES,
                     hbm_lookup_cycles_value);
            axi_read(ADDR_A16_FPGA_END_TO_END_CYCLES,
                     fpga_end_to_end_cycles_value);
            held_result = result_value[15:0];
            held_bottom_cycles = bottom_cycles_value;
            held_interaction_cycles = interaction_cycles_value;
            held_top_cycles = top_cycles_value;
            held_total_cycles = total_cycles_value;
            held_hbm_lookup_cycles = hbm_lookup_cycles_value;
            held_fpga_end_to_end_cycles = fpga_end_to_end_cycles_value;
            stage_cycle_sum = bottom_cycles_value +
                              interaction_cycles_value +
                              top_cycles_value;

            if (held_result !== 16'sd36)
                $fatal(1, "result mismatch: %0d", held_result);
            if (result_index_value[5:0] !== 6'd0)
                $fatal(1, "result index mismatch: %0d",
                       result_index_value[5:0]);
            if ((result_meta_value[0] !== 1'b1) ||
                (result_meta_value[1] !== 1'b1))
                $fatal(1, "result meta mismatch: 0x%08x",
                       result_meta_value);
            if (result_meta_value[23:16] !== 8'd4)
                $fatal(1, "result tag mismatch: %0d",
                       result_meta_value[23:16]);
            if ((bottom_cycles_value === 32'd0) ||
                (interaction_cycles_value === 32'd0) ||
                (top_cycles_value === 32'd0) ||
                (total_cycles_value === 32'd0)) begin
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
            if ((hbm_lookup_cycles_value === 32'd0) ||
                (fpga_end_to_end_cycles_value <= hbm_lookup_cycles_value) ||
                (fpga_end_to_end_cycles_value <= total_cycles_value)) begin
                $fatal(1,
                       "A16 latency relation mismatch lookup=%0d e2e=%0d compute=%0d",
                       hbm_lookup_cycles_value,
                       fpga_end_to_end_cycles_value,
                       total_cycles_value);
            end
            if (fpga_end_to_end_cycles_value <
                (hbm_lookup_cycles_value + total_cycles_value)) begin
                $fatal(1,
                       "negative A16 pipeline overhead lookup=%0d e2e=%0d compute=%0d",
                       hbm_lookup_cycles_value,
                       fpga_end_to_end_cycles_value,
                       total_cycles_value);
            end
            pipeline_overhead_cycles =
                fpga_end_to_end_cycles_value -
                hbm_lookup_cycles_value - total_cycles_value;

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
                axi_read(ADDR_A16_HBM_LOOKUP_CYCLES,
                         hbm_lookup_cycles_value);
                axi_read(ADDR_A16_FPGA_END_TO_END_CYCLES,
                         fpga_end_to_end_cycles_value);
                if ((status_value[2] !== 1'b1) ||
                    (result_value[15:0] !== held_result))
                    $fatal(1,
                           "result changed under host backpressure");
                if ((bottom_cycles_value !== held_bottom_cycles) ||
                    (interaction_cycles_value !==
                     held_interaction_cycles) ||
                    (top_cycles_value !== held_top_cycles) ||
                    (total_cycles_value !== held_total_cycles) ||
                    (hbm_lookup_cycles_value !==
                     held_hbm_lookup_cycles) ||
                    (fpga_end_to_end_cycles_value !==
                     held_fpga_end_to_end_cycles)) begin
                    $fatal(1,
                           "cycle counter changed under Host backpressure");
                end
            end

            axi_write(ADDR_PIPE_CONTROL_STATUS, PIPE_CMD_RESULT_POP);

            wait_attempts = 0;
            axi_read(ADDR_PIPE_CONTROL_STATUS, status_value);
            while (status_value[1] !== 1'b1) begin
                wait_attempts = wait_attempts + 1;
                if (wait_attempts > 5000)
                    $fatal(1, "done timeout status=0x%08x",
                           status_value);
                if ((status_value[31] === 1'b1) ||
                    (status_value[5] === 1'b1) ||
                    (status_value[4] === 1'b1))
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
            axi_read(ADDR_A16_HBM_LOOKUP_CYCLES,
                     hbm_lookup_cycles_value);
            axi_read(ADDR_A16_FPGA_END_TO_END_CYCLES,
                     fpga_end_to_end_cycles_value);
            if ((bottom_cycles_value !== held_bottom_cycles) ||
                (interaction_cycles_value !== held_interaction_cycles) ||
                (top_cycles_value !== held_top_cycles) ||
                (total_cycles_value !== held_total_cycles) ||
                (hbm_lookup_cycles_value !== held_hbm_lookup_cycles) ||
                (fpga_end_to_end_cycles_value !==
                 held_fpga_end_to_end_cycles)) begin
                $fatal(1, "cycle counter changed after result retirement");
            end

            axi_write(ADDR_PIPE_CONTROL_STATUS, PIPE_CMD_CLEAR_DONE);
            axi_read(ADDR_PIPE_CONTROL_STATUS, status_value);
            if ((status_value[1] === 1'b1) ||
                (status_value[31] === 1'b1) ||
                (status_value[5] === 1'b1) ||
                (status_value[4] === 1'b1)) begin
                $fatal(1, "clear-done status mismatch: 0x%08x",
                       status_value);
            end
            axi_read(ADDR_PIPE_BOTTOM_CYCLES, bottom_cycles_value);
            axi_read(ADDR_PIPE_INTERACTION_CYCLES,
                     interaction_cycles_value);
            axi_read(ADDR_PIPE_TOP_CYCLES, top_cycles_value);
            axi_read(ADDR_PIPE_TOTAL_CYCLES, total_cycles_value);
            axi_read(ADDR_A16_HBM_LOOKUP_CYCLES,
                     hbm_lookup_cycles_value);
            axi_read(ADDR_A16_FPGA_END_TO_END_CYCLES,
                     fpga_end_to_end_cycles_value);
            if ((bottom_cycles_value !== held_bottom_cycles) ||
                (interaction_cycles_value !== held_interaction_cycles) ||
                (top_cycles_value !== held_top_cycles) ||
                (total_cycles_value !== held_total_cycles) ||
                (hbm_lookup_cycles_value !== held_hbm_lookup_cycles) ||
                (fpga_end_to_end_cycles_value !==
                 held_fpga_end_to_end_cycles)) begin
                $fatal(1, "cycle counter changed after clear-done");
            end

            if (run_index == 0) begin
                first_bottom_cycles = held_bottom_cycles;
                first_interaction_cycles = held_interaction_cycles;
                first_top_cycles = held_top_cycles;
                first_total_cycles = held_total_cycles;
                first_hbm_lookup_cycles = held_hbm_lookup_cycles;
                first_fpga_end_to_end_cycles =
                    held_fpga_end_to_end_cycles;
            end else begin
                if ((held_bottom_cycles !== first_bottom_cycles) ||
                    (held_interaction_cycles !==
                     first_interaction_cycles) ||
                    (held_top_cycles !== first_top_cycles) ||
                    (held_total_cycles !== first_total_cycles) ||
                    (held_hbm_lookup_cycles !==
                     first_hbm_lookup_cycles) ||
                    (held_fpga_end_to_end_cycles !==
                     first_fpga_end_to_end_cycles)) begin
                    $fatal(1,
                           "cycle counters differ across identical restarts");
                end
            end
        end
    endtask

    task automatic service_success_group;
        integer slot;
        begin
            wait_arvalid_mask(4'hF);
            for (slot = 0; slot < 4; slot = slot + 1)
                check_ar_payload(slot);
            held_araddr[0] = m_axi_gmem_araddr[0];
            held_araddr[1] = m_axi_gmem_araddr[1];
            held_araddr[2] = m_axi_gmem_araddr[2];
            held_araddr[3] = m_axi_gmem_araddr[3];
            repeat (4) begin
                @(posedge ap_clk);
                for (slot = 0; slot < 4; slot = slot + 1) begin
                    if ((m_axi_gmem_arvalid[slot] !== 1'b1) ||
                        (m_axi_gmem_araddr[slot] !== held_araddr[slot]))
                        $fatal(1, "AR payload changed while stalled slot=%0d",
                               slot);
                end
            end

            axi_write(ADDR_A15_CONTROL_STATUS, A15_CMD_START);
            axi_read(ADDR_PIPE_ERROR_CODE, error_code_value);
            if ((error_code_value[17] !== 1'b1) ||
                (error_code_value[11:8] !== 4'd3))
                $fatal(1,
                       "repeated START was not rejected deterministically: 0x%08x",
                       error_code_value);
            axi_write(ADDR_PIPE_CONTROL_STATUS, PIPE_CMD_ERROR_ACK);

            axi_write(ADDR_A15_TABLE_BASE_LO, 32'hFFFF_FFF0);
            axi_read(ADDR_PIPE_ERROR_CODE, error_code_value);
            if ((error_code_value[17] !== 1'b1) ||
                (error_code_value[11:8] !== 4'd1))
                $fatal(1, "busy base write was not rejected: 0x%08x",
                       error_code_value);
            axi_write(ADDR_PIPE_CONTROL_STATUS, PIPE_CMD_ERROR_ACK);

            for (slot = 0; slot < 4; slot = slot + 1)
                handshake_ar(slot);
            if (r_handshake_count !== 0)
                $fatal(1, "R beat occurred before all four AR handshakes");

            repeat (3) @(posedge ap_clk);
            for (step = 0; step < 4; step = step + 1)
                drive_r(reorder_port(step), 1'b0);

            if ((response_order_observed[0] !== 2) ||
                (response_order_observed[1] !== 0) ||
                (response_order_observed[2] !== 3) ||
                (response_order_observed[3] !== 1))
                $fatal(1, "response order mismatch %0d %0d %0d %0d",
                       response_order_observed[0],
                       response_order_observed[1],
                       response_order_observed[2],
                       response_order_observed[3]);
            if (first_r_handshake_ar_count !== 4)
                $fatal(1, "first R saw only %0d AR handshakes",
                       first_r_handshake_ar_count);

            wait_loaded_mask(4'hF);
        end
    endtask

    always @(posedge ap_clk) begin
        if (!ap_rst_n)
            cycle_count <= 0;
        else begin
            cycle_count <= cycle_count + 1;
            if (cycle_count > 3000000)
                $fatal(1,
                       "tb_dlrm_f37x_rtl_kernel_stage2n_a17_v1: TIMEOUT");
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
        first_hbm_lookup_cycles = 32'd0;
        first_fpga_end_to_end_cycles = 32'd0;

        reset_dut();
        axi_read(ADDR_A15_CONTROL_STATUS, a15_status_value);
        axi_read(ADDR_A15_TABLE_BASE_LO, status_value);
        axi_read(ADDR_A17_RESERVED, reserved_value);
        axi_read(ADDR_PIPE_VERSION, version_value);
        if ((a15_status_value[5:0] !== 6'd0) ||
            (a15_status_value[6] !== 1'b1) || (status_value !== 32'd0))
            $fatal(1, "A15 reset state mismatch status=0x%08x base=0x%08x",
                   a15_status_value, status_value);
        if (reserved_value !== 32'd0)
            $fatal(1, "reserved 0x314 is not zero: 0x%08x", reserved_value);
        if (version_value !== 32'h0002_4E17)
            $fatal(1, "pipeline version mismatch: 0x%08x", version_value);
        axi_read(ADDR_PIPE_EMB_LOADED_MASK, mask_value);
        if (mask_value[3:0] !== 4'h0)
            $fatal(1, "loaded mask not clear after reset");
        if ((|m_axi_gmem_awvalid) || (|m_axi_gmem_wvalid) ||
            (|m_axi_gmem_bready))
            $fatal(1, "read-only AXI write channels are not tied off");
        axi_read(ADDR_A16_HBM_LOOKUP_CYCLES,
                 hbm_lookup_cycles_value);
        axi_read(ADDR_A16_FPGA_END_TO_END_CYCLES,
                 fpga_end_to_end_cycles_value);
        if ((hbm_lookup_cycles_value !== 32'd0) ||
            (fpga_end_to_end_cycles_value !== 32'd0))
            $fatal(1, "A16 counters are not zero after reset");
        axi_write(ADDR_A17_RESERVED, 32'hDEAD_BEEF);
        axi_read(ADDR_PIPE_ERROR_CODE, error_code_value);
        axi_read(ADDR_A17_RESERVED, reserved_value);
        if ((error_code_value[17] !== 1'b1) ||
            (error_code_value[11:8] !== 4'd4) ||
            (reserved_value !== 32'd0))
            $fatal(1, "reserved 0x314 write was not rejected");
        axi_write(ADDR_PIPE_CONTROL_STATUS, PIPE_CMD_ERROR_ACK);
        verify_saturating_counter();
        $display("A17_2_RESET_CLEAN=PASS");
        $display("A17_2_SATURATION=PASS");

        program_a17_table_bases();
        $display("A17_2_SPLIT_AXI_LITE=PASS");
        $display("A17_2_FOUR_BASE_CAPTURE=PASS");

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
            (error_code_value[17] !== 1'b1) ||
            (error_code_value[11:8] !== 4'd5))
            $fatal(1, "Host embedding rejection mismatch mask=%h error=0x%08x",
                   mask_value[3:0], error_code_value);
        axi_write(ADDR_PIPE_CONTROL_STATUS, PIPE_CMD_ERROR_ACK);
        $display("A17_2_HOST_EMBEDDING_REJECT=PASS");

        axi_write(ADDR_A15_CONTROL_STATUS, A15_CMD_START);
        axi_read(ADDR_A15_CONTROL_STATUS, a15_status_value);
        if (a15_status_value[0] !== 1'b1)
            $fatal(1, "error-path START did not become active");
        wait_arvalid_mask(4'hF);
        $display("A17_2_FOUR_AXI=PASS");
        for (port = 0; port < 4; port = port + 1)
            check_ar_payload(port);

        handshake_ar(0);
        handshake_ar(2);
        handshake_ar(3);
        repeat (4) begin
            @(posedge ap_clk);
            if ((m_axi_gmem_arvalid[1] !== 1'b1) ||
                (m_axi_gmem_araddr[1] !== table_base(1) + (ROW1 << 4)))
                $fatal(1, "stalled AR1 payload was not retained");
            if (m_axi_gmem_rready[1] !== 1'b0)
                $fatal(1, "stalled port1 RREADY is not low");
        end
        drive_r(2, 1'b0);
        drive_r(0, 1'b0);
        drive_r(3, 1'b0);
        if (m_axi_gmem_arvalid[1] !== 1'b1)
            $fatal(1, "port1 ARVALID dropped while other channels completed");
        handshake_ar(1);
        drive_r(1, 1'b1);
        wait_a15_error();
        axi_read(ADDR_PIPE_EMB_LOADED_MASK, mask_value);
        axi_read(ADDR_PIPE_TOTAL_CYCLES, total_cycles_value);
        if (mask_value[3:0] !== 4'h0)
            $fatal(1, "failing group injected embeddings mask=%h",
                   mask_value[3:0]);
        if (total_cycles_value !== 32'd0)
            $fatal(1, "pipeline started after lookup error");
        if ((ar_handshake_count !== 4) || (r_handshake_count !== 4))
            $fatal(1, "error path did not drain all four responses");
        axi_write(ADDR_A15_CONTROL_STATUS, A15_CMD_CLEAR);
        wait_a15_idle();
        $display("A17_2_STALL=PASS");
        $display("A17_2_ERROR=PASS");
        $display("A17_2_ERROR_DRAIN_RECOVERY=PASS");

        reset_dut();
        axi_read(ADDR_MLP_VERSION, version_value);
        if (version_value !== 32'h0002_4701)
            $fatal(1, "legacy MLP version mismatch: 0x%08x", version_value);
        axi_read(ADDR_INT_VERSION, version_value);
        if (version_value !== 32'h0002_4E02)
            $fatal(1, "interaction version mismatch: 0x%08x", version_value);
        axi_read(ADDR_PIPE_VERSION, version_value);
        if (version_value !== 32'h0002_4E17)
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

        for (run_index = 0; run_index < 2; run_index = run_index + 1) begin
            ar_handshake_count = 0;
            r_handshake_count = 0;
            first_r_handshake_ar_count = -1;
            response_order_count = 0;

            write_bottom_input();
            axi_read(ADDR_PIPE_EMB_LOADED_MASK, mask_value);
            if ((run_index == 0) && (mask_value[3:0] !== 4'h0))
                $fatal(1, "first-run mask must be zero before A17 START");
            if ((run_index == 1) && (mask_value[3:0] !== 4'hF))
                $fatal(1, "restart must preserve accepted loaded mask");

            start_a15_pipeline();
            service_success_group();
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
            if ((a15_status_value[4] !== 1'b1) ||
                (a15_status_value[5] === 1'b1) ||
                (a15_status_value[31] === 1'b1))
                $fatal(1, "A15 completion status mismatch: 0x%08x",
                       a15_status_value);
            axi_write(ADDR_A15_CONTROL_STATUS, A15_CMD_CLEAR);
            wait_a15_idle();

            axi_read(ADDR_A16_HBM_LOOKUP_CYCLES,
                     hbm_lookup_cycles_value);
            axi_read(ADDR_A16_FPGA_END_TO_END_CYCLES,
                     fpga_end_to_end_cycles_value);
            if ((hbm_lookup_cycles_value !== held_hbm_lookup_cycles) ||
                (fpga_end_to_end_cycles_value !==
                 held_fpga_end_to_end_cycles))
                $fatal(1, "A16 counters changed after A15 CLEAR");

            if ((ar_handshake_count !== 4) || (r_handshake_count !== 4))
                $fatal(1, "successful accounting mismatch ar/r=%0d/%0d",
                       ar_handshake_count, r_handshake_count);

            $display("A17_2_RUN_%0d=PASS", run_index + 1);
        end

        $display("A17_2_FOUR_AR_BEFORE_ANY_R=PASS");
        $display("A17_2_REORDER=PASS");
        $display("A17_2_COUNTER_RESTART_DETERMINISM=PASS");
        $display("A17_2_RESTART=PASS");
        $display("A17_2_LOADED_MASK=PASS");
        $display("A17_2_RESULT_MATCH=PASS");
        $display("A17_2_A13_COUNTER_ABI=PASS");
        $display("A17_2_CANONICAL_ROWS=37,38,39,40");
        $display("A17_2_GOLDEN_FINAL_RESULT=36");
        $display("A17_2_ACTUAL_FINAL_RESULT=%0d", held_result);
        $display("A17_2_HBM_LOOKUP_CYCLES=%0d",
                 held_hbm_lookup_cycles);
        $display("A17_2_BOTTOM_CYCLES=%0d", held_bottom_cycles);
        $display("A17_2_INTERACTION_CYCLES=%0d",
                 held_interaction_cycles);
        $display("A17_2_TOP_CYCLES=%0d", held_top_cycles);
        $display("A17_2_COMPUTE_TOTAL_CYCLES=%0d", held_total_cycles);
        $display("A17_2_FPGA_END_TO_END_CYCLES=%0d",
                 held_fpga_end_to_end_cycles);
        $display("A17_2_PIPELINE_OVERHEAD_CYCLES=%0d",
                 pipeline_overhead_cycles);
        $display("A17_2_AR_HANDSHAKES=%0d", ar_handshake_count);
        $display("A17_2_R_HANDSHAKES=%0d", r_handshake_count);
        $display("A17_2_FINAL_LOADED_MASK=0x%0h", mask_value[3:0]);
        $display("A17_2_LATENCY_ACCOUNTING=PASS");
        $display("STAGE2N_A17_2_PUBLIC_KERNEL_XSIM_V1_PASS");
        $finish;
    end

endmodule
