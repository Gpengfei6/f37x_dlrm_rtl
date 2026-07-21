"""Bit-accurate reference model for sequential Stage-2B dense layers."""

from dataclasses import dataclass

from stage2a_reference import (
    DenseJob,
    SUPPORTED_PE_COUNTS,
    dense_layer_multicycle,
    lane_mask,
    quantize_runtime,
    validate_job,
)


DEFAULT_MAX_LAYERS = 4


@dataclass(frozen=True)
class LayerDescriptor:
    in_dim: int
    out_dim: int
    weight_base: int
    bias_base: int
    output_shift: int
    relu_enable: bool

    @classmethod
    def from_dict(cls, value):
        if value is None:
            return None
        return cls(
            in_dim=int(value["in_dim"]),
            out_dim=int(value["out_dim"]),
            weight_base=int(value["weight_base"]),
            bias_base=int(value["bias_base"]),
            output_shift=int(value["output_shift"]),
            relu_enable=bool(value["relu_enable"]),
        )

    def to_dict(self):
        return {
            "in_dim": self.in_dim,
            "out_dim": self.out_dim,
            "weight_base": self.weight_base,
            "bias_base": self.bias_base,
            "output_shift": self.output_shift,
            "relu_enable": self.relu_enable,
        }


@dataclass(frozen=True)
class DescriptorValidation:
    valid: bool
    error: str = None
    layer_index: int = None

    def to_dict(self):
        return {
            "valid": self.valid,
            "error": self.error,
            "layer_index": self.layer_index,
        }


@dataclass(frozen=True)
class MlpExecutionResult:
    final_output: list
    layer_outputs: list
    layer_accumulators: list
    final_buffer_select: int
    buffer_selections: list

    def to_dict(self):
        return {
            "final_output": self.final_output,
            "layer_outputs": self.layer_outputs,
            "layer_accumulators": self.layer_accumulators,
            "final_buffer_select": self.final_buffer_select,
            "buffer_selections": self.buffer_selections,
        }


def layer_buffer_selections(layer_count, initial_buffer_select=0):
    if layer_count < 0:
        raise ValueError("layer_count must be non-negative")
    if initial_buffer_select not in (0, 1):
        raise ValueError("initial_buffer_select must be zero or one")
    selections = []
    for layer_index in range(layer_count):
        input_select = initial_buffer_select ^ (layer_index & 1)
        selections.append({
            "layer_index": layer_index,
            "input_buffer_select": input_select,
            "output_buffer_select": 1 - input_select,
        })
    return selections, initial_buffer_select ^ (layer_count & 1)


def validate_descriptors(
        descriptors, layer_count, descriptor_loaded=None,
        max_layers=DEFAULT_MAX_LAYERS, max_in_dim=1024, max_out_dim=1024,
        acc_width=48, max_weight_values=65536, max_bias_values=1024):
    """Validate the complete descriptor table before any dense job starts.

    Python integers intentionally provide the extended-precision address
    arithmetic required by the hardware contract.  No address is masked before
    its exclusive end is compared with the provider capacity.
    """
    if layer_count < 1 or layer_count > max_layers:
        return DescriptorValidation(False, "BAD_LAYER_COUNT", None)

    if descriptor_loaded is None:
        descriptor_loaded = [descriptor is not None for descriptor in descriptors]

    active = []
    for layer_index in range(layer_count):
        loaded = (layer_index < len(descriptor_loaded) and
                  bool(descriptor_loaded[layer_index]))
        descriptor = descriptors[layer_index] if layer_index < len(descriptors) else None
        if not loaded or descriptor is None:
            return DescriptorValidation(
                False, "MISSING_DESCRIPTOR", layer_index
            )
        active.append(descriptor)

    for layer_index, descriptor in enumerate(active):
        dense_job = DenseJob(
            in_dim=descriptor.in_dim,
            out_dim=descriptor.out_dim,
            input_buffer_select=0,
            output_buffer_select=1,
            weight_offset=descriptor.weight_base,
            bias_offset=descriptor.bias_base,
            output_shift=descriptor.output_shift,
            relu_enable=descriptor.relu_enable,
        )
        dense_valid, dense_error = validate_job(
            dense_job, max_in_dim=max_in_dim, max_out_dim=max_out_dim,
            acc_width=acc_width,
        )
        if not dense_valid:
            error = "BAD_SHIFT" if dense_error == "BAD_SHIFT" else "BAD_DIMENSION"
            return DescriptorValidation(False, error, layer_index)

        if layer_index and active[layer_index - 1].out_dim != descriptor.in_dim:
            return DescriptorValidation(
                False, "DIMENSION_MISMATCH", layer_index
            )

        weight_count = int(descriptor.in_dim) * int(descriptor.out_dim)
        weight_end = int(descriptor.weight_base) + weight_count
        if descriptor.weight_base < 0 or weight_end > int(max_weight_values):
            return DescriptorValidation(False, "WEIGHT_RANGE", layer_index)

        bias_end = int(descriptor.bias_base) + int(descriptor.out_dim)
        if descriptor.bias_base < 0 or bias_end > int(max_bias_values):
            return DescriptorValidation(False, "BIAS_RANGE", layer_index)

    return DescriptorValidation(True)


