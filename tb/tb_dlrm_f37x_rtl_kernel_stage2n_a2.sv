`timescale 1ns / 1ps

module tb_dlrm_f37x_rtl_kernel_stage2n_a2;

    localparam integer ADDR_WIDTH = 12;

    localparam logic [ADDR_WIDTH-1:0] ADDR_CONTROL_STATUS = 12'h000;
    localparam logic [ADDR_WIDTH-1:0] ADDR_RESULT_COUNT = 12'h008;
    localparam logic [ADDR_WIDTH-1:0] ADDR_LAYER_COUNT = 12'h010;
    localparam logic [ADDR_WIDTH-1:0] ADDR_INITIAL_BUFFER = 12'h014;
    localparam logic [ADDR_WIDTH-1:0] ADDR_DESC_INDEX = 12'h020;
    localparam logic [ADDR_WIDTH-1:0] ADDR_DESC_WORD0 = 12'h024;
    localparam logic [ADDR_WIDTH-1:0] ADDR_DESC_WORD1 = 12'h028;
    localparam logic [ADDR_WIDTH-1:0] ADDR_DESC_WORD2 = 12'h02C;
    localparam logic [ADDR_WIDTH-1:0] ADDR_ACT_BUFFER = 12'h040;
    localparam logic [ADDR_WIDTH-1:0] ADDR_ACT_CHUNK_INDEX = 12'h044;
    localparam logic [ADDR_WIDTH-1:0] ADDR_ACT_LANE_MASK = 12'h048;
    localparam logic [ADDR_WIDTH-1:0] ADDR_ACT_DATA0 = 12'h050;
    localparam logic [ADDR_WIDTH-1:0] ADDR_ACT_DATA1 = 12'h054;
    localparam logic [ADDR_WIDTH-1:0] ADDR_ACT_DATA2 = 12'h058;
    localparam logic [ADDR_WIDTH-1:0] ADDR_ACT_DATA3 = 12'h05C;
    localparam logic [ADDR_WIDTH-1:0] ADDR_ACT_DATA4 = 12'h060;
    localparam logic [ADDR_WIDTH-1:0] ADDR_ACT_DATA5 = 12'h064;
    localparam logic [ADDR_WIDTH-1:0] ADDR_ACT_DATA6 = 12'h068;
    localparam logic [ADDR_WIDTH-1:0] ADDR_ACT_DATA7 = 12'h06C;
    localparam logic [ADDR_WIDTH-1:0] ADDR_WEIGHT_ADDRESS = 12'h080;
    localparam logic [ADDR_WIDTH-1:0] ADDR_WEIGHT_DATA = 12'h084;
    localparam logic [ADDR_WIDTH-1:0] ADDR_BIAS_ADDRESS = 12'h090;
    localparam logic [ADDR_WIDTH-1:0] ADDR_BIAS_DATA = 12'h094;
    localparam logic [ADDR_WIDTH-1:0] ADDR_RESULT_DATA = 12'h0A0;
    localparam logic [ADDR_WIDTH-1:0] ADDR_RESULT_INDEX = 12'h0A4;
    localparam logic [ADDR_WIDTH-1:0] ADDR_RESULT_META = 12'h0A8;

    localparam logic [ADDR_WIDTH-1:0] ADDR_INT_CONTROL_STATUS = 12'h100;
    localparam logic [ADDR_WIDTH-1:0] ADDR_INT_VERSION = 12'h104;
    localparam logic [ADDR_WIDTH-1:0] ADDR_INT_RESULT_COUNT = 12'h108;
    localparam logic [ADDR_WIDTH-1:0] ADDR_INT_SHIFT = 12'h10C;
    localparam logic [ADDR_WIDTH-1:0] ADDR_INT_VECTOR_INDEX = 12'h110;
    localparam logic [ADDR_WIDTH-1:0] ADDR_INT_VECTOR_DATA0 = 12'h114;
    localparam logic [ADDR_WIDTH-1:0] ADDR_INT_VECTOR_DATA1 = 12'h118;
    localparam logic [ADDR_WIDTH-1:0] ADDR_INT_VECTOR_DATA2 = 12'h11C;
    localparam logic [ADDR_WIDTH-1:0] ADDR_INT_VECTOR_DATA3 = 12'h120;
    localparam logic [ADDR_WIDTH-1:0] ADDR_INT_RESULT_DATA = 12'h124;
    localparam logic [ADDR_WIDTH-1:0] ADDR_INT_RESULT_INDEX = 12'h128;
    localparam logic [ADDR_WIDTH-1:0] ADDR_INT_RESULT_META = 12'h12C;
    localparam logic [ADDR_WIDTH-1:0] ADDR_INT_LOADED_MASK = 12'h130;

    localparam logic [31:0] CMD_START = 32'h0000_0001;
    localparam logic [31:0] CMD_DESC_COMMIT = 32'h0000_0002;
    localparam logic [31:0] CMD_ACT_COMMIT = 32'h0000_0004;
    localparam logic [31:0] CMD_WEIGHT_COMMIT = 32'h0000_0008;
    localparam logic [31:0] CMD_BIAS_COMMIT = 32'h0000_0010;
    localparam logic [31:0] CMD_RESULT_POP = 32'h0000_0020;

    localparam logic [31:0] INT_CMD_LOAD_VECTOR = 32'h0000_0001;
    localparam logic [31:0] INT_CMD_START = 32'h0000_0002;
    localparam logic [31:0] INT_CMD_RESULT_POP = 32'h0000_0004;

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

    integer cycle_count;
    integer output_number;
    integer wait_attempts;

    logic [31:0] status_value;
    logic [31:0] result_value;
    logic [31:0] index_value;
    logic [31:0] meta_value;
    logic [31:0] count_value;
    logic [31:0] loaded_mask_value;
    logic [31:0] version_value;
    logic [95:0] descriptor_value;
    logic signed [15:0] expected_interaction [0:17];

    dlrm_f37x_rtl_kernel_stage2n_a2 dut (
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
        .s_axi_control_rready(s_axi_control_rready)
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

    task automatic axi_write(
        input logic [ADDR_WIDTH-1:0] address,
        input logic [31:0] data
    );
        begin
            @(negedge ap_clk);
            s_axi_control_awaddr = address;
            s_axi_control_awvalid = 1'b1;
            while (!s_axi_control_awready) begin
                @(posedge ap_clk);
            end
            @(negedge ap_clk);
            s_axi_control_awvalid = 1'b0;

            s_axi_control_wdata = data;
            s_axi_control_wstrb = 4'hF;
            s_axi_control_wvalid = 1'b1;
            while (!s_axi_control_wready) begin
                @(posedge ap_clk);
            end
            @(negedge ap_clk);
            s_axi_control_wvalid = 1'b0;
            s_axi_control_bready = 1'b1;

            while (!s_axi_control_bvalid) begin
                @(posedge ap_clk);
            end
            if (s_axi_control_bresp !== 2'b00) begin
                $fatal(1, "AXI write response error at address 0x%0h",
                       address);
            end

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
            while (!s_axi_control_arready) begin
                @(posedge ap_clk);
            end
            @(negedge ap_clk);
            s_axi_control_arvalid = 1'b0;
            s_axi_control_rready = 1'b1;

            while (!s_axi_control_rvalid) begin
                @(posedge ap_clk);
            end
            data = s_axi_control_rdata;
            if (s_axi_control_rresp !== 2'b00) begin
                $fatal(1, "AXI read response error at address 0x%0h",
                       address);
            end

            @(negedge ap_clk);
            s_axi_control_rready = 1'b0;
        end
    endtask

    task automatic wait_mlp_command_idle;
        begin
            wait_attempts = 0;
            axi_read(ADDR_CONTROL_STATUS, status_value);
            while (status_value[7]) begin
                wait_attempts = wait_attempts + 1;
                if (wait_attempts > 2000) begin
                    $fatal(1, "Timeout waiting for MLP command");
                end
                axi_read(ADDR_CONTROL_STATUS, status_value);
            end
            if (status_value[5] || status_value[4]) begin
                $fatal(1, "MLP kernel error: status=0x%08x",
                       status_value);
            end
        end
    endtask

    task automatic wait_interaction_command_idle;
        begin
            wait_attempts = 0;
            axi_read(ADDR_INT_CONTROL_STATUS, status_value);
            while (status_value[7]) begin
                wait_attempts = wait_attempts + 1;
                if (wait_attempts > 2000) begin
                    $fatal(1, "Timeout waiting for interaction command");
                end
                axi_read(ADDR_INT_CONTROL_STATUS, status_value);
            end
            if (status_value[5] || status_value[4]) begin
                $fatal(1, "Interaction error: status=0x%08x",
                       status_value);
            end
        end
    endtask

    task automatic write_descriptor(
        input integer index,
        input logic [95:0] value
    );
        begin
            axi_write(ADDR_DESC_INDEX, index);
            axi_write(ADDR_DESC_WORD0, value[31:0]);
            axi_write(ADDR_DESC_WORD1, value[63:32]);
            axi_write(ADDR_DESC_WORD2, value[95:64]);
            axi_write(ADDR_CONTROL_STATUS, CMD_DESC_COMMIT);
            wait_mlp_command_idle();
        end
    endtask

    task automatic write_weight(
        input integer address,
        input integer value
    );
        begin
            axi_write(ADDR_WEIGHT_ADDRESS, address);
            axi_write(ADDR_WEIGHT_DATA, value);
            axi_write(ADDR_CONTROL_STATUS, CMD_WEIGHT_COMMIT);
            wait_mlp_command_idle();
        end
    endtask

    task automatic write_bias(
        input integer address,
        input logic [23:0] value
    );
        begin
            axi_write(ADDR_BIAS_ADDRESS, address);
            axi_write(ADDR_BIAS_DATA, {8'd0, value});
            axi_write(ADDR_CONTROL_STATUS, CMD_BIAS_COMMIT);
            wait_mlp_command_idle();
        end
    endtask

    task automatic write_activation_lane0(input integer value);
        begin
            axi_write(ADDR_ACT_BUFFER, 0);
            axi_write(ADDR_ACT_CHUNK_INDEX, 0);
            axi_write(ADDR_ACT_LANE_MASK, 32'h0000_0001);
            axi_write(ADDR_ACT_DATA0, value[15:0]);
            axi_write(ADDR_ACT_DATA1, 0);
            axi_write(ADDR_ACT_DATA2, 0);
            axi_write(ADDR_ACT_DATA3, 0);
            axi_write(ADDR_ACT_DATA4, 0);
            axi_write(ADDR_ACT_DATA5, 0);
            axi_write(ADDR_ACT_DATA6, 0);
            axi_write(ADDR_ACT_DATA7, 0);
            axi_write(ADDR_CONTROL_STATUS, CMD_ACT_COMMIT);
            wait_mlp_command_idle();
        end
    endtask

    task automatic write_interaction_vector(
        input integer vector_index,
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
            axi_write(ADDR_INT_VECTOR_INDEX, vector_index);
            axi_write(ADDR_INT_VECTOR_DATA0, pack_pair(v0, v1));
            axi_write(ADDR_INT_VECTOR_DATA1, pack_pair(v2, v3));
            axi_write(ADDR_INT_VECTOR_DATA2, pack_pair(v4, v5));
            axi_write(ADDR_INT_VECTOR_DATA3, pack_pair(v6, v7));
            axi_write(
                ADDR_INT_CONTROL_STATUS,
                INT_CMD_LOAD_VECTOR
            );
            wait_interaction_command_idle();
        end
    endtask

    always @(posedge ap_clk) begin
        if (!ap_rst_n) begin
            cycle_count <= 0;
        end
        else begin
            cycle_count <= cycle_count + 1;
            if (cycle_count > 200000) begin
                $fatal(
                    1,
                    "tb_dlrm_f37x_rtl_kernel_stage2n_a2: TIMEOUT"
                );
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
        s_axi_control_bready = 1'b0;
        s_axi_control_araddr = '0;
        s_axi_control_arvalid = 1'b0;
        s_axi_control_rready = 1'b0;

        expected_interaction[0] = 16'sd1;
        expected_interaction[1] = 16'sd2;
        expected_interaction[2] = 16'sd3;
        expected_interaction[3] = 16'sd4;
        expected_interaction[4] = 16'sd5;
        expected_interaction[5] = 16'sd6;
        expected_interaction[6] = 16'sd7;
        expected_interaction[7] = 16'sd8;
        expected_interaction[8] = -16'sd4;
        expected_interaction[9] = 16'sd72;
        expected_interaction[10] = 16'sd0;
        expected_interaction[11] = -16'sd204;
        expected_interaction[12] = 16'sd4;
        expected_interaction[13] = -16'sd72;
        expected_interaction[14] = 16'sd192;
        expected_interaction[15] = 16'sd4;
        expected_interaction[16] = 16'sd104;
        expected_interaction[17] = -16'sd192;

        repeat (6) @(posedge ap_clk);
        @(negedge ap_clk);
        ap_rst_n = 1'b1;

        // Legacy MLP window regression: expected result remains 19.
        descriptor_value =
            pack_descriptor(1, 1, 0, 0, 0, 0);
        write_descriptor(0, descriptor_value);

        descriptor_value =
            pack_descriptor(1, 1, 1, 1, 0, 0);
        write_descriptor(1, descriptor_value);

        write_weight(0, 2);
        write_weight(1, 3);
        write_bias(0, 24'h000001);
        write_bias(1, 24'hFFFFFE);
        write_activation_lane0(3);

        axi_write(ADDR_LAYER_COUNT, 2);
        axi_write(ADDR_INITIAL_BUFFER, 0);
        axi_write(ADDR_CONTROL_STATUS, CMD_START);
        wait_mlp_command_idle();

        axi_read(ADDR_CONTROL_STATUS, status_value);
        while (!status_value[2]) begin
            if (status_value[5] || status_value[4]) begin
                $fatal(1, "MLP error waiting result: 0x%08x",
                       status_value);
            end
            axi_read(ADDR_CONTROL_STATUS, status_value);
        end

        axi_read(ADDR_RESULT_DATA, result_value);
        axi_read(ADDR_RESULT_INDEX, index_value);
        axi_read(ADDR_RESULT_META, meta_value);

        if ($signed(result_value) !== 32'sd19) begin
            $fatal(1, "Expected legacy MLP result 19, got %0d",
                   $signed(result_value));
        end
        if (index_value[9:0] !== 10'd0) begin
            $fatal(1, "Unexpected MLP result index %0d",
                   index_value[9:0]);
        end
        if (!meta_value[0] || !meta_value[1]) begin
            $fatal(1, "Unexpected MLP result meta 0x%08x",
                   meta_value);
        end

        axi_write(ADDR_CONTROL_STATUS, CMD_RESULT_POP);

        axi_read(ADDR_CONTROL_STATUS, status_value);
        while (!status_value[1]) begin
            axi_read(ADDR_CONTROL_STATUS, status_value);
        end

        axi_read(ADDR_RESULT_COUNT, count_value);
        if (count_value !== 32'd1) begin
            $fatal(1, "Expected one MLP result, got %0d",
                   count_value);
        end

        // Independent interaction register window.
        axi_read(ADDR_INT_VERSION, version_value);
        if (version_value !== 32'h0002_4E02) begin
            $fatal(1, "Unexpected interaction version 0x%08x",
                   version_value);
        end

        write_interaction_vector(
            0, 1, 2, 3, 4, 5, 6, 7, 8
        );
        write_interaction_vector(
            1, 1, 0, -1, 0, 1, 0, -1, 0
        );
        write_interaction_vector(
            2, 2, 2, 2, 2, 2, 2, 2, 2
        );
        write_interaction_vector(
            3, -1, -2, -3, -4, -5, -6, -7, -8
        );
        write_interaction_vector(
            4, 10, 9, 8, 7, 6, 5, 4, 3
        );

        axi_read(ADDR_INT_LOADED_MASK, loaded_mask_value);
        if (loaded_mask_value[4:0] !== 5'b1_1111) begin
            $fatal(1, "Expected all vectors loaded, mask=0x%08x",
                   loaded_mask_value);
        end

        axi_write(ADDR_INT_SHIFT, 0);
        axi_write(ADDR_INT_CONTROL_STATUS, INT_CMD_START);
        wait_interaction_command_idle();

        for (output_number = 0; output_number < 18;
             output_number = output_number + 1) begin

            wait_attempts = 0;
            axi_read(ADDR_INT_CONTROL_STATUS, status_value);
            while (!status_value[2]) begin
                wait_attempts = wait_attempts + 1;
                if (wait_attempts > 10000) begin
                    $fatal(
                        1,
                        "Timeout waiting interaction result %0d",
                        output_number
                    );
                end
                if (status_value[5] || status_value[4]) begin
                    $fatal(
                        1,
                        "Interaction error waiting result: 0x%08x",
                        status_value
                    );
                end
                axi_read(ADDR_INT_CONTROL_STATUS, status_value);
            end

            axi_read(ADDR_INT_RESULT_DATA, result_value);
            axi_read(ADDR_INT_RESULT_INDEX, index_value);
            axi_read(ADDR_INT_RESULT_META, meta_value);

            if (index_value[4:0] !== output_number[4:0]) begin
                $fatal(
                    1,
                    "Interaction index mismatch: expected %0d got %0d",
                    output_number,
                    index_value[4:0]
                );
            end

            if ($signed(result_value) !==
                $signed(expected_interaction[output_number])) begin
                $fatal(
                    1,
                    "Interaction value mismatch at %0d: expected %0d got %0d",
                    output_number,
                    expected_interaction[output_number],
                    $signed(result_value)
                );
            end

            if (!meta_value[0]) begin
                $fatal(1, "Interaction result not valid at %0d",
                       output_number);
            end

            if (meta_value[1] !== (output_number == 17)) begin
                $fatal(1, "Interaction last mismatch at %0d",
                       output_number);
            end

            axi_write(
                ADDR_INT_CONTROL_STATUS,
                INT_CMD_RESULT_POP
            );
        end

        wait_attempts = 0;
        axi_read(ADDR_INT_CONTROL_STATUS, status_value);
        while (!status_value[1]) begin
            wait_attempts = wait_attempts + 1;
            if (wait_attempts > 10000) begin
                $fatal(1, "Timeout waiting interaction done");
            end
            axi_read(ADDR_INT_CONTROL_STATUS, status_value);
        end

        axi_read(ADDR_INT_RESULT_COUNT, count_value);
        if (count_value !== 32'd18) begin
            $fatal(1, "Expected 18 interaction results, got %0d",
                   count_value);
        end

        $display("tb_dlrm_f37x_rtl_kernel_stage2n_a2: PASS mlp_result=19 interaction_outputs=18");

        repeat (5) @(posedge ap_clk);
        $finish;
    end

endmodule
