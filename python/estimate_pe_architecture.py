#!/usr/bin/env python3
"""Estimate Stage-2 vector-PE cycles, storage, bandwidth, and arithmetic width.

This architecture-only model generates no RTL and makes no synthesis claim.
"""

import argparse
import json
from dataclasses import asdict, dataclass


DEFAULT_CLOCK_MHZ = 250.0
DEFAULT_PE_COUNTS = (4, 8, 16, 32)
APPROVED_ACCUMULATOR_WIDTHS = (32, 48)


@dataclass(frozen=True)
class LayerSpec:
    name: str
    input_dim: int
    output_dim: int
    input_width: int


DEFAULT_LAYERS = (
    LayerSpec("8->4", 8, 4, 10),
    LayerSpec("64->32", 64, 32, 16),
    LayerSpec("128->64", 128, 64, 16),
    LayerSpec("256->128", 256, 128, 16),
    LayerSpec("512->256", 512, 256, 16),
)


def ceil_div(numerator, denominator):
    return (numerator + denominator - 1) // denominator


def ceil_log2(value):
    return 0 if value <= 1 else (value - 1).bit_length()


def signed_bounds(width):
    return -(1 << (width - 1)), (1 << (width - 1)) - 1


def dot_product_bounds(input_dim, input_width, weight_width, bias_width):
    input_min, input_max = signed_bounds(input_width)
    weight_min, weight_max = signed_bounds(weight_width)
    products = (
        input_min * weight_min,
        input_min * weight_max,
        input_max * weight_min,
        input_max * weight_max,
    )
    bias_min, bias_max = signed_bounds(bias_width)
    return (
        input_dim * min(products) + bias_min,
        input_dim * max(products) + bias_max,
    )


def signed_width_for_range(minimum, maximum):
    width = 2
    while minimum < -(1 << (width - 1)) or maximum > (1 << (width - 1)) - 1:
        width += 1
    return width


def estimate_layer(layer, num_pe, clock_mhz, weight_width, bias_width,
                   accumulator_width):
    k = ceil_div(layer.input_dim, num_pe)
    r = ceil_log2(num_pe)
    q = 1
    cycles_per_output = k + r + q
    baseline_cycles = layer.output_dim * cycles_per_output
    overlap_cycles = layer.output_dim * k + r + q
    input_load_cycles = k
    baseline_isolated = input_load_cycles + baseline_cycles
    overlap_isolated = input_load_cycles + overlap_cycles
    tail_lanes = layer.input_dim % num_pe or num_pe
    lane_utilization = layer.input_dim / float(k * num_pe)

    input_bits = layer.input_dim * layer.input_width
    weight_bits = layer.input_dim * layer.output_dim * weight_width
    bias_bits = layer.output_dim * bias_width
    minimum, maximum = dot_product_bounds(
        layer.input_dim, layer.input_width, weight_width, bias_width
    )
    safe_width = signed_width_for_range(minimum, maximum)
    clock_hz = clock_mhz * 1_000_000.0

    return {
        "layer": layer.name,
        "input_dim": layer.input_dim,
        "output_dim": layer.output_dim,
        "input_width": layer.input_width,
        "num_pe": num_pe,
        "mac_cycles_per_output": k,
        "reduction_cycles_per_output": r,
        "quantize_cycles_per_output": q,
        "baseline_cycles_per_output": cycles_per_output,
        "baseline_layer_compute_cycles": baseline_cycles,
        "overlap_target_layer_compute_cycles": overlap_cycles,
        "input_load_cycles": input_load_cycles,
        "baseline_isolated_sample_cycles": baseline_isolated,
        "overlap_target_isolated_sample_cycles": overlap_isolated,
        "tail_valid_lanes": tail_lanes,
        "lane_utilization": lane_utilization,
        "baseline_theoretical_layers_per_second": clock_hz / baseline_cycles,
        "overlap_target_theoretical_layers_per_second": clock_hz / overlap_cycles,
        "baseline_isolated_samples_per_second": clock_hz / baseline_isolated,
        "overlap_target_isolated_samples_per_second": clock_hz / overlap_isolated,
        "baseline_useful_macs_per_cycle": (
            layer.input_dim * layer.output_dim / float(baseline_cycles)
        ),
        "dsp_multiplier_upper_budget": num_pe,
        "lane_accumulators": num_pe,
        "final_accumulator_registers": 1,
        "accumulator_register_bits": (num_pe + 1) * accumulator_width,
        "input_buffer_bytes": ceil_div(input_bits, 8),
        "double_input_buffer_bytes": 2 * ceil_div(input_bits, 8),
        "weight_provider_bytes_per_sample": ceil_div(weight_bits, 8),
        "bias_provider_bytes_per_sample": ceil_div(bias_bits, 8),
        "peak_weight_bits_per_cycle": num_pe * weight_width,
        "peak_weight_gb_per_second": (
            num_pe * weight_width / 8.0 * clock_hz / 1_000_000_000.0
        ),
        "peak_input_bits_per_cycle": num_pe * layer.input_width,
        "dot_product_minimum": minimum,
        "dot_product_maximum": maximum,
        "safe_accumulator_width": safe_width,
        "configured_accumulator_width": accumulator_width,
        "configured_accumulator_covers_worst_case": accumulator_width >= safe_width,
        "int32_covers_worst_case": 32 >= safe_width,
        "int48_covers_worst_case": 48 >= safe_width,
    }