def execute_mlp(
        inputs, descriptors, weight_memory, bias_memory, layer_count=None,
        descriptor_loaded=None, num_pe=16, acc_width=48, output_width=16,
        initial_buffer_select=0, max_layers=DEFAULT_MAX_LAYERS,
        max_in_dim=1024, max_out_dim=1024, max_weight_values=None,
        max_bias_values=None):
    """Execute dense layers sequentially with an INT16 boundary per layer."""
    if num_pe not in SUPPORTED_PE_COUNTS:
        raise ValueError("unsupported NUM_PE")
    layer_count = len(descriptors) if layer_count is None else layer_count
    max_weight_values = (
        len(weight_memory) if max_weight_values is None else max_weight_values
    )
    max_bias_values = (
        len(bias_memory) if max_bias_values is None else max_bias_values
    )
    validation = validate_descriptors(
        descriptors, layer_count, descriptor_loaded,
        max_layers=max_layers, max_in_dim=max_in_dim,
        max_out_dim=max_out_dim, acc_width=acc_width,
        max_weight_values=max_weight_values,
        max_bias_values=max_bias_values,
    )
    if not validation.valid:
        raise ValueError("{} at layer {}".format(
            validation.error, validation.layer_index
        ))
    if len(inputs) != descriptors[0].in_dim:
        raise ValueError("initial input length does not match layer zero")

    buffer_selections, final_buffer = layer_buffer_selections(
        layer_count, initial_buffer_select
    )
    activations = [int(value) for value in inputs]
    layer_outputs = []
    layer_accumulators = []

    for layer_index in range(layer_count):
        descriptor = descriptors[layer_index]
        if len(activations) != descriptor.in_dim:
            raise ValueError("intermediate activation length mismatch")
        weights = []
        for output_index in range(descriptor.out_dim):
            row_start = (descriptor.weight_base +
                         output_index * descriptor.in_dim)
            row_end = row_start + descriptor.in_dim
            row = weight_memory[row_start:row_end]
            if len(row) != descriptor.in_dim:
                raise ValueError("weight memory image is incomplete")
            weights.append([int(value) for value in row])
        biases = bias_memory[
            descriptor.bias_base:descriptor.bias_base + descriptor.out_dim
        ]
        if len(biases) != descriptor.out_dim:
            raise ValueError("bias memory image is incomplete")

        accumulators, outputs = dense_layer_multicycle(
            activations, weights, [int(value) for value in biases],
            num_pe=num_pe, acc_width=acc_width, output_width=output_width,
            output_shift=descriptor.output_shift,
            relu_enable=descriptor.relu_enable,
        )
        independently_quantized = [
            quantize_runtime(
                accumulator, acc_width, output_width,
                descriptor.output_shift, descriptor.relu_enable,
            )
            for accumulator in accumulators
        ]
        if outputs != independently_quantized:
            raise AssertionError("Stage-2A quantization contract diverged")
        layer_accumulators.append(accumulators)
        layer_outputs.append(outputs)
        # The next layer receives these quantized signed-INT16 values, never the
        # high-precision accumulator values.
        activations = list(outputs)

    return MlpExecutionResult(
        final_output=list(activations),
        layer_outputs=layer_outputs,
        layer_accumulators=layer_accumulators,
        final_buffer_select=final_buffer,
        buffer_selections=buffer_selections,
    )


def activation_chunk_masks(input_dim, num_pe):
    """Return Stage-2A low-lane masks for every chunk of one vector."""
    chunk_count = (input_dim + num_pe - 1) // num_pe
    return [lane_mask(input_dim, num_pe, chunk) for chunk in range(chunk_count)]


def pack_layer_descriptor(
        descriptor, in_dim_width=11, out_dim_width=11,
        weight_addr_width=32, bias_addr_width=32, shift_width=6):
    """Pack one default-schema descriptor with the first field at the LSB."""
    if descriptor is None:
        return 0
    value = int(descriptor.in_dim)
    offset = in_dim_width
    value |= int(descriptor.out_dim) << offset
    offset += out_dim_width
    value |= int(descriptor.weight_base) << offset
    offset += weight_addr_width
    value |= int(descriptor.bias_base) << offset
    offset += bias_addr_width
    value |= int(descriptor.output_shift) << offset
    offset += shift_width
    value |= int(bool(descriptor.relu_enable)) << offset
    return value


def unpack_layer_descriptor(
        value, in_dim_width=11, out_dim_width=11,
        weight_addr_width=32, bias_addr_width=32, shift_width=6):
    """Decode the fixed Stage-2B vector schema into a descriptor."""
    offset = 0

    def take(width):
        nonlocal offset
        result = (int(value) >> offset) & ((1 << width) - 1)
        offset += width
        return result

    return LayerDescriptor(
        in_dim=take(in_dim_width),
        out_dim=take(out_dim_width),
        weight_base=take(weight_addr_width),
        bias_base=take(bias_addr_width),
        output_shift=take(shift_width),
        relu_enable=bool(take(1)),
    )
