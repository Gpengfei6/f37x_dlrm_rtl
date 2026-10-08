`timescale 1ns/1ps

// KDOT_INTERACTION_C1 dynamic test.
// Expected values come from tb/ref/kaggle_interaction_c1_ref_v1.py.
// Contract B: 367 outputs. Index 0..15 is Bottom. Index 16..366 is the
// 351 dots. Output 366 is pair (26,25), pair index 350.
// GOLDEN_VALUE_26_25 = 156 is that dot's integer result in the tail case,
// not the pair index.
module tb_dlrm_feature_interaction_kaggle_c1_v1;
    localparam integer VECTOR_COUNT = 27;
    localparam integer VECTOR_DIM = 16;
    localparam integer RESULT_COUNT = 367;
    localparam integer TIMEOUT = 400000;
    localparam integer CASE_ZERO = 0;
    localparam integer CASE_RANDOM = 1;
    localparam integer CASE_POS = 2;
    localparam integer CASE_NEG = 3;
    localparam integer CASE_POS16 = 4;
    localparam integer CASE_NEG16 = 5;
    localparam integer CASE_TIE_POS = 6;
    localparam integer CASE_TIE_NEG = 7;
    localparam integer CASE_TIE_POS15 = 8;
    localparam integer CASE_TIE_NEG15 = 9;
    localparam integer CASE_SHIFT47 = 10;
    localparam integer CASE_ORDER = 11;
    localparam integer CASE_TAIL = 12;

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

    integer mismatches;
    integer vector_index;
    integer observed;
    integer last_handshakes;
    integer cycles;
    integer stall_seen;
    bit beat_open;
    logic signed [15:0] beat_data;
    logic [8:0] beat_index;
    logic beat_last;
    integer case_cursor;

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
            beat_open = 1'b0;
            repeat (4) @(posedge clk);
            @(negedge clk);
            rst = 1'b0;
            @(negedge clk);
            if (result_valid !== 1'b0 || done !== 1'b0 || busy !== 1'b0)
                $fatal(1, "reset did not return the engine to idle");
        end
    endtask

    task automatic load_case(
        input integer selected_case,
        input integer reverse_order
    );
        integer step;
        integer which;
        begin
            for (step = 0; step < VECTOR_COUNT; step = step + 1) begin
                which = reverse_order ? (VECTOR_COUNT - 1 - step) : step;
                vector_load_valid = 1'b1;
                vector_load_index = which[4:0];
                vector_load_data = pack_vector(selected_case, which);
                while (!vector_load_ready) @(posedge clk);
                @(posedge clk);
            end
            vector_load_valid = 1'b0;
        end
    endtask

    task automatic score_beat(
        input integer selected_case
    );
        begin
            if (result_index !== observed[8:0]) begin
                mismatches = mismatches + 1;
                $fatal(1, "index case %0d got %0d expected %0d",
                    selected_case, result_index, observed);
            end
            if (result_data !== c1_expected[selected_case][observed]) begin
                mismatches = mismatches + 1;
                $fatal(1, "data case %0d index %0d got %0d expected %0d",
                    selected_case, observed, result_data,
                    c1_expected[selected_case][observed]);
            end
            if (result_last !== (observed == RESULT_COUNT - 1))
                $fatal(1, "result_last case %0d index %0d", selected_case, observed);
            if (result_last)
                last_handshakes = last_handshakes + 1;
            observed = observed + 1;
        end
    endtask

    // mode 0: accept every beat immediately
    // mode 1: hold each beat for (index % 4) samples, then accept
    // mode 2: hold only the final beat for 8 samples, then accept
    task automatic collect_case(
        input integer selected_case,
        input integer mode
    );
        integer hold_count;
        integer accept;
        begin
            observed = 0;
            last_handshakes = 0;
            beat_open = 1'b0;
            hold_count = 0;
            cycles = 0;
            result_ready = 1'b0;
            interaction_shift = c1_shift[selected_case];
            start_valid = 1'b1;
            while (!start_ready) @(posedge clk);
            @(posedge clk);
            start_valid = 1'b0;

            while (observed < RESULT_COUNT) begin
                @(negedge clk);
                cycles = cycles + 1;
                if (cycles > TIMEOUT)
                    $fatal(1, "timeout case %0d observed %0d", selected_case, observed);
                if (!result_valid) begin
                    beat_open = 1'b0;
                    result_ready = 1'b0;
                end else begin
                    if (beat_open) begin
                        if (result_data !== beat_data ||
                            result_index !== beat_index ||
                            result_last !== beat_last) begin
                            $fatal(1, "beat changed while ready was low, case %0d",
                                selected_case);
                        end
                        hold_count = hold_count + 1;
                    end else begin
                        beat_data = result_data;
                        beat_index = result_index;
                        beat_last = result_last;
                        beat_open = 1'b1;
                        hold_count = 0;
                    end
                    accept = 1;
                    if (mode == 1)
                        accept = (hold_count >= (result_index % 4));
                    else if (mode == 2 && result_index == 9'd366)
                        accept = (hold_count >= 8);
                    if (accept) begin
                        score_beat(selected_case);
                        result_ready = 1'b1;
                        beat_open = 1'b0;
                    end else begin
                        result_ready = 1'b0;
                        if (mode == 2 && result_index == 9'd366)
                            stall_seen = stall_seen + 1;
                    end
                end
            end
            @(posedge clk);
            @(negedge clk);
            if (done !== 1'b1 || result_valid !== 1'b0)
                $fatal(1, "done/valid after last beat, case %0d done=%0b valid=%0b",
                    selected_case, done, result_valid);
            if (last_handshakes != 1)
                $fatal(1, "result_last handshakes=%0d case %0d",
                    last_handshakes, selected_case);
            result_ready = 1'b0;
        end
    endtask

    initial begin
        mismatches = 0;
        stall_seen = 0;
        if (C1_CASE_COUNT != 13)
            $fatal(1, "unexpected golden case count %0d", C1_CASE_COUNT);
        if (c1_expected[CASE_POS16][16] !== 16'sd960)
            $fatal(1, "16 positive products golden is not 960");
        if (c1_expected[CASE_NEG16][16] !== -16'sd960)
            $fatal(1, "16 negative products golden is not -960");
        if (c1_expected[CASE_TIE_POS][16] !== 16'sd1 ||
            c1_expected[CASE_TIE_NEG][16] !== -16'sd1)
            $fatal(1, "shift-1 tie golden drifted");
        if (c1_expected[CASE_TIE_POS15][16] !== 16'sd1 ||
            c1_expected[CASE_TIE_NEG15][16] !== -16'sd1)
            $fatal(1, "shift-15 tie golden drifted");
        if (c1_expected[CASE_ORDER][16] !== 16'sd2)
            $fatal(1, "first pair (1,0) golden is not 2");
        if (c1_expected[CASE_ORDER][191] !== 16'sd100)
            $fatal(1, "middle pair (19,4) golden is not 100");
        if (c1_expected[CASE_ORDER][366] !== 16'sd702)
            $fatal(1, "last pair identity golden is not 702");
        if (c1_expected[CASE_TAIL][366] !== 16'sd156)
            $fatal(1, "GOLDEN_VALUE_26_25 is not 156");
        if (c1_expected[CASE_POS][16] !== 16'sd32767)
            $fatal(1, "positive saturation golden drifted");
        if (c1_expected[CASE_NEG][0] !== 16'sh8000 ||
            c1_expected[CASE_NEG][16] !== 16'sd32767)
            $fatal(1, "negative extreme golden drifted");

        $display("CONTRACT=B");
        $display("BOTTOM_INDEX=0..15");
        $display("INTERACTION_INDEX=16..366");
        $display("LAST_PAIR=(26,25)");
        $display("LAST_PAIR_INDEX=350");
        $display("LAST_OUTPUT_INDEX=366");
        $display("GOLDEN_VALUE_26_25=%0d", c1_expected[CASE_TAIL][366]);
        $display("GOLDEN_NOTE=156 is the tail-case dot product, not a pair index");

        apply_reset();
        for (case_cursor = 0; case_cursor < C1_CASE_COUNT; case_cursor = case_cursor + 1) begin
            load_case(case_cursor, 0);
            collect_case(case_cursor, 0);
            $display("PASS always_ready case %0d", case_cursor);
        end

        load_case(CASE_ZERO, 1);
        collect_case(CASE_ZERO, 0);
        $display("PASS reverse_load");

        load_case(CASE_RANDOM, 0);
        collect_case(CASE_RANDOM, 1);
        $display("PASS random_pause");

        load_case(CASE_ORDER, 0);
        collect_case(CASE_ORDER, 2);
        if (stall_seen < 8)
            $fatal(1, "final beat was not paused, stalls=%0d", stall_seen);
        $display("PASS final_beat_pause stalls=%0d", stall_seen);

        load_case(CASE_ORDER, 0);
        collect_case(CASE_ORDER, 0);
        collect_case(CASE_ORDER, 0);
        $display("PASS second_request_same_vectors");

        load_case(CASE_TAIL, 0);
        collect_case(CASE_TAIL, 0);
        $display("PASS second_request_new_vectors");

        load_case(CASE_RANDOM, 0);
        interaction_shift = c1_shift[CASE_RANDOM];
        start_valid = 1'b1;
        result_ready = 1'b0;
        while (!start_ready) @(posedge clk);
        @(posedge clk);
        start_valid = 1'b0;
        cycles = 0;
        while (!(result_valid && result_index == 9'd4)) begin
            @(negedge clk);
            cycles = cycles + 1;
            if (cycles > TIMEOUT)
                $fatal(1, "reset stimulus did not reach index 4");
        end
        rst = 1'b1;
        result_ready = 1'b0;
        repeat (4) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;
        @(negedge clk);
        if (result_valid !== 1'b0 || done !== 1'b0 || busy !== 1'b0)
            $fatal(1, "restart after reset was not idle");
        load_case(CASE_ZERO, 0);
        collect_case(CASE_ZERO, 0);
        $display("PASS reset_restart");

        load_case(CASE_ZERO, 0);
        interaction_shift = 6'd48;
        start_valid = 1'b1;
        result_ready = 1'b0;
        while (!start_ready) @(posedge clk);
        @(posedge clk);
        start_valid = 1'b0;
        cycles = 0;
        while (!error_valid) begin
            @(negedge clk);
            if (result_valid)
                $fatal(1, "illegal shift produced a result");
            cycles = cycles + 1;
            if (cycles > 20)
                $fatal(1, "illegal shift did not raise error");
        end
        if (error_code !== 4'd2)
            $fatal(1, "illegal shift error code %0d", error_code);
        error_ready = 1'b1;
        @(posedge clk);
        $display("PASS bad_shift");

        if (mismatches != 0)
            $fatal(1, "mismatches %0d", mismatches);
        $display("KDOT_INTERACTION_C1_351PAIR=PASS");
        $display("KDOT_INTERACTION_C1_ORDER=PASS");
        $display("KDOT_INTERACTION_C1_NUMERIC=PASS");
        $display("KDOT_INTERACTION_C1_BACKPRESSURE=PASS");
        $display("KDOT_INTERACTION_C1_RESET=PASS");
        $display("KDOT_INTERACTION_C1_PASS");
        $finish;
    end
endmodule
