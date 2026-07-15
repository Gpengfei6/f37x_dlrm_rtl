"""Deterministic synthetic inputs for structural and tooling validation only."""

import numpy as np

from model.dlrm.config import DLRMConfig


TRACE_MODES = (
    "deterministic",
    "high_duplicate",
    "low_duplicate",
    "balanced_channels",
    "skewed_channels",
    "hotspot_shift",
)


def _categorical_ids(config, sample_count, mode, rng, channel_count):
    ids = np.empty((sample_count, config.num_tables), dtype=np.int64)
    for table_id, table_size in enumerate(config.table_sizes):
        if mode == "high_duplicate":
            hot_size = max(1, min(4, table_size))
            ids[:, table_id] = rng.integers(0, hot_size, size=sample_count)
        elif mode == "low_duplicate":
            ids[:, table_id] = (
                np.arange(sample_count, dtype=np.int64) * (2 * table_id + 1) + table_id
            ) % table_size
        elif mode == "balanced_channels":
            ids[:, table_id] = (
                np.arange(sample_count, dtype=np.int64) * channel_count
                + np.arange(sample_count, dtype=np.int64) % channel_count
                + table_id * channel_count
            ) % table_size
        elif mode == "skewed_channels":
            channel = table_id % max(1, min(2, channel_count))
            base = rng.integers(0, max(1, (table_size + channel_count - 1) // channel_count), sample_count)
            ids[:, table_id] = (base * channel_count + channel) % table_size
        elif mode == "hotspot_shift":
            split = sample_count // 2
            first = rng.integers(0, max(1, min(4, table_size)), split)
            second_base = max(0, table_size - min(4, table_size))
            second = second_base + rng.integers(0, max(1, table_size - second_base), sample_count - split)
            ids[:, table_id] = np.concatenate((first, second))
        else:
            ids[:, table_id] = rng.integers(0, table_size, size=sample_count)
    return ids


def generate_synthetic_dataset(config, sample_count=None, mode="deterministic", channel_count=8):
    """Return deterministic dense, categorical and label arrays.

    Labels are generated from a fixed latent expression. They are useful for
    repeatability and metric plumbing, not for accuracy or novelty claims.
    """
    if not isinstance(config, DLRMConfig):
        config = DLRMConfig.from_dict(config)
    if mode not in TRACE_MODES:
        raise ValueError("unsupported synthetic mode: {}".format(mode))
    sample_count = config.synthetic_samples if sample_count is None else int(sample_count)
    if sample_count <= 0 or channel_count <= 0:
        raise ValueError("sample_count and channel_count must be positive")
    mode_seed = sum((index + 1) * ord(value) for index, value in enumerate(mode))
    rng = np.random.default_rng(config.seed + mode_seed)
    dense = rng.normal(0.0, 1.0, (sample_count, config.num_dense_features)).astype(config.dtype)
    categorical = _categorical_ids(config, sample_count, mode, rng, channel_count)
    dense_score = dense[:, : min(4, config.num_dense_features)].sum(axis=1)
    categorical_score = np.zeros(sample_count, dtype=np.float64)
    for table_id, table_size in enumerate(config.table_sizes):
        categorical_score += ((categorical[:, table_id] % 7) - 3) / max(1.0, table_size ** 0.5)
    labels = (dense_score + categorical_score >= np.median(dense_score + categorical_score)).astype(np.float32)
    return {
        "dense_features": dense,
        "categorical_ids": categorical,
        "labels": labels,
        "metadata": {
            "source": "synthetic",
            "mode": mode,
            "seed": config.seed,
            "sample_count": sample_count,
            "claim_boundary": "tooling validation only; not real Criteo evidence",
        },
    }
