`timescale 1ns / 1ps

// Stage 2N-A2 integration top.
//
// This module preserves the verified Stage 2G/2M MLP AXI-Lite register window
// at 0x000-0x0FF and adds an independent DLRM feature-interaction window at
// 0x100-0x13F. The original dlrm_f37x_rtl_kernel is instantiated unchanged.
//
// Interaction register window:
//   0x100 CONTROL_STATUS
//   0x104 VERSION
//   0x108 RESULT_COUNT
//   0x10C SHIFT
//   0x110 VECTOR_INDEX
//   0x114 VECTOR_DATA0  elements 0,1
//   0x118 VECTOR_DATA1  elements 2,3
//   0x11C VECTOR_DATA2  elements 4,5
//   0x120 VECTOR_DATA3  elements 6,7
//   0x124 RESULT_DATA
//   0x128 RESULT_INDEX
//   0x12C RESULT_META
//   0x130 LOADED_MASK
//
// Interaction CONTROL_STATUS write commands:
//   0x01 LOAD_VECTOR
//   0x02 START
//   0x04 RESULT_POP
//   0x08 ERROR_ACK
//   0x10 CLEAR_DONE
module dlrm_f37x_rtl_kernel_stage2n_a2 #(
    parameter integer C_S_AXI_CONTROL_ADDR_WIDTH = 12,
    parameter integer C_S_AXI_CONTROL_DATA_WIDTH = 32
)(
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
        ADDR_INTERACTION_BASE = 12'h100;
    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_INT_CONTROL_STATUS = 12'h100;
    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_INT_VERSION = 12'h104;
    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_INT_RESULT_COUNT = 12'h108;
    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_INT_SHIFT = 12'h10C;
    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_INT_VECTOR_INDEX = 12'h110;
    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_INT_VECTOR_DATA0 = 12'h114;
    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_INT_VECTOR_DATA1 = 12'h118;
    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_INT_VECTOR_DATA2 = 12'h11C;
    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_INT_VECTOR_DATA3 = 12'h120;
    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_INT_RESULT_DATA = 12'h124;
    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_INT_RESULT_INDEX = 12'h128;
    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_INT_RESULT_META = 12'h12C;
    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_INT_LOADED_MASK = 12'h130;

    localparam logic [7:0] INT_CMD_LOAD_VECTOR = 8'h01;
    localparam logic [7:0] INT_CMD_START       = 8'h02;
    localparam logic [7:0] INT_CMD_RESULT_POP  = 8'h04;
    localparam logic [7:0] INT_CMD_ERROR_ACK   = 8'h08;
    localparam logic [7:0] INT_CMD_CLEAR_DONE  = 8'h10;

    localparam logic [3:0] WRAPPER_ERROR_NONE        = 4'd0;
    localparam logic [3:0] WRAPPER_ERROR_PENDING     = 4'd1;
    localparam logic [3:0] WRAPPER_ERROR_BAD_COMMAND = 4'd2;
    localparam logic [3:0] WRAPPER_ERROR_CORE_BUSY   = 4'd3;
    localparam logic [3:0] WRAPPER_ERROR_BAD_ADDRESS = 4'd4;

    logic host_aw_pending;
    logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0] host_awaddr_reg;
    logic host_w_pending;
    logic [C_S_AXI_CONTROL_DATA_WIDTH-1:0] host_wdata_reg;
    logic [(C_S_AXI_CONTROL_DATA_WIDTH/8)-1:0] host_wstrb_reg;

    logic mlp_write_active;
    logic mlp_aw_sent;
    logic mlp_w_sent;

    logic mlp_read_active;
    logic mlp_ar_sent;
    logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0] mlp_araddr_reg;

    logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0] mlp_awaddr;
    logic mlp_awvalid;
    logic mlp_awready;
    logic [C_S_AXI_CONTROL_DATA_WIDTH-1:0] mlp_wdata;
    logic [(C_S_AXI_CONTROL_DATA_WIDTH/8)-1:0] mlp_wstrb;
    logic mlp_wvalid;
    logic mlp_wready;
    logic [1:0] mlp_bresp;
    logic mlp_bvalid;
    logic mlp_bready;
    logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0] mlp_araddr;
    logic mlp_arvalid;
    logic mlp_arready;
    logic [C_S_AXI_CONTROL_DATA_WIDTH-1:0] mlp_rdata;
    logic [1:0] mlp_rresp;
    logic mlp_rvalid;
    logic mlp_rready;

    logic [31:0] int_shift_stage;
    logic [31:0] int_vector_index_stage;
    logic [31:0] int_vector_data_stage [0:3];

    logic [2:0] int_vector_index_cmd;
    logic [127:0] int_vector_data_cmd;
    logic [5:0] int_shift_cmd;

    logic int_load_pending;
    logic int_start_pending;
    logic int_result_ready_pulse;
    logic int_error_ready_pulse;

    logic int_vector_load_ready;
    logic int_start_ready;
    logic int_result_valid;
    logic signed [15:0] int_result_data;
    logic [4:0] int_result_index;
    logic int_result_last;
    logic int_busy;
    logic int_done;
    logic int_error_valid;
    logic [3:0] int_error_code;

    logic int_done_latched;
    logic [31:0] int_result_count;
    logic [4:0] int_loaded_mask;
    logic int_wrapper_error_latched;
    logic [3:0] int_wrapper_error_code;

    logic int_command_pending_any;
    logic [31:0] int_status_word;
    logic [31:0] int_result_meta_word;

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
        !host_aw_pending &&
        !mlp_write_active &&
        !s_axi_control_bvalid;

    assign s_axi_control_wready =
        !host_w_pending &&
        !mlp_write_active &&
        !s_axi_control_bvalid;

    assign s_axi_control_arready =
        !mlp_read_active &&
        !s_axi_control_rvalid;

    assign mlp_awaddr = host_awaddr_reg;
    assign mlp_awvalid = mlp_write_active && !mlp_aw_sent;
    assign mlp_wdata = host_wdata_reg;
    assign mlp_wstrb = host_wstrb_reg;
    assign mlp_wvalid = mlp_write_active && !mlp_w_sent;
    assign mlp_bready =
        mlp_write_active &&
        mlp_aw_sent &&
        mlp_w_sent &&
        !s_axi_control_bvalid;

    assign mlp_araddr = mlp_araddr_reg;
    assign mlp_arvalid = mlp_read_active && !mlp_ar_sent;
    assign mlp_rready =
        mlp_read_active &&
        mlp_ar_sent &&
        !s_axi_control_rvalid;

    assign int_command_pending_any =
        int_load_pending || int_start_pending;

    always_comb begin
        int_status_word = 32'd0;
        int_status_word[0] = int_busy;
        int_status_word[1] = int_done_latched;
        int_status_word[2] = int_result_valid;
        int_status_word[3] = int_result_last;
        int_status_word[4] = int_error_valid;
        int_status_word[5] = int_wrapper_error_latched;
        int_status_word[6] = int_load_pending;
        int_status_word[7] = int_command_pending_any;
        int_status_word[8] = int_vector_load_ready;
        int_status_word[9] = int_start_ready;
        int_status_word[20:16] = int_loaded_mask;
        int_status_word[27:24] = int_error_code;
        int_status_word[31:28] = int_wrapper_error_code;

        int_result_meta_word = 32'd0;
        int_result_meta_word[0] = int_result_valid;
        int_result_meta_word[1] = int_result_last;
        int_result_meta_word[12:8] = int_result_index;
    end

    always_ff @(posedge ap_clk) begin
        if (!ap_rst_n) begin
            host_aw_pending <= 1'b0;
            host_awaddr_reg <= '0;
            host_w_pending <= 1'b0;
            host_wdata_reg <= '0;
            host_wstrb_reg <= '0;

            mlp_write_active <= 1'b0;
            mlp_aw_sent <= 1'b0;
            mlp_w_sent <= 1'b0;

            s_axi_control_bresp <= 2'b00;
            s_axi_control_bvalid <= 1'b0;

            int_shift_stage <= 32'd0;
            int_vector_index_stage <= 32'd0;
            for (reset_word = 0; reset_word < 4;
                 reset_word = reset_word + 1) begin
                int_vector_data_stage[reset_word] <= 32'd0;
            end

            int_vector_index_cmd <= 3'd0;
            int_vector_data_cmd <= 128'd0;
            int_shift_cmd <= 6'd0;

            int_load_pending <= 1'b0;
            int_start_pending <= 1'b0;
            int_result_ready_pulse <= 1'b0;
            int_error_ready_pulse <= 1'b0;

            int_done_latched <= 1'b0;
            int_result_count <= 32'd0;
            int_loaded_mask <= 5'd0;
            int_wrapper_error_latched <= 1'b0;
            int_wrapper_error_code <= WRAPPER_ERROR_NONE;
        end
        else begin
            int_result_ready_pulse <= 1'b0;
            int_error_ready_pulse <= 1'b0;

            if (int_done) begin
                int_done_latched <= 1'b1;
            end

            if (int_result_valid && int_result_ready_pulse) begin
                int_result_count <= int_result_count + 1'b1;
            end

            if (int_load_pending && int_vector_load_ready) begin
                int_load_pending <= 1'b0;
                if (int_vector_index_cmd < 3'd5) begin
                    int_loaded_mask[int_vector_index_cmd] <= 1'b1;
                end
            end

            if (int_start_pending && int_start_ready) begin
                int_start_pending <= 1'b0;
            end

            if (s_axi_control_bvalid && s_axi_control_bready) begin
                s_axi_control_bvalid <= 1'b0;
            end

            if (s_axi_control_awvalid && s_axi_control_awready) begin
                host_awaddr_reg <= s_axi_control_awaddr;
                host_aw_pending <= 1'b1;
            end

            if (s_axi_control_wvalid && s_axi_control_wready) begin
                host_wdata_reg <= s_axi_control_wdata;
                host_wstrb_reg <= s_axi_control_wstrb;
                host_w_pending <= 1'b1;
            end

            if (!mlp_write_active &&
                !s_axi_control_bvalid &&
                host_aw_pending &&
                host_w_pending) begin

                host_aw_pending <= 1'b0;
                host_w_pending <= 1'b0;

                if (host_awaddr_reg < ADDR_INTERACTION_BASE) begin
                    mlp_write_active <= 1'b1;
                    mlp_aw_sent <= 1'b0;
                    mlp_w_sent <= 1'b0;
                end
                else begin
                    s_axi_control_bresp <= 2'b00;
                    s_axi_control_bvalid <= 1'b1;

                    case (host_awaddr_reg)
                        ADDR_INT_CONTROL_STATUS: begin
                            if (host_wstrb_reg[0]) begin
                                case (host_wdata_reg[7:0])
                                    8'h00: begin
                                    end

                                    INT_CMD_LOAD_VECTOR: begin
                                        if (int_command_pending_any) begin
                                            int_wrapper_error_latched <= 1'b1;
                                            int_wrapper_error_code <=
                                                WRAPPER_ERROR_PENDING;
                                        end
                                        else if (!int_vector_load_ready) begin
                                            int_wrapper_error_latched <= 1'b1;
                                            int_wrapper_error_code <=
                                                WRAPPER_ERROR_CORE_BUSY;
                                        end
                                        else begin
                                            int_vector_index_cmd <=
                                                int_vector_index_stage[2:0];
                                            int_vector_data_cmd <= {
                                                int_vector_data_stage[3],
                                                int_vector_data_stage[2],
                                                int_vector_data_stage[1],
                                                int_vector_data_stage[0]
                                            };
                                            int_load_pending <= 1'b1;
                                        end
                                    end

                                    INT_CMD_START: begin
                                        if (int_command_pending_any) begin
                                            int_wrapper_error_latched <= 1'b1;
                                            int_wrapper_error_code <=
                                                WRAPPER_ERROR_PENDING;
                                        end
                                        else if (!int_start_ready) begin
                                            int_wrapper_error_latched <= 1'b1;
                                            int_wrapper_error_code <=
                                                WRAPPER_ERROR_CORE_BUSY;
                                        end
                                        else begin
                                            int_shift_cmd <=
                                                int_shift_stage[5:0];
                                            int_start_pending <= 1'b1;
                                            int_done_latched <= 1'b0;
                                            int_result_count <= 32'd0;
                                        end
                                    end

                                    INT_CMD_RESULT_POP: begin
                                        int_result_ready_pulse <= 1'b1;
                                    end

                                    INT_CMD_ERROR_ACK: begin
                                        int_error_ready_pulse <= 1'b1;
                                        int_wrapper_error_latched <= 1'b0;
                                        int_wrapper_error_code <=
                                            WRAPPER_ERROR_NONE;
                                    end

                                    INT_CMD_CLEAR_DONE: begin
                                        int_done_latched <= 1'b0;
                                    end

                                    default: begin
                                        int_wrapper_error_latched <= 1'b1;
                                        int_wrapper_error_code <=
                                            WRAPPER_ERROR_BAD_COMMAND;
                                    end
                                endcase
                            end
                        end

                        ADDR_INT_SHIFT: begin
                            int_shift_stage <= apply_wstrb32(
                                int_shift_stage,
                                host_wdata_reg,
                                host_wstrb_reg
                            );
                        end

                        ADDR_INT_VECTOR_INDEX: begin
                            int_vector_index_stage <= apply_wstrb32(
                                int_vector_index_stage,
                                host_wdata_reg,
                                host_wstrb_reg
                            );
                        end

                        ADDR_INT_VECTOR_DATA0: begin
                            int_vector_data_stage[0] <= apply_wstrb32(
                                int_vector_data_stage[0],
                                host_wdata_reg,
                                host_wstrb_reg
                            );
                        end

                        ADDR_INT_VECTOR_DATA1: begin
                            int_vector_data_stage[1] <= apply_wstrb32(
                                int_vector_data_stage[1],
                                host_wdata_reg,
                                host_wstrb_reg
                            );
                        end

                        ADDR_INT_VECTOR_DATA2: begin
                            int_vector_data_stage[2] <= apply_wstrb32(
                                int_vector_data_stage[2],
                                host_wdata_reg,
                                host_wstrb_reg
                            );
                        end

                        ADDR_INT_VECTOR_DATA3: begin
                            int_vector_data_stage[3] <= apply_wstrb32(
                                int_vector_data_stage[3],
                                host_wdata_reg,
                                host_wstrb_reg
                            );
                        end

                        default: begin
                            int_wrapper_error_latched <= 1'b1;
                            int_wrapper_error_code <=
                                WRAPPER_ERROR_BAD_ADDRESS;
                        end
                    endcase
                end
            end

            if (mlp_write_active) begin
                if (!mlp_aw_sent && mlp_awready) begin
                    mlp_aw_sent <= 1'b1;
                end
                if (!mlp_w_sent && mlp_wready) begin
                    mlp_w_sent <= 1'b1;
                end

                if (mlp_bvalid && mlp_bready) begin
                    s_axi_control_bresp <= mlp_bresp;
                    s_axi_control_bvalid <= 1'b1;
                    mlp_write_active <= 1'b0;
                    mlp_aw_sent <= 1'b0;
                    mlp_w_sent <= 1'b0;
                end
            end
        end
    end

    always_ff @(posedge ap_clk) begin
        if (!ap_rst_n) begin
            mlp_read_active <= 1'b0;
            mlp_ar_sent <= 1'b0;
            mlp_araddr_reg <= '0;

            s_axi_control_rdata <= 32'd0;
            s_axi_control_rresp <= 2'b00;
            s_axi_control_rvalid <= 1'b0;
        end
        else begin
            if (s_axi_control_rvalid && s_axi_control_rready) begin
                s_axi_control_rvalid <= 1'b0;
            end

            if (s_axi_control_arvalid && s_axi_control_arready) begin
                if (s_axi_control_araddr < ADDR_INTERACTION_BASE) begin
                    mlp_araddr_reg <= s_axi_control_araddr;
                    mlp_read_active <= 1'b1;
                    mlp_ar_sent <= 1'b0;
                end
                else begin
                    s_axi_control_rresp <= 2'b00;

                    case (s_axi_control_araddr)
                        ADDR_INT_CONTROL_STATUS:
                            s_axi_control_rdata <= int_status_word;
                        ADDR_INT_VERSION:
                            s_axi_control_rdata <= 32'h0002_4E02;
                        ADDR_INT_RESULT_COUNT:
                            s_axi_control_rdata <= int_result_count;
                        ADDR_INT_SHIFT:
                            s_axi_control_rdata <= int_shift_stage;
                        ADDR_INT_VECTOR_INDEX:
                            s_axi_control_rdata <= int_vector_index_stage;
                        ADDR_INT_VECTOR_DATA0:
                            s_axi_control_rdata <=
                                int_vector_data_stage[0];
                        ADDR_INT_VECTOR_DATA1:
                            s_axi_control_rdata <=
                                int_vector_data_stage[1];
                        ADDR_INT_VECTOR_DATA2:
                            s_axi_control_rdata <=
                                int_vector_data_stage[2];
                        ADDR_INT_VECTOR_DATA3:
                            s_axi_control_rdata <=
                                int_vector_data_stage[3];
                        ADDR_INT_RESULT_DATA:
                            s_axi_control_rdata <= {
                                {16{int_result_data[15]}},
                                int_result_data
                            };
                        ADDR_INT_RESULT_INDEX:
                            s_axi_control_rdata <= {
                                27'd0,
                                int_result_index
                            };
                        ADDR_INT_RESULT_META:
                            s_axi_control_rdata <= int_result_meta_word;
                        ADDR_INT_LOADED_MASK:
                            s_axi_control_rdata <= {
                                27'd0,
                                int_loaded_mask
                            };
                        default:
                            s_axi_control_rdata <= 32'd0;
                    endcase

                    s_axi_control_rvalid <= 1'b1;
                end
            end

            if (mlp_read_active) begin
                if (!mlp_ar_sent && mlp_arready) begin
                    mlp_ar_sent <= 1'b1;
                end

                if (mlp_rvalid && mlp_rready) begin
                    s_axi_control_rdata <= mlp_rdata;
                    s_axi_control_rresp <= mlp_rresp;
                    s_axi_control_rvalid <= 1'b1;
                    mlp_read_active <= 1'b0;
                    mlp_ar_sent <= 1'b0;
                end
            end
        end
    end

    dlrm_f37x_rtl_kernel u_verified_mlp_kernel (
        .ap_clk(ap_clk),
        .ap_rst_n(ap_rst_n),

        .s_axi_control_awaddr(mlp_awaddr),
        .s_axi_control_awvalid(mlp_awvalid),
        .s_axi_control_awready(mlp_awready),

        .s_axi_control_wdata(mlp_wdata),
        .s_axi_control_wstrb(mlp_wstrb),
        .s_axi_control_wvalid(mlp_wvalid),
        .s_axi_control_wready(mlp_wready),

        .s_axi_control_bresp(mlp_bresp),
        .s_axi_control_bvalid(mlp_bvalid),
        .s_axi_control_bready(mlp_bready),

        .s_axi_control_araddr(mlp_araddr),
        .s_axi_control_arvalid(mlp_arvalid),
        .s_axi_control_arready(mlp_arready),

        .s_axi_control_rdata(mlp_rdata),
        .s_axi_control_rresp(mlp_rresp),
        .s_axi_control_rvalid(mlp_rvalid),
        .s_axi_control_rready(mlp_rready)
    );

    dlrm_feature_interaction_engine u_feature_interaction_engine (
        .clk(ap_clk),
        .rst(!ap_rst_n),

        .vector_load_valid(int_load_pending),
        .vector_load_ready(int_vector_load_ready),
        .vector_load_index(int_vector_index_cmd),
        .vector_load_data(int_vector_data_cmd),

        .start_valid(int_start_pending),
        .start_ready(int_start_ready),
        .interaction_shift(int_shift_cmd),

        .result_valid(int_result_valid),
        .result_ready(int_result_ready_pulse),
        .result_data(int_result_data),
        .result_index(int_result_index),
        .result_last(int_result_last),

        .busy(int_busy),
        .done(int_done),

        .error_valid(int_error_valid),
        .error_ready(int_error_ready_pulse),
        .error_code(int_error_code)
    );

endmodule
