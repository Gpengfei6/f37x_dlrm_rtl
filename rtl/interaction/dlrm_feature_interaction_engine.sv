`timescale 1ns/1ps

// Stage 2N-A1: fixed-shape DLRM feature-interaction engine.
//
// Contract:
//   * Five signed INT16 vectors, each with eight elements.
//   * Vector 0 is the Bottom-MLP output.
//   * Vectors 1..4 are embedding vectors supplied by the host.
//   * Eighteen signed INT16 outputs:
//       output[0..7]   = vector 0 unchanged
//       output[8..17]  = lower-triangle dot products in NumPy
//                        np.tril_indices(5, k=-1) order:
//                        (1,0), (2,0), (2,1), (3,0), (3,1),
//                        (3,2), (4,0), (4,1), (4,2), (4,3)
//   * Dot products use signed 48-bit accumulation.
//   * Runtime right shift uses nearest rounding, ties away from zero.
//   * Shifted values saturate to signed INT16.
//
// This module is intentionally standalone in Stage 2N-A1. It does not alter
// the existing MLP controller or F37X AXI-Lite wrapper.
module dlrm_feature_interaction_engine #(
    parameter integer VECTOR_COUNT = 5,
    parameter integer VECTOR_DIM = 8,
    parameter integer INPUT_WIDTH = 16,
    parameter integer ACC_WIDTH = 48,
    parameter integer OUTPUT_WIDTH = 16,
    parameter integer SHIFT_WIDTH =
        (ACC_WIDTH <= 1) ? 1 : $clog2(ACC_WIDTH + 1)
) (
    input  logic                             clk,
    input  logic                             rst,

    input  logic                             vector_load_valid,
    output logic                             vector_load_ready,
    input  logic [2:0]                       vector_load_index,
    input  logic [VECTOR_DIM*INPUT_WIDTH-1:0] vector_load_data,

    input  logic                             start_valid,
    output logic                             start_ready,
    input  logic [SHIFT_WIDTH-1:0]           interaction_shift,

    output logic                             result_valid,
    input  logic                             result_ready,
    output logic signed [OUTPUT_WIDTH-1:0]   result_data,
    output logic [4:0]                       result_index,
    output logic                             result_last,

    output logic                             busy,
    output logic                             done,

    output logic                             error_valid,
    input  logic                             error_ready,
    output logic [3:0]                       error_code
);

    localparam integer PAIR_COUNT = 10;

    localparam logic [3:0] ERROR_NONE            = 4'd0;
    localparam logic [3:0] ERROR_MISSING_VECTOR  = 4'd1;
    localparam logic [3:0] ERROR_BAD_SHIFT       = 4'd2;
    localparam logic [3:0] ERROR_BAD_VECTOR      = 4'd3;

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
    logic [3:0] pair_index_reg;
    logic [3:0] dim_index_reg;
    logic signed [ACC_WIDTH-1:0] accumulator_reg;

    logic result_valid_reg;
    logic signed [OUTPUT_WIDTH-1:0] result_data_reg;
    logic [4:0] result_index_reg;
    logic done_reg;

    logic error_valid_reg;
    logic [3:0] error_code_reg;

    logic [2:0] pair_row_value;
    logic [2:0] pair_column_value;
    logic signed [INPUT_WIDTH-1:0] pair_left_value;
    logic signed [INPUT_WIDTH-1:0] pair_right_value;
    logic signed [(2*INPUT_WIDTH)-1:0] pair_product;
    logic signed [ACC_WIDTH-1:0] pair_product_extended;
    logic signed [ACC_WIDTH-1:0] accumulator_with_product;

    integer reset_vector;
    integer reset_element;
    integer load_element;

    function automatic logic [2:0] pair_row(
        input logic [3:0] pair_index
    );
        begin
            case (pair_index)
                4'd0: pair_row = 3'd1;
                4'd1: pair_row = 3'd2;
                4'd2: pair_row = 3'd2;
                4'd3: pair_row = 3'd3;
                4'd4: pair_row = 3'd3;
                4'd5: pair_row = 3'd3;
                4'd6: pair_row = 3'd4;
                4'd7: pair_row = 3'd4;
                4'd8: pair_row = 3'd4;
                default: pair_row = 3'd4;
            endcase
        end
    endfunction

    function automatic logic [2:0] pair_column(
        input logic [3:0] pair_index
    );
        begin
            case (pair_index)
                4'd0: pair_column = 3'd0;
                4'd1: pair_column = 3'd0;
                4'd2: pair_column = 3'd1;
                4'd3: pair_column = 3'd0;
                4'd4: pair_column = 3'd1;
                4'd5: pair_column = 3'd2;
                4'd6: pair_column = 3'd0;
                4'd7: pair_column = 3'd1;
                4'd8: pair_column = 3'd2;
                default: pair_column = 3'd3;
            endcase
        end
    endfunction

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

            if (negative) begin
                magnitude =
                    (~{{1{value[ACC_WIDTH-1]}}, value}) + 1'b1;
            end
            else begin
                magnitude = {1'b0, value};
            end

            rounding_bias = '0;
            if (shift_amount != 0) begin
                rounding_bias[shift_amount-1'b1] = 1'b1;
            end

            rounded_magnitude = magnitude + rounding_bias;

            if (shift_amount == 0) begin
                shifted_value = negative
                    ? -$signed(rounded_magnitude)
                    :  $signed(rounded_magnitude);
            end
            else begin
                shifted_value = negative
                    ? -$signed(rounded_magnitude >> shift_amount)
                    :  $signed(rounded_magnitude >> shift_amount);
            end

            maximum_value =
                ({{ACC_WIDTH{1'b0}}, 1'b1}
                 <<< (OUTPUT_WIDTH-1)) - 1'b1;
            minimum_value =
                -({{ACC_WIDTH{1'b0}}, 1'b1}
                  <<< (OUTPUT_WIDTH-1));

            if (shifted_value > maximum_value) begin
                quantize_dot =
                    {1'b0, {(OUTPUT_WIDTH-1){1'b1}}};
            end
            else if (shifted_value < minimum_value) begin
                quantize_dot =
                    {1'b1, {(OUTPUT_WIDTH-1){1'b0}}};
            end
            else begin
                quantize_dot = shifted_value[OUTPUT_WIDTH-1:0];
            end
        end
    endfunction

    assign vector_load_ready =
        (state == STATE_IDLE) && !error_valid_reg;
    assign start_ready =
        (state == STATE_IDLE) && !error_valid_reg &&
        !vector_load_valid;

    assign result_valid = result_valid_reg;
    assign result_data = result_data_reg;
    assign result_index = result_index_reg;
    assign result_last =
        result_valid_reg && (result_index_reg == 5'd17);

    assign busy = (state != STATE_IDLE);
    assign done = done_reg;

    assign error_valid = error_valid_reg;
    assign error_code = error_code_reg;

    always_comb begin
        pair_row_value = pair_row(pair_index_reg);
        pair_column_value = pair_column(pair_index_reg);

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
        end
        else begin
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
                        end
                        else begin
                            for (load_element = 0;
                                 load_element < VECTOR_DIM;
                                 load_element = load_element + 1) begin
                                vector_mem
                                    [vector_load_index]
                                    [load_element] <=
                                    vector_load_data[
                                        load_element*INPUT_WIDTH
                                        +: INPUT_WIDTH
                                    ];
                            end
                            vector_loaded[vector_load_index] <= 1'b1;
                        end
                    end
                    else if (!error_valid_reg && start_valid) begin
                        done_reg <= 1'b0;
                        if (vector_loaded != {VECTOR_COUNT{1'b1}}) begin
                            error_valid_reg <= 1'b1;
                            error_code_reg <= ERROR_MISSING_VECTOR;
                        end
                        else if (interaction_shift >= ACC_WIDTH) begin
                            error_valid_reg <= 1'b1;
                            error_code_reg <= ERROR_BAD_SHIFT;
                        end
                        else begin
                            shift_reg <= interaction_shift;
                            pair_index_reg <= 4'd0;
                            dim_index_reg <= 4'd0;
                            accumulator_reg <= '0;

                            result_index_reg <= 5'd0;
                            result_data_reg <= vector_mem[0][0];
                            result_valid_reg <= 1'b1;
                            state <= STATE_EMIT_BOTTOM;
                        end
                    end
                end

                STATE_EMIT_BOTTOM: begin
                    if (result_valid_reg && result_ready) begin
                        if (result_index_reg == 5'd7) begin
                            result_valid_reg <= 1'b0;
                            pair_index_reg <= 4'd0;
                            dim_index_reg <= 4'd0;
                            accumulator_reg <= '0;
                            state <= STATE_CALC_DOT;
                        end
                        else begin
                            result_index_reg <= result_index_reg + 1'b1;
                            result_data_reg <=
                                vector_mem[0][result_index_reg + 1'b1];
                        end
                    end
                end

                STATE_CALC_DOT: begin
                    if (dim_index_reg == VECTOR_DIM-1) begin
                        result_index_reg <=
                            5'd8 + pair_index_reg;
                        result_data_reg <= quantize_dot(
                            accumulator_with_product,
                            shift_reg
                        );
                        result_valid_reg <= 1'b1;
                        state <= STATE_EMIT_DOT;
                    end
                    else begin
                        accumulator_reg <= accumulator_with_product;
                        dim_index_reg <= dim_index_reg + 1'b1;
                    end
                end

                STATE_EMIT_DOT: begin
                    if (result_valid_reg && result_ready) begin
                        if (pair_index_reg == PAIR_COUNT-1) begin
                            result_valid_reg <= 1'b0;
                            done_reg <= 1'b1;
                            state <= STATE_IDLE;
                        end
                        else begin
                            result_valid_reg <= 1'b0;
                            pair_index_reg <= pair_index_reg + 1'b1;
                            dim_index_reg <= 4'd0;
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

endmodule
