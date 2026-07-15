"""Bit-accurate reference functions for the Stage-2A vector PE baseline."""

from dataclasses import dataclass

from fixed_point import round_shift_nearest_away, saturate_signed, wrap_signed


SUPPORTED_PE_COUNTS = (4, 8, 16, 32)


@dataclass(frozen=True)
class DenseJob:
    in_dim: int
    out_dim: int
    input_buffer_select: int = 0
    output_buffer_select: int = 1
    weight_offset: int = 0
    bias_offset: int = 0
    output_shift: int = 4
    relu_enable: bool = True


def validate_job(job, max_in_dim=1024, max_out_dim=1024, acc_width=48):
    """Return ``(valid, error_name)`` using the RTL descriptor rules."""
    if job.in_dim <= 0 or job.in_dim > max_in_dim:
        return False, "BAD_DIMENSION"
    if job.out_dim <= 0 or job.out_dim > max_out_dim:
        return False, "BAD_DIMENSION"
    if job.input_buffer_select not in (0, 1):
        return False, "BAD_BUFFER"
    if job.output_buffer_select not in (0, 1):
        return False, "BAD_BUFFER"
    if job.input_buffer_select == job.output_buffer_select:
        return False, "BUFFER_ALIAS"
    if job.output_shift < 0 or job.output_shift > acc_width:
        return False, "BAD_SHIFT"
    return True, None


def lane_mask(input_dim, num_pe, chunk_index):
    if num_pe not in SUPPORTED_PE_COUNTS:
        raise ValueError("num_pe must be one of {}".format(SUPPORTED_PE_COUNTS))
    if input_dim <= 0 or chunk_index < 0:
        raise ValueError("input_dim must be positive and chunk_index non-negative")
    mask = 0
    for lane in range(num_pe):
        if chunk_index * num_pe + lane < input_dim:
            mask |= 1 << lane
    return mask


def vector_dot_multicycle(inputs, weights, bias, num_pe=16, acc_width=48):
    """Mirror lane-local accumulation followed by a wrapped reduction tree."""
    if len(inputs) != len(weights) or not inputs:
        raise ValueError("input and weight vectors must have equal nonzero length")
    if num_pe not in SUPPORTED_PE_COUNTS:
        raise ValueError("unsupported NUM_PE")
    if acc_width < 2:
        raise ValueError("acc_width must be at least two")

    lane_sums = [0] * num_pe
    lane_sums[0] = wrap_signed(bias, acc_width)
    for index, (input_value, weight_value) in enumerate(zip(inputs, weights)):
        lane = index % num_pe
        lane_sums[lane] = wrap_signed(
            lane_sums[lane] + int(input_value) * int(weight_value), acc_width
        )

    reduction = lane_sums
    while len(reduction) > 1:
        reduction = [
            wrap_signed(reduction[index] + reduction[index + 1], acc_width)
            for index in range(0, len(reduction), 2)
        ]
    return reduction[0]


def quantize_runtime(accumulator, acc_width=48, output_width=16,
                     output_shift=4, relu_enable=True):
    if output_shift < 0 or output_shift > acc_width:
        raise ValueError("output_shift outside accumulator width")
    accumulator = wrap_signed(accumulator, acc_width)
    quantized = saturate_signed(
        round_shift_nearest_away(accumulator, output_shift), output_width
    )
    return max(0, quantized) if relu_enable else quantized


def dense_layer_multicycle(inputs, weights, biases, num_pe=16, acc_width=48,
                           output_width=16, output_shift=4, relu_enable=True):
    if len(weights) != len(biases):
        raise ValueError("weight-row/bias length mismatch")
    if any(len(row) != len(inputs) for row in weights):
        raise ValueError("weight-row/input length mismatch")
    accumulators = [
        vector_dot_multicycle(inputs, row, bias, num_pe, acc_width)
        for row, bias in zip(weights, biases)
    ]
    outputs = [
        quantize_runtime(value, acc_width, output_width,
                         output_shift, relu_enable)
        for value in accumulators
    ]
    return accumulators, outputs


def cycle_model(input_dim, output_dim, num_pe, quantize_cycles=1):
    if input_dim <= 0 or output_dim <= 0:
        raise ValueError("dimensions must be positive")
    if num_pe not in SUPPORTED_PE_COUNTS:
        raise ValueError("unsupported NUM_PE")
    k = (input_dim + num_pe - 1) // num_pe
    r = (num_pe - 1).bit_length()
    q = quantize_cycles
    return {
        "k": k,
        "r": r,
        "q": q,
        "baseline_cycles_per_output": k + r + q,
        "baseline_layer_cycles": output_dim * (k + r + q),
        "overlap_target_layer_cycles": output_dim * k + r + q,
    }
