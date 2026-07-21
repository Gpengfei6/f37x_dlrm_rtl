"""Generate deterministic Stage-2B multilayer descriptor and result vectors."""

import json
import random
from pathlib import Path

from fixed_point import encode_twos_complement
from stage2b_reference import (
    LayerDescriptor,
    execute_mlp,
    pack_layer_descriptor,
    validate_descriptors,
)


PROJECT_ROOT = Path(__file__).resolve().parents[1]
SEED = 0xF37B21
MAX_LAYERS = 4
MAX_IN_DIM = 1024
MAX_OUT_DIM = 1024
MAX_WEIGHT_VALUES = 65536
MAX_BIAS_VALUES = 1024
INPUT_WIDTH = 16
OUTPUT_WIDTH = 16
WEIGHT_WIDTH = 8
BIAS_WIDTH = 24
DESCRIPTOR_ROW_WIDTH = 96
VECTOR_FILES = (
    "tests/vectors/stage2b_inputs.hex",
    "tests/vectors/stage2b_weights.hex",
    "tests/vectors/stage2b_biases.hex",
    "tests/vectors/stage2b_descriptors.hex",
    "tests/expected/stage2b_final_outputs.hex",
    "tests/expected/stage2b_expected.json",
)


def signed_hex(value, width):
    return "{:0{}x}".format(
        encode_twos_complement(value, width), (width + 3) // 4
    )


def pack_lanes(values, width, lane_count):
    if len(values) > lane_count:
        raise ValueError("vector exceeds packed row capacity")
    packed = 0
    for lane, value in enumerate(values):
        packed |= encode_twos_complement(value, width) << (lane * width)
    return packed


def write_lines(path, lines):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="ascii", newline="\n") as handle:
        for line in lines:
            handle.write(str(line))
            handle.write("\n")


def make_layer(rng, in_dim, out_dim, weight_limit=12, bias_limit=4096):
    weights = [
        [rng.randint(-weight_limit, weight_limit) for _ in range(in_dim)]
        for _ in range(out_dim)
    ]
    biases = [rng.randint(-bias_limit, bias_limit) for _ in range(out_dim)]
    return weights, biases


