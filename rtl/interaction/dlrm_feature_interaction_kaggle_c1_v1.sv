`timescale 1ns/1ps

// Kaggle DOT interaction engine, RTL-C1.
//
// This module is intentionally separate from
// rtl/interaction/dlrm_feature_interaction_engine.sv. That toy engine stays
// unchanged.
//
// Output contract B, matching facebookresearch/dlrm commit 6d75c84d
// with arch_interaction_op=dot and arch_interaction_itself=False:
//   * 27 signed INT16 vectors, 16 elements each.
//   * Load index 0 is the Bottom MLP output. Indices 1..26 are embeddings.
//     Arrival order may vary; the index selects the slot.
//   * 367 signed INT16 outputs, not 351:
//       index 0..15   = Bottom vector, element 0 first
//       index 16..366 = dot(V[i], V[j]) for i=1..26, j=0..i-1
//   * Pair 0 is (1,0). Pair 350 is (26,25). Output 366 is that last pair.
//   * result_last is high only while index 366 is valid. Backpressure may
//     hold that beat; it is not a second last beat.
//   * Each dot is 16 signed INT16 products accumulated in INT48.
//   * Runtime right shift uses nearest rounding, ties away from zero,
//     then saturates to signed INT16.
module dlrm_feature_interaction_kaggle_c1_v1 #(
    parameter integer VECTOR_COUNT = 27,
    parameter integer VECTOR_DIM   = 16,
    parameter integer INPUT_WIDTH  = 16,
    parameter integer ACC_WIDTH    = 48,
    parameter integer OUTPUT_WIDTH = 16,
    parameter integer SHIFT_WIDTH  =
        (ACC_WIDTH <= 1) ? 1 : $clog2(ACC_WIDTH + 1)
) (
    input  logic                                      clk,
    input  logic                                      rst,

    input  logic                                      vector_load_valid,
    output logic                                      vector_load_ready,
    input  logic [$clog2(VECTOR_COUNT)-1:0]          vector_load_index,
    input  logic [VECTOR_DIM*INPUT_WIDTH-1:0]        vector_load_data,

    input  logic                                      start_valid,
    output logic                                      start_ready,
    input  logic [SHIFT_WIDTH-1:0]                    interaction_shift,

    output logic                                      result_valid,
    input  logic                                      result_ready,
    output logic signed [OUTPUT_WIDTH-1:0]            result_data,
    output logic [$clog2(VECTOR_DIM+((VECTOR_COUNT*(VECTOR_COUNT-1))/2))-1:0]
                                                      result_index,
    output logic                                      result_last,

    output logic                                      busy,
    output logic                                      done,

    output logic                                      error_valid,
    input  logic                                      error_ready,
    output logic [3:0]                                error_code
);

    localparam integer PAIR_COUNT =
        (VECTOR_COUNT * (VECTOR_COUNT - 1)) / 2;
    localparam integer RESULT_COUNT = VECTOR_DIM + PAIR_COUNT;
    localparam integer INDEX_WIDTH =
        (VECTOR_COUNT <= 1) ? 1 : $clog2(VECTOR_COUNT);
    localparam integer DIM_WIDTH =
        (VECTOR_DIM <= 1) ? 1 : $clog2(VECTOR_DIM);
    localparam integer PAIR_WIDTH =
        (PAIR_COUNT <= 1) ? 1 : $clog2(PAIR_COUNT);
    localparam integer RESULT_INDEX_WIDTH =
        (RESULT_COUNT <= 1) ? 1 : $clog2(RESULT_COUNT);

    localparam logic [3:0] ERROR_NONE           = 4'd0;
    localparam logic [3:0] ERROR_MISSING_VECTOR = 4'd1;
    localparam logic [3:0] ERROR_BAD_SHIFT      = 4'd2;
    localparam logic [3:0] ERROR_BAD_VECTOR     = 4'd3;

    typedef enum logic [2:0] {
        STATE_IDLE,
        STATE_EMIT_BOTTOM,
        STATE_CALC_DOT,
        STATE_EMIT_DOT
    } state_t;

    state_t state;

    logic signed [INPUT_WIDTH-1:0]
        vector_mem [0:VECTOR_COUNT-1][0:VECTOR_DIM-1];
    logic [VECTOR_COUNT-1:0] vector_loaded;

    logic [SHIFT_WIDTH-1:0] shift_reg;
    logic [PAIR_WIDTH-1:0] pair_index_reg;
    logic [DIM_WIDTH-1:0] dim_index_reg;
    logic signed [ACC_WIDTH-1:0] accumulator_reg;

    logic result_valid_reg;
    logic signed [OUTPUT_WIDTH-1:0] result_data_reg;
    logic [RESULT_INDEX_WIDTH-1:0] result_index_reg;
    logic done_reg;

    logic error_valid_reg;
    logic [3:0] error_code_reg;

    logic [INDEX_WIDTH-1:0] pair_row_value;
    logic [INDEX_WIDTH-1:0] pair_column_value;
    logic signed [INPUT_WIDTH-1:0] pair_left_value;
    logic signed [INPUT_WIDTH-1:0] pair_right_value;
    logic signed [(2*INPUT_WIDTH)-1:0] pair_product;
    logic signed [ACC_WIDTH-1:0] pair_product_extended;
    logic signed [ACC_WIDTH-1:0] accumulator_with_product;

    integer reset_vector;
    integer reset_element;
    integer load_element;

    function automatic logic signed [OUTPUT_WIDTH-1:0] quantize_dot(
        input logic signed [ACC_WIDTH-1:0] value,
        input logic [SHIFT_WIDTH-1:0] shift_amount
    );
        logic negative;
        logic [ACC_WIDTH:0] magnitude;
        logic [ACC_WIDTH:0] rounded_magnitude;
        logic [ACC_WIDTH:0] rounding_bias;
        logic signed [ACC_WIDTH:0] shifted_value;
        logic signed [ACC_WIDTH:0] maximum_value;
        logic signed [ACC_WIDTH:0] minimum_value;
        begin
            negative = value[ACC_WIDTH-1];
            if (negative)
                magnitude = (~{{1{value[ACC_WIDTH-1]}}, value}) + 1'b1;
            else
                magnitude = {1'b0, value};

            rounding_bias = '0;
            if (shift_amount != 0)
                rounding_bias[shift_amount-1'b1] = 1'b1;
            rounded_magnitude = magnitude + rounding_bias;

            if (shift_amount == 0) begin
                shifted_value = negative
                    ? -$signed(rounded_magnitude)
                    :  $signed(rounded_magnitude);
            end else begin
                shifted_value = negative
                    ? -$signed(rounded_magnitude >> shift_amount)
                    :  $signed(rounded_magnitude >> shift_amount);
            end

            maximum_value =
                ({{ACC_WIDTH{1'b0}}, 1'b1} <<< (OUTPUT_WIDTH-1)) - 1'b1;
            minimum_value =
                -({{ACC_WIDTH{1'b0}}, 1'b1} <<< (OUTPUT_WIDTH-1));

            if (shifted_value > maximum_value)
                quantize_dot = {1'b0, {(OUTPUT_WIDTH-1){1'b1}}};
            else if (shifted_value < minimum_value)
                quantize_dot = {1'b1, {(OUTPUT_WIDTH-1){1'b0}}};
            else
                quantize_dot = shifted_value[OUTPUT_WIDTH-1:0];
        end
    endfunction

    assign vector_load_ready =
        (state == STATE_IDLE) && !error_valid_reg;
    assign start_ready =
        (state == STATE_IDLE) && !error_valid_reg && !vector_load_valid;

    assign result_valid = result_valid_reg;
    assign result_data = result_data_reg;
    assign result_index = result_index_reg;
    assign result_last =
        result_valid_reg &&
        (result_index_reg == RESULT_INDEX_WIDTH'(RESULT_COUNT-1));

    assign busy = (state != STATE_IDLE);
    assign done = done_reg;
    assign error_valid = error_valid_reg;
    assign error_code = error_code_reg;

    always_comb begin
        integer row_i;
        integer covered;
        integer pair_index_int;

        pair_row_value = '0;
        pair_column_value = '0;
        covered = 0;
        pair_index_int = pair_index_reg;
        for (row_i = 1; row_i < VECTOR_COUNT; row_i = row_i + 1) begin
            if ((pair_index_int >= covered) &&
                (pair_index_int < (covered + row_i))) begin
                pair_row_value = row_i[INDEX_WIDTH-1:0];
                pair_column_value = pair_index_int - covered;
            end
            covered = covered + row_i;
        end

        pair_left_value =
            vector_mem[pair_row_value][dim_index_reg];
        pair_right_value =
            vector_mem[pair_column_value][dim_index_reg];
        pair_product =
            $signed(pair_left_value) * $signed(pair_right_value);
        pair_product_extended = {
            {(ACC_WIDTH-(2*INPUT_WIDTH)){pair_product[(2*INPUT_WIDTH)-1]}},
            pair_product
        };
        accumulator_with_product =
            accumulator_reg + pair_product_extended;
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            state <= STATE_IDLE;
            vector_loaded <= '0;
            shift_reg <= '0;
            pair_index_reg <= '0;
            dim_index_reg <= '0;
            accumulator_reg <= '0;
            result_valid_reg <= 1'b0;
            result_data_reg <= '0;
            result_index_reg <= '0;
            done_reg <= 1'b0;
            error_valid_reg <= 1'b0;
            error_code_reg <= ERROR_NONE;
            for (reset_vector = 0;
                 reset_vector < VECTOR_COUNT;
                 reset_vector = reset_vector + 1) begin
                for (reset_element = 0;
                     reset_element < VECTOR_DIM;
                     reset_element = reset_element + 1) begin
                    vector_mem[reset_vector][reset_element] <= '0;
                end
            end
        end else begin
            if (error_valid_reg && error_ready) begin
                error_valid_reg <= 1'b0;
                error_code_reg <= ERROR_NONE;
            end

            case (state)
                STATE_IDLE: begin
                    result_valid_reg <= 1'b0;
                    if (!error_valid_reg && vector_load_valid) begin
                        done_reg <= 1'b0;
                        if (vector_load_index >= VECTOR_COUNT) begin
                            error_valid_reg <= 1'b1;
                            error_code_reg <= ERROR_BAD_VECTOR;
                        end else begin
                            for (load_element = 0;
                                 load_element < VECTOR_DIM;
                                 load_element = load_element + 1) begin
                                vector_mem[vector_load_index][load_element] <=
                                    vector_load_data[
                                        load_element*INPUT_WIDTH +: INPUT_WIDTH];
                            end
                            vector_loaded[vector_load_index] <= 1'b1;
                        end
                    end else if (!error_valid_reg && start_valid) begin
                        done_reg <= 1'b0;
                        if (vector_loaded != {VECTOR_COUNT{1'b1}}) begin
                            error_valid_reg <= 1'b1;
                            error_code_reg <= ERROR_MISSING_VECTOR;
                        end else if (interaction_shift >= ACC_WIDTH) begin
                            error_valid_reg <= 1'b1;
                            error_code_reg <= ERROR_BAD_SHIFT;
                        end else begin
                            shift_reg <= interaction_shift;
                            pair_index_reg <= '0;
                            dim_index_reg <= '0;
                            accumulator_reg <= '0;
                            result_index_reg <= '0;
                            result_data_reg <= vector_mem[0][0];
                            result_valid_reg <= 1'b1;
                            state <= STATE_EMIT_BOTTOM;
                        end
                    end
                end

                STATE_EMIT_BOTTOM: begin
                    if (result_valid_reg && result_ready) begin
                        if (result_index_reg ==
                            RESULT_INDEX_WIDTH'(VECTOR_DIM-1)) begin
                            result_valid_reg <= 1'b0;
                            pair_index_reg <= '0;
                            dim_index_reg <= '0;
                            accumulator_reg <= '0;
                            state <= STATE_CALC_DOT;
                        end else begin
                            result_index_reg <= result_index_reg + 1'b1;
                            result_data_reg <=
                                vector_mem[0][
                                    DIM_WIDTH'(result_index_reg + 1'b1)];
                        end
                    end
                end

                STATE_CALC_DOT: begin
                    if (dim_index_reg == DIM_WIDTH'(VECTOR_DIM-1)) begin
                        result_index_reg <=
                            RESULT_INDEX_WIDTH'(VECTOR_DIM) +
                            RESULT_INDEX_WIDTH'(pair_index_reg);
                        result_data_reg <= quantize_dot(
                            accumulator_with_product, shift_reg);
                        result_valid_reg <= 1'b1;
                        state <= STATE_EMIT_DOT;
                    end else begin
                        accumulator_reg <= accumulator_with_product;
                        dim_index_reg <= dim_index_reg + 1'b1;
                    end
                end

                STATE_EMIT_DOT: begin
                    if (result_valid_reg && result_ready) begin
                        if (pair_index_reg == PAIR_WIDTH'(PAIR_COUNT-1)) begin
                            result_valid_reg <= 1'b0;
                            done_reg <= 1'b1;
                            state <= STATE_IDLE;
                        end else begin
                            result_valid_reg <= 1'b0;
                            pair_index_reg <= pair_index_reg + 1'b1;
                            dim_index_reg <= '0;
                            accumulator_reg <= '0;
                            state <= STATE_CALC_DOT;
                        end
                    end
                end

                default: begin
                    state <= STATE_IDLE;
                    result_valid_reg <= 1'b0;
                    error_valid_reg <= 1'b1;
                    error_code_reg <= ERROR_BAD_VECTOR;
                end
            endcase
        end
    end

    initial begin
        if (VECTOR_COUNT != 27 || VECTOR_DIM != 16)
            $error("C1 module is fixed to the Kaggle 27x16 contract");
        if (PAIR_COUNT != 351 || RESULT_COUNT != 367)
            $error("C1 pair or result count is not the Kaggle contract");
        if (RESULT_INDEX_WIDTH < 9)
            $error("C1 result index is narrower than 9 bits");
        if (ACC_WIDTH < 36)
            $error("C1 accumulator is below the 36-bit signed bound");
        if ((2*INPUT_WIDTH) > ACC_WIDTH)
            $error("C1 product does not fit in the accumulator");
    end

endmodule
