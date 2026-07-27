`timescale 1ns/1ps

module tb_dlrm_feature_interaction_engine;

    logic clk;
    logic rst;

    logic vector_load_valid;
    logic vector_load_ready;
    logic [2:0] vector_load_index;
    logic [127:0] vector_load_data;

    logic start_valid;
    logic start_ready;
    logic [5:0] interaction_shift;

    logic result_valid;
    logic result_ready;
    logic signed [15:0] result_data;
    logic [4:0] result_index;
    logic result_last;

    logic busy;
    logic done;

    logic error_valid;
    logic error_ready;
    logic [3:0] error_code;

    logic signed [15:0] expected [0:17];
    integer ready_cycle;
    integer observed_count;
    integer timeout_cycles;

    dlrm_feature_interaction_engine dut (
        .clk(clk),
        .rst(rst),

        .vector_load_valid(vector_load_valid),
        .vector_load_ready(vector_load_ready),
        .vector_load_index(vector_load_index),
        .vector_load_data(vector_load_data),

        .start_valid(start_valid),
        .start_ready(start_ready),
        .interaction_shift(interaction_shift),

        .result_valid(result_valid),
        .result_ready(result_ready),
        .result_data(result_data),
        .result_index(result_index),
        .result_last(result_last),

        .busy(busy),
        .done(done),

        .error_valid(error_valid),
        .error_ready(error_ready),
        .error_code(error_code)
    );

    always #5 clk = ~clk;

    always_ff @(posedge clk) begin
        if (rst) begin
            ready_cycle <= 0;
            result_ready <= 1'b0;
        end
        else begin
            ready_cycle <= ready_cycle + 1;
            // Deterministic output backpressure.
            result_ready <= ((ready_cycle % 4) != 1);
        end
    end

    task automatic reset_dut;
        begin
            rst = 1'b1;
            vector_load_valid = 1'b0;
            vector_load_index = '0;
            vector_load_data = '0;
            start_valid = 1'b0;
            interaction_shift = '0;
            error_ready = 1'b0;
            repeat (5) @(posedge clk);
            rst = 1'b0;
            repeat (2) @(posedge clk);
        end
    endtask

    task automatic acknowledge_error;
        input [3:0] expected_code;
        begin
            timeout_cycles = 0;
            while (!error_valid && timeout_cycles < 100) begin
                @(posedge clk);
                timeout_cycles = timeout_cycles + 1;
            end
            if (!error_valid) begin
                $fatal(1, "Timed out waiting for error code %0d",
                       expected_code);
            end
            if (error_code !== expected_code) begin
                $fatal(1, "Error mismatch: expected %0d got %0d",
                       expected_code, error_code);
            end

            @(negedge clk);
            error_ready = 1'b1;
            @(posedge clk);
            @(negedge clk);
            error_ready = 1'b0;

            timeout_cycles = 0;
            while (error_valid && timeout_cycles < 100) begin
                @(posedge clk);
                timeout_cycles = timeout_cycles + 1;
            end
            if (error_valid) begin
                $fatal(1, "Error did not clear");
            end
        end
    endtask

    task automatic request_start;
        input [5:0] shift_value;
        begin
            @(negedge clk);
            interaction_shift = shift_value;
            start_valid = 1'b1;

            timeout_cycles = 0;
            while (!start_ready && timeout_cycles < 100) begin
                @(posedge clk);
                timeout_cycles = timeout_cycles + 1;
            end
            if (!start_ready) begin
                $fatal(1, "Timed out waiting for start_ready");
            end

            @(posedge clk);
            @(negedge clk);
            start_valid = 1'b0;
        end
    endtask

    task automatic load_vector;
        input [2:0] index;
        input signed [15:0] v0;
        input signed [15:0] v1;
        input signed [15:0] v2;
        input signed [15:0] v3;
        input signed [15:0] v4;
        input signed [15:0] v5;
        input signed [15:0] v6;
        input signed [15:0] v7;
        begin
            @(negedge clk);
            vector_load_index = index;
            vector_load_data = {
                v7, v6, v5, v4, v3, v2, v1, v0
            };
            vector_load_valid = 1'b1;

            timeout_cycles = 0;
            while (!vector_load_ready && timeout_cycles < 100) begin
                @(posedge clk);
                timeout_cycles = timeout_cycles + 1;
            end
            if (!vector_load_ready) begin
                $fatal(1, "Timed out loading vector %0d", index);
            end

            @(posedge clk);
            @(negedge clk);
            vector_load_valid = 1'b0;
            vector_load_data = '0;
        end
    endtask

    task automatic check_current_run;
        begin
            observed_count = 0;
            timeout_cycles = 0;

            while (observed_count < 18 && timeout_cycles < 3000) begin
                @(posedge clk);
                timeout_cycles = timeout_cycles + 1;

                if (result_valid && result_ready) begin
                    if (result_index !== observed_count[4:0]) begin
                        $fatal(
                            1,
                            "Result index mismatch: expected %0d got %0d",
                            observed_count,
                            result_index
                        );
                    end
                    if (result_data !== expected[observed_count]) begin
                        $fatal(
                            1,
                            "Result data mismatch at %0d: expected %0d got %0d",
                            observed_count,
                            expected[observed_count],
                            result_data
                        );
                    end
                    if (result_last !== (observed_count == 17)) begin
                        $fatal(
                            1,
                            "result_last mismatch at %0d",
                            observed_count
                        );
                    end
                    observed_count = observed_count + 1;
                end
            end

            if (observed_count != 18) begin
                $fatal(
                    1,
                    "Timed out: received %0d of 18 results",
                    observed_count
                );
            end

            timeout_cycles = 0;
            while (!done && timeout_cycles < 100) begin
                @(posedge clk);
                timeout_cycles = timeout_cycles + 1;
            end
            if (!done) begin
                $fatal(1, "Timed out waiting for done");
            end

            @(posedge clk);
            if (busy) begin
                $fatal(1, "Engine remained busy after done");
            end
        end
    endtask

    task automatic set_expected_case1;
        begin
            expected[0] = 16'sd1;
            expected[1] = 16'sd2;
            expected[2] = 16'sd3;
            expected[3] = 16'sd4;
            expected[4] = 16'sd5;
            expected[5] = 16'sd6;
            expected[6] = 16'sd7;
            expected[7] = 16'sd8;

            expected[8]  = -16'sd4;
            expected[9]  = 16'sd72;
            expected[10] = 16'sd0;
            expected[11] = -16'sd204;
            expected[12] = 16'sd4;
            expected[13] = -16'sd72;
            expected[14] = 16'sd192;
            expected[15] = 16'sd4;
            expected[16] = 16'sd104;
            expected[17] = -16'sd192;
        end
    endtask

    task automatic set_expected_case2;
        begin
            expected[0] = 16'sd32767;
            expected[1] = 16'sd32767;
            expected[2] = 16'sd32767;
            expected[3] = 16'sd32767;
            expected[4] = 16'sd32767;
            expected[5] = 16'sd32767;
            expected[6] = 16'sd32767;
            expected[7] = 16'sd32767;

            expected[8]  = 16'sd32767;
            expected[9]  = 16'sh8000;
            expected[10] = 16'sh8000;
            expected[11] = 16'sd16384;
            expected[12] = 16'sd16384;
            expected[13] = -16'sd16384;
            expected[14] = -16'sd16384;
            expected[15] = -16'sd16384;
            expected[16] = 16'sd16384;
            expected[17] = -16'sd1;
        end
    endtask

    initial begin
        clk = 1'b0;
        rst = 1'b1;
        vector_load_valid = 1'b0;
        vector_load_index = '0;
        vector_load_data = '0;
        start_valid = 1'b0;
        interaction_shift = '0;
        result_ready = 1'b0;
        error_ready = 1'b0;

        reset_dut();

        // Error path: starting before all five vectors are loaded.
        request_start(6'd0);
        acknowledge_error(4'd1);

        // Error path: invalid vector index.
        @(negedge clk);
        vector_load_index = 3'd7;
        vector_load_data = '0;
        vector_load_valid = 1'b1;
        @(posedge clk);
        @(negedge clk);
        vector_load_valid = 1'b0;
        acknowledge_error(4'd3);

        // Case 1: no shift, exact lower-triangle order.
        load_vector(3'd0, 1, 2, 3, 4, 5, 6, 7, 8);
        load_vector(3'd1, 1, 0, -1, 0, 1, 0, -1, 0);
        load_vector(3'd2, 2, 2, 2, 2, 2, 2, 2, 2);
        load_vector(3'd3, -1, -2, -3, -4, -5, -6, -7, -8);
        load_vector(3'd4, 10, 9, 8, 7, 6, 5, 4, 3);

        set_expected_case1();
        request_start(6'd0);
        check_current_run();

        // Error path: unsupported shift.
        request_start(6'd48);
        acknowledge_error(4'd2);

        // Case 2: INT16 saturation and ties-away-from-zero rounding.
        load_vector(
            3'd0,
            32767, 32767, 32767, 32767,
            32767, 32767, 32767, 32767
        );
        load_vector(
            3'd1,
            32767, 32767, 32767, 32767,
            32767, 32767, 32767, 32767
        );
        load_vector(
            3'd2,
            -32768, -32768, -32768, -32768,
            -32768, -32768, -32768, -32768
        );
        load_vector(3'd3, 1, 0, 0, 0, 0, 0, 0, 0);
        load_vector(3'd4, -1, 0, 0, 0, 0, 0, 0, 0);

        set_expected_case2();
        request_start(6'd1);
        check_current_run();

        // Repeat without reloading: vectors must persist.
        request_start(6'd1);
        check_current_run();

        $display(
            "tb_dlrm_feature_interaction_engine: PASS "
            "cases=3 outputs=54 errors=3"
        );
        $finish;
    end

endmodule
