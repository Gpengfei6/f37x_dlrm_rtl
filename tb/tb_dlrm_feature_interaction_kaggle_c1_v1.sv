`timescale 1ns/1ps

module tb_dlrm_feature_interaction_kaggle_c1_v1;
    localparam integer VECTOR_COUNT = 27;
    localparam integer VECTOR_DIM = 16;
    localparam integer RESULT_COUNT = 367;
    localparam integer TIMEOUT = 200000;

    logic clk;
    logic rst;
    logic vector_load_valid;
    logic vector_load_ready;
    logic [4:0] vector_load_index;
    logic [VECTOR_DIM*16-1:0] vector_load_data;
    logic start_valid;
    logic start_ready;
    logic [5:0] interaction_shift;
    logic result_valid;
    logic result_ready;
    logic signed [15:0] result_data;
    logic [8:0] result_index;
    logic result_last;
    logic busy;
    logic done;
    logic error_valid;
    logic error_ready;
    logic [3:0] error_code;

    integer observed;
    integer mismatches;
    integer cycles;
    integer case_index;
    integer vector_index;
    integer element_index;
    integer stall;

    `include "generated/kaggle_c1_cases_v1.svh"

    dlrm_feature_interaction_kaggle_c1_v1 dut (
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

    initial clk = 1'b0;
    always #5 clk = ~clk;

    function automatic logic [VECTOR_DIM*16-1:0] pack_vector(
        input integer selected_case,
        input integer selected_vector
    );
        integer element;
        begin
            pack_vector = '0;
            for (element = 0; element < VECTOR_DIM; element = element + 1)
                pack_vector[element*16 +: 16] =
                    c1_vec[selected_case][selected_vector][element];
        end
    endfunction

    task automatic apply_reset;
        begin
            rst = 1'b1;
            vector_load_valid = 1'b0;
            vector_load_index = '0;
            vector_load_data = '0;
            start_valid = 1'b0;
            interaction_shift = '0;
            result_ready = 1'b0;
            error_ready = 1'b1;
            repeat (4) @(posedge clk);
            rst = 1'b0;
            @(posedge clk);
        end
    endtask

    task automatic load_case(input integer selected_case);
        begin
            for (vector_index = 0;
                 vector_index < VECTOR_COUNT;
                 vector_index = vector_index + 1) begin
                vector_load_valid = 1'b1;
                vector_load_index = vector_index[4:0];
                vector_load_data = pack_vector(selected_case, vector_index);
                while (!vector_load_ready) @(posedge clk);
                @(posedge clk);
            end
            vector_load_valid = 1'b0;
        end
    endtask

    task automatic collect_case(
        input integer selected_case,
        input integer stall_mode
    );
        begin
            observed = 0;
            cycles = 0;
            interaction_shift = c1_shift[selected_case];
            start_valid = 1'b1;
            result_ready = 1'b0;
            cycles = 0;
            while (!start_ready) begin
                @(posedge clk);
                cycles = cycles + 1;
                if (cycles > TIMEOUT)
                    $fatal(1, "start timeout on case %0d", selected_case);
            end
            @(posedge clk);
            start_valid = 1'b0;

            while (observed < RESULT_COUNT) begin
                @(posedge clk);
                cycles = cycles + 1;
                if (cycles > TIMEOUT)
                    $fatal(1, "result timeout on case %0d", selected_case);

                if (stall_mode == 0)
                    result_ready = 1'b1;
                else if (stall_mode == 1)
                    result_ready = (cycles % 5) == 0;
                else
                    result_ready = (cycles % 3) != 0;

                if (result_valid && result_ready) begin
                    if (result_index !== observed[8:0]) begin
                        mismatches = mismatches + 1;
                        $display(
                            "INDEX case %0d got %0d expected %0d",
                            selected_case, result_index, observed
                        );
                    end
                    if (result_data !== c1_expected[selected_case][observed]) begin
                        mismatches = mismatches + 1;
                        $display(
                            "DATA case %0d index %0d got %0d expected %0d",
                            selected_case, observed, result_data,
                            c1_expected[selected_case][observed]
                        );
                    end
                    if (result_last !== (observed == RESULT_COUNT-1)) begin
                        mismatches = mismatches + 1;
                        $display("LAST case %0d index %0d", selected_case, observed);
                    end
                    observed = observed + 1;
                end
            end
            result_ready = 1'b1;
            cycles = 0;
            while (!done) begin
                @(posedge clk);
                cycles = cycles + 1;
                if (cycles > 20)
                    $fatal(1, "done timeout on case %0d", selected_case);
            end
            result_ready = 1'b0;
        end
    endtask

    initial begin
        mismatches = 0;
        if (c1_expected[2][16] !== 16'sd32767)
            $fatal(1, "positive extreme golden is not saturated INT16");
        if (c1_expected[3][0] !== 16'sh8000)
            $fatal(1, "negative bottom golden drifted");
        if (c1_expected[3][16] !== 16'sd32767)
            $fatal(1, "negative products are positive and must saturate high");
        if (c1_expected[4][366] !== 16'sd156)
            $fatal(1, "tail pair (26,25) golden is not 156");
        if (c1_expected[5][0] !== 16'sd1 || c1_expected[5][16] !== 16'sd1)
            $fatal(1, "rounding tie golden is not 1");
        if (c1_expected[0][366] !== 16'sd0)
            $fatal(1, "zero golden drifted");

        apply_reset();
        for (case_index = 0; case_index < C1_CASE_COUNT; case_index = case_index + 1) begin
            load_case(case_index);
            collect_case(case_index, case_index % 3);
        end

        load_case(0);
        collect_case(0, 0);
        load_case(4);
        collect_case(4, 1);

        load_case(1);
        interaction_shift = c1_shift[1];
        start_valid = 1'b1;
        result_ready = 1'b0;
        while (!start_ready) @(posedge clk);
        @(posedge clk);
        start_valid = 1'b0;
        stall = 0;
        for (cycles = 0; cycles < 40; cycles = cycles + 1) begin
            @(posedge clk);
            if (result_valid && result_ready)
                stall = stall + 1;
        end
        if (stall != 0)
            $fatal(1, "backpressure accepted %0d results", stall);
        apply_reset();
        load_case(0);
        collect_case(0, 2);

        if (mismatches != 0)
            $fatal(1, "C1 mismatches: %0d", mismatches);
        $display("C1_PASS cases=%0d results_per_case=%0d", C1_CASE_COUNT, RESULT_COUNT);
        $finish;
    end
endmodule
