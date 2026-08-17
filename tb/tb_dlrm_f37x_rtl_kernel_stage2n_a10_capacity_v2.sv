`timescale 1ns/1ps

module tb_dlrm_f37x_rtl_kernel_stage2n_a10_capacity_v2;

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

    localparam logic [31:0] PIPE_CMD_DESC_COMMIT = 32'h0000_0001;
    localparam logic [31:0] PIPE_CMD_ACT_COMMIT = 32'h0000_0002;
    localparam logic [31:0] PIPE_CMD_EMB_COMMIT = 32'h0000_0004;
    localparam logic [31:0] PIPE_CMD_WEIGHT_COMMIT = 32'h0000_0008;
    localparam logic [31:0] PIPE_CMD_BIAS_COMMIT = 32'h0000_0010;
    localparam logic [31:0] PIPE_CMD_START = 32'h0000_0020;
    localparam logic [31:0] PIPE_CMD_RESULT_POP = 32'h0000_0040;

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
    integer wait_attempts;
    integer address_index;
    integer run_index;
    integer hold_index;

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

    dlrm_f37x_rtl_kernel_stage2n_a10_v2 dut (
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

    task automatic start_pipeline;
        begin
            // Stage 2M shape:
            // bottom descriptors 0..1, two layers, initial buffer 0.
            axi_write(ADDR_PIPE_BOTTOM_CONFIG, 32'h0000_0200);
            // top descriptors 2..4, three layers, input buffer 0.
            axi_write(ADDR_PIPE_TOP_CONFIG, 32'h0000_0302);
            // interaction shift=0 for the deterministic capacity vector.
            axi_write(ADDR_PIPELINE_CONFIG, 32'h0000_0000);
            axi_write(ADDR_PIPE_CONTROL_STATUS, PIPE_CMD_START);
            wait_command_idle();
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
            held_result = result_value[15:0];

            if (held_result !== 16'sd36)
                $fatal(1, "result mismatch: %0d", held_result);
            if (result_index_value[5:0] !== 6'd0)
                $fatal(1, "result index mismatch: %0d",
                       result_index_value[5:0]);
            if (!result_meta_value[0] || !result_meta_value[1])
                $fatal(1, "result meta mismatch: 0x%08x",
                       result_meta_value);

            for (hold_index = 0;
                 hold_index < backpressure_cycles;
                 hold_index = hold_index + 1) begin
                axi_read(ADDR_PIPE_CONTROL_STATUS, status_value);
                axi_read(ADDR_PIPE_RESULT_DATA, result_value);
                if (!status_value[2] ||
                    result_value[15:0] !== held_result)
                    $fatal(1,
                           "result changed under host backpressure");
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
        end
    endtask

    always @(posedge ap_clk) begin
        if (!ap_rst_n)
            cycle_count <= 0;
        else begin
            cycle_count <= cycle_count + 1;
            if (cycle_count > 3000000)
                $fatal(1,
                       "tb_dlrm_f37x_rtl_kernel_stage2n_a10_capacity_v2: TIMEOUT");
        end
    end

    initial begin
        ap_clk = 1'b0;
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
        cycle_count = 0;

        repeat (8) @(posedge ap_clk);
        ap_rst_n = 1'b1;
        repeat (4) @(posedge ap_clk);

        // Prove that the two previously verified windows are preserved.
        axi_read(ADDR_MLP_VERSION, version_value);
        if (version_value !== 32'h0002_4701)
            $fatal(1, "legacy MLP version mismatch: 0x%08x",
                   version_value);

        axi_read(ADDR_INT_VERSION, version_value);
        if (version_value !== 32'h0002_4E02)
            $fatal(1, "interaction version mismatch: 0x%08x",
                   version_value);

        axi_read(ADDR_PIPE_VERSION, version_value);
        if (version_value !== 32'h0002_4E11)
            $fatal(1, "pipeline version mismatch: 0x%08x",
                   version_value);

        // Five descriptors matching the Stage 2M architecture:
        // bottom 8->16->8, interaction 18, top 18->32->16->1.
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

        // Initialize all 1360 Stage 2M-shape weights.
        for (address_index = 0; address_index < 1360;
             address_index = address_index + 1)
            write_weight(address_index, 0);

        // Bottom layer 0: copy inputs 0..7 to outputs 0..7.
        for (address_index = 0; address_index < 8;
             address_index = address_index + 1)
            write_weight(address_index * 9, 1);

        // Bottom layer 1: copy the first eight layer-0 outputs.
        for (address_index = 0; address_index < 8;
             address_index = address_index + 1)
            write_weight(128 + address_index * 17, 1);

        // Top layer 0: copy interaction elements 0..7.
        for (address_index = 0; address_index < 8;
             address_index = address_index + 1)
            write_weight(256 + address_index * 19, 1);

        // Top layer 1: copy its first eight inputs.
        for (address_index = 0; address_index < 8;
             address_index = address_index + 1)
            write_weight(832 + address_index * 33, 1);

        // Top layer 2: sum the first eight values => 1+...+8 = 36.
        for (address_index = 0; address_index < 8;
             address_index = address_index + 1)
            write_weight(1344 + address_index, 1);

        // Exercise and initialize all 73 Stage 2M-shape biases.
        for (address_index = 0; address_index < 73;
             address_index = address_index + 1)
            write_bias(address_index, 0);

        // Zero embeddings make the first eight interaction outputs equal
        // to the bottom vector and all ten pairwise terms equal to zero.
        write_embedding(0, 0, 0, 0, 0, 0, 0, 0, 0);
        write_embedding(1, 0, 0, 0, 0, 0, 0, 0, 0);
        write_embedding(2, 0, 0, 0, 0, 0, 0, 0, 0);
        write_embedding(3, 0, 0, 0, 0, 0, 0, 0, 0);

        axi_read(ADDR_PIPE_EMB_LOADED_MASK, mask_value);
        if (mask_value[3:0] !== 4'hF)
            $fatal(1, "embedding mask mismatch: 0x%0h",
                   mask_value[3:0]);

        for (run_index = 0; run_index < 2;
             run_index = run_index + 1) begin
            write_bottom_input();
            start_pipeline();
            if (run_index == 0)
                wait_for_result(0);
            else
                wait_for_result(12);
        end

        $display("MLP_WINDOW_VERSION=0x00024701");
        $display("INTERACTION_WINDOW_VERSION=0x00024e02");
        $display("PIPELINE_WINDOW_VERSION=0x00024e11");
        $display("PIPELINE_DESCRIPTOR_CAPACITY=8");
        $display("PIPELINE_WEIGHT_CAPACITY=2048");
        $display("PIPELINE_BIAS_CAPACITY=128");
        $display("MODEL_DESCRIPTOR_COUNT=5");
        $display("MODEL_WEIGHT_VALUES=1360");
        $display("MODEL_BIAS_VALUES=73");
        $display("MODEL_SHAPE=8x16x8_interact18_32x16x1");
        $display("PIPELINE_START_COMMANDS=2");
        $display("PIPELINE_RESULT=36");
        $display("BOTTOM_OUTPUTS=8");
        $display("INTERACTION_OUTPUTS=18");
        $display("FINAL_BACKPRESSURE_CYCLES=12");
        $display("tb_dlrm_f37x_rtl_kernel_stage2n_a10_capacity_v2: PASS runs=2 final=36 descriptors=5 weights=1360 biases=73");
        $finish;
    end

endmodule
