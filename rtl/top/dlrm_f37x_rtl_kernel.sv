`timescale 1ns / 1ps

module dlrm_f37x_rtl_kernel #(
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
        ADDR_CONTROL_STATUS = 12'h000;
    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_VERSION = 12'h004;
    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_RESULT_COUNT = 12'h008;

    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_LAYER_COUNT = 12'h010;
    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_INITIAL_BUFFER = 12'h014;

    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_DESC_INDEX = 12'h020;
    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_DESC_WORD0 = 12'h024;
    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_DESC_WORD1 = 12'h028;
    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_DESC_WORD2 = 12'h02C;

    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_ACT_BUFFER = 12'h040;
    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_ACT_CHUNK_INDEX = 12'h044;
    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_ACT_LANE_MASK = 12'h048;
    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_ACT_DATA0 = 12'h050;
    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_ACT_DATA1 = 12'h054;
    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_ACT_DATA2 = 12'h058;
    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_ACT_DATA3 = 12'h05C;
    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_ACT_DATA4 = 12'h060;
    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_ACT_DATA5 = 12'h064;
    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_ACT_DATA6 = 12'h068;
    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_ACT_DATA7 = 12'h06C;

    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_WEIGHT_ADDRESS = 12'h080;
    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_WEIGHT_DATA = 12'h084;

    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_BIAS_ADDRESS = 12'h090;
    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_BIAS_DATA = 12'h094;

    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_RESULT_DATA = 12'h0A0;
    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_RESULT_INDEX = 12'h0A4;
    localparam logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0]
        ADDR_RESULT_META = 12'h0A8;

    localparam logic [7:0] CMD_START           = 8'h01;
    localparam logic [7:0] CMD_DESC_COMMIT     = 8'h02;
    localparam logic [7:0] CMD_ACT_COMMIT      = 8'h04;
    localparam logic [7:0] CMD_WEIGHT_COMMIT   = 8'h08;
    localparam logic [7:0] CMD_BIAS_COMMIT     = 8'h10;
    localparam logic [7:0] CMD_RESULT_POP      = 8'h20;
    localparam logic [7:0] CMD_ERROR_ACK       = 8'h40;
    localparam logic [7:0] CMD_CLEAR_DONE      = 8'h80;

    localparam logic [3:0] WRAPPER_ERROR_NONE          = 4'd0;
    localparam logic [3:0] WRAPPER_ERROR_PENDING       = 4'd1;
    localparam logic [3:0] WRAPPER_ERROR_BAD_COMMAND   = 4'd2;
    localparam logic [3:0] WRAPPER_ERROR_CORE_BUSY     = 4'd3;

    logic aw_pending;
    logic [C_S_AXI_CONTROL_ADDR_WIDTH-1:0] awaddr_reg;
    logic w_pending;
    logic [C_S_AXI_CONTROL_DATA_WIDTH-1:0] wdata_reg;
    logic [(C_S_AXI_CONTROL_DATA_WIDTH/8)-1:0] wstrb_reg;

    logic aw_fire;
    logic w_fire;
    logic write_fire;
    logic ar_fire;

    logic [31:0] layer_count_stage;
    logic [31:0] initial_buffer_stage;

    logic [31:0] desc_index_stage;
    logic [31:0] desc_word0_stage;
    logic [31:0] desc_word1_stage;
    logic [31:0] desc_word2_stage;

    logic [31:0] act_buffer_stage;
    logic [31:0] act_chunk_stage;
    logic [31:0] act_lane_mask_stage;
    logic [31:0] act_data_stage [0:7];

    logic [31:0] weight_address_stage;
    logic [31:0] weight_data_stage;
    logic [31:0] bias_address_stage;
    logic [31:0] bias_data_stage;

    logic [2:0] start_layer_count_cmd;
    logic start_initial_buffer_cmd;
    logic start_pending;

    logic [1:0] descriptor_index_cmd;
    logic [95:0] descriptor_data_cmd;
    logic descriptor_pending;

    logic act_buffer_cmd;
    logic [5:0] act_chunk_cmd;
    logic [15:0] act_lane_mask_cmd;
    logic [255:0] act_data_cmd;
    logic act_pending;

    logic [31:0] weight_address_cmd;
    logic signed [7:0] weight_data_cmd;
    logic weight_pending;

    logic [31:0] bias_address_cmd;
    logic signed [23:0] bias_data_cmd;
    logic bias_pending;

    logic result_ready_pulse;
    logic error_ready_pulse;

    logic done_latched;
    logic [31:0] result_count;
    logic wrapper_error_latched;
    logic [3:0] wrapper_error_code;

    logic core_descriptor_ready;
    logic core_start_ready;
    logic core_act_ready;
    logic core_weight_ready;
    logic core_bias_ready;

    logic core_result_valid;
    logic signed [15:0] core_result_data;
    logic [9:0] core_result_index;
    logic core_result_last;
    logic [7:0] core_result_tag;

    logic core_busy;
    logic core_done;
    logic core_final_buffer_select;
    logic core_error_valid;
    logic [3:0] core_error_code;

    logic command_pending_any;
    logic [31:0] status_word;
    logic [31:0] result_meta_word;

    integer reset_index;

    function automatic logic [31:0] apply_wstrb32(
        input logic [31:0] current_value,
        input logic [31:0] next_value,
        input logic [3:0] strobe
    );
        integer byte_index;
        begin
            apply_wstrb32 = current_value;
            for (byte_index = 0; byte_index < 4; byte_index = byte_index + 1) begin
                if (strobe[byte_index]) begin
                    apply_wstrb32[byte_index*8 +: 8] =
                        next_value[byte_index*8 +: 8];
                end
            end
        end
    endfunction

    assign command_pending_any =
        start_pending ||
        descriptor_pending ||
        act_pending ||
        weight_pending ||
        bias_pending;

    always_comb begin
        s_axi_control_awready =
            !aw_pending && !s_axi_control_bvalid;
        s_axi_control_wready =
            !w_pending && !s_axi_control_bvalid;
        s_axi_control_arready =
            !s_axi_control_rvalid;

        s_axi_control_bresp = 2'b00;
        s_axi_control_rresp = 2'b00;

        aw_fire =
            s_axi_control_awvalid && s_axi_control_awready;
        w_fire =
            s_axi_control_wvalid && s_axi_control_wready;
        write_fire =
            aw_pending && w_pending && !s_axi_control_bvalid;
        ar_fire =
            s_axi_control_arvalid && s_axi_control_arready;
    end

    always_comb begin
        status_word = 32'd0;
        status_word[0] = core_busy;
        status_word[1] = done_latched;
        status_word[2] = core_result_valid;
        status_word[3] = core_result_last;
        status_word[4] = core_error_valid;
        status_word[5] = wrapper_error_latched;
        status_word[6] = core_final_buffer_select;
        status_word[7] = command_pending_any;
        status_word[8] = core_start_ready;
        status_word[9] = core_descriptor_ready;
        status_word[10] = core_act_ready;
        status_word[11] = core_weight_ready;
        status_word[12] = core_bias_ready;
        status_word[23:16] = core_result_tag;
        status_word[27:24] = core_error_code;
        status_word[31:28] = wrapper_error_code;

        result_meta_word = 32'd0;
        result_meta_word[0] = core_result_valid;
        result_meta_word[1] = core_result_last;
        result_meta_word[15:8] = core_result_tag;
    end

    always_ff @(posedge ap_clk) begin
        if (!ap_rst_n) begin
            aw_pending <= 1'b0;
            awaddr_reg <= '0;
            w_pending <= 1'b0;
            wdata_reg <= '0;
            wstrb_reg <= '0;
            s_axi_control_bvalid <= 1'b0;

            layer_count_stage <= 32'd0;
            initial_buffer_stage <= 32'd0;
            desc_index_stage <= 32'd0;
            desc_word0_stage <= 32'd0;
            desc_word1_stage <= 32'd0;
            desc_word2_stage <= 32'd0;
            act_buffer_stage <= 32'd0;
            act_chunk_stage <= 32'd0;
            act_lane_mask_stage <= 32'd0;
            weight_address_stage <= 32'd0;
            weight_data_stage <= 32'd0;
            bias_address_stage <= 32'd0;
            bias_data_stage <= 32'd0;

            for (reset_index = 0; reset_index < 8;
                 reset_index = reset_index + 1) begin
                act_data_stage[reset_index] <= 32'd0;
            end

            start_layer_count_cmd <= 3'd0;
            start_initial_buffer_cmd <= 1'b0;
            start_pending <= 1'b0;

            descriptor_index_cmd <= 2'd0;
            descriptor_data_cmd <= 96'd0;
            descriptor_pending <= 1'b0;

            act_buffer_cmd <= 1'b0;
            act_chunk_cmd <= 6'd0;
            act_lane_mask_cmd <= 16'd0;
            act_data_cmd <= 256'd0;
            act_pending <= 1'b0;

            weight_address_cmd <= 32'd0;
            weight_data_cmd <= 8'sd0;
            weight_pending <= 1'b0;

            bias_address_cmd <= 32'd0;
            bias_data_cmd <= 24'sd0;
            bias_pending <= 1'b0;

            result_ready_pulse <= 1'b0;
            error_ready_pulse <= 1'b0;

            done_latched <= 1'b0;
            result_count <= 32'd0;
            wrapper_error_latched <= 1'b0;
            wrapper_error_code <= WRAPPER_ERROR_NONE;
        end
        else begin
            result_ready_pulse <= 1'b0;
            error_ready_pulse <= 1'b0;

            if (core_done) begin
                done_latched <= 1'b1;
            end

            if (core_result_valid && result_ready_pulse) begin
                result_count <= result_count + 1'b1;
            end

            if (start_pending && core_start_ready) begin
                start_pending <= 1'b0;
            end
            if (descriptor_pending && core_descriptor_ready) begin
                descriptor_pending <= 1'b0;
            end
            if (act_pending && core_act_ready) begin
                act_pending <= 1'b0;
            end
            if (weight_pending && core_weight_ready) begin
                weight_pending <= 1'b0;
            end
            if (bias_pending && core_bias_ready) begin
                bias_pending <= 1'b0;
            end

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
                    ADDR_CONTROL_STATUS: begin
                        if (wstrb_reg[0]) begin
                            case (wdata_reg[7:0])
                                8'h00: begin
                                end

                                CMD_START: begin
                                    if (command_pending_any) begin
                                        wrapper_error_latched <= 1'b1;
                                        wrapper_error_code <=
                                            WRAPPER_ERROR_PENDING;
                                    end
                                    else if (core_busy ||
                                             core_error_valid) begin
                                        wrapper_error_latched <= 1'b1;
                                        wrapper_error_code <=
                                            WRAPPER_ERROR_CORE_BUSY;
                                    end
                                    else begin
                                        start_layer_count_cmd <=
                                            layer_count_stage[2:0];
                                        start_initial_buffer_cmd <=
                                            initial_buffer_stage[0];
                                        start_pending <= 1'b1;
                                        done_latched <= 1'b0;
                                        result_count <= 32'd0;
                                    end
                                end

                                CMD_DESC_COMMIT: begin
                                    if (command_pending_any) begin
                                        wrapper_error_latched <= 1'b1;
                                        wrapper_error_code <=
                                            WRAPPER_ERROR_PENDING;
                                    end
                                    else if (core_busy ||
                                             core_error_valid) begin
                                        wrapper_error_latched <= 1'b1;
                                        wrapper_error_code <=
                                            WRAPPER_ERROR_CORE_BUSY;
                                    end
                                    else begin
                                        descriptor_index_cmd <=
                                            desc_index_stage[1:0];
                                        descriptor_data_cmd <= {
                                            desc_word2_stage,
                                            desc_word1_stage,
                                            desc_word0_stage
                                        };
                                        descriptor_pending <= 1'b1;
                                    end
                                end

                                CMD_ACT_COMMIT: begin
                                    if (command_pending_any) begin
                                        wrapper_error_latched <= 1'b1;
                                        wrapper_error_code <=
                                            WRAPPER_ERROR_PENDING;
                                    end
                                    else if (core_busy ||
                                             core_error_valid) begin
                                        wrapper_error_latched <= 1'b1;
                                        wrapper_error_code <=
                                            WRAPPER_ERROR_CORE_BUSY;
                                    end
                                    else begin
                                        act_buffer_cmd <=
                                            act_buffer_stage[0];
                                        act_chunk_cmd <=
                                            act_chunk_stage[5:0];
                                        act_lane_mask_cmd <=
                                            act_lane_mask_stage[15:0];
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

                                CMD_WEIGHT_COMMIT: begin
                                    if (command_pending_any) begin
                                        wrapper_error_latched <= 1'b1;
                                        wrapper_error_code <=
                                            WRAPPER_ERROR_PENDING;
                                    end
                                    else if (core_busy ||
                                             core_error_valid) begin
                                        wrapper_error_latched <= 1'b1;
                                        wrapper_error_code <=
                                            WRAPPER_ERROR_CORE_BUSY;
                                    end
                                    else begin
                                        weight_address_cmd <=
                                            weight_address_stage;
                                        weight_data_cmd <=
                                            weight_data_stage[7:0];
                                        weight_pending <= 1'b1;
                                    end
                                end

                                CMD_BIAS_COMMIT: begin
                                    if (command_pending_any) begin
                                        wrapper_error_latched <= 1'b1;
                                        wrapper_error_code <=
                                            WRAPPER_ERROR_PENDING;
                                    end
                                    else if (core_busy ||
                                             core_error_valid) begin
                                        wrapper_error_latched <= 1'b1;
                                        wrapper_error_code <=
                                            WRAPPER_ERROR_CORE_BUSY;
                                    end
                                    else begin
                                        bias_address_cmd <=
                                            bias_address_stage;
                                        bias_data_cmd <=
                                            bias_data_stage[23:0];
                                        bias_pending <= 1'b1;
                                    end
                                end

                                CMD_RESULT_POP: begin
                                    result_ready_pulse <= 1'b1;
                                end

                                CMD_ERROR_ACK: begin
                                    error_ready_pulse <= 1'b1;
                                    wrapper_error_latched <= 1'b0;
                                    wrapper_error_code <=
                                        WRAPPER_ERROR_NONE;
                                end

                                CMD_CLEAR_DONE: begin
                                    done_latched <= 1'b0;
                                end

                                default: begin
                                    wrapper_error_latched <= 1'b1;
                                    wrapper_error_code <=
                                        WRAPPER_ERROR_BAD_COMMAND;
                                end
                            endcase
                        end
                    end

                    ADDR_LAYER_COUNT: begin
                        layer_count_stage <= apply_wstrb32(
                            layer_count_stage,
                            wdata_reg,
                            wstrb_reg
                        );
                    end

                    ADDR_INITIAL_BUFFER: begin
                        initial_buffer_stage <= apply_wstrb32(
                            initial_buffer_stage,
                            wdata_reg,
                            wstrb_reg
                        );
                    end

                    ADDR_DESC_INDEX: begin
                        desc_index_stage <= apply_wstrb32(
                            desc_index_stage,
                            wdata_reg,
                            wstrb_reg
                        );
                    end

                    ADDR_DESC_WORD0: begin
                        desc_word0_stage <= apply_wstrb32(
                            desc_word0_stage,
                            wdata_reg,
                            wstrb_reg
                        );
                    end

                    ADDR_DESC_WORD1: begin
                        desc_word1_stage <= apply_wstrb32(
                            desc_word1_stage,
                            wdata_reg,
                            wstrb_reg
                        );
                    end

                    ADDR_DESC_WORD2: begin
                        desc_word2_stage <= apply_wstrb32(
                            desc_word2_stage,
                            wdata_reg,
                            wstrb_reg
                        );
                    end

                    ADDR_ACT_BUFFER: begin
                        act_buffer_stage <= apply_wstrb32(
                            act_buffer_stage,
                            wdata_reg,
                            wstrb_reg
                        );
                    end

                    ADDR_ACT_CHUNK_INDEX: begin
                        act_chunk_stage <= apply_wstrb32(
                            act_chunk_stage,
                            wdata_reg,
                            wstrb_reg
                        );
                    end

                    ADDR_ACT_LANE_MASK: begin
                        act_lane_mask_stage <= apply_wstrb32(
                            act_lane_mask_stage,
                            wdata_reg,
                            wstrb_reg
                        );
                    end

                    ADDR_ACT_DATA0: begin
                        act_data_stage[0] <= apply_wstrb32(
                            act_data_stage[0], wdata_reg, wstrb_reg);
                    end
                    ADDR_ACT_DATA1: begin
                        act_data_stage[1] <= apply_wstrb32(
                            act_data_stage[1], wdata_reg, wstrb_reg);
                    end
                    ADDR_ACT_DATA2: begin
                        act_data_stage[2] <= apply_wstrb32(
                            act_data_stage[2], wdata_reg, wstrb_reg);
                    end
                    ADDR_ACT_DATA3: begin
                        act_data_stage[3] <= apply_wstrb32(
                            act_data_stage[3], wdata_reg, wstrb_reg);
                    end
                    ADDR_ACT_DATA4: begin
                        act_data_stage[4] <= apply_wstrb32(
                            act_data_stage[4], wdata_reg, wstrb_reg);
                    end
                    ADDR_ACT_DATA5: begin
                        act_data_stage[5] <= apply_wstrb32(
                            act_data_stage[5], wdata_reg, wstrb_reg);
                    end
                    ADDR_ACT_DATA6: begin
                        act_data_stage[6] <= apply_wstrb32(
                            act_data_stage[6], wdata_reg, wstrb_reg);
                    end
                    ADDR_ACT_DATA7: begin
                        act_data_stage[7] <= apply_wstrb32(
                            act_data_stage[7], wdata_reg, wstrb_reg);
                    end

                    ADDR_WEIGHT_ADDRESS: begin
                        weight_address_stage <= apply_wstrb32(
                            weight_address_stage,
                            wdata_reg,
                            wstrb_reg
                        );
                    end

                    ADDR_WEIGHT_DATA: begin
                        weight_data_stage <= apply_wstrb32(
                            weight_data_stage,
                            wdata_reg,
                            wstrb_reg
                        );
                    end

                    ADDR_BIAS_ADDRESS: begin
                        bias_address_stage <= apply_wstrb32(
                            bias_address_stage,
                            wdata_reg,
                            wstrb_reg
                        );
                    end

                    ADDR_BIAS_DATA: begin
                        bias_data_stage <= apply_wstrb32(
                            bias_data_stage,
                            wdata_reg,
                            wstrb_reg
                        );
                    end

                    default: begin
                    end
                endcase
            end
            else if (s_axi_control_bvalid &&
                     s_axi_control_bready) begin
                s_axi_control_bvalid <= 1'b0;
            end
        end
    end

    always_ff @(posedge ap_clk) begin
        if (!ap_rst_n) begin
            s_axi_control_rvalid <= 1'b0;
            s_axi_control_rdata <= 32'd0;
        end
        else begin
            if (ar_fire) begin
                case (s_axi_control_araddr)
                    ADDR_CONTROL_STATUS:
                        s_axi_control_rdata <= status_word;
                    ADDR_VERSION:
                        s_axi_control_rdata <= 32'h0002_4701;
                    ADDR_RESULT_COUNT:
                        s_axi_control_rdata <= result_count;
                    ADDR_LAYER_COUNT:
                        s_axi_control_rdata <= layer_count_stage;
                    ADDR_INITIAL_BUFFER:
                        s_axi_control_rdata <= initial_buffer_stage;
                    ADDR_DESC_INDEX:
                        s_axi_control_rdata <= desc_index_stage;
                    ADDR_DESC_WORD0:
                        s_axi_control_rdata <= desc_word0_stage;
                    ADDR_DESC_WORD1:
                        s_axi_control_rdata <= desc_word1_stage;
                    ADDR_DESC_WORD2:
                        s_axi_control_rdata <= desc_word2_stage;
                    ADDR_ACT_BUFFER:
                        s_axi_control_rdata <= act_buffer_stage;
                    ADDR_ACT_CHUNK_INDEX:
                        s_axi_control_rdata <= act_chunk_stage;
                    ADDR_ACT_LANE_MASK:
                        s_axi_control_rdata <= act_lane_mask_stage;
                    ADDR_ACT_DATA0:
                        s_axi_control_rdata <= act_data_stage[0];
                    ADDR_ACT_DATA1:
                        s_axi_control_rdata <= act_data_stage[1];
                    ADDR_ACT_DATA2:
                        s_axi_control_rdata <= act_data_stage[2];
                    ADDR_ACT_DATA3:
                        s_axi_control_rdata <= act_data_stage[3];
                    ADDR_ACT_DATA4:
                        s_axi_control_rdata <= act_data_stage[4];
                    ADDR_ACT_DATA5:
                        s_axi_control_rdata <= act_data_stage[5];
                    ADDR_ACT_DATA6:
                        s_axi_control_rdata <= act_data_stage[6];
                    ADDR_ACT_DATA7:
                        s_axi_control_rdata <= act_data_stage[7];
                    ADDR_WEIGHT_ADDRESS:
                        s_axi_control_rdata <= weight_address_stage;
                    ADDR_WEIGHT_DATA:
                        s_axi_control_rdata <= weight_data_stage;
                    ADDR_BIAS_ADDRESS:
                        s_axi_control_rdata <= bias_address_stage;
                    ADDR_BIAS_DATA:
                        s_axi_control_rdata <= bias_data_stage;
                    ADDR_RESULT_DATA:
                        s_axi_control_rdata <= {
                            {16{core_result_data[15]}},
                            core_result_data
                        };
                    ADDR_RESULT_INDEX:
                        s_axi_control_rdata <= {
                            22'd0,
                            core_result_index
                        };
                    ADDR_RESULT_META:
                        s_axi_control_rdata <= result_meta_word;
                    default:
                        s_axi_control_rdata <= 32'd0;
                endcase

                s_axi_control_rvalid <= 1'b1;
            end
            else if (s_axi_control_rvalid &&
                     s_axi_control_rready) begin
                s_axi_control_rvalid <= 1'b0;
            end
        end
    end

    mlp_sequence_controller u_mlp_sequence_controller (
        .clk(ap_clk),
        .rst(!ap_rst_n),

        .descriptor_cfg_valid(descriptor_pending),
        .descriptor_cfg_ready(core_descriptor_ready),
        .descriptor_cfg_index(descriptor_index_cmd),
        .descriptor_cfg_data(descriptor_data_cmd),

        .start_valid(start_pending),
        .start_ready(core_start_ready),
        .layer_count(start_layer_count_cmd),
        .initial_buffer_select(start_initial_buffer_cmd),

        .act_load_valid(act_pending),
        .act_load_ready(core_act_ready),
        .act_load_buffer_select(act_buffer_cmd),
        .act_load_chunk_index(act_chunk_cmd),
        .act_load_lane_mask(act_lane_mask_cmd),
        .act_load_data(act_data_cmd),

        .weight_cfg_valid(weight_pending),
        .weight_cfg_ready(core_weight_ready),
        .weight_cfg_address(weight_address_cmd),
        .weight_cfg_data(weight_data_cmd),

        .bias_cfg_valid(bias_pending),
        .bias_cfg_ready(core_bias_ready),
        .bias_cfg_address(bias_address_cmd),
        .bias_cfg_data(bias_data_cmd),

        .result_valid(core_result_valid),
        .result_ready(result_ready_pulse),
        .result_data(core_result_data),
        .result_index(core_result_index),
        .result_last(core_result_last),
        .result_tag(core_result_tag),

        .busy(core_busy),
        .done(core_done),
        .final_buffer_select(core_final_buffer_select),

        .error_valid(core_error_valid),
        .error_ready(error_ready_pulse),
        .error_code(core_error_code)
    );

endmodule