def parse_layer(text, default_input_width):
    try:
        shape, separator, width_text = text.partition(":")
        input_text, output_text = shape.lower().split("x", 1)
        input_dim = int(input_text)
        output_dim = int(output_text)
        input_width = int(width_text) if separator else default_input_width
    except (ValueError, TypeError):
        raise argparse.ArgumentTypeError("layer must be INxOUT or INxOUT:INPUT_WIDTH")
    if input_dim <= 0 or output_dim <= 0 or input_width <= 1:
        raise argparse.ArgumentTypeError("layer dimensions/width must be positive")
    return LayerSpec("{}->{}".format(input_dim, output_dim), input_dim,
                     output_dim, input_width)


def compact_number(value):
    if abs(value) >= 1_000_000:
        return "{:.3f}M".format(value / 1_000_000.0)
    if abs(value) >= 1_000:
        return "{:.3f}k".format(value / 1_000.0)
    return "{:.3f}".format(value)


def render_markdown(estimates, layers, pe_counts, args):
    lines = [
        "# PE architecture estimate", "",
        "Assumptions: {:.3f} MHz, INT{} weights, INT{} bias, INT{} internal "
        "accumulator for register-count estimates, one output lane, "
        "`R=ceil(log2(P))`, and `Q=1`. Arithmetic coverage is shown for both "
        "approved modes: INT32 wrap compatibility and INT48 safe accumulation."
        .format(args.clock_mhz, args.weight_width, args.bias_width,
                args.accumulator_width), "",
        "## Baseline and overlap-target cycles", "",
        "| Layer | P | K | R | Baseline cycles/output | Baseline layer cycles | "
        "Overlap target cycles | Baseline layers/s | Overlap layers/s | Lane util. |",
        "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for item in estimates:
        lines.append(
            "| {layer} | {num_pe} | {mac_cycles_per_output} | "
            "{reduction_cycles_per_output} | {baseline_cycles_per_output} | "
            "{baseline_layer_compute_cycles} | "
            "{overlap_target_layer_compute_cycles} | {base_rate} | "
            "{overlap_rate} | {util:.1f}% |".format(
                base_rate=compact_number(item["baseline_theoretical_layers_per_second"]),
                overlap_rate=compact_number(item["overlap_target_theoretical_layers_per_second"]),
                util=100.0 * item["lane_utilization"], **item
            )
        )

    lines.extend(["", "## Storage and accumulator coverage", "",
        "The weight column is provider traffic per sample, not a committed "
        "whole-layer on-chip cache.", "",
        "| Layer | Input width | One input | Ping-pong input | Weight traffic | Bias | "
        "Safe width | INT32 | INT48 |",
        "|---|---:|---:|---:|---:|---:|---:|---|---|",
    ])
    for layer in layers:
        item = next(x for x in estimates
                    if x["layer"] == layer.name and x["num_pe"] == pe_counts[0])
        lines.append(
            "| {layer} | {input_width} | {input_buffer_bytes} B | "
            "{double_input_buffer_bytes} B | {weight_kib:.3f} KiB | "
            "{bias_provider_bytes_per_sample} B | {safe_accumulator_width} bits | "
            "{int32} | {int48} |".format(
                weight_kib=item["weight_provider_bytes_per_sample"] / 1024.0,
                int32="safe" if item["int32_covers_worst_case"] else "wrap possible",
                int48="safe" if item["int48_covers_worst_case"] else "overflow possible",
                **item
            )
        )

    lines.extend(["", "## Parallelism resources", "",
        "Multiplier counts are logical upper budgets. DSP mapping, packing, and "
        "the 48-bit accumulator implementation require Vivado synthesis evidence.", "",
        "| P | Multipliers | Lane accumulators | ACC{} register bits | "
        "Weight bits/cycle | Weight GB/s @ {:.0f} MHz |".format(
            args.accumulator_width, args.clock_mhz),
        "|---:|---:|---:|---:|---:|---:|",
    ])
    for pe_count in pe_counts:
        item = next(x for x in estimates
                    if x["layer"] == layers[-1].name and x["num_pe"] == pe_count)
        lines.append(
            "| {num_pe} | {dsp_multiplier_upper_budget} | {lane_accumulators} | "
            "{accumulator_register_bits} | {peak_weight_bits_per_cycle} | "
            "{peak_weight_gb_per_second:.3f} |".format(**item)
        )

    lines.extend(["", "## Batch scaling at P={}".format(args.recommended_pe), "",
        "Stage 2A executes samples serially and does not cache a whole weight layer. "
        "Compute and provider traffic therefore scale linearly with batch size, so "
        "steady-state samples/s is unchanged. Provider-side reuse is a future option.", "",
        "| Layer | Batch | Baseline isolated cycles | Samples/s | Weight bytes/sample |",
        "|---|---:|---:|---:|---:|",
    ])
    for layer in layers:
        item = next(x for x in estimates
                    if x["layer"] == layer.name and x["num_pe"] == args.recommended_pe)
        for batch in args.batch_sizes:
            total = batch * item["baseline_isolated_sample_cycles"]
            rate = batch * args.clock_mhz * 1_000_000.0 / total
            lines.append("| {} | {} | {} | {} | {} B |".format(
                layer.name, batch, total, compact_number(rate),
                item["weight_provider_bytes_per_sample"]))
    return "\n".join(lines)


def self_check():
    stage1 = estimate_layer(DEFAULT_LAYERS[0], 4, 250.0, 8, 24, 48)
    assert stage1["mac_cycles_per_output"] == 2
    assert stage1["baseline_cycles_per_output"] == 5
    assert stage1["baseline_layer_compute_cycles"] == 20
    assert stage1["overlap_target_layer_compute_cycles"] == 11
    assert stage1["input_buffer_bytes"] == 10
    assert stage1["weight_provider_bytes_per_sample"] == 32
    assert stage1["safe_accumulator_width"] == 25
    expected = (25, 30, 31, 32, 33)
    actual = tuple(estimate_layer(layer, 16, 250.0, 8, 24, 48)
                   ["safe_accumulator_width"] for layer in DEFAULT_LAYERS)
    assert actual == expected


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--clock-mhz", type=float, default=DEFAULT_CLOCK_MHZ)
    parser.add_argument("--weight-width", type=int, default=8)
    parser.add_argument("--bias-width", type=int, default=24)
    parser.add_argument("--accumulator-width", type=int, default=48)
    parser.add_argument("--default-input-width", type=int, default=16)
    parser.add_argument("--pe", nargs="+", type=int, default=DEFAULT_PE_COUNTS)
    parser.add_argument("--layers", nargs="*", default=None)
    parser.add_argument("--recommended-pe", type=int, default=16)
    parser.add_argument("--batch-sizes", nargs="+", type=int, default=(1, 4, 8))
    parser.add_argument("--format", choices=("markdown", "json"), default="markdown")
    parser.add_argument("--self-check", action="store_true")
    args = parser.parse_args()

    if args.clock_mhz <= 0 or args.accumulator_width < 2:
        parser.error("clock and accumulator width must be positive")
    if min(args.pe) <= 0 or args.recommended_pe not in args.pe:
        parser.error("PE counts must be positive and include --recommended-pe")
    if min(args.batch_sizes) <= 0:
        parser.error("batch sizes must be positive")

    self_check()
    if args.self_check:
        print("estimate_pe_architecture: SELF-CHECK PASS")
        return
    layers = (tuple(parse_layer(text, args.default_input_width)
                    for text in args.layers) if args.layers else DEFAULT_LAYERS)
    estimates = [estimate_layer(layer, pe_count, args.clock_mhz,
                                args.weight_width, args.bias_width,
                                args.accumulator_width)
                 for layer in layers for pe_count in args.pe]
    if args.format == "json":
        print(json.dumps({
            "assumptions": {
                "clock_mhz": args.clock_mhz,
                "weight_width": args.weight_width,
                "bias_width": args.bias_width,
                "register_count_accumulator_width": args.accumulator_width,
                "approved_accumulator_widths": APPROVED_ACCUMULATOR_WIDTHS,
                "pe_counts": args.pe,
                "baseline_cycle_model": "O*(ceil(D/P)+ceil(log2(P))+Q)",
                "overlap_target_cycle_model": "O*ceil(D/P)+ceil(log2(P))+Q",
                "stage2a_overlap_enabled": False,
            },
            "layers": [asdict(layer) for layer in layers],
            "estimates": estimates,
        }, indent=2, sort_keys=True))
    else:
        print(render_markdown(estimates, layers, tuple(args.pe), args))


if __name__ == "__main__":
    main()
