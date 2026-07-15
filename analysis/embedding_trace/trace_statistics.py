"""Request-window duplicate, locality, skew and reuse statistics."""

from collections import Counter, defaultdict

import numpy as np


DEFAULT_WINDOWS = (1, 2, 4, 8, 16, 32, 64)


def _percentiles(values):
    if not values:
        return {"average": None, "p50": None, "p95": None, "p99": None, "maximum": None}
    array = np.asarray(values, dtype=np.float64)
    return {
        "average": float(np.mean(array)), "p50": float(np.percentile(array, 50)),
        "p95": float(np.percentile(array, 95)), "p99": float(np.percentile(array, 99)),
        "maximum": float(np.max(array)),
    }


def _gini(counts):
    values = np.asarray(list(counts), dtype=np.float64)
    if values.size == 0 or np.sum(values) == 0:
        return 0.0
    values.sort()
    index = np.arange(1, values.size + 1)
    return float(np.sum((2 * index - values.size - 1) * values) / (values.size * np.sum(values)))


def analyze_trace(records, windows=DEFAULT_WINDOWS, top_keys=10):
    if not records:
        raise ValueError("trace is empty")
    records = sorted(records, key=lambda value: value["arrival_order"])
    request_ids = sorted({int(record["request_id"]) for record in records})
    by_request = defaultdict(list)
    by_batch = defaultdict(list)
    key_counts = Counter()
    table_counts = defaultdict(Counter)
    last_position = {}
    reuse_distances = []
    for position, record in enumerate(records):
        by_request[int(record["request_id"])].append(record)
        by_batch[int(record["batch_id"])].append(record)
        key = (int(record["table_id"]), int(record["embedding_id"]))
        key_counts[key] += 1
        table_counts[key[0]][key[1]] += 1
        if key in last_position:
            reuse_distances.append(position - last_position[key])
        last_position[key] = position
    per_window = {}
    for window_size in windows:
        window_rows = []
        window_key_sets = []
        for start in range(0, len(request_ids), int(window_size)):
            selected = request_ids[start:start + int(window_size)]
            lookups = [record for request_id in selected for record in by_request[request_id]]
            key_set = {(int(value["table_id"]), int(value["embedding_id"])) for value in lookups}
            unique = len(key_set)
            total = len(lookups)
            window_key_sets.append(key_set)
            window_rows.append({"requests": len(selected), "lookups": total, "unique": unique,
                                "duplicates": total - unique})
        total_lookups = sum(value["lookups"] for value in window_rows)
        total_unique = sum(value["unique"] for value in window_rows)
        duplicate_counts = [value["duplicates"] for value in window_rows]
        adjacent_reuse = []
        for previous, current in zip(window_key_sets, window_key_sets[1:]):
            adjacent_reuse.append(len(previous & current) / max(1, len(current)))
        per_window[str(window_size)] = {
            "window_count": len(window_rows),
            "lookup_count": total_lookups,
            "unique_read_count": total_unique,
            "duplicate_count": total_lookups - total_unique,
            "duplicate_ratio": (total_lookups - total_unique) / total_lookups,
            "ideal_read_reduction_ratio": (total_lookups - total_unique) / total_lookups,
            "unique_growth_per_request": total_unique / len(request_ids),
            "unique_ids_per_window": _percentiles([value["unique"] for value in window_rows]),
            "adjacent_window_reuse_ratio": _percentiles(adjacent_reuse),
            "duplicate_burstiness": _percentiles(duplicate_counts),
        }
    per_table = {}
    for table_id, counts in sorted(table_counts.items()):
        total = sum(counts.values())
        per_table[str(table_id)] = {
            "lookups": total,
            "unique_keys": len(counts),
            "hottest_key_share": max(counts.values()) / total,
            "key_frequency_gini": _gini(counts.values()),
            "top_ids": [
                {"embedding_id": int(embedding_id), "count": int(count),
                 "share": count / total}
                for embedding_id, count in counts.most_common(int(top_keys))
            ],
            "frequency_histogram": {
                str(frequency): id_count
                for frequency, id_count in sorted(Counter(counts.values()).items())
            },
        }
    hot = [
        {"table_id": key[0], "embedding_id": key[1], "count": count,
         "share": count / len(records)}
        for key, count in key_counts.most_common(int(top_keys))
    ]
    batch_lookups = sum(len(values) for values in by_batch.values())
    batch_unique = sum(
        len({(int(value["table_id"]), int(value["embedding_id"])) for value in values})
        for values in by_batch.values()
    )
    return {
        "request_count": len(request_ids), "lookup_count": len(records),
        "table_count": len(table_counts), "unique_key_count": len(key_counts),
        "lookups_per_request": _percentiles([len(by_request[value]) for value in request_ids]),
        "within_batch_duplicate_ratio": (batch_lookups - batch_unique) / batch_lookups,
        "windows": per_window, "reuse_distance_lookups": _percentiles(reuse_distances),
        "per_table_skew": per_table, "hot_keys": hot,
    }