def build_cases():
    rng = random.Random(SEED)
    weight_memory = []
    bias_memory = []
    cases = []

    def allocate_layer(weights, biases, shift, relu):
        if not weights or len(weights) != len(biases):
            raise ValueError("layer weight and bias dimensions are invalid")
        in_dim = len(weights[0])
        if in_dim == 0 or any(len(row) != in_dim for row in weights):
            raise ValueError("layer weight rows are inconsistent")
        weight_base = len(weight_memory)
        bias_base = len(bias_memory)
        for row in weights:
            weight_memory.extend(int(value) for value in row)
        bias_memory.extend(int(value) for value in biases)
        if len(weight_memory) > MAX_WEIGHT_VALUES:
            raise ValueError("deterministic weight image exceeds capacity")
        if len(bias_memory) > MAX_BIAS_VALUES:
            raise ValueError("deterministic bias image exceeds capacity")
        return LayerDescriptor(
            in_dim=in_dim,
            out_dim=len(weights),
            weight_base=weight_base,
            bias_base=bias_base,
            output_shift=shift,
            relu_enable=relu,
        )

    def add_valid(name, category, inputs, layer_definitions, num_pe,
                  acc_width, initial_buffer=0, description=""):
        descriptors = [
            allocate_layer(weights, biases, shift, relu)
            for weights, biases, shift, relu in layer_definitions
        ]
        cases.append({
            "name": name,
            "category": category,
            "description": description,
            "inputs": list(inputs),
            "layer_count": len(descriptors),
            "descriptors": descriptors,
            "descriptor_loaded": [True] * len(descriptors),
            "num_pe": num_pe,
            "acc_width": acc_width,
            "initial_buffer_select": initial_buffer,
            "expected_error": None,
        })

    def add_invalid(name, category, inputs, layer_count, descriptors,
                    loaded, expected_error, acc_width=48, num_pe=16,
                    description=""):
        cases.append({
            "name": name,
            "category": category,
            "description": description,
            "inputs": list(inputs),
            "layer_count": layer_count,
            "descriptors": list(descriptors),
            "descriptor_loaded": list(loaded),
            "num_pe": num_pe,
            "acc_width": acc_width,
            "initial_buffer_select": 0,
            "expected_error": expected_error,
        })

    model_data = json.loads(
        (PROJECT_ROOT / "tests/vectors/model_data.json").read_text(encoding="utf-8")
    )
    phase1_expected = json.loads(
        (PROJECT_ROOT / "tests/expected/top_expected.json").read_text(
            encoding="utf-8"
        )
    )
    add_valid(
        "single_stage2a_compat",
        "single_layer",
        phase1_expected[0]["aggregate"],
        [(model_data["weights"], model_data["biases"], 4, True)],
        num_pe=4,
        acc_width=32,
        description="Stage-1-compatible 8-to-4 layer reused through Stage 2A",
    )

    two0 = make_layer(rng, 8, 5)
    two1 = make_layer(rng, 5, 3)
    add_valid(
        "two_layer_a_b_a", "two_layer", [rng.randint(-32, 32) for _ in range(8)],
        [(two0[0], two0[1], 3, True), (two1[0], two1[1], 2, False)],
        num_pe=4, acc_width=48,
        description="Two layers ending back in buffer A",
    )

    three_definitions = []
    for in_dim, out_dim, shift, relu in (
        (6, 5, 2, True), (5, 4, 3, True), (4, 3, 1, False)
    ):
        weights, biases = make_layer(rng, in_dim, out_dim)
        three_definitions.append((weights, biases, shift, relu))
    add_valid(
        "three_layer_a_b_a_b", "three_layer",
        [rng.randint(-24, 24) for _ in range(6)], three_definitions,
        num_pe=8, acc_width=48,
        description="Three layers ending in buffer B",
    )

    four_definitions = []
    for in_dim, out_dim in ((7, 6), (6, 5), (5, 4), (4, 2)):
        weights, biases = make_layer(rng, in_dim, out_dim, weight_limit=7)
        four_definitions.append((weights, biases, 2, True))
    add_valid(
        "four_layer_boundary", "max_layers",
        [rng.randint(-16, 16) for _ in range(7)], four_definitions,
        num_pe=4, acc_width=48,
        description="MAX_LAYERS boundary and even ping-pong parity",
    )

    add_valid(
        "intermediate_relu_final_linear", "relu_policy", [-20, 7, -3],
        [
            ([[1, 0, 0], [0, 1, 0], [0, 0, 1]], [0, 0, 0], 0, True),
            ([[-2, -3, -1], [1, 1, 1]], [-1, 0], 0, False),
        ],
        num_pe=4, acc_width=48,
        description="Intermediate ReLU enabled and final ReLU disabled",
    )

    add_valid(
        "negative_intermediate", "signed_intermediate", [5, -7, 3],
        [
            ([[-2, 1, 0], [1, 0, -1]], [0, 0], 0, False),
            ([[2, -1], [-1, 1]], [0, 0], 0, False),
        ],
        num_pe=4, acc_width=48,
        description="Negative INT16 intermediate values feed the next layer",
    )

    add_valid(
        "intermediate_positive_negative_saturation", "saturation",
        [32767, -32768],
        [
            ([[127, 0], [0, 127]], [8388607, -8388608], 0, False),
            ([[1, 1], [1, -1]], [0, 0], 0, False),
        ],
        num_pe=4, acc_width=48,
        description="Both signed INT16 saturation limits occur between layers",
    )

    tail0 = make_layer(rng, 13, 7)
    tail1 = make_layer(rng, 7, 5)
    add_valid(
        "tail_13_7_5", "tail_mask", [rng.randint(-64, 64) for _ in range(13)],
        [(tail0[0], tail0[1], 3, True), (tail1[0], tail1[1], 2, False)],
        num_pe=4, acc_width=48,
        description="Both layers have dimensions not divisible by NUM_PE",
    )

    small = make_layer(rng, 3, 2)
    add_valid(
        "input_dim_less_than_num_pe", "small_dimension", [11, -9, 5],
        [(small[0], small[1], 1, False)],
        num_pe=16, acc_width=48,
        description="One masked chunk with in_dim smaller than NUM_PE",
    )

    add_valid(
        "acc32_wrap", "accumulator_mode", [32767] * 520,
        [([[127] * 520], [8388607], 20, False)],
        num_pe=16, acc_width=32,
        description="Exact positive sum crosses signed INT32 and wraps",
    )

    add_valid(
        "acc48_safe", "accumulator_mode", [-32768] * 1024,
        [([[-128] * 1024], [8388607], 20, False)],
        num_pe=32, acc_width=48,
        description="Reviewed maximum dimension remains exact in ACC48",
    )

    add_invalid(
        "invalid_layer_count_zero", "invalid_descriptor", [0], 0, [], [],
        "BAD_LAYER_COUNT"
    )
    add_invalid(
        "invalid_layer_count_too_large", "invalid_descriptor", [0],
        MAX_LAYERS + 1, [], [], "BAD_LAYER_COUNT"
    )
    add_invalid(
        "missing_descriptor", "invalid_descriptor", [1, 2], 2,
        [LayerDescriptor(2, 2, 0, 0, 4, True), None], [True, False],
        "MISSING_DESCRIPTOR"
    )
    add_invalid(
        "dimension_mismatch", "invalid_descriptor", [1, 2, 3], 2,
        [LayerDescriptor(3, 2, 0, 0, 4, True),
         LayerDescriptor(3, 1, 0, 0, 4, False)], [True, True],
        "DIMENSION_MISMATCH"
    )
    add_invalid(
        "invalid_in_dim_zero", "invalid_descriptor", [0], 1,
        [LayerDescriptor(0, 1, 0, 0, 4, True)], [True], "BAD_DIMENSION"
    )
    add_invalid(
        "invalid_out_dim_capacity", "invalid_descriptor", [0], 1,
        [LayerDescriptor(1, MAX_OUT_DIM + 1, 0, 0, 4, True)], [True],
        "BAD_DIMENSION"
    )
    add_invalid(
        "weight_address_out_of_range", "invalid_descriptor", [1, 2, 3, 4],
        1, [LayerDescriptor(4, 2, MAX_WEIGHT_VALUES - 7, 0, 4, True)],
        [True], "WEIGHT_RANGE"
    )
    add_invalid(
        "bias_address_out_of_range", "invalid_descriptor", [1, 2, 3, 4],
        1, [LayerDescriptor(4, 2, 0, MAX_BIAS_VALUES - 1, 4, True)],
        [True], "BIAS_RANGE"
    )
    add_invalid(
        "output_shift_out_of_range", "invalid_descriptor", [1, 2, 3, 4],
        1, [LayerDescriptor(4, 1, 0, 0, 49, False)], [True], "BAD_SHIFT"
    )

    if len(cases) != 20:
        raise AssertionError("unexpected deterministic case count")
    return cases, weight_memory, bias_memory


