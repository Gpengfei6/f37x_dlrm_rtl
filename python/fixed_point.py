"""Bit-accurate fixed-point helpers shared by vector generation and reference code."""


def signed_bounds(width):
    if width <= 0:
        raise ValueError("width must be positive")
    return -(1 << (width - 1)), (1 << (width - 1)) - 1


def wrap_signed(value, width):
    """Reduce an integer to a signed two's-complement value of *width* bits."""
    mask = (1 << width) - 1
    raw = int(value) & mask
    sign = 1 << (width - 1)
    return raw - (1 << width) if raw & sign else raw


def saturate_signed(value, width):
    minimum, maximum = signed_bounds(width)
    return min(max(int(value), minimum), maximum)


def round_shift_nearest_away(value, shift):
    """Signed right shift, rounding nearest with exact ties away from zero."""
    if shift < 0:
        raise ValueError("shift must be non-negative")
    value = int(value)
    if shift == 0:
        return value
    rounded_magnitude = (abs(value) + (1 << (shift - 1))) >> shift
    return -rounded_magnitude if value < 0 else rounded_magnitude


def saturating_round(value, in_width, out_width, shift):
    """Mirror saturating_round.sv, including interpretation of the input width."""
    value = wrap_signed(value, in_width)
    return saturate_signed(round_shift_nearest_away(value, shift), out_width)


def relu_quant(value, in_width, out_width, shift):
    quantized = saturating_round(value, in_width, out_width, shift)
    return max(0, quantized)


def embedding_aggregate(rows, aggregate_width):
    if not rows:
        raise ValueError("at least one embedding row is required")
    dimension = len(rows[0])
    if any(len(row) != dimension for row in rows):
        raise ValueError("embedding rows have inconsistent dimensions")
    result = [0] * dimension
    for row in rows:
        for index, value in enumerate(row):
            result[index] = wrap_signed(result[index] + value, aggregate_width)
    return result


def dot_product(inputs, weights, bias, acc_width):
    if len(inputs) != len(weights):
        raise ValueError("input/weight length mismatch")
    accumulator = wrap_signed(bias, acc_width)
    for input_value, weight_value in zip(inputs, weights):
        accumulator = wrap_signed(
            accumulator + int(input_value) * int(weight_value), acc_width
        )
    return accumulator


def dense_relu(inputs, weights, biases, acc_width, output_width, output_shift):
    if len(weights) != len(biases):
        raise ValueError("weight-row/bias length mismatch")
    accumulators = []
    outputs = []
    for weight_row, bias in zip(weights, biases):
        accumulator = dot_product(inputs, weight_row, bias, acc_width)
        accumulators.append(accumulator)
        outputs.append(relu_quant(accumulator, acc_width, output_width, output_shift))
    return accumulators, outputs


def encode_twos_complement(value, width):
    return int(value) & ((1 << width) - 1)


def decode_twos_complement(value, width):
    return wrap_signed(value, width)

