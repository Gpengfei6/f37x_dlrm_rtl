"""Canonical embedding lookup trace records and JSONL/CSV/NPY serialization."""

import csv
import json
from pathlib import Path

import numpy as np


TRACE_FIELDS = (
    "request_id", "batch_id", "table_id", "embedding_id", "arrival_order",
    "timestamp", "is_duplicate", "window",
)


def build_embedding_trace(categorical_ids, batch_size=16, request_interval=1.0, duplicate_window=8):
    categorical_ids = np.asarray(categorical_ids, dtype=np.int64)
    if categorical_ids.ndim != 2:
        raise ValueError("categorical_ids must have shape [requests, tables]")
    if batch_size <= 0 or request_interval < 0 or duplicate_window <= 0:
        raise ValueError("batch_size/window must be positive and interval non-negative")
    records = []
    recent_by_window = {}
    arrival_order = 0
    for request_id, row in enumerate(categorical_ids):
        window = request_id // duplicate_window
        seen = recent_by_window.setdefault(window, set())
        for table_id, embedding_id in enumerate(row):
            key = (int(table_id), int(embedding_id))
            records.append({
                "request_id": int(request_id),
                "batch_id": int(request_id // batch_size),
                "table_id": int(table_id),
                "embedding_id": int(embedding_id),
                "arrival_order": int(arrival_order),
                "timestamp": float(request_id * request_interval),
                "is_duplicate": key in seen,
                "window": int(window),
            })
            seen.add(key)
            arrival_order += 1
    return records


def save_trace(records, path):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    suffix = path.suffix.lower()
    if suffix == ".jsonl":
        with path.open("w", encoding="utf-8") as handle:
            for record in records:
                handle.write(json.dumps(record, sort_keys=True) + "\n")
    elif suffix == ".csv":
        with path.open("w", encoding="utf-8", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=TRACE_FIELDS)
            writer.writeheader()
            writer.writerows(records)
    elif suffix == ".npy":
        dtype = np.dtype([
            ("request_id", "<i8"), ("batch_id", "<i8"), ("table_id", "<i8"),
            ("embedding_id", "<i8"), ("arrival_order", "<i8"),
            ("timestamp", "<f8"), ("is_duplicate", "?"), ("window", "<i8"),
        ])
        values = np.empty(len(records), dtype=dtype)
        for index, record in enumerate(records):
            values[index] = tuple(record[field] for field in TRACE_FIELDS)
        np.save(path, values, allow_pickle=False)
    else:
        raise ValueError("trace extension must be .jsonl, .csv or .npy")


def load_trace(path):
    path = Path(path)
    suffix = path.suffix.lower()
    if suffix == ".jsonl":
        with path.open("r", encoding="utf-8") as handle:
            return [json.loads(line) for line in handle if line.strip()]
    if suffix == ".csv":
        records = []
        with path.open("r", encoding="utf-8", newline="") as handle:
            for raw in csv.DictReader(handle):
                records.append({
                    "request_id": int(raw["request_id"]), "batch_id": int(raw["batch_id"]),
                    "table_id": int(raw["table_id"]), "embedding_id": int(raw["embedding_id"]),
                    "arrival_order": int(raw["arrival_order"]), "timestamp": float(raw["timestamp"]),
                    "is_duplicate": raw["is_duplicate"].lower() in ("1", "true", "yes"),
                    "window": int(raw["window"]),
                })
        return records
    if suffix == ".npy":
        values = np.load(path, allow_pickle=False)
        return [
            {field: values[index][field].item() for field in TRACE_FIELDS}
            for index in range(len(values))
        ]
    raise ValueError("trace extension must be .jsonl, .csv or .npy")
