"""Lightweight post-coalescing channel assignment/scheduling model."""

from collections import Counter

import numpy as np

from .hbm_mapping import candidate_channels, map_channel


SCHEDULERS = (
    "modulo", "static_table", "per_channel_fifo_rr", "queue_aware", "age_queue"
)


def _metrics(entries, channel_count, assignments, starts, finishes, waits, queue_depths, service_cycles):
    counts = Counter(assignments)
    request_counts = [counts.get(index, 0) for index in range(channel_count)]
    makespan = max(finishes) if finishes else 0.0
    busy = sum(request_counts) * service_cycles
    completion_latencies = [finish - float(entry.get("timestamp", entry["arrival_order"]))
                            for entry, finish in zip(entries, finishes)]
    return {
        "channel_count": channel_count,
        "coalesced_read_count": len(entries),
        "channel_request_counts": request_counts,
        "request_imbalance_max_over_mean": max(request_counts) / np.mean(request_counts) if entries else 0.0,
        "request_count_variance": float(np.var(request_counts)),
        "request_count_standard_deviation": float(np.std(request_counts)),
        "queue_depth": {
            "average": float(np.mean(queue_depths)) if queue_depths else 0.0,
            "maximum": int(max(queue_depths)) if queue_depths else 0,
        },
        "wait_cycles": {
            "average": float(np.mean(waits)) if waits else 0.0,
            "p50": float(np.percentile(waits, 50)) if waits else 0.0,
            "p95": float(np.percentile(waits, 95)) if waits else 0.0,
            "p99": float(np.percentile(waits, 99)) if waits else 0.0,
            "maximum": float(max(waits)) if waits else 0.0,
        },
        "estimated_completion_cycles": float(makespan),
        "aggregate_channel_utilization": busy / (makespan * channel_count) if makespan else 0.0,
        "aggregate_channel_idle_ratio": 1.0 - busy / (makespan * channel_count) if makespan else 1.0,
        "request_completion_cycles": {
            "average": float(np.mean(completion_latencies)) if completion_latencies else 0.0,
            "p50": float(np.percentile(completion_latencies, 50)) if completion_latencies else 0.0,
            "p95": float(np.percentile(completion_latencies, 95)) if completion_latencies else 0.0,
            "p99": float(np.percentile(completion_latencies, 99)) if completion_latencies else 0.0,
            "maximum": float(max(completion_latencies)) if completion_latencies else 0.0,
        },
    }


def simulate_channel_schedule(entries, channel_count, scheduler="modulo", service_cycles=8.0):
    """Assign abstract reads to channels and estimate FIFO service.

    Queue-aware policies assume each embedding can be placed at one of two
    deterministic candidate channels. This is a feasibility assumption, not a
    statement about the final F37X address map.
    """
    if scheduler not in SCHEDULERS:
        raise ValueError("unsupported scheduler")
    if channel_count not in (4, 8, 16, 32):
        raise ValueError("channel_count must be one of 4, 8, 16, 32")
    if service_cycles <= 0:
        raise ValueError("service_cycles must be positive")
    ordered = sorted(entries, key=lambda value: (value.get("timestamp", 0.0), value["arrival_order"]))
    available = [0.0] * channel_count
    finish_queues = [[] for _ in range(channel_count)]
    assignments, starts, finishes, waits, depths = [], [], [], [], []
    for entry in ordered:
        arrival = float(entry.get("timestamp", entry["arrival_order"]))
        table_id, embedding_id = entry["table_id"], entry["embedding_id"]
        for queue_index in range(channel_count):
            finish_queues[queue_index] = [
                value for value in finish_queues[queue_index] if value > arrival
            ]
        if scheduler == "static_table":
            channel = map_channel(table_id, embedding_id, channel_count, "static_table")
        elif scheduler in ("modulo", "per_channel_fifo_rr"):
            primary = map_channel(table_id, embedding_id, channel_count, "modulo")
            # The RR baseline preserves fixed placement. With independent,
            # work-conserving channels it should match fixed-map FIFO timing;
            # that no-change result is intentional rather than an improvement.
            channel = primary
        else:
            candidates = candidate_channels(table_id, embedding_id, channel_count)
            if scheduler == "queue_aware":
                channel = min(candidates, key=lambda value: (max(arrival, available[value]), value))
            else:
                # Penalize both projected queue delay and the age of the oldest
                # queued item. This stays intentionally lightweight.
                def age_queue_score(value):
                    oldest_age = 0.0
                    if finish_queues[value]:
                        oldest_start = finish_queues[value][0] - service_cycles
                        oldest_age = max(0.0, arrival - oldest_start)
                    return (
                        max(arrival, available[value])
                        + 0.25 * len(finish_queues[value])
                        + 0.125 * oldest_age,
                        value,
                    )
                channel = min(
                    candidates,
                    key=age_queue_score,
                )
        depths.append(len(finish_queues[channel]))
        start = max(arrival, available[channel])
        finish = start + service_cycles
        available[channel] = finish
        finish_queues[channel].append(finish)
        assignments.append(channel)
        starts.append(start)
        finishes.append(finish)
        waits.append(start - arrival)
    report = _metrics(
        ordered, channel_count, assignments, starts, finishes, waits, depths, service_cycles
    )
    report.update({
        "scheduler": scheduler,
        "service_cycles_per_read": service_cycles,
        "mapping_boundary": (
            "two-candidate replicated/relocatable placement assumption"
            if scheduler in ("queue_aware", "age_queue")
            else "single deterministic abstract mapping"
        ),
        "hardware_boundary": "not a physical F37X HBM address, crossbar or timing model",
        "dispatch_behavior": (
            "fixed-mapped per-channel FIFO; round-robin observation adds no service capacity"
            if scheduler == "per_channel_fifo_rr"
            else "online deterministic assignment in arrival order"
        ),
    })
    return report
