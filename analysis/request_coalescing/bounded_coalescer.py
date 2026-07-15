"""Bounded-window one-read/multi-consumer coalescing feasibility model."""

from collections import Counter, defaultdict
from dataclasses import dataclass

import numpy as np


POLICIES = ("none", "fixed_count", "fixed_time", "dual", "adaptive")


@dataclass(frozen=True)
class CoalescerConfig:
    policy: str = "dual"
    max_requests: int = 8
    max_wait: float = 8.0
    max_unique: int = 256
    arrival_rate: float = 1.0
    embedding_latency: float = 8.0
    broadcast_cost: float = 0.25
    reorder_cost: float = 0.1
    tag_bytes: int = 16
    consumer_bytes: int = 8

    def __post_init__(self):
        if self.policy not in POLICIES:
            raise ValueError("unsupported coalescing policy")
        if (self.max_requests <= 0 or self.max_wait < 0 or self.max_unique <= 0
                or self.arrival_rate <= 0):
            raise ValueError("coalescer bounds must be positive (max_wait may be zero)")


def _requests(records):
    grouped = defaultdict(list)
    for record in sorted(records, key=lambda value: value["arrival_order"]):
        grouped[int(record["request_id"])].append(record)
    return [grouped[key] for key in sorted(grouped)]


def _keys(request):
    return {(int(value["table_id"]), int(value["embedding_id"])) for value in request}


def _adaptive_target(recent_ratio, maximum):
    if recent_ratio >= 0.35:
        return maximum
    if recent_ratio >= 0.15:
        return max(2, maximum // 2)
    return max(1, maximum // 4)


def _arrival_time(record, config):
    trace_time = float(record.get("timestamp", record["request_id"]))
    return trace_time / config.arrival_rate


def _form_windows(records, config):
    requests = _requests(records)
    windows, current = [], []
    current_keys = set()
    recent_ratios = []
    overflow_bypass = 0
    for request in requests:
        request_keys = _keys(request)
        request_time = _arrival_time(request[0], config)
        if config.policy == "none":
            windows.extend([[value] for value in request])
            continue
        if len(request_keys) > config.max_unique:
            if current:
                windows.append([value for group in current for value in group])
                current, current_keys = [], set()
            windows.extend([[value] for value in request])
            overflow_bypass += len(request)
            continue
        first_time = request_time if not current else _arrival_time(current[0][0], config)
        recent_ratio = float(np.mean(recent_ratios[-4:])) if recent_ratios else 0.0
        target = (_adaptive_target(recent_ratio, config.max_requests)
                  if config.policy == "adaptive" else config.max_requests)
        # max_requests is a hard safety bound for every coalescing policy.
        count_limit = len(current) >= target
        time_limit = config.policy in ("fixed_time", "dual", "adaptive") and current and request_time - first_time > config.max_wait
        unique_limit = current and len(current_keys | request_keys) > config.max_unique
        if count_limit or time_limit or unique_limit:
            flat = [value for group in current for value in group]
            windows.append(flat)
            recent_ratios.append(1.0 - len(current_keys) / max(1, len(flat)))
            current, current_keys = [], set()
        current.append(request)
        current_keys |= request_keys
    if current:
        windows.append([value for group in current for value in group])
    return windows, overflow_bypass


def _percentile(values, percentile):
    return float(np.percentile(values, percentile)) if values else 0.0


def simulate_coalescing(records, config):
    if not isinstance(config, CoalescerConfig):
        config = CoalescerConfig(**config)
    if not records:
        raise ValueError("trace is empty")
    windows, overflow_bypass = _form_windows(records, config)
    original_reads, coalesced_reads = len(records), 0
    waits, occupancies, request_occupancies, fanout_tag_occupancies, fanouts = [], [], [], [], []
    coalesced_entries = []
    completion_time = 0.0
    for window_id, window in enumerate(windows):
        consumers = defaultdict(list)
        for record in window:
            consumers[(int(record["table_id"]), int(record["embedding_id"]))].append(record)
        coalesced_reads += len(consumers)
        occupancies.append(len(consumers))
        request_occupancies.append(len({int(value["request_id"]) for value in window}))
        fanout_tag_occupancies.append(len(window))
        last = max(_arrival_time(value, config) for value in window)
        waits.extend(last - _arrival_time(value, config) for value in window)
        service = len(consumers) * config.embedding_latency
        service += sum(max(0, len(values) - 1) * config.broadcast_cost for values in consumers.values())
        service += len(window) * config.reorder_cost
        completion_time = max(completion_time, last) + service
        for key, values in consumers.items():
            fanouts.append(len(values))
            coalesced_entries.append({
                "window": window_id, "table_id": key[0], "embedding_id": key[1],
                "arrival_order": min(int(value["arrival_order"]) for value in values),
                # Reads are released only after the bounded window closes.
                "timestamp": last,
                "window_close_timestamp": last,
                "fanout": len(values),
            })
    request_count = len({int(value["request_id"]) for value in records})
    total_reduction = original_reads - coalesced_reads
    fanout_histogram = {str(key): value for key, value in sorted(Counter(fanouts).items())}
    maximum_lookups_per_request = max(Counter(int(value["request_id"]) for value in records).values())
    tag_state_bytes = config.max_unique * config.tag_bytes
    consumer_state_bytes = config.max_requests * maximum_lookups_per_request * config.consumer_bytes
    result = {
        "policy": config.policy,
        "parameters": vars(config),
        "request_count": request_count,
        "original_read_count": original_reads,
        "coalesced_read_count": coalesced_reads,
        "read_reduction_count": total_reduction,
        "read_reduction_ratio": total_reduction / original_reads,
        "coalescing_ratio": total_reduction / original_reads,
        "window_count": len(windows),
        "wait_time": {
            "average": float(np.mean(waits)), "p50": _percentile(waits, 50),
            "p95": _percentile(waits, 95), "p99": _percentile(waits, 99),
            "maximum": max(waits),
        },
        "tag_occupancy": {"average": float(np.mean(occupancies)), "maximum": max(occupancies)},
        "request_queue_occupancy": {
            "average": float(np.mean(request_occupancies)), "maximum": max(request_occupancies)
        },
        "fanout_histogram": fanout_histogram,
        "maximum_fanout_tags": max(fanouts),
        "fanout_tag_occupancy": {
            "average": float(np.mean(fanout_tag_occupancies)),
            "maximum": max(fanout_tag_occupancies),
        },
        "overflow_bypass_lookups": overflow_bypass,
        "estimated_state_bytes": tag_state_bytes + consumer_state_bytes,
        "state_bytes_breakdown": {
            "unique_tag_state": tag_state_bytes,
            "consumer_reorder_state": consumer_state_bytes,
            "maximum_lookups_per_request": maximum_lookups_per_request,
        },
        "estimated_completion_time": completion_time,
        "estimated_request_throughput": request_count / completion_time if completion_time else None,
        "model_boundary": "abstract serialized embedding service plus broadcast/reorder costs",
    }
    return result, coalesced_entries