def generate(output_root=None):
    output_root = Path(output_root or PROJECT_ROOT)
    cases, weight_memory, bias_memory = build_cases()
    input_lines = []
    descriptor_lines = []
    output_lines = []
    serialized_cases = []

    for case_index, case in enumerate(cases):
        descriptors = case["descriptors"]
        validation = validate_descriptors(
            descriptors, case["layer_count"], case["descriptor_loaded"],
            max_layers=MAX_LAYERS, max_in_dim=MAX_IN_DIM,
            max_out_dim=MAX_OUT_DIM, acc_width=case["acc_width"],
            max_weight_values=MAX_WEIGHT_VALUES,
            max_bias_values=MAX_BIAS_VALUES,
        )
        if case["expected_error"] is None:
            if not validation.valid:
                raise AssertionError("{} unexpectedly invalid: {}".format(
                    case["name"], validation.error
                ))
            execution = execute_mlp(
                case["inputs"], descriptors, weight_memory, bias_memory,
                layer_count=case["layer_count"],
                descriptor_loaded=case["descriptor_loaded"],
                num_pe=case["num_pe"], acc_width=case["acc_width"],
                initial_buffer_select=case["initial_buffer_select"],
                max_layers=MAX_LAYERS, max_in_dim=MAX_IN_DIM,
                max_out_dim=MAX_OUT_DIM,
                max_weight_values=MAX_WEIGHT_VALUES,
                max_bias_values=MAX_BIAS_VALUES,
            )
            expected_execution = execution.to_dict()
            final_output = execution.final_output
        else:
            if validation.valid or validation.error != case["expected_error"]:
                raise AssertionError("{} expected {} but got {}".format(
                    case["name"], case["expected_error"], validation.error
                ))
            expected_execution = None
            final_output = []

        input_lines.append("{:0{}x}".format(
            pack_lanes(case["inputs"], INPUT_WIDTH, MAX_IN_DIM),
            MAX_IN_DIM * INPUT_WIDTH // 4,
        ))
        output_lines.append("{:0{}x}".format(
            pack_lanes(final_output, OUTPUT_WIDTH, MAX_OUT_DIM),
            MAX_OUT_DIM * OUTPUT_WIDTH // 4,
        ))
        for descriptor_slot in range(MAX_LAYERS):
            descriptor = (
                descriptors[descriptor_slot]
                if descriptor_slot < len(descriptors) else None
            )
            descriptor_lines.append("{:024x}".format(
                pack_layer_descriptor(descriptor)
            ))

        serialized_cases.append({
            "case_index": case_index,
            "name": case["name"],
            "category": case["category"],
            "description": case["description"],
            "num_pe": case["num_pe"],
            "acc_width": case["acc_width"],
            "initial_buffer_select": case["initial_buffer_select"],
            "layer_count": case["layer_count"],
            "descriptor_loaded": case["descriptor_loaded"],
            "descriptors": [
                descriptor.to_dict() if descriptor is not None else None
                for descriptor in descriptors
            ],
            "inputs": case["inputs"],
            "expected_validation": validation.to_dict(),
            "expected_execution": expected_execution,
        })

    metadata = {
        "schema_version": 1,
        "seed": "0x{:X}".format(SEED),
        "max_layers": MAX_LAYERS,
        "max_in_dim": MAX_IN_DIM,
        "max_out_dim": MAX_OUT_DIM,
        "max_weight_values": MAX_WEIGHT_VALUES,
        "max_bias_values": MAX_BIAS_VALUES,
        "input_width": INPUT_WIDTH,
        "output_width": OUTPUT_WIDTH,
        "weight_width": WEIGHT_WIDTH,
        "bias_width": BIAS_WIDTH,
        "descriptor_row_width": DESCRIPTOR_ROW_WIDTH,
        "input_row_hex_chars": MAX_IN_DIM * INPUT_WIDTH // 4,
        "output_row_hex_chars": MAX_OUT_DIM * OUTPUT_WIDTH // 4,
        "descriptor_row_hex_chars": DESCRIPTOR_ROW_WIDTH // 4,
        "lane_zero_is_lsb": True,
        "weight_values_written": len(weight_memory),
        "bias_values_written": len(bias_memory),
        "case_count": len(serialized_cases),
        "cases": serialized_cases,
    }

    write_lines(output_root / "tests/vectors/stage2b_inputs.hex", input_lines)
    write_lines(
        output_root / "tests/vectors/stage2b_weights.hex",
        (signed_hex(value, WEIGHT_WIDTH) for value in weight_memory),
    )
    write_lines(
        output_root / "tests/vectors/stage2b_biases.hex",
        (signed_hex(value, BIAS_WIDTH) for value in bias_memory),
    )
    write_lines(
        output_root / "tests/vectors/stage2b_descriptors.hex", descriptor_lines
    )
    write_lines(
        output_root / "tests/expected/stage2b_final_outputs.hex", output_lines
    )
    expected_path = output_root / "tests/expected/stage2b_expected.json"
    expected_path.parent.mkdir(parents=True, exist_ok=True)
    expected_path.write_text(
        json.dumps(metadata, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    return metadata


def main():
    metadata = generate()
    print("generate_stage2b_vectors: wrote {} deterministic cases (seed {})".format(
        metadata["case_count"], metadata["seed"]
    ))


if __name__ == "__main__":
    main()
